package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"go/format"
	"go/parser"
	"go/token"
	"math/rand"
	"os"
	"path/filepath"
	"reflect"
	"runtime"
	"sort"
	"strings"
	"testing"
	"time"
)

func roundTrip(t *testing.T, source string) string {
	t.Helper()
	parsed := parseSource(source)
	if !parsed.OK {
		t.Fatalf("parse %q: %+v", source, parsed.Error)
	}
	payload, err := json.Marshal(parsed.AST)
	if err != nil {
		t.Fatal(err)
	}
	printed := unparseSource(string(payload))
	if !printed.OK {
		t.Fatalf("unparse %s: %+v\n%s", source, printed.Error, payload)
	}
	if reparsed := parseSource(printed.Source); !reparsed.OK {
		t.Fatalf("reparse: %+v\n%s", reparsed.Error, printed.Source)
	} else {
		assertEquivalentM1(t, parsed.AST, reparsed.AST)
	}
	again := parseSource(printed.Source)
	payload, err = json.Marshal(again.AST)
	if err != nil {
		t.Fatal(err)
	}
	second := unparseSource(string(payload))
	if !second.OK || second.Source != printed.Source {
		t.Fatalf("unstable reification:\n%s\nthen:\n%s (%+v)", printed.Source, second.Source, second.Error)
	}
	return printed.Source
}

func TestLargeGeneratedSourceCommentScaling(t *testing.T) {
	const declarations = 12000
	var source strings.Builder
	source.WriteString("package generated\n")
	for i := 0; i < declarations; i++ {
		fmt.Fprintf(&source, "// item %d\nvar Value%d = %d\n", i, i, i)
	}
	start := time.Now()
	parsed := parseSource(source.String())
	if !parsed.OK {
		t.Fatalf("%+v", parsed.Error)
	}
	if elapsed := time.Since(start); elapsed > 10*time.Second {
		t.Fatalf("comment indexing regressed: %s for %d declarations", elapsed, declarations)
	}
	file := parsed.AST.(File)
	if len(file.Children) != declarations {
		t.Fatalf("lost declarations: %d", len(file.Children))
	}
	for i, node := range file.Children {
		comments, _ := node.Extra["before_comments"].([]string)
		if len(comments) != 1 || comments[0] != fmt.Sprintf("// item %d", i) {
			t.Fatalf("comment %d attached incorrectly: %+v", i, node.Extra)
		}
	}
}

func TestCommentIndexMatchesLinearQueries(t *testing.T) {
	random := rand.New(rand.NewSource(42))
	var nodes []*Node
	for i := 0; i < 400; i++ {
		line, col := 1+random.Intn(100), 1+random.Intn(30)
		nodes = append(nodes, &Node{Span: Span{Line: line, Col: col, EndLine: line + random.Intn(15), EndCol: col + random.Intn(10)}})
	}
	index := newCommentIndex(nodes)
	for i := 0; i < 2000; i++ {
		line, col := 1+random.Intn(100), 1+random.Intn(30)
		span := Span{Line: line, Col: col, EndLine: line + random.Intn(3), EndCol: col + random.Intn(5)}
		var containing, following, preceding *Node
		for _, node := range nodes {
			s := node.Span
			if posLE(s.Line, s.Col, span.Line, span.Col) && posLE(span.EndLine, span.EndCol, s.EndLine, s.EndCol) {
				if containing == nil || spanSize(s) < spanSize(containing.Span) {
					containing = node
				}
			}
			if posLE(span.EndLine, span.EndCol, s.Line, s.Col) {
				if following == nil || posLE(s.Line, s.Col, following.Span.Line, following.Span.Col) {
					following = node
				}
			}
			if s.EndLine == span.Line && s.EndCol <= span.Col {
				if preceding == nil || posLE(preceding.Span.EndLine, preceding.Span.EndCol, s.EndLine, s.EndCol) {
					preceding = node
				}
			}
		}
		a, b, c := index.boundaries(span)
		if a != containing || b != following || c != preceding {
			t.Fatalf("indexed query %d differs from linear reference at %+v", i, span)
		}
	}
}

