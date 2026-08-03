# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Refactored -- Cache Behaviour & Backend Pluggability
- **`Metastatic.Cache` Behaviour** -- replaced inline `if_dllb_available` checkers in `Metastatic.Cache` with a pluggable behaviour (`init/0`, `get/2`, `put/4`, `clear/0`) and facade dispatcher.
- **Cache Backends** -- added `Metastatic.Cache.ETS` (default ETS memory cache) and `Metastatic.Cache.DLLB` (`Dllb` database cache).
- **Configuration & Dependencies** -- added optional `:dllb` dependency (`runtime: false`) and introduced `:metastatic, :cache` config option accepting `:ets` (default) or `:dllb`.

### Added -- Cure v0.20.0 catch-up
- **`:bin_segment` (M2.1 Core)** -- new node type for a single element of
  a bitstring literal / pattern (`<<value::type-size(n)-unit(u)-sign-endian>>`).
  Shape `{:bin_segment, meta, [value]}` with optional meta keys
  `:type`, `:signedness`, `:endianness`, `:size` (AST node), `:unit`
  (integer). Added to `@core_types`, given a `valid_node?/3` clause,
  a `Metastatic.AST.bin_segment/2` builder helper, `AST.to_string/1`
  rendering, and handlers in the Cure and Elixir `FromMeta` adapters.
- **`:comment` (M2.1 Core)** -- new trivia node representing a source
  comment. Shape `{:comment, meta, text}` with `:comment_kind` meta
  (`:line` / `:doc` / `:block`). Analyzers and codegens skip comments;
  formatters and documentation tooling round-trip them. Added to
  `@core_types`, given a `valid_node?/3` clause, the
  `Metastatic.AST.comment/3` builder, `AST.to_string/1` rendering,
  leaf-safe traversal wiring, and handlers in both `FromMeta`
  adapters (Elixir collapses them to `nil` because its tokenizer
  strips comments from quoted ASTs).
- **`:literal` subtype `:bytes` dual shape.** The validator now
  accepts either the historical `binary()` payload or a list of
  `:bin_segment` children. When the payload is a segment list,
  `AST.traverse/4`, `AST.prewalker/1`, `AST.postwalker/1`,
  `AST.path/2`, and `AST.variables/1` descend into each segment's
  value so analyzers see the bound names inside
  `<<x::utf8, rest::binary>>`-style patterns.
- **`Metastatic.Adapters.Cure.ToMeta`** -- new abstraction adapter
  that parses Cure source through the Cure compiler's lexer + parser
  (when linked in at runtime) and normalises the resulting MetaAST
  (default `:comment_kind` metadata, atom-coerced `:bin_segment`
  specifiers, recursive `:param` normalisation). Exposes
  `from_source/2`, `from_ast/1`, and `normalize/1`.
- **`Metastatic.Adapters.Cure.abstract/3`** -- routes through the new
  `ToMeta.from_source/2`, threads the `preserve_comments:` option, and
  returns a `Document` with `metadata: %{language: :cure}` so the
  result round-trips cleanly through `Adapter.round_trip/2`.
- **`METAST_SPEC.md`** -- adds dedicated `:bin_segment` and
  `:comment` subsections under M2.1 Core, documents the dual `:bytes`
  payload, and updates the Node Type Reference table.

### Added -- previously unreleased
- **MetaAST nodes backported from Cure v0.18.0 -- v0.19.0:**
  - `:pin` (M2.2 Extended) -- pattern-position pin operator `^x`.
    Shape `{:pin, meta, [inner]}`. Promoted from a dead placeholder
    entry in the Elixir adapter to a first-class node type recognised
    by `Metastatic.AST.conforms?/1`.
  - `:assert_type` (M2.2 Extended) -- compile-time type assertion
    `assert_type expr : T`. Shape `{:assert_type, meta, [expr, type_ast]}`.
    Reified by the Cure adapter; dropped to `expr` by the Elixir adapter
    (Elixir has no surface syntax for it).
  - `container_type: :proof` -- new value of the `:container` metadata
    key emitted by Cure for `proof Name.Path` containers. Structurally
    identical to `:module` but semantically a proposition-level namespace.
- **MetaAST nodes backported from earlier Cure releases:**
  - `:record_update` (M2.2s Structural, Cure v0.15.0) -- functional
    record update `Name{base | field: val, ...}`. Shape
    `{:record_update, [name: "Name", ...], [base | field_pairs]}`.
  - `container_type: :fsm` (Cure v0.7.0) -- finite state machine
    container `fsm Name with Payload`. Carries optional FSM metadata
    (`:payload`, `:terminal_states`, `:invariants`, `:verify`, `:timer`,
    `:on_transition`, `:on_enter`, `:on_exit`, `:on_failure`,
    `:on_timer`); transitions are `:function_call` nodes with `:from`,
    `:event`, `:to`, and `:event_kind` metadata.
