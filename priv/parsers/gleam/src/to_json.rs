//! Gleam source → M1 JSON.
//!
//! `gleam_core::parse::parse_module/3` produces a `Parsed` (an
//! `UntypedModule` plus a `ModuleExtra` of comment and blank-line spans). This
//! module walks that tree once and emits the `Node` mirror defined in
//! [`crate::ast`].
//!
//! ## Coverage
//!
//! Every `UntypedExpr`, `UntypedStatement`, `UntypedDefinition`, `Pattern`,
//! `TypeAst`, `Constant`, `ClauseGuard` and `BitArrayOption` variant is
//! matched. There is no `_ =>` arm on those enums anywhere in this file: a
//! Gleam release that adds a variant makes the bridge fail to compile, which
//! is the only reliable way to keep "we model everything" true across
//! `vendor.sh` refreshes. `Node::Unsupported` exists for constructs that are
//! modelled but not *reifiable* (see `from_json`), not as a catch-all here.
//!
//! ## Spans
//!
//! `gleam_core` reports byte offsets; [`crate::span::LineIndex`] converts them
//! to the 1-based line/column pairs every other Metastatic adapter speaks.

use camino::Utf8PathBuf;
use ecow::EcoString;
use gleam_core::ast::{
    ArgNames, Assert, AssignmentKind, BitArrayOption, CallArg, ClauseGuard, Constant, Definition,
    Pattern, Publicity, RecordConstructor, RecordConstructorArg, Statement, TargetedDefinition,
    TypeAst, TypeAstConstructor, TypeAstConstructorName, TypeAstFn, TypeAstHole, TypeAstTuple,
    TypeAstVar, UnqualifiedImport, UntypedArg, UntypedAssignment, UntypedClause,
    UntypedClauseGuard, UntypedConstant, UntypedCustomType, UntypedDefinition, UntypedExpr,
    UntypedExprBitArraySegment, UntypedFunction, UntypedImport, UntypedModuleConstant,
    UntypedPattern, UntypedRecordUpdateArg, UntypedStatement, UntypedTypeAlias, UntypedUse,
    UseAssignment,
};
use gleam_core::parse::SpannedString;
use gleam_core::type_::error::VariableOrigin;
use gleam_core::type_::Deprecation;
use gleam_core::warning::WarningEmitter;

use crate::ast::{ErrorInfo, LiteralValue, Module, Node, Span};
use crate::span::LineIndex;

/// The path reported in parse diagnostics. See `main::REPORTED_PATH`.
const REPORTED_PATH: &str = "metastatic_input.gleam";

/// Parses `source` into the M1 [`Module`].
///
/// Returns the structured error the Elixir side formats, never a panic: a
/// parse error from `gleam_core` is a value, and the only other failure mode
/// (a byte offset outside the source) already degrades to `Span::UNKNOWN`.
pub fn parse_module(source: &str) -> Result<Module, ErrorInfo> {
    let path = Utf8PathBuf::from(REPORTED_PATH);
    let warnings = WarningEmitter::null();

    let parsed =
        gleam_core::parse::parse_module(path, source, &warnings).map_err(|error| ErrorInfo {
            kind: "ParseError".to_string(),
            msg: describe_parse_error(&error),
            line: Some(error_line(&error, source)),
        })?;

    let index = LineIndex::new(source);
    let module = &parsed.module;

    let mut children = Vec::with_capacity(module.definitions.len());
    for TargetedDefinition { definition, target } in &module.definitions {
        children.push(definition_node(definition, &index, target.map(target_name)));
    }

    let comments = parsed
        .extra
        .module_comments
        .iter()
        .map(|span| {
            index
                .slice(span.start, span.end)
                .trim_start_matches('/')
                .trim()
                .to_string()
        })
        .collect();

    let span = module_span(source, &index);
    Ok(Module::new(span, comments, children))
}

/// The span covering the whole file.
///
/// `Module` itself carries no `SrcSpan`, so the extent comes from the source:
/// line 1 column 1 through the last character.
fn module_span(source: &str, index: &LineIndex<'_>) -> Span {
    let end = source.len() as u32;
    index.span(0, end)
}

/// Renders a `gleam_core` parse error as one readable sentence.
///
/// `ParseErrorType::details/0` is `pub(crate)`, so the structured text is not
/// reachable from here. What *is* reachable is `Debug`, which for the
/// interesting variants carries the token and the expectation
/// (`UnexpectedToken { token: RPar, expected: ["a type"] }`). Rather than
/// printing raw `Debug` output, the common variants are spelled out and the
/// rest fall back to their `Debug` form — honest about what it cannot
/// translate, and never wrong.
fn describe_parse_error(error: &gleam_core::parse::error::ParseError) -> String {
    use gleam_core::parse::error::ParseErrorType;

    // `ParseError::error` is boxed in the vendored snapshot and unboxed in
    // some upstream revisions. `Box` is `Deref<Target = T>` and `T` is
    // `Deref<Target = T>` for every `T`, so `AsRef` is the one bound that
    // holds for both; `unbox` below picks the right view.
    match unbox(&error.error) {
        ParseErrorType::UnexpectedEof => "unexpected end of file".to_string(),
        ParseErrorType::UnexpectedToken {
            token,
            expected,
            hint,
            ..
        } => {
            let expected = expected.join(" or ");
            match hint {
                Some(hint) => format!("unexpected `{token}`, expected {expected} ({hint})"),
                None => format!("unexpected `{token}`, expected {expected}"),
            }
        }
        ParseErrorType::ExpectedName => "expected a name".to_string(),
        ParseErrorType::ExpectedUpName => "expected a type name".to_string(),
        ParseErrorType::ExpectedExpr => "expected an expression".to_string(),
        ParseErrorType::ExpectedPattern => "expected a pattern".to_string(),
        ParseErrorType::ExpectedType => "expected a type".to_string(),
        ParseErrorType::ExpectedValue => "expected a value".to_string(),
        ParseErrorType::ExpectedEqual => "expected `=`".to_string(),
        ParseErrorType::ExpectedDefinition => "expected a definition".to_string(),
        ParseErrorType::ExpectedFunctionDefinition => "expected a function definition".to_string(),
        ParseErrorType::LexError { error } => describe_lexical_error(&error.error),
        other => format!("{other:?}"),
    }
}

/// Borrows a `ParseErrorType` through either a `Box<ParseErrorType>` or a bare
/// `ParseErrorType`.
///
/// The vendored snapshot boxes the field; upstream has shipped it unboxed.
/// Rather than pinning this file to one revision, the two shapes are absorbed
/// here so a `vendor.sh` refresh does not break the bridge.
fn unbox(
    error: &impl std::borrow::Borrow<gleam_core::parse::error::ParseErrorType>,
) -> &gleam_core::parse::error::ParseErrorType {
    error.borrow()
}

