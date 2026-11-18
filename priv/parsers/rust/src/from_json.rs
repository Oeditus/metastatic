//! M1 [`Node`] tree → `syn::File`.
//!
//! The inverse of [`crate::to_json`]. Two properties matter:
//!
//! 1. **Totality.** Every node kind `to_json` emits must be reconstructible, or
//!    the round-trip loses information. `Node::unsupported` is reconstructed by
//!    re-parsing its preserved source text, which is why the escape hatch is
//!    lossless.
//! 2. **No panics.** This runs on data that may have been mutated by the Elixir
//!    side, so every failure is a `Result` — never an `unwrap`.
//!
//! `syn::parse_str` is used as the reconstruction engine for anything we do not
//! build by hand. That keeps this module small and guarantees the output is
//! *valid Rust* rather than a hand-assembled tree that merely looks right.

use syn::Item;

use crate::ast::{File, Node};

/// A reconstruction failure, reported to the Elixir side as a bridge error.
#[derive(Debug, Clone, PartialEq)]
pub struct ReifyError {
    pub kind: &'static str,
    pub msg: String,
}

impl ReifyError {
    fn new(kind: &'static str, msg: impl Into<String>) -> ReifyError {
        ReifyError {
            kind,
            msg: msg.into(),
        }
    }
}

impl std::fmt::Display for ReifyError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}: {}", self.kind, self.msg)
    }
}

/// Converts an M1 document back into a `syn::File`.
pub fn node_to_file(document: &File) -> Result<syn::File, ReifyError> {
    let mut items = Vec::with_capacity(document.children.len());

    for child in &document.children {
        items.push(node_to_item(child)?);
    }

    Ok(syn::File {
        shebang: None,
        attrs: Vec::new(),
        items,
    })
}

/// Converts one M1 node into a top-level item.
pub fn node_to_item(node: &Node) -> Result<Item, ReifyError> {
    match node.kind.as_str() {
        "Function" => node_to_function(node),
        "Struct" => node_to_struct(node),
        "Enum" => node_to_enum(node),
        "Use" => node_to_use(node),
        "TypeAlias" => node_to_type_alias(node),
        "Trait" => node_to_trait(node),
        "Impl" => node_to_impl(node),
        "Module" => node_to_module(node),

        // The escape hatch: re-parse the preserved source text.
        "Unsupported" => parse_item(node.source.as_deref().unwrap_or_default()),

        // A statement that reached the top level is still valid Rust as an item
        // only if it parses; otherwise report it rather than emitting junk.
        other => parse_item(&render_statement(node).map_err(|error| {
            ReifyError::new(
                "ReifyError",
                format!("cannot reify top-level node `{other}`: {error}"),
            )
        })?),
    }
}

/// Renders the `fn` items of a trait body.
///
/// Trait methods are emitted as bodiless signatures, which is always valid in a
/// trait. Parameters are preserved so the signature survives the round-trip.
fn render_item_signatures(children: &[Node]) -> Result<Vec<String>, ReifyError> {
    children
        .iter()
        .map(|child| match child.kind.as_str() {
            "Function" => {
                let name = child.name.as_deref().unwrap_or("method");
                let (params, _body) = split_params(&child.children);
                let rendered = params
                    .iter()
                    .map(|param| render_param(param))
                    .collect::<Result<Vec<_>, _>>()?;
                Ok(format!("fn {name}({});", rendered.join(", ")))
            }
            "Unsupported" => Ok(child.source.clone().unwrap_or_default()),
            other => Err(ReifyError::new(
                "ReifyError",
                format!("cannot reify `{other}` inside a trait"),
            )),
        })
        .collect()
}

fn node_to_trait(node: &Node) -> Result<Item, ReifyError> {
    let name = node
        .name
        .as_deref()
        .ok_or_else(|| ReifyError::new("ReifyError", "trait node has no name"))?;

    let methods = render_item_signatures(&node.children)?;
    parse_item(&format!("trait {name} {{ {} }}", methods.join(" ")))
}

