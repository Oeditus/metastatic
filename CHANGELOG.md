# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Phase 2 - Python Adapter (In Progress)
- Python AST parser integration
- Python → MetaAST transformation
- MetaAST → Python transformation
- Round-trip testing framework

## [0.1.0] - 2026-01-20

### Phase 1 Complete - Core Foundation

#### Added
- **Core MetaAST Types** (`lib/metastatic/ast.ex`)
  - M2.1 Core layer: `literal`, `variable`, `binary_op`, `unary_op`, `function_call`, `conditional`, `early_return`, `block`
  - M2.2 Extended layer: `loop`, `lambda`, `collection_op`, `pattern_match`, `exception_handling`, `async_operation`
  - M2.3 Native layer: `language_specific` escape hatch
  - Wildcard pattern support (`:_`) for pattern matching
  - `conforms?/1` - M1 → M2 conformance validation
  - `variables/1` - Variable extraction from MetaAST

- **Document Module** (`lib/metastatic/document.ex`)
  - Document struct wrapping M2 AST with metadata
  - Language tracking and metadata management
  - `new/4` - Create documents
  - `valid?/1` - Document validation
  - `update_ast/2` - AST updates preserving metadata
  - `update_metadata/2` - Metadata merging
  - `variables/1` - Variable extraction from documents

- **Adapter Behaviour** (`lib/metastatic/adapter.ex`)
  - Behaviour defining M1 ↔ M2 transformation contract
  - Required callbacks: `parse/1`, `to_meta/1`, `from_meta/2`, `unparse/1`, `file_extensions/0`
  - Optional callback: `validate_mutation/2`
  - Helper functions: `round_trip/2`, `abstract/3`, `reify/2`, `for_language/1`, `detect_language/1`

- **Builder Module** (`lib/metastatic/builder.ex`)
  - High-level API for MetaAST construction
  - `from_source/2` - Parse source to MetaAST (Source → M1 → M2)
  - `to_source/1` - Convert MetaAST to source (M2 → M1 → Source)
  - `from_file/2` - Parse files with language detection
  - `to_file/3` - Write MetaAST to files
  - `round_trip/2` - Round-trip testing
  - `valid_source?/2` - Source validation
  - `supported_languages/0` - Query available adapters

- **Validator Module** (`lib/metastatic/validator.ex`)
  - Formal M1 → M2 conformance checking
  - Three validation modes: `:strict`, `:standard`, `:permissive`
  - `validate/2` - Full document validation with metadata
  - `valid?/2` - Quick boolean validation
  - `validate_ast/2` - AST-only validation
  - Validation metadata: level, native_constructs, warnings, variables, depth, node_count
  - Constraint checking: max_depth, max_variables
  - Warning generation: deep nesting, large ASTs, native constructs

- **Adapter Registry** (`lib/metastatic/adapter/registry.ex`) - Milestone 1.2
  - GenServer-based registry for managing language adapters
  - Dynamic adapter registration with validation
  - File extension mapping for automatic language detection
  - Concurrent access support with proper state management
  - `register/2`, `get/1`, `unregister/1`, `list/0`, `detect_language/1`
  - Integrated with application supervisor
  - 23 tests covering registration, retrieval, concurrency

- **Round-Trip Testing Framework** (`test/support/adapter_helper.ex`) - Milestone 1.2
  - Comprehensive utilities for M1 ↔ M2 transformation testing
  - `assert_round_trip/3` - Full pipeline validation
  - `assert_valid_meta_ast/3` - M2 conformance checking
  - `assert_valid_reification/3` - M2 → M1 → Source validation
  - `calculate_fidelity/2` - Levenshtein distance-based similarity scoring
  - `measure_performance/2` - Per-stage timing metrics
  - `load_fixtures/1` - Test fixture loading
  - 21 tests covering all helper functions

- **Fixture Helper Framework** (`test/support/fixture_helper.ex`) - Milestone 1.4
  - Structured fixture loading and management (301 lines)
  - Support for multiple languages with expected MetaAST outputs
  - `load_fixture/2`, `load_language/1`, `load_all/0`
  - `save_fixture/4`, `validate_fixture/2`, `stats/0`
  - Directory structure: `test/fixtures/{language}/expected/`

- **Benchmark Suite** - Milestone 1.4
  - `test/benchmarks/ast_bench.exs` - AST operation performance
  - `test/benchmarks/validation_bench.exs` - Validation performance
  - Measures ops/sec and microseconds per operation
  - Run with: `mix run test/benchmarks/ast_bench.exs`