func TestShadowedPredeclaredIdentifiers(t *testing.T) {
	source := "package p\nvar true = 1\nvar packageUse = true\nfunc f(false bool) bool { nil := false; _ = nil; return false }\n"
	roundTrip(t, source)
	file := parseSource(source).AST.(File)
	packageUse := file.Children[1].Children[0].Children[1]
	if packageUse.Name != "true" || !flag(packageUse, "bound") {
		t.Fatalf("package binding lost: %+v", packageUse)
	}
	fn := file.Children[2]
	parameter := fn.Children[0].Children[0]
	if parameter.Name != "false" || !flag(parameter, "bound") {
		t.Fatalf("parameter binding lost: %+v", parameter)
	}
	assignment := fn.Children[2]
	if !flag(assignment.Children[0], "bound") || !flag(assignment.Children[1], "bound") {
		t.Fatalf("local nil/parameter false binding lost: %+v", assignment)
	}
	localSource := "package p\nfunc f(){true := true; _ = true; nil := 1; _ = nil}"
	roundTrip(t, localSource)
	localFile := parseSource(localSource).AST.(File)
	statements := localFile.Children[0].Children
	if !flag(statements[0].Children[0], "bound") || flag(statements[0].Children[1], "bound") || !flag(statements[1].Children[1], "bound") {
		t.Fatalf("short-declaration RHS must remain predeclared; later reference bound: %+v", statements)
	}
	if !flag(statements[2].Children[0], "bound") || !flag(statements[3].Children[1], "bound") {
		t.Fatalf("nil shadowing lost: %+v", statements)
	}
	expression := parseSource("func(true bool) bool { return true }").AST.(Node)
	if !flag(expression.Children[0].Children[0].Children[0], "bound") ||
		!flag(expression.Children[1].Children[0].Children[0], "bound") {
		t.Fatalf("bare expression parameter shadowing lost: %+v", expression)
	}
}

func TestIndentedLineDirectiveExamplesRemainOrdinaryComments(t *testing.T) {
	for _, source := range []string{
		"package p\nfunc f(){\n //line filename:line:col\nreturn\n}\n",
		"package p\n //line filename:line:col\nvar x int\n",
		"func() {\n //line filename:line:col\nreturn\n}",
	} {
		got := roundTrip(t, source)
		if !strings.Contains(got, "// line filename:line:col") {
			t.Fatalf("prose directive not protected:\n%s", got)
		}
	}
}

func assertEquivalentM1(t *testing.T, before, after any) {
	t.Helper()
	normalize := func(value any) any {
		encoded, err := json.Marshal(value)
		if err != nil {
			t.Fatal(err)
		}
		var decoded any
		if err := decodeJSON(string(encoded), &decoded); err != nil {
			t.Fatal(err)
		}
		return normalizedM1(decoded)
	}
	a, b := normalize(before), normalize(after)
	if !reflect.DeepEqual(a, b) {
		left, _ := json.Marshal(a)
		right, _ := json.Marshal(b)
		t.Fatalf("M1 semantics changed:\nbefore: %s\nafter: %s", left, right)
	}
}

func normalizedM1(value any) any {
	switch value := value.(type) {
	case map[string]any:
		result := make(map[string]any)
		for key, child := range value {
			switch key {
			case "span", "before_comments", "after_comments", "package_comments", "raw", "raw_tag", "original_value", "semi":
				continue
			}
			// These fields duplicate type_node as original source spelling.
			if key == "value_type" && value["kind"] == "CompositeLit" && value["type_node"] != nil {
				continue
			}
			if key == "name" && value["kind"] == "Field" && value["children"] == nil && value["type_node"] != nil {
				continue
			}
			if key == "children" && value["kind"] != "LabeledStmt" {
				// go/format removes standalone no-op semicolons, but the
				// EmptyStmt target of a label remains structurally significant.
				if nodes, ok := child.([]any); ok {
					filtered := make([]any, 0, len(nodes))
					for _, node := range nodes {
						if object, ok := node.(map[string]any); ok && object["kind"] == "EmptyStmt" {
							continue
						}
						filtered = append(filtered, node)
					}
					child = filtered
				}
			}
			normalized := normalizedM1(child)
			// go/format sorts imports. Preserve each complete spec (including
			// aliases), but compare those semantically unordered lists as sets.
			if key == "imports" || key == "children" && value["kind"] == "ImportDecl" {
				if nodes, ok := normalized.([]any); ok {
					sort.Slice(nodes, func(i, j int) bool {
						a, _ := json.Marshal(nodes[i])
						b, _ := json.Marshal(nodes[j])
						return string(a) < string(b)
					})
				}
			}
			if children, ok := normalized.([]any); ok && len(children) == 0 && key == "children" {
				continue
			}
			if object, ok := normalized.(map[string]any); ok && len(object) == 0 && key == "extra" {
				continue
			}
			result[key] = normalized
		}
		return result
	case []any:
		result := make([]any, 0, len(value))
		for _, child := range value {
			result = append(result, normalizedM1(child))
		}
		return result
	default:
		return value
	}
}