- `Metastatic.Adapters.Cure.FromMeta` now reifies `:pin`, `:assert_type`,
  `:record_update`, and `container_type: :proof` / `:fsm` instead of
  falling back to `inspect/1`. The new `emit_fsm/3` helper renders the
  container header (`fsm Name [with Payload]`), the transition body, the
  optional `@timer <ms>` annotation, and any `on_transition` /
  `on_enter` / `on_exit` / `on_failure` / `on_timer` callback blocks.
- **Macro-like AST traversal and manipulation API** -- mirrors Elixir's `Macro` module for MetaAST:
  - `prewalk/2`, `postwalk/2` -- transform-only tree walks (no accumulator)
  - `prewalker/1`, `postwalker/1` -- lazy enumerable traversals (`Stream`-based)
  - `path/2` -- find the path from a matching node up to the root
  - `unpipe/1` -- flatten nested `:pipe` chains into a list of `{node, position}` tuples
  - `pipe_into/3` -- inject an expression into a `:function_call` argument list at a given position
  - `decompose_call/1` -- extract `{name, args}` from `:function_call` nodes (returns `:error` otherwise)
  - `to_string/1` -- human-readable pseudo-code representation of MetaAST for debugging
  - `literal?/1` -- recursively check whether a subtree is composed entirely of literal values
  - `operator?/1` -- predicate for `:binary_op` and `:unary_op` nodes
  - `validate/1` -- structural validation returning `:ok` or `{:error, {:invalid_node, node}}`
  - `unique_var/1` -- generate unique variable nodes with monotonic counter
- All new functions available on both `Metastatic.AST` (canonical) and `Metastatic` (convenience delegates)
- Full `@doc`, `@spec`, and doctests for every new function
- 1992 tests passing (336 doctests + 1656 tests), zero regressions

### Documentation
- Added "AST Traversal & Manipulation" section to README.md explaining why traversal matters and
  showing walking, lazy enumeration, path-finding, pipe utilities, predicates, and inspection
- Added "AST Traversal & Manipulation" section to GETTING_STARTED.md with comprehensive examples
  for every new function and a quick-reference list

## [0.15.1] - 2026-04-12

Major adapter overhaul: all five language adapters now emit proper M2 types instead of falling back
to `:language_specific`, alongside new M2 node types, Erlang adapter expansion, and comprehensive
documentation with mermaid diagrams. 1919 tests passing (263 doctests + 1656 tests), zero regressions.

### Added
- **New M2 node types:**
  - `:throw` (M2.1 Core) -- raise/throw across languages
  - `:yield` (M2.2 Extended) -- generators (`yield`/`yield_from`)
  - `:decorator` (M2.2s Structural) -- decorators/annotations
- **`:bitwise` operator category** for `band`, `bor`, `bxor`, `bsl`, `bsr`, `<<`, `>>`
- **Expanded `container_type`:** `:interface`, `:trait`, `:protocol`, `:enum`, `:struct`
- **New literal subtypes:** `:char`, `:bytes`
- **New loop types:** `:do_while`, `:infinite`
- **Expanded `import_type`:** `:from`, `:module`, `:export`
- Builder helpers: `throw_node/3`, `yield_node/3`, `decorator/3`
- Erlang adapter: `-module(Name)` -> `:container`; function defs -> `:function_def` with params;
  `fun` expressions -> `:lambda`; `fun Name/Arity` -> `:lambda` with `capture_form`;
  `try`/`catch`/`after` -> `:exception_handling`; `#{...}` -> `:map` with `:pair` children;
  `-export([...])` -> `:import` with export type; `receive` remains `:language_specific`
- Python `with` statement -> `:block` with `[original_form: :with]` and inline_match bindings
- Mermaid diagrams throughout: `GETTING_STARTED.md`, `RESEARCH.md`, `METAST_SPEC.md`,
  `SUPPLEMENTAL_MODULES.md`, module docstrings (`ast.ex`, `adapter.ex`, `validator.ex`),
  and mix task docs

### Changed
- **Ruby adapter:** `dstr` -> `:string_interpolation`; `irange`/`erange` -> `:range` with
  `[inclusive: true/false]`; `break`/`next` -> `:early_return` with `[kind: :break/:continue]`;
  `regexp` -> `:literal` with `[subtype: :regex, flags: [...]]`; `<<`/`>>` -> `category: :bitwise`;
  round-trip (`from_meta`) support added for all new types
