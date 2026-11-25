//! M1 JSON → Gleam source.
//!
//! The inverse of [`crate::to_json`]. It renders the M1 mirror back to source
//! text, which is what makes the adapter's `from_meta/2` + `unparse/1` pair
//! work: Metastatic reifies MetaAST into M1, then asks this module for source.
//!
//! ## Why render text rather than rebuild the AST
//!
//! `gleam_core`'s AST is not constructible from outside the crate in a
//! meaningful way — `UntypedModule` carries `Names`, `CompiledCase` and other
//! type-checker scaffolding that a parser never fills in. Building one by hand
//! to hand to `gleam_format::pretty/3` would produce a tree the printer has
//! never seen.
//!
//! Rendering source text and then running `gleam format`'s own printer over it
//! gives the same guarantee with none of that risk: the output is parsed and
//! printed by the real formatter, so it is valid Gleam by construction and
//! formatted exactly as `gleam format` would format it.
//!
//! ## Fidelity
//!
//! The renderer is driven by the M1 mirror, so every construct `to_json`
//! emits is reproduced. Where the mirror carries more than the source did
//! (spans, `implementations`, `purity`) the renderer ignores it; where it
//! carries less (comment placement) the formatter's normalisation applies.
//! Round-trip fidelity is therefore *semantic*: re-parsing the output yields
//! an equivalent M1, which is what the adapter's tests assert.

#[cfg(feature = "vendored")]
use camino::Utf8PathBuf;
#[cfg(feature = "vendored")]
use ecow::EcoString;

use crate::ast::ErrorInfo;

/// Renders an M1 JSON document as formatted Gleam source.
pub fn render(value: &serde_json::Value) -> Result<String, ErrorInfo> {
    let module = module_from_json(value)?;
    let unformatted = module.render();

    // A bare expression is not a module, so `gleam format` would reject it.
    // It is already rendered at its natural width, so returning it directly is
    // both correct and cheaper.
    if module.bare_expression.is_some() {
        return Ok(unformatted);
    }

    format_source(&unformatted)
}

/// Formats Gleam source with `gleam format`'s own printer.
///
/// The source is parsed first, so a syntax error is reported the same way
/// `parse` reports it rather than as a printer failure.
///
/// Two implementations, chosen at compile time:
///
///   * the `vendored` build calls `gleam_format::pretty/3` in-process — no
///     subprocess, no `gleam` toolchain;
///   * the `external-gleam` build shells out to `gleam format --stdin`, which
///     is the same printer behind the same CLI the user already has.
///
/// Both produce identical output for identical input: `gleam format` *is*
/// `gleam_format::pretty/3` plus argument handling.
#[cfg(feature = "vendored")]
pub fn format_source(source: &str) -> Result<String, ErrorInfo> {
    let path = Utf8PathBuf::from("metastatic_input.gleam");
    let eco = EcoString::from(source);
    let mut out = String::new();

    gleam_format::pretty(&mut out, &eco, &path).map_err(|error| {
        // `gleam_format` wraps the parse error in its own `Error::Parse`, whose
        // `Display` is the generic "failed to parse Gleam source code". The
        // `ParseError` behind it carries the position, so it is reported
        // explicitly rather than left as `None` — otherwise `format` reports a
        // line and `parse` does not, for the same input.
        let line = match &error {
            gleam_core::Error::Parse { error, .. } => {
                Some(crate::to_json::error_line(error, source))
            }
            _ => None,
        };

        ErrorInfo {
            kind: "FormatError".to_string(),
            msg: error.to_string(),
            line,
        }
    })?;

    Ok(out)
}

/// Formats Gleam source by invoking `gleam format --stdin`.
///
/// Used by the `external-gleam` build, which ships without the vendored
/// compiler crates and therefore has no in-process printer.
#[cfg(not(feature = "vendored"))]
pub fn format_source(source: &str) -> Result<String, ErrorInfo> {
    use std::io::Write;
    use std::process::{Command, Stdio};

    let mut child = Command::new("gleam")
        .args(["format", "--stdin"])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|error| ErrorInfo {
            kind: "FormatError".to_string(),
            msg: format!("cannot run `gleam format`: {error}. Put `gleam` on PATH."),
            line: None,
        })?;

    // Writing can fail with EPIPE when `gleam` rejects the input and exits
    // before reading it all; that is reported through the exit status below,
    // which carries the actual syntax error, so the write error is ignored.
    if let Some(stdin) = child.stdin.as_mut() {
        let _ = stdin.write_all(source.as_bytes());
    }
    drop(child.stdin.take());

    let output = child.wait_with_output().map_err(|error| ErrorInfo {
        kind: "FormatError".to_string(),
        msg: format!("`gleam format` failed: {error}"),
        line: None,
    })?;

    if output.status.success() {
        String::from_utf8(output.stdout).map_err(|error| ErrorInfo {
            kind: "FormatError".to_string(),
            msg: format!("`gleam format` produced invalid UTF-8: {error}"),
            line: None,
        })
    } else {
        let stderr = String::from_utf8_lossy(&output.stderr);
        Err(ErrorInfo {
            kind: "FormatError".to_string(),
            msg: format!("failed to parse Gleam source code: {}", stderr.trim()),
            line: first_error_line(&stderr),
        })
    }
}

/// Extracts the line a `gleam format` diagnostic points at.
///
/// The CLI prints a codespan-style block whose header is `<file>:<line>:<col>`:
///
/// ```text
///   ┌─ <stdin>:1:16
/// ```
///
/// The line is the *second* component from the end, not the last — taking the
/// last one reported the column, which is off by a variable amount and so
/// looks plausible until it is compared with the source. Returns `None` when
/// the output carries no such header, rather than guessing.
#[cfg(not(feature = "vendored"))]
fn first_error_line(stderr: &str) -> Option<usize> {
    stderr
        .lines()
        .find(|line| line.contains('┌'))
        .and_then(|line| line.rsplit('┌').next())
        .and_then(|header| {
            header
                .trim_start_matches(['─', ' '])
                .trim()
                .strip_prefix('<')
        })
        .and_then(|header| header.split_once('>'))
        .map(|(_file, position)| position.trim_start_matches(':'))
        .and_then(|position| {
            let parts: Vec<&str> = position.split(':').collect();
            match parts.as_slice() {
                [line, _column] => line.trim().parse().ok(),
                _ => None,
            }
        })
}

/// The M1 module, decoded into renderable form.
pub struct RenderModule {
    pub comments: Vec<String>,
    pub definitions: Vec<RenderNode>,
    /// When the input was a bare expression rather than a module, the
    /// expression itself. `render/1` returns it directly instead of the
    /// wrapping function it was put in to satisfy the printer.
    pub bare_expression: Option<RenderNode>,
}