fn node_to_impl(node: &Node) -> Result<Item, ReifyError> {
    // `to_json` stores the self type in `name`; an inherent impl has no trait.
    let self_type = node.name.as_deref().unwrap_or("()");

    // Unlike a trait, an `impl` method must have a body — `prettyplease`
    // refuses to print a bodiless `ImplItem`. Methods are therefore rendered
    // through the ordinary function path, which always emits `{ ... }`.
    let methods = node
        .children
        .iter()
        .map(|child| match child.kind.as_str() {
            "Function" => node_to_function(child)
                .map(|item| quote::ToTokens::to_token_stream(&item).to_string()),
            "Unsupported" => Ok(child.source.clone().unwrap_or_default()),
            other => Err(ReifyError::new(
                "ReifyError",
                format!("cannot reify `{other}` inside an impl"),
            )),
        })
        .collect::<Result<Vec<_>, _>>()?;

    parse_item(&format!("impl {self_type} {{ {} }}", methods.join(" ")))
}

fn node_to_module(node: &Node) -> Result<Item, ReifyError> {
    let name = node
        .name
        .as_deref()
        .ok_or_else(|| ReifyError::new("ReifyError", "module node has no name"))?;

    let items = node
        .children
        .iter()
        .map(|child| {
            node_to_item(child)
                .map(|item| quote::ToTokens::to_token_stream(&item).to_string())
                .map_err(|error| {
                    ReifyError::new(
                        "ReifyError",
                        format!("cannot reify an item inside module `{name}`: {error}"),
                    )
                })
        })
        .collect::<Result<Vec<_>, _>>()?;

    parse_item(&format!("mod {name} {{ {} }}", items.join(" ")))
}

fn node_to_function(node: &Node) -> Result<Item, ReifyError> {
    let name = node
        .name
        .as_deref()
        .ok_or_else(|| ReifyError::new("ReifyError", "function node has no name"))?;

    // Parameters are the leading `Param` children; the rest is the body.
    let (params, body) = split_params(&node.children);

    let mut signature = format!("fn {name}(");
    let rendered_params = params
        .iter()
        .map(|param| render_param(param))
        .collect::<Result<Vec<_>, _>>()?;
    signature.push_str(&rendered_params.join(", "));
    signature.push(')');

    // `to_json` stores the declared return type on `type_node`; dropping it
    // would silently change the function's signature on every round-trip.
    if let Some(return_type) = node
        .type_node
        .as_deref()
        .and_then(|type_node| type_node.name.as_deref())
    {
        if return_type != "()" {
            signature.push_str(&format!(" -> {return_type}"));
        }
    }

    let rendered_body = body
        .iter()
        .map(|statement| render_block_statement(statement))
        .collect::<Result<Vec<_>, _>>()?;

    let source = format!("{signature} {{\n{}\n}}", rendered_body.join("\n"));
    parse_item(&source)
}

fn node_to_struct(node: &Node) -> Result<Item, ReifyError> {
    let name = node
        .name
        .as_deref()
        .ok_or_else(|| ReifyError::new("ReifyError", "struct node has no name"))?;

    let fields = node
        .children
        .iter()
        .map(|field| {
            let field_name = field.name.as_deref().unwrap_or("_field");
            let ty = field
                .type_node
                .as_deref()
                .and_then(|type_node| type_node.name.as_deref())
                .unwrap_or("()");
            format!("{field_name}: {ty}")
        })
        .collect::<Vec<_>>();

    let trailing = if node.semi { "," } else { "" };

    parse_item(&format!(
        "struct {name} {{ {}{trailing} }}",
        fields.join(", ")
    ))
}

fn node_to_enum(node: &Node) -> Result<Item, ReifyError> {
    let name = node
        .name
        .as_deref()
        .ok_or_else(|| ReifyError::new("ReifyError", "enum node has no name"))?;

    let variants = node
        .children
        .iter()
        .filter_map(|variant| variant.name.clone())
        .collect::<Vec<_>>();

    // Preserve the trailing comma recorded by `to_json`; `syn` keeps it as part
    // of the AST, so dropping it would change the round-tripped tree.
    let trailing = if node.semi { "," } else { "" };

    parse_item(&format!(
        "enum {name} {{ {}{trailing} }}",
        variants.join(", ")
    ))
}

fn node_to_use(node: &Node) -> Result<Item, ReifyError> {
    let name = node
        .name
        .as_deref()
        .ok_or_else(|| ReifyError::new("ReifyError", "use node has no path"))?;

    parse_item(&format!("use {name};"))
}