- **Python adapter:** All comprehensions (`ListComp`/`DictComp`/`SetComp`/`GeneratorExp`) ->
  `:comprehension` with proper `:generator`/`:filter` children; `match` (3.10+) ->
  `:pattern_match` with `:match_arm` children; `AugAssign` -> `:augmented_assignment`;
  `NamedExpr` (walrus `:=`) -> `:inline_match`; `Raise` -> `:throw`; `Yield`/`YieldFrom` ->
  `:yield`; `AsyncFunctionDef` -> `:function_def` with `[async: true]`; decorated
  functions/classes -> proper M2 nodes with `[decorators: [...]]`
- **Haskell adapter:** modules -> `:container` with `container_type: :module`; function bindings ->
  `:function_def`; type signatures -> `:type_annotation` with `[annotation_type: :spec]`; list
  comprehensions -> `:comprehension` with `[comp_type: :list]`; `class_decl` -> `:container` with
  `container_type: :interface`
- **Erlang adapter:** bitwise ops -> `category: :bitwise`; char literals -> `subtype: :char`
- 1919 tests passing (263 doctests + 1656 tests), zero regressions

## [0.12.1] - 2026-03-24

### Added
- **Comprehensive Ruby/Rails Support** - Major expansion of the Ruby adapter:
  - Safe navigation operator (`&.`) via `csend` AST type: maps to `function_call`/`attribute_access` with `null_safe: true`
  - Conditional assignment operators: `||=` (`or_asgn`) and `&&=` (`and_asgn`) map to `augmented_assignment`
  - All Ruby parameter types: `optarg`, `kwarg`, `kwoptarg`, `restarg`, `kwrestarg`, `blockarg`, `forward_arg`
  - Variable binding forms for `ivasgn`, `cvasgn`, `gvasgn` (1-child targets in `||=`/`&&=`)
  - Multi-statement `kwbegin` blocks (explicit `begin...end`)
  - FromMeta round-trip: `csend` reconstruction, `or_asgn`/`and_asgn` reconstruction, all parameter types
  - Fixed fragile `collection_op` from_meta lambda extraction
  - Parser now emits `end_line` and `end_column` in location info
  - 3 Rails fixture files for testing (model, concern, service)
  - 41 new tests including integration tests against 53-file Rails app (51/53 transform successfully)
  - Test suite: 255 doctests + 1646 tests, 0 failures

## [0.12.0] - 2026-03-19

### Added
- **OpKind Semantic Metadata System** - Semantic operation kind metadata for accurate code analysis:
  - New `Metastatic.Semantic.OpKind` module providing semantic meaning for function calls and operations
  - Supports 7 domains: `:db`, `:http`, `:auth`, `:cache`, `:queue`, `:file`, `:external_api`
  - Rich operation types for each domain (e.g., DB: retrieve, retrieve_all, query, create, update, delete, transaction, preload, aggregate)
  - Framework-aware detection (Ecto, Django, Sequelize, ActiveRecord, etc.)
  - OpKind stored in `:op_kind` metadata field of `:function_call` nodes
  - 5 business logic analyzers updated to use OpKind with semantic-first, heuristic-fallback pattern:
    - BlockingInPlug: Checks OpKind domain for blocking operations
    - MissingTelemetryForExternalHttp: Uses OpKind.http?() for HTTP detection
    - SyncOverAsync: Identifies blocking operations via OpKind domain
    - InefficientFilter: Detects fetch-all operations via OpKind (domain: :db, operation: :retrieve_all/:query)
    - TOCTOU: Identifies file check/use operations via OpKind
  - Significantly improves analyzer accuracy while maintaining backward compatibility
  - Example: `{:function_call, [name: "Repo.get", op_kind: [domain: :db, operation: :retrieve, target: "User"]], [args...]}`

### Changed
- **Uniform 3-Tuple MetaAST Format** - Complete migration to `{type_atom, keyword_meta, children_or_value}` structure:
  - All MetaAST nodes now use a uniform 3-tuple format for consistency and easier pattern matching
  - Metadata moved to keyword lists in the second element (e.g., `[subtype: :integer]`, `[operator: :+]`)
  - Children/value in the third element (list for composites, value for leaves)
  - Updated all 5 language adapters (Python, Elixir, Ruby, Erlang, Haskell) to produce 3-tuple output
  - Updated all 9 analysis tools (complexity, duplication, metrics, etc.) for new format
  - Updated all 20 business logic analyzers for new format:
    - SwallowingException: Updated `exception_handling` pattern matching
    - NPlusOneQuery: Fixed lambda detection with `Keyword.keyword?` check
    - InefficientFilter: Added handler for `function_def` bodies
    - TelemetryInRecursiveFunction: Fixed body traversal through all children
    - MissingPreload: Updated `collection_op` format handling
  - Fixed Elixir adapter try/rescue transformation with pre_transform marker
  - Fixed `extract_module_name/1` to handle `{:literal, _, atom}` format
  - Test suite: 1,422 tests passing (235 doctests + 1,187 tests, 100% coverage)

