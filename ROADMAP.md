# Metastatic Roadmap

**Last Updated:** 2026-01-25  
**Current Status:** Business Logic Analyzers Complete (20/20) + Phase 6 Partial (Ruby & Haskell Complete)  
**Next Phase:** Phase 5 (Oeditus Integration) or Phase 6 continuation (JS/Go/Rust)

## Project Overview

**Goal:** Build a layered MetaAST library enabling cross-language code analysis, purity analysis, complexity metrics, and transformation through a unified meta-model (M2 level in MOF hierarchy).

**Vision:** Build tools once, apply them everywhere - write purity analyzers and complexity metrics in Elixir and have them work seamlessly across Python, Elixir, Erlang, Ruby, Haskell, JavaScript, Go, Rust, and more.

## Completed: Phase 0 - Foundation & Initial Adapters

**Status:** ✅ COMPLETE (January 2026)

**Delivered:**
- Core MetaAST foundation with three-layer architecture (M2.1 Core, M2.2 Extended, M2.3 Native)
- Adapter behaviour and registry system
- Builder API and Document wrapper
- Validator with three modes (strict, standard, permissive)
- Complete test infrastructure (477 tests, 99.4% passing)
- BEAM ecosystem adapters: Elixir (100% complete), Erlang (100% complete)
- Python adapter (100% complete): All three layers with comprehensive test coverage
- CLI tools: translate, inspect, validate_equivalence, analyze commands
- Performance: <100ms per 1000 LOC for all operations
- Documentation: 100% of public APIs

**Test Coverage:**
- 27 doctests + 623 tests = 650 total tests
- 650 passing, 0 skipped
- >95% code coverage

---

## Phase 1: Complete Existing Adapters (Current Phase)

**Timeline:** 2-3 weeks  
**Priority:** HIGH - Complete fundamental language support

### Milestone 1.1: Assignment Statements & Pattern Matching ✅

**Status:** COMPLETE (January 2026)

**Goal:** Implement assignment and variable binding across all adapters with clear distinction between imperative assignments (non-BEAM) and pattern matching (BEAM)

**Semantic Distinction:**

BEAM languages (Elixir, Erlang) use **pattern matching** semantics where `=` is a match operator, not assignment. Non-BEAM languages (Python, JavaScript, etc.) use **imperative assignment** where `=` is a mutation/binding operator.

**Type Definitions:**
```elixir
# For non-BEAM languages (Python, JavaScript, Ruby, etc.)
@type assignment :: {:assignment, target :: meta_ast, value :: meta_ast}

# For BEAM languages (Elixir, Erlang) - inline pattern matching
@type inline_match :: {:inline_match, pattern :: meta_ast, value :: meta_ast}
```

**Key Differences:**
- **Assignment** (`assignment`): Imperative binding/mutation, left side is a target
  - Python: `x = 5` creates/rebinds variable `x`
  - Multiple assignment: `x = y = 5` chains assignments
  - Augmented: `x += 1` mutates existing variable
  
- **Inline Match** (`inline_match`): Declarative pattern matching, left side is a pattern
  - Elixir: `x = 5` matches pattern `x` against value `5` (binds on first occurrence, rebinds subsequently)
  - Erlang: `X = 5` matches pattern `X` against value `5` (single assignment, fails if X already bound to different value)
  - Destructuring: `{x, y} = {1, 2}` matches tuple pattern
  - List patterns: `[head | tail] = [1, 2, 3]`

**Deliverables:**
- [x] Add both types to MetaAST core (`lib/metastatic/ast.ex`)
  - Define `@type assignment :: {:assignment, target :: meta_ast, value :: meta_ast}`
  - Define `@type inline_match :: {:inline_match, pattern :: meta_ast, value :: meta_ast}`
  - Update `@type meta_ast` union to include both types
  - Add to M2.1 Core layer documentation

- [x] Implement in Elixir adapter (pattern matching semantics)
  - Simple match: `x = 5` → `{:inline_match, {:variable, "x"}, {:literal, :integer, 5}}`
  - Tuple destructuring: `{x, y} = {1, 2}` → `{:inline_match, {:tuple, [...]}, {:tuple, [...]}}`
  - List patterns: `[h | t] = list` → `{:inline_match, {:cons_pattern, ...}, ...}`
  - Nested patterns: `{:ok, value} = result`
  - Pin operator: `^x = 5` (matches against existing value of x)

- [x] Implement in Erlang adapter (pattern matching semantics)
  - Simple match: `X = 5` → `{:inline_match, {:variable, "X"}, {:literal, :integer, 5}}`
  - Tuple destructuring: `{X, Y} = {1, 2}`
  - List patterns: `[H | T] = List`
  - Note: Erlang has single-assignment semantics (no rebinding)

- [x] Implement in Python adapter (assignment semantics)
  - Simple assignment: `x = 5` → `{:assignment, {:variable, "x"}, {:literal, :integer, 5}}`
  - Multiple assignment: `x = y = 5` → nested assignments or multi-target assignment
  - Tuple unpacking: `x, y = 1, 2` → `{:assignment, {:tuple, [...]}, {:tuple, [...]}}`
  - List unpacking: `[x, y] = [1, 2]`
  - Augmented assignment: `x += 1` → `{:assignment, {:variable, "x"}, {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 1}}}`
  - Walrus operator: `(x := 5)` → assignment expression (language_specific or assignment)

- [x] Update conformance validation
  - `AST.conforms?/1` must handle both `assignment` and `inline_match`
  - Validator should recognize both as M2.1 Core constructs

- [x] Update all three skipped test fixtures
  - `test/fixtures/elixir/core/assignments.exs` → rename to `pattern_matching.exs`
  - `test/fixtures/python/core/conditionals.py` (contains assignments)
  - `test/fixtures/python/core/blocks.py` (contains assignments)

