//! `syn::File` → M1 [`Node`] tree.
//!
//! Covers the constructs listed in `RUST_IMPL.md` §4. Anything else becomes
//! [`Node::unsupported`] carrying its source text, which the Elixir side maps
//! to `:language_specific` — so unsupported syntax still round-trips exactly
//! (the SQL adapter's `original_ast` trick).
//!
//! The `quote!`-based fallback is what makes that possible: `ToTokens` gives us
//! the source text for *any* node without a per-node printer.

use quote::ToTokens;
use syn::{Expr, Item, Lit, Pat, Stmt, Type};

use crate::ast::{File, LiteralValue, Node};
use crate::span::span_of;

/// Converts a parsed file into the M1 document.
pub fn file_to_node(file: &syn::File) -> File {
    let children = file.items.iter().map(item_to_node).collect();
    File::new(span_of(file), children)
}

/// Converts a single top-level item.
pub fn item_to_node(item: &Item) -> Node {
    let span = span_of(item);

    match item {
        Item::Fn(func) => {
            let mut node = Node::new("Function", span);
            node.name = Some(func.sig.ident.to_string());

            // The declared return type is carried on `type_node` so the
            // reifier can restore the signature. `ReturnType::Default` (no
            // `-> …`) is left as `None` rather than `()` so the two cases stay
            // distinguishable.
            if let syn::ReturnType::Type(_, ty) = &func.sig.output {
                node.type_node = Some(Box::new(type_to_node(ty)));
            }

            node.children = func
                .block
                .stmts
                .iter()
                .map(stmt_to_node)
                .collect::<Vec<_>>();

            // Parameters are attached as `Param` children *before* the body so
            // the Elixir side can split them positionally without a second list.
            let params = func
                .sig
                .inputs
                .iter()
                .map(fn_arg_to_node)
                .collect::<Vec<_>>();

            node.children = params.into_iter().chain(node.children).collect();
            node
        }

        Item::Struct(item_struct) => {
            let mut node = Node::new("Struct", span);
            node.name = Some(item_struct.ident.to_string());
            node.children = item_struct
                .fields
                .iter()
                .map(|field| {
                    let mut field_node = Node::new("Field", span_of(field));
                    field_node.name = field.ident.as_ref().map(|i| i.to_string());
                    field_node.type_node = Some(Box::new(type_to_node(&field.ty)));
                    field_node
                })
                .collect();

            // As with enums, a trailing comma is part of `syn`'s AST. It lives
            // on the `Punctuated` inside `Fields::Named`/`Unnamed`, not on
            // `Fields` itself.
            node.semi = match &item_struct.fields {
                syn::Fields::Named(named) => named.named.trailing_punct(),
                syn::Fields::Unnamed(unnamed) => unnamed.unnamed.trailing_punct(),
                syn::Fields::Unit => false,
            };
            node
        }

        Item::Enum(item_enum) => {
            let mut node = Node::new("Enum", span);
            node.name = Some(item_enum.ident.to_string());
            node.children = item_enum
                .variants
                .iter()
                .map(|variant| {
                    let mut variant_node = Node::new("Variant", span_of(variant));
                    variant_node.name = Some(variant.ident.to_string());
                    variant_node
                })
                .collect();

            // `syn` stores the separators as `Punctuated` elements, so a
            // trailing comma is part of the AST. It is not part of the variant
            // list, so it is recorded on the enum node instead — otherwise the
            // reified enum loses it and the round-trip differs.
            node.semi = item_enum.variants.trailing_punct();
            node
        }

        Item::Trait(item_trait) => {
            let mut node = Node::new("Trait", span);
            node.name = Some(item_trait.ident.to_string());
            // `TraitItem` and `ImplItem` are distinct types from `Item`, so
            // they get their own converters rather than a shared `map`.
            node.children = item_trait
                .items
                .iter()
                .map(trait_item_to_node)
                .collect::<Vec<_>>();
            node
        }

        Item::Impl(item_impl) => {
            let mut node = Node::new("Impl", span);
            node.name = Some(item_impl.self_ty.to_token_stream().to_string());
            node.children = item_impl
                .items
                .iter()
                .map(impl_item_to_node)
                .collect::<Vec<_>>();
            node
        }

        Item::Mod(item_mod) => {
            let mut node = Node::new("Module", span);
            node.name = Some(item_mod.ident.to_string());
            node.children = item_mod
                .content
                .as_ref()
                .map(|(_, items)| items.iter().map(item_to_node).collect())
                .unwrap_or_default();
            node
        }

        Item::Use(item_use) => {
            let mut node = Node::new("Use", span);
            node.name = Some(item_use.tree.to_token_stream().to_string());
            node
        }

        Item::Type(item_type) => {
            let mut node = Node::new("TypeAlias", span);
            node.name = Some(item_type.ident.to_string());
            node.type_node = Some(Box::new(type_to_node(&item_type.ty)));
            node
        }

        Item::Macro(item_macro) => {
            let mut node = Node::new("MacroInvocation", span);
            node.name = Some(item_macro.mac.path.to_token_stream().to_string());
            node.source = Some(item_macro.to_token_stream().to_string());
            node
        }

        other => Node::unsupported(span, other.to_token_stream().to_string()),
    }
}