### Added
- M1 Metadata Preservation - Full context threading for Ragex integration:
  - Expanded location type with optional M1 context fields: `:language`, `:module`, `:function`, `:arity`, `:container`, `:visibility`, `:file`, `:m1_meta`
  - Added AST helper functions: `with_context/2`, `extract_metadata/2`, `node_module/1`, `node_function/1`, `node_arity/1`, `node_file/1`, `node_container/1`, `node_visibility/1`
  - Elixir adapter now attaches module and function context to structural nodes (container, function_def)
  - Runner properly handles location-aware nodes (both with and without metadata) in `update_contexts/2` and `extract_children/2`
  - Analyzer.issue/1 helper automatically extracts location metadata from nodes
  - Updated TelemetryInRecursiveFunction analyzer to handle both 6-tuple and 7-tuple function_def patterns
  - All 1,431 tests passing (202 doctests + 1,229 tests including 14 new metadata tests)
  - Enables Ragex to access function names, arities, modules, and locations from business logic analyzers
- Business Logic Analyzers - 20 language-agnostic analyzers ported from oeditus_credo:
  - **Tier 1 (Pure MetaAST, 9 analyzers)**: CallbackHell, MissingErrorHandling, SilentErrorCase, SwallowingException, HardcodedValue, NPlusOneQuery, InefficientFilter, UnmanagedTask, TelemetryInRecursiveFunction
  - **Tier 2 (Function Name Heuristics, 4 analyzers)**: MissingTelemetryForExternalHttp, SyncOverAsync, DirectStructUpdate, MissingHandleAsync
  - **Tier 3 (Naming Conventions, 4 analyzers)**: BlockingInPlug, MissingTelemetryInAuthPlug, MissingTelemetryInLiveviewMount, MissingTelemetryInObanWorker
  - **Tier 4 (Content Analysis, 3 analyzers)**: MissingPreload, InlineJavascript, MissingThrottle
  - Each analyzer includes comprehensive cross-language examples (Python, JavaScript, Elixir, C#, Go, Java, Ruby, Rust)
  - Total: ~4,800 lines across 20 analyzer modules
  - All 1,282 tests passing (142 doctests + 1,140 tests)
  - Demonstrates that business logic analysis is fundamentally language-agnostic
- M2.1 Core Layer enhancements:
  - `list` type for list/array literals (moved from literal collection to first-class core type)
  - `map` type for map/dictionary/object literals (moved from literal collection to first-class core type)
  - Updated all language adapters (Python, Elixir) to use new list/map types
  - Updated all analysis modules to traverse list elements and map key-value pairs
  - Updated validator to classify list/map as core layer
  - Updated CLI tools (inspector, formatter) to handle list/map display
  - Added 12 new tests for list/map functionality (1,356 total tests passing: 131 doctests + 1,225 tests)
- M2.2s Structural/Organizational Layer - New meta-model layer for cross-language structural constructs
  - `container` type for modules/classes/namespaces with visibility-aware member tracking
  - `function_def` type for function/method definitions with guards, visibility, and pattern parameters
  - `attribute_access` type for field/property access on objects
  - `augmented_assignment` type for compound assignment operators (+=, -=, etc.)
  - `property` type for property declarations with getters/setters
- Full support for M2.2s types across all analysis modules:
  - Duplication fingerprinting (Type I/II clone detection)
  - Cyclomatic complexity analysis
  - Cognitive complexity analysis
  - Nesting depth tracking
  - Halstead metrics (operators/operands)
  - Function metrics (statements, returns)
  - Lines of code (LoC) counting
- Comprehensive test coverage: 143 new tests for structural types (1,149 total tests passing)
- Helper functions: `container_name/1`, `function_name/1`, `function_visibility/1`, `has_state?/1`

### Documentation
- Added `STRUCTURAL_LAYER_RESEARCH.md` - Theory and cross-language analysis of structural constructs
- Added `STRUCTURAL_LAYER_DESIGN.md` - Implementation design decisions and rationale
- Updated `README.md` with M2.2s layer description
- Enhanced `@typedoc` for all structural types with M1 instances and examples

### Mix Tasks
- All 15 mix tasks now have comprehensive `@moduledoc` documentation and `@impl Mix.Task`
- Added ruby and haskell language support to `analyze`, `complexity`, `purity_check`, `translate`, `validate_equivalence`
- `detect_duplicates` now fully implemented - parses real source files via language adapters

## [0.1.0] - 2026-01-21

MVP

## Notes

This project follows a rigorous theoretical foundation based on:
- OMG Meta Object Facility (MOF) Specification
- Eclipse Modeling Framework (EMF)
- Formal meta-modeling theory

See `THEORETICAL_FOUNDATIONS.md` for the complete formal treatment with proofs.