/// Renders the lexical half of a parse error.
fn describe_lexical_error(error: &gleam_core::parse::error::LexicalErrorType) -> String {
    use gleam_core::parse::error::LexicalErrorType;

    match error {
        LexicalErrorType::UnrecognizedToken { token } => {
            format!("unrecognised character `{token}`")
        }
        LexicalErrorType::UnexpectedStringEnd => "unterminated string literal".to_string(),
        LexicalErrorType::BadStringEscape => "invalid escape sequence in a string".to_string(),
        LexicalErrorType::DigitOutOfRadix => "digit out of range for the radix".to_string(),
        LexicalErrorType::NumTrailingUnderscore => {
            "a number cannot end with an underscore".to_string()
        }
        LexicalErrorType::RadixIntNoValue => "a radix prefix needs a value".to_string(),
        LexicalErrorType::MissingExponent => "an exponent needs a value".to_string(),
        LexicalErrorType::InvalidTripleEqual => "`===` is not a Gleam operator".to_string(),
        LexicalErrorType::MergeConflictIndicator => "unresolved merge conflict markers".to_string(),
        LexicalErrorType::UnsupportedProceduralOperator => {
            "Gleam has no compound assignment operators".to_string()
        }
        LexicalErrorType::InvalidUnicodeEscape(_) => "invalid unicode escape".to_string(),
        LexicalErrorType::VisuallySimilarInvalidCharacter { name, correct } => {
            format!("`{name}` looks like ASCII `{correct}` but is not")
        }
    }
}

/// The 1-based line a parse error points at.
///
/// `pub(crate)` because `from_json::format_source` needs it too: the printer
/// wraps the same `ParseError`, and reporting a line for `format` but not for
/// `parse` on identical input would be a wart.
pub(crate) fn error_line(error: &gleam_core::parse::error::ParseError, source: &str) -> usize {
    let index = LineIndex::new(source);
    index.line_of(error.location.start)
}

// ─────────────────────────────────────────────────────────────────────
// Definitions
// ─────────────────────────────────────────────────────────────────────

/// The Gleam name of a `Target`, for the `@target(…)` attribute.
fn target_name(target: gleam_core::build::Target) -> &'static str {
    match target {
        gleam_core::build::Target::Erlang => "erlang",
        gleam_core::build::Target::JavaScript => "javascript",
    }
}

/// One top-level definition.
///
/// `targeted` carries the `@target(…)` name when the definition had one, which
/// the reifier needs to restore the attribute.
fn definition_node(
    definition: &UntypedDefinition,
    index: &LineIndex<'_>,
    targeted: Option<&str>,
) -> Node {
    let mut node = match definition {
        Definition::Function(function) => function_node(function, index),
        Definition::Import(import) => import_node(import, index),
        Definition::TypeAlias(alias) => type_alias_node(alias, index),
        Definition::CustomType(custom_type) => custom_type_node(custom_type, index),
        Definition::ModuleConstant(constant) => module_constant_node(constant, index),
    };

    if let Some(target_name) = targeted {
        // The definition's `@target(…)` attribute is part of its identity: a
        // reified tree without it would be compiled for both backends. The
        // target name is recorded (under `target`) so the reifier restores the
        // exact attribute instead of guessing one.
        //
        // Merged into the existing `extra` rather than replacing it: `extra`
        // already carries `publicity`, and overwriting it silently dropped
        // `pub` from every targeted definition.
        let mut extra = node.extra.take().unwrap_or_else(|| serde_json::json!({}));
        if let Some(map) = extra.as_object_mut() {
            map.insert(
                "target".to_string(),
                serde_json::Value::String(target_name.to_string()),
            );
        }
        node.extra = Some(extra);
    }

    node
}

/// `pub fn name(args) -> Ret { body }`
fn function_node(function: &UntypedFunction, index: &LineIndex<'_>) -> Node {
    let mut node = Node::new(
        "Fn",
        index.span(function.location.start, function.end_position),
    )
    .with_name(
        function
            .name
            .as_ref()
            .map(|(_, name)| name.clone())
            .unwrap_or_default(),
    );

    node.public = matches!(function.publicity, Publicity::Public);

    let mut children = Vec::new();
    for argument in &function.arguments {
        children.push(arg_node(argument, index));
    }
    for statement in &function.body {
        children.push(statement_node(statement, index));
    }

    node.children = children;
    node.type_node = function
        .return_annotation
        .as_ref()
        .map(|annotation| Box::new(type_ast_node(annotation, index)));

    node.extra = Some(function_extra(function, index));
    node
}

/// The parts of a function that do not fit a child slot.
fn function_extra(function: &UntypedFunction, index: &LineIndex<'_>) -> serde_json::Value {
    let mut extra = serde_json::json!({
        "publicity": publicity_name(&function.publicity),
        "deprecated": deprecation_message(&function.deprecation),
        "purity": purity_name(&function.purity),
    });

    let map = extra.as_object_mut().expect("object literal");
    map.insert(
        "implementations".to_string(),
        implementations_json(&function.implementations),
    );

    if let Some((_, documentation)) = &function.documentation {
        map.insert(
            "documentation".to_string(),
            serde_json::Value::String(documentation.to_string()),
        );
    }

    if let Some((module, function_name, span)) = &function.external_erlang {
        map.insert(
            "external_erlang".to_string(),
            serde_json::json!({
                "module": module,
                "function": function_name,
                "span": span_json(index.span(span.start, span.end)),
            }),
        );
    }

    if let Some((module, function_name, span)) = &function.external_javascript {
        map.insert(
            "external_javascript".to_string(),
            serde_json::json!({
                "module": module,
                "function": function_name,
                "span": span_json(index.span(span.start, span.end)),
            }),
        );
    }

    extra
}

/// `import gleam/list.{map as m, type List}`
fn import_node(import: &UntypedImport, index: &LineIndex<'_>) -> Node {
    let mut node = Node::new(
        "Import",
        index.span(import.location.start, import.location.end),
    )
    .with_name(import.module.clone());

    let mut extra = serde_json::json!({
        "values": import
            .unqualified_values
            .iter()
            .map(unqualified_import_json)
            .collect::<Vec<_>>(),
        "types": import
            .unqualified_types
            .iter()
            .map(unqualified_import_json)
            .collect::<Vec<_>>(),
    });

    let map = extra.as_object_mut().expect("object literal");

    if let Some((as_name, _)) = &import.as_name {
        map.insert(
            "as_name".to_string(),
            serde_json::Value::String(as_name.name().to_string()),
        );
        map.insert(
            "as_discard".to_string(),
            serde_json::Value::Bool(matches!(as_name, gleam_core::ast::AssignName::Discard(_))),
        );
    }

    if let Some(documentation) = &import.documentation {
        map.insert(
            "documentation".to_string(),
            serde_json::Value::String(documentation.to_string()),
        );
    }

    node.extra = Some(extra);
    node
}

fn unqualified_import_json(import: &UnqualifiedImport) -> serde_json::Value {
    serde_json::json!({
        "name": import.name,
        "as_name": import.as_name,
    })
}

/// `pub type Name(a) = Type`
fn type_alias_node(alias: &UntypedTypeAlias, index: &LineIndex<'_>) -> Node {
    let mut node = Node::new(
        "TypeAlias",
        index.span(alias.location.start, alias.location.end),
    )
    .with_name(alias.alias.clone());

    node.public = matches!(alias.publicity, Publicity::Public);
    node.type_node = Some(Box::new(type_ast_node(&alias.type_ast, index)));
    node.extra = Some(serde_json::json!({
        "publicity": publicity_name(&alias.publicity),
        "parameters": parameters_json(&alias.parameters),
        "deprecated": deprecation_message(&alias.deprecation),
        "documentation": alias.documentation.as_ref().map(|(_, doc)| doc.to_string()),
    }));

    node
}

