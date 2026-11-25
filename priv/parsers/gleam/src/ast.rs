//! The M1 representation: a serde-serialisable mirror of the Gleam AST.
//!
//! `gleam_core::ast`'s node types are not `Serialize`, and adding `serde` to
//! them would mean forking the compiler. Instead — exactly as the Rust and Go
//! bridges do — this module defines a plain data mirror that:
//!
//! * serialises to JSON with `serde`,
//! * carries an explicit `kind` tag on every node so the Elixir side can match
//!   on it without knowing Gleam's Rust type names,
//! * carries a `span` on every node so MetaAST nodes can be given
//!   `line`/`col`/`end_line`/`end_col`.
//!
//! The shape is deliberately shallow: a node is `{kind, span, ...fields}`.
//! This is the contract `Metastatic.Adapters.Gleam.ToMeta` pattern-matches
//! against.
//!
//! Only the constructs listed in `README.md` are modelled. Anything else is
//! reported as `Node::Unsupported`, which the Elixir side maps to a
//! `:language_specific` node carrying the original source text — the same
//! 100%-fidelity escape hatch the Go and Rust adapters use.

use serde::{Deserialize, Serialize};

/// A source position, 1-based on both axes, end-exclusive in columns.
///
/// `gleam_core` reports byte offsets (`SrcSpan`), which are converted here so
/// that every adapter in Metastatic speaks the same position language.
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
    /// point at) and as a fallback for a byte offset outside the source.
    pub const UNKNOWN: Span = Span {
        line: 0,
        col: 0,
        end_line: 0,
        end_col: 0,
    };

    /// True when this span carries no usable position.
    #[allow(dead_code)]
    pub fn is_unknown(&self) -> bool {
        self.line == 0 && self.col == 0
    }
}

impl Default for Span {
    fn default() -> Self {
        Span::UNKNOWN
    }
}

/// A single M1 node.
///
/// `kind` is the discriminant the Elixir adapter matches on; the remaining
/// fields are kind-specific and `Option`al so that one struct covers the whole
/// surface without a fragile enum-per-variant serde representation.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Node {
    /// The Gleam construct, e.g. `"Fn"`, `"BinOp"`, `"Case"`, `"Ident"`.
    pub kind: String,
    /// Source position of the node, or [`Span::UNKNOWN`].
    #[serde(default)]
    pub span: Span,
    /// The operator, identifier, label, module or declaration name.
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub name: Option<String>,
    /// The literal payload, for `kind == "Int" | "Float" | "String"`.
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub value: Option<LiteralValue>,
    /// Child nodes, in source order.
    #[serde(skip_serializing_if = "Vec::is_empty", default)]
    pub children: Vec<Node>,
    /// The declared or annotated type.
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub type_node: Option<Box<Node>>,
    /// The binding pattern of a `let`, `use` or `case` clause.
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub pattern: Option<Box<Node>>,
    /// The original source text, for `kind == "Unsupported"`.
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub source: Option<String>,
    /// `pub` on a declaration, or `pub` on a record field.
    #[serde(skip_serializing_if = "std::ops::Not::not", default)]
    pub public: bool,
    /// `opaque` on an external type.
    #[serde(skip_serializing_if = "std::ops::Not::not", default)]
    pub opaque: bool,
    /// The `_` prefix of a discarded argument or assignment.
    #[serde(skip_serializing_if = "std::ops::Not::not", default)]
    pub discard: bool,
    /// Kind-specific scalars that do not deserve a top-level field: the raw
    /// spelling of a literal, the label of a call argument, the target of a
    /// `use` expression, the spread flag of a record update, and so on.
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub extra: Option<serde_json::Value>,
}

impl Node {
    /// Builds a node of `kind` with a span and no children.
    pub fn new(kind: impl Into<String>, span: Span) -> Node {
        Node {
            kind: kind.into(),
            span,
            name: None,
            value: None,
            children: Vec::new(),
            type_node: None,
            pattern: None,
            source: None,
            public: false,
            opaque: false,
            discard: false,
            extra: None,
        }
    }

    /// Builds a node of `kind` carrying children.
    #[allow(dead_code)]
    pub fn with_children(kind: impl Into<String>, span: Span, children: Vec<Node>) -> Node {
        Node {
            children,
            ..Node::new(kind, span)
        }
    }