func TestBareExpressionCommentsSurviveEdits(t *testing.T) {
	for _, source := range []string{
		"// leading\n1 + 2 // trailing",
		"1 /* between operands */ + 2",
		"f(/* argument */ 1, 2 /* other */)",
		"func() int {\n// body\nreturn 1\n}",
		"\"// not a comment\" /* real comment */",
		"func() int {\n//line generated.go:123\nreturn 1\n}",
	} {
		t.Run(source, func(t *testing.T) {
			got := roundTrip(t, source)
			node := parseSource(source).AST.(Node)
			var comments []string
			if values, ok := node.Extra["before_comments"].([]string); ok {
				comments = values
			}
			for _, comment := range comments {
				if strings.Count(got, comment) != 1 {
					t.Fatalf("comment duplicated/lost: %q\n%s", comment, got)
				}
			}
			if strings.Contains(source, "//line") && !strings.Contains(got, "{\n//line generated.go:123\n") {
				t.Fatalf("nested directive moved:\n%s", got)
			}
		})
	}
	node := parseSource("1 /* retained */ + 2 // tail").AST.(Node)
	node.Children[1].Value = json.Number("9")
	payload, _ := json.Marshal(node)
	printed := unparseSource(string(payload))
	if !printed.OK || !strings.Contains(printed.Source, "1 + 9") ||
		strings.Count(printed.Source, "/* retained */") != 1 ||
		strings.Count(printed.Source, "// tail") != 1 {
		t.Fatalf("%+v", printed)
	}
	roundTrip(t, printed.Source)
}

func TestHeaderCommentsStayOutOfSemicolonBoundaries(t *testing.T) {
	roundTrip(t, "package p\nfunc f(){ if x := f(); /* header */ x != nil {} ; switch x:=f(); /* comment */ { default: _=x }; for i:=0; /* cond */ i<3; i++ {} }")
}

func TestArbitraryByteMutation(t *testing.T) {
	source := `{"kind":"BasicLit","value_type":"string","value":"","extra":{"value_bytes_base64":"/wA="}}`
	printed := unparseSource(source)
	if !printed.OK || printed.Source != `"\xff\x00"` {
		t.Fatalf("%+v", printed)
	}
	for _, payload := range []string{
		`{"kind":"BasicLit","value_type":"string","extra":{"value_bytes_base64":"!"}}`,
		`{"kind":"BasicLit","value_type":"string","extra":{"value_bytes_base64":42}}`,
	} {
		if response := unparseSource(payload); response.OK {
			t.Fatalf("expected base64 error: %+v", response)
		}
	}
}

func TestExpressionRoundTrips(t *testing.T) {
	sources := []string{
		"0", "1", "0xff", "0b1010_0011", "0o755", "0777",
		"18446744073709551616", "0xffffffffffffffffffffffffffffffffffff",
		"9007199254740993", "1.25", "1e1000", "0x1.fp+10", "2.5i",
		"'界'", "'\\n'", "\"hello\\nworld\"", "`raw\nstring`", "\"\\xff\\x00\"",
		"x", "true", "false", "nil", "1 + 2 * 3", "(1 + 2) * 3",
		"a - (b - c)", "a / (b * c)", "a || b && c", "a &^ b", "a << 3",
		"!x", "-(-x)", "+(+x)", "^x", "&x", "*p", "<-ch",
		"& &x", "& ^x", "+ +x", "- -x", "<- <-ch",
		"f()", "f(x, y)", "f(xs...)", "obj.Method(x)", "(*p).Field",
		"f(0 ...)", "f(1.5 ...)",
		"xs[0]", "f[int](x)", "f[int,string](x)", "xs[:]", "xs[1:]",
		"xs[:2]", "xs[1:2:3]", "x.(T)", "[]int{1, 2}",
		"map[string]int{\"a\":1}", "[...]int{1,2}", "[][]int{{1,2},{3}}",
		"struct{ X int `json:\"x\"` }{X:1}", "func(x int) int { return x + 1 }",
		"func() {}",
	}
	for _, source := range sources {
		t.Run(source, func(t *testing.T) {
			got := roundTrip(t, source)
			if strings.HasPrefix(source, "func") {
				return
			}
			want, err := format.Source([]byte(source))
			if err != nil {
				t.Fatal(err)
			}
			if got != strings.TrimSpace(string(want)) {
				t.Fatalf("got %q, want %q", got, strings.TrimSpace(string(want)))
			}
		})
	}
}