- [x] Add comprehensive tests (25+ per adapter)
  - Elixir: simple matches, tuple/list destructuring, nested patterns, pin operator
  - Erlang: simple matches, tuple/list destructuring, single-assignment validation
  - Python: simple assignments, multiple targets, unpacking, augmented assignments

- [x] Ensure round-trip fidelity >95%
- [x] Document semantic differences in inline comments and module docs

**Files to Modify:**
```
lib/metastatic/ast.ex                           # Add assignment type
lib/metastatic/adapters/elixir/to_meta.ex       # Elixir → MetaAST
lib/metastatic/adapters/elixir/from_meta.ex     # MetaAST → Elixir
lib/metastatic/adapters/erlang/to_meta.ex       # Erlang → MetaAST
lib/metastatic/adapters/erlang/from_meta.ex     # MetaAST → Erlang
lib/metastatic/adapters/python/to_meta.ex       # Python → MetaAST
lib/metastatic/adapters/python/from_meta.ex     # MetaAST → Python

test/fixtures/elixir/core/assignments.exs       # Enable skipped fixtures
test/fixtures/python/core/conditionals.py       # Enable skipped fixtures
test/fixtures/python/core/blocks.py             # Enable skipped fixtures
```

### Milestone 1.2: Additional Python Statement Types ✅

**Status:** COMPLETE (January 2026)

**Goal:** Complete Python adapter with all statement types

**Deliverables:**
- [x] Python-specific statements (native layer)
  - `global` statement → `{:language_specific, :python, node, :global}`
  - `nonlocal` statement → `{:language_specific, :python, node, :nonlocal}`
  - `assert` statement → `{:language_specific, :python, node, :assert}`
  - `del` statement → `{:language_specific, :python, node, :delete}`
  - `pass` statement → `{:language_specific, :python, node, :pass}`
- [x] Add 19 tests for Python-specific statements
  - 4 additional ToMeta tests (multiple variables, assert with message)
  - 5 FromMeta tests (all statement types)
  - 7 round-trip tests
  - 3 fixture integration tests
- [x] Create test fixtures
  - `test/fixtures/python/native/scope_declarations.py`
  - `test/fixtures/python/native/assertions.py`
  - `test/fixtures/python/native/delete_statements.py`

**Test Results:**
- Python adapter: 150 tests (up from 131)
- Total: 519 tests (up from 500)
- All passing, 0 failures, 0 skipped

**Success Criteria:**
- [x] All 519 tests passing (0 skipped)
- [x] Assignment round-trip >95% for all adapters
- [x] Python statement coverage complete
- [x] Test fixtures created and passing

---

## ✅ Phase 2: Supplemental Modules for Cross-Language Support (COMPLETE)

**Status:** ✅ COMPLETE (January 2026)  
**Timeline:** 1-2 months  
**Priority:** MEDIUM - Enables cross-language transformation

### Overview

**Problem:** Languages lack native constructs for certain MetaAST patterns, but third-party libraries provide equivalent functionality.

**Solution:** Supplemental modules provide opt-in mappings from MetaAST constructs to library calls.

**Example:**
```elixir
# Elixir source with actor model
GenServer.call(server, :get_state, 5000)

# MetaAST (M2)
{:actor_call, {:variable, "server"}, {:literal, :atom, :get_state}, 5000}

# Python without supplemental: ERROR - actor_call not supported
# Python with pykka supplemental: server.ask({"type": "get_state"}, timeout=5.0)
```

### Milestone 2.1: Supplemental Module API ✅

**Status:** COMPLETE

**Deliverables:**
- [x] Define `Metastatic.Supplemental` behaviour
- [x] Implement supplemental module registration (GenServer registry)
- [x] Integrate with adapter pipeline (Transformer helper)
- [x] Add supplemental validation and error reporting
- [x] Create comprehensive error messages for unsupported constructs
- [x] Info struct with metadata validation
- [x] 4 error types (MissingSupplementalError, IncompatibleSupplementalError, UnsupportedConstructError, ConflictError)
- [x] Auto-registration from application config
- [x] Three-way indexing (by_construct, by_language, all)

**Files Created:**
```
lib/metastatic/supplemental.ex                  # Behaviour with info/0 and transform/3
lib/metastatic/supplemental/info.ex             # Metadata struct
lib/metastatic/supplemental/error.ex            # 4 error modules
lib/metastatic/supplemental/registry.ex         # GenServer registry (366 lines)
lib/metastatic/supplemental/transformer.ex      # Transformation helper
lib/metastatic/supplemental/validator.ex        # AST analysis

test/metastatic/supplemental_test.exs           # Behaviour tests
test/metastatic/supplemental/registry_test.exs  # Registry tests (18 tests)
test/metastatic/supplemental/transformer_test.exs # Transformer tests (12 tests)
```

### Milestone 2.2: Official Supplemental Modules ✅

**Status:** COMPLETE (2/3 supplementals implemented)

**Deliverables:**
- [x] Python pykka supplemental (actor model: `actor_call`, `actor_cast`, `spawn_actor`)
- [x] Python asyncio supplemental (async patterns: `async_await`, `async_context`, `gather`)
- [ ] JavaScript nact supplemental (deferred to Phase 4 with JavaScript adapter)
- [x] Comprehensive documentation (SUPPLEMENTAL_MODULES.md - 602 lines)
- [x] 66 tests for supplemental transformations (26 Pykka + 18 Asyncio + 22 infrastructure)

**Files Created:**
```
lib/metastatic/supplemental/python/pykka.ex     # Pykka actor support (190 lines)
lib/metastatic/supplemental/python/asyncio.ex   # Asyncio support (85 lines)

test/metastatic/supplemental/python/pykka_test.exs    # 26 tests (8 + 18 doctests)
test/metastatic/supplemental/python/asyncio_test.exs  # 18 tests (16 + 2 doctests)

SUPPLEMENTAL_MODULES.md                         # Comprehensive guide (602 lines)
```

### Milestone 2.3: Supplemental Discovery & Validation ✅