/// Converts an item inside a `trait` body.
///
/// `TraitItem` is a distinct type from `Item`; a defaulted method body is
/// converted with the same `Function` shape so the Elixir side sees one node
/// kind regardless of where the method was declared.
fn trait_item_to_node(item: &syn::TraitItem) -> Node {
    let span = span_of(item);

    match item {
        syn::TraitItem::Fn(method) => {
            let mut node = Node::new("Function", span);
            node.name = Some(method.sig.ident.to_string());

            let params = method
                .sig
                .inputs
                .iter()
                .map(fn_arg_to_node)
                .collect::<Vec<_>>();

            let body = method
                .default
                .as_ref()
                .map(|block| block.stmts.iter().map(stmt_to_node).collect::<Vec<_>>())
                .unwrap_or_default();

            node.children = params.into_iter().chain(body).collect();
            node
        }

        other => Node::unsupported(span, other.to_token_stream().to_string()),
    }
}

/// Converts an item inside an `impl` body.
fn impl_item_to_node(item: &syn::ImplItem) -> Node {
    let span = span_of(item);

    match item {
        syn::ImplItem::Fn(method) => {
            let mut node = Node::new("Function", span);
            node.name = Some(method.sig.ident.to_string());

            let params = method
                .sig
                .inputs
                .iter()
                .map(fn_arg_to_node)
                .collect::<Vec<_>>();

            let body = method
                .block
                .stmts
                .iter()
                .map(stmt_to_node)
                .collect::<Vec<_>>();

            node.children = params.into_iter().chain(body).collect();
            node
        }

        syn::ImplItem::Const(constant) => {
            let mut node = Node::new("Const", span);
            node.name = Some(constant.ident.to_string());
            node.children = vec![expr_to_node(&constant.expr)];
            node
        }

        other => Node::unsupported(span, other.to_token_stream().to_string()),
    }
}

fn fn_arg_to_node(arg: &syn::FnArg) -> Node {
    let span = span_of(arg);

    match arg {
        syn::FnArg::Typed(pat_type) => {
            let mut node = Node::new("Param", span);
            node.pattern = Some(Box::new(pat_to_node(&pat_type.pat)));
            node.type_node = Some(Box::new(type_to_node(&pat_type.ty)));
            node
        }

        syn::FnArg::Receiver(receiver) => {
            let mut node = Node::new("Param", span);
            node.name = Some("self".to_string());

            // `self`, `&self` and `&mut self` are three different signatures.
            // Collapsing them to `self` changes the method's ownership
            // semantics, so the reference and mutability are recorded.
            let kind = match (&receiver.reference, receiver.mutability.is_some()) {
                (None, false) => "Self",
                (None, true) => "MutSelf",
                (Some(_), false) => "RefSelf",
                (Some(_), true) => "RefMutSelf",
            };

            node.pattern = Some(Box::new(Node::new(kind, span)));
            node
        }
    }
}