/// `pub type Name { Constructor(Int) }`
fn custom_type_node(custom_type: &UntypedCustomType, index: &LineIndex<'_>) -> Node {
    let mut node = Node::new(
        "CustomType",
        index.span(custom_type.location.start, custom_type.end_position),
    )
    .with_name(custom_type.name.clone());

    node.public = matches!(custom_type.publicity, Publicity::Public);
    node.opaque = custom_type.opaque;
    node.children = custom_type
        .constructors
        .iter()
        .map(|constructor| record_constructor_node(constructor, index))
        .collect();

    node.extra = Some(serde_json::json!({
        "publicity": publicity_name(&custom_type.publicity),
        "parameters": parameters_json(&custom_type.parameters),
        "deprecated": deprecation_message(&custom_type.deprecation),
        "documentation": custom_type.documentation.as_ref().map(|(_, doc)| doc.to_string()),
    }));

    node
}

fn record_constructor_node(constructor: &RecordConstructor<()>, index: &LineIndex<'_>) -> Node {
    let mut node = Node::new(
        "RecordConstructor",
        index.span(constructor.location.start, constructor.location.end),
    )
    .with_name(constructor.name.clone());

    node.children = constructor
        .arguments
        .iter()
        .map(|argument| record_constructor_arg_node(argument, index))
        .collect();

    node.extra = Some(serde_json::json!({
        "deprecated": deprecation_message(&constructor.deprecation),
        "documentation": constructor.documentation.as_ref().map(|(_, doc)| doc.to_string()),
    }));

    node
}

fn record_constructor_arg_node(argument: &RecordConstructorArg<()>, index: &LineIndex<'_>) -> Node {
    let mut node = Node::new(
        "RecordConstructorArg",
        index.span(argument.location.start, argument.location.end),
    );

    node.type_node = Some(Box::new(type_ast_node(&argument.ast, index)));
    node.extra = Some(serde_json::json!({
        "label": argument.label.as_ref().map(|(_, label)| label.to_string()),
        "documentation": argument.doc.as_ref().map(|(_, doc)| doc.to_string()),
    }));

    node
}

/// `pub const name: Type = value`
fn module_constant_node(constant: &UntypedModuleConstant, index: &LineIndex<'_>) -> Node {
    let mut node = Node::new(
        "ModuleConstant",
        index.span(constant.location.start, constant.location.end),
    )
    .with_name(constant.name.clone());

    node.public = matches!(constant.publicity, Publicity::Public);
    node.type_node = constant
        .annotation
        .as_ref()
        .map(|annotation| Box::new(type_ast_node(annotation, index)));
    node.children = vec![constant_node(&constant.value, index)];
    node.extra = Some(serde_json::json!({
        "publicity": publicity_name(&constant.publicity),
        "documentation": constant.documentation.as_ref().map(|(_, doc)| doc.to_string()),
    }));

    node
}

// ─────────────────────────────────────────────────────────────────────
// Statements and expressions
// ─────────────────────────────────────────────────────────────────────

fn statement_node(statement: &UntypedStatement, index: &LineIndex<'_>) -> Node {
    match statement {
        Statement::Expression(expression) => expr_node(expression, index),
        Statement::Assignment(assignment) => assignment_node(assignment, index),
        Statement::Use(use_) => use_node(use_, index),
        Statement::Assert(assert) => assert_node(assert, index),
    }
}

/// `let pattern = value`
fn assignment_node(assignment: &UntypedAssignment, index: &LineIndex<'_>) -> Node {
    let span = index.span(assignment.location.start, assignment.location.end);
    let mut node = Node::new("Let", span);

    node.pattern = Some(Box::new(pattern_node(&assignment.pattern, index)));
    node.children = vec![expr_node(&assignment.value, index)];
    node.type_node = assignment
        .annotation
        .as_ref()
        .map(|annotation| Box::new(type_ast_node(annotation, index)));

    node.extra = Some(serde_json::json!({
        "kind": assignment_kind_name(&assignment.kind),
    }));

    node
}

fn assignment_kind_name(kind: &AssignmentKind<UntypedExpr>) -> &'static str {
    match kind {
        AssignmentKind::Let => "let",
        AssignmentKind::Assert { .. } => "assert",
        // Assignments the compiler synthesises while desugaring a `use` or a
        // pattern assert. They never appear in a parsed module, but the enum
        // has the variant, so it is named rather than wildcarded.
        AssignmentKind::Generated => "generated",
    }
}

/// `use a <- result.try(x)`
fn use_node(use_: &UntypedUse, index: &LineIndex<'_>) -> Node {
    let mut node = Node::new("Use", index.span(use_.location.start, use_.location.end));

    node.children = vec![expr_node(&use_.call, index)];
    node.extra = Some(serde_json::json!({
        "assignments": use_
            .assignments
            .iter()
            .map(|assignment| use_assignment_json(assignment, index))
            .collect::<Vec<_>>(),
        "right_hand_side": span_json(index.span(
            use_.right_hand_side_location.start,
            use_.right_hand_side_location.end,
        )),
    }));

    node
}

fn use_assignment_json(assignment: &UseAssignment<()>, index: &LineIndex<'_>) -> serde_json::Value {
    serde_json::json!({
        "pattern": serde_json::to_value(pattern_node(&assignment.pattern, index)).unwrap_or_default(),
        "annotation": assignment
            .annotation
            .as_ref()
            .map(|annotation| serde_json::to_value(type_ast_node(annotation, index)).unwrap_or_default()),
    })
}

/// `assert value` / `assert value as "message"`
fn assert_node(assert: &Assert<UntypedExpr>, index: &LineIndex<'_>) -> Node {
    let mut node = Node::new(
        "Assert",
        index.span(assert.location.start, assert.location.end),
    );

    node.children = vec![expr_node(&assert.value, index)];
    if let Some(message) = &assert.message {
        node.children.push(expr_node(message, index));
    }

    node
}

