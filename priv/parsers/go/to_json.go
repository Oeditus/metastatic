// `go/ast` → M1 [`Node`] tree.
//
// Every construct the Elixir `ToMeta` module maps is converted here; anything
// else becomes an `Unsupported` node carrying its original source text, which
// the Elixir side maps to `:language_specific`. That escape hatch is what makes
// unsupported syntax explicit rather than silently discarding it. Reification
// of modelled nodes is structural; ordinary comments may move to safe syntax
// boundaries, and formatting is normalized by go/format.
package main

import (
	"encoding/base64"
	"encoding/json"
	"go/ast"
	"go/constant"
	"go/token"
	"strconv"
	"strings"
	"unicode/utf8"
)

// converter holds the state needed to convert a parsed file: the file set (for
// positions) and the source bytes (for the `Unsupported` escape hatch).
type converter struct {
	fset   *token.FileSet
	source []byte
}

// newConverter builds a converter for one parse.
func newConverter(fset *token.FileSet, source []byte) *converter {
	return &converter{fset: fset, source: source}
}

// span returns the position of a node, or UnknownSpan when it has none.
func (c *converter) span(node ast.Node) Span {
	if node == nil {
		return UnknownSpan
	}

	start := c.fset.PositionFor(node.Pos(), false)
	end := c.fset.PositionFor(node.End(), false)

	if !start.IsValid() {
		return UnknownSpan
	}

	return Span{Line: start.Line, Col: start.Column, EndLine: end.Line, EndCol: end.Column}
}

// text returns the original source text of a node, used for `Unsupported`.
func (c *converter) text(node ast.Node) string {
	if node == nil {
		return ""
	}

	start := c.fset.PositionFor(node.Pos(), false).Offset
	end := c.fset.PositionFor(node.End(), false).Offset

	if start < 0 || end > len(c.source) || start >= end {
		return ""
	}

	return string(c.source[start:end])
}

// unsupported wraps a node the converter does not model.
func (c *converter) unsupported(node ast.Node) Node {
	return Unsupported(c.span(node), c.text(node))
}

// file converts a parsed file into the M1 document.
func (c *converter) file(file *ast.File) File {
	pkg := ""
	if file.Name != nil {
		pkg = file.Name.Name
	}

	imports := make([]Node, 0, len(file.Imports))
	for _, spec := range file.Imports {
		imports = append(imports, c.importSpec(spec))
	}

	children := make([]Node, 0, len(file.Decls))
	for _, decl := range file.Decls {
		children = append(children, c.decl(decl))
	}

	result := NewFile(c.span(file), pkg, imports, children)
	c.preserveComments(file, &result)
	return result
}

// ----- Declarations -----

// decl converts a top-level declaration.
func (c *converter) decl(decl ast.Decl) Node {
	switch d := decl.(type) {
	case *ast.FuncDecl:
		return c.funcDecl(d)
	case *ast.GenDecl:
		return c.genDecl(d)
	default:
		return c.unsupported(decl)
	}
}

// funcDecl converts `func f(...) ... { ... }`.
//
// Parameters, results and the receiver are attached as `Field` nodes *before*
// the body so the Elixir side can split them positionally, exactly as the Rust
// bridge does for `syn::ItemFn`.
func (c *converter) funcDecl(fn *ast.FuncDecl) Node {
	node := NewNode("FuncDecl", c.span(fn))
	node.Extra = map[string]any{"has_body": fn.Body != nil}

	if fn.Name != nil {
		node.Name = fn.Name.Name
	}

	var children []Node

	if fn.Recv != nil {
		for _, field := range fn.Recv.List {
			children = append(children, c.field(field, "Receiver"))
		}
	}

	if fn.Type != nil {
		if fn.Type.TypeParams != nil {
			for _, field := range fn.Type.TypeParams.List {
				children = append(children, c.field(field, "TypeParam"))
			}
		}
		for _, field := range fn.Type.Params.List {
			children = append(children, c.field(field, "Param"))
		}

		if fn.Type.Results != nil {
			for _, field := range fn.Type.Results.List {
				children = append(children, c.field(field, "Result"))
			}
		}
	}

	if fn.Body != nil {
		for _, stmt := range fn.Body.List {
			children = append(children, c.stmt(stmt))
		}
	}

	node.Children = children
	return node
}