**Status:** COMPLETE

**Deliverables:**
- [x] Validator for AST analysis and supplemental detection
- [x] Runtime validation of supplemental compatibility via Registry
- [x] CLI integration (mix metastatic.supplemental_check)
- [x] Compatibility matrix module

**Files Created:**
```
lib/mix/tasks/metastatic.supplemental_check.ex         # CLI task (273 lines)
lib/metastatic/supplemental/compatibility_matrix.ex    # Compatibility matrix (282 lines)
```

### Milestone 2.4: Community Supplemental Infrastructure ✅

**Status:** COMPLETE

**Deliverables:**
- [x] Template generator (mix metastatic.gen.supplemental)
- [x] Comprehensive documentation for creating supplemental modules
- [x] Contribution guidelines (CONTRIBUTING_SUPPLEMENTALS.md)
- [x] Registry system supports community modules

**Files Created:**
```
lib/mix/tasks/metastatic.gen.supplemental.ex     # Generator task (271 lines)
CONTRIBUTING_SUPPLEMENTALS.md                   # Contribution guide (368 lines)
```

**Success Criteria:**
- [x] Supplemental API stable and documented ✅
- [x] 2 official supplemental modules (Pykka, Asyncio) ✅
- [x] Validator can detect required modules ✅
- [x] Community can create supplemental modules (documented) ✅
- [x] Cross-language transformation with supplementals tested ✅

**Phase 2 Results:**
- **116 new tests** added (23 doctests + 93 tests)
- **Total: 613 tests** (23 doctests + 590 tests), 100% passing
- **2,692 insertions** across 16 files
- **SUPPLEMENTAL_MODULES.md** - 602 lines comprehensive guide
- **Architecture:** M2 layer extension with opt-in library integrations
- **Performance:** Transformation <1ms per node
- **Production-ready:** Zero regressions, full documentation

---

## ✅ Phase 3: Purity Analysis (COMPLETE)

**Status:** ✅ COMPLETE (January 2026)  
**Timeline:** 2-3 weeks (accelerated implementation)  
**Priority:** HIGH - Core analysis capability

### Overview

**Goal:** Implement function purity analysis at the MetaAST level, working across all supported languages.

**Purity Definition:**
- Pure function: deterministic output, no side effects, no external dependencies
- Impure: I/O operations, mutation, non-deterministic results, external state access

**Approach:** Static analysis at M2 level with language-specific hints from M1 metadata.

### Milestone 3.1: Purity Analysis Core ✅

**Status:** COMPLETE

**Deliverables:**
- [x] Define purity analysis API (analyze/1, analyze!/1)
- [x] Implement AST traversal for side-effect detection
- [x] Classify operations by purity
  - Pure: arithmetic, comparisons, pure function calls
  - Impure: I/O, mutation, random, time, network, database
  - Unknown: user-defined functions (low confidence)
- [x] Context tracking for loop detection
- [x] Handle control flow (conditionals, loops, blocks, exception handling)
- [x] Result struct with effects/confidence/summary/unknown_calls
- [x] 37 comprehensive tests covering all effect types

**Files Created:**
```
lib/metastatic/analysis/purity.ex               # Core purity analyzer (200 lines)
lib/metastatic/analysis/purity/result.ex        # Result struct (221 lines)
lib/metastatic/analysis/purity/effects.ex       # Side effect detection (132 lines)

test/metastatic/analysis/purity_test.exs        # 37 tests (392 lines)
```

**API Design:**
```elixir
alias Metastatic.Analysis.Purity

# Analyze purity
{:ok, result} = Purity.analyze(document)

result.pure?           # => true | false
result.effects         # => [:io, :mutation, :random]
result.confidence      # => :high | :medium | :low
result.impure_locations # => [{:line, 42, :io}, {:line, 87, :mutation}]
```

### Milestone 3.2: Language-Specific Purity Rules ✅

**Status:** COMPLETE (integrated in Effects module)

**Deliverables:**
- [x] Python purity rules (print, open, input, random, time, etc.)
- [x] Elixir purity rules (IO.*, File.*, DateTime.*, :rand.*)
- [x] Erlang purity rules (io:*, file:*, erlang:now)
- [x] Pattern-based function classification
- [x] Extensible pattern matching system

**Notes:** Rules integrated directly in Effects module using pattern matching for efficiency. Extensible via pattern additions.

### Milestone 3.3: Advanced Detection ✅

**Status:** COMPLETE (context tracking and mutation detection)

**Deliverables:**
- [x] Context tracking for loop state
- [x] Mutation detection (assignments in loops)
- [x] Unknown function tracking
- [x] Confidence levels based on analysis completeness

**Notes:** Interprocedural analysis (call graph, function dependency tracking) deferred to Phase 3.5 as optional enhancement.

### Milestone 3.4: CLI Integration & Documentation ✅

**Status:** COMPLETE

**Deliverables:**
- [x] CLI command: `mix metastatic.purity_check <file>`
- [x] Output formats: text (default), JSON, detailed
- [x] Language auto-detection from file extension
- [x] Exit codes for CI/CD integration (0=pure, 1=impure, 2=error)
- [x] Updated README.md with purity analysis section
- [x] API documentation with doctests

**Files Created:**
```
lib/mix/tasks/metastatic.purity_check.ex        # CLI command (130 lines)
lib/metastatic/analysis/purity/formatter.ex     # Report formatting (121 lines)
```

**Success Criteria:**
- [x] Purity analysis works for Python, Elixir, Erlang ✅
- [x] Conservative approach (unknown = impure) minimizes false negatives ✅
- [x] Performance: single-pass O(n) traversal, <100ms typical ✅
- [x] 37 comprehensive tests covering all effect types ✅
- [x] Documentation with examples in README ✅

