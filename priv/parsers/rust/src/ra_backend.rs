//! Optional lossless backend built on `ra_ap_syntax` (Phase 6).
//!
//! The default `syn` + `prettyplease` pipeline is *semantically* lossless but
//! normalises formatting: `prettyplease` re-prints the tree in rustfmt style,
//! so comments and original whitespace do not survive.
//!
//! `ra_ap_syntax` parses to a **lossless** concrete syntax tree: every token,
//! including trivia (whitespace and comments), is retained with its exact text.
//! Re-printing the tree therefore reproduces the input byte for byte.
//!
//! This module is compiled only with `--features ra`, because the dependency
//! tree is large (~100 crates) and most callers do not need byte-exact output.
//!
//! ## What this backend is for
//!
//! * `fmt --backend ra` — normalise *nothing*; round-trip the source exactly.
//! * A future `parse --backend ra` could emit a trivia-preserving M1 so that
//!   `from_meta` reproduces comments. That is deliberately **not** implemented
//!   yet: the M1 mirror in [`crate::ast`] has no trivia slots, and adding them
//!   would change the contract every other module depends on.

#![cfg(feature = "ra")]

use ra_ap_syntax::{Edition, SourceFile};

/// Parses `source` and re-prints it from the lossless CST.
///
/// The result is byte-identical to the input for any source that parses,
/// comments and blank lines included. Returns `None` when the source contains
/// syntax errors, so the caller can fall back to the `syn` backend.
pub fn round_trip(source: &str) -> Option<String> {
    let parse = SourceFile::parse(source, Edition::Edition2021);

    if !parse.errors().is_empty() {
        return None;
    }

    // `syntax_node().to_string()` walks the CST and concatenates every token's
    // text, trivia included — which is exactly the original source.
    let printed = parse.syntax_node().to_string();

    if printed == source {
        Some(printed)
    } else {
        // A mismatch means the CST lost or duplicated trivia; report it rather
        // than silently claiming byte-exactness.
        None
    }
}

/// Returns the syntax errors reported by `ra_ap_syntax`.
///
/// Not called by the CLI yet — kept so a future `parse --backend ra` can
/// surface CST diagnostics without re-parsing.
#[allow(dead_code)]
pub fn errors(source: &str) -> Vec<String> {
    let parse = SourceFile::parse(source, Edition::Edition2021);

    parse
        .errors()
        .iter()
        .map(|error| error.to_string())
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trips_formatting_exactly() {
        // Deliberately idiosyncratic formatting: `prettyplease` would rewrite
        // all of it, the CST backend must not.
        let source = "fn   main( ) {\n\n    // a comment\n    let x=1;   \n}\n";
        assert_eq!(round_trip(source).as_deref(), Some(source));
    }

    #[test]
    fn preserves_comments() {
        let source = "// leading\nfn f() { /* inline */ }\n// trailing\n";
        assert_eq!(round_trip(source).as_deref(), Some(source));
    }

    #[test]
    fn rejects_invalid_source() {
        assert_eq!(round_trip("fn f( {"), None);
        assert!(!errors("fn f( {").is_empty());
    }

    #[test]
    fn valid_source_has_no_errors() {
        assert!(errors("fn f() {}").is_empty());
    }
}