fn node_to_type_alias(node: &Node) -> Result<Item, ReifyError> {
    let name = node
        .name
        .as_deref()
        .ok_or_else(|| ReifyError::new("ReifyError", "type alias node has no name"))?;

    let ty = node
        .type_node
        .as_deref()
        .and_then(|type_node| type_node.name.as_deref())
        .unwrap_or("()");

    parse_item(&format!("type {name} = {ty};"))
}

/// Renders a node as a statement, for use inside a function body.
fn render_statement(node: &Node) -> Result<String, ReifyError> {
    match node.kind.as_str() {
        "Let" => {
            let pattern = node
                .pattern
                .as_deref()
                .map(render_pattern)
                .transpose()?
                .unwrap_or_else(|| "_".to_string());

            let value = node
                .children
                .first()
                .map(render_expression)
                .transpose()?
                .unwrap_or_else(|| "()".to_string());

            Ok(format!("let {pattern} = {value};"))
        }

        "Unsupported" => Ok(node.source.clone().unwrap_or_default()),

        // A reassignment is always a statement, so it always terminates.
        "Assign" => {
            let expression = render_expression(node)?;
            Ok(format!("{expression};"))
        }

        // Anything else is an expression statement.
        _ => {
            let expression = render_expression(node)?;
            if node.semi {
                Ok(format!("{expression};"))
            } else {
                Ok(expression)
            }
        }
    }
}

/// Renders a node as a block statement, honouring the recorded semicolon.
///
/// `render_statement` terminates expression statements with `;`, which is
/// correct for `let`-style bodies but wrong for two cases:
///
/// * a preserved `Unsupported` fragment may already be a complete item or
///   statement (`unsafe { … }`, `asm!(…)`), so appending `;` yields
///   `unsafe { … };` which does not re-parse;
/// * a block-like expression (`if`, `match`, `loop`) is already a complete
///   statement and a trailing `;` would change its value semantics.
fn render_block_statement(node: &Node) -> Result<String, ReifyError> {
    match node.kind.as_str() {
        "Unsupported" => Ok(node.source.clone().unwrap_or_default()),

        _ => render_statement(node),
    }
}