fn stmt_to_node(stmt: &Stmt) -> Node {
    let span = span_of(stmt);

    match stmt {
        Stmt::Local(local) => {
            let mut node = Node::new("Let", span);
            node.pattern = Some(Box::new(pat_to_node(&local.pat)));
            node.children = local
                .init
                .as_ref()
                .map(|init| vec![expr_to_node(&init.expr)])
                .unwrap_or_default();
            node
        }

        Stmt::Item(item) => item_to_node(item),

        Stmt::Expr(expr, semi) => {
            let mut node = expr_to_node(expr);
            // The trailing semicolon is semantically load-bearing: `x + y` as a
            // tail expression is the block's value, `x + y;` discards it.
            // Dropping the flag made every function body round-trip into a
            // value-discarding form.
            node.semi = semi.is_some();
            node
        }

        other => Node::unsupported(span, other.to_token_stream().to_string()),
    }
}

/// Converts an expression.
pub fn expr_to_node(expr: &Expr) -> Node {
    let span = span_of(expr);

    match expr {
        Expr::Lit(expr_lit) => literal_to_node(&expr_lit.lit, span),

        Expr::Path(expr_path) => {
            let mut node = Node::new("Path", span);
            node.name = Some(expr_path.path.to_token_stream().to_string());
            node
        }

        Expr::Binary(expr_bin) => {
            let mut node = Node::new("Binary", span);
            node.name = Some(expr_bin.op.to_token_stream().to_string());
            node.children = vec![expr_to_node(&expr_bin.left), expr_to_node(&expr_bin.right)];
            node
        }

        Expr::Unary(expr_unary) => {
            let mut node = Node::new("Unary", span);
            node.name = Some(expr_unary.op.to_token_stream().to_string());
            node.children = vec![expr_to_node(&expr_unary.expr)];
            node
        }

        Expr::Call(expr_call) => {
            let mut node = Node::new("Call", span);
            node.name = Some(expr_call.func.to_token_stream().to_string());
            node.children = expr_call.args.iter().map(expr_to_node).collect();
            node
        }

        Expr::MethodCall(expr_method) => {
            let mut node = Node::new("MethodCall", span);
            node.name = Some(expr_method.method.to_string());
            // The receiver is always the first child, then the arguments.
            let mut children = vec![expr_to_node(&expr_method.receiver)];
            children.extend(expr_method.args.iter().map(expr_to_node));
            node.children = children;
            node
        }

        Expr::Field(expr_field) => {
            // `FieldAccess` distinguishes a member access (`point.x`) from a
            // struct field *declaration* (`struct P { x: i32 }`), which is also
            // a `Field` node. Without the distinction the two are
            // indistinguishable downstream.
            let mut node = Node::new("FieldAccess", span);
            node.name = Some(expr_field.member.to_token_stream().to_string());
            node.children = vec![expr_to_node(&expr_field.base)];
            node
        }

        Expr::Index(expr_index) => {
            let mut node = Node::new("Index", span);
            node.children = vec![
                expr_to_node(&expr_index.expr),
                expr_to_node(&expr_index.index),
            ];
            node
        }

        Expr::If(expr_if) => {
            let mut node = Node::new("If", span);
            node.children = vec![
                expr_to_node(&expr_if.cond),
                block_to_node(&expr_if.then_branch),
            ];
            if let Some((_, else_expr)) = &expr_if.else_branch {
                node.children.push(expr_to_node(else_expr));
            }
            node
        }

        Expr::Block(expr_block) => block_to_node(&expr_block.block),

        Expr::Return(expr_return) => {
            let mut node = Node::new("Return", span);
            node.children = expr_return
                .expr
                .as_ref()
                .map(|expr| vec![expr_to_node(expr)])
                .unwrap_or_default();
            node
        }

        Expr::While(expr_while) => {
            let mut node = Node::new("While", span);
            node.children = vec![
                expr_to_node(&expr_while.cond),
                block_to_node(&expr_while.body),
            ];
            node
        }

        Expr::ForLoop(expr_for) => {
            let mut node = Node::new("ForLoop", span);
            node.pattern = Some(Box::new(pat_to_node(&expr_for.pat)));
            node.children = vec![expr_to_node(&expr_for.expr), block_to_node(&expr_for.body)];
            node
        }

        Expr::Loop(expr_loop) => {
            let mut node = Node::new("Loop", span);
            node.children = vec![block_to_node(&expr_loop.body)];
            node
        }

        Expr::Match(expr_match) => {
            let mut node = Node::new("Match", span);
            node.children = std::iter::once(expr_to_node(&expr_match.expr))
                .chain(expr_match.arms.iter().map(|arm| {
                    let mut arm_node = Node::new("MatchArm", span_of(arm));
                    arm_node.pattern = Some(Box::new(pat_to_node(&arm.pat)));
                    arm_node.children = vec![expr_to_node(&arm.body)];
                    arm_node
                }))
                .collect();
            node
        }

        Expr::Closure(expr_closure) => {
            let mut node = Node::new("Closure", span);
            node.children = vec![expr_to_node(&expr_closure.body)];
            node
        }

        Expr::Array(expr_array) => {
            let mut node = Node::new("Array", span);
            node.children = expr_array.elems.iter().map(expr_to_node).collect();
            node
        }

        Expr::Tuple(expr_tuple) => {
            let mut node = Node::new("Tuple", span);
            node.children = expr_tuple.elems.iter().map(expr_to_node).collect();
            node
        }

        Expr::Assign(expr_assign) => {
            let mut node = Node::new("Assign", span);
            node.children = vec![
                expr_to_node(&expr_assign.left),
                expr_to_node(&expr_assign.right),
            ];
            node
        }

        Expr::Range(expr_range) => {
            let mut node = Node::new("Range", span);
            if let Some(start) = &expr_range.start {
                node.children.push(expr_to_node(start));
            }
            if let Some(end) = &expr_range.end {
                node.children.push(expr_to_node(end));
            }
            node
        }

        Expr::Await(expr_await) => {
            let mut node = Node::new("Await", span);
            node.children = vec![expr_to_node(&expr_await.base)];
            node
        }

        Expr::Try(expr_try) => {
            let mut node = Node::new("Try", span);
            node.children = vec![expr_to_node(&expr_try.expr)];
            node
        }

        // `&x` and `&mut x`. The mutability is load-bearing: dropping it turns
        // a mutable borrow into a shared one, which does not compile.
        Expr::Reference(expr_ref) => {
            let mut node = Node::new("Reference", span);
            if expr_ref.mutability.is_some() {
                node.mutability = Some(true);
            }
            node.children = vec![expr_to_node(&expr_ref.expr)];
            node
        }

        // `unsafe { ... }` — the block is preserved verbatim, but the marker is
        // kept so the reifier can re-emit the `unsafe` keyword.
        Expr::Unsafe(expr_unsafe) => {
            let mut node = Node::new("Unsafe", span);
            node.children = expr_unsafe.block.stmts.iter().map(stmt_to_node).collect();
            node
        }

        Expr::Async(expr_async) => {
            let mut node = Node::new("Async", span);
            node.children = expr_async.block.stmts.iter().map(stmt_to_node).collect();
            node
        }

        // `let Some(x) = expr` in `if let` / `while let` position.
        Expr::Let(expr_let) => {
            let mut node = Node::new("LetExpr", span);
            node.pattern = Some(Box::new(pat_to_node(&expr_let.pat)));
            node.children = vec![expr_to_node(&expr_let.expr)];
            node
        }

        Expr::Struct(expr_struct) => {
            let mut node = Node::new("StructExpr", span);
            node.name = Some(expr_struct.path.to_token_stream().to_string());
            node.children = expr_struct
                .fields
                .iter()
                .map(|field| {
                    let mut field_node = Node::new("StructField", span_of(field));
                    field_node.name = Some(field.member.to_token_stream().to_string());
                    field_node.children = vec![expr_to_node(&field.expr)];
                    field_node
                })
                .collect();
            node
        }

        Expr::Paren(expr_paren) => {
            // Parentheses are preserved as their own node: `syn` keeps them in
            // the AST, so unwrapping here would make `(a + b) * 2` round-trip
            // as `a + b * 2` — a different program.
            let mut node = Node::new("Paren", span);
            node.children = vec![expr_to_node(&expr_paren.expr)];
            node
        }

        other => Node::unsupported(span, other.to_token_stream().to_string()),
    }
}

