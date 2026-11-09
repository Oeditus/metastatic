use sqlparser::ast::{Expr, Statement};
use sqlparser::dialect::{
    AnsiDialect, BigQueryDialect, ClickHouseDialect, DuckDbDialect, GenericDialect,
    MySqlDialect, PostgreSqlDialect, SQLiteDialect, SnowflakeDialect, Dialect,
};
use sqlparser::tokenizer::Token;
use sqlparser::parser::Parser;
use serde_json::json;
use std::env;
use std::fs;
use std::io::{self, Read};

fn get_dialect(name: &str) -> Box<dyn Dialect> {
    match name.to_lowercase().as_str() {
        "postgres" | "postgresql" => Box::new(PostgreSqlDialect {}),
        "mysql" => Box::new(MySqlDialect {}),
        "sqlite" => Box::new(SQLiteDialect {}),
        "ansi" => Box::new(AnsiDialect {}),
        "snowflake" => Box::new(SnowflakeDialect {}),
        "bigquery" => Box::new(BigQueryDialect {}),
        "duckdb" => Box::new(DuckDbDialect {}),
        "clickhouse" => Box::new(ClickHouseDialect {}),
        _ => Box::new(GenericDialect {}),
    }
}

/// Split a SQL script into individual statements on top-level semicolons.
///
/// Statement boundaries are only recognised when the semicolon sits outside
/// of string literals, dollar-quoted bodies (`$$ ... $$`, `$tag$ ... $tag$`),
/// quoted identifiers, and comments. This lets the parser handle scripts that
/// contain constructs `sqlparser` cannot model (e.g. `ALTER DEFAULT
/// PRIVILEGES`, `DO $$ ... $$`) by parsing each statement independently and
/// skipping the ones that are unsupported.
fn split_statements(sql: &str) -> Vec<String> {
    let bytes = sql.as_bytes();
    let mut statements = Vec::new();
    let mut start = 0usize;
    let mut i = 0usize;

    while i < bytes.len() {
        match bytes[i] {
            // Line comment: skip to end of line.
            b'-' if i + 1 < bytes.len() && bytes[i + 1] == b'-' => {
                while i < bytes.len() && bytes[i] != b'\n' {
                    i += 1;
                }
            }
            // Block comment: skip to closing `*/`.
            b'/' if i + 1 < bytes.len() && bytes[i + 1] == b'*' => {
                i += 2;
                while i + 1 < bytes.len() && !(bytes[i] == b'*' && bytes[i + 1] == b'/') {
                    i += 1;
                }
                i = (i + 2).min(bytes.len());
            }
            // Single-quoted string literal (with `''` escape).
            b'\'' => {
                i += 1;
                while i < bytes.len() {
                    if bytes[i] == b'\'' {
                        if i + 1 < bytes.len() && bytes[i + 1] == b'\'' {
                            i += 2;
                            continue;
                        }
                        break;
                    }
                    i += 1;
                }
                i += 1;
            }
            // Double-quoted identifier (with `""` escape).
            b'"' => {
                i += 1;
                while i < bytes.len() {
                    if bytes[i] == b'"' {
                        if i + 1 < bytes.len() && bytes[i + 1] == b'"' {
                            i += 2;
                            continue;
                        }
                        break;
                    }
                    i += 1;
                }
                i += 1;
            }
            // Dollar-quoted string: `$$ ... $$` or `$tag$ ... $tag$`.
            b'$' => {
                if let Some(delim_len) = dollar_quote_delimiter_len(&bytes[i..]) {
                    let delimiter = &sql[i..i + delim_len];
                    i += delim_len;
                    match sql[i..].find(delimiter) {
                        Some(offset) => i += offset + delim_len,
                        None => i = bytes.len(),
                    }
                } else {
                    i += 1;
                }
            }
            // Top-level statement separator.
            b';' => {
                statements.push(sql[start..i].to_string());
                start = i + 1;
                i += 1;
            }
            _ => i += 1,
        }
    }

    if start < sql.len() {
        statements.push(sql[start..].to_string());
    }

    statements
        .into_iter()
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .collect()
}