impl RenderModule {
    /// Renders the module as source text.
    pub fn render(&self) -> String {
        // A bare expression is returned as-is: the wrapper function exists
        // only so `gleam format` has a valid module to parse.
        if let Some(expression) = &self.bare_expression {
            return expression.render(0);
        }

        let mut out = String::new();

        for comment in &self.comments {
            out.push_str("////");
            if !comment.is_empty() {
                out.push(' ');
                out.push_str(comment);
            }
            out.push('\n');
        }

        if !self.comments.is_empty() {
            out.push('\n');
        }

        for (position, definition) in self.definitions.iter().enumerate() {
            if position > 0 {
                out.push('\n');
            }
            out.push_str(&definition.render(0));
            out.push('\n');
        }

        out
    }
}

fn module_from_json(value: &serde_json::Value) -> Result<RenderModule, ErrorInfo> {
    let object = value
        .as_object()
        .ok_or_else(|| decode_error("module is not an object"))?;

    // A bare node — not a `Module` — is a single expression. `from_meta/2` on
    // an expression MetaAST produces exactly that, and the conformance suite
    // relies on it, so it is rendered as a one-expression module rather than
    // rejected. `gleam format` only accepts whole modules, so the expression
    // has to be wrapped in something valid.
    if object.get("kind").and_then(|kind| kind.as_str()) != Some("Module") {
        let node = RenderNode::from_json(value)?;
        return Ok(RenderModule {
            comments: Vec::new(),
            definitions: vec![RenderNode::from_json(&serde_json::json!({
                "kind": "Fn",
                "span": {"line": 1, "col": 1, "end_line": 1, "end_col": 1},
                "name": "main",
                "public": true,
                "children": [value.clone()],
                "extra": {"publicity": "public"},
            }))?],
            bare_expression: Some(node),
        });
    }

    let comments = object
        .get("comments")
        .and_then(|comments| comments.as_array())
        .map(|comments| {
            comments
                .iter()
                .filter_map(|comment| comment.as_str().map(str::to_string))
                .collect()
        })
        .unwrap_or_default();

    let definitions = object
        .get("children")
        .and_then(|children| children.as_array())
        .map(|children| {
            children
                .iter()
                .map(RenderNode::from_json)
                .collect::<Result<Vec<_>, _>>()
        })
        .transpose()?
        .unwrap_or_default();

    Ok(RenderModule {
        comments,
        definitions,
        bare_expression: None,
    })
}

/// A decoded M1 node, ready to render.
///
/// Kept as a thin wrapper over the JSON object rather than a hand-written enum
/// mirror: the renderer needs the same fields `to_json` wrote, and re-declaring
/// them as Rust types would mean a second place to update when a construct is
/// added. The accessors below are the only place that knows the shape.
pub struct RenderNode {
    value: serde_json::Value,
}

impl RenderNode {
    fn from_json(value: &serde_json::Value) -> Result<RenderNode, ErrorInfo> {
        if !value.is_object() {
            return Err(decode_error("node is not an object"));
        }

        Ok(RenderNode {
            value: value.clone(),
        })
    }

    fn kind(&self) -> &str {
        self.value
            .get("kind")
            .and_then(|kind| kind.as_str())
            .unwrap_or("")
    }

    fn name(&self) -> Option<&str> {
        self.value.get("name").and_then(|name| name.as_str())
    }

    fn children(&self) -> &[serde_json::Value] {
        self.value
            .get("children")
            .and_then(|children| children.as_array())
            .map(Vec::as_slice)
            .unwrap_or(&[])
    }

    fn extra(&self) -> Option<&serde_json::Map<String, serde_json::Value>> {
        self.value.get("extra").and_then(|extra| extra.as_object())
    }

    fn extra_str(&self, key: &str) -> Option<&str> {
        self.extra()
            .and_then(|extra| extra.get(key))
            .and_then(|value| value.as_str())
    }

    fn extra_bool(&self, key: &str) -> bool {
        self.extra()
            .and_then(|extra| extra.get(key))
            .and_then(|value| value.as_bool())
            .unwrap_or(false)
    }

    fn extra_value(&self, key: &str) -> Option<&serde_json::Value> {
        self.extra().and_then(|extra| extra.get(key))
    }

    fn pattern(&self) -> Option<RenderNode> {
        self.value
            .get("pattern")
            .and_then(|pattern| RenderNode::from_json(pattern).ok())
    }

    fn type_node(&self) -> Option<RenderNode> {
        self.value
            .get("type_node")
            .and_then(|node| RenderNode::from_json(node).ok())
    }

    fn literal(&self) -> Option<(String, String)> {
        let value = self.value.get("value")?.as_object()?;
        let subtype = value.get("subtype")?.as_str()?.to_string();
        let payload = value.get("value")?.as_str()?.to_string();
        Some((subtype, payload))
    }

    fn child(&self, position: usize) -> Result<RenderNode, ErrorInfo> {
        self.children()
            .get(position)
            .ok_or_else(|| decode_error("missing child node"))
            .and_then(RenderNode::from_json)
    }
}

fn decode_error(message: &str) -> ErrorInfo {
    ErrorInfo {
        kind: "DecodeError".to_string(),
        msg: message.to_string(),
        line: None,
    }
}

// ─────────────────────────────────────────────────────────────────────
// Rendering
// ─────────────────────────────────────────────────────────────────────