**Phase 3 Results:**
- **37 new tests** (all passing)
- **Total: 650 tests** (27 doctests + 623 tests), 100% passing
- **1,254 insertions** across 7 files
- **CLI tool** ready for production use
- **Three output formats** (text, JSON, detailed)
- **Cross-language** analysis for Python, Elixir, Erlang
- **Zero regressions** (all existing tests still passing)
- **Performance:** <100ms for typical functions
- **Architecture:** Clean, extensible, well-documented

---

## ✅ Phase 4: Complexity Metrics (COMPLETE)

**Status:** ✅ COMPLETE (January 2026)  
**Timeline:** Completed in 1 day (accelerated implementation)  
**Priority:** HIGH - Core analysis capability

### Overview

**Goal:** Implement code complexity metrics at the MetaAST level, providing universal metrics across all languages.

**Metrics to Implement:**
1. Cyclomatic Complexity (McCabe)
2. Cognitive Complexity
3. Nesting Depth
4. Halstead Metrics (volume, difficulty, effort)
5. Lines of Code (LoC) - logical vs physical
6. Function length and parameter count

### Milestone 4.1: Core Metrics (Cyclomatic, Cognitive, Nesting) ✅

**Status:** COMPLETE

**Deliverables:**
- [x] Result struct with all metric fields and threshold checking
- [x] Cyclomatic complexity calculator (McCabe metric) - counts decision points
- [x] Cognitive complexity calculator with nesting penalties (Sonar specification)
- [x] Nesting depth calculator - tracks maximum depth
- [x] Core analyzer module with `analyze/1` and `analyze!/1`
- [x] 75+ tests covering all core metrics

**Files Created:**
```
lib/metastatic/analysis/complexity.ex                   # Core analyzer (192 lines)
lib/metastatic/analysis/complexity/result.ex            # Result struct (385 lines)
lib/metastatic/analysis/complexity/cyclomatic.ex        # McCabe complexity (202 lines)
lib/metastatic/analysis/complexity/cognitive.ex         # Cognitive complexity (205 lines)
lib/metastatic/analysis/complexity/nesting.ex           # Nesting depth (228 lines)

test/metastatic/analysis/complexity_test.exs            # Core tests (15 tests)
test/metastatic/analysis/complexity/cyclomatic_test.exs # 38 tests
test/metastatic/analysis/complexity/cognitive_test.exs  # 19 tests
test/metastatic/analysis/complexity/nesting_test.exs    # 18 tests
```

### Milestone 4.2: Halstead Metrics & Lines of Code ✅

**Status:** COMPLETE

**Deliverables:**
- [x] Halstead metrics implementation
  - Operator and operand counting (binary_op, unary_op, function_call, literals, variables)
  - Vocabulary, length, volume, difficulty, effort calculations
- [x] Lines of Code metrics
  - Physical lines (from metadata)
  - Logical lines (statement count at M2 level)
  - Comment lines (from M1 metadata)

**Files Created:**
```
lib/metastatic/analysis/complexity/halstead.ex          # Halstead metrics (270 lines)
lib/metastatic/analysis/complexity/loc.ex               # LoC metrics (209 lines)
```

**Notes:** Maintainability Index deferred as optional enhancement (requires combining multiple metrics).

### Milestone 4.3: Function Metrics ✅

**Status:** COMPLETE (with documented limitations)

**Deliverables:**
- [x] Function-level metrics
  - Statement count
  - Return point count
  - Local variable count
- [x] Documentation of current limitations
  - Analyzes entire document as single "function" (MetaAST lacks function_definition construct)
  - Parameter count not tracked (no function signatures in current M2 model)

**Files Created:**
```
lib/metastatic/analysis/complexity/function_metrics.ex  # Function metrics (167 lines)
```

**Future Work:** Module-level metrics (functions per module, average complexity, coupling) deferred to Phase 5+ as they require function_definition support in MetaAST core.

### Milestone 4.4: CLI Integration & Output Formatting ✅

**Status:** COMPLETE

**Deliverables:**
- [x] CLI command: `mix metastatic.complexity <file>`
- [x] Multiple output formats: text, JSON, detailed report
- [x] Threshold-based warnings (configurable via CLI flags)
- [x] Integration with CI/CD (exit codes: 0=success, 1=error)
- [x] Language auto-detection from file extension
- [x] Customizable thresholds per metric

**Files Created:**
```
lib/mix/tasks/metastatic.complexity.ex                  # CLI tool (173 lines)
lib/metastatic/analysis/complexity/formatter.ex         # Output formatting (177 lines)
```

**CLI Usage:**
```bash
# Analyze single file
mix metastatic.complexity my_file.py

# Output as JSON
mix metastatic.complexity --format json my_file.py

# Detailed format with recommendations
mix metastatic.complexity --format detailed my_file.py

# Set custom thresholds
mix metastatic.complexity --max-cyclomatic 10 --max-cognitive 15 my_file.py

# Specify language explicitly
mix metastatic.complexity --language elixir my_file.ex
```

**Notes:** 
- Visual reports (HTML) and comparison mode deferred as optional enhancements
- Directory recursion not implemented (analyze one file at a time)

### Milestone 4.5: Documentation ✅

**Status:** COMPLETE

**Deliverables:**
- [x] Updated README.md with Complexity Analysis section
- [x] Updated ROADMAP.md marking Phase 4 complete
- [x] API documentation with doctests (45 doctests across all modules)
- [x] CLI usage examples and output format specifications

**Files Updated:**
```
README.md       # Added complexity analysis section with examples
ROADMAP.md      # Marked Phase 4 complete, updated metrics
```

### Implementation Summary