/// Returns the byte length of a dollar-quote opening delimiter at the start of
/// `bytes` (either `$$` or `$tag$`), or `None` when `bytes` does not start one.
fn dollar_quote_delimiter_len(bytes: &[u8]) -> Option<usize> {
    if bytes.first() != Some(&b'$') {
        return None;
    }

    let mut idx = 1usize;
    while idx < bytes.len() {
        match bytes[idx] {
            b'$' => return Some(idx + 1),
            // Dollar-quote tags are identifiers: letters, digits, underscores,
            // and must not start with a digit.
            b'a'..=b'z' | b'A'..=b'Z' | b'_' => idx += 1,
            b'0'..=b'9' if idx > 1 => idx += 1,
            _ => return None,
        }
    }

    None
}

/// Serializes a list of parsed statements into the success payload.
fn statements_payload(statements: &[Statement]) -> serde_json::Value {
    match serde_json::to_value(statements) {
        Ok(val) => json!({ "ok": true, "ast": val }),
        Err(e) => json!({
            "ok": false,
            "error": { "type": "SerializationError", "msg": e.to_string() }
        }),
    }
}

/// Parses a script statement-by-statement, keeping the statements that
/// `sqlparser` understands and reporting the rest as `unsupported`.
///
/// This is the fallback for scripts that mix supported statements with
/// dialect constructs the crate does not model yet.
fn parse_statement_wise(sql: &str, dialect_ref: &dyn Dialect) -> Option<serde_json::Value> {
    let chunks = split_statements(sql);

    if chunks.len() < 2 {
        return None;
    }

    let mut statements: Vec<Statement> = Vec::new();
    let mut unsupported: Vec<serde_json::Value> = Vec::new();

    for chunk in chunks {
        match Parser::parse_sql(dialect_ref, &chunk) {
            Ok(parsed) if !parsed.is_empty() => statements.extend(parsed),
            _ => unsupported.push(json!({
                "source": chunk,
                "reason": "unsupported_statement"
            })),
        }
    }

    if statements.is_empty() {
        return None;
    }

    match serde_json::to_value(&statements) {
        Ok(val) => {
            let mut payload = json!({ "ok": true, "ast": val });
            if !unsupported.is_empty() {
                if let serde_json::Value::Object(ref mut map) = payload {
                    map.insert("unsupported".to_string(), json!(unsupported));
                }
            }
            Some(payload)
        }
        Err(_) => None,
    }
}

fn parse_sql(sql: &str, dialect_name: &str) -> serde_json::Value {
    let dialect = get_dialect(dialect_name);
    let dialect_ref = dialect.as_ref();

    // 1. Try statement parsing
    match Parser::parse_sql(dialect_ref, sql) {
        Ok(statements) if !statements.is_empty() => statements_payload(&statements),
        _ => {
            // 2. Retry statement-by-statement so that a single unsupported
            //    statement (e.g. `ALTER DEFAULT PRIVILEGES`, `DO $$ ... $$`)
            //    does not discard the rest of the script.
            if let Some(payload) = parse_statement_wise(sql, dialect_ref) {
                return payload;
            }

            // 3. Fall back to expression parsing
            match Parser::new(dialect_ref).try_with_sql(sql) {
                Ok(mut parser) => match parser.parse_expr() {
                    Ok(expr) => {
                        let next_token = parser.peek_token();
                        if next_token.token != Token::EOF {
                            json!({
                                "ok": false,
                                "error": { "type": "ParseError", "msg": format!("Unexpected trailing token: {:?}", next_token) }
                            })
                        } else {
                            match serde_json::to_value(&expr) {
                                Ok(expr_val) => json!({
                                    "ok": true,
                                    "ast": { "Expr": expr_val }
                                }),
                                Err(e) => json!({
                                    "ok": false,
                                    "error": { "type": "SerializationError", "msg": e.to_string() }
                                }),
                            }
                        }
                    }
                    Err(e) => json!({
                        "ok": false,
                        "error": { "type": "ParseError", "msg": e.to_string() }
                    }),
                },
                Err(e) => json!({
                    "ok": false,
                    "error": { "type": "ParseError", "msg": e.to_string() }
                }),
            }
        }
    }
}