func TestFileSyntaxRoundTrips(t *testing.T) {
	sources := []string{
		`package p`,
		`package p; import "fmt"; func f() { fmt.Println("hello") }`,
		`package p; import ( f "fmt"; . "math"; _ "net/http" )`,
		`package p; const ( A = iota; B; C, D = 3, 4 ); var a,b int; var c,d = 1,2`,
		`package p; type Alias = int; type Box[T any] struct { Value T }; func Id[T any](x T) T { return x }`,
		`package p; type Box[T any] struct { Value T }; func (b *Box[T]) Get() T { return b.Value }`,
		`package p; type I interface { ~int | ~string; M(a,b int) (x int, err error) }; type F func(a,b int) (int,error)`,
		`package p; type I interface { func(); func(P); M() }`,
		`package p; func f(a,b int, xs ...string) (x,y int) { return a,b }`,
		`package p; func external(x int) int`,
		`package p; func f() { var x int; const C = 1; type T int; x=1; a,b := 1,2; a,b=b,a; x+=a; x++; x--; return }`,
		`package p; func f() { if x := f(); x != nil { f() } else if true { f() } else { f() } }`,
		`package p; func f() { for {}; for true {}; for i:=0;i<10;i++ {}; for ;true; {}; for i=0;;i++ {} }`,
		`package p; func f() { for range xs {}; for k := range xs {}; for k,v := range xs {}; for k,v = range xs {}; for range 10 {} }`,
		`package p; func f() { switch {}; switch x {}; switch x:=f();x {case 1,2: f(); default: return}; switch {case true: f()} }`,
		`package p; func f() { switch x.(type) {case int,string: return; default: f()}; switch y:=f();x:=y.(type) {case int: _=x} }`,
		`package p; func f() { select {}; select {case ch<-x: f(); case x:=<-ch: _=x; default: return} }`,
		`package p; func f() { defer f(); go f(); L: for {break L}; goto L; for {continue}; switch {case true: fallthrough; default: return} }`,
		`package p; type S struct { X,Y int; *Other; F func(int) error; C <-chan int; D chan<- int; E chan int }`,
		`package p; func f(){ ; {} }`,
		`package p; func f(){ goto Done; Done:; }`,
	}
	for _, source := range sources {
		t.Run(source, func(t *testing.T) { roundTrip(t, source) })
	}
}

func TestCurrentChildrenWin(t *testing.T) {
	parsed := parseSource("package p\nfunc f() int { return 0xff }\n")
	file := parsed.AST.(File)
	file.Children[0].Name = "changed"
	file.Children[0].Children[1].Children[0].Value = json.Number("42")
	payload, _ := json.Marshal(file)
	printed := unparseSource(string(payload))
	if !printed.OK || !strings.Contains(printed.Source, "func changed() int") || !strings.Contains(printed.Source, "return 42") || strings.Contains(printed.Source, "0xff") {
		t.Fatalf("%+v", printed)
	}
}

func TestCommentsDirectivesAndCgo(t *testing.T) {
	source := "//go:build linux\n\n// Package p tests comments.\npackage p\n\n/*\n#include <stdlib.h>\n*/\nimport \"C\"\n\n// Value documents Value.\nvar Value = 1 // inline\n\n//go:noinline\nfunc f() int {\n // body\n return 1 /* inner */ + 2\n}\n"
	got := roundTrip(t, source)
	for _, comment := range []string{"//go:build linux", "// Package p", "#include <stdlib.h>", "// Value documents", "// inline", "//go:noinline", "// body", "/* inner */"} {
		if strings.Count(got, comment) != 1 {
			t.Fatalf("comment %q missing/duplicated:\n%s", comment, got)
		}
	}
	if !strings.Contains(got, "*/\nimport \"C\"") || !strings.Contains(got, "//go:noinline\nfunc f") {
		t.Fatalf("directive adjacency lost:\n%s", got)
	}
	if !strings.HasPrefix(got, "//go:build linux\n\n") {
		t.Fatalf("build constraint placement:\n%s", got)
	}
}