/// One expression.
///
/// Every `UntypedExpr` variant is matched explicitly — see the module
/// documentation for why there is no wildcard arm.
fn expr_node(expression: &UntypedExpr, index: &LineIndex<'_>) -> Node {
    match expression {
        UntypedExpr::Int {
            location, value, ..
        } => literal_node(
            "Int",
            index.span(location.start, location.end),
            LiteralValue::Integer(value.to_string()),
        ),

        UntypedExpr::Float {
            location, value, ..
        } => literal_node(
            "Float",
            index.span(location.start, location.end),
            LiteralValue::Float(value.to_string()),
        ),

        UntypedExpr::String { location, value } => literal_node(
            "String",
            index.span(location.start, location.end),
            LiteralValue::String(value.to_string()),
        ),

        UntypedExpr::Var { location, name } => {
            Node::new("Var", index.span(location.start, location.end)).with_name(name.clone())
        }

        UntypedExpr::Block {
            location,
            statements,
        } => Node::with_children(
            "Block",
            index.span(location.start, location.end),
            statements
                .iter()
                .map(|statement| statement_node(statement, index))
                .collect(),
        ),

        UntypedExpr::Fn {
            location,
            kind,
            arguments,
            body,
            return_annotation,
            ..
        } => {
            let mut node = Node::new("FnLiteral", index.span(location.start, location.end));

            let mut children: Vec<Node> = arguments
                .iter()
                .map(|argument| arg_node(argument, index))
                .collect();
            children.extend(
                body.iter()
                    .map(|statement| statement_node(statement, index)),
            );

            node.children = children;
            node.type_node = return_annotation
                .as_ref()
                .map(|annotation| Box::new(type_ast_node(annotation, index)));
            node.extra = Some(serde_json::json!({
                "kind": function_literal_kind_name(kind),
                "hole": function_literal_hole(kind, index),
            }));

            node
        }

        UntypedExpr::List {
            location,
            elements,
            tail,
        } => {
            let mut node = Node::with_children(
                "List",
                index.span(location.start, location.end),
                elements
                    .iter()
                    .map(|element| expr_node(element, index))
                    .collect(),
            );

            node.extra = Some(serde_json::json!({
                "tail": tail
                    .as_ref()
                    .map(|tail| serde_json::to_value(expr_node(tail, index)).unwrap_or_default()),
            }));

            node
        }

        UntypedExpr::Call {
            location,
            fun,
            arguments,
            ..
        } => {
            let mut node = Node::new("Call", index.span(location.start, location.end));

            let mut children = vec![expr_node(fun, index)];
            children.extend(
                arguments
                    .iter()
                    .map(|argument| call_arg_node(argument, index)),
            );
            node.children = children;

            node
        }

        UntypedExpr::BinOp {
            location,
            operator,
            left,
            right,
            ..
        } => {
            let mut node = Node::with_children(
                "BinOp",
                index.span(location.start, location.end),
                vec![expr_node(left, index), expr_node(right, index)],
            );

            node.name = Some(operator.name().to_string());
            node.extra = Some(serde_json::json!({
                "operator": binop_variant_name(operator),
            }));

            node
        }

        UntypedExpr::Pipeline { expressions } => Node::with_children(
            "Pipeline",
            index.span(
                expressions.first().location().start,
                expressions.last().location().end,
            ),
            expressions
                .iter()
                .map(|expression| expr_node(expression, index))
                .collect(),
        ),

        UntypedExpr::Case {
            location,
            subjects,
            clauses,
        } => {
            let mut node = Node::new("Case", index.span(location.start, location.end));

            node.children = subjects
                .iter()
                .map(|subject| expr_node(subject, index))
                .collect();

            if let Some(clauses) = clauses {
                node.children
                    .extend(clauses.iter().map(|clause| clause_node(clause, index)));
            }

            node
        }

        UntypedExpr::FieldAccess {
            location,
            label,
            container,
            ..
        } => {
            let mut node = Node::with_children(
                "FieldAccess",
                index.span(location.start, location.end),
                vec![expr_node(container, index)],
            );

            node.name = Some(label.to_string());
            node
        }

        UntypedExpr::Tuple { location, elements } => Node::with_children(
            "Tuple",
            index.span(location.start, location.end),
            elements
                .iter()
                .map(|element| expr_node(element, index))
                .collect(),
        ),

        UntypedExpr::TupleIndex {
            location,
            index: tuple_index,
            tuple,
        } => {
            let mut node = Node::with_children(
                "TupleIndex",
                index.span(location.start, location.end),
                vec![expr_node(tuple, index)],
            );

            node.extra = Some(serde_json::json!({ "index": tuple_index }));
            node
        }

        UntypedExpr::Todo {
            kind,
            location,
            message,
        } => {
            let mut node = Node::new("Todo", index.span(location.start, location.end));

            node.children = message
                .as_ref()
                .map(|message| vec![expr_node(message, index)])
                .unwrap_or_default();
            node.extra = Some(serde_json::json!({ "kind": todo_kind_name(kind) }));

            node
        }

        UntypedExpr::Panic { location, message } => {
            let mut node = Node::new("Panic", index.span(location.start, location.end));

            node.children = message
                .as_ref()
                .map(|message| vec![expr_node(message, index)])
                .unwrap_or_default();

            node
        }

        UntypedExpr::Echo {
            location,
            expression,
            message,
            ..
        } => {
            let mut node = Node::new("Echo", index.span(location.start, location.end));

            node.children = expression
                .as_ref()
                .map(|expression| vec![expr_node(expression, index)])
                .unwrap_or_default();
            if let Some(message) = message {
                node.children.push(expr_node(message, index));
            }

            node
        }

        UntypedExpr::BitArray { location, segments } => Node::with_children(
            "BitArray",
            index.span(location.start, location.end),
            segments
                .iter()
                .map(|segment| bit_array_segment_node(segment, index))
                .collect(),
        ),

        UntypedExpr::RecordUpdate {
            location,
            constructor,
            record,
            arguments,
            ..
        } => {
            let mut node = Node::new("RecordUpdate", index.span(location.start, location.end));

            let mut children = vec![
                expr_node(constructor, index),
                expr_node(&record.base, index),
            ];
            children.extend(
                arguments
                    .iter()
                    .map(|argument| record_update_arg_node(argument, index)),
            );
            node.children = children;

            node
        }

        UntypedExpr::NegateBool { location, value } => unary_node(
            "NegateBool",
            index.span(location.start, location.end),
            value,
            index,
        ),

        UntypedExpr::NegateInt { location, value } => unary_node(
            "NegateInt",
            index.span(location.start, location.end),
            value,
            index,
        ),
    }
}

fn unary_node(kind: &str, span: Span, value: &UntypedExpr, index: &LineIndex<'_>) -> Node {
    Node::with_children(kind, span, vec![expr_node(value, index)])
}

fn literal_node(kind: &str, span: Span, value: LiteralValue) -> Node {
    Node {
        value: Some(value),
        ..Node::new(kind, span)
    }
}

/// One `case` clause.
fn clause_node(clause: &UntypedClause, index: &LineIndex<'_>) -> Node {
    let mut node = Node::new(
        "Clause",
        index.span(clause.location.start, clause.location.end),
    );

    let mut patterns: Vec<Node> = clause
        .pattern
        .iter()
        .map(|pattern| pattern_node(pattern, index))
        .collect();

    for alternative in &clause.alternative_patterns {
        patterns.extend(
            alternative
                .iter()
                .map(|pattern| pattern_node(pattern, index)),
        );
    }

    node.children = patterns;
    node.children.push(expr_node(&clause.then, index));
    node.extra = Some(serde_json::json!({
        "pattern_count": clause.pattern_count(),
        "alternative_patterns": clause.alternative_patterns.len(),
        "guard": clause
            .guard
            .as_ref()
            .map(|guard| serde_json::to_value(clause_guard_node(guard, index)).unwrap_or_default()),
    }));

    node
}

fn arg_node(argument: &UntypedArg, index: &LineIndex<'_>) -> Node {
    let mut node = Node::new(
        "Arg",
        index.span(argument.location.start, argument.location.end),
    );

    node.name = Some(argument_name(&argument.names));
    node.discard = matches!(
        argument.names,
        ArgNames::Discard { .. } | ArgNames::LabelledDiscard { .. }
    );
    node.type_node = argument
        .annotation
        .as_ref()
        .map(|annotation| Box::new(type_ast_node(annotation, index)));
    node.extra = Some(serde_json::json!({
        "label": argument.names.get_label().map(|(label, _)| label.to_string()),
        "names": arg_names_json(&argument.names, index),
    }));

    node
}