// genDecl converts `import`, `const`, `var` and `type` declarations.
func (c *converter) genDecl(decl *ast.GenDecl) Node {
	switch decl.Tok {
	case token.IMPORT:
		node := NewNode("ImportDecl", c.span(decl))
		node.Extra = map[string]any{"grouped": decl.Lparen.IsValid()}
		for _, spec := range decl.Specs {
			if importSpec, ok := spec.(*ast.ImportSpec); ok {
				node.Children = append(node.Children, c.importSpec(importSpec))
			}
		}
		return node

	case token.CONST, token.VAR:
		kind := "VarDecl"
		if decl.Tok == token.CONST {
			kind = "ConstDecl"
		}

		node := NewNode(kind, c.span(decl))
		node.Extra = map[string]any{"grouped": decl.Lparen.IsValid()}
		for _, spec := range decl.Specs {
			if valueSpec, ok := spec.(*ast.ValueSpec); ok {
				node.Children = append(node.Children, c.valueSpec(valueSpec, decl.Tok == token.CONST))
			}
		}
		return node

	case token.TYPE:
		node := NewNode("TypeDecl", c.span(decl))
		node.Extra = map[string]any{"grouped": decl.Lparen.IsValid()}
		for _, spec := range decl.Specs {
			if typeSpec, ok := spec.(*ast.TypeSpec); ok {
				node.Children = append(node.Children, c.typeSpec(typeSpec))
			}
		}
		return node

	default:
		return c.unsupported(decl)
	}
}

// importSpec converts one `import` spec.
func (c *converter) importSpec(spec *ast.ImportSpec) Node {
	node := NewNode("ImportSpec", c.span(spec))

	if spec.Path != nil {
		if path, err := strconv.Unquote(spec.Path.Value); err == nil {
			node.Name = path
		} else {
			node.Name = spec.Path.Value
		}
	}

	if spec.Name != nil {
		node.Extra = map[string]any{"alias": spec.Name.Name}
	}

	return node
}

// valueSpec converts one `var`/`const` spec.
func (c *converter) valueSpec(spec *ast.ValueSpec, isConst bool) Node {
	node := NewNode("ValueSpec", c.span(spec))
	node.Extra = map[string]any{"name_count": len(spec.Names)}

	if len(spec.Names) > 0 && spec.Names[0] != nil {
		node.Name = spec.Names[0].Name
	}

	// Every declared name is kept, so `var a, b int` does not lose `b`.
	names := make([]Node, 0, len(spec.Names))
	for _, name := range spec.Names {
		names = append(names, c.expr(name))
	}
	node.Children = names

	if spec.Type != nil {
		typeNode := c.expr(spec.Type)
		node.TypeNode = &typeNode
	}

	for _, value := range spec.Values {
		node.Children = append(node.Children, c.expr(value))
	}

	node.Mutable = !isConst
	return node
}

// typeSpec converts one `type` spec.
func (c *converter) typeSpec(spec *ast.TypeSpec) Node {
	node := NewNode("TypeSpec", c.span(spec))
	node.Extra = map[string]any{"alias": spec.Assign.IsValid()}

	if spec.Name != nil {
		node.Name = spec.Name.Name
	}

	if spec.Type != nil {
		typeNode := c.expr(spec.Type)
		node.TypeNode = &typeNode
	}

	// A type declaration may carry a whole method set (`type I interface {...}`),
	// whose members are converted as ordinary nodes.
	if spec.TypeParams != nil {
		for _, field := range spec.TypeParams.List {
			node.Children = append(node.Children, c.field(field, "TypeParam"))
		}
	}

	return node
}

