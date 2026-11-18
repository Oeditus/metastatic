//! The M1 representation: a serde-serialisable mirror of the Rust AST.
//!
//! `syn`'s node types are not `Serialize`, and adding `serde` to them would mean
//! either a fork or a wrapper type per node. Instead — exactly as the Java
//! adapter does with `com.sun.source.tree` — this module defines a plain data
//! mirror that:
//!
//! * serialises to JSON with `serde`,
//! * carries an explicit `kind` tag on every node so the Elixir side can match
//!   on it without knowing Rust's type names,
//! * carries a `span` on every node so MetaAST nodes can be given `line`/`col`.
//!
//! The shape is deliberately shallow: a node is `{kind, span, ...fields}`. This
//! is the contract `RUST_IMPL.md` §2 calls "M1 shape", and it is what
//! `Metastatic.Adapters.Rust.ToMeta` pattern-matches against.
//!
//! Only the constructs listed in `RUST_IMPL.md` §4 are modelled. Anything else
//! is reported as `Node::Unsupported`, which the Elixir side maps to a
//! `:language_specific` node carrying the original source text — the same
//! 100%-fidelity escape hatch the SQL adapter uses.

use serde::{Deserialize, Serialize};

/// A source position, 1-based on both axes.
///
/// `proc-macro2` reports 1-based lines and 0-based columns; the column is
/// normalised to 1-based here so that it agrees with Elixir's `:col` convention
/// used by the other adapters.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct Span {
    pub line: usize,
    pub col: usize,
    pub end_line: usize,
    pub end_col: usize,
}

impl Span {
    /// A span that carries no position information.
    ///
    /// Used for nodes synthesised by `from_json` (which have no source text to
    /// point at) and as a fallback when `span-locations` yields 0.
    pub const UNKNOWN: Span = Span {
        line: 0,
        col: 0,
        end_line: 0,
        end_col: 0,
    };

    /// True when this span carries no usable position.
    pub fn is_unknown(&self) -> bool {
        self.line == 0 && self.col == 0
    }
}

/// A single M1 node.
///
/// `kind` is the discriminant the Elixir adapter matches on; the remaining
/// fields are kind-specific and `Option`al so that one struct covers the whole
/// surface without a fragile enum-per-variant serde representation.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Node {
    /// The Rust AST node kind, e.g. `"Binary"`, `"Function"`, `"Literal"`.
    pub kind: String,
    /// Source position of the node, or `Span::UNKNOWN`.
    #[serde(default = "Span::default_unknown")]
    pub span: Span,
    /// The literal value, for `kind == "Literal"`.
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub value: Option<LiteralValue>,
    /// The operator or name, for operators, calls, imports and declarations.
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub name: Option<String>,
    /// Child nodes, in source order.
    #[serde(skip_serializing_if = "Vec::is_empty", default)]
    pub children: Vec<Node>,
    /// A pattern node, for `let`, `match` arms and function parameters.
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub pattern: Option<Box<Node>>,
    /// A type node, for parameters, fields and `type` aliases.
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub type_node: Option<Box<Node>>,
    /// The original source text, for `kind == "Unsupported"`.
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub source: Option<String>,
    /// Whether this expression statement was terminated by a semicolon.
    ///
    /// Load-bearing: a tail expression is a block's value, a `;`-terminated
    /// one discards it. Omitted from JSON when `false` to keep the payload
    /// small.
    #[serde(skip_serializing_if = "std::ops::Not::not", default)]
    pub semi: bool,

    /// `true` when a binding pattern is declared `mut`.
    ///
    /// Distinct from `semi` (statement terminator). Omitted from JSON when
    /// absent so the payload stays small.
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub mutability: Option<bool>,
}

impl Default for Span {
    fn default() -> Self {
        Span::UNKNOWN
    }
}

impl Span {
    /// serde default for the `span` field.
    fn default_unknown() -> Span {
        Span::UNKNOWN
    }
}

