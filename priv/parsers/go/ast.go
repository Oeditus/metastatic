// Package main implements `metastatic-go-parser`, the Go AST bridge for
// Metastatic.
//
// The bridge is the Go analogue of `priv/parsers/rust/`: it parses Go source
// into a language-neutral JSON tree (M1) that `Metastatic.Adapters.Go.ToMeta`
// pattern-matches on, and reifies that tree back to gofmt-formatted source.
//
// This file defines the M1 wire format. It is deliberately a flat, tagged
// struct rather than a mirror of `go/ast`:
//
//   - every node carries a `kind` discriminant, so the Elixir side never has
//     to know Go's type names;
//   - every node carries a `span` (1-based line/column), so MetaAST nodes can
//     be given source positions;
//   - optional fields are omitted from the JSON rather than emitted as null,
//     which keeps payloads small and lets Elixir match on `Map.has_key?/2`.
//
// The shape is the same one `RUST_IMPL.md` §2 calls "M1 shape", so both
// adapters are readable with the same mental model.
package main

import "encoding/json"

// Span is a source position, 1-based on both axes, end-exclusive in columns.
//
// `go/token` reports 1-based lines and 1-based columns, so no normalisation is
// needed — unlike the Rust bridge, where `proc-macro2` columns are 0-based.
type Span struct {
	Line    int `json:"line"`
	Col     int `json:"col"`
	EndLine int `json:"end_line"`
	EndCol  int `json:"end_col"`
}

// UnknownSpan is the span used for synthesised nodes that have no source text
// to point at (for example a node rebuilt by `from_json`).
var UnknownSpan = Span{}

// Node is one M1 node.
//
// `Kind` is the discriminant the Elixir adapter matches on. Every other field
// is kind-specific and optional; `omitempty` keeps the JSON payload small and
// makes "absent" distinguishable from "empty".
type Node struct {
	// Kind is the Go AST node kind, e.g. "BinaryExpr", "FuncDecl", "Ident".
	Kind string `json:"kind"`
	// Span is the source position, or UnknownSpan.
	Span Span `json:"span"`
	// Name is the operator, identifier, selector, import path or declaration
	// name, depending on Kind.
	Name string `json:"name,omitempty"`
	// Value is the literal payload (a JSON scalar) for Kind == "BasicLit".
	Value any `json:"value,omitempty"`
	// ValueType is the literal subtype: "int", "float", "imag", "char" or
	// "string" for BasicLit; the underlying type name for CompositeLit.
	ValueType string `json:"value_type,omitempty"`
	// Children are the sub-nodes, in source order.
	Children []Node `json:"children,omitempty"`
	// Pattern is the binding pattern of a `:=`, `var`, `range` or `case`
	// clause.
	Pattern *Node `json:"pattern,omitempty"`
	// TypeNode is the declared type of a parameter, field, receiver, result
	// or type declaration.
	TypeNode *Node `json:"type_node,omitempty"`
	// Source preserves the original text of a construct the bridge does not
	// model as a node (Kind == "Unsupported").
	Source string `json:"source,omitempty"`
	// Semi records explicit empty statements. Ordinary separators are
	// regenerated structurally and normalized by go/format.
	Semi bool `json:"semi,omitempty"`
	// Mutable records a `var` declaration (as opposed to `:=`), which Go
	// treats differently in scoping rules.
	Mutable bool `json:"mutable,omitempty"`
	// Pointer records a pointer-shaped type or a pointer receiver.
	Pointer bool `json:"pointer,omitempty"`
	// Variadic records a `...T` parameter or a `xs...` call argument.
	Variadic bool `json:"variadic,omitempty"`
	// Extra carries kind-specific scalars that do not deserve a top-level
	// field (e.g. the tag of a struct field, the label of a branch).
	Extra map[string]any `json:"extra,omitempty"`
}

// NewNode builds a node of kind with a span and no children.
func NewNode(kind string, span Span) Node {
	return Node{Kind: kind, Span: span}
}

// WithChildren builds a node of kind carrying children.
func WithChildren(kind string, span Span, children []Node) Node {
	return Node{Kind: kind, Span: span, Children: children}
}

// Unsupported builds an opaque node carrying source text verbatim. Reification
// of all modelled kinds instead honors the current structural fields/children.
func Unsupported(span Span, source string) Node {
	return Node{Kind: "Unsupported", Span: span, Source: source}
}

// File is the M1 document: the root node of a parsed Go file.
//
// It is a Node with Kind "File" plus the package clause, which is not an
// ordinary statement and therefore has no place in the children list.
type File struct {
	Kind    string `json:"kind"`
	Span    Span   `json:"span"`
	Package string `json:"package,omitempty"`
	// Imports is a convenience index. Children ImportDecl nodes are authoritative;
	// Imports is used only when no ImportDecl appears in Children.
	Imports  []Node         `json:"imports,omitempty"`
	Children []Node         `json:"children,omitempty"`
	Extra    map[string]any `json:"extra,omitempty"`
}

// NewFile builds the document node.
func NewFile(span Span, pkg string, imports []Node, children []Node) File {
	return File{Kind: "File", Span: span, Package: pkg, Imports: imports, Children: children}
}

// Response is the single JSON object the bridge writes to stdout.
//
// A *reported* failure (bad syntax, bad JSON) is `{"ok": false, ...}` on exit
// status 0, because the Elixir side treats a non-zero exit as "the bridge
// could not run". Only usage errors and unreadable input exit non-zero.
type Response struct {
	OK     bool           `json:"ok"`
	AST    any            `json:"ast,omitempty"`
	Source string         `json:"source"`
	Meta   map[string]any `json:"meta,omitempty"`
	Error  *ResponseError `json:"error,omitempty"`
}

// ResponseError is the structured error payload.
type ResponseError struct {
	Type string `json:"type"`
	Msg  string `json:"msg"`
	Line int    `json:"line,omitempty"`
}

// ASTResponse reports a successful parse.
func ASTResponse(ast any) Response {
	return Response{OK: true, AST: ast}
}

// SourceResponse reports a successful print, with optional metadata.
func SourceResponse(source string, meta map[string]any) Response {
	return Response{OK: true, Source: source, Meta: meta}
}

// ErrorResponse reports a failure the caller can act on.
func ErrorResponse(kind, msg string, line int) Response {
	return Response{OK: false, Error: &ResponseError{Type: kind, Msg: msg, Line: line}}
}

// MarshalJSON keeps `span` present even when it is the zero value, so the
// Elixir side can always read `node["span"]` without a nil check.
func (n Node) MarshalJSON() ([]byte, error) {
	type alias Node
	return json.Marshal(struct {
		alias
		Span Span `json:"span"`
	}{alias: alias(n), Span: n.Span})
}
