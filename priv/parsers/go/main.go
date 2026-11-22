// Package main implements `metastatic-go-parser`, the Go AST bridge for
// Metastatic.
//
// The bridge reads a file path as its last argument and writes exactly one
// JSON object to stdout, matching the canonical envelope
// `Metastatic.Adapter.Bridge` decodes:
//
//	metastatic-go-parser parse    <file.go>    -> {"ok":true,"ast":{...}}
//	metastatic-go-parser unparse  <ast.json>   -> {"ok":true,"source":"..."}
//	metastatic-go-parser fmt      <file.go>    -> {"ok":true,"source":"..."}
//	metastatic-go-parser selftest [<dir>]      -> {"ok":true,"ast":{...}}
//
// Exit status is always 0 for a *reported* failure and non-zero only when the
// bridge itself could not run (bad usage, unreadable file). The Elixir side
// treats a non-zero exit as "the bridge could not run", so a parse failure
// must not use it.
//
// The bridge depends on nothing outside the standard library: `go/parser` and
// `go/ast` ship with the toolchain, and `go/format` is the reference printer.
// That is the Go analogue of the Rust bridge's `syn` + `prettyplease` pair,
// with one important difference — `go/format` is the *authoritative* printer,
// so a reified tree prints byte-identically to `gofmt`.
package main

import (
	"encoding/json"
	"fmt"
	"go/ast"
	"go/format"
	"go/parser"
	"go/scanner"
	"go/token"
	"io"
	"os"
	"strings"
)

func main() {
	os.Exit(run(os.Args[1:], os.Stdout, os.Stderr))
}

// ParseExprFrom does not run go/parser's resolver. A separate wrapped file
// supplies only Obj bindings, transferred by byte offset; the expression AST
// and its physical source positions remain the original, unwrapped ones.
func resolveExpressionObjects(expression ast.Expr, fset *token.FileSet, source string) {
	const prefix = "package p\nvar _ = "
	resolvedSet := token.NewFileSet()
	file, err := parser.ParseFile(resolvedSet, "bindings.go", prefix+source+"\n", 0)
	if err != nil {
		return
	}
	bindings := make(map[int]*ast.Object)
	ast.Inspect(file, func(node ast.Node) bool {
		if ident, ok := node.(*ast.Ident); ok && ident.Obj != nil {
			offset := resolvedSet.PositionFor(ident.Pos(), false).Offset - len(prefix)
			if offset >= 0 {
				bindings[offset] = ident.Obj
			}
		}
		return true
	})
	ast.Inspect(expression, func(node ast.Node) bool {
		if ident, ok := node.(*ast.Ident); ok {
			ident.Obj = bindings[fset.PositionFor(ident.Pos(), false).Offset]
		}
		return true
	})
}

// run executes one bridge invocation and returns the process exit status.
//
// It is separated from `main` so the whole protocol can be exercised from
// tests without spawning a process.
func run(args []string, stdout, stderr io.Writer) int {
	mode, inputArg, err := parseArgs(args)
	if err != nil {
		emit(stdout, stderr, ErrorResponse("UsageError", err.Error(), 0))
		return 2
	}

	// `selftest` takes no input. Short-circuit before reading so that a caller
	// which forgets to close stdin cannot hang the bridge.
	if mode == "selftest" {
		emit(stdout, stderr, selftest(inputArg))
		return 0
	}

	input, err := readInput(inputArg)
	if err != nil {
		emit(stdout, stderr, ErrorResponse("IOError", err.Error(), 0))
		return 1
	}

	var response Response

	switch mode {
	case "parse":
		response = parseSource(input)
	case "unparse":
		response = unparseSource(input)
	case "fmt":
		response = formatSource(input)
	default:
		response = ErrorResponse("UsageError", fmt.Sprintf("unknown mode %q", mode), 0)
	}

	emit(stdout, stderr, response)
	return 0
}

// parseArgs extracts the mode and the optional input path.
//
// Unknown flags and extra positional arguments are rejected. --filename is
// accepted for compatibility; wire spans always use physical input positions.
func parseArgs(args []string) (string, string, error) {
	mode, input := "parse", ""
	seenMode := false
	for i := 0; i < len(args); i++ {
		arg := args[i]
		if arg == "--filename" {
			if i+1 == len(args) {
				return "", "", fmt.Errorf("--filename requires a value")
			}
			i++
			continue
		}
		if strings.HasPrefix(arg, "--filename=") {
			continue
		}
		if strings.HasPrefix(arg, "-") {
			return "", "", fmt.Errorf("unknown option %q", arg)
		}
		if !seenMode && input == "" && (arg == "parse" || arg == "unparse" || arg == "fmt" || arg == "selftest") {
			mode, seenMode = arg, true
			continue
		}
		if input != "" {
			return "", "", fmt.Errorf("unexpected argument %q", arg)
		}
		input = arg
	}
	if input == "" && mode != "selftest" {
		return "", "", fmt.Errorf("missing input file path")
	}
	return mode, input, nil
}