impl RenderNode {
    /// Renders this node as source at `indent` levels of two spaces.
    ///
    /// An unknown kind renders as `todo` rather than failing: a node the
    /// renderer does not know is a *bridge* gap, and emitting a visible `todo`
    /// keeps the surrounding module valid so the caller sees the problem in the
    /// output instead of losing the whole file. `to_json` has no wildcard arm,
    /// so this can only happen for hand-written M1.
    fn render(&self, indent: usize) -> String {
        let pad = "  ".repeat(indent);

        match self.kind() {
            "Import" => self.render_import(),
            "Fn" => self.render_function(indent),
            "TypeAlias" => self.render_type_alias(indent),
            "CustomType" => self.render_custom_type(indent),
            "ModuleConstant" => self.render_module_constant(indent),
            "RecordConstructor" => self.render_record_constructor(indent),
            "RecordConstructorArg" => self.render_record_constructor_arg(),
            "Arg" => self.render_arg(),
            "Let" => self.render_let(indent),
            "Use" => self.render_use(indent),
            "Assert" => self.render_assert(indent),
            "Block" => self.render_block(indent),
            "Call" => self.render_call(indent),
            "Pipeline" => self.render_pipeline(indent),
            "Case" => self.render_case(indent),
            "Clause" => self.render_clause(indent),
            "FnLiteral" => self.render_fn_literal(indent),
            "BinOp" => self.render_bin_op(indent),
            "NegateInt" => format!("-{}", self.render_child_expr(0, indent)),
            "NegateBool" => format!("!{}", self.render_child_expr(0, indent)),
            "Not" => format!("!{}", self.render_child_expr(0, indent)),
            "FieldAccess" => format!(
                "{}.{}",
                self.render_child_expr(0, indent),
                self.name().unwrap_or("_")
            ),
            "ModuleSelect" => format!(
                "{}.{}",
                self.extra_str("module").unwrap_or("_"),
                self.name().unwrap_or("_")
            ),
            "TupleIndex" => format!(
                "{}.{}",
                self.render_child_expr(0, indent),
                self.extra()
                    .and_then(|extra| extra.get("index"))
                    .and_then(|index| index.as_u64())
                    .unwrap_or(0)
            ),
            "List" => self.render_list(indent),
            "Tuple" => self.render_tuple(indent),
            // A call argument is only labelled when the source labelled it;
            // an unlabelled one is a bare expression. Rendering `_: value`
            // for the unlabelled case produced `io.println(_: "hi")`, which
            // Gleam rejects — the round-trip self-test caught it.
            "CallArg" => match self.extra_str("label") {
                Some(label) => format!("{label}: {}", self.render_child_expr(0, indent)),
                None => self.render_child_expr(0, indent),
            },
            "RecordUpdateArg" => format!(
                "{}: {}",
                self.name().unwrap_or("_"),
                self.render_child_expr(0, indent)
            ),
            "BitArray" => self.render_bit_array(indent),
            "BitArraySegment" => self.render_bit_array_segment(indent),
            "Record" => self.render_record(indent),
            "RecordUpdate" => self.render_record_update(indent),
            "Var" => self
                .extra_str("module")
                .map(|module| format!("{module}.{}", self.name().unwrap_or("_")))
                .unwrap_or_else(|| self.name().unwrap_or("_").to_string()),
            "Discard" => self.name().unwrap_or("_").to_string(),
            "Assign" => format!(
                "{} as {}",
                self.render_child_expr(0, indent),
                self.name().unwrap_or("_")
            ),
            "Constructor" => self.render_constructor(indent),
            // `ToMeta` renders the right-hand side into `name` (including a
            // leading `_` for a discarded binding), so both cases print the
            // same way.
            "StringPrefix" => format!(
                "\"{}\" <> {}",
                self.extra_str("left").unwrap_or(""),
                self.name().unwrap_or("_")
            ),
            "Int" | "Float" | "String" => self.render_literal(),
            "Todo" => match self.children().first() {
                Some(message) => format!(
                    "todo as {}",
                    RenderNode::from_json(message)
                        .map(|node| node.render(indent))
                        .unwrap_or_else(|_| "\"\"".to_string())
                ),
                None => "todo".to_string(),
            },
            "Panic" => match self.children().first() {
                Some(message) => format!(
                    "panic as {}",
                    RenderNode::from_json(message)
                        .map(|node| node.render(indent))
                        .unwrap_or_else(|_| "\"\"".to_string())
                ),
                None => "panic".to_string(),
            },
            "Echo" => {
                let mut parts = vec!["echo".to_string()];
                for child in self.children() {
                    if let Ok(node) = RenderNode::from_json(child) {
                        parts.push(node.render(indent));
                    }
                }
                parts.join(" ")
            }
            "FnType" => self.render_fn_type(indent),
            "TupleType" => format!(
                "#({})",
                self.children()
                    .iter()
                    .filter_map(|child| RenderNode::from_json(child).ok())
                    .map(|node| node.render(indent))
                    .collect::<Vec<_>>()
                    .join(", ")
            ),
            "TypeConstructor" => {
                let arguments: Vec<String> = self
                    .children()
                    .iter()
                    .filter_map(|child| RenderNode::from_json(child).ok())
                    .map(|node| node.render(indent))
                    .collect();

                let name = match self.extra_str("module") {
                    Some(module) => format!("{module}.{}", self.name().unwrap_or("_")),
                    None => self.name().unwrap_or("_").to_string(),
                };

                if arguments.is_empty() {
                    name
                } else {
                    format!("{name}({})", arguments.join(", "))
                }
            }
            "TypeVar" => self.name().unwrap_or("_").to_string(),
            "TypeHole" => self.name().unwrap_or("_").to_string(),
            "InvalidPattern" | "InvalidGuard" | "InvalidConstant" => "_".to_string(),
            _ => format!("{pad}todo"),
        }
    }

    /// Renders the child at `position` as an expression.
    fn render_child_expr(&self, position: usize, indent: usize) -> String {
        self.child(position)
            .map(|node| node.render(indent))
            .unwrap_or_else(|_| "todo".to_string())
    }

    fn render_literal(&self) -> String {
        match self.literal() {
            Some((subtype, payload)) => match subtype.as_str() {
                // `gleam_core` keeps a string literal's *raw* source text
                // between the quotes — escapes included — so wrapping it is
                // enough. Running `escape_string/1` over it double-escaped
                // every backslash and quote.
                "string" => format!("\"{payload}\""),
                _ => payload,
            },
            None => match self.kind() {
                "String" => "\"\"".to_string(),
                _ => "0".to_string(),
            },
        }
    }

    fn render_import(&self) -> String {
        let mut out = format!("import {}", self.name().unwrap_or("_"));

        if let Some(as_name) = self.extra_str("as_name") {
            out.push_str(&format!(" as {as_name}"));
        }

        let values = self.unqualified("values");
        let types = self.unqualified("types");

        let mut imports: Vec<String> = Vec::new();
        imports.extend(types.into_iter().map(|name| format!("type {name}")));
        imports.extend(values);

        if !imports.is_empty() {
            out.push_str(&format!(".{{{}}}", imports.join(", ")));
        }

        out
    }

    /// `{name as alias}` entries of an import.
    fn unqualified(&self, key: &str) -> Vec<String> {
        self.extra_value(key)
            .and_then(|value| value.as_array())
            .map(|entries| {
                entries
                    .iter()
                    .filter_map(|entry| {
                        let name = entry.get("name")?.as_str()?;
                        match entry.get("as_name").and_then(|as_name| as_name.as_str()) {
                            Some(alias) => Some(format!("{name} as {alias}")),
                            None => Some(name.to_string()),
                        }
                    })
                    .collect()
            })
            .unwrap_or_default()
    }

    fn render_function(&self, indent: usize) -> String {
        let pad = "  ".repeat(indent);
        let mut out = String::new();

        out.push_str(&pad);
        out.push_str(&self.render_attributes(indent));

        if self.extra_str("publicity") == Some("public") {
            out.push_str("pub ");
        }

        out.push_str("fn ");
        out.push_str(self.name().unwrap_or("anonymous"));
        out.push('(');
        out.push_str(&self.render_args());
        out.push(')');

        if let Some(return_type) = self.type_node() {
            out.push_str(" -> ");
            out.push_str(&return_type.render(indent));
        }

        // A function with an `@external` attribute has no body in the source,
        // and `fn f() {}` is a syntax error — the `{}` would be an empty block.
        if self.extra_value("external_erlang").is_some()
            || self.extra_value("external_javascript").is_some()
        {
            return out;
        }

        let body = self.render_body(indent + 1);
        out.push_str(" {\n");
        out.push_str(&body);
        out.push_str(&pad);
        out.push('}');

        out
    }

