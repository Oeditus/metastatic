//! `metastatic-rust-parser` — the Rust AST bridge for Metastatic.
//!
//! Reads a file path as its last argument and writes exactly one JSON object to
//! stdout, matching the canonical envelope `Metastatic.Adapter.Bridge` decodes:
//!
//! ```text
//! metastatic-rust-parser parse   <file.rs>    -> {"ok":true,"ast":{...}}
//! metastatic-rust-parser unparse <ast.json>   -> {"ok":true,"source":"..."}
//! metastatic-rust-parser fmt     <file.rs>    -> {"ok":true,"source":"..."}
//! metastatic-rust-parser selftest [<dir>]     -> {"ok":true,"ast":{...}}
//! ```
//!
//! `fmt` accepts `--backend prettyplease|ra`. With `--features ra` built in,
//! `ra` round-trips the source **byte for byte** (comments and whitespace
//! preserved) via the lossless `ra_ap_syntax` CST; `prettyplease` (the default)
//! normalises formatting to rustfmt style.
//!
//! Exit status is always 0 for a *reported* failure and non-zero only when the
//! bridge itself could not run (bad usage, unreadable file). The Elixir side
//! treats a non-zero exit as an error, so a parse failure must not use it.
//!
//! No `unwrap`/`expect` in production paths: every fallible step returns a
//! `Response::error` with a structured error the Elixir side can format.

mod ast;
mod compare;
mod from_json;
#[cfg(feature = "ra")]
mod ra_backend;
mod selftest;
mod span;
mod to_json;

use std::env;
use std::fs;
use std::io::{self, Write};
use std::process::ExitCode;

use ast::Response;

fn main() -> ExitCode {
    let args: Vec<String> = env::args().collect();

    let (mode, input_arg, backend) = match parse_args(&args) {
        Ok(parsed) => parsed,
        Err(message) => {
            emit(&Response::error("UsageError", message, None));
            return ExitCode::from(2);
        }
    };

    // `selftest` takes no input. Short-circuit before reading so that a caller
    // which forgets to close stdin cannot hang the bridge.
    if mode == "selftest" {
        emit(&selftest::run());
        return ExitCode::SUCCESS;
    }

    let input = match read_input(input_arg.as_deref()) {
        Ok(text) => text,
        Err(error) => {
            emit(&Response::error("IOError", error, None));
            return ExitCode::FAILURE;
        }
    };

    let response = match mode.as_str() {
        "parse" => parse(&input),
        "unparse" => unparse(&input),
        "fmt" => format_source_with(&input, &backend),
        other => Response::error("UsageError", format!("unknown mode `{other}`"), None),
    };

    emit(&response);
    ExitCode::SUCCESS
}

/// Extracts the mode and optional file argument.
///
/// Flags are ignored so that `--edition 2021` and friends can be added later
/// without breaking existing callers.
fn parse_args(args: &[String]) -> Result<(String, Option<String>, String), String> {
    let mut mode = "parse".to_string();
    let mut input: Option<String> = None;
    let mut backend = "prettyplease".to_string();
    let mut index = 1;

    while index < args.len() {
        let arg = &args[index];

        if arg.starts_with("--") {
            // `--backend <name>` is the only flag with a meaningful value;
            // every other flag is skipped along with its value so that future
            // options (e.g. `--edition 2024`) do not break existing callers.
            if arg == "--backend" {
                if let Some(value) = args.get(index + 1) {
                    backend = value.clone();
                }
            }

            index += 2;
            continue;
        }

        match arg.as_str() {
            "parse" | "unparse" | "fmt" | "selftest" => mode = arg.clone(),
            other => input = Some(other.to_string()),
        }

        index += 1;
    }

    Ok((mode, input, backend))
}

/// Reads the input payload from a file path.
///
/// The Elixir side always passes a real path: `Metastatic.Subprocess.run/4`
/// writes the payload to a temp file and appends it as the last argument. Stdin
/// is therefore never read — an absent path is a usage error rather than an
/// implicit `-` — so a misconfigured caller fails fast instead of blocking on a
/// pipe that will never be closed.
fn read_input(path: Option<&str>) -> Result<String, String> {
    match path {
        Some(path) => {
            fs::read_to_string(path).map_err(|error| format!("failed to read `{path}`: {error}"))
        }

        None => {
            Err("missing input file path (usage: metastatic-rust-parser <mode> <file>)".to_string())
        }
    }
}