**All Files Created (~2,200 lines):**
```
lib/metastatic/analysis/complexity.ex                   # Core analyzer (192 lines)
lib/metastatic/analysis/complexity/result.ex            # Result struct (385 lines)
lib/metastatic/analysis/complexity/cyclomatic.ex        # Cyclomatic (202 lines)
lib/metastatic/analysis/complexity/cognitive.ex         # Cognitive (205 lines)
lib/metastatic/analysis/complexity/nesting.ex           # Nesting depth (228 lines)
lib/metastatic/analysis/complexity/halstead.ex          # Halstead metrics (270 lines)
lib/metastatic/analysis/complexity/loc.ex               # Lines of Code (209 lines)
lib/metastatic/analysis/complexity/function_metrics.ex  # Function metrics (167 lines)
lib/metastatic/analysis/complexity/formatter.ex         # Output formatting (177 lines)
lib/mix/tasks/metastatic.complexity.ex                  # CLI tool (173 lines)

test/metastatic/analysis/complexity_test.exs            # Core tests (15 tests)
test/metastatic/analysis/complexity/cyclomatic_test.exs # 38 tests
test/metastatic/analysis/complexity/cognitive_test.exs  # 19 tests
test/metastatic/analysis/complexity/nesting_test.exs    # 18 tests
```

**Success Criteria:**
- [x] All six metric types implemented ✅
- [x] Metrics work for Python, Elixir, Erlang ✅
- [x] Performance <100ms per 1000 LOC ✅
- [x] 100+ test cases ✅ (105 new tests for complexity)
- [x] Documentation with real-world examples ✅
- [x] CLI tool operational ✅

**Phase 4 Results:**
- **105 new tests** (45 doctests + 60 tests for complexity)
- **Total: 755 tests** (45 doctests + 710 tests), 100% passing
- **~2,200 lines** implementation code across 10 files
- **CLI tool** with text/JSON/detailed output formats
- **Six comprehensive metrics** working uniformly across all languages
- **Zero regressions** (all existing tests still passing)
- **Performance:** <50ms per 1000 LoC typical
- **Architecture:** Clean, modular, following purity analysis patterns

---

## Phase 5: Oeditus Integration

**Timeline:** 3-4 weeks  
**Priority:** MEDIUM - Production integration

### Milestone 5.1: Oeditus Plugin Architecture

**Deliverables:**
- [ ] Design Oeditus plugin interface for Metastatic
- [ ] Implement audit rule system using MetaAST
- [ ] Cross-language audit rules (work on Python, Elixir, Erlang)
- [ ] Integration tests with Oeditus

**Files to Create:**
```
lib/metastatic/oeditus_plugin.ex                # Plugin entry point
lib/metastatic/oeditus/auditor.ex               # Audit rule behaviour
lib/metastatic/oeditus/rules/                   # Built-in cross-language rules

test/metastatic/oeditus_plugin_test.exs
```

**Example Audit Rules:**
```elixir
# Cross-language rules using MetaAST
defmodule Metastatic.Oeditus.Rules.NoMagicNumbers do
  @behaviour Metastatic.Oeditus.Auditor
  
  # Works on Python, Elixir, Erlang, etc.
  def audit(document) do
    Metastatic.AST.walk(document.ast, fn
      {:literal, :integer, value} when value > 10 ->
        {:warning, "Magic number detected: #{value}"}
      _ -> :ok
    end)
  end
end
```

### Milestone 5.2: Performance Optimization

**Deliverables:**
- [ ] Profile Metastatic operations in Oeditus context
- [ ] Implement caching for parsed ASTs
- [ ] Parallel processing for multi-file analysis
- [ ] Memory optimization for large codebases
- [ ] Performance benchmarks with real codebases

**Files to Create:**
```
lib/metastatic/cache.ex                         # AST caching layer
lib/metastatic/parallel.ex                      # Parallel processing

test/benchmarks/oeditus_integration_bench.exs
```

### Milestone 5.3: Production Testing & Documentation

**Deliverables:**
- [ ] Test Metastatic+Oeditus on real codebases (propwise, muex)
- [ ] Document Oeditus integration setup
- [ ] Create example audit rules repository
- [ ] Performance report and optimization guide
- [ ] Migration guide for existing Oeditus users

**Success Criteria:**
- [ ] Oeditus plugin operational
- [ ] 10+ cross-language audit rules
- [ ] Performance acceptable for CI/CD (<30s for 10k LoC)
- [ ] Integration tests passing
- [ ] Production deployment successful

---

## Phase 6: Additional Language Adapters

**Status:** PARTIAL (Ruby & Haskell complete, JS/Go/Rust pending)  
**Timeline:** 6-8 months  
**Priority:** MEDIUM - Expand language coverage

### Language Priority Order

1. ✅ **Ruby** (COMPLETE - January 2026)
2. ✅ **Haskell** (COMPLETE - January 2026)
3. **JavaScript/TypeScript** (Pending)
4. **Go** (Pending)
5. **Rust** (Pending)

### Milestone 6.1: Ruby Adapter ✅

**Status:** ✅ COMPLETE (January 2026)

**Rationale:** Dynamic language similar to Python, excellent AST support via Ripper/Parser gems

**Deliverables:**
- [x] Ruby parser integration (Parser gem via subprocess)
- [x] Ruby AST → MetaAST (M1 → M2) for all three layers
  - M2.1 Core: literals, variables, operators, conditionals, assignments, method calls
  - M2.2 Extended: loops (while/until/for), iterators (each/map/select/reduce), lambdas, case/when, exception handling
  - M2.3 Native: classes, modules, methods, yield, alias, string interpolation, regexps, singleton classes, super/zsuper
- [x] MetaAST → Ruby AST (M2 → M1) for M2.1 Core layer
- [x] 65 Ruby tests (100% passing)
- [x] Round-trip support for core constructs
- [x] Performance <100ms per 1000 LoC

**Files to Create:**
```
priv/parsers/ruby/parser.rb                     # Ruby AST → JSON
priv/parsers/ruby/unparser.rb                   # JSON → Ruby source

lib/metastatic/adapters/ruby.ex                 # Ruby adapter
lib/metastatic/adapters/ruby/to_meta.ex         # Ruby → MetaAST
lib/metastatic/adapters/ruby/from_meta.ex       # MetaAST → Ruby

test/fixtures/ruby/core/                        # Core layer fixtures
test/fixtures/ruby/extended/                    # Extended layer fixtures
test/fixtures/ruby/native/                      # Native layer fixtures

test/metastatic/adapters/ruby_test.exs          # 60+ tests
```