fn block_to_node(block: &syn::Block) -> Node {
    Node::with_children(
        "Block",
        span_of(block),
        block.stmts.iter().map(stmt_to_node).collect(),
    )
}

fn literal_to_node(lit: &Lit, span: crate::ast::Span) -> Node {
    let mut node = Node::new("Literal", span);

    node.value = Some(match lit {
        Lit::Int(int) => match int.base10_parse::<i64>() {
            Ok(value) => LiteralValue::Integer(value),
            Err(_) => LiteralValue::BigInteger(int.base10_digits().to_string()),
        },
        Lit::Float(float) => match float.base10_parse::<f64>() {
            Ok(value) => LiteralValue::Float(value),
            Err(_) => LiteralValue::Other(float.base10_digits().to_string()),
        },
        Lit::Str(string) => LiteralValue::String(string.value()),
        Lit::Bool(boolean) => LiteralValue::Boolean(boolean.value),
        Lit::Char(char_lit) => LiteralValue::Char(char_lit.value().to_string()),
        Lit::ByteStr(bytes) => LiteralValue::Bytes(bytes.value()),
        other => LiteralValue::Other(other.to_token_stream().to_string()),
    });

    node
}

fn pat_to_node(pat: &Pat) -> Node {
    let span = span_of(pat);

    match pat {
        Pat::Wild(_) => Node::new("Wild", span),

        Pat::Ident(pat_ident) => {
            let mut node = Node::new("Ident", span);
            node.name = Some(pat_ident.ident.to_string());
            // `mut` is part of the binding's semantics: dropping it turns a
            // mutable `let mut total` into an immutable one, which does not
            // compile once the body assigns to it. It is carried on its own
            // field — `semi` means "statement terminator" everywhere else.
            if pat_ident.mutability.is_some() {
                node.mutability = Some(true);
            }
            node
        }

        Pat::Tuple(pat_tuple) => {
            let mut node = Node::new("TuplePat", span);
            node.children = pat_tuple.elems.iter().map(pat_to_node).collect();
            node
        }

        Pat::Path(pat_path) => {
            let mut node = Node::new("PathPat", span);
            node.name = Some(pat_path.path.to_token_stream().to_string());
            node
        }

        other => Node::unsupported(span, other.to_token_stream().to_string()),
    }
}