fn arg_names_json(names: &ArgNames, index: &LineIndex<'_>) -> serde_json::Value {
    match names {
        ArgNames::Discard { name, location } => serde_json::json!({
            "kind": "discard",
            "name": name,
            "span": span_json(index.span(location.start, location.end)),
        }),
        ArgNames::LabelledDiscard {
            label,
            label_location,
            name,
            name_location,
        } => serde_json::json!({
            "kind": "labelled_discard",
            "label": label,
            "label_span": span_json(index.span(label_location.start, label_location.end)),
            "name": name,
            "span": span_json(index.span(name_location.start, name_location.end)),
        }),
        ArgNames::Named { name, location } => serde_json::json!({
            "kind": "named",
            "name": name,
            "span": span_json(index.span(location.start, location.end)),
        }),
        ArgNames::NamedLabelled {
            label,
            label_location,
            name,
            name_location,
        } => serde_json::json!({
            "kind": "named_labelled",
            "label": label,
            "label_span": span_json(index.span(label_location.start, label_location.end)),
            "name": name,
            "span": span_json(index.span(name_location.start, name_location.end)),
        }),
    }
}

fn argument_name(names: &ArgNames) -> String {
    match names {
        ArgNames::Discard { name, .. }
        | ArgNames::LabelledDiscard { name, .. }
        | ArgNames::Named { name, .. }
        | ArgNames::NamedLabelled { name, .. } => name.to_string(),
    }
}

fn call_arg_node(argument: &CallArg<UntypedExpr>, index: &LineIndex<'_>) -> Node {
    let mut node = Node::with_children(
        "CallArg",
        index.span(argument.location.start, argument.location.end),
        vec![expr_node(&argument.value, index)],
    );

    node.extra = Some(serde_json::json!({ "label": argument.label }));

    node
}

fn record_update_arg_node(argument: &UntypedRecordUpdateArg, index: &LineIndex<'_>) -> Node {
    let mut node = Node::with_children(
        "RecordUpdateArg",
        index.span(argument.location.start, argument.location.end),
        vec![expr_node(&argument.value, index)],
    );

    node.name = Some(argument.label.to_string());

    node
}

fn bit_array_segment_node(segment: &UntypedExprBitArraySegment, index: &LineIndex<'_>) -> Node {
    let mut node = Node::new(
        "BitArraySegment",
        index.span(segment.location.start, segment.location.end),
    );

    node.children = vec![expr_node(&segment.value, index)];
    node.extra = Some(serde_json::json!({
        "options": segment
            .options
            .iter()
            .map(|option| bit_array_option_json(option, index))
            .collect::<Vec<_>>(),
    }));

    node
}

fn bit_array_option_json<Value>(
    option: &BitArrayOption<Value>,
    index: &LineIndex<'_>,
) -> serde_json::Value
where
    Value: Nodeable,
{
    match option {
        BitArrayOption::Bytes { location } => option_json("bytes", location, index, None),
        BitArrayOption::Int { location } => option_json("int", location, index, None),
        BitArrayOption::Float { location } => option_json("float", location, index, None),
        BitArrayOption::Bits { location } => option_json("bits", location, index, None),
        BitArrayOption::Utf8 { location } => option_json("utf8", location, index, None),
        BitArrayOption::Utf16 { location } => option_json("utf16", location, index, None),
        BitArrayOption::Utf32 { location } => option_json("utf32", location, index, None),
        BitArrayOption::Utf8Codepoint { location } => {
            option_json("utf8_codepoint", location, index, None)
        }
        BitArrayOption::Utf16Codepoint { location } => {
            option_json("utf16_codepoint", location, index, None)
        }
        BitArrayOption::Utf32Codepoint { location } => {
            option_json("utf32_codepoint", location, index, None)
        }
        BitArrayOption::Signed { location } => option_json("signed", location, index, None),
        BitArrayOption::Unsigned { location } => option_json("unsigned", location, index, None),
        BitArrayOption::Big { location } => option_json("big", location, index, None),
        BitArrayOption::Little { location } => option_json("little", location, index, None),
        BitArrayOption::Native { location } => option_json("native", location, index, None),
        BitArrayOption::Size {
            location,
            value,
            short_form,
        } => option_json(
            "size",
            location,
            index,
            Some(serde_json::json!({
                "value": serde_json::to_value(value.to_node(index)).unwrap_or_default(),
                "short_form": short_form,
            })),
        ),
        BitArrayOption::Unit { location, value } => option_json(
            "unit",
            location,
            index,
            Some(serde_json::json!({ "value": value })),
        ),
    }
}