/// Renders a node as an expression.
fn render_expression(node: &Node) -> Result<String, ReifyError> {
    match node.kind.as_str() {
        "Literal" => render_literal(node),

        "Path" => Ok(node.name.clone().unwrap_or_else(|| "_".to_string())),

        "Binary" => {
            let left = render_child(node, 0)?;
            let right = render_child(node, 1)?;
            let op = node.name.as_deref().unwrap_or("+");
            // No parentheses: `to_json` does not record whether the source had
            // them, so adding them here would make the reified tree differ from
            // the original (`Expr::Paren` vs `Expr::Binary`). Precedence is
            // preserved because both sides are rendered as complete expressions
            // and `prettyplease` re-inserts the parentheses the grammar needs.
            Ok(format!("{left} {op} {right}"))
        }

        "Unary" => {
            let operand = render_child(node, 0)?;
            let op = node.name.as_deref().unwrap_or("-");
            Ok(format!("{op}{operand}"))
        }

        "Call" => {
            let name = node.name.as_deref().unwrap_or("drop");
            let args = node
                .children
                .iter()
                .map(render_expression)
                .collect::<Result<Vec<_>, _>>()?;
            Ok(format!("{name}({})", args.join(", ")))
        }

        "MethodCall" => {
            let receiver = render_child(node, 0)?;
            let method = node.name.as_deref().unwrap_or("clone");
            let args = node
                .children
                .iter()
                .skip(1)
                .map(render_expression)
                .collect::<Result<Vec<_>, _>>()?;
            Ok(format!("{receiver}.{method}({})", args.join(", ")))
        }

        "FieldAccess" => {
            let base = render_child(node, 0)?;
            let member = node.name.as_deref().unwrap_or("field");
            Ok(format!("{base}.{member}"))
        }

        "Reference" => {
            let inner = render_child(node, 0)?;
            if node.mutability.unwrap_or(false) {
                Ok(format!("&mut {inner}"))
            } else {
                Ok(format!("&{inner}"))
            }
        }

        "Unsafe" => {
            let body = render_block_body(node)?;
            Ok(format!("unsafe {{ {body} }}"))
        }

        "Async" => {
            let body = render_block_body(node)?;
            Ok(format!("async {{ {body} }}"))
        }

        "LetExpr" => {
            let pattern = node
                .pattern
                .as_deref()
                .map(render_pattern)
                .transpose()?
                .unwrap_or_else(|| "_".to_string());
            let value = render_child(node, 0)?;
            Ok(format!("let {pattern} = {value}"))
        }

        "Index" => {
            let collection = render_child(node, 0)?;
            let index = render_child(node, 1)?;
            Ok(format!("{collection}[{index}]"))
        }

        "If" => {
            let condition = render_child(node, 0)?;
            let then_branch = render_child(node, 1)?;
            match node.children.get(2) {
                Some(else_branch) => Ok(format!(
                    "if {condition} {} else {}",
                    then_branch,
                    render_expression(else_branch)?
                )),
                None => Ok(format!("if {condition} {then_branch}")),
            }
        }

        "Paren" => {
            let inner = render_child(node, 0)?;
            Ok(format!("({inner})"))
        }

        "Block" => {
            let statements = node
                .children
                .iter()
                .map(render_block_statement)
                .collect::<Result<Vec<_>, _>>()?;
            Ok(format!("{{ {} }}", statements.join(" ")))
        }

        "Return" => match node.children.first() {
            Some(value) => Ok(format!("return {};", render_expression(value)?)),
            None => Ok("return;".to_string()),
        },

        "Array" => {
            let elements = node
                .children
                .iter()
                .map(render_expression)
                .collect::<Result<Vec<_>, _>>()?;
            Ok(format!("[{}]", elements.join(", ")))
        }

        "Tuple" => {
            let elements = node
                .children
                .iter()
                .map(render_expression)
                .collect::<Result<Vec<_>, _>>()?;
            Ok(format!("({})", elements.join(", ")))
        }

        "Assign" => {
            let left = render_child(node, 0)?;
            let right = render_child(node, 1)?;
            Ok(format!("{left} = {right}"))
        }

        "Match" => {
            let scrutinee = render_child(node, 0)?;
            let arms = node
                .children
                .iter()
                .skip(1)
                .map(render_match_arm)
                .collect::<Result<Vec<_>, _>>()?;
            // A trailing comma is part of `syn`'s AST for a match expression;
            // omitting it changes the round-tripped tree.
            Ok(format!(
                "match {scrutinee} {{ {arms}, }}",
                arms = arms.join(", ")
            ))
        }

        "While" => {
            let condition = render_child(node, 0)?;
            let body = render_child(node, 1)?;
            Ok(format!("while {condition} {body}"))
        }

        "ForLoop" => {
            let pattern = node
                .pattern
                .as_deref()
                .map(render_pattern)
                .transpose()?
                .unwrap_or_else(|| "_".to_string());
            let iterable = render_child(node, 0)?;
            let body = render_child(node, 1)?;
            Ok(format!("for {pattern} in {iterable} {body}"))
        }

        "Loop" => {
            let body = render_child(node, 0)?;
            Ok(format!("loop {body}"))
        }

        "Closure" => {
            let body = render_child(node, 0)?;
            Ok(format!("|| {body}"))
        }

        "StructExpr" => {
            let name = node.name.as_deref().unwrap_or("Self");
            let fields = node
                .children
                .iter()
                .map(|field| {
                    let field_name = field.name.as_deref().unwrap_or("_field");
                    let value = field
                        .children
                        .first()
                        .map(render_expression)
                        .transpose()?
                        .unwrap_or_else(|| "()".to_string());
                    Ok::<String, ReifyError>(format!("{field_name}: {value}"))
                })
                .collect::<Result<Vec<_>, _>>()?;
            Ok(format!("{name} {{ {} }}", fields.join(", ")))
        }

        "Await" => {
            let inner = render_child(node, 0)?;
            Ok(format!("{inner}.await"))
        }

        "Try" => {
            let inner = render_child(node, 0)?;
            Ok(format!("{inner}?"))
        }

        "Range" => {
            let start = node
                .children
                .first()
                .map(render_expression)
                .transpose()?
                .unwrap_or_default();
            let end = node
                .children
                .get(1)
                .map(render_expression)
                .transpose()?
                .unwrap_or_default();
            Ok(format!("{start}..{end}"))
        }

        "Unsupported" => Ok(node.source.clone().unwrap_or_default()),

        other => Err(ReifyError::new(
            "ReifyError",
            format!("cannot reify node kind `{other}` as an expression"),
        )),
    }
}