    /// Attributes that precede a definition (`@deprecated`, `@external`, …).
    fn render_attributes(&self, indent: usize) -> String {
        let pad = "  ".repeat(indent);
        let mut out = String::new();

        // `///` documentation comes first, above every attribute and keyword.
        // It is part of the definition's identity: dropping it changes the M1
        // on re-parse and loses it from `gleam docs`.
        if let Some(documentation) = self.extra_str("documentation") {
            for line in documentation.lines() {
                out.push_str(&format!("{pad}///{line}\n"));
            }
        }

        if let Some(target) = self.extra_str("target") {
            out.push_str(&format!("{pad}@target({target})\n"));
        }

        if let Some(message) = self.extra_str("deprecated") {
            out.push_str(&format!(
                "{pad}@deprecated(\"{}\")\n",
                escape_string(message)
            ));
        }

        for (key, target) in [
            ("external_erlang", "erlang"),
            ("external_javascript", "javascript"),
        ] {
            if let Some(external) = self.extra_value(key).and_then(|value| value.as_object()) {
                let module = external
                    .get("module")
                    .and_then(|m| m.as_str())
                    .unwrap_or("");
                let function = external
                    .get("function")
                    .and_then(|f| f.as_str())
                    .unwrap_or("");
                out.push_str(&format!(
                    "{pad}@external({target}, \"{module}\", \"{function}\")\n"
                ));
            }
        }

        out
    }

    fn render_args(&self) -> String {
        self.children()
            .iter()
            .filter_map(|child| RenderNode::from_json(child).ok())
            .filter(|node| node.kind() == "Arg")
            .map(|node| node.render_arg())
            .collect::<Vec<_>>()
            .join(", ")
    }

    fn render_arg(&self) -> String {
        let label = match self.extra_str("label") {
            Some(label) => format!("{label} "),
            None => String::new(),
        };

        let name = self.name().unwrap_or("_");

        match self.type_node() {
            Some(annotation) => format!("{label}{name}: {}", annotation.render(0)),
            None => format!("{label}{name}"),
        }
    }

    /// Renders a body: every non-`Arg` child, one per line, at `indent`.
    fn render_body(&self, indent: usize) -> String {
        let pad = "  ".repeat(indent);

        self.children()
            .iter()
            .filter_map(|child| RenderNode::from_json(child).ok())
            .filter(|node| node.kind() != "Arg")
            .map(|node| format!("{pad}{}\n", node.render(indent)))
            .collect()
    }

    fn render_type_alias(&self, indent: usize) -> String {
        let pad = "  ".repeat(indent);
        let mut out = String::new();

        out.push_str(&pad);
        out.push_str(&self.render_attributes(indent));

        if self.extra_str("publicity") == Some("public") {
            out.push_str("pub ");
        }

        out.push_str("type ");
        out.push_str(self.name().unwrap_or("Anonymous"));
        out.push_str(&self.render_parameters());

        if let Some(aliased) = self.type_node() {
            out.push_str(" = ");
            out.push_str(&aliased.render(indent));
        }

        out
    }

    fn render_parameters(&self) -> String {
        let parameters: Vec<String> = self
            .extra_value("parameters")
            .and_then(|value| value.as_array())
            .map(|parameters| {
                parameters
                    .iter()
                    .filter_map(|parameter| parameter.as_str().map(str::to_string))
                    .collect()
            })
            .unwrap_or_default();

        if parameters.is_empty() {
            String::new()
        } else {
            format!("({})", parameters.join(", "))
        }
    }

    fn render_custom_type(&self, indent: usize) -> String {
        let pad = "  ".repeat(indent);
        let mut out = String::new();

        out.push_str(&pad);
        out.push_str(&self.render_attributes(indent));

        if self.extra_str("publicity") == Some("public") {
            out.push_str("pub ");
        }

        if self.value.get("opaque").and_then(|opaque| opaque.as_bool()) == Some(true) {
            out.push_str("opaque ");
        }

        out.push_str("type ");
        out.push_str(self.name().unwrap_or("Anonymous"));
        out.push_str(&self.render_parameters());
        out.push_str(" {\n");

        for child in self.children() {
            if let Ok(constructor) = RenderNode::from_json(child) {
                out.push_str(&constructor.render(indent + 1));
                out.push('\n');
            }
        }

        out.push_str(&pad);
        out.push('}');

        out
    }

    fn render_record_constructor(&self, indent: usize) -> String {
        let pad = "  ".repeat(indent);
        let arguments: Vec<String> = self
            .children()
            .iter()
            .filter_map(|child| RenderNode::from_json(child).ok())
            .map(|node| node.render_record_constructor_arg())
            .collect();

        let mut out = String::new();

        // A constructor's `///` documentation is part of its identity: dropping
        // it changes the M1 on re-parse, and `gleam docs` would lose it.
        if let Some(documentation) = self.extra_str("documentation") {
            for line in documentation.lines() {
                out.push_str(&format!("{pad}///{line}\n"));
            }
        }

        if arguments.is_empty() {
            out.push_str(&format!("{pad}{}", self.name().unwrap_or("Constructor")));
        } else {
            out.push_str(&format!(
                "{pad}{}({})",
                self.name().unwrap_or("Constructor"),
                arguments.join(", ")
            ));
        }

        out
    }

    fn render_record_constructor_arg(&self) -> String {
        let label = match self.extra_str("label") {
            Some(label) => format!("{label}: "),
            None => String::new(),
        };

        match self.type_node() {
            Some(annotation) => format!("{label}{}", annotation.render(0)),
            None => format!("{label}todo"),
        }
    }

    fn render_module_constant(&self, indent: usize) -> String {
        let pad = "  ".repeat(indent);
        let mut out = String::new();

        out.push_str(&pad);
        out.push_str(&self.render_attributes(indent));

        if self.extra_str("publicity") == Some("public") {
            out.push_str("pub ");
        }

        out.push_str("const ");
        out.push_str(self.name().unwrap_or("constant"));

        if let Some(annotation) = self.type_node() {
            out.push_str(": ");
            out.push_str(&annotation.render(indent));
        }

        out.push_str(" = ");
        out.push_str(&self.render_child_expr(0, indent));

        out
    }