func TestLineDirectivePreservesRawUnsupportedText(t *testing.T) {
	source := "package p\n//line generated.go:300\nfunc f() int { return 1 }\n"
	got := roundTrip(t, source)
	if !strings.Contains(got, "//line generated.go:300") {
		t.Fatal(got)
	}
}

func TestImportsNotDuplicated(t *testing.T) {
	got := roundTrip(t, "package p\nimport \"fmt\"\nfunc f(){fmt.Println(1)}")
	if strings.Count(got, "\"fmt\"") != 1 {
		t.Fatal(got)
	}
	printed := unparseSource(`{"kind":"File","package":"p","imports":[{"kind":"ImportSpec","name":"fmt"}]}`)
	if !printed.OK || strings.Count(printed.Source, "\"fmt\"") != 1 {
		t.Fatalf("%+v", printed)
	}
}

func TestMalformedPayloadsReturnErrors(t *testing.T) {
	payloads := []string{
		"", "{", "null", "[]", "42", `"hello"`, "{}",
		`{"kind":"Unknown"}`, `{"kind":"BinaryExpr","name":"+"}`,
		`{"kind":"CallExpr"}`, `{"kind":"File","package":"bad-name"}`,
		`{"kind":"Ident","name":"x"} {}`, `{"kind":"Unsupported","source":""}`,
		`{"kind":"File","package":"p","children":[{"kind":"AssignStmt","name":"="}]}`,
		`{"kind":"File","package":"p","children":[{"kind":"VarDecl","children":[{"kind":"ValueSpec","extra":{"name_count":-1}}]}]}`,
		`{"kind":"File","package":"p","children":[{"kind":"FuncDecl","name":"f","children":[{"kind":"AssignStmt","name":"=","children":[],"extra":{"lhs_count":1e1000}}]}]}`,
		`{"kind":"BasicLit","value_type":"int","value":"f()"}`,
		`{"kind":"BasicLit","value_type":"char","value":""}`,
	}
	for _, payload := range payloads {
		t.Run(payload, func(t *testing.T) {
			response := unparseSource(payload)
			if response.OK || response.Error == nil {
				t.Fatalf("expected structured error: %+v", response)
			}
		})
	}
}

func TestProtocol(t *testing.T) {
	directory := t.TempDir()
	empty := filepath.Join(directory, "empty.go")
	if err := os.WriteFile(empty, nil, 0600); err != nil {
		t.Fatal(err)
	}
	var emptyStdout, emptyStderr bytes.Buffer
	if code := run([]string{"fmt", empty}, &emptyStdout, &emptyStderr); code != 0 {
		t.Fatalf("empty fmt exit %d: %s", code, emptyStderr.String())
	}
	var emptyResponse map[string]any
	if err := json.Unmarshal(emptyStdout.Bytes(), &emptyResponse); err != nil {
		t.Fatal(err)
	}
	if source, exists := emptyResponse["source"]; !exists || source != "" || emptyResponse["ok"] != true {
		t.Fatalf("empty source payload lost: %s", emptyStdout.String())
	}
	if err := os.Remove(empty); err != nil {
		t.Fatal(err)
	}
	source := filepath.Join(directory, "input.go")
	if err := os.WriteFile(source, []byte("package p\nvar x=1"), 0600); err != nil {
		t.Fatal(err)
	}
	for _, mode := range []string{"parse", "fmt", "selftest"} {
		args := []string{mode}
		if mode != "selftest" {
			args = append(args, source)
		}
		var stdout, stderr bytes.Buffer
		if code := run(args, &stdout, &stderr); code != 0 {
			t.Fatalf("%s exit %d: %s", mode, code, stderr.String())
		}
		var response Response
		if err := json.Unmarshal(stdout.Bytes(), &response); err != nil || !response.OK {
			t.Fatalf("%s: %s %v", mode, stdout.String(), err)
		}
	}
	for _, args := range [][]string{nil, {"parse"}, {"parse", source, source}, {"--unknown", source}, {"--filename"}, {"parse", "--bad"}} {
		var stdout, stderr bytes.Buffer
		if run(args, &stdout, &stderr) != 2 {
			t.Fatalf("expected usage error for %v", args)
		}
		var response Response
		if err := json.Unmarshal(stdout.Bytes(), &response); err != nil || response.Error.Type != "UsageError" {
			t.Fatalf("%s", stdout.String())
		}
	}
	var stdout, stderr bytes.Buffer
	if run([]string{"parse", filepath.Join(directory, "absent")}, &stdout, &stderr) != 1 {
		t.Fatal("expected IO error")
	}
	if result := selftest(directory); !result.OK {
		t.Fatalf("%+v", result.Error)
	}
	if result := selftest(filepath.Join(directory, "absent")); result.OK {
		t.Fatal("expected selftest path error")
	}
	if result := parseSource("package p\nfunc {"); result.OK || result.Error.Line != 2 {
		t.Fatalf("%+v", result)
	}
}