// field converts a parameter, result, receiver or struct field list entry.
//
// `role` distinguishes the four positions, because Go spells them with the
// same `*ast.Field` type and the Elixir side needs to know which one it is.
func (c *converter) field(field *ast.Field, role string) Node {
	node := NewNode("Field", c.span(field))
	node.Extra = map[string]any{"role": role}

	if len(field.Names) > 0 && field.Names[0] != nil {
		node.Name = field.Names[0].Name
	} else if field.Type != nil {
		// An unnamed parameter (`func f(int)`) or an embedded field
		// (`struct { io.Reader }`) has no name; the type is the identity.
		node.Name = c.text(field.Type)
	}

	// Every declared name is preserved: `func f(a, b int)` declares two
	// parameters sharing one type, and collapsing them would lose `b`.
	for _, name := range field.Names {
		node.Children = append(node.Children, c.expr(name))
	}

	if field.Type != nil {
		typeNode := c.expr(field.Type)
		node.TypeNode = &typeNode

		// `...T` is a variadic parameter; the marker is load-bearing because
		// the printed form differs from a slice parameter.
		if _, ok := field.Type.(*ast.Ellipsis); ok {
			node.Variadic = true
		}
	}

	if field.Tag != nil {
		node.Extra["raw_tag"] = field.Tag.Value
		if tag, err := strconv.Unquote(field.Tag.Value); err == nil {
			node.Extra["tag"] = tag
		}
	}

	return node
}

// ----- Statements -----

// stmt converts a statement.
func (c *converter) stmt(stmt ast.Stmt) Node {
	switch s := stmt.(type) {
	case *ast.ExprStmt:
		node := c.expr(s.X)
		return node

	case *ast.AssignStmt:
		return c.assignStmt(s)

	case *ast.ReturnStmt:
		node := NewNode("ReturnStmt", c.span(s))
		for _, result := range s.Results {
			node.Children = append(node.Children, c.expr(result))
		}
		return node

	case *ast.IfStmt:
		return c.ifStmt(s)

	case *ast.ForStmt:
		return c.forStmt(s)

	case *ast.RangeStmt:
		return c.rangeStmt(s)

	case *ast.SwitchStmt:
		return c.switchStmt(s)

	case *ast.TypeSwitchStmt:
		return c.typeSwitchStmt(s)

	case *ast.SelectStmt:
		return c.selectStmt(s)

	case *ast.BlockStmt:
		return c.blockStmt(s)

	case *ast.DeferStmt:
		node := NewNode("DeferStmt", c.span(s))
		if s.Call != nil {
			node.Children = []Node{c.expr(s.Call)}
		}
		return node

	case *ast.GoStmt:
		node := NewNode("GoStmt", c.span(s))
		if s.Call != nil {
			node.Children = []Node{c.expr(s.Call)}
		}
		return node

	case *ast.LabeledStmt:
		node := NewNode("LabeledStmt", c.span(s))
		if s.Label != nil {
			node.Name = s.Label.Name
		}
		node.Children = []Node{c.stmt(s.Stmt)}
		return node

	case *ast.BranchStmt:
		return c.branchStmt(s)

	case *ast.IncDecStmt:
		node := NewNode("IncDecStmt", c.span(s))
		node.Name = s.Tok.String()
		node.Children = []Node{c.expr(s.X)}
		return node

	case *ast.DeclStmt:
		node := NewNode("DeclStmt", c.span(s))
		if s.Decl != nil {
			node.Children = []Node{c.decl(s.Decl)}
		}
		return node

	case *ast.SendStmt:
		node := NewNode("SendStmt", c.span(s))
		node.Children = []Node{c.expr(s.Chan), c.expr(s.Value)}
		return node

	case *ast.EmptyStmt:
		node := NewNode("EmptyStmt", c.span(s))
		node.Semi = !s.Implicit
		return node

	case *ast.CommClause:
		return c.commClause(s)

	case *ast.CaseClause:
		return c.caseClause(s)

	default:
		return c.unsupported(stmt)
	}
}