    fn render_let(&self, indent: usize) -> String {
        let mut out = String::new();

        out.push_str(match self.extra_str("kind") {
            Some("assert") => "assert ",
            _ => "let ",
        });

        if let Some(pattern) = self.pattern() {
            out.push_str(&pattern.render(indent));
        }

        if let Some(annotation) = self.type_node() {
            out.push_str(": ");
            out.push_str(&annotation.render(indent));
        }

        out.push_str(" = ");
        out.push_str(&self.render_child_expr(0, indent));

        out
    }

    fn render_use(&self, indent: usize) -> String {
        let mut out = String::from("use ");

        let assignments: Vec<String> = self
            .extra_value("assignments")
            .and_then(|value| value.as_array())
            .map(|assignments| {
                assignments
                    .iter()
                    .filter_map(|assignment| {
                        let pattern = assignment.get("pattern")?;
                        RenderNode::from_json(pattern)
                            .ok()
                            .map(|node| node.render(indent))
                    })
                    .collect()
            })
            .unwrap_or_default();

        if !assignments.is_empty() {
            out.push_str(&assignments.join(", "));
            out.push_str(" <- ");
        }

        out.push_str(&self.render_child_expr(0, indent));

        out
    }

    fn render_assert(&self, indent: usize) -> String {
        let mut out = String::from("assert ");
        out.push_str(&self.render_child_expr(0, indent));

        if let Ok(message) = self.child(1) {
            out.push_str(" as ");
            out.push_str(&message.render(indent));
        }

        out
    }

    fn render_block(&self, indent: usize) -> String {
        let pad = "  ".repeat(indent);
        let inner = "  ".repeat(indent + 1);
        let mut out = String::from("{\n");

        for child in self.children() {
            if let Ok(node) = RenderNode::from_json(child) {
                out.push_str(&inner);
                out.push_str(&node.render(indent + 1));
                out.push('\n');
            }
        }

        out.push_str(&pad);
        out.push('}');

        out
    }

    fn render_call(&self, indent: usize) -> String {
        let callee = self.render_child_expr(0, indent);

        let arguments: Vec<String> = self
            .children()
            .iter()
            .skip(1)
            .filter_map(|child| RenderNode::from_json(child).ok())
            .map(|node| node.render(indent))
            .collect();

        format!("{callee}({})", arguments.join(", "))
    }

    fn render_pipeline(&self, indent: usize) -> String {
        self.children()
            .iter()
            .filter_map(|child| RenderNode::from_json(child).ok())
            .map(|node| node.render(indent))
            .collect::<Vec<_>>()
            .join("\n  |> ")
    }

    fn render_case(&self, indent: usize) -> String {
        let pad = "  ".repeat(indent);
        let inner = "  ".repeat(indent + 1);

        let subjects: Vec<String> = self
            .children()
            .iter()
            .filter_map(|child| RenderNode::from_json(child).ok())
            .filter(|node| node.kind() != "Clause")
            .map(|node| node.render(indent))
            .collect();

        let mut out = format!("case {} {{\n", subjects.join(", "));

        for child in self.children() {
            if let Ok(clause) = RenderNode::from_json(child) {
                if clause.kind() == "Clause" {
                    out.push_str(&inner);
                    out.push_str(&clause.render_clause_body(indent + 1));
                    out.push('\n');
                }
            }
        }

        out.push_str(&pad);
        out.push('}');

        out
    }

    fn render_clause(&self, indent: usize) -> String {
        self.render_clause_body(indent)
    }

    fn render_clause_body(&self, indent: usize) -> String {
        let mut patterns: Vec<String> = Vec::new();
        let mut then: Option<RenderNode> = None;

        for child in self.children() {
            match RenderNode::from_json(child) {
                Ok(node) => {
                    if then.is_some() {
                        // A second expression after the body is a renderer
                        // bug; keep the first and let the formatter decide.
                        continue;
                    }
                    if is_last_child(self, child) {
                        then = Some(node);
                    } else {
                        patterns.push(node.render(indent));
                    }
                }
                Err(_) => continue,
            }
        }

        let mut out = String::new();
        out.push_str(&patterns.join(", "));

        if let Some(guard) = self
            .extra_value("guard")
            .filter(|guard| !guard.is_null())
            .and_then(|guard| RenderNode::from_json(guard).ok())
        {
            out.push_str(&format!(" if {}", guard.render(indent)));
        }

        out.push_str(" ->");

        match then {
            Some(body) => {
                out.push(' ');
                out.push_str(&body.render(indent));
            }
            None => out.push_str(" todo"),
        }

        out
    }

    fn render_fn_literal(&self, indent: usize) -> String {
        // A capture (`f(1, _)`) is desugared by the parser into an anonymous
        // function whose last parameter is the hole. Rendering the desugared
        // form is valid Gleam but not what the author wrote, and it changes the
        // AST on re-parse. The hole's name is the last `Arg`, so the sugar is
        // restored by pulling that argument back out.
        if self.extra_str("kind") == Some("capture") {
            if let Some(capture) = self.render_capture(indent) {
                return capture;
            }
        }

        let mut out = String::from("fn(");

        let arguments: Vec<String> = self
            .children()
            .iter()
            .filter_map(|child| RenderNode::from_json(child).ok())
            .filter(|node| node.kind() == "Arg")
            .map(|node| node.render_arg())
            .collect();

        out.push_str(&arguments.join(", "));
        out.push(')');

        if let Some(return_type) = self.type_node() {
            out.push_str(" -> ");
            out.push_str(&return_type.render(indent));
        }

        out.push_str(" {\n");
        out.push_str(&self.render_body(indent + 1));
        out.push_str(&"  ".repeat(indent));
        out.push('}');

        out
    }

    /// Renders a desugared capture back to `f(a, _)` form, or `None` when the
    /// shape is not the one the parser produces.
    fn render_capture(&self, indent: usize) -> Option<String> {
        let arguments: Vec<RenderNode> = self
            .children()
            .iter()
            .filter_map(|child| RenderNode::from_json(child).ok())
            .filter(|node| node.kind() == "Arg")
            .collect();

        let (hole, call_arguments) = arguments.split_last()?;
        let hole_name = hole.name()?;

        let body = self
            .children()
            .iter()
            .filter_map(|child| RenderNode::from_json(child).ok())
            .find(|node| node.kind() != "Arg")?;

        let rendered = body.render(indent);
        if !rendered.contains(hole_name) {
            return None;
        }

        // Only a single-expression body is a capture; anything else is a real
        // anonymous function that happens to share the shape.
        let _ = call_arguments;
        Some(rendered.replacen(hole_name, "_", 1))
    }

    fn render_bin_op(&self, indent: usize) -> String {
        let operator = self
            .extra_str("operator")
            .and_then(binop_symbol)
            .or_else(|| self.name().map(str::to_string))
            .unwrap_or_else(|| "+".to_string());

        format!(
            "{} {operator} {}",
            self.render_child_expr(0, indent),
            self.render_child_expr(1, indent)
        )
    }

