//! Structural AST comparison that ignores source positions.
//!
//! `syn`'s `Debug` output embeds `Span` byte offsets (`span: bytes(4..7)`), so
//! comparing `format!("{:#?}", items)` compares *positions*, not structure.
//! That made the Phase 0 gate report a false failure: a reified tree parsed from
//! freshly generated source is at different byte offsets than the original, yet
//! is structurally identical.
//!
//! This module normalises the `Debug` rendering by stripping every
//! `span: bytes(…)` occurrence, which yields a position-independent structural
//! fingerprint. It is deliberately textual rather than a hand-written visitor:
//! `syn`'s node set is large, and a visitor that forgot one node type would
//! silently weaken the gate. Stripping spans cannot *miss* a node.
//!
//! The same normalisation is what `RUST_IMPL.md` §9 means by "compare parsed
//! ASTs, not strings".

/// Renders a value's `Debug` form with all `syn` span information removed.
///
/// Returns a fingerprint that is equal for two trees that differ only in where
/// they were parsed from.
pub fn structural_fingerprint<T: std::fmt::Debug>(value: &T) -> String {
    strip_spans(&format!("{value:#?}"))
}

/// Removes every `span: bytes(a..b)` fragment from a rendered AST.
///
/// `syn` renders token fields as `name: bytes(a..b)` too — a lifetime's
/// `apostrophe: bytes(228..229)` is the one that bit us — so the pattern is
/// the generic `<ident>: bytes(<digits>..<digits>)` rather than the literal
/// `span: bytes(`.
fn strip_spans(rendered: &str) -> String {
    let mut output = String::with_capacity(rendered.len());
    let mut rest = rendered;

    while let Some(index) = find_byte_range(rest) {
        output.push_str(&rest[..index]);
        rest = &rest[index..];

        // Skip through the closing `)` of `bytes(a..b)`.
        match rest.find(')') {
            Some(close) => rest = &rest[close + 1..],
            None => {
                output.push_str(rest);
                return output;
            }
        }
    }

    output.push_str(rest);
    output
}

/// Returns the index at which a `<ident>: bytes(` fragment starts, if any.
fn find_byte_range(text: &str) -> Option<usize> {
    let mut search_from = 0usize;

    while let Some(offset) = text[search_from..].find(": bytes(") {
        let at = search_from + offset;
        // Walk back over the identifier that owns the field name.
        let start = text[..at]
            .rfind(|character: char| !(character.is_alphanumeric() || character == '_'))
            .map(|index| index + 1)
            .unwrap_or(0);

        if start < at {
            return Some(start);
        }

        search_from = at + ": bytes(".len();
    }

    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn strips_span_fragments() {
        let rendered = "Ident { sym: x, span: bytes(4..5) }";
        assert_eq!(strip_spans(rendered), "Ident { sym: x,  }");
    }

    #[test]
    fn strips_token_byte_ranges_too() {
        // Lifetimes render their apostrophe as a token with a byte range.
        let rendered = "Lifetime { apostrophe: bytes(228..229), ident: Ident { sym: a } }";
        assert_eq!(
            strip_spans(rendered),
            "Lifetime { , ident: Ident { sym: a } }"
        );
    }

    #[test]
    fn leaves_text_without_spans_untouched() {
        let rendered = "Item::Fn { attrs: [] }";
        assert_eq!(strip_spans(rendered), rendered);
    }

    #[test]
    fn trees_at_different_offsets_share_a_fingerprint() {
        let first = syn::parse_str::<syn::File>("fn add(x: i32) -> i32 { x }").expect("parse");
        // Same program with leading whitespace, so every span is shifted.
        let second =
            syn::parse_str::<syn::File>("\n\n\nfn add(x: i32) -> i32 { x }").expect("parse");

        assert_ne!(
            format!("{:#?}", first.items),
            format!("{:#?}", second.items),
            "raw Debug must differ, otherwise this test proves nothing"
        );

        assert_eq!(
            structural_fingerprint(&first.items),
            structural_fingerprint(&second.items),
            "structural fingerprints must ignore source positions"
        );
    }

    #[test]
    fn different_programs_have_different_fingerprints() {
        let first = syn::parse_str::<syn::File>("fn add(x: i32) -> i32 { x + 1 }").expect("parse");
        let second = syn::parse_str::<syn::File>("fn add(x: i32) -> i32 { x + 2 }").expect("parse");

        assert_ne!(
            structural_fingerprint(&first.items),
            structural_fingerprint(&second.items),
            "a real structural difference must be detected"
        );
    }
}