impl Node {
    /// Builds a node of `kind` with a span and no children.
    pub fn new(kind: impl Into<String>, span: Span) -> Node {
        Node {
            kind: kind.into(),
            span,
            value: None,
            name: None,
            children: Vec::new(),
            pattern: None,
            type_node: None,
            source: None,
            semi: false,
            mutability: None,
        }
    }

    /// Builds a node of `kind` carrying children.
    pub fn with_children(kind: impl Into<String>, span: Span, children: Vec<Node>) -> Node {
        Node {
            children,
            ..Node::new(kind, span)
        }
    }

    /// Builds a node that preserves source text verbatim.
    ///
    /// This is the escape hatch for constructs outside `RUST_IMPL.md` §4: the
    /// Elixir side turns it into `:language_specific` and `from_json` restores
    /// the text unchanged, so unsupported syntax still round-trips.
    pub fn unsupported(span: Span, source: impl Into<String>) -> Node {
        Node {
            source: Some(source.into()),
            ..Node::new("Unsupported", span)
        }
    }
}

/// A literal's value, tagged by subtype so the Elixir side can map it onto
/// MetaAST's `{:literal, [subtype: …], value}` without re-parsing.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "subtype", content = "value", rename_all = "snake_case")]
pub enum LiteralValue {
    Integer(i64),
    /// Integers that do not fit in `i64` are kept as their source text.
    BigInteger(String),
    Float(f64),
    String(String),
    Boolean(bool),
    Char(String),
    /// Byte strings carry their bytes as an integer array.
    Bytes(Vec<u8>),
    /// Anything else (`b'x'` suffixes we do not model, etc.).
    Other(String),
}

/// The top-level M1 document: a file's items plus any leading attributes.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct File {
    pub kind: String,
    pub span: Span,
    pub children: Vec<Node>,
}

impl File {
    /// Wraps a list of top-level items.
    pub fn new(span: Span, children: Vec<Node>) -> File {
        File {
            kind: "File".to_string(),
            span,
            children,
        }
    }
}

/// The JSON envelope every bridge mode emits.
///
/// Matches `Metastatic.Adapter.Bridge`'s canonical shape, so the Elixir side
/// needs no bespoke decoder:
///
/// ```json
/// {"ok": true,  "ast": {...}}
/// {"ok": true,  "source": "..."}
/// {"ok": false, "error": {"type": "...", "msg": "...", "line": 3}}
/// ```
///
/// Serialisation is hand-written rather than derived: the two variants share
/// the `ok` key but differ in every other one, so a derived untagged enum would
/// have to guess. Deserialisation is likewise explicit and dispatches on `ok`.
#[derive(Debug, Clone, PartialEq)]
pub enum Response {
    Success(Success),
    Failure(Failure),
}

impl Serialize for Response {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        match self {
            Response::Success(success) => success.serialize(serializer),
            Response::Failure(failure) => failure.serialize(serializer),
        }
    }
}

impl<'de> Deserialize<'de> for Response {
    fn deserialize<D: serde::Deserializer<'de>>(deserializer: D) -> Result<Response, D::Error> {
        // Read into a map first so `ok` can be inspected before committing to
        // a variant. Deserialising straight into `Success` would succeed for a
        // failure payload, because every one of its fields is optional.
        let value = serde_json::Value::deserialize(deserializer)?;

        let ok = value
            .get("ok")
            .and_then(serde_json::Value::as_bool)
            .ok_or_else(|| serde::de::Error::missing_field("ok"))?;

        if ok {
            serde_json::from_value(value)
                .map(Response::Success)
                .map_err(serde::de::Error::custom)
        } else {
            serde_json::from_value(value)
                .map(Response::Failure)
                .map_err(serde::de::Error::custom)
        }
    }
}

/// A successful bridge response.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Success {
    pub ok: bool,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub ast: Option<serde_json::Value>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub source: Option<String>,
    /// Extra bridge diagnostics (formatter used, warnings, …).
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub meta: Option<serde_json::Value>,
}