    fn render_list(&self, indent: usize) -> String {
        let mut elements: Vec<String> = self
            .children()
            .iter()
            .filter_map(|child| RenderNode::from_json(child).ok())
            .map(|node| node.render(indent))
            .collect();

        if let Some(tail) = self
            .extra_value("tail")
            .filter(|tail| !tail.is_null())
            .and_then(|tail| RenderNode::from_json(tail).ok())
        {
            elements.push(format!("..{}", tail.render(indent)));
        }

        format!("[{}]", elements.join(", "))
    }

    fn render_tuple(&self, indent: usize) -> String {
        let elements: Vec<String> = self
            .children()
            .iter()
            .filter_map(|child| RenderNode::from_json(child).ok())
            .map(|node| node.render(indent))
            .collect();

        format!("#({})", elements.join(", "))
    }

    fn render_bit_array(&self, indent: usize) -> String {
        let segments: Vec<String> = self
            .children()
            .iter()
            .filter_map(|child| RenderNode::from_json(child).ok())
            .map(|node| node.render_bit_array_segment(indent))
            .collect();

        format!("<<{}>>", segments.join(", "))
    }

    fn render_bit_array_segment(&self, indent: usize) -> String {
        let value = self.render_child_expr(0, indent);

        let options: Vec<String> = self
            .extra_value("options")
            .and_then(|options| options.as_array())
            .map(|options| {
                options
                    .iter()
                    .filter_map(|option| {
                        let name = option.get("name")?.as_str()?;
                        let inner = option.get("extra");
                        Some(match (name, inner) {
                            ("size", Some(extra)) => match extra.get("short_form") {
                                Some(serde_json::Value::Bool(true)) => format!(
                                    ":{}",
                                    extra
                                        .get("value")
                                        .and_then(|value| RenderNode::from_json(value).ok())
                                        .map(|node| node.render(indent))
                                        .unwrap_or_else(|| "0".to_string())
                                ),
                                _ => format!(
                                    ":size({})",
                                    extra
                                        .get("value")
                                        .and_then(|value| RenderNode::from_json(value).ok())
                                        .map(|node| node.render(indent))
                                        .unwrap_or_else(|| "0".to_string())
                                ),
                            },
                            ("unit", Some(extra)) => format!(
                                ":unit({})",
                                extra.get("value").and_then(|v| v.as_u64()).unwrap_or(1)
                            ),
                            _ => format!(":{name}"),
                        })
                    })
                    .collect()
            })
            .unwrap_or_default();

        if options.is_empty() {
            value
        } else {
            format!("{value}{}", options.join(""))
        }
    }

    fn render_record(&self, indent: usize) -> String {
        let name = match self.extra_str("module") {
            Some(module) => format!("{module}.{}", self.name().unwrap_or("_")),
            None => self.name().unwrap_or("_").to_string(),
        };

        if self.extra_bool("has_arguments") {
            let arguments: Vec<String> = self
                .children()
                .iter()
                .filter_map(|child| RenderNode::from_json(child).ok())
                .map(|node| node.render(indent))
                .collect();
            format!("{name}({})", arguments.join(", "))
        } else {
            name
        }
    }

    fn render_record_update(&self, indent: usize) -> String {
        // Children are `[constructor, base, arguments…]` — see `to_json`. The
        // constructor is the *expression* being updated (`Rectangle(..rect)`
        // parses it as a `Var`), so its name comes from that child rather than
        // from this node, which carries none.
        let name = self.render_child_expr(0, indent);
        let base = self.render_child_expr(1, indent);
        let arguments: Vec<String> = self
            .children()
            .iter()
            .skip(2)
            .filter_map(|child| RenderNode::from_json(child).ok())
            .map(|node| node.render(indent))
            .collect();

        if arguments.is_empty() {
            format!("{name}(..{base})")
        } else {
            format!("{name}(..{base}, {})", arguments.join(", "))
        }
    }

    fn render_constructor(&self, indent: usize) -> String {
        let name = match self.extra_str("module") {
            Some(module) => format!("{module}.{}", self.name().unwrap_or("_")),
            None => self.name().unwrap_or("_").to_string(),
        };

        let mut arguments: Vec<String> = self
            .children()
            .iter()
            .filter_map(|child| RenderNode::from_json(child).ok())
            .map(|node| node.render(indent))
            .collect();

        // `spread` is `null` when the source had no `..`, so presence alone is
        // not enough: an `is_some()` check here rendered `Point(..)` for every
        // constructor in the module.
        if self
            .extra_value("spread")
            .is_some_and(|spread| !spread.is_null())
        {
            arguments.push("..".to_string());
        }

        if arguments.is_empty() {
            name
        } else {
            format!("{name}({})", arguments.join(", "))
        }
    }

    fn render_fn_type(&self, indent: usize) -> String {
        let children: Vec<RenderNode> = self
            .children()
            .iter()
            .filter_map(|child| RenderNode::from_json(child).ok())
            .collect();

        match children.split_last() {
            Some((return_type, arguments)) => format!(
                "fn({}) -> {}",
                arguments
                    .iter()
                    .map(|argument| argument.render(indent))
                    .collect::<Vec<_>>()
                    .join(", "),
                return_type.render(indent)
            ),
            None => "fn() -> Nil".to_string(),
        }
    }
}

/// True when `child` is the last element of `node`'s children.
fn is_last_child(node: &RenderNode, child: &serde_json::Value) -> bool {
    node.children()
        .last()
        .map(|last| std::ptr::eq(last, child))
        .unwrap_or(false)
}

/// The source spelling of a `BinOp` variant name.
///
/// `to_json` writes the upstream variant name (`AddInt`, `AddFloat`, …) rather
/// than the printed operator, because `+` and `+.` are different operators that
/// share a prefix. This is the inverse table.
fn binop_symbol(variant: &str) -> Option<String> {
    let symbol = match variant {
        "And" => "&&",
        "Or" => "||",
        "Eq" => "==",
        "NotEq" => "!=",
        "LtInt" => "<",
        "LtEqInt" => "<=",
        "LtFloat" => "<.",
        "LtEqFloat" => "<=.",
        "GtEqInt" => ">=",
        "GtInt" => ">",
        "GtEqFloat" => ">=.",
        "GtFloat" => ">.",
        "AddInt" => "+",
        "AddFloat" => "+.",
        "SubInt" => "-",
        "SubFloat" => "-.",
        "MultInt" => "*",
        "MultFloat" => "*.",
        "DivInt" => "/",
        "DivFloat" => "/.",
        "RemainderInt" => "%",
        "Concatenate" => "<>",
        _ => return None,
    };

    Some(symbol.to_string())
}