// assignStmt converts `x = y`, `x := y`, `x += y` and tuple forms.
func (c *converter) assignStmt(stmt *ast.AssignStmt) Node {
	node := NewNode("AssignStmt", c.span(stmt))
	node.Extra = map[string]any{"lhs_count": len(stmt.Lhs)}
	node.Name = stmt.Tok.String()

	// `:=` is a *definition*, `=` is an assignment. The distinction is
	// load-bearing: only the former introduces a binding.
	node.Mutable = stmt.Tok == token.DEFINE

	for _, lhs := range stmt.Lhs {
		node.Children = append(node.Children, c.expr(lhs))
	}

	for _, rhs := range stmt.Rhs {
		node.Children = append(node.Children, c.expr(rhs))
	}

	// A single-target definition keeps the target in `pattern` so the Elixir
	// side can emit a `:variable` rather than a tuple expression.
	if len(stmt.Lhs) == 1 {
		pattern := c.expr(stmt.Lhs[0])
		node.Pattern = &pattern
	}

	return node
}

// ifStmt converts `if [init;] cond { ... } [else ...]`.
func (c *converter) ifStmt(stmt *ast.IfStmt) Node {
	node := NewNode("IfStmt", c.span(stmt))
	node.Extra = map[string]any{"has_init": stmt.Init != nil, "has_else": stmt.Else != nil}

	if stmt.Init != nil {
		node.Children = append(node.Children, c.stmt(stmt.Init))
	}

	if stmt.Cond != nil {
		node.Children = append(node.Children, c.expr(stmt.Cond))
	}

	if stmt.Body != nil {
		node.Children = append(node.Children, c.blockStmt(stmt.Body))
	}

	if stmt.Else != nil {
		node.Children = append(node.Children, c.stmt(stmt.Else))
	}

	return node
}

// forStmt converts the three forms of `for` header.
func (c *converter) forStmt(stmt *ast.ForStmt) Node {
	node := NewNode("ForStmt", c.span(stmt))

	// Any of the three header slots may be absent, which Go spells as a nil
	// node; the Elixir side pads them so the MetaAST node stays conforming.
	if stmt.Init != nil {
		node.Children = append(node.Children, c.stmt(stmt.Init))
	} else {
		node.Children = append(node.Children, NewNode("Absent", UnknownSpan))
	}

	if stmt.Cond != nil {
		node.Children = append(node.Children, c.expr(stmt.Cond))
	} else {
		node.Children = append(node.Children, NewNode("Absent", UnknownSpan))
	}

	if stmt.Post != nil {
		node.Children = append(node.Children, c.stmt(stmt.Post))
	} else {
		node.Children = append(node.Children, NewNode("Absent", UnknownSpan))
	}

	if stmt.Body != nil {
		node.Children = append(node.Children, c.blockStmt(stmt.Body))
	}

	return node
}

// rangeStmt converts `for k, v := range xs { ... }`.
func (c *converter) rangeStmt(stmt *ast.RangeStmt) Node {
	node := NewNode("RangeStmt", c.span(stmt))
	node.Extra = map[string]any{"has_value": stmt.Value != nil}
	node.Mutable = stmt.Tok == token.DEFINE

	if stmt.Key != nil {
		key := c.expr(stmt.Key)
		node.Pattern = &key
	}

	if stmt.Value != nil {
		node.Children = append(node.Children, c.expr(stmt.Value))
	}

	if stmt.X != nil {
		node.Children = append(node.Children, c.expr(stmt.X))
	}

	if stmt.Body != nil {
		node.Children = append(node.Children, c.blockStmt(stmt.Body))
	}

	return node
}

// switchStmt converts `switch [init;] [tag] { cases }`.
func (c *converter) switchStmt(stmt *ast.SwitchStmt) Node {
	node := NewNode("SwitchStmt", c.span(stmt))
	node.Extra = map[string]any{"has_init": stmt.Init != nil, "has_tag": stmt.Tag != nil}

	if stmt.Init != nil {
		node.Children = append(node.Children, c.stmt(stmt.Init))
	}

	if stmt.Tag != nil {
		node.Children = append(node.Children, c.expr(stmt.Tag))
	}

	if stmt.Body != nil {
		for _, clause := range stmt.Body.List {
			if caseClause, ok := clause.(*ast.CaseClause); ok {
				node.Children = append(node.Children, c.caseClause(caseClause))
			}
		}
	}

	return node
}

