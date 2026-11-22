package main

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"go/ast"
	"go/format"
	"go/parser"
	"go/token"
	"reflect"
	"strconv"
	"strings"
)

func flag(n Node, key string) bool        { value, _ := n.Extra[key].(bool); return value }
func textExtra(n Node, key string) string { value, _ := n.Extra[key].(string); return value }

func count(n Node, key string, fallback int) (int, error) {
	value, exists := n.Extra[key]
	if !exists {
		return fallback, nil
	}
	var number int
	switch value := value.(type) {
	case int:
		number = value
	case float64:
		number = int(value)
		if float64(number) != value {
			return 0, fmt.Errorf("%s.%s must be an integer", n.Kind, key)
		}
	case json.Number:
		i, err := strconv.Atoi(string(value))
		if err != nil {
			return 0, err
		}
		number = i
	default:
		return 0, fmt.Errorf("%s.%s must be an integer", n.Kind, key)
	}
	if number < 0 || number > len(n.Children) {
		return 0, fmt.Errorf("%s.%s is out of range", n.Kind, key)
	}
	return number, nil
}

func sourceBlock(statements []string) string {
	var nonempty []string
	for _, statement := range statements {
		if strings.TrimSpace(statement) != "" {
			nonempty = append(nonempty, statement)
		}
	}
	if len(nonempty) == 0 {
		return "{}"
	}
	return "{\n" + strings.Join(nonempty, "\n") + "\n}"
}

func expressionToSource(n Node) (string, error) {
	source, err := render(n)
	if err != nil {
		return "", err
	}
	if _, err := parser.ParseExpr(source); err != nil {
		return "", fmt.Errorf("invalid reified expression: %w", err)
	}
	// An AST-only format.Node call discards free comments. Format a validated
	// initializer instead, then remove precisely the synthetic declaration.
	const marker = "var __metastatic_expression ="
	formatted, err := format.Source([]byte("package p\n" + marker + " " + source + "\n"))
	if err != nil {
		return "", err
	}
	_, expression, found := strings.Cut(string(formatted), marker)
	if !found {
		return "", fmt.Errorf("formatter lost expression wrapper")
	}
	return strings.TrimSpace(expression), nil
}

func fileToSource(file File) (string, error) {
	if !token.IsIdentifier(file.Package) {
		return "", fmt.Errorf("invalid package name %q", file.Package)
	}
	var out strings.Builder
	out.WriteString(commentExtra(file.Extra, "before_comments"))
	out.WriteString("package " + file.Package + "\n")
	out.WriteString(commentExtra(file.Extra, "package_comments"))
	hasImports := false
	for _, child := range file.Children {
		if child.Kind == "ImportDecl" {
			hasImports = true
		}
	}
	if !hasImports && len(file.Imports) > 0 {
		source, err := render(Node{Kind: "ImportDecl", Children: file.Imports})
		if err != nil {
			return "", err
		}
		out.WriteString(source + "\n")
	}
	for _, child := range file.Children {
		switch child.Kind {
		case "FuncDecl", "ImportDecl", "VarDecl", "ConstDecl", "TypeDecl", "Unsupported":
		default:
			return "", fmt.Errorf("%s is not a file declaration", child.Kind)
		}
		source, err := render(child)
		if err != nil {
			return "", err
		}
		out.WriteString(source + "\n")
	}
	out.WriteString(commentExtra(file.Extra, "after_comments"))
	return out.String(), nil
}