/// Escapes a string literal's payload for Gleam source.
fn escape_string(value: &str) -> String {
    let mut out = String::with_capacity(value.len());

    for character in value.chars() {
        match character {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            other => out.push(other),
        }
    }

    out
}

// The round-trip tests parse real Gleam to build their input, which needs the
// vendored parser; the `external-gleam` build has none, so they do not apply
// to it.
#[cfg(all(test, feature = "vendored"))]
mod tests {
    use super::*;
    use crate::to_json::parse_module;

    /// Parses `source`, renders it back, and returns the rendered text.
    fn round_trip(source: &str) -> String {
        let module = parse_module(source).expect("parse");
        let json = serde_json::to_value(&module).expect("serialise");
        render(&json).expect("render")
    }

    /// Strips location fields and sorts order-insensitive collections, so two
    /// trees compare on *semantics* — which is the contract the adapter
    /// exposes: formatting may normalise, meaning may not.
    ///
    /// Two normalisations are needed:
    ///
    ///   * location fields (`span`, `line`, `col`, …) move when the formatter
    ///     reflows a line, and carry no meaning;
    ///   * an import's unqualified list (`{map, filter as keep}`) is sorted by
    ///     `gleam format`, so `{map, filter as keep}` and
    ///     `{filter as keep, map}` are the same import written two ways.
    fn strip(value: &serde_json::Value) -> serde_json::Value {
        match value {
            serde_json::Value::Object(map) => {
                let mut out: serde_json::Map<String, serde_json::Value> = map
                    .iter()
                    .filter(|(key, _)| {
                        !matches!(
                            key.as_str(),
                            "span" | "line" | "col" | "end_line" | "end_col"
                        )
                    })
                    .map(|(key, value)| (key.clone(), strip(value)))
                    .collect();

                if let Some(serde_json::Value::Object(extra)) = out.get_mut("extra") {
                    for key in ["values", "types"] {
                        if let Some(serde_json::Value::Array(entries)) = extra.get_mut(key) {
                            entries.sort_by(|left, right| {
                                let name = |entry: &serde_json::Value| {
                                    entry
                                        .get("name")
                                        .and_then(|name| name.as_str())
                                        .unwrap_or("")
                                        .to_string()
                                };
                                name(left).cmp(&name(right))
                            });
                        }
                    }
                }

                serde_json::Value::Object(out)
            }
            serde_json::Value::Array(items) => {
                serde_json::Value::Array(items.iter().map(strip).collect())
            }
            other => other.clone(),
        }
    }

    /// Asserts that `source` survives parse → render → parse unchanged.
    ///
    /// This is the fidelity contract the adapter exposes: formatting may
    /// normalise, semantics may not.
    fn assert_round_trips(source: &str) {
        let first = parse_module(source).expect("first parse");
        let json = serde_json::to_value(&first).expect("serialise");
        let rendered = render(&json).expect("render");
        let second = parse_module(&rendered).expect("re-parse");

        let before = strip(&serde_json::to_value(&first).expect("serialise"));
        let after = strip(&serde_json::to_value(&second).expect("serialise"));

        assert_eq!(
            before, after,
            "round-trip changed the tree\n--- rendered ---\n{rendered}"
        );
    }

    #[test]
    fn literals_round_trip() {
        assert_round_trips("pub fn f() -> Int { 42 }");
        assert_round_trips("pub fn f() -> Float { 3.5 }");
        assert_round_trips("pub fn f() -> String { \"hi\" }");
    }

    #[test]
    fn operators_round_trip_including_the_float_forms() {
        assert_round_trips("pub fn f(a: Int, b: Int) -> Int { a + b - a * b / b % b }");
        assert_round_trips("pub fn f(a: Float, b: Float) -> Float { a +. b -. a *. b /. b }");
        assert_round_trips("pub fn f(a: Int, b: Int) -> Bool { a == b && a != b || a < b }");
        assert_round_trips("pub fn f(a: Float, b: Float) -> Bool { a <. b && a >=. b }");
        assert_round_trips("pub fn f(a: String, b: String) -> String { a <> b }");
    }

    #[test]
    fn unary_operators_round_trip() {
        assert_round_trips("pub fn f(a: Int) -> Int { -a }");
        assert_round_trips("pub fn f(a: Bool) -> Bool { !a }");
    }

    #[test]
    fn collections_round_trip() {
        assert_round_trips("pub fn f() -> List(Int) { [1, 2, 3] }");
        assert_round_trips("pub fn f(xs: List(Int)) -> List(Int) { [1, ..xs] }");
        assert_round_trips("pub fn f() -> #(Int, String) { #(1, \"a\") }");
        assert_round_trips("pub fn f(t: #(Int, Int)) -> Int { t.0 }");
    }

    #[test]
    fn calls_round_trip_with_and_without_labels() {
        assert_round_trips("pub fn g(a: Int) -> Int { a }\npub fn f() -> Int { g(1) }");
        assert_round_trips(
            "pub fn g(label a: Int) -> Int { a }\npub fn f() -> Int { g(label: 1) }",
        );
        assert_round_trips("pub fn f() -> Int { 1 }\npub fn g() -> Int { f() }");
    }

    #[test]
    fn pipelines_round_trip() {
        assert_round_trips(
            "pub fn f(xs: List(Int)) -> List(Int) {\n  xs\n  |> map(fn(x) { x })\n}",
        );
    }

    #[test]
    fn case_expressions_round_trip() {
        assert_round_trips("pub fn f(x: Int) -> Int {\n  case x {\n    0 -> 1\n    _ -> 2\n  }\n}");
        assert_round_trips(
            "pub fn f(x: Int) -> Int {\n  case x {\n    n if n > 0 -> n\n    _ -> 0\n  }\n}",
        );
    }

    #[test]
    fn multi_subject_case_round_trips() {
        assert_round_trips(
            "pub fn f(a: Int, b: Int) -> Int {\n  case a, b {\n    0, 0 -> 0\n    _, _ -> 1\n  }\n}",
        );
    }

    #[test]
    fn custom_types_and_constructors_round_trip() {
        assert_round_trips("pub type T {\n  A\n  B(Int)\n  C(x: Int, y: String)\n}");
        assert_round_trips("pub opaque type T {\n  T(Int)\n}");
        assert_round_trips("pub type T(a) = List(a)");
    }

    #[test]
    fn constructor_patterns_round_trip() {
        assert_round_trips(
            "pub type T {\n  A\n  B(Int)\n}\npub fn f(t: T) -> Int {\n  case t {\n    A -> 0\n    B(n) -> n\n  }\n}",
        );
    }

    #[test]
    fn record_updates_round_trip() {
        assert_round_trips(
            "pub type T {\n  T(x: Int, y: Int)\n}\npub fn f(t: T) -> T {\n  T(..t, x: 1)\n}",
        );
    }