/// A failed bridge response. Distinguished from [`Success`] by `error`.
///
/// `ok` is deserialised here (and not in [`Success`]) so that serde's untagged
/// resolution has a *required* field to discriminate on. Without it, `Success`
/// matches every object — all of its fields are optional — and a failure
/// decodes as an empty success.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Failure {
    pub ok: bool,
    pub error: ErrorInfo,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ErrorInfo {
    #[serde(rename = "type")]
    pub kind: String,
    pub msg: String,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub line: Option<usize>,
}

impl Response {
    /// A parse/unparse success carrying an AST.
    pub fn ast(value: serde_json::Value) -> Response {
        Response::Success(Success {
            ok: true,
            ast: Some(value),
            source: None,
            meta: None,
        })
    }

    /// A success carrying generated source plus bridge metadata.
    pub fn source_with_meta(text: impl Into<String>, meta: serde_json::Value) -> Response {
        Response::Success(Success {
            ok: true,
            ast: None,
            source: Some(text.into()),
            meta: Some(meta),
        })
    }

    /// A failure with a structured error.
    pub fn error(kind: impl Into<String>, msg: impl Into<String>, line: Option<usize>) -> Response {
        Response::Failure(Failure {
            ok: false,
            error: ErrorInfo {
                kind: kind.into(),
                msg: msg.into(),
                line,
            },
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn span_unknown_is_recognised() {
        assert!(Span::UNKNOWN.is_unknown());
        assert!(!Span {
            line: 1,
            col: 1,
            end_line: 1,
            end_col: 2
        }
        .is_unknown());
    }

    #[test]
    fn node_serialises_with_kind_and_span() {
        let node = Node::new(
            "Literal",
            Span {
                line: 2,
                col: 5,
                end_line: 2,
                end_col: 6,
            },
        );

        let json = serde_json::to_value(&node).expect("serialise");
        assert_eq!(json["kind"], "Literal");
        assert_eq!(json["span"]["line"], 2);
        // Absent optional fields must not appear as `null`.
        assert!(json.get("value").is_none());
        assert!(json.get("children").is_none());
    }

    #[test]
    fn literal_value_is_tagged_by_subtype() {
        let value = LiteralValue::Integer(42);
        let json = serde_json::to_value(&value).expect("serialise");
        assert_eq!(json["subtype"], "integer");
        assert_eq!(json["value"], 42);
    }

    #[test]
    fn unsupported_node_preserves_source() {
        let node = Node::unsupported(Span::UNKNOWN, "asm!(\"nop\")");
        assert_eq!(node.kind, "Unsupported");
        assert_eq!(node.source.as_deref(), Some("asm!(\"nop\")"));
    }

    #[test]
    fn response_round_trips_through_json() {
        let response = Response::error("ParseError", "unexpected token", Some(3));
        let json = serde_json::to_string(&response).expect("serialise");
        let decoded: Response = serde_json::from_str(&json).expect("deserialise");
        assert_eq!(decoded, response);
    }

    #[test]
    fn success_round_trips_through_json() {
        let response = Response::ast(serde_json::json!({ "kind": "File" }));
        let json = serde_json::to_string(&response).expect("serialise");
        let decoded: Response = serde_json::from_str(&json).expect("deserialise");
        assert_eq!(decoded, response);
    }

    #[test]
    fn wire_format_keeps_the_ok_flag() {
        // The Elixir side's `Bridge.decode/1` keys off `"ok"`, so the field
        // must still be emitted even though it is not deserialised.
        let json = serde_json::to_string(&Response::error("E", "m", None)).expect("serialise");
        assert!(
            json.contains("\"ok\":false"),
            "unexpected wire format: {json}"
        );

        let json = serde_json::to_string(&Response::ast(serde_json::json!({}))).expect("serialise");
        assert!(
            json.contains("\"ok\":true"),
            "unexpected wire format: {json}"
        );
    }
}
