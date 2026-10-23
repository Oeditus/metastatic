# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

### Added -- Project audit, canonicalisation & conformance tooling
- **`Metastatic.MetaAST`** -- new shared core for MetaAST-shaped trees. Owns the
  uniform 3-tuple accessors (`type/1`, `meta/1`, `children/1`), metadata helpers
  (`get_meta/3`, `put_meta/3`, `update_meta/2,4`), traversal (`traverse/4`,
  `prewalk/2`, `postwalk/2`), lazy walkers (`prewalker/1`, `prewalker/3`) and
  `path/2`. Both `Metastatic.AST` and `Metastatic.NL.AST` delegate to it, so the
  two meta-ASTs can no longer drift apart in their shared surface (R-3).
- **Adapter contract guard** (`test/metastatic/adapter_contract_test.exs`) --
  enumerates every adapter in `Metastatic.Languages` and asserts it satisfies the
  `Metastatic.Adapter` contract, so a new language cannot be merged below the
  quality bar (R-5).
- **Adapter conformance suites** for JavaScript, TypeScript and Ruby, joining the
  existing Python/Elixir/Erlang suites (R-5).
- **`AUDIT.md`** -- full project audit (findings `F-1`…`F-22`, recommendations
  `R-1`…`R-5`) with the executed roadmap and a final R-1..R-5 status section.
  `R-1`…`R-5`) with the executed roadmap.
- **`Metastatic.AST.canonicalize/1`** and **`AST.semantic_meta_keys/0`** -- strip
  incidental metadata (locations, `original_meta`, formatting) to a canonical
  form. `Metastatic.Document.equivalent?/2` is now a thin wrapper over it, so the
  cross-language equivalence claim is backed by one shared definition instead of
  a private, drift-prone whitelist.
- **Cross-language conformance matrix test**
  (`test/metastatic/cross_language_conformance_test.exs`) -- asserts that the
  same expression canonicalises identically across every available adapter, and
  documents Ruby's bare-identifier ambiguity as a known, intentional difference.
- **Property-based round-trip tests** (`stream_data`) -- randomised MetaAST trees
  are reified and re-abstracted per adapter, asserting canonical stability and
### Tests
- **Mix-task coverage** -- the three previously-untested Mix tasks now have
  dedicated suites: `metastatic.gen.supplemental` (0 % -> 100 %),
  `metastatic.lint.prose` (0 % -> 88.5 %), and `metastatic.supplemental_check`
  (0 % -> 62.7 %), covering argument validation, exit codes, file/directory
  handling, output formats and parse errors. Project coverage 58.2 % -> 60.3 %.

### Fixed
- **`Metastatic.Supplemental.CompatibilityMatrix`**
  round-trip). Applied to the Python, Elixir and Erlang adapters.

### Fixed
- **`Metastatic.Supplemental.CompatibilityMatrix`** -- `build/0` (and therefore
  every public function) raised at runtime: it iterated `Registry.list_all()`
  as `{module, info}` tuples (it returns a bare `[module()]`) and read
  `info.target_language` / `info.dependencies` (the `Info` fields are
  `:language` / `:requires`). Now iterates modules, calls `module.info/0`, and
  uses the correct fields. Covered by a new `compatibility_matrix_test.exs`
  (module 0 % -> 100 %).
- **`Metastatic.Cache.DLLB`** -- payloads are now decoded with
  `:erlang.binary_to_term/2` **and `[:safe]`**, so a tampered or foreign cache
  cannot exhaust atoms or execute code; malformed payloads are treated as a
  cache miss. Payloads are written with `[:compressed]`.
- **`Metastatic.Cache.DLLB`** -- cache keys carry a version tag so a parser
  upgrade never serves stale MetaAST.
- **`Metastatic.Adapters.Erlang.unparse/1`** -- now appends the Erlang
  expression terminator (`.`), so generated source is re-parseable. Caught by
  the new conformance suite.
- **`mix.exs`** -- `:crypto` added to `extra_applications` (used by the DLLB
  cache key digest). The non-existent `:dllb` Hex dependency is no longer
  declared; the backend is documented as host-provided and detected at runtime.

### Changed
- **`Metastatic.Cache`** -- defaults explicitly to `:ets` instead of sniffing
  the environment; `:dllb` is opt-in.
- **`Metastatic.Cache.ETS`** -- replaced the "wipe the whole table" eviction
  cliff with age-based eviction of the oldest batch, and added key versioning.
- **`Metastatic.Semantic.Patterns`** -- the merged per-language pattern list is
  cached in `:persistent_term` and invalidated by `register/3`, removing
  per-node rebuilds during tree traversal.
- **`Metastatic.Semantic.Enricher.enrich_tree/3`** -- accepts `enrich: false` to
  skip the extra traversal; the Elixir adapter threads the option through
  `to_meta/2`.
- **`Metastatic.Supplemental.Validator`** -- rebuilt on `AST.layer/1` and
  `AST.traverse/4`, replacing a bespoke walker and two hard-coded type lists
  that had drifted from `Metastatic.AST`.
- **`Metastatic.Adapter`** -- behaviour docs updated to the 3-tuple format;
  `to_meta/2` is now an optional callback and `valid_adapter?/1` accepts either
  arity; `for_language/1` resolves through `Metastatic.Languages` instead of
  `Module.concat` (which created atoms from arbitrary input).
- **`Metastatic.Adapter.Registry`** -- refuses to silently replace a language's
  adapter with a different module (`{:error, {:already_registered, …}}`);
  re-registering the same module stays idempotent.
- **`Metastatic.Languages`** -- `:agda` and `:haskell` are tagged
  `experimental`; `parse_language/1` returns `:none` (not `nil`) for the
  "unspecified" case, making its three outcomes explicit.