func TestLiteralMutationAndExactIntegers(t *testing.T) {
	node := parseSource("9007199254740993").AST.(Node)
	payload, _ := json.Marshal(node)
	if !strings.Contains(string(payload), `"value":9007199254740993`) {
		t.Fatal(string(payload))
	}
	if got := unparseSource(string(payload)); !got.OK || got.Source != "9007199254740993" {
		t.Fatalf("%+v", got)
	}
	node.Value = json.Number("9007199254740995")
	payload, _ = json.Marshal(node)
	if got := unparseSource(string(payload)); !got.OK || got.Source != "9007199254740995" {
		t.Fatalf("%+v", got)
	}
	node = parseSource(`"\xff"`).AST.(Node)
	node.Value = "edited"
	delete(node.Extra, "value_bytes_base64")
	payload, _ = json.Marshal(node)
	if got := unparseSource(string(payload)); !got.OK || got.Source != `"edited"` {
		t.Fatalf("%+v", got)
	}
}

func TestExpressionSpansAndUnsupportedEscape(t *testing.T) {
	node := parseSource("\n  x + 1").AST.(Node)
	if node.Span.Line != 2 || node.Span.Col != 3 {
		t.Fatalf("%+v", node.Span)
	}
	printed := unparseSource(`{"kind":"Unsupported","source":"f(1)"}`)
	if !printed.OK || printed.Source != "f(1)" {
		t.Fatalf("%+v", printed)
	}
	if _, err := parser.ParseFile(token.NewFileSet(), "", "package p\n"+printed.Source, 0); err == nil {
		t.Fatal("sanity check expected declaration error")
	}
}

func FuzzUnparseNeverPanics(f *testing.F) {
	for _, seed := range []string{`{}`, `null`, `{"kind":"BinaryExpr"}`, `{"kind":"File","package":"p"}`} {
		f.Add(seed)
	}
	f.Fuzz(func(t *testing.T, source string) { _ = unparseSource(source) })
}

func TestStandardLibraryCorpus(t *testing.T) {
	if os.Getenv("GO_BRIDGE_CORPUS") == "" {
		t.Skip("set GO_BRIDGE_CORPUS=1 for standard-library corpus audit")
	}
	for _, directory := range []string{"encoding/json", "go/parser"} {
		root := filepath.Join(runtime.GOROOT(), "src", directory)
		err := filepath.WalkDir(root, func(path string, entry os.DirEntry, err error) error {
			if err != nil {
				return err
			}
			if entry.IsDir() || !strings.HasSuffix(path, ".go") || strings.Contains(path, "/testdata/") {
				return nil
			}
			t.Run(path, func(t *testing.T) {
				source, err := os.ReadFile(path)
				if err != nil {
					t.Fatal(err)
				}
				parsed := parseSource(string(source))
				if !parsed.OK {
					t.Fatalf("%+v", parsed.Error)
				}
				file := parsed.AST.(File)
				reified, err := fileToSource(file)
				if err != nil {
					t.Fatal(err)
				}
				formatted, err := format.Source([]byte(reified))
				if err != nil {
					lines := strings.Split(reified, "\n")
					_, parseErr := parser.ParseFile(token.NewFileSet(), "", reified, 0)
					line := errorLine(parseErr)
					start := line - 3
					if start < 0 {
						start = 0
					}
					end := line + 3
					if end > len(lines) {
						end = len(lines)
					}
					t.Fatalf("%v\n%s", err, strings.Join(lines[start:end], "\n"))
				}
				reparsed := parseSource(string(formatted))
				if !reparsed.OK {
					t.Fatalf("reparse: %+v", reparsed.Error)
				}
				assertEquivalentM1(t, parsed.AST, reparsed.AST)
			})
			return nil
		})
		if err != nil {
			t.Fatal(err)
		}
	}
}