// typeSwitchStmt converts `switch v := x.(type) { cases }`.
func (c *converter) typeSwitchStmt(stmt *ast.TypeSwitchStmt) Node {
	node := NewNode("TypeSwitchStmt", c.span(stmt))
	node.Extra = map[string]any{"has_init": stmt.Init != nil}

	if stmt.Init != nil {
		node.Children = append(node.Children, c.stmt(stmt.Init))
	}

	if stmt.Assign != nil {
		node.Children = append(node.Children, c.stmt(stmt.Assign))
	}

	if stmt.Body != nil {
		for _, clause := range stmt.Body.List {
			if caseClause, ok := clause.(*ast.CaseClause); ok {
				node.Children = append(node.Children, c.caseClause(caseClause))
			}
		}
	}

	return node
}

// selectStmt converts `select { comms }`.
func (c *converter) selectStmt(stmt *ast.SelectStmt) Node {
	node := NewNode("SelectStmt", c.span(stmt))

	if stmt.Body != nil {
		for _, clause := range stmt.Body.List {
			if commClause, ok := clause.(*ast.CommClause); ok {
				node.Children = append(node.Children, c.commClause(commClause))
			}
		}
	}

	return node
}

// commClause converts one `select` clause.
func (c *converter) commClause(clause *ast.CommClause) Node {
	node := NewNode("CommClause", c.span(clause))
	node.Extra = map[string]any{"has_comm": clause.Comm != nil}

	if clause.Comm != nil {
		node.Children = append(node.Children, c.stmt(clause.Comm))
	}

	for _, body := range clause.Body {
		node.Children = append(node.Children, c.stmt(body))
	}

	return node
}

// caseClause converts one `switch` case, including `default`.
func (c *converter) caseClause(clause *ast.CaseClause) Node {
	node := NewNode("CaseClause", c.span(clause))

	// An empty expression list is `default`, which has no AST node of its own.
	if len(clause.List) == 0 {
		node.Extra = map[string]any{"default": true}
	}

	for _, expr := range clause.List {
		node.Children = append(node.Children, c.expr(expr))
	}

	node.Pattern = &Node{Kind: "CaseBody", Span: UnknownSpan}

	var body []Node
	for _, stmt := range clause.Body {
		body = append(body, c.stmt(stmt))
	}
	node.Pattern.Children = body

	return node
}

// branchStmt converts `break`, `continue`, `goto` and `fallthrough`.
func (c *converter) branchStmt(stmt *ast.BranchStmt) Node {
	node := NewNode("BranchStmt", c.span(stmt))
	node.Name = stmt.Tok.String()

	if stmt.Label != nil {
		node.Extra = map[string]any{"label": stmt.Label.Name}
	}

	return node
}

// blockStmt converts `{ ... }`.
func (c *converter) blockStmt(block *ast.BlockStmt) Node {
	node := NewNode("BlockStmt", c.span(block))

	if block != nil {
		for _, stmt := range block.List {
			node.Children = append(node.Children, c.stmt(stmt))
		}
	}

	return node
}

// ----- Expressions -----

