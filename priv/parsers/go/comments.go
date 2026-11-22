package main

import (
	"go/ast"
	"go/scanner"
	"go/token"
	"strings"
)

// expressionWithComments hoists ordinary expression comments to the root
// boundary so edits cannot splice a line comment between an operator and its
// operand. Directives instead retain normal statement/declaration attachment,
// including inside function literals; they must not migrate to another entity.
func (c *converter) expressionWithComments(expression ast.Expr) Node {
	node := c.expr(expression)
	var lexical scanner.Scanner
	lexical.Init(c.fset.File(expression.Pos()), c.source, nil, scanner.ScanComments)
	var ordinary []string
	var directives []*ast.CommentGroup
	for {
		position, kind, text := lexical.Scan()
		if kind == token.EOF {
			break
		}
		if kind != token.COMMENT {
			continue
		}
		if strings.HasPrefix(text, "//line ") && c.fset.PositionFor(position, false).Column != 1 {
			text = "// line " + strings.TrimPrefix(text, "//line ")
		}
		if strings.HasPrefix(text, "//go:") || strings.HasPrefix(text, "//line ") || strings.HasPrefix(text, "/*line ") {
			directives = append(directives, &ast.CommentGroup{List: []*ast.Comment{{Slash: position, Text: text}}})
		} else {
			ordinary = append(ordinary, text)
		}
	}
	if len(directives) > 0 {
		document := File{Span: node.Span, Children: []Node{node}}
		c.preserveComments(&ast.File{Comments: directives}, &document)
		node = document.Children[0]
		for _, key := range []string{"before_comments", "package_comments", "after_comments"} {
			if comments, ok := document.Extra[key].([]string); ok {
				if node.Extra == nil {
					node.Extra = make(map[string]any)
				}
				for _, comment := range comments {
					appendComment(node.Extra, "before_comments", comment)
				}
			}
		}
	}
	if len(ordinary) > 0 {
		if node.Extra == nil {
			node.Extra = make(map[string]any)
		}
		for _, comment := range ordinary {
			appendComment(node.Extra, "before_comments", comment)
		}
	}
	return node
}

// safeCommentGroup keeps genuine directives intact, but protects indented
// prose examples that only resemble //line directives. Relocation and gofmt
// can otherwise move such comments to column one and activate them. A single
// space after // makes their original non-directive status unambiguous.
func (c *converter) safeCommentGroup(group *ast.CommentGroup) string {
	raw := c.text(group)
	start := c.fset.PositionFor(group.Pos(), false).Offset
	for i := len(group.List) - 1; i >= 0; i-- {
		comment := group.List[i]
		position := c.fset.PositionFor(comment.Pos(), false)
		if position.Column != 1 && strings.HasPrefix(comment.Text, "//line ") {
			offset := position.Offset - start
			if offset >= 0 && offset+2 <= len(raw) {
				raw = raw[:offset+2] + " " + raw[offset+2:]
			}
		}
	}
	return raw
}

// preserveComments retains comments without tying generated tokens to stale
// offsets. Comments attach to declarations, statements, specs or fields, never
// between an operator and its operand. Ordinary inline comments may move to the
// beginning of their containing statement; directives stay on their own lines.
func (c *converter) preserveComments(parsed *ast.File, file *File) {
	file.Extra = make(map[string]any)
	index := newCommentIndex(commentCandidates(file))
	for _, group := range parsed.Comments {
		span := c.span(group)
		raw := c.safeCommentGroup(group)
		if span.EndLine < file.Span.Line {
			appendComment(file.Extra, "before_comments", raw)
			continue
		}
		containing, following, preceding := index.boundaries(span)
		target, key := containing, "before_comments"
		if containing != nil && following != nil &&
			posLE(following.Span.EndLine, following.Span.EndCol, containing.Span.EndLine, containing.Span.EndCol) {
			switch containing.Kind {
			case "FuncDecl", "IfStmt", "ForStmt", "RangeStmt", "SwitchStmt", "TypeSwitchStmt", "SelectStmt", "TypeDecl", "VarDecl", "ConstDecl", "ImportDecl", "CaseClause", "CommClause":
				target = following
			}
		}
		// Same-line trailing comments belong after the immediately preceding
		// declaration/statement, not before the next declaration.
		if preceding != nil {
			target, key = preceding, "after_comments"
		} else if containing == nil {
			target = following
		}
		if target != nil {
			if target.Kind == "Field" {
				key = "before_comments"
			}
			if target.Extra == nil {
				target.Extra = make(map[string]any)
			}
			appendComment(target.Extra, key, raw)
		} else if span.Line <= file.Span.Line {
			appendComment(file.Extra, "package_comments", raw)
		} else {
			appendComment(file.Extra, "after_comments", raw)
		}
	}
}

func spanSize(s Span) int { return (s.EndLine-s.Line)*100000 + s.EndCol - s.Col }
func posLE(line, col, otherLine, otherCol int) bool {
	return line < otherLine || line == otherLine && col <= otherCol
}
func appendComment(extra map[string]any, key, comment string) {
	values, _ := extra[key].([]string)
	extra[key] = append(values, comment)
}

func commentBoundary(kind string) bool {
	if strings.HasSuffix(kind, "Decl") || strings.HasSuffix(kind, "Spec") {
		return true
	}
	switch kind {
	case "Field", "AssignStmt", "ReturnStmt", "IfStmt", "ForStmt", "RangeStmt", "SwitchStmt", "TypeSwitchStmt", "SelectStmt", "DeferStmt", "GoStmt", "LabeledStmt", "BranchStmt", "IncDecStmt", "SendStmt", "EmptyStmt", "CaseClause", "CommClause":
		return true
	default:
		return false
	}
}