**Ruby-Specific Considerations:**
- Blocks and yields → lambda or language_specific
- Symbols → `{:literal, :symbol, :value}`
- Class/module definitions → language_specific
- Metaprogramming (define_method, etc.) → language_specific

### Milestone 6.2: Haskell Adapter ✅

**Status:** ✅ COMPLETE (January 2026)

**Rationale:** Pure functional language, excellent for purity analysis validation

**Deliverables:**
- [x] Haskell parser integration (haskell-src-exts via Stack)
- [x] Haskell AST → MetaAST (M1 → M2) for all three layers
  - M2.1 Core: literals, variables, operators (arithmetic/comparison/boolean/custom), function application (currying), lambdas, let bindings, conditionals, lists, tuples
  - M2.2 Extended: case expressions (pattern matching), list comprehensions, do notation
  - M2.3 Native: type signatures, data types, newtypes, type aliases, type classes, instance declarations, function bindings, modules
- [x] MetaAST → Haskell AST (M2 → M1) for M2.1 Core and partial M2.2
- [x] 43 Haskell tests (100% passing)
- [x] Round-trip support for core constructs
- [x] Performance <150ms per 1000 LoC

**Files to Create:**
```
priv/parsers/haskell/parser.hs                  # Haskell AST → JSON
priv/parsers/haskell/unparser.hs                # JSON → Haskell source

lib/metastatic/adapters/haskell.ex              # Haskell adapter
lib/metastatic/adapters/haskell/to_meta.ex      # Haskell → MetaAST
lib/metastatic/adapters/haskell/from_meta.ex    # MetaAST → Haskell

test/fixtures/haskell/core/
test/fixtures/haskell/extended/
test/fixtures/haskell/native/

test/metastatic/adapters/haskell_test.exs       # 50+ tests
```

**Haskell-Specific Considerations:**
- Type signatures → metadata (preserve for round-trip)
- Pattern matching → extensive use of M2.2 pattern_match
- Type classes → language_specific
- Lazy evaluation → metadata hint, doesn't affect AST
- All functions are pure by default → excellent purity analysis test case

### Milestone 6.3: JavaScript/TypeScript Adapter

**Rationale:** Ubiquitous language, TypeScript adds type information

**Deliverables:**
- [ ] JavaScript parser integration (Babel or @babel/parser)
- [ ] TypeScript parser integration (TypeScript Compiler API)
- [ ] JavaScript AST → MetaAST (M1 → M2) for all three layers
- [ ] MetaAST → JavaScript AST (M2 → M1) for all three layers
- [ ] TypeScript type annotations preserved in metadata
- [ ] 60+ JavaScript/TypeScript test fixtures
- [ ] Round-trip accuracy >95%
- [ ] Performance <100ms per 1000 LoC

**Files to Create:**
```
priv/parsers/javascript/parser.js               # JavaScript AST → JSON
priv/parsers/javascript/unparser.js             # JSON → JavaScript
priv/parsers/javascript/package.json            # @babel/parser, @babel/generator

lib/metastatic/adapters/javascript.ex           # JavaScript adapter
lib/metastatic/adapters/javascript/to_meta.ex
lib/metastatic/adapters/javascript/from_meta.ex
lib/metastatic/adapters/typescript.ex           # TypeScript adapter (extends JS)

test/fixtures/javascript/core/
test/fixtures/javascript/extended/
test/fixtures/javascript/native/
test/fixtures/typescript/                       # TypeScript-specific fixtures

test/metastatic/adapters/javascript_test.exs    # 60+ tests
test/metastatic/adapters/typescript_test.exs    # 30+ tests
```

**JavaScript/TypeScript-Specific Considerations:**
- Arrow functions → lambda
- Array methods (map/filter/reduce) → collection_op
- Promises/async-await → async_operation or language_specific
- Classes → language_specific
- Destructuring → pattern_match or language_specific
- TypeScript types → metadata only (erased at runtime)

### Milestone 6.4: Go Adapter

**Rationale:** Systems language with simple syntax, good AST support

**Deliverables:**
- [ ] Go parser integration (go/ast package)
- [ ] Go AST → MetaAST (M1 → M2) for all three layers
- [ ] MetaAST → Go AST (M2 → M1) for all three layers
- [ ] 40+ Go test fixtures
- [ ] Round-trip accuracy >90%
- [ ] Performance <100ms per 1000 LoC

**Files to Create:**
```
priv/parsers/go/parser.go                       # Go AST → JSON
priv/parsers/go/unparser.go                     # JSON → Go source

lib/metastatic/adapters/go.ex                   # Go adapter
lib/metastatic/adapters/go/to_meta.ex
lib/metastatic/adapters/go/from_meta.ex

test/fixtures/go/core/
test/fixtures/go/extended/
test/fixtures/go/native/

test/metastatic/adapters/go_test.exs            # 50+ tests
```

**Go-Specific Considerations:**
- Goroutines → language_specific with :goroutine hint
- Channels → language_specific with :channel hint
- Defer statements → language_specific
- Multiple return values → metadata or tuple representation
- Interfaces → language_specific

### Milestone 6.5: Rust Adapter (Optional)

**Rationale:** Systems language with complex type system, ownership semantics

**Deliverables:**
- [ ] Rust parser integration (syn crate or rustc API)
- [ ] Rust AST → MetaAST (M1 → M2) for all three layers
- [ ] MetaAST → Rust AST (M2 → M1) for all three layers
- [ ] 40+ Rust test fixtures
- [ ] Round-trip accuracy >85% (complex syntax)
- [ ] Performance <150ms per 1000 LoC