// render emits current fields and children only. Source is consulted solely for
// the explicitly opaque Unsupported escape hatch.
func render(n Node) (result string, err error) {
	defer func() {
		if err == nil {
			after := commentExtra(n.Extra, "after_comments")
			if after != "" {
				after = " " + after
			}
			result = commentExtra(n.Extra, "before_comments") + result + after
		}
	}()
	children := make([]string, len(n.Children))
	for i, child := range n.Children {
		children[i], err = render(child)
		if err != nil {
			return "", fmt.Errorf("%s child %d: %w", n.Kind, i, err)
		}
	}
	need := func(size int) error {
		if len(children) != size {
			return fmt.Errorf("%s requires %d children, got %d", n.Kind, size, len(children))
		}
		return nil
	}
	typ := ""
	if n.TypeNode != nil {
		typ, err = render(*n.TypeNode)
		if err != nil {
			return "", err
		}
	}
	pattern := ""
	if n.Pattern != nil {
		pattern, err = render(*n.Pattern)
		if err != nil {
			return "", err
		}
	}
	join := func() string { return strings.Join(children, ", ") }
	block := func() string { return sourceBlock(children) }
	switch n.Kind {
	case "Unsupported":
		if strings.TrimSpace(n.Source) == "" {
			return "", fmt.Errorf("Unsupported requires nonempty source")
		}
		return n.Source, nil
	case "Absent":
		return "", nil
	case "Ident":
		if !token.IsIdentifier(n.Name) {
			return "", fmt.Errorf("invalid identifier %q", n.Name)
		}
		return n.Name, nil
	case "BasicLit":
		return literalSource(n)
	case "BinaryExpr":
		if err := need(2); err != nil {
			return "", err
		}
		if !contains("+ - * / % & | ^ << >> &^ && || == != < <= > >= ~", n.Name) {
			return "", fmt.Errorf("unsupported binary operator %q", n.Name)
		}
		precedence := operatorPrecedence(n.Name)
		return operand(n.Children[0], children[0], precedence) + " " + n.Name + " " + operand(n.Children[1], children[1], precedence+1), nil
	case "UnaryExpr", "StarExpr":
		if err := need(1); err != nil {
			return "", err
		}
		op := n.Name
		if n.Kind == "StarExpr" {
			op = "*"
		}
		if !contains("+ - ! ^ * & <- ~", op) {
			return "", fmt.Errorf("unsupported unary operator %q", op)
		}
		value := operand(n.Children[0], children[0], 6)
		if n.Children[0].Kind == "UnaryExpr" || n.Children[0].Kind == "StarExpr" {
			// Whitespace prevents ++, --, && and &^ token fusion without
			// introducing an otherwise nonexistent ParenExpr into the tree.
			value = " " + value
		}
		return op + value, nil
	case "ParenExpr":
		if err := need(1); err != nil {
			return "", err
		}
		return "(" + children[0] + ")", nil
	case "CallExpr":
		if len(children) == 0 {
			return "", fmt.Errorf("CallExpr requires callee")
		}
		args := strings.Join(children[1:], ", ")
		if n.Variadic {
			if len(children) < 2 {
				return "", fmt.Errorf("variadic call requires argument")
			}
			// A numeric argument followed directly by ... can lex as a
			// floating-point token (0. plus ..). gofmt removes safe spacing.
			args += " ..."
		}
		return operand(n.Children[0], children[0], 7) + "(" + args + ")", nil
	case "SelectorExpr":
		if err := need(1); err != nil {
			return "", err
		}
		if !token.IsIdentifier(n.Name) {
			return "", fmt.Errorf("invalid selector %q", n.Name)
		}
		return operand(n.Children[0], children[0], 7) + "." + n.Name, nil
	case "IndexExpr":
		if err := need(2); err != nil {
			return "", err
		}
		return operand(n.Children[0], children[0], 7) + "[" + children[1] + "]", nil
	case "IndexListExpr":
		if len(children) < 2 {
			return "", fmt.Errorf("IndexListExpr requires indices")
		}
		return operand(n.Children[0], children[0], 7) + "[" + strings.Join(children[1:], ", ") + "]", nil
	case "SliceExpr":
		if err := need(4); err != nil {
			return "", err
		}
		bounds := children[1:3]
		if flag(n, "slice3") {
			bounds = children[1:4]
		}
		return operand(n.Children[0], children[0], 7) + "[" + strings.Join(bounds, ":") + "]", nil
	case "TypeAssertExpr":
		if err := need(1); err != nil {
			return "", err
		}
		if flag(n, "type_switch") {
			typ = "type"
		}
		if typ == "" {
			return "", fmt.Errorf("TypeAssertExpr requires type")
		}
		return children[0] + ".(" + typ + ")", nil
	case "CompositeLit":
		return typ + "{" + join() + "}", nil
	case "KeyValueExpr":
		if err := need(2); err != nil {
			return "", err
		}
		return children[0] + ": " + children[1], nil
	case "ArrayType":
		if err := need(2); err != nil {
			return "", err
		}
		return "[" + children[0] + "]" + children[1], nil
	case "MapType":
		if err := need(2); err != nil {
			return "", err
		}
		return "map[" + children[0] + "]" + children[1], nil
	case "ChanType":
		if err := need(1); err != nil {
			return "", err
		}
		if !contains("chan <-chan chan<-", n.Name) {
			return "", fmt.Errorf("invalid channel direction")
		}
		return n.Name + " " + children[0], nil
	case "Ellipsis":
		if len(children) > 1 {
			return "", fmt.Errorf("Ellipsis requires at most one child")
		}
		return "..." + strings.Join(children, ""), nil
	case "StructType", "InterfaceType":
		keyword := "struct"
		if n.Kind == "InterfaceType" {
			keyword = "interface"
		}
		return keyword + " " + block(), nil
	case "Field":
		names := join()
		if typ == "" {
			return "", fmt.Errorf("Field requires type")
		}
		// Interface methods spell M(...) rather than M func(...).
		if names != "" && textExtra(n, "role") == "InterfaceMethod" && strings.HasPrefix(typ, "func(") {
			typ = strings.TrimPrefix(typ, "func")
			return names + typ, nil
		}
		if names != "" {
			names += " "
		}
		tag := ""
		if value, ok := n.Extra["tag"].(string); ok {
			tag = " " + strconv.Quote(value)
			if raw := textExtra(n, "raw_tag"); raw != "" {
				if original, err := strconv.Unquote(raw); err == nil && original == value {
					tag = " " + raw
				}
			}
		}
		return names + typ + tag, nil
	case "FuncType", "FuncDecl":
		var recv, params, results, generics, body []string
		for i, child := range n.Children {
			if child.Kind == "Field" {
				switch textExtra(child, "role") {
				case "Receiver":
					recv = append(recv, children[i])
				case "TypeParam":
					generics = append(generics, children[i])
				case "Param":
					params = append(params, children[i])
				case "Result":
					results = append(results, children[i])
				default:
					return "", fmt.Errorf("invalid function field role")
				}
			} else {
				body = append(body, children[i])
			}
		}
		head := "func"
		if n.Kind == "FuncDecl" {
			if !token.IsIdentifier(n.Name) {
				return "", fmt.Errorf("invalid function name")
			}
			if len(recv) > 0 {
				head += " (" + strings.Join(recv, ", ") + ")"
			}
			head += " " + n.Name
		}
		if len(generics) > 0 {
			head += "[" + strings.Join(generics, ", ") + "]"
		}
		head += "(" + commaList(params) + ")"
		if len(results) == 1 {
			singleUnnamed := false
			for _, field := range n.Children {
				if textExtra(field, "role") == "Result" {
					singleUnnamed = len(field.Children) == 0
				}
			}
			if singleUnnamed && !strings.Contains(results[0], "\n") {
				head += " " + results[0]
			} else {
				head += " (" + commaList(results) + ")"
			}
		} else if len(results) > 0 {
			head += " (" + commaList(results) + ")"
		}
		if n.Kind == "FuncDecl" {
			hasBody, specified := n.Extra["has_body"].(bool)
			if !specified || hasBody {
				head += " " + sourceBlock(body)
			} else if len(body) > 0 {
				return "", fmt.Errorf("bodyless FuncDecl has statements")
			}
		} else if len(body) > 0 {
			return "", fmt.Errorf("FuncType has non-field children")
		}
		return head, nil
	case "FuncLit":
		if err := need(2); err != nil {
			return "", err
		}
		return children[0] + " " + children[1], nil
	case "ImportDecl", "VarDecl", "ConstDecl", "TypeDecl":
		keyword := map[string]string{"ImportDecl": "import", "VarDecl": "var", "ConstDecl": "const", "TypeDecl": "type"}[n.Kind]
		if len(children) == 1 && !flag(n, "grouped") {
			return keyword + " " + children[0], nil
		}
		return keyword + " (\n" + strings.Join(children, "\n") + "\n)", nil
	case "ImportSpec":
		alias := textExtra(n, "alias")
		if alias != "" {
			if alias != "." && !token.IsIdentifier(alias) {
				return "", fmt.Errorf("invalid import alias")
			}
			alias += " "
		}
		return alias + strconv.Quote(n.Name), nil
	case "ValueSpec":
		fallback := 1
		if len(children) == 0 {
			fallback = 0
		}
		size, err := count(n, "name_count", fallback)
		if err != nil {
			return "", err
		}
		if size == 0 {
			return "", fmt.Errorf("ValueSpec requires names")
		}
		source := strings.Join(children[:size], ", ")
		if typ != "" {
			source += " " + typ
		}
		if size < len(children) {
			source += " = " + strings.Join(children[size:], ", ")
		}
		return source, nil
	case "TypeSpec":
		if !token.IsIdentifier(n.Name) || typ == "" {
			return "", fmt.Errorf("TypeSpec requires name and type")
		}
		source := n.Name
		if len(children) > 0 {
			source += "[" + join() + "]"
		}
		if flag(n, "alias") {
			source += " ="
		}
		return source + " " + typ, nil
	case "AssignStmt":
		size, err := count(n, "lhs_count", 1)
		if err != nil {
			return "", err
		}
		if size < 1 || size == len(children) {
			return "", fmt.Errorf("AssignStmt requires targets and values")
		}
		if !contains("= := += -= *= /= %= &= |= ^= <<= >>= &^=", n.Name) {
			return "", fmt.Errorf("invalid assignment operator")
		}
		return strings.Join(children[:size], ", ") + " " + n.Name + " " + strings.Join(children[size:], ", "), nil
	case "BlockStmt", "CaseBody":
		return block(), nil
	case "ReturnStmt":
		return "return " + join(), nil
	case "IfStmt":
		offset := 0
		head := "if "
		if flag(n, "has_init") {
			offset++
			if len(children) < 1 {
				return "", fmt.Errorf("IfStmt missing init")
			}
			head += children[0] + "; "
		}
		if len(children) < offset+2 || len(children) > offset+3 {
			return "", fmt.Errorf("IfStmt requires condition, body and optional else")
		}
		head += children[offset] + " " + children[offset+1]
		if len(children) == offset+3 {
			head += " else " + children[offset+2]
		}
		return head, nil
	case "ForStmt":
		if err := need(4); err != nil {
			return "", err
		}
		head := strings.Join(children[:3], "; ")
		if children[0] == "" && children[2] == "" {
			head = children[1]
		}
		return "for " + head + " " + children[3], nil
	case "RangeStmt":
		size := 2
		if flag(n, "has_value") {
			size++
		}
		if err := need(size); err != nil {
			return "", err
		}
		var bind string
		if n.Pattern != nil {
			bind = pattern
			if flag(n, "has_value") {
				bind += ", " + children[0]
			}
			op := " = "
			if n.Mutable {
				op = " := "
			}
			bind += op
		} else if flag(n, "has_value") {
			return "", fmt.Errorf("range value without key")
		}
		return "for " + bind + "range " + children[size-2] + " " + children[size-1], nil
	case "SwitchStmt", "TypeSwitchStmt":
		offset := 0
		head := "switch "
		if flag(n, "has_init") {
			if len(children) < 1 {
				return "", fmt.Errorf("switch missing init")
			}
			head += children[0] + "; "
			offset++
		}
		if n.Kind == "TypeSwitchStmt" || flag(n, "has_tag") {
			if len(children) <= offset {
				return "", fmt.Errorf("switch missing tag")
			}
			head += children[offset] + " "
			offset++
		}
		return head + "{\n" + strings.Join(children[offset:], "\n") + "\n}", nil
	case "SelectStmt":
		return "select " + block(), nil
	case "CaseClause":
		head := "case " + join()
		if flag(n, "default") {
			head = "default"
		}
		if n.Pattern == nil || n.Pattern.Kind != "CaseBody" {
			return "", fmt.Errorf("CaseClause requires CaseBody pattern")
		}
		// CaseBody is a list, not an extra lexical scope.
		var body []string
		for _, child := range n.Pattern.Children {
			source, err := render(child)
			if err != nil {
				return "", err
			}
			body = append(body, source)
		}
		return head + ":\n" + strings.Join(body, "\n"), nil
	case "CommClause":
		offset := 0
		head := "default"
		if flag(n, "has_comm") {
			if len(children) == 0 {
				return "", fmt.Errorf("CommClause missing communication")
			}
			head = "case " + children[0]
			offset++
		}
		return head + ":\n" + strings.Join(children[offset:], "\n"), nil
	case "DeferStmt", "GoStmt":
		if err := need(1); err != nil {
			return "", err
		}
		keyword := "defer"
		if n.Kind == "GoStmt" {
			keyword = "go"
		}
		return keyword + " " + children[0], nil
	case "LabeledStmt":
		if err := need(1); err != nil {
			return "", err
		}
		if !token.IsIdentifier(n.Name) {
			return "", fmt.Errorf("invalid label")
		}
		if n.Children[0].Kind == "EmptyStmt" {
			children[0] = ";"
		}
		return n.Name + ":\n" + children[0], nil
	case "BranchStmt":
		if !contains("break continue goto fallthrough", n.Name) {
			return "", fmt.Errorf("invalid branch")
		}
		label := textExtra(n, "label")
		if label != "" {
			if !token.IsIdentifier(label) {
				return "", fmt.Errorf("invalid branch label")
			}
			label = " " + label
		}
		return n.Name + label, nil
	case "IncDecStmt":
		if err := need(1); err != nil {
			return "", err
		}
		if n.Name != "++" && n.Name != "--" {
			return "", fmt.Errorf("invalid increment operator")
		}
		return children[0] + n.Name, nil
	case "DeclStmt":
		if err := need(1); err != nil {
			return "", err
		}
		return children[0], nil
	case "SendStmt":
		if err := need(2); err != nil {
			return "", err
		}
		return children[0] + " <- " + children[1], nil
	case "EmptyStmt":
		return "", nil
	default:
		return "", fmt.Errorf("unsupported M1 kind %q", n.Kind)
	}
}