    /// Builds a node that preserves source text verbatim.
    #[allow(dead_code)]
    ///
    /// This is the escape hatch for constructs outside the modelled surface:
    /// the Elixir side turns it into `:language_specific` and `from_json`
    /// restores the text unchanged, so unsupported syntax still round-trips.
    pub fn unsupported(span: Span, source: impl Into<String>) -> Node {
        Node {
            source: Some(source.into()),
            ..Node::new("Unsupported", span)
        }
    }

    /// Sets the `name` field.
    #[allow(dead_code)]
    pub fn with_name(mut self, name: impl Into<String>) -> Node {
        self.name = Some(name.into());
        self
    }
}

/// A literal's value, tagged by subtype so the Elixir side can map it onto
/// MetaAST's `{:literal, [subtype: …], value}` without re-parsing.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "subtype", content = "value", rename_all = "snake_case")]
pub enum LiteralValue {
    /// Integers are kept as their source spelling: Gleam integers are
    /// arbitrary precision, so `1 <<< 200` has no `i64` representation.
    Integer(String),
    /// Floats keep their source spelling for the same reason.
    Float(String),
    String(String),
}

/// The top-level M1 document: a module's definitions plus the comments that
/// precede the first one.
///
/// Only the `vendored` build constructs one (see `to_json`); the
/// `external-gleam` build has no parser, so the type is declared but unused
/// there. `allow(dead_code)` keeps that build warning-free without hiding a
/// real problem in the build that does use it.
#[allow(dead_code)]
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Module {
    pub kind: String,
    pub span: Span,
    /// Module-level comments (`//// …`), already stripped of their markers.
    #[serde(skip_serializing_if = "Vec::is_empty", default)]
    pub comments: Vec<String>,
    pub children: Vec<Node>,
}

impl Module {
    /// Wraps a list of top-level definitions.
    #[allow(dead_code)]
    pub fn new(span: Span, comments: Vec<String>, children: Vec<Node>) -> Module {
        Module {
            kind: "Module".to_string(),
            span,
            comments,
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
/// have to guess.
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

/// A failed bridge response.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Failure {
    pub ok: bool,
    pub error: ErrorInfo,
}

impl From<ErrorInfo> for Failure {
    fn from(error: ErrorInfo) -> Failure {
        Failure { ok: false, error }
    }
}

/// A structured error the Elixir side formats with
/// `Metastatic.Adapter.Bridge.format_error/1`.
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

    /// A success carrying generated source.
    pub fn source(text: impl Into<String>) -> Response {
        Response::source_with_meta(text, serde_json::json!({ "formatter": "gleam-format" }))
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

    /// A failure built from an already-constructed [`ErrorInfo`].
    pub fn failure(info: ErrorInfo) -> Response {
        Response::Failure(info.into())
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
            "Ident",
            Span {
                line: 2,
                col: 5,
                end_line: 2,
                end_col: 6,
            },
        );

        let json = serde_json::to_value(&node).expect("serialise");
        assert_eq!(json["kind"], "Ident");
        assert_eq!(json["span"]["line"], 2);
        // Absent optional fields must not appear as `null`.
        assert!(json.get("value").is_none());
        assert!(json.get("children").is_none());
        assert!(json.get("public").is_none());
    }

    #[test]
    fn literal_value_is_tagged_by_subtype() {
        let value = LiteralValue::Integer("42".to_string());
        let json = serde_json::to_value(&value).expect("serialise");
        assert_eq!(json["subtype"], "integer");
        assert_eq!(json["value"], "42");
    }

    #[test]
    fn unsupported_node_preserves_source() {
        let node = Node::unsupported(Span::UNKNOWN, "todo as \"later\"");
        assert_eq!(node.kind, "Unsupported");
        assert_eq!(node.source.as_deref(), Some("todo as \"later\""));
    }

    #[test]
    fn response_round_trips_through_json() {
        // `Response` is write-only (the bridge never decodes its own output),
        // so the round-trip is checked against the `Failure` payload it emits
        // rather than against `Response` itself.
        let response = Response::error("ParseError", "unexpected token", Some(3));
        let json = serde_json::to_string(&response).expect("serialise");
        let decoded: Failure = serde_json::from_str(&json).expect("deserialise");
        assert_eq!(decoded.ok, false);
        assert_eq!(decoded.error.kind, "ParseError");
        assert_eq!(decoded.error.line, Some(3));
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