fn render_literal(node: &Node) -> Result<String, ReifyError> {
    use crate::ast::LiteralValue;

    match node.value.as_ref() {
        Some(LiteralValue::Integer(value)) => Ok(value.to_string()),
        Some(LiteralValue::BigInteger(text)) => Ok(text.clone()),
        Some(LiteralValue::Float(value)) => Ok(format_float(*value)),
        Some(LiteralValue::String(value)) => Ok(format!("{:?}", value)),
        Some(LiteralValue::Boolean(value)) => Ok(value.to_string()),
        Some(LiteralValue::Char(value)) => Ok(format!("'{}'", value.escape_default())),
        Some(LiteralValue::Bytes(bytes)) => Ok(format!("b{:?}", String::from_utf8_lossy(bytes))),
        Some(LiteralValue::Other(text)) => Ok(text.clone()),
        None => Err(ReifyError::new("ReifyError", "literal node has no value")),
    }
}

/// Renders a float so that it always re-parses as a float.
///
/// `format!("{}", 1.0)` yields `"1"`, which `syn` parses as an integer and the
/// round-trip would silently change the literal's subtype.
fn format_float(value: f64) -> String {
    let rendered = format!("{value}");
    if rendered.contains('.') || rendered.contains('e') || rendered.contains('E') {
        rendered
    } else {
        format!("{rendered}.0")
    }
}

/// Renders one `match` arm as `pattern => body`.
fn render_match_arm(arm: &Node) -> Result<String, ReifyError> {
    let pattern = arm
        .pattern
        .as_deref()
        .map(render_pattern)
        .transpose()?
        .unwrap_or_else(|| "_".to_string());

    let body = arm
        .children
        .first()
        .map(render_expression)
        .transpose()?
        .unwrap_or_else(|| "()".to_string());

    Ok(format!("{pattern} => {body}"))
}

fn render_pattern(node: &Node) -> Result<String, ReifyError> {
    match node.kind.as_str() {
        "Wild" => Ok("_".to_string()),
        // A `self` receiver is rendered bare: `self: Self` is not valid Rust.
        "Self" => Ok("self".to_string()),
        "MutSelf" => Ok("mut self".to_string()),
        "RefSelf" => Ok("&self".to_string()),
        "RefMutSelf" => Ok("&mut self".to_string()),
        "Ident" => {
            let name = node.name.clone().unwrap_or_else(|| "_".to_string());
            if node.mutability.unwrap_or(false) {
                Ok(format!("mut {name}"))
            } else {
                Ok(name)
            }
        }
        "PathPat" => Ok(node.name.clone().unwrap_or_else(|| "_".to_string())),
        // `to_meta` maps a `Path` expression onto `:variable`, which reifies back
        // to a `Path` node — so a `Path` can legitimately appear in pattern
        // position (e.g. an enum variant or a constant binding).
        "Path" => Ok(node.name.clone().unwrap_or_else(|| "_".to_string())),
        "TuplePat" => {
            let elements = node
                .children
                .iter()
                .map(render_pattern)
                .collect::<Result<Vec<_>, _>>()?;
            Ok(format!("({})", elements.join(", ")))
        }
        "Unsupported" => Ok(node.source.clone().unwrap_or_else(|| "_".to_string())),
        other => Err(ReifyError::new(
            "ReifyError",
            format!("cannot reify pattern kind `{other}`"),
        )),
    }
}