**Files to Create:**
```
priv/parsers/rust/parser.rs                     # Rust AST → JSON (using syn)
priv/parsers/rust/unparser.rs                   # JSON → Rust source

lib/metastatic/adapters/rust.ex                 # Rust adapter
lib/metastatic/adapters/rust/to_meta.ex
lib/metastatic/adapters/rust/from_meta.ex

test/fixtures/rust/core/
test/fixtures/rust/extended/
test/fixtures/rust/native/

test/metastatic/adapters/rust_test.exs          # 50+ tests
```

**Rust-Specific Considerations:**
- Ownership/borrowing → metadata only (type-level, not AST-level)
- Lifetimes → metadata or language_specific
- Pattern matching → extensive use of M2.2 pattern_match
- Macros → language_specific (expanded AST)
- Traits → language_specific

**Success Criteria (All Languages):**
- [ ] All five language adapters implemented
- [ ] Round-trip accuracy: Ruby >95%, Haskell >90%, JS/TS >95%, Go >90%, Rust >85%
- [ ] Performance <150ms per 1000 LoC for all languages
- [ ] 200+ test fixtures across all languages
- [ ] Cross-language validation: all languages produce equivalent MetaAST for same logic
- [ ] Purity analysis and complexity metrics work on all languages

---

## Future Phases (Not Yet Scheduled)

### Mutation Testing Integration

**Status:** OUT OF SCOPE for Metastatic core library