- **CI/CD Pipeline** (`.github/workflows/ci.yml`) - Milestone 1.4
  - Automated testing on Elixir 1.19 / OTP 27
  - Test, Quality, and Documentation jobs
  - Dependency and PLT caching for faster builds
  - Triggered on push/PR to main/develop branches

- **Comprehensive Test Suite**
  - `test/metastatic/ast_test.exs` - 332 lines (37 tests)
  - `test/metastatic/document_test.exs` - 94 lines (9 tests)
  - `test/metastatic/validator_test.exs` - 274 lines (53 tests)
  - `test/metastatic/adapter/registry_test.exs` - 242 lines (23 tests)
  - `test/metastatic/builder_test.exs` - 356 lines (32 tests)
  - `test/support/adapter_helper_test.exs` - 296 lines (21 tests)
  - **Total: 175 tests (21 doctests + 154 tests), 100% passing**

- **Documentation**
  - `RESEARCH.md` - Comprehensive architecture analysis (826 lines)
  - `THEORETICAL_FOUNDATIONS.md` - Formal meta-modeling theory with 22 definitions and 12 theorems (953 lines)
  - `IMPLEMENTATION_PLAN.md` - 14-month roadmap with meta-modeling perspective (1138 lines)
  - `GETTING_STARTED.md` - Developer onboarding guide (397 lines)
  - `README.md` - Project overview with Phase 1 status
  - Full API documentation via ExDoc

- **Dependencies**
  - `jason ~> 1.4` - JSON serialization
  - `ex_doc ~> 0.34` - Documentation generation

### Implementation Details

#### Type System
- Main type: `@type meta_ast` (renamed from `node` to avoid built-in conflict)
- Binary operations use category atoms: `:arithmetic`, `:comparison`, `:boolean`
- Unary operations categorized as `:arithmetic` or `:boolean`
- Function calls use string names (not node references)
- Loop types: `:while` (3-tuple), `:for`/`:for_each` (5-tuple with item and collection)
- Collection operations: `:map`/`:filter` (4-tuple), `:reduce` (5-tuple with initial value)
- Lambda parameters and captures as string lists

#### Validation
- Three-mode validation: strict (no native constructs), standard (native allowed with warnings), permissive (all accepted)
- Depth calculation for nesting detection
- Node counting for complexity metrics
- Variable extraction returns `MapSet` of variable names
- Warnings for: native constructs, deep nesting (>100), large ASTs (>1000 nodes)

#### Quality Metrics Achieved
- Test coverage: 100% of public APIs
- Test count: 175 tests (21 doctests + 154 tests)
- Documentation: 100% of public functions with @doc
- Code organization: 2,660 lines across 8 core modules
- Type safety: Full @spec coverage on public functions
- Infrastructure: Benchmarks, CI/CD, fixture framework

### Meta-Modeling Foundation
This release establishes the M2 (meta-model) layer in the MOF hierarchy:
- M3: Elixir type system (`@type`, `@spec`)
- **M2: MetaAST** (this release) - defines what AST nodes CAN be
- M1: Language-specific ASTs (Python, JavaScript, etc.) - coming in Phase 2
- M0: Runtime execution

## Development Timeline

- **2026-01-20**: Phase 1 Complete (All 4 Milestones)
  - Milestone 1.1: Core MetaAST types, Document, Validator
  - Milestone 1.2: Adapter Registry, Round-trip testing framework
  - Milestone 1.3: Builder with 32 tests, Registry integration
  - Milestone 1.4: Fixture framework, Benchmarks, CI/CD pipeline
  - 175 tests passing (100% coverage)
  - Complete documentation (3,648 lines)
  - Production-ready infrastructure

## Future Releases

### [0.2.0] - Planned (Phase 2)
- Python adapter implementation
- Python AST parser integration
- M1 ↔ M2 transformations for Python
- 50+ Python test fixtures
- Round-trip accuracy >95%

### [0.3.0] - Planned (Phase 3)
- JavaScript adapter
- Elixir adapter
- Mutation engine (arithmetic, comparison, boolean)
- Purity analyzer

### [0.4.0] - Planned (Phase 4)
- CLI tool
- Oeditus integration
- Performance optimization

### [1.0.0] - Planned (Phase 5)
- Production-ready release
- 6+ languages supported
- Community contributions
- Open source release

## Notes

This project follows a rigorous theoretical foundation based on:
- OMG Meta Object Facility (MOF) Specification
- Eclipse Modeling Framework (EMF)
- Formal meta-modeling theory

See `THEORETICAL_FOUNDATIONS.md` for the complete formal treatment with proofs.