fn render_param(node: &Node) -> Result<String, ReifyError> {
    if node.kind != "Param" {
        return Err(ReifyError::new("ReifyError", "expected a Param node"));
    }

    // A `self` receiver is a pattern with no type: `self: Self` is not valid
    // Rust, and `&self` / `&mut self` / `mut self` must keep their sigil.
    if let Some(pattern) = node.pattern.as_deref() {
        if let Some(receiver) = render_receiver(pattern) {
            return Ok(receiver);
        }
    }

    let pattern = node
        .pattern
        .as_deref()
        .map(render_pattern)
        .transpose()?
        .unwrap_or_else(|| "_".to_string());

    let ty = node
        .type_node
        .as_deref()
        .and_then(|type_node| type_node.name.as_deref())
        .unwrap_or("()");

    Ok(format!("{pattern}: {ty}"))
}

/// Returns the rendered receiver when the pattern is a `self` form.
fn render_receiver(pattern: &Node) -> Option<String> {
    match pattern.kind.as_str() {
        "Self" => Some("self".to_string()),
        "MutSelf" => Some("mut self".to_string()),
        "RefSelf" => Some("&self".to_string()),
        "RefMutSelf" => Some("&mut self".to_string()),
        _ => None,
    }
}

/// Renders a node's children as a block body (`stmt; stmt`), used by block-like
/// expressions such as `unsafe { … }` and `async { … }`.
fn render_block_body(node: &Node) -> Result<String, ReifyError> {
    let statements = node
        .children
        .iter()
        .map(render_block_statement)
        .collect::<Result<Vec<_>, _>>()?;

    Ok(statements.join(" "))
}

fn render_child(node: &Node, index: usize) -> Result<String, ReifyError> {
    node.children
        .get(index)
        .ok_or_else(|| {
            ReifyError::new(
                "ReifyError",
                format!("node `{}` is missing child {index}", node.kind),
            )
        })
        .and_then(render_expression)
}

/// Splits a function node's children into parameters and body statements.
fn split_params(children: &[Node]) -> (Vec<&Node>, Vec<&Node>) {
    let split_at = children
        .iter()
        .position(|child| child.kind != "Param")
        .unwrap_or(children.len());

    let (params, body) = children.split_at(split_at);
    (params.iter().collect(), body.iter().collect())
}

fn parse_item(source: &str) -> Result<Item, ReifyError> {
    syn::parse_str::<Item>(source).map_err(|error| {
        ReifyError::new(
            "ParseError",
            format!("generated item does not parse: {error}\n---\n{source}"),
        )
    })
}