/// Anything that can be turned into an M1 [`Node`].
///
/// `BitArrayOption<Value>` is generic over the segment's value type, and the
/// three instantiations (`UntypedExpr`, `UntypedPattern`, `UntypedConstant`)
/// share the option list verbatim. Rather than three copies of
/// `bit_array_option_json`, the helper is generic over this trait, which has
/// exactly three implementations.
trait Nodeable {
    fn to_node(&self, index: &LineIndex<'_>) -> Node;
}

impl Nodeable for UntypedExpr {
    fn to_node(&self, index: &LineIndex<'_>) -> Node {
        expr_node(self, index)
    }
}

impl Nodeable for UntypedPattern {
    fn to_node(&self, index: &LineIndex<'_>) -> Node {
        pattern_node(self, index)
    }
}

impl Nodeable for UntypedConstant {
    fn to_node(&self, index: &LineIndex<'_>) -> Node {
        constant_node(self, index)
    }
}

fn option_json(
    name: &str,
    location: &src_span::SrcSpan,
    index: &LineIndex<'_>,
    extra: Option<serde_json::Value>,
) -> serde_json::Value {
    let mut value = serde_json::json!({
        "name": name,
        "span": span_json(index.span(location.start, location.end)),
    });

    if let (Some(extra), Some(map)) = (extra, value.as_object_mut()) {
        map.insert("extra".to_string(), extra);
    }

    value
}

// ─────────────────────────────────────────────────────────────────────
// Patterns
// ─────────────────────────────────────────────────────────────────────

fn pattern_node(pattern: &UntypedPattern, index: &LineIndex<'_>) -> Node {
    match pattern {
        Pattern::Int {
            location, value, ..
        } => literal_node(
            "Int",
            index.span(location.start, location.end),
            LiteralValue::Integer(value.to_string()),
        ),

        Pattern::Float {
            location, value, ..
        } => literal_node(
            "Float",
            index.span(location.start, location.end),
            LiteralValue::Float(value.to_string()),
        ),

        Pattern::String { location, value } => literal_node(
            "String",
            index.span(location.start, location.end),
            LiteralValue::String(value.to_string()),
        ),

        Pattern::Variable {
            location,
            name,
            origin,
            ..
        } => {
            let mut node =
                Node::new("Var", index.span(location.start, location.end)).with_name(name.clone());

            node.extra = Some(serde_json::json!({
                "origin": variable_origin_json(origin),
            }));

            node
        }

        Pattern::Discard { location, name, .. } => {
            let mut node = Node::new("Discard", index.span(location.start, location.end))
                .with_name(name.clone());

            node.discard = true;
            node
        }

        Pattern::Assign {
            name,
            location,
            pattern,
        } => {
            let mut node = Node::with_children(
                "Assign",
                index.span(location.start, location.end),
                vec![pattern_node(pattern, index)],
            );

            node.name = Some(name.to_string());
            node
        }

        Pattern::List {
            location,
            elements,
            tail,
            ..
        } => {
            let mut node = Node::with_children(
                "List",
                index.span(location.start, location.end),
                elements
                    .iter()
                    .map(|element| pattern_node(element, index))
                    .collect(),
            );

            node.extra = Some(serde_json::json!({
                "tail": tail
                    .as_ref()
                    .map(|tail| serde_json::to_value(tail_pattern_json(tail, index)).unwrap_or_default()),
            }));

            node
        }

        Pattern::Constructor {
            location,
            name,
            arguments,
            module,
            spread,
            ..
        } => {
            let mut node = Node::new("Constructor", index.span(location.start, location.end))
                .with_name(name.clone());

            node.children = arguments
                .iter()
                .map(|argument| call_arg_pattern_node(argument, index))
                .collect();
            node.extra = Some(serde_json::json!({
                "module": module.as_ref().map(|(module, _)| module.to_string()),
                "spread": spread.map(|span| span_json(index.span(span.start, span.end))),
            }));

            node
        }

        Pattern::Tuple { location, elements } => Node::with_children(
            "Tuple",
            index.span(location.start, location.end),
            elements
                .iter()
                .map(|element| pattern_node(element, index))
                .collect(),
        ),

        Pattern::BitArray { location, segments } => Node::with_children(
            "BitArray",
            index.span(location.start, location.end),
            segments
                .iter()
                .map(|segment| bit_array_pattern_segment_node(segment, index))
                .collect(),
        ),

        Pattern::StringPrefix {
            location,
            left_side_string,
            right_side_assignment,
            ..
        } => {
            let mut node = Node::new("StringPrefix", index.span(location.start, location.end));

            node.name = Some(right_side_assignment.name().to_string());
            node.extra = Some(serde_json::json!({
                "left": left_side_string,
                "discard": matches!(
                    right_side_assignment,
                    gleam_core::ast::AssignName::Discard(_)
                ),
            }));

            node
        }

        Pattern::Invalid { location, .. } => {
            Node::new("InvalidPattern", index.span(location.start, location.end))
        }

        Pattern::BitArraySize(size) => bit_array_size_node(size, index),
    }
}

fn tail_pattern_json(
    tail: &gleam_core::ast::TailPattern<()>,
    index: &LineIndex<'_>,
) -> serde_json::Value {
    serde_json::json!({
        "pattern": serde_json::to_value(pattern_node(&tail.pattern, index)).unwrap_or_default(),
        "location": span_json(index.span(tail.location.start, tail.location.end)),
    })
}

fn call_arg_pattern_node(argument: &CallArg<UntypedPattern>, index: &LineIndex<'_>) -> Node {
    let mut node = Node::with_children(
        "CallArg",
        index.span(argument.location.start, argument.location.end),
        vec![pattern_node(&argument.value, index)],
    );

    node.extra = Some(serde_json::json!({ "label": argument.label }));

    node
}

fn bit_array_pattern_segment_node(
    segment: &gleam_core::ast::UntypedPatternBitArraySegment,
    index: &LineIndex<'_>,
) -> Node {
    let mut node = Node::new(
        "BitArraySegment",
        index.span(segment.location.start, segment.location.end),
    );

    node.children = vec![pattern_node(&segment.value, index)];
    node.extra = Some(serde_json::json!({
        "options": segment
            .options
            .iter()
            .map(|option| bit_array_option_json(option, index))
            .collect::<Vec<_>>(),
    }));

    node
}

fn bit_array_size_node(size: &gleam_core::ast::BitArraySize<()>, index: &LineIndex<'_>) -> Node {
    use gleam_core::ast::BitArraySize;

    match size {
        BitArraySize::Int {
            location, value, ..
        } => literal_node(
            "Int",
            index.span(location.start, location.end),
            LiteralValue::Integer(value.to_string()),
        ),

        BitArraySize::Variable { location, name, .. } => {
            Node::new("Var", index.span(location.start, location.end)).with_name(name.clone())
        }

        BitArraySize::BinaryOperator {
            location,
            operator,
            left,
            right,
        } => {
            let mut node = Node::with_children(
                "BinOp",
                index.span(location.start, location.end),
                vec![
                    bit_array_size_node(left, index),
                    bit_array_size_node(right, index),
                ],
            );

            node.name = Some(operator.to_bin_op().name().to_string());
            node.extra = Some(serde_json::json!({
                "operator": binop_variant_name(&operator.to_bin_op()),
            }));

            node
        }

        BitArraySize::Block { location, inner } => Node::with_children(
            "Block",
            index.span(location.start, location.end),
            vec![bit_array_size_node(inner, index)],
        ),
    }
}

// ─────────────────────────────────────────────────────────────────────
// Types
// ─────────────────────────────────────────────────────────────────────

fn type_ast_node(type_ast: &TypeAst, index: &LineIndex<'_>) -> Node {
    match type_ast {
        TypeAst::Constructor(constructor) => type_ast_constructor_node(constructor, index),

        TypeAst::Fn(TypeAstFn {
            location,
            arguments,
            return_,
        }) => {
            let mut node = Node::new("FnType", index.span(location.start, location.end));

            let mut children: Vec<Node> = arguments
                .iter()
                .map(|argument| type_ast_node(argument, index))
                .collect();
            children.push(type_ast_node(return_, index));
            node.children = children;

            node
        }

        TypeAst::Var(TypeAstVar { location, name }) => {
            Node::new("TypeVar", index.span(location.start, location.end)).with_name(name.clone())
        }

        TypeAst::Tuple(TypeAstTuple { location, elements }) => Node::with_children(
            "TupleType",
            index.span(location.start, location.end),
            elements
                .iter()
                .map(|element| type_ast_node(element, index))
                .collect(),
        ),

        TypeAst::Hole(TypeAstHole { location, name }) => {
            Node::new("TypeHole", index.span(location.start, location.end)).with_name(name.clone())
        }
    }
}

fn type_ast_constructor_node(constructor: &TypeAstConstructor, index: &LineIndex<'_>) -> Node {
    let mut node = Node::with_children(
        "TypeConstructor",
        index.span(constructor.location.start, constructor.location.end),
        constructor
            .arguments
            .iter()
            .map(|argument| type_ast_node(argument, index))
            .collect(),
    );

    node.extra = Some(match &constructor.name {
        TypeAstConstructorName::Unqualified { name, .. } => {
            node.name = Some(name.to_string());
            serde_json::json!({ "module": serde_json::Value::Null })
        }
        TypeAstConstructorName::Qualified { module, name, .. } => {
            node.name = name.as_ref().map(|(name, _)| name.to_string());
            serde_json::json!({ "module": module.to_string() })
        }
    });

    node
}

// ─────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────

fn constant_node(constant: &UntypedConstant, index: &LineIndex<'_>) -> Node {
    match constant {
        Constant::Int {
            location, value, ..
        } => literal_node(
            "Int",
            index.span(location.start, location.end),
            LiteralValue::Integer(value.to_string()),
        ),

        Constant::Float {
            location, value, ..
        } => literal_node(
            "Float",
            index.span(location.start, location.end),
            LiteralValue::Float(value.to_string()),
        ),

        Constant::String { location, value } => literal_node(
            "String",
            index.span(location.start, location.end),
            LiteralValue::String(value.to_string()),
        ),

        Constant::Tuple {
            location, elements, ..
        } => Node::with_children(
            "Tuple",
            index.span(location.start, location.end),
            elements
                .iter()
                .map(|element| constant_node(element, index))
                .collect(),
        ),

        Constant::List {
            location,
            elements,
            tail,
            ..
        } => {
            let mut node = Node::with_children(
                "List",
                index.span(location.start, location.end),
                elements
                    .iter()
                    .map(|element| constant_node(element, index))
                    .collect(),
            );

            node.extra = Some(serde_json::json!({
                "tail": tail
                    .as_ref()
                    .map(|tail| serde_json::to_value(constant_node(tail, index)).unwrap_or_default()),
            }));

            node
        }

        Constant::Record {
            location,
            module,
            name,
            arguments,
            ..
        } => {
            let mut node = Node::new("Record", index.span(location.start, location.end))
                .with_name(name.clone());

            node.children = arguments
                .as_ref()
                .map(|arguments| {
                    arguments
                        .iter()
                        .map(|argument| call_arg_constant_node(argument, index))
                        .collect()
                })
                .unwrap_or_default();
            node.extra = Some(serde_json::json!({
                "module": module.as_ref().map(|(module, _)| module.to_string()),
                "has_arguments": arguments.is_some(),
            }));

            node
        }

        Constant::RecordUpdate {
            location,
            module,
            name,
            record,
            arguments,
            ..
        } => {
            let mut node = Node::new("RecordUpdate", index.span(location.start, location.end))
                .with_name(name.clone());

            let mut children = vec![constant_node(&record.base, index)];
            children.extend(
                arguments
                    .iter()
                    .map(|argument| record_update_arg_constant_node(argument, index)),
            );
            node.children = children;
            node.extra = Some(serde_json::json!({
                "module": module.as_ref().map(|(module, _)| module.to_string()),
            }));

            node
        }

        Constant::BitArray { location, segments } => Node::with_children(
            "BitArray",
            index.span(location.start, location.end),
            segments
                .iter()
                .map(|segment| bit_array_constant_segment_node(segment, index))
                .collect(),
        ),

        Constant::Var {
            location,
            module,
            name,
            ..
        } => {
            let mut node =
                Node::new("Var", index.span(location.start, location.end)).with_name(name.clone());

            node.extra = Some(serde_json::json!({
                "module": module.as_ref().map(|(module, _)| module.to_string()),
            }));

            node
        }

        Constant::BinaryOperator {
            location,
            operator,
            left,
            right,
            ..
        } => {
            let mut node = Node::with_children(
                "BinOp",
                index.span(location.start, location.end),
                vec![constant_node(left, index), constant_node(right, index)],
            );

            node.name = Some(operator.name().to_string());
            node.extra = Some(serde_json::json!({
                "operator": binop_variant_name(operator),
            }));

            node
        }

        Constant::Invalid { location, .. } => {
            Node::new("InvalidConstant", index.span(location.start, location.end))
        }

        Constant::Todo {
            location, message, ..
        } => {
            let mut node = Node::new("Todo", index.span(location.start, location.end));

            node.children = message
                .as_ref()
                .map(|message| vec![constant_node(message, index)])
                .unwrap_or_default();

            node
        }
    }
}

fn call_arg_constant_node(argument: &CallArg<UntypedConstant>, index: &LineIndex<'_>) -> Node {
    let mut node = Node::with_children(
        "CallArg",
        index.span(argument.location.start, argument.location.end),
        vec![constant_node(&argument.value, index)],
    );

    node.extra = Some(serde_json::json!({ "label": argument.label }));

    node
}

fn record_update_arg_constant_node(
    argument: &gleam_core::ast::RecordUpdateArg<UntypedConstant>,
    index: &LineIndex<'_>,
) -> Node {
    let mut node = Node::with_children(
        "RecordUpdateArg",
        index.span(argument.location.start, argument.location.end),
        vec![constant_node(&argument.value, index)],
    );

    node.name = Some(argument.label.to_string());

    node
}

fn bit_array_constant_segment_node(
    segment: &gleam_core::ast::UntypedConstantBitArraySegment,
    index: &LineIndex<'_>,
) -> Node {
    let mut node = Node::new(
        "BitArraySegment",
        index.span(segment.location.start, segment.location.end),
    );

    node.children = vec![constant_node(&segment.value, index)];
    node.extra = Some(serde_json::json!({
        "options": segment
            .options
            .iter()
            .map(|option| bit_array_option_json(option, index))
            .collect::<Vec<_>>(),
    }));

    node
}

// ─────────────────────────────────────────────────────────────────────
// Guards
// ─────────────────────────────────────────────────────────────────────

fn clause_guard_node(guard: &UntypedClauseGuard, index: &LineIndex<'_>) -> Node {
    match guard {
        ClauseGuard::Block { location, value } => Node::with_children(
            "Block",
            index.span(location.start, location.end),
            vec![clause_guard_node(value, index)],
        ),

        ClauseGuard::BinaryOperator {
            location,
            operator,
            left,
            right,
            ..
        } => {
            let mut node = Node::with_children(
                "BinOp",
                index.span(location.start, location.end),
                vec![
                    clause_guard_node(left, index),
                    clause_guard_node(right, index),
                ],
            );

            node.name = Some(operator.name().to_string());
            node.extra = Some(serde_json::json!({
                "operator": binop_variant_name(operator),
            }));

            node
        }

        ClauseGuard::Not {
            location,
            expression,
        } => Node::with_children(
            "Not",
            index.span(location.start, location.end),
            vec![clause_guard_node(expression, index)],
        ),

        ClauseGuard::Var { location, name, .. } => {
            Node::new("Var", index.span(location.start, location.end)).with_name(name.clone())
        }

        ClauseGuard::TupleIndex {
            location,
            index: tuple_index,
            tuple,
            ..
        } => {
            let mut node = Node::with_children(
                "TupleIndex",
                index.span(location.start, location.end),
                vec![clause_guard_node(tuple, index)],
            );

            node.extra = Some(serde_json::json!({ "index": tuple_index }));
            node
        }

        ClauseGuard::FieldAccess {
            label_location,
            label,
            container,
            ..
        } => {
            let mut node = Node::with_children(
                "FieldAccess",
                index.span(container.location().start, label_location.end),
                vec![clause_guard_node(container, index)],
            );

            node.name = Some(label.to_string());
            node
        }

        ClauseGuard::ModuleSelect {
            location,
            label,
            module_name,
            literal,
            ..
        } => {
            let mut node = Node::new("ModuleSelect", index.span(location.start, location.end))
                .with_name(label.clone());

            node.children = vec![constant_node(literal, index)];
            node.extra = Some(serde_json::json!({ "module": module_name.to_string() }));

            node
        }

        ClauseGuard::Constant(constant) => constant_node(constant, index),

        ClauseGuard::Invalid { location, .. } => {
            Node::new("InvalidGuard", index.span(location.start, location.end))
        }
    }
}

// ─────────────────────────────────────────────────────────────────────
// Small helpers
// ─────────────────────────────────────────────────────────────────────

fn span_json(span: Span) -> serde_json::Value {
    serde_json::json!({
        "line": span.line,
        "col": span.col,
        "end_line": span.end_line,
        "end_col": span.end_col,
    })
}

fn parameters_json(parameters: &[SpannedString]) -> Vec<String> {
    parameters
        .iter()
        .map(|(_, name)| name.to_string())
        .collect()
}

fn publicity_name(publicity: &Publicity) -> &'static str {
    match publicity {
        Publicity::Public => "public",
        Publicity::Private => "private",
        Publicity::Internal { .. } => "internal",
    }
}