fn type_to_node(ty: &Type) -> Node {
    let mut node = Node::new("Type", span_of(ty));
    // `to_token_stream` inserts a space between every token, which turns
    // `[i32; 0]` into `[i32 ; 0]` — not valid Rust when re-emitted verbatim.
    // `prettyplease` is the authority on canonical spacing, so the type is
    // rendered through it by wrapping it in a throwaway item.
    node.name = Some(render_type(ty));
    node
}

/// Renders a type with canonical spacing.
fn render_type(ty: &Type) -> String {
    let item: Item = syn::parse_quote! { type __MetastaticType = #ty; };
    let printed = prettyplease::unparse(&syn::File {
        shebang: None,
        attrs: Vec::new(),
        items: vec![item],
    });

    printed
        .trim()
        .strip_prefix("type __MetastaticType = ")
        .and_then(|rest| rest.strip_suffix(';'))
        .map(|rest| rest.trim().to_string())
        .unwrap_or_else(|| ty.to_token_stream().to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn parse(source: &str) -> syn::File {
        syn::parse_str(source).expect("fixture must parse")
    }

    #[test]
    fn converts_a_function_with_parameters() {
        let file = parse("fn add(x: i32, y: i32) -> i32 {\n    x + y\n}\n");
        let document = file_to_node(&file);

        assert_eq!(document.kind, "File");
        assert_eq!(document.children.len(), 1);

        let func = &document.children[0];
        assert_eq!(func.kind, "Function");
        assert_eq!(func.name.as_deref(), Some("add"));

        // Two `Param` children followed by the body expression.
        assert_eq!(func.children[0].kind, "Param");
        assert_eq!(func.children[1].kind, "Param");
        assert_eq!(func.children[2].kind, "Binary");
    }

    #[test]
    fn converts_literals_with_subtypes() {
        let file = parse("fn f() { let a = 42; let b = 1.5; let c = \"hi\"; let d = true; }");
        let document = file_to_node(&file);
        let func = &document.children[0];

        let values: Vec<&LiteralValue> = func
            .children
            .iter()
            .filter_map(|node| node.children.first())
            .filter_map(|node| node.value.as_ref())
            .collect();

        assert_eq!(values[0], &LiteralValue::Integer(42));
        assert_eq!(values[1], &LiteralValue::Float(1.5));
        assert_eq!(values[2], &LiteralValue::String("hi".to_string()));
        assert_eq!(values[3], &LiteralValue::Boolean(true));
    }

    #[test]
    fn binary_operators_carry_their_symbol() {
        let file = parse("fn f() { let x = 1 + 2; }");
        let document = file_to_node(&file);

        // The function has no parameters, so its only child is the `Let`,
        // whose only child is the binary expression.
        let let_node = &document.children[0].children[0];
        assert_eq!(let_node.kind, "Let");

        let binary = &let_node.children[0];
        assert_eq!(binary.kind, "Binary");
        assert_eq!(binary.name.as_deref(), Some("+"));
        assert_eq!(binary.children.len(), 2);
    }

    #[test]
    fn unsupported_items_preserve_source_text() {
        // `asm!` has no MetaAST analogue, so it stays an escape hatch even
        // though the enclosing `unsafe` block is now modelled.
        let file = parse("fn f() { asm!(\"nop\"); }");
        let document = file_to_node(&file);
        let func = &document.children[0];

        let unsupported = &func.children[0];
        assert_eq!(unsupported.kind, "Unsupported");
        assert!(unsupported.source.is_some());
    }

    #[test]
    fn unsafe_blocks_are_modelled() {
        let file = parse("fn f() { let x = unsafe { 1 }; }");
        let document = file_to_node(&file);
        let let_node = &document.children[0].children[0];

        assert_eq!(let_node.children[0].kind, "Unsafe");
    }

    #[test]
    fn converts_structs_and_enums() {
        let file = parse("struct Point { x: i32, y: i32 }\nenum Shape { Circle, Square }\n");
        let document = file_to_node(&file);

        assert_eq!(document.children[0].kind, "Struct");
        assert_eq!(document.children[0].name.as_deref(), Some("Point"));
        assert_eq!(document.children[0].children.len(), 2);

        assert_eq!(document.children[1].kind, "Enum");
        assert_eq!(document.children[1].children.len(), 2);
    }

    #[test]
    fn converts_use_declarations() {
        let file = parse("use std::collections::HashMap;");
        let document = file_to_node(&file);

        assert_eq!(document.children[0].kind, "Use");
        let name = document.children[0].name.as_deref().unwrap_or_default();
        assert!(name.contains("HashMap"), "unexpected use name: {name}");
    }

    #[test]
    fn every_node_has_a_span() {
        // Risk R1 guard: no node may silently lose its position.
        let file = parse("fn main() {\n    let x = 1;\n}\n");
        let document = file_to_node(&file);

        assert!(!document.span.is_unknown(), "file span must be known");
        assert!(
            !document.children[0].span.is_unknown(),
            "item span must be known"
        );
    }
}
