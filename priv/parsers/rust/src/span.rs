//! Source-span extraction.
//!
//! `proc-macro2` only reports real line/column information when the
//! `span-locations` feature is enabled **and** the span came from a
//! `proc_macro2::TokenStream` parsed by `syn` outside a proc-macro context.
//! That combination is what makes risk R1 in `RUST_IMPL.md` resolvable without
//! falling back to `ra_ap_syntax`.
//!
//! Every conversion goes through [`span_of`], so if the assumption ever breaks
//! the failure is visible in one place: `Span::UNKNOWN` everywhere, which the
//! `selftest` mode asserts against.

use proc_macro2::Span as PmSpan;
use syn::spanned::Spanned;

use crate::ast::Span;

/// Converts a `proc-macro2` span into the M1 [`Span`].
///
/// Columns are normalised to 1-based to agree with the `:col` convention the
/// other Metastatic adapters use.
pub fn from_pm(span: PmSpan) -> Span {
    let start = span.start();
    let end = span.end();

    Span {
        line: start.line,
        col: start.column + 1,
        end_line: end.line,
        end_col: end.column + 1,
    }
}

/// Returns the span of any `syn` node.
pub fn span_of<T: Spanned>(node: &T) -> Span {
    from_pm(node.span())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn syn_spans_carry_line_and_column() {
        // This is the Phase 0 gate for risk R1: if `span-locations` is not
        // effective, every assertion below collapses to 0.
        let file: syn::File = syn::parse_str("fn main() {\n    let x = 1;\n}\n").expect("parse");

        let func = match &file.items[0] {
            syn::Item::Fn(f) => f,
            other => panic!("expected a function, got {:?}", other),
        };

        let span = span_of(func);
        assert_eq!(span.line, 1, "function must start on line 1");
        assert_eq!(span.col, 1, "function must start at column 1");
        assert!(!span.is_unknown(), "spans must not be unknown");
    }

    #[test]
    fn nested_nodes_report_their_own_position() {
        let file: syn::File =
            syn::parse_str("fn main() {\n    let x = 1;\n    let y = 2;\n}\n").expect("parse");

        let func = match &file.items[0] {
            syn::Item::Fn(f) => f,
            other => panic!("expected a function, got {:?}", other),
        };

        let second_let = match &func.block.stmts[1] {
            syn::Stmt::Local(local) => local,
            other => panic!("expected a let statement, got {:?}", other),
        };

        let span = span_of(second_let);
        assert_eq!(span.line, 3, "second `let` must be on line 3");
        assert!(span.col >= 5, "second `let` must be indented");
    }

    #[test]
    fn end_position_is_after_start() {
        let file: syn::File = syn::parse_str("fn f() {}").expect("parse");
        let span = span_of(&file);

        assert!(span.end_line >= span.line);
        if span.end_line == span.line {
            assert!(span.end_col >= span.col);
        }
    }
}