    #[test]
    fn imports_round_trip() {
        assert_round_trips("import gleam/io");
        assert_round_trips("import gleam/io as console");
        assert_round_trips("import gleam/list.{map}");
        assert_round_trips("import gleam/list.{map as m}");
        assert_round_trips("import gleam/list.{type List}");
    }

    #[test]
    fn use_expressions_round_trip() {
        assert_round_trips("pub fn f() {\n  use x <- g(1)\n  x\n}");
        assert_round_trips("pub fn f() {\n  use a, b <- g(1)\n  a\n}");
    }

    #[test]
    fn assert_expressions_round_trip() {
        assert_round_trips("pub fn f(x: Int) -> Int {\n  assert x > 0\n  x\n}");
        assert_round_trips("pub fn f(x: Int) -> Int {\n  assert x > 0 as \"bad\"\n  x\n}");
    }

    #[test]
    fn bit_arrays_round_trip() {
        assert_round_trips("pub fn f() -> BitArray { <<1, 2, 3>> }");
        assert_round_trips("pub fn f() -> BitArray { <<1:size(8)>> }");
        assert_round_trips("pub fn f() -> BitArray { <<\"hi\":utf8>> }");
    }

    #[test]
    fn bit_array_patterns_round_trip() {
        assert_round_trips(
            "pub fn f(d: BitArray) -> Int {\n  case d {\n    <<first, rest:bits>> -> first\n    <<>> -> 0\n  }\n}",
        );
    }

    #[test]
    fn string_prefix_pattern_round_trips() {
        assert_round_trips(
            "pub fn f(s: String) -> String {\n  case s {\n    \"hi \" <> rest -> rest\n    _ -> s\n  }\n}",
        );
    }

    #[test]
    fn anonymous_functions_and_captures_round_trip() {
        assert_round_trips("pub fn f() -> fn(Int) -> Int { fn(x) { x } }");
        assert_round_trips(
            "pub fn g(a: Int, b: Int) -> Int { a }\npub fn f() -> fn(Int) -> Int { g(1, _) }",
        );
    }

    #[test]
    fn todo_and_panic_round_trip() {
        assert_round_trips("pub fn f() -> Int { todo }");
        assert_round_trips("pub fn f() -> Int { todo as \"later\" }");
        assert_round_trips("pub fn f() -> Int { panic }");
        assert_round_trips("pub fn f() -> Int { panic as \"boom\" }");
    }

    #[test]
    fn blocks_round_trip() {
        assert_round_trips("pub fn f() -> Int {\n  let x = {\n    let y = 1\n    y\n  }\n  x\n}");
    }

    #[test]
    fn function_attributes_round_trip() {
        assert_round_trips("@deprecated(\"old\")\npub fn f() -> Int { 1 }");
        assert_round_trips(
            "@external(erlang, \"lists\", \"reverse\")\npub fn f(xs: List(a)) -> List(a)",
        );
        assert_round_trips("@target(javascript)\npub fn f() -> Int { 1 }");
    }

    #[test]
    fn documentation_round_trips() {
        assert_round_trips("//// Module docs.\n\npub fn f() -> Int { 1 }");
        assert_round_trips("/// Function docs.\npub fn f() -> Int { 1 }");
        assert_round_trips("pub type T {\n  /// Constructor docs.\n  A\n}");
    }

    #[test]
    fn labelled_arguments_round_trip() {
        assert_round_trips("pub fn f(label a: Int, b other: String) -> Int { a }");
    }

    #[test]
    fn generic_types_round_trip() {
        assert_round_trips("pub fn f(x: a) -> a { x }");
        assert_round_trips("pub fn f(g: fn(Int) -> Int) -> Int { g(1) }");
    }

    #[test]
    fn module_constants_round_trip() {
        assert_round_trips("pub const answer: Int = 42");
        assert_round_trips("const greeting = \"hi\"");
        assert_round_trips("pub const pair = #(1, 2)");
    }

    #[test]
    fn a_realistic_module_round_trips() {
        let source = "\
//// A realistic module.

import gleam/list.{map, filter as keep}
import gleam/option.{type Option, None, Some}

/// A shape.
pub type Shape {
  /// A circle.
  Circle(radius: Float)
  Rectangle(width: Float, height: Float)
  Point
}

pub const origin = 0

pub fn area(shape: Shape) -> Float {
  case shape {
    Circle(radius) -> 3.14 *. radius *. radius
    Rectangle(width, height) if width > 0.0 -> width *. height
    Rectangle(_, _) -> 0.0
    Point -> 0.0
  }
}

pub fn double(xs: List(Int)) -> List(Int) {
  xs
  |> map(fn(x) { x * 2 })
  |> keep(fn(x) { x > 0 })
}

pub fn unwrap(value: Option(Int)) -> Int {
  case value {
    Some(n) -> n
    None -> origin
  }
}
";
        assert_round_trips(source);
    }

    #[test]
    fn a_malformed_document_is_a_decode_error_not_a_panic() {
        // A non-object is not renderable at all.
        let error = render(&serde_json::json!("not a node")).unwrap_err();
        assert_eq!(error.kind, "DecodeError");

        // A node of an unknown kind is rendered as `todo` rather than failing:
        // that is the documented escape hatch for hand-written M1, and it keeps
        // the surrounding module valid so the caller sees the problem in the
        // output. `to_json` has no wildcard arm, so a *parsed* module can never
        // contain one.
        let rendered = render(&serde_json::json!({"kind": "NotAModule"})).expect("renders");
        assert!(rendered.contains("todo"), "unexpected output: {rendered}");
    }

    #[test]
    fn a_bare_expression_renders_without_a_wrapping_module() {
        // `from_meta/2` on an expression MetaAST produces a single node; the
        // conformance suite depends on it rendering as that expression rather
        // than as a module.
        let rendered = render(&serde_json::json!({
            "kind": "BinOp",
            "name": "+",
            "extra": {"operator": "AddInt"},
            "children": [
                {"kind": "Int", "value": {"subtype": "integer", "value": "1"}},
                {"kind": "Int", "value": {"subtype": "integer", "value": "2"}}
            ]
        }))
        .expect("renders");

        assert_eq!(rendered, "1 + 2");
    }

    #[test]
    fn format_source_reports_a_parse_error() {
        let error = format_source("pub fn f( {").unwrap_err();
        assert_eq!(error.kind, "FormatError");
    }

    #[test]
    fn strings_are_escaped() {
        assert_round_trips("pub fn f() -> String { \"a\\\"b\\\\c\" }");
    }

    #[test]
    fn round_trip_helper_is_used() {
        // `round_trip/1` exists for ad-hoc inspection; exercise it so it does
        // not rot.
        assert!(round_trip("pub fn f() -> Int { 1 }").contains("pub fn f()"));
    }
}
