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

fn parse_sql(sql: &str, dialect_name: &str) -> serde_json::Value {
    let dialect = get_dialect(dialect_name);
    let dialect_ref = dialect.as_ref();

    // 1. Try statement parsing
    match Parser::parse_sql(dialect_ref, sql) {
        Ok(statements) if !statements.is_empty() => {
            match serde_json::to_value(&statements) {
                Ok(val) => json!({ "ok": true, "ast": val }),
                Err(e) => json!({
                    "ok": false,
                    "error": { "type": "SerializationError", "msg": e.to_string() }
                }),
            }
        }
        _ => {
            // 2. Fall back to expression parsing
            match Parser::new(dialect_ref).try_with_sql(sql) {
                Ok(mut parser) => match parser.parse_expr() {
                    Ok(expr) => {
                        let next_token = parser.peek_token();
                        if next_token.token != Token::EOF && next_token != Token::EOF {
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