- **`Metastatic.Priv`** -- `subprocess_env/1` and the `priv` search path are
  configurable (`config :metastatic, :subprocess_env` / `:priv_dirs`) instead of
  hard-coding `mise`/`~/.local` paths; the previous behaviour is the default.
- **`Metastatic.CLI.Formatter`** -- rewritten to render the `:tree`, `:json`
  and `:plain` formats from a single canonical `to_map/1` intermediate instead
  of three parallel pattern-match ladders. Node-type knowledge now lives in one
  place, and the module gained its first dedicated test suite
  (`formatter_test.exs`, 17 tests).
- **`Metastatic.NL.AST.traverse/4`** -- now traverses metadata values, matching
  `Metastatic.AST.traverse/4`.
- **`Metastatic.AST.traverse/4`** -- the metadata-walk invariant is now
  documented, and the internal `contains_meta_node?`/`meta_node?` helpers make
  explicit that only genuine 3-tuple nodes (not incidental `{:ok, _}`-style
  tuples) are descended into.

### Removed
- Unused `:typle` dependency.

### Documentation
- README: corrected the cross-language equivalence example to use
  `Document.equivalent?/2` (raw `ast ==` is false across languages because of
  location metadata); bumped the install snippet to `~> 0.32`; unpinned the logo
  URL. `mix.exs` package now ships `METAST_NL_SPEC.md`, `RESEARCH.md` and
  `CONTRIBUTING_SUPPLEMENTALS.md`.
- `Metastatic.Semantic.OpKind`: moduledoc now lists all seven domains (it
  previously claimed only `:db` was implemented).

## [Unreleased] -- prior work

### Added -- Agda Language Adapter (Option A: Haskell-based Parser Bridge)
- **`Metastatic.Adapters.Agda`** -- added complete Agda language adapter supporting bidirectional transformations between Agda source code (`.agda`, `.lagda`) and MetaAST (M2).
  - **`priv/parsers/agda/Parser.hs`** -- built-in Haskell-based parser bridge using `Agda.Syntax.Parser` and `Agda.Syntax.Concrete` to parse Agda modules, declarations, types, and expressions into JSON AST with precise source location ranges.
  - **`Metastatic.Adapters.Agda.Subprocess`** -- execution manager for the parser binary with automatic GHC compile fallback.
  - **`Metastatic.Adapters.Agda.ToMeta`** -- transforms concrete Agda AST to MetaAST layers: literals, variables, infix binary operations, lambdas, applications, arrow types, type definitions (`type_sig`, `data`, `record`), modules, imports, and postulates.
  - **`Metastatic.Adapters.Agda.FromMeta` & `Unparser`** -- reifies MetaAST back to Agda AST and unparses to valid Agda source code, supporting full cross-language translation and round-tripping.
  - **Registration** -- added `:agda` to `Metastatic.Languages` single source of truth and supported extensions (`.agda`, `.lagda`).

### Improved -- Haskell Adapter Performance & Round-Trip Unparsing
- **Direct Binary Execution in `Metastatic.Adapters.Haskell.Subprocess`** -- optimized subprocess execution to directly invoke the compiled parser binary if present instead of invoking `stack exec parser` on every run, resulting in a ~10x speedup for parsing and test suites.
- **`Metastatic.Adapters.Haskell.Unparser`** -- implemented Haskell unparsing for expressions, literals, infix operations, lambdas, conditionals, let bindings, case expressions, type signatures, and modules, enabling `Metastatic.Adapters.Haskell.unparse/1` and `Metastatic.Adapter.round_trip/2` support.

### Fixed -- Cure escript loading no longer downgrades Metastatic
- **`Metastatic.Adapters.Cure.ToMeta.load_beams/1`** -- extracted the beam loading done by the `cure` escript fallback into a public, tested function. It loads only `Cure.*` modules and never replaces a module that is already loaded or reachable on the code path.
- **Why it matters** -- the released `cure` escript embeds its own dependencies, including an older Metastatic. Before this fix (v0.30.0), the fallback force-loaded every embedded beam whose path contained "cure", which replaced `Metastatic.Adapters.Cure` with the older copy that has no `parse/1`. Hosts with `cure` on `PATH` and no Cure compiler on the code path (for example CI using `setup-cure`) then failed with `function Metastatic.Adapters.Cure.parse/1 is undefined or private`.
- **Regression tests** -- added tests covering Metastatic modules in the archive, already-loaded Cure modules, and non-beam entries.

### Added & Fixed -- Subprocess Fallback & Comprehensive Language Support
- **`Metastatic.Adapters.Cure.Subprocess`** -- added CLI / Subprocess fallback parser module for the Cure language adapter, enabling Cure source code parsing via external `cure` CLI binaries when in-process compiler modules (`Cure.Compiler.Lexer` / `Parser`) are unavailable.
- **Language Delegation in `Metastatic`** -- updated `Metastatic.languages/0`, `Metastatic.supported?/1`, and `Metastatic.adapter_for_language/1` to delegate directly to `Metastatic.Languages` single source of truth, properly exposing all 9 supported languages (`:cure`, `:elixir`, `:erlang`, `:haskell`, `:javascript`, `:march`, `:python`, `:ruby`, `:typescript`).
- **MetaCredo Cross-Language Integration Docs** -- documented the companion Elixir static analysis and linting library `MetaCredo`, highlighting its ability to analyze and lint any source code understood by `Metastatic`.
- **Documentation Audit** -- comprehensive updates across `README.md`, `GETTING_STARTED.md`, `METAST_SPEC.md`, and module docs covering March and Cure language adapters.

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