fn ensure_spans(val: &mut serde_json::Value) {
    let dummy_span = json!({
        "start": {"line": 1, "column": 1},
        "end": {"line": 1, "column": 1}
    });

    match val {
        serde_json::Value::Object(map) => {
            if let Some(v) = map.get_mut("Value") {
                if let serde_json::Value::Object(inner) = v {
                    if !inner.contains_key("span") {
                        inner.insert("span".to_string(), dummy_span.clone());
                    }
                }
            }
            if let Some(v) = map.get_mut("Identifier") {
                if let serde_json::Value::Object(inner) = v {
                    if !inner.contains_key("span") {
                        inner.insert("span".to_string(), dummy_span.clone());
                    }
                }
            }
            for (_, v) in map.iter_mut() {
                ensure_spans(v);
            }
        }
        serde_json::Value::Array(arr) => {
            for v in arr.iter_mut() {
                ensure_spans(v);
            }
        }
        _ => {}
    }
}

fn unparse_ast(json_val: serde_json::Value) -> serde_json::Value {
    let mut root = match json_val.get("ast") {
        Some(inner) => inner.clone(),
        None => json_val,
    };

    ensure_spans(&mut root);

    // Case 1: Wrapped expression {"Expr": ...}
    if let Some(expr_val) = root.get("Expr") {
        match serde_json::from_value::<Expr>(expr_val.clone()) {
            Ok(expr) => return json!({ "ok": true, "source": expr.to_string() }),
            Err(e) => return json!({
                "ok": false,
                "error": { "type": "UnparseError", "msg": format!("Failed to parse Expr: {}", e) }
            }),
        }
    }

    // Case 2: Direct expression object (e.g. {"BinaryOp": ...})
    if root.is_object() && (root.get("BinaryOp").is_some() || root.get("Value").is_some() || root.get("Identifier").is_some()) {
        if let Ok(expr) = serde_json::from_value::<Expr>(root.clone()) {
            return json!({ "ok": true, "source": expr.to_string() });
        }
    }

    // Case 3: List of statements
    if let Ok(statements) = serde_json::from_value::<Vec<Statement>>(root.clone()) {
        let unparsed = statements
            .iter()
            .map(|s| s.to_string())
            .collect::<Vec<_>>()
            .join(";\n");
        return json!({ "ok": true, "source": unparsed });
    }

    // Case 4: Single statement
    if let Ok(statement) = serde_json::from_value::<Statement>(root.clone()) {
        return json!({ "ok": true, "source": statement.to_string() });
    }

    json!({
        "ok": false,
        "error": { "type": "UnparseError", "msg": "Invalid AST format for unparsing" }
    })
}

fn read_input(arg: Option<&String>) -> Result<String, String> {
    match arg {
        Some(path) if path != "-" => {
            fs::read_to_string(path).map_err(|e| format!("Failed to read file {}: {}", path, e))
        }
        _ => {
            let mut buffer = String::new();
            io::stdin()
                .read_to_string(&mut buffer)
                .map_err(|e| format!("Failed to read from stdin: {}", e))?;
            Ok(buffer)
        }
    }
}

fn main() {
    let args: Vec<String> = env::args().collect();

    let mut mode = "parse";
    let mut dialect = "generic";
    let mut file_arg: Option<&String> = None;

    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "parse" => {
                mode = "parse";
            }
            "unparse" => {
                mode = "unparse";
            }
            "--dialect" => {
                if i + 1 < args.len() {
                    i += 1;
                    dialect = &args[i];
                }
            }
            "--unparse" => {
                mode = "unparse";
            }
            arg if !arg.starts_with("--") => {
                file_arg = Some(&args[i]);
            }
            _ => {}
        }
        i += 1;
    }

    let input = match read_input(file_arg) {
        Ok(content) => content,
        Err(e) => {
            let res = json!({
                "ok": false,
                "error": { "type": "IOError", "msg": e }
            });
            println!("{}", res);
            return;
        }
    };

    let result = if mode == "unparse" {
        match serde_json::from_str::<serde_json::Value>(&input) {
            Ok(json_val) => unparse_ast(json_val),
            Err(e) => json!({
                "ok": false,
                "error": { "type": "JSONError", "msg": format!("Invalid JSON: {}", e) }
            }),
        }
    } else {
        parse_sql(&input, dialect)
    };

    println!("{}", result);
}
