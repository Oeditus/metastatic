//! The Metastatic Gleam parser bridge.
//!
//! A short-lived CLI that speaks the `Metastatic.Adapter.Bridge` protocol on
//! stdout and reads its input from a file path given as the last argument:
//!
//! ```text
//! metastatic-gleam-parser parse    <file.gleam>
//! metastatic-gleam-parser unparse  <file.json>
//! metastatic-gleam-parser format   <file.gleam>
//! metastatic-gleam-parser selftest <anything>
//! ```
//!
//! Every mode prints a single JSON object:
//!
//! ```json
//! {"ok": true,  "ast": {...}}
//! {"ok": true,  "source": "..."}
//! {"ok": false, "error": {"type": "...", "msg": "...", "line": 3}}
//! ```
//!
//! The bridge never reads stdin, so a missing argument fails fast instead of
//! blocking on a pipe that will never close.
//!
//! ## Why a file argument and not stdin
//!
//! `gleam_core::parse::parse_module/3` takes a path (it is used in error
//! messages), and `gleam_format::pretty/3` takes one too. Passing the temp file
//! `Metastatic.Subprocess.run/4` already creates means the bridge never has to
//! invent a path, and the path in a parse error points at a real file.

mod ast;
mod from_json;
// `span` and `to_json` both depend on the vendored `gleam-core` types, so the
// `external-gleam` build (which ships without `vendor/`) omits them entirely.
#[cfg(feature = "vendored")]
mod span;
#[cfg(feature = "vendored")]
mod to_json;

use std::path::PathBuf;

use crate::ast::Response;

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();

    let response = match args.as_slice() {
        [mode, path] => run(mode, PathBuf::from(path)),
        [mode] if mode == "selftest" => selftest(),
        [] => Response::error(
            "UsageError",
            "usage: metastatic-gleam-parser <parse|unparse|format|selftest> <path>",
            None,
        ),
        [mode] => Response::error(
            "UsageError",
            format!("mode `{mode}` requires a path argument"),
            None,
        ),
        _ => Response::error(
            "UsageError",
            "too many arguments; expected <mode> <path>",
            None,
        ),
    };

    match serde_json::to_string(&response) {
        Ok(json) => println!("{json}"),
        // A serialisation failure is a bridge bug, but it must still produce
        // the wire format: the Elixir side decodes JSON or reports a protocol
        // error, and an empty stdout would be the latter with no detail.
        Err(error) => println!(
            "{}",
            serde_json::json!({
                "ok": false,
                "error": {"type": "SerialiseError", "msg": error.to_string()},
            })
        ),
    }
}

/// Dispatches one mode. Every arm returns a [`Response`]; nothing panics.
fn run(mode: &str, path: PathBuf) -> Response {
    match mode {
        "parse" => parse(&path),
        "unparse" => unparse(&path),
        "format" => format_source(&path),
        "selftest" => selftest(),
        other => Response::error(
            "UsageError",
            format!("unknown mode `{other}`; expected parse, unparse, format or selftest"),
            None,
        ),
    }
}

/// Reads a file, mapping the IO error onto the bridge's error shape.
fn read(path: &PathBuf) -> Result<String, Response> {
    std::fs::read_to_string(path).map_err(|error| {
        Response::error(
            "IoError",
            format!("cannot read {}: {error}", path.display()),
            None,
        )
    })
}

/// `parse`: Gleam source → M1 JSON.
#[cfg(feature = "vendored")]
fn parse(path: &PathBuf) -> Response {
    let source = match read(path) {
        Ok(source) => source,
        Err(response) => return response,
    };

    match to_json::parse_module(&source) {
        Ok(module) => Response::ast(serde_json::to_value(&module).unwrap_or_default()),
        Err(failure) => Response::failure(failure),
    }
}

/// `parse` in the `external-gleam` build.
///
/// A full M1 needs the compiler's own untyped AST, which is not reachable from
/// the `gleam` CLI: `gleam export package-interface` emits type signatures
/// only, with no function bodies. Rather than return a *wrong* tree, this
/// build reports precisely what is missing and how to get it.
#[cfg(not(feature = "vendored"))]
fn parse(_path: &PathBuf) -> Response {
    Response::error(
        "UnsupportedBuild",
        "this Metastatic package ships the Gleam bridge without the compiler \
         crates, so it cannot produce a MetaAST. Install the full package \
         (without HEX_BUILD=1), or put a full `metastatic-gleam-parser` on \
         PATH. `format` and `unparse` work in this build.",
        None,
    )
}

/// `unparse`: M1 JSON → Gleam source.
fn unparse(path: &PathBuf) -> Response {
    let json = match read(path) {
        Ok(json) => json,
        Err(response) => return response,
    };

    let value: serde_json::Value = match serde_json::from_str(&json) {
        Ok(value) => value,
        Err(error) => {
            return Response::error("DecodeError", format!("invalid M1 JSON: {error}"), None)
        }
    };

    match from_json::render(&value) {
        Ok(source) => Response::source(source),
        Err(failure) => Response::failure(failure),
    }
}

/// `format`: normalise Gleam source with `gleam format`'s own printer.
fn format_source(path: &PathBuf) -> Response {
    let source = match read(path) {
        Ok(source) => source,
        Err(response) => return response,
    };

    match from_json::format_source(&source) {
        Ok(formatted) => Response::source(formatted),
        Err(failure) => Response::failure(failure),
    }
}

/// `selftest`: verifies the binary that is about to be used.
///
/// Checks that a parse yields spans, that the AST survives
/// parse → JSON → reify → print → re-parse, and that the printer is reachable.
/// The Elixir adapter exposes this so CI and diagnostics can assert on the
/// exact binary in use rather than on the source tree.
#[cfg(feature = "vendored")]
fn selftest() -> Response {
    let checks = to_json::selftest();
    let status = if checks.iter().all(|check| check.passed) {
        "ok"
    } else {
        "failed"
    };

    Response::ast(serde_json::json!({
        "status": status,
        "build": "vendored",
        "checks": checks
            .into_iter()
            .map(|check| serde_json::json!({
                "name": check.name,
                "passed": check.passed,
                "detail": check.detail,
            }))
            .collect::<Vec<_>>(),
    }))
}

/// `selftest` in the `external-gleam` build.
///
/// Only the printer is reachable, so that is all that is checked. Reporting
/// `"status": "ok"` would be a lie about `parse`, so the build is named in the
/// report and `parse` is listed as unsupported.
#[cfg(not(feature = "vendored"))]
fn selftest() -> Response {
    let format_check = match from_json::format_source("pub fn  main( ){1}") {
        Ok(formatted) => {
            let passed = formatted.contains("pub fn main()");
            serde_json::json!({
                "name": "format",
                "passed": passed,
                "detail": format!("{} bytes", formatted.len()),
            })
        }
        Err(error) => serde_json::json!({
            "name": "format",
            "passed": false,
            "detail": error.msg,
        }),
    };

    let parse_check = serde_json::json!({
        "name": "parse",
        "passed": false,
        "detail": "unsupported in the external-gleam build",
    });

    Response::ast(serde_json::json!({
        "status": "partial",
        "build": "external-gleam",
        "checks": [format_check, parse_check],
    }))
}