// readInput reads the payload from a file path.
//
// The Elixir side always passes a real path: `Metastatic.Subprocess.run/4`
// writes the payload to a temp file and appends it as the last argument.
// Stdin is therefore never read — an absent path is a usage error rather than
// an implicit `-` — so a misconfigured caller fails fast instead of blocking
// on a pipe that will never be closed.
func readInput(path string) (string, error) {
	if path == "" {
		return "", fmt.Errorf("missing input file path (usage: metastatic-go-parser <mode> <file>)")
	}

	data, err := os.ReadFile(path)
	if err != nil {
		return "", fmt.Errorf("failed to read %q: %w", path, err)
	}

	return string(data), nil
}

// parseSource parses Go source into the M1 JSON tree.
//
// Whole files are tried first, then bare expressions through ParseExprFrom.
// Both entry points retain physical, unadjusted input positions.
func parseSource(source string) Response {
	fset := token.NewFileSet()

	file, err := parser.ParseFile(fset, "input.go", source, parser.ParseComments)
	if err == nil {
		converter := newConverter(fset, []byte(source))
		return respondWith(converter.file(file))
	}

	// Retry as a bare expression without synthetic wrapper offsets.
	if node, ok := parseExpression(source); ok {
		return respondWith(node)
	}

	return ErrorResponse("ParseError", err.Error(), errorLine(err))
}

// parseExpression parses `source` as a single Go expression.
//
// Returns `ok == false` when the source is not exactly one expression, so the
// caller can report the *file* error — the one that describes the input the
// caller actually meant to send.
func parseExpression(source string) (Node, bool) {
	if strings.TrimSpace(source) == "" {
		return Node{}, false
	}
	fset := token.NewFileSet()
	expression, err := parser.ParseExprFrom(fset, "input.go", source, parser.ParseComments)
	if err != nil {
		return Node{}, false
	}
	resolveExpressionObjects(expression, fset, source)
	converter := newConverter(fset, []byte(source))
	return converter.expressionWithComments(expression), true
}

// formatSource parses and re-prints, normalising formatting with `go/format`.
func formatSource(source string) Response {
	formatted, err := format.Source([]byte(source))
	if err != nil {
		return ErrorResponse("ParseError", err.Error(), 0)
	}

	return SourceResponse(string(formatted), map[string]any{"formatter": "go/format"})
}

// unparseSource reifies an M1 JSON tree back into Go source.
//
// Accepts either a `File` document (the usual case) or a single node, which is
// what `parse` returns for a bare expression such as `1 + 2`.
func unparseSource(payload string) Response {
	var document File

	if err := decodeJSON(payload, &document); err != nil {
		return ErrorResponse("JSONError", "invalid JSON: "+err.Error(), 0)
	}

	if document.Kind != "File" {
		// A bare node document: the JSON had a `kind` we do not recognise as
		// a file, so reify it as a single expression instead.
		var node Node
		if err := decodeJSON(payload, &node); err != nil {
			return ErrorResponse("JSONError", "invalid M1 node: "+err.Error(), 0)
		}

		source, err := expressionToSource(node)
		if err != nil {
			return ErrorResponse("ReifyError", err.Error(), 0)
		}

		return SourceResponse(source, map[string]any{"formatter": "go/format"})
	}

	source, err := fileToSource(document)
	if err != nil {
		return ErrorResponse("ReifyError", err.Error(), 0)
	}

	// `go/format` is the authority on Go layout, so the printed program is
	// exactly what `gofmt` would produce for the reified tree.
	formatted, err := format.Source([]byte(source))
	if err != nil {
		return ErrorResponse("FormatError", err.Error(), 0)
	}

	return SourceResponse(string(formatted), map[string]any{"formatter": "go/format"})
}

// respondWith serialises a document, reporting a serialisation failure as an
// error rather than emitting an empty payload.
func respondWith(document any) Response {
	if _, err := json.Marshal(document); err != nil {
		return ErrorResponse("SerializationError", "failed to serialise the AST: "+err.Error(), 0)
	}

	return ASTResponse(document)
}

// errorLine extracts the line number from a `go/scanner` error list, so the
// Elixir side can report `SyntaxError at line N: ...` like every other
// adapter.
func errorLine(err error) int {
	if list, ok := err.(scanner.ErrorList); ok && len(list) > 0 {
		return list[0].Pos.Line
	}
	return 0
}

// decodeJSON keeps large integers exact and rejects null, multiple documents,
// and malformed JSON rather than treating zero-valued structs as valid nodes.
func decodeJSON(payload string, target any) error {
	if strings.TrimSpace(payload) == "null" {
		return fmt.Errorf("expected object, got null")
	}
	decoder := json.NewDecoder(strings.NewReader(payload))
	decoder.UseNumber()
	if err := decoder.Decode(target); err != nil {
		return err
	}
	var trailing any
	if err := decoder.Decode(&trailing); err != io.EOF {
		if err != nil {
			return err
		}
		return fmt.Errorf("unexpected trailing JSON")
	}
	return nil
}

// emit writes a response as a single JSON line.
//
// A write failure cannot be reported through the protocol, so it is reported
// on stderr and swallowed — the process still exits 0 so the caller sees the
// empty stdout as a decode error rather than a crash.
func emit(stdout, stderr io.Writer, response Response) {
	encoded, err := json.Marshal(response)
	if err != nil {
		fmt.Fprintf(stderr, "metastatic-go-parser: failed to encode response: %v\n", err)
		return
	}

	if _, err := stdout.Write(append(encoded, '\n')); err != nil {
		fmt.Fprintf(stderr, "metastatic-go-parser: failed to write response: %v\n", err)
	}
}