fn deprecation_message(deprecation: &Deprecation) -> Option<String> {
    match deprecation {
        Deprecation::NotDeprecated => None,
        Deprecation::Deprecated { message } => Some(message.to_string()),
    }
}

/// The `Purity` of a function, as a stable string.
///
/// `gleam_core::type_::expression` is a private module, so `Purity` cannot be
/// named here. `Debug` is the only public view of it, and its variant names
/// (`Pure`, `Trusted`, `Impure`) are what the string is derived from — which
/// keeps this working without vendoring a patch into the compiler.
fn purity_name(purity: &impl std::fmt::Debug) -> String {
    format!("{purity:?}").to_lowercase()
}

/// The target implementations a function provides.
///
/// Same privacy constraint as `purity_name/1`: `Implementations` is not
/// nameable, so its `Debug` rendering is parsed into the same JSON shape the
/// Elixir side expects. The struct is a plain record of five booleans, so its
/// `Debug` output is stable and unambiguous.
fn implementations_json(implementations: &impl std::fmt::Debug) -> serde_json::Value {
    let rendered = format!("{implementations:?}");

    let flag = |name: &str| -> bool {
        rendered
            .split(',')
            .filter_map(|part| part.split_once(':'))
            .any(|(key, value)| key.trim() == name && value.trim() == "true")
    };

    serde_json::json!({
        "gleam": flag("gleam"),
        "erlang": flag("can_run_on_erlang"),
        "javascript": flag("can_run_on_javascript"),
        "erlang_externals": flag("uses_erlang_externals"),
        "javascript_externals": flag("uses_javascript_externals"),
    })
}