// expr converts an expression.
func (c *converter) expr(expr ast.Expr) Node {
	switch e := expr.(type) {
	case *ast.Ident:
		node := Node{Kind: "Ident", Span: c.span(e), Name: e.Name}
		// true, false and nil are predeclared identifiers, not reserved words.
		// Obj identifies locally/package-bound shadowing without inventing a
		// second resolver or serializing go/ast's cyclic object graph.
		if e.Obj != nil && (e.Name == "true" || e.Name == "false" || e.Name == "nil") {
			node.Extra = map[string]any{"bound": true}
		}
		return node

	case *ast.BasicLit:
		return c.basicLit(e)

	case *ast.BinaryExpr:
		node := NewNode("BinaryExpr", c.span(e))
		node.Name = e.Op.String()
		node.Children = []Node{c.expr(e.X), c.expr(e.Y)}
		return node

	case *ast.UnaryExpr:
		node := NewNode("UnaryExpr", c.span(e))
		node.Name = e.Op.String()
		node.Children = []Node{c.expr(e.X)}
		return node

	case *ast.StarExpr:
		node := NewNode("StarExpr", c.span(e))
		node.Pointer = true
		node.Children = []Node{c.expr(e.X)}
		return node

	case *ast.ParenExpr:
		node := NewNode("ParenExpr", c.span(e))
		node.Children = []Node{c.expr(e.X)}
		return node

	case *ast.CallExpr:
		return c.callExpr(e)

	case *ast.SelectorExpr:
		node := NewNode("SelectorExpr", c.span(e))
		if e.Sel != nil {
			node.Name = e.Sel.Name
		}
		node.Children = []Node{c.expr(e.X)}
		return node

	case *ast.IndexExpr:
		node := NewNode("IndexExpr", c.span(e))
		node.Children = []Node{c.expr(e.X), c.expr(e.Index)}
		return node

	case *ast.IndexListExpr:
		node := NewNode("IndexListExpr", c.span(e))
		node.Children = append(node.Children, c.expr(e.X))
		for _, index := range e.Indices {
			node.Children = append(node.Children, c.expr(index))
		}
		return node

	case *ast.SliceExpr:
		node := NewNode("SliceExpr", c.span(e))
		node.Children = []Node{c.expr(e.X)}
		for _, bound := range []ast.Expr{e.Low, e.High, e.Max} {
			if bound != nil {
				node.Children = append(node.Children, c.expr(bound))
			} else {
				node.Children = append(node.Children, NewNode("Absent", UnknownSpan))
			}
		}
		node.Extra = map[string]any{"slice3": e.Slice3}
		return node

	case *ast.TypeAssertExpr:
		node := NewNode("TypeAssertExpr", c.span(e))
		node.Children = []Node{c.expr(e.X)}
		// `x.(type)` outside a type switch has no type node; the marker keeps
		// the two forms distinguishable.
		if e.Type != nil {
			typeNode := c.expr(e.Type)
			node.TypeNode = &typeNode
		} else {
			node.Extra = map[string]any{"type_switch": true}
		}
		return node

	case *ast.CompositeLit:
		return c.compositeLit(e)

	case *ast.KeyValueExpr:
		node := NewNode("KeyValueExpr", c.span(e))
		node.Children = []Node{c.expr(e.Key), c.expr(e.Value)}
		return node

	case *ast.FuncLit:
		node := NewNode("FuncLit", c.span(e))
		node.Children = []Node{c.funcTypeChildren(e.Type), c.blockStmt(e.Body)}
		return node

	case *ast.ArrayType:
		node := NewNode("ArrayType", c.span(e))
		if e.Len != nil {
			node.Children = []Node{c.expr(e.Len)}
		} else {
			node.Children = []Node{NewNode("Absent", UnknownSpan)}
		}
		node.Children = append(node.Children, c.expr(e.Elt))
		return node

	case *ast.MapType:
		node := NewNode("MapType", c.span(e))
		node.Children = []Node{c.expr(e.Key), c.expr(e.Value)}
		return node

	case *ast.ChanType:
		node := NewNode("ChanType", c.span(e))
		node.Name = chanDirName(e.Dir)
		node.Children = []Node{c.expr(e.Value)}
		return node

	case *ast.StructType:
		node := NewNode("StructType", c.span(e))
		if e.Fields != nil {
			for _, field := range e.Fields.List {
				node.Children = append(node.Children, c.field(field, "StructField"))
			}
		}
		return node

	case *ast.InterfaceType:
		node := NewNode("InterfaceType", c.span(e))
		if e.Methods != nil {
			for _, field := range e.Methods.List {
				node.Children = append(node.Children, c.field(field, "InterfaceMethod"))
			}
		}
		return node

	case *ast.FuncType:
		return c.funcTypeChildren(e)

	case *ast.Ellipsis:
		node := NewNode("Ellipsis", c.span(e))
		node.Variadic = true
		if e.Elt != nil {
			node.Children = []Node{c.expr(e.Elt)}
		}
		return node
	default:
		return c.unsupported(expr)
	}
}

