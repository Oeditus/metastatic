# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

## [0.1.0] - 2026-01-21

MVP

## Notes

This project follows a rigorous theoretical foundation based on:
- OMG Meta Object Facility (MOF) Specification
- Eclipse Modeling Framework (EMF)
- Formal meta-modeling theory

See `THEORETICAL_FOUNDATIONS.md` for the complete formal treatment with proofs.
