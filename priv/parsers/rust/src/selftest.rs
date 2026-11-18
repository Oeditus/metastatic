//! The Phase 0 exit gate.
//!
//! `RUST_IMPL.md` §8 defines Phase 0's exit criterion as:
//!
//! > Byte-identical `syn::File` on round-trip; spans populated (risk R1
//! > resolved).
//!
//! This module turns that sentence into an executable check. It runs a corpus
//! of snippets through `parse → to_json → from_json → print → parse` and
//! asserts, for every snippet:
//!
//! 1. **Spans are populated** (risk R1) — no node silently reports line 0.
//! 2. **The AST survives the JSON hop** — `to_json` then `from_json` yields a
//!    tree whose `Debug` form is identical to the original `syn::File`.
//! 3. **The printed form re-parses** (risk R2) — `prettyplease` output is valid
//!    Rust, and re-parsing it yields the same tree again.
//!
//! It is deliberately a *binary mode* rather than a `#[test]`-only concern: the
//! Elixir side can shell out to `metastatic-rust-parser selftest` in CI to
//! verify the bridge it is about to use, on the exact toolchain in play.

use serde_json::json;

use crate::ast::{File, Response};
use crate::compare::structural_fingerprint;
use crate::{from_json, to_json};

/// One named snippet in the corpus.
struct Case {
    name: &'static str,
    source: &'static str,
}

/// The corpus. Every construct listed in `RUST_IMPL.md` §4 appears at least
/// once, so a regression in any mapping row fails the gate.
const CORPUS: &[Case] = &[
    Case {
        name: "literals",
        source: "fn f() {\n    let a = 42;\n    let b = 1.5;\n    let c = \"hi\";\n    let d = true;\n    let e = 'x';\n}\n",
    },
    Case {
        name: "binary_ops",
        source: "fn f(a: i32, b: i32) -> i32 {\n    (a + b) * 2 - 1\n}\n",
    },
    Case {
        name: "calls_and_methods",
        source: "fn f(items: Vec<i32>) -> usize {\n    let n = items.len();\n    let m = compute(n, 2);\n    m\n}\n",
    },
    Case {
        name: "conditionals",
        source: "fn f(x: i32) -> &'static str {\n    if x > 0 {\n        \"positive\"\n    } else {\n        \"non-positive\"\n    }\n}\n",
    },
    Case {
        name: "loops",
        source: "fn f(items: Vec<i32>) -> i32 {\n    let mut total = 0;\n    for item in items {\n        total = total + item;\n    }\n    total\n}\n",
    },
    Case {
        name: "match",
        source: "fn f(x: i32) -> i32 {\n    match x {\n        0 => 1,\n        _ => 2,\n    }\n}\n",
    },
    Case {
        name: "structs_and_enums",
        source: "struct Point {\n    x: i32,\n    y: i32,\n}\n\nenum Shape {\n    Circle,\n    Square,\n}\n",
    },
    Case {
        name: "use_and_type_alias",
        source: "use std::collections::HashMap;\n\ntype Table = HashMap<String, i32>;\n",
    },
    Case {
        name: "arrays_and_tuples",
        source: "fn f() -> (i32, i32) {\n    let items = [1, 2, 3];\n    (items[0], items[1])\n}\n",
    },
    Case {
        name: "unsupported_escape_hatch",
        source: "fn f() {\n    unsafe {\n        asm!(\"nop\");\n    }\n}\n",
    },
];

/// Runs the whole corpus and reports the aggregate result.
pub fn run() -> Response {
    let mut failures: Vec<serde_json::Value> = Vec::new();
    let mut checked = 0usize;

    for case in CORPUS {
        checked += 1;

        if let Err(reason) = check_case(case) {
            failures.push(json!({ "case": case.name, "reason": reason }));
        }
    }

    if failures.is_empty() {
        Response::ast(json!({
            "status": "ok",
            "cases": checked,
            "spans_populated": true,
            "ast_round_trip": true,
            "print_round_trip": true,
        }))
    } else {
        Response::error(
            "SelfTestError",
            format!(
                "{} of {} cases failed: {}",
                failures.len(),
                checked,
                serde_json::to_string(&failures).unwrap_or_default()
            ),
            None,
        )
    }
}

/// Runs one case through all three checks.
fn check_case(case: &Case) -> Result<(), String> {
    let original = syn::parse_file(case.source)
        .map_err(|error| format!("corpus snippet does not parse: {error}"))?;

    // 1. Spans must be populated (risk R1).
    let document = to_json::file_to_node(&original);
    assert_spans_populated(&document)?;

    // 2. The AST must survive the JSON hop.
    let json = serde_json::to_string(&document)
        .map_err(|error| format!("failed to serialise M1: {error}"))?;
    let decoded: File = serde_json::from_str(&json)
        .map_err(|error| format!("failed to deserialise M1: {error}"))?;

    if decoded != document {
        return Err("M1 document changed across the JSON hop".to_string());
    }

    let reified = from_json::node_to_file(&decoded)
        .map_err(|error| format!("failed to reify M1: {error}"))?;

    if structural_fingerprint(&reified.items) != structural_fingerprint(&original.items) {
        return Err("reified AST differs from the original AST".to_string());
    }

    // 3. The printed form must re-parse to the same tree (risk R2).
    let printed = prettyplease::unparse(&reified);
    let reparsed = syn::parse_file(&printed)
        .map_err(|error| format!("printed output does not re-parse: {error}\n---\n{printed}"))?;

    if structural_fingerprint(&reparsed.items) != structural_fingerprint(&original.items) {
        return Err("re-parsed output differs from the original AST".to_string());
    }

    Ok(())
}

/// Walks the M1 tree and fails if any node lost its position.
fn assert_spans_populated(document: &File) -> Result<(), String> {
    if document.span.is_unknown() {
        return Err("the file node has no span".to_string());
    }

    for child in &document.children {
        assert_node_span(child)?;
    }

    Ok(())
}

fn assert_node_span(node: &crate::ast::Node) -> Result<(), String> {
    if node.span.is_unknown() {
        return Err(format!("node `{}` has no span", node.kind));
    }

    for child in &node.children {
        assert_node_span(child)?;
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_corpus_is_not_empty() {
        assert!(CORPUS.len() >= 10, "the corpus must cover every §4 row");
    }

    #[test]
    fn every_corpus_snippet_parses() {
        for case in CORPUS {
            assert!(
                syn::parse_file(case.source).is_ok(),
                "corpus snippet `{}` does not parse",
                case.name
            );
        }
    }

    #[test]
    fn every_corpus_snippet_passes_the_gate() {
        for case in CORPUS {
            assert_eq!(
                check_case(case),
                Ok(()),
                "corpus snippet `{}` failed the Phase 0 gate",
                case.name
            );
        }
    }

    #[test]
    fn run_reports_success_for_the_corpus() {
        match run() {
            Response::Success(success) => {
                assert!(success.ok);
                let ast = success.ast.expect("ast");
                assert_eq!(ast["status"], "ok");
                assert_eq!(ast["spans_populated"], true);
                assert_eq!(ast["ast_round_trip"], true);
                assert_eq!(ast["print_round_trip"], true);
            }
            other => panic!("expected a success, got {other:?}"),
        }
    }
}