// basicLit converts a literal, normalising Go's lexical forms to JSON scalars.
func (c *converter) basicLit(lit *ast.BasicLit) Node {
	node := NewNode("BasicLit", c.span(lit))
	node.ValueType = strings.ToLower(lit.Kind.String())
	node.Extra = map[string]any{"raw": lit.Value}

	switch lit.Kind {
	case token.INT:
		if value, err := strconv.ParseInt(lit.Value, 0, 64); err == nil {
			node.Value = value
		} else if value, err := strconv.ParseUint(lit.Value, 0, 64); err == nil {
			node.Value = value
		} else {
			value := constant.MakeFromLiteral(lit.Value, token.INT, 0)
			if value.Kind() == constant.Int {
				node.Value = json.Number(value.ExactString())
			} else {
				node.Value = lit.Value
			}
		}

	case token.FLOAT:
		if value, err := strconv.ParseFloat(lit.Value, 64); err == nil {
			node.Value = value
		} else {
			node.Value = lit.Value
		}

	case token.STRING:
		if value, err := strconv.Unquote(lit.Value); err == nil {
			node.Value = value
			if !utf8.ValidString(value) {
				node.Extra["value_bytes_base64"] = base64.StdEncoding.EncodeToString([]byte(value))
			}
		} else {
			node.Value = lit.Value
		}

	case token.CHAR:
		if value, _, _, err := strconv.UnquoteChar(strings.Trim(lit.Value, "'"), '\''); err == nil {
			node.Value = string(value)
		} else {
			node.Value = lit.Value
		}

	default:
		node.Value = lit.Value
	}

	node.Extra["original_value"] = node.Value
	return node
}

// callExpr converts a call, including conversions and `xs...` splices.
func (c *converter) callExpr(call *ast.CallExpr) Node {
	node := NewNode("CallExpr", c.span(call))
	node.Variadic = call.Ellipsis.IsValid()

	node.Children = []Node{c.expr(call.Fun)}
	for _, arg := range call.Args {
		node.Children = append(node.Children, c.expr(arg))
	}

	return node
}

// compositeLit converts `T{...}`, `[]T{...}` and `map[K]V{...}`.
func (c *converter) compositeLit(lit *ast.CompositeLit) Node {
	node := NewNode("CompositeLit", c.span(lit))

	if lit.Type != nil {
		typeNode := c.expr(lit.Type)
		node.TypeNode = &typeNode
		node.ValueType = c.text(lit.Type)
	}

	for _, element := range lit.Elts {
		node.Children = append(node.Children, c.expr(element))
	}

	return node
}

// funcTypeChildren converts a function *type* into a `FuncType` node carrying
// its parameters and results as children.
func (c *converter) funcTypeChildren(fnType *ast.FuncType) Node {
	node := NewNode("FuncType", c.span(fnType))

	if fnType == nil {
		return node
	}

	if fnType.TypeParams != nil {
		for _, field := range fnType.TypeParams.List {
			node.Children = append(node.Children, c.field(field, "TypeParam"))
		}
	}

	if fnType.Params != nil {
		for _, field := range fnType.Params.List {
			node.Children = append(node.Children, c.field(field, "Param"))
		}
	}

	if fnType.Results != nil {
		for _, field := range fnType.Results.List {
			node.Children = append(node.Children, c.field(field, "Result"))
		}
	}

	return node
}

// chanDirName renders a channel direction as the source keyword, so the Elixir
// side can restore `chan`, `<-chan` and `chan<-` exactly.
func chanDirName(dir ast.ChanDir) string {
	switch dir {
	case ast.RECV:
		return "<-chan"
	case ast.SEND:
		return "chan<-"
	default:
		return "chan"
	}
}