func contains(options, value string) bool {
	for _, option := range strings.Fields(options) {
		if option == value {
			return true
		}
	}
	return false
}

func literalSource(n Node) (string, error) {
	if encoded, exists := n.Extra["value_bytes_base64"]; exists {
		text, ok := encoded.(string)
		if !ok || n.ValueType != "string" {
			return "", fmt.Errorf("value_bytes_base64 requires string literal and base64 string")
		}
		value, err := base64.StdEncoding.DecodeString(text)
		if err != nil {
			return "", fmt.Errorf("invalid value_bytes_base64: %w", err)
		}
		if raw := textExtra(n, "raw"); raw != "" {
			original, err := strconv.Unquote(raw)
			if err == nil && original == string(value) {
				return raw, nil
			}
		}
		return strconv.Quote(string(value)), nil
	}
	if raw := textExtra(n, "raw"); raw != "" {
		// Comparing JSON representations also handles decoded json.Number and
		// native integer values without converting arbitrary integers to float64.
		a, _ := json.Marshal(n.Value)
		b, _ := json.Marshal(n.Extra["original_value"])
		if reflect.DeepEqual(a, b) {
			if err := validateLiteral(raw, n.ValueType); err != nil {
				return "", err
			}
			return raw, nil
		}
	}
	switch n.ValueType {
	case "string":
		value, ok := n.Value.(string)
		if !ok {
			return "", fmt.Errorf("string literal requires string value")
		}
		return strconv.Quote(value), nil
	case "char":
		value, ok := n.Value.(string)
		if !ok || len([]rune(value)) != 1 {
			return "", fmt.Errorf("char literal requires exactly one rune")
		}
		return strconv.QuoteRune([]rune(value)[0]), nil
	case "int", "float", "imag":
		var source string
		switch value := n.Value.(type) {
		case json.Number:
			source = string(value)
		case string:
			source = value
		case int, int64, uint64, float64:
			source = fmt.Sprint(value)
		default:
			return "", fmt.Errorf("numeric literal requires number or lexical string")
		}
		if err := validateLiteral(source, n.ValueType); err != nil {
			return "", err
		}
		return source, nil
	default:
		return "", fmt.Errorf("unsupported literal type %q", n.ValueType)
	}
}