/// Parses Rust source into the M1 JSON tree.
///
/// `syn::parse_file` only accepts a sequence of **items**, so a bare expression
/// such as `1 + 2` is rejected. Every other Metastatic adapter accepts one, and
/// the conformance suite uses `1 + 2` as its canonical sample, so a failed file
/// parse is retried as an expression before being reported.
fn parse(source: &str) -> Response {
    match syn::parse_file(source) {
        Ok(file) => respond_with(&to_json::file_to_node(&file)),

        Err(file_error) => match syn::parse_str::<syn::Expr>(source.trim()) {
            Ok(expression) => respond_with(&to_json::expr_to_node(&expression)),

            // Report the *file* error: it is the one that describes the input
            // the caller actually meant to send.
            Err(_) => {
                let line = file_error.span().start().line;
                Response::error("ParseError", file_error.to_string(), Some(line))
            }
        },
    }
}

/// Serialises a converted node, reporting a serialisation failure as an error.
fn respond_with<T: serde::Serialize>(document: &T) -> Response {
    match serde_json::to_value(document) {
        Ok(value) => Response::ast(value),
        Err(error) => Response::error(
            "SerializationError",
            format!("failed to serialise the AST: {error}"),
            None,
        ),
    }
}

/// Reifies an M1 JSON tree back into Rust source.
///
/// Accepts either a `File` document (the usual case) or a single node, which is
/// what `parse` returns for a bare expression such as `1 + 2`.
fn unparse(payload: &str) -> Response {
    let value: serde_json::Value = match serde_json::from_str(payload) {
        Ok(value) => value,
        Err(error) => return Response::error("JSONError", format!("invalid JSON: {error}"), None),
    };

    // A `File` document has `kind: "File"`; anything else is a bare node.
    if value.get("kind").and_then(|kind| kind.as_str()) == Some("File") {
        let document: ast::File = match serde_json::from_value(value) {
            Ok(document) => document,
            Err(error) => {
                return Response::error("JSONError", format!("invalid M1 document: {error}"), None)
            }
        };

        return match from_json::node_to_file(&document) {
            Ok(file) => Response::source_with_meta(
                prettyplease::unparse(&file),
                serde_json::json!({ "formatter": "prettyplease" }),
            ),
            Err(error) => Response::error(error.kind, error.msg, None),
        };
    }

    let node: ast::Node = match serde_json::from_value(value) {
        Ok(node) => node,
        Err(error) => {
            return Response::error("JSONError", format!("invalid M1 node: {error}"), None)
        }
    };

    match from_json::expression_to_source(&node) {
        Ok(source) => {
            Response::source_with_meta(source, serde_json::json!({ "formatter": "prettyplease" }))
        }
        Err(error) => Response::error(error.kind, error.msg, None),
    }
}

/// Parses and re-prints, normalising formatting.
/// Parses and re-prints, selecting the backend.
///
/// `ra` requires the `ra` feature; when it is not compiled in, or the source
/// does not parse losslessly, this falls back to `prettyplease` and says so in
/// the response metadata rather than failing.
fn format_source_with(source: &str, backend: &str) -> Response {
    if backend == "ra" {
        return format_with_ra(source);
    }

    match syn::parse_file(source) {
        Ok(file) => Response::source_with_meta(
            prettyplease::unparse(&file),
            serde_json::json!({ "formatter": "prettyplease" }),
        ),
        Err(error) => {
            let line = error.span().start().line;
            Response::error("ParseError", error.to_string(), Some(line))
        }
    }
}

#[cfg(feature = "ra")]
fn format_with_ra(source: &str) -> Response {
    match ra_backend::round_trip(source) {
        Some(printed) => Response::source_with_meta(
            printed,
            serde_json::json!({ "formatter": "ra_ap_syntax", "lossless": true }),
        ),
        None => {
            // Fall back rather than fail: a source the CST cannot reproduce
            // byte-for-byte is still printable by `prettyplease`.
            let mut response = format_source_with(source, "prettyplease");
            if let Response::Success(ref mut success) = response {
                success.meta = Some(serde_json::json!({
                    "formatter": "prettyplease",
                    "lossless": false,
                    "fallback_reason": "ra backend could not round-trip byte-exactly"
                }));
            }
            response
        }
    }
}

#[cfg(not(feature = "ra"))]
fn format_with_ra(source: &str) -> Response {
    let mut response = format_source_with(source, "prettyplease");
    if let Response::Success(ref mut success) = response {
        success.meta = Some(serde_json::json!({
            "formatter": "prettyplease",
            "lossless": false,
            "fallback_reason": "binary built without the `ra` feature"
        }));
    }
    response
}