fn variable_origin_json(origin: &VariableOrigin) -> serde_json::Value {
    serde_json::json!({
        "syntax": format!("{:?}", origin.syntax),
        "declaration": format!("{:?}", origin.declaration),
    })
}

fn function_literal_kind_name(kind: &gleam_core::ast::FunctionLiteralKind) -> &'static str {
    match kind {
        gleam_core::ast::FunctionLiteralKind::Capture { .. } => "capture",
        gleam_core::ast::FunctionLiteralKind::Anonymous { .. } => "anonymous",
        gleam_core::ast::FunctionLiteralKind::Use { .. } => "use",
    }
}

fn function_literal_hole(
    kind: &gleam_core::ast::FunctionLiteralKind,
    index: &LineIndex<'_>,
) -> Option<serde_json::Value> {
    match kind {
        gleam_core::ast::FunctionLiteralKind::Capture { hole } => {
            Some(span_json(index.span(hole.start, hole.end)))
        }
        gleam_core::ast::FunctionLiteralKind::Anonymous { head } => {
            Some(span_json(index.span(head.start, head.end)))
        }
        gleam_core::ast::FunctionLiteralKind::Use { location } => {
            Some(span_json(index.span(location.start, location.end)))
        }
    }
}

fn todo_kind_name(kind: &gleam_core::ast::TodoKind) -> &'static str {
    match kind {
        gleam_core::ast::TodoKind::Keyword => "keyword",
        gleam_core::ast::TodoKind::EmptyFunction { .. } => "empty_function",
        gleam_core::ast::TodoKind::IncompleteUse => "incomplete_use",
        gleam_core::ast::TodoKind::EmptyBlock => "empty_block",
    }
}

/// The upstream variant name of a `BinOp`, so the reifier can rebuild the
/// exact operator (including the int/float distinction that `name()` erases:
/// `+.` and `+` both print as `+` in some contexts).
fn binop_variant_name(operator: &gleam_core::ast::BinOp) -> String {
    format!("{operator:?}")
}

/// Kept so the `EcoString` import is used even if a future refactor drops the
/// last direct mention.
#[allow(dead_code)]
fn _ecow_marker(_: &EcoString) {}

// ─────────────────────────────────────────────────────────────────────
// Self-test
// ─────────────────────────────────────────────────────────────────────

/// One self-test result.
pub struct Check {
    pub name: &'static str,
    pub passed: bool,
    pub detail: String,
}

/// Verifies the binary that is about to be used.
///
/// The checks are deliberately about *behaviour of this build*, not about the
/// source tree: a stale binary and a fresh one have identical sources, so only
/// running them tells them apart.
pub fn selftest() -> Vec<Check> {
    vec![
        check_parse_spans(),
        check_round_trip(),
        check_format_reachable(),
        check_error_reporting(),
    ]
}

const SAMPLE: &str = "import gleam/io\n\npub fn main() {\n  io.println(\"hi\")\n}\n";

fn check_parse_spans() -> Check {
    match parse_module(SAMPLE) {
        Ok(module) => {
            let located = module
                .children
                .iter()
                .filter(|node| node.span.line > 0)
                .count();
            Check {
                name: "parse_spans",
                passed: located == module.children.len() && !module.children.is_empty(),
                detail: format!(
                    "{located}/{} definitions carry a line",
                    module.children.len()
                ),
            }
        }
        Err(error) => Check {
            name: "parse_spans",
            passed: false,
            detail: error.msg,
        },
    }
}

fn check_round_trip() -> Check {
    let parsed = match parse_module(SAMPLE) {
        Ok(module) => module,
        Err(error) => {
            return Check {
                name: "round_trip",
                passed: false,
                detail: error.msg,
            };
        }
    };

    let json = match serde_json::to_value(&parsed) {
        Ok(json) => json,
        Err(error) => {
            return Check {
                name: "round_trip",
                passed: false,
                detail: error.to_string(),
            };
        }
    };

    match crate::from_json::render(&json) {
        Ok(source) => match parse_module(&source) {
            Ok(reparsed) => Check {
                name: "round_trip",
                passed: reparsed.children.len() == parsed.children.len(),
                detail: format!(
                    "{} definitions before, {} after",
                    parsed.children.len(),
                    reparsed.children.len()
                ),
            },
            Err(error) => Check {
                name: "round_trip",
                passed: false,
                detail: format!("re-parse failed: {}", error.msg),
            },
        },
        Err(error) => Check {
            name: "round_trip",
            passed: false,
            detail: error.msg,
        },
    }
}

fn check_format_reachable() -> Check {
    match crate::from_json::format_source(SAMPLE) {
        Ok(formatted) => Check {
            name: "format",
            passed: formatted.contains("pub fn main()"),
            detail: format!("{} bytes", formatted.len()),
        },
        Err(error) => Check {
            name: "format",
            passed: false,
            detail: error.msg,
        },
    }
}

fn check_error_reporting() -> Check {
    match parse_module("pub fn main( {\n") {
        Ok(_) => Check {
            name: "error_reporting",
            passed: false,
            detail: "malformed source parsed without an error".to_string(),
        },
        Err(error) => Check {
            name: "error_reporting",
            passed: error.line.is_some() && !error.msg.is_empty(),
            detail: format!("line {:?}: {}", error.line, error.msg),
        },
    }
}