func commentExtra(extra map[string]any, key string) string {
	var comments []string
	switch values := extra[key].(type) {
	case []string:
		comments = values
	case []any:
		for _, value := range values {
			if text, ok := value.(string); ok {
				comments = append(comments, text)
			}
		}
	}
	if len(comments) == 0 {
		return ""
	}
	return strings.Join(comments, "\n\n") + "\n"
}

func validateLiteral(source, valueType string) error {
	expr, err := parser.ParseExpr(source)
	if err != nil {
		return fmt.Errorf("invalid literal: %w", err)
	}
	if unary, ok := expr.(*ast.UnaryExpr); ok && (unary.Op == token.SUB || unary.Op == token.ADD) {
		expr = unary.X
	}
	literal, ok := expr.(*ast.BasicLit)
	if !ok || strings.ToLower(literal.Kind.String()) != valueType {
		return fmt.Errorf("invalid %s literal %q", valueType, source)
	}
	return nil
}
func operatorPrecedence(op string) int {
	switch op {
	case "||":
		return 1
	case "&&":
		return 2
	case "==", "!=", "<", "<=", ">", ">=":
		return 3
	case "+", "-", "|", "^":
		return 4
	default:
		return 5
	}
}
func operand(n Node, source string, minimum int) string {
	precedence := 7
	if n.Kind == "BinaryExpr" {
		precedence = operatorPrecedence(n.Name)
	}
	if n.Kind == "UnaryExpr" || n.Kind == "StarExpr" {
		precedence = 6
	}
	if precedence < minimum {
		return "(" + source + ")"
	}
	return source
}
func commaList(values []string) string {
	source := strings.Join(values, ", ")
	if strings.Contains(source, "\n") {
		return source + ",\n"
	}
	return source
}