/// Writes a response as a single JSON line.
///
/// A write failure cannot be reported through the protocol, so it is reported
/// on stderr and swallowed — the process still exits 0 so the caller sees the
/// empty stdout as a decode error rather than a crash.
fn emit(response: &Response) {
    match serde_json::to_string(response) {
        Ok(json) => {
            let stdout = io::stdout();
            let mut handle = stdout.lock();
            if handle.write_all(json.as_bytes()).is_err() {
                return;
            }
            let _ = handle.write_all(b"\n");
            let _ = handle.flush();
        }

        Err(error) => {
            eprintln!("metastatic-rust-parser: failed to encode response: {error}");
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn args(items: &[&str]) -> Vec<String> {
        items.iter().map(|item| item.to_string()).collect()
    }

    #[test]
    fn defaults_to_parse_mode_without_arguments() {
        let (mode, input, _backend) = parse_args(&args(&["bridge"])).expect("parse args");
        assert_eq!(mode, "parse");
        assert_eq!(input, None);
    }

    #[test]
    fn recognises_every_mode() {
        for mode in ["parse", "unparse", "fmt", "selftest"] {
            let (parsed, _, _backend) = parse_args(&args(&["bridge", mode])).expect("parse args");
            assert_eq!(parsed, mode);
        }
    }

    #[test]
    fn treats_the_last_bare_argument_as_the_input_path() {
        let (mode, input, _backend) =
            parse_args(&args(&["bridge", "parse", "/tmp/x.rs"])).expect("parse");
        assert_eq!(mode, "parse");
        assert_eq!(input.as_deref(), Some("/tmp/x.rs"));
    }

    #[test]
    fn ignores_long_flags_and_their_values() {
        let (mode, input, _backend) = parse_args(&args(&[
            "bridge",
            "parse",
            "--edition",
            "2021",
            "/tmp/x.rs",
        ]))
        .expect("parse");
        assert_eq!(mode, "parse");
        assert_eq!(input.as_deref(), Some("/tmp/x.rs"));
    }

    #[test]
    fn reads_the_backend_flag() {
        let (mode, _input, backend) =
            parse_args(&args(&["bridge", "fmt", "--backend", "ra"])).expect("parse");
        assert_eq!(mode, "fmt");
        assert_eq!(backend, "ra");
    }

    #[test]
    fn defaults_to_the_prettyplease_backend() {
        let (_mode, _input, backend) = parse_args(&args(&["bridge", "fmt"])).expect("parse");
        assert_eq!(backend, "prettyplease");
    }

    #[test]
    fn parse_reports_syntax_errors_with_a_line() {
        let response = parse("fn broken( {");
        match response {
            Response::Failure(failure) => {
                assert_eq!(failure.error.kind, "ParseError");
                assert!(
                    failure.error.line.is_some(),
                    "a syntax error must carry a line"
                );
            }
            other => panic!("expected a failure, got {other:?}"),
        }
    }

    #[test]
    fn parse_succeeds_on_valid_source() {
        let response = parse("fn main() {}\n");
        match response {
            Response::Success(success) => {
                assert!(success.ok);
                assert!(
                    success.ast.is_some(),
                    "a successful parse must carry an AST"
                );
            }
            other => panic!("expected a success, got {other:?}"),
        }
    }

    #[test]
    fn unparse_reports_invalid_json() {
        let response = unparse("not json");
        match response {
            Response::Failure(failure) => assert_eq!(failure.error.kind, "JSONError"),
            other => panic!("expected a failure, got {other:?}"),
        }
    }

    #[test]
    fn a_missing_path_is_a_usage_error_not_a_stdin_read() {
        // Regression guard: the bridge used to fall back to stdin, which hung
        // forever when a caller forgot to close the pipe.
        let error = read_input(None).expect_err("a missing path must fail");
        assert!(
            error.contains("missing input file path"),
            "unexpected: {error}"
        );
    }

    #[test]
    fn selftest_needs_no_input() {
        // `selftest` must be runnable with no file argument and no stdin.
        match selftest::run() {
            Response::Success(success) => assert!(success.ok),
            other => panic!("expected a success, got {other:?}"),
        }
    }

    #[test]
    fn unparse_round_trips_through_parse() {
        let source = "fn add(x: i32, y: i32) -> i32 {\n    x + y\n}\n";

        let ast = match parse(source) {
            Response::Success(success) => success.ast.expect("ast"),
            other => panic!("expected a success, got {other:?}"),
        };

        let payload = serde_json::to_string(&ast).expect("serialise");

        match unparse(&payload) {
            Response::Success(success) => {
                let printed = success.source.expect("source");
                assert!(printed.contains("fn add"), "unexpected output: {printed}");
            }
            other => panic!("expected a success, got {other:?}"),
        }
    }

    #[test]
    fn fmt_normalises_formatting() {
        let response = format_source_with("fn  main( ){let x=1;}", "prettyplease");
        match response {
            Response::Success(success) => {
                let printed = success.source.expect("source");
                assert!(
                    printed.contains("fn main()"),
                    "unexpected output: {printed}"
                );
            }
            other => panic!("expected a success, got {other:?}"),
        }
    }
}