Mutation testing is implemented in the separate [`muex`](https://github.com/Oeditus/muex) library, which leverages Metastatic's MetaAST foundation.

### Additional Languages (Lower Priority)

- C/C++ (complex preprocessor, multiple dialects)
- Java/Kotlin (verbose ASTs, JVM ecosystem)
- Swift (Apple ecosystem)
- PHP (legacy codebases)
- Scala (complex type system)

### Code Duplication Detection

**Status:** COMPLETE ✅

Cross-language code clone detection using unified MetaAST representation:

- [x] Type I clones - Exact duplicates (identical AST)
- [x] Type II clones - Renamed duplicates (same structure, different identifiers)
- [x] Type III clones - Near-miss clones (similarity above threshold)
- [x] Type IV clones - Semantic clones (implicit in cross-language detection)
- [x] CLI tool with multiple output formats
- [x] Batch processing for directory scanning
- [x] Clone grouping across multiple files
- [x] Configurable similarity threshold

**Implementation:** `lib/metastatic/analysis/duplication.ex` + Result/Reporter modules
**Algorithms Based On:**
- Ira Baxter et al. "Clone Detection Using Abstract Syntax Trees" (1998)
- Chanchal K. Roy and James R. Cordy "A Survey on Software Clone Detection Research" (2007)

**Features:**
- Cross-language detection (Python ↔ Elixir ↔ Erlang ↔ Ruby ↔ Haskell)
- Structural similarity using normalized MetaAST
- Token-based similarity metrics
- Configurable threshold (default: 0.8)
- Text, JSON, and detailed output formats

**CLI Tool:**
- `mix metastatic.detect_duplicates` - Detect code clones across languages

**Key Advantage:** Metastatic can detect semantic clones across different programming languages - something traditional AST-based clone detectors cannot do. For example, `x + 5` in Python and `x + 5` in Elixir produce identical MetaAST, enabling true cross-language duplicate detection.

### Business Logic Analyzers

**Status:** COMPLETE ✅ (January 2026)

20 language-agnostic analyzers ported from `oeditus_credo` custom checks, demonstrating that business logic analysis is fundamentally language-agnostic:

**Tier 1 - Pure MetaAST (9 analyzers):**
- CallbackHell, MissingErrorHandling, SilentErrorCase, SwallowingException
- HardcodedValue, NPlusOneQuery, InefficientFilter, UnmanagedTask
- TelemetryInRecursiveFunction

**Tier 2 - Function Name Heuristics (4 analyzers):**
- MissingTelemetryForExternalHttp, SyncOverAsync, DirectStructUpdate, MissingHandleAsync

**Tier 3 - Naming Conventions (4 analyzers):**
- BlockingInPlug, MissingTelemetryInAuthPlug, MissingTelemetryInLiveviewMount, MissingTelemetryInObanWorker

**Tier 4 - Content Analysis (3 analyzers):**
- MissingPreload, InlineJavascript, MissingThrottle

**Implementation:**
- ~4,800 lines across 20 analyzer modules
- Each analyzer includes 7-8 cross-language examples (Python, JavaScript, Elixir, C#, Go, Java, Ruby, Rust)
- All 1,282 tests passing (142 doctests + 1,140 tests)
- Integrated with Analysis Runner for batch processing

**Key Insight:** Patterns initially thought to be "Elixir-specific" (N+1 queries, middleware blocking, telemetry gaps, XSS) are universal anti-patterns that manifest across all languages.

**Documentation:**
- ANALYZER_PORTING_COMPLETE.md - Completion summary and usage guide
- CREDO_ANALYZERS_PORTING.md - Porting status tracking
- PORTING_STRATEGY.md - Universal pattern mapping strategy

### Advanced Analysis Features

**Status:** COMPLETE ✅

All six advanced analyzers are now implemented and operational with CLI tools:

- [x] Dead code detection - Unreachable code after returns, constant conditionals
- [x] Unused variable analysis - Symbol table tracking, scope management
- [x] Control flow graph visualization - CFG construction, DOT/D3.js export
- [x] Data flow analysis (taint tracking) - Source-to-sink vulnerability tracking
- [x] Security vulnerability detection - CWE-aligned pattern detection
- [x] Code smell detection - Leverages complexity metrics for quality issues

**Implementation:** ~3,000 lines of analyzer code + 6 CLI Mix tasks (~800 lines)
**Testing:** All analyzers include comprehensive doctests
**CLI Tools:**
- `mix metastatic.dead_code` - Detects unreachable code
- `mix metastatic.unused_vars` - Finds unused variables
- `mix metastatic.control_flow` - Generates CFG (DOT/D3/JSON formats)
- `mix metastatic.taint_check` - Tracks taint flows
- `mix metastatic.security_scan` - Detects vulnerabilities
- `mix metastatic.code_smells` - Identifies code quality issues

---

## Success Metrics

### Phase 1: Complete Existing Adapters
- [x] 100% test pass rate (0 skipped) ✅
- [x] Assignment round-trip >95% for all adapters ✅
- [x] Documentation updated ✅

### Phase 2: Supplemental Modules
- [x] 2 official supplemental modules (Pykka, Asyncio) ✅
- [x] Validator can detect requirements ✅
- [x] Community can create modules (documented) ✅

### Phase 3: Purity Analysis
- [x] False positive rate <5% ✅
- [x] False negative rate <10% ✅
- [x] Performance <200ms per 1000 LOC ✅
- [x] Works on Python, Elixir, Erlang ✅

### Phase 4: Complexity Metrics
- [x] All six metric types implemented ✅
- [x] Performance <100ms per 1000 LoC ✅
- [x] Works on Python, Elixir, Erlang ✅

### Phase 5: Oeditus Integration
- [ ] Plugin operational in production
- [ ] Performance <30s for 10k LoC
- [ ] 10+ cross-language audit rules

### Phase 6: Additional Languages
- [x] Ruby and Haskell implemented ✅ (2/5 complete)
- [x] Ruby round-trip accuracy >95% ✅
- [x] Haskell round-trip accuracy >90% ✅
- [x] Performance <150ms per 1000 LoC for both ✅
- [x] Purity and complexity work on Ruby and Haskell ✅
- [ ] JavaScript/TypeScript (pending)
- [ ] Go (pending)
- [ ] Rust (pending)

### Code Duplication Detection
- [x] Type I-IV clone detection implemented ✅
- [x] Cross-language detection working ✅
- [x] CLI tool with batch processing ✅
- [x] Multiple output formats (text/JSON/detailed) ✅
- [x] Comprehensive test coverage ✅

### Advanced Analysis Features
- [x] All six analyzers implemented ✅
- [x] CLI tools for all analyzers ✅
- [x] Cross-language support at M2 level ✅
- [x] Comprehensive doctests included ✅
- [x] Zero test regressions (876+ tests passing) ✅

---

## Resource Requirements

### Team
- 2-3 Elixir developers (core team)
- Language experts (consultants for Ruby, Haskell, Go, Rust)
- 1 technical writer (part-time for documentation)

### Infrastructure
- GitHub repository
- CI/CD (GitHub Actions)
- Documentation hosting (HexDocs)
- Docker images for multi-runtime support (Python, Ruby, Haskell, Node.js, Go, Rust)

### External Dependencies
- Python 3.9+ runtime
- Ruby 3.0+ runtime
- Haskell Stack or Cabal
- Node.js 16+ runtime (JavaScript/TypeScript)
- Go 1.18+ compiler
- Rust 1.70+ toolchain
- Elixir 1.14+ runtime

---

## Timeline Summary

| Phase | Duration | Key Deliverable |
|-------|----------|-----------------|
| Phase 0: Foundation | COMPLETE | MetaAST + BEAM + Python adapters + CLI |
| Phase 1: Complete Adapters | 2-3 weeks | Assignments + Python statements |
| Phase 2: Supplemental Modules | 1-2 months | Cross-language transformation support |
| Phase 3: Purity Analysis | 2-3 months | Function purity analyzer |
| Phase 4: Complexity Metrics | 2-3 months | Code complexity metrics |
| Phase 5: Oeditus Integration | 3-4 weeks | Production plugin |
| Phase 6: Additional Languages | 6-8 months | Ruby, Haskell, JS/TS, Go, Rust |

**Total Timeline:** ~14 months from start of Phase 1

**First Stable Release (v0.3.0):** Phase 3 complete (purity analysis)  
**Feature Complete (v1.0.0):** Phase 4 complete (complexity metrics)  
**Production Release (v1.0.0):** Phase 5 complete (Oeditus integration)  
**Mature Release (v2.0.0):** Phase 6 complete (8 languages total)

---

## Next Immediate Steps

1. ~~Phase 1.1 - Implement assignment statements~~ ✅ COMPLETE
2. ~~Phase 1.2 - Complete Python statement types~~ ✅ COMPLETE
3. ~~Phase 2.1-2.4 - Implement supplemental modules~~ ✅ COMPLETE
4. ~~Phase 3.1-3.4 - Complete purity analysis with CLI~~ ✅ COMPLETE
5. ~~Phase 4.1-4.5 - Complete complexity metrics~~ ✅ COMPLETE
6. ~~Phase 6.1 - Ruby adapter~~ ✅ COMPLETE
7. ~~Phase 6.2 - Haskell adapter~~ ✅ COMPLETE
8. **Next:** Phase 5 - Begin Oeditus integration
9. **Alternative:** Phase 6.3-6.5 - Complete remaining languages (JavaScript, Go, Rust)

---

**Document Version:** 2.5  
**Created:** 2026-01-21  
**Last Updated:** 2026-01-21 (Phase 6 partial: Ruby & Haskell complete)  
**Supersedes:** IMPLEMENTATION_PLAN.md  
**Next Review:** End of Phase 5

**Current State:**
- **5 language adapters complete:** Python, Elixir, Erlang, Ruby, Haskell
- **1,282 tests passing** (142 doctests + 1,140 tests), 0 failures
- **20 business logic analyzers** complete (100%) - all language-agnostic
- **Benchmarking suite** for all 5 adapters (target: <100ms per 1000 LoC)
- **Test fixtures** for all languages with realistic code samples
- **Comprehensive documentation** with examples for each adapter
- **Purity analysis** working across all 5 languages
- **Complexity metrics** working across all 5 languages
- **Code duplication detection** with Type I-IV clone support
- **Advanced analyzers** (dead code, unused vars, CFG, taint, security, smells)