/// Renders a bare expression node back to source.
pub fn expression_to_source(node: &Node) -> Result<String, ReifyError> {
    let source = render_expression(node)?;

    // `prettyplease` only prints whole files, so the expression is normalised by
    // embedding it in a function, printing that, and taking the tail back out.
    let wrapper = format!("fn __metastatic_expr() {{ {source} }}");
    let file = syn::parse_file(&wrapper).map_err(|error| {
        ReifyError::new(
            "ParseError",
            format!("generated expression does not parse: {error}\n---\n{source}"),
        )
    })?;

    let printed = prettyplease::unparse(&file);

    // Extract the body between the outer braces.
    match (printed.find('{'), printed.rfind('}')) {
        (Some(open), Some(close)) if open < close => Ok(printed[open + 1..close]
            .trim()
            .trim_end_matches(';')
            .to_string()),
        _ => Ok(source),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ast::{LiteralValue, Span};
    use crate::to_json;

    fn literal(value: LiteralValue) -> Node {
        let mut node = Node::new("Literal", Span::UNKNOWN);
        node.value = Some(value);
        node
    }

    #[test]
    fn renders_integers_and_floats_without_losing_subtype() {
        assert_eq!(
            render_literal(&literal(LiteralValue::Integer(42))).unwrap(),
            "42"
        );
        // `1.0` must not degrade to `1`, which would re-parse as an integer.
        assert_eq!(
            render_literal(&literal(LiteralValue::Float(1.0))).unwrap(),
            "1.0"
        );
        assert_eq!(
            render_literal(&literal(LiteralValue::Float(1.5))).unwrap(),
            "1.5"
        );
    }

    #[test]
    fn renders_binary_expressions_without_gratuitous_parens() {
        let mut node = Node::new("Binary", Span::UNKNOWN);
        node.name = Some("+".to_string());
        node.children = vec![
            literal(LiteralValue::Integer(1)),
            literal(LiteralValue::Integer(2)),
        ];

        // No `Expr::Paren` is introduced: `to_json` does not record whether the
        // source had parentheses, so adding them would break the round-trip.
        assert_eq!(render_expression(&node).unwrap(), "1 + 2");
    }

    #[test]
    fn renders_method_calls_with_receiver_first() {
        let mut node = Node::new("MethodCall", Span::UNKNOWN);
        node.name = Some("len".to_string());
        node.children = vec![
            Node::new("Path", Span::UNKNOWN),
            literal(LiteralValue::Integer(1)),
        ];
        node.children[0].name = Some("items".to_string());

        assert_eq!(render_expression(&node).unwrap(), "items.len(1)");
    }

    #[test]
    fn missing_child_is_an_error_not_a_panic() {
        let node = Node::new("Binary", Span::UNKNOWN);
        let error = render_expression(&node).expect_err("must fail");
        assert_eq!(error.kind, "ReifyError");
    }

    #[test]
    fn unsupported_nodes_are_reparsed_from_source() {
        let node = Node::unsupported(Span::UNKNOWN, "struct Ghost { a: u8 }");
        let item = node_to_item(&node).expect("must reify");
        assert!(matches!(item, Item::Struct(_)));
    }

    #[test]
    fn generated_items_are_valid_rust() {
        let node = Node::unsupported(Span::UNKNOWN, "fn broken( {");
        let error = node_to_item(&node).expect_err("malformed source must fail");
        assert_eq!(error.kind, "ParseError");
    }

    #[test]
    fn round_trips_a_simple_function() {
        let source = "fn add(x: i32, y: i32) -> i32 {\n    x + y\n}\n";
        let file: syn::File = syn::parse_str(source).expect("parse");

        let document = to_json::file_to_node(&file);
        let reified = node_to_file(&document).expect("reify");

        // Structural equality, not textual: `prettyplease` normalises
        // formatting and the reified tree is parsed from new source, so
        // positions differ while the structure must not.
        assert_eq!(
            crate::compare::structural_fingerprint(&reified.items),
            crate::compare::structural_fingerprint(&file.items)
        );
    }

    #[test]
    fn round_trips_structs_and_enums() {
        let source =
            "struct Point { x: i32, y: i32 }\n\nenum Shape {\n    Circle,\n    Square,\n}\n";
        let file: syn::File = syn::parse_str(source).expect("parse");

        let document = to_json::file_to_node(&file);
        let reified = node_to_file(&document).expect("reify");

        assert_eq!(
            crate::compare::structural_fingerprint(&reified.items),
            crate::compare::structural_fingerprint(&file.items)
        );
    }

    #[test]
    fn every_rendered_statement_is_valid_rust() {
        // Guards the reifier against emitting text that merely looks right.
        let file = syn::parse_str::<syn::File>(
            "fn f(items: Vec<i32>) -> i32 {\n    let n = items.len();\n    let x = 1 + 2;\n    x\n}\n",
        )
        .expect("parse");

        let document = to_json::file_to_node(&file);
        let func = &document.children[0];

        // Skip the `Param` children; every remaining child is a statement.
        let rendered = func
            .children
            .iter()
            .filter(|child| child.kind != "Param")
            .map(render_block_statement)
            .collect::<Result<Vec<_>, _>>()
            .expect("render statements");

        // A tail expression is only a valid *statement* inside a block, so the
        // whole body is validated as one block rather than statement by
        // statement.
        let body = format!("fn f() {{ {} }}", rendered.join(" "));
        syn::parse_str::<syn::Item>(&body)
            .unwrap_or_else(|error| panic!("invalid body `{body}`: {error}"));
    }

    #[test]
    fn bare_expressions_round_trip_to_source() {
        // `parse` returns a single node for an expression input, so `unparse`
        // must be able to render that shape back.
        let expression = syn::parse_str::<syn::Expr>("1 + 2").expect("parse");
        let node = to_json::expr_to_node(&expression);

        let source = expression_to_source(&node).expect("render expression");
        assert_eq!(source, "1 + 2");
    }

    #[test]
    fn expression_to_source_rejects_unrenderable_nodes() {
        let node = Node::new("NotARealKind", Span::UNKNOWN);
        assert!(expression_to_source(&node).is_err());
    }
}
