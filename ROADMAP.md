# Metastatic Roadmap

**Last Updated:** 2026-01-21  
**Current Status:** Phase 0 Complete (Foundation + BEAM + Python Adapters)  
**Next Phase:** Phase 1 (Complete Existing Adapters)

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
- 21 doctests + 456 tests = 477 total tests
- 474 passing, 3 skipped (assignments not yet implemented)
- >95% code coverage

---

## Phase 1: Complete Existing Adapters (Current Phase)

**Timeline:** 2-3 weeks  
**Priority:** HIGH - Complete fundamental language support

### Milestone 1.1: Assignment Statements & Pattern Matching

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
- [ ] Add both types to MetaAST core (`lib/metastatic/ast.ex`)
  - Define `@type assignment :: {:assignment, target :: meta_ast, value :: meta_ast}`
  - Define `@type inline_match :: {:inline_match, pattern :: meta_ast, value :: meta_ast}`
  - Update `@type meta_ast` union to include both types
  - Add to M2.1 Core layer documentation

- [ ] Implement in Elixir adapter (pattern matching semantics)
  - Simple match: `x = 5` → `{:inline_match, {:variable, "x"}, {:literal, :integer, 5}}`
  - Tuple destructuring: `{x, y} = {1, 2}` → `{:inline_match, {:tuple, [...]}, {:tuple, [...]}}`
  - List patterns: `[h | t] = list` → `{:inline_match, {:cons_pattern, ...}, ...}`
  - Nested patterns: `{:ok, value} = result`
  - Pin operator: `^x = 5` (matches against existing value of x)

- [ ] Implement in Erlang adapter (pattern matching semantics)
  - Simple match: `X = 5` → `{:inline_match, {:variable, "X"}, {:literal, :integer, 5}}`
  - Tuple destructuring: `{X, Y} = {1, 2}`
  - List patterns: `[H | T] = List`
  - Note: Erlang has single-assignment semantics (no rebinding)

- [ ] Implement in Python adapter (assignment semantics)
  - Simple assignment: `x = 5` → `{:assignment, {:variable, "x"}, {:literal, :integer, 5}}`
  - Multiple assignment: `x = y = 5` → nested assignments or multi-target assignment
  - Tuple unpacking: `x, y = 1, 2` → `{:assignment, {:tuple, [...]}, {:tuple, [...]}}`
  - List unpacking: `[x, y] = [1, 2]`
  - Augmented assignment: `x += 1` → `{:assignment, {:variable, "x"}, {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 1}}}`
  - Walrus operator: `(x := 5)` → assignment expression (language_specific or assignment)

- [ ] Update conformance validation
  - `AST.conforms?/1` must handle both `assignment` and `inline_match`
  - Validator should recognize both as M2.1 Core constructs

- [ ] Update all three skipped test fixtures
  - `test/fixtures/elixir/core/assignments.exs` → rename to `pattern_matching.exs`
  - `test/fixtures/python/core/conditionals.py` (contains assignments)
  - `test/fixtures/python/core/blocks.py` (contains assignments)

- [ ] Add comprehensive tests (25+ per adapter)
  - Elixir: simple matches, tuple/list destructuring, nested patterns, pin operator
  - Erlang: simple matches, tuple/list destructuring, single-assignment validation
  - Python: simple assignments, multiple targets, unpacking, augmented assignments

- [ ] Ensure round-trip fidelity >95%
- [ ] Document semantic differences in inline comments and module docs

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

### Milestone 1.2: Additional Python Statement Types

**Goal:** Complete Python adapter with all statement types

**Deliverables:**
- [ ] Python-specific statements (native layer)
  - `global` statement → `{:language_specific, :python, node, :global_declaration}`
  - `nonlocal` statement → `{:language_specific, :python, node, :nonlocal_declaration}`
  - `assert` statement → `{:language_specific, :python, node, :assert_statement}`
  - `del` statement → `{:language_specific, :python, node, :delete_statement}`
  - `pass` statement → `{:language_specific, :python, node, :pass_statement}`
- [ ] Add 15+ tests for Python-specific statements
- [ ] Update documentation with coverage matrix

**Success Criteria:**
- [ ] All 477 tests passing (0 skipped)
- [ ] Assignment round-trip >95% for all adapters
- [ ] Python statement coverage >98%
- [ ] Documentation updated with assignment examples

---

## Phase 2: Supplemental Modules for Cross-Language Support

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

### Milestone 2.1: Supplemental Module API

**Deliverables:**
- [ ] Define `Metastatic.Supplemental` behaviour
- [ ] Implement supplemental module registration
- [ ] Integrate with adapter `from_meta` pipeline
- [ ] Add supplemental validation and error reporting
- [ ] Create comprehensive error messages for unsupported constructs

**Files to Create:**
```
lib/metastatic/supplemental.ex                  # Core supplemental API
lib/metastatic/supplemental/registry.ex         # Module registry
lib/metastatic/supplemental/validator.ex        # Validation

test/metastatic/supplemental_test.exs           # Core tests
```

### Milestone 2.2: Official Supplemental Modules

**Deliverables:**
- [ ] Python pykka supplemental (actor model: `actor_call`, `spawn_process`)
- [ ] Python asyncio supplemental (async patterns)
- [ ] JavaScript nact supplemental (actor model)
- [ ] Documentation with usage examples
- [ ] 30+ tests for supplemental transformations

**Files to Create:**
```
lib/metastatic/supplemental/python/pykka.ex     # Pykka actor support
lib/metastatic/supplemental/python/asyncio.ex   # Asyncio support
lib/metastatic/supplemental/javascript/nact.ex  # Nact actor support

test/metastatic/supplemental/python_pykka_test.exs
test/metastatic/supplemental/python_asyncio_test.exs
test/metastatic/supplemental/javascript_nact_test.exs
```

### Milestone 2.3: Supplemental Discovery & Validation

**Deliverables:**
- [ ] Static analysis tool to detect required supplemental modules
- [ ] Runtime validation of supplemental compatibility
- [ ] CLI integration: `metastatic analyze --supplemental my_file.ex --target python`
- [ ] Compatibility matrix documentation

**Files to Create:**
```
lib/metastatic/supplemental/analyzer.ex         # Detect requirements
lib/metastatic/supplemental/compatibility.ex    # Version checking

lib/mix/tasks/metastatic.analyze.supplemental.ex # Mix task
```

### Milestone 2.4: Community Supplemental Infrastructure

**Deliverables:**
- [ ] Supplemental module template generator: `mix metastatic.gen.supplemental`
- [ ] Documentation for creating supplemental modules
- [ ] Contribution guidelines
- [ ] Registry of community modules

**Success Criteria:**
- [ ] Supplemental API stable and documented
- [ ] 3+ official supplemental modules (pykka, nact, asyncio)
- [ ] Static analysis detects required modules
- [ ] Community can create supplemental modules
- [ ] Cross-language transformation with supplemental modules tested

---

## Phase 3: Purity Analysis

**Timeline:** 2-3 months  
**Priority:** HIGH - Core analysis capability

### Overview

**Goal:** Implement function purity analysis at the MetaAST level, working across all supported languages.

**Purity Definition:**
- Pure function: deterministic output, no side effects, no external dependencies
- Impure: I/O operations, mutation, non-deterministic results, external state access

**Approach:** Static analysis at M2 level with language-specific hints from M1 metadata.

### Milestone 3.1: Purity Analysis Core

**Deliverables:**
- [ ] Define purity analysis API
- [ ] Implement AST traversal for side-effect detection
- [ ] Classify operations by purity
  - Pure: arithmetic, comparisons, pure function calls
  - Impure: I/O, mutation, random, time, network, database
  - Unknown: user-defined functions (requires annotation or interprocedural analysis)
- [ ] Track data flow through variables
- [ ] Handle control flow (conditionals, loops)

**Files to Create:**
```
lib/metastatic/analysis/purity.ex               # Core purity analyzer
lib/metastatic/analysis/purity/classifier.ex    # Operation classifier
lib/metastatic/analysis/purity/dataflow.ex      # Data flow tracking
lib/metastatic/analysis/purity/effects.ex       # Side effect detection

test/metastatic/analysis/purity_test.exs        # 50+ tests
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

### Milestone 3.2: Language-Specific Purity Rules

**Deliverables:**
- [ ] Python purity rules (stdlib function classifications)
- [ ] Elixir purity rules (Kernel, Enum, Stream functions)
- [ ] Erlang purity rules (stdlib modules)
- [ ] User-extensible purity annotations
- [ ] Configuration system for custom rules

**Files to Create:**
```
lib/metastatic/analysis/purity/rules/python.ex
lib/metastatic/analysis/purity/rules/elixir.ex
lib/metastatic/analysis/purity/rules/erlang.ex
lib/metastatic/analysis/purity/annotations.ex   # User annotations

priv/purity_rules/python_stdlib.exs             # Python stdlib classifications
priv/purity_rules/elixir_stdlib.exs             # Elixir stdlib classifications
priv/purity_rules/erlang_stdlib.exs             # Erlang OTP classifications
```

### Milestone 3.3: Interprocedural Analysis

**Deliverables:**
- [ ] Call graph construction
- [ ] Function dependency tracking
- [ ] Recursive purity propagation
- [ ] Memoization for performance
- [ ] Handle mutual recursion

**Files to Create:**
```
lib/metastatic/analysis/purity/callgraph.ex     # Call graph builder
lib/metastatic/analysis/purity/interprocedural.ex # Cross-function analysis
```

### Milestone 3.4: CLI Integration & Documentation

**Deliverables:**
- [ ] CLI command: `metastatic purity-check <file>`
- [ ] Output formats: text, JSON, detailed report
- [ ] Integration with existing `analyze` command
- [ ] Comprehensive documentation with examples
- [ ] Performance benchmarks (<200ms per 1000 LOC)

**Files to Create:**
```
lib/mix/tasks/metastatic.purity_check.ex        # CLI command
lib/metastatic/analysis/purity/formatter.ex     # Report formatting

test/mix/tasks/metastatic_purity_check_test.exs # 25+ tests
```

**Success Criteria:**
- [ ] Purity analysis works for Python, Elixir, Erlang
- [ ] False positive rate <5%
- [ ] False negative rate <10%
- [ ] Performance <200ms per 1000 LOC
- [ ] 100+ test cases covering edge cases
- [ ] Documentation with real-world examples

---

## Phase 4: Complexity Metrics

**Timeline:** 2-3 months  
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

### Milestone 4.1: Cyclomatic & Cognitive Complexity

**Deliverables:**
- [ ] Cyclomatic complexity calculation
  - Decision points: conditionals, loops, boolean operators
  - Path counting through control flow
- [ ] Cognitive complexity calculation
  - Nesting penalties
  - Structural complexity
  - Recursion detection
- [ ] Configurable thresholds and warnings

**Files to Create:**
```
lib/metastatic/analysis/complexity.ex           # Core complexity analyzer
lib/metastatic/analysis/complexity/cyclomatic.ex # McCabe complexity
lib/metastatic/analysis/complexity/cognitive.ex  # Cognitive complexity
lib/metastatic/analysis/complexity/control_flow.ex # CFG construction

test/metastatic/analysis/complexity_test.exs    # 50+ tests
```

**API Design:**
```elixir
alias Metastatic.Analysis.Complexity

# Analyze complexity
{:ok, metrics} = Complexity.analyze(document)

metrics.cyclomatic       # => 12
metrics.cognitive        # => 18
metrics.max_nesting      # => 4
metrics.warnings         # => ["High complexity (>10)", "Deep nesting (>3)"]
```

### Milestone 4.2: Halstead Metrics & LoC

**Deliverables:**
- [ ] Halstead metrics implementation
  - Operator and operand counting
  - Vocabulary, length, volume, difficulty, effort
- [ ] Lines of Code metrics
  - Physical lines (raw line count)
  - Logical lines (statement count at M2 level)
  - Comment lines (from M1 metadata)
- [ ] Maintainability Index calculation

**Files to Create:**
```
lib/metastatic/analysis/complexity/halstead.ex  # Halstead metrics
lib/metastatic/analysis/complexity/loc.ex       # LoC metrics
lib/metastatic/analysis/complexity/maintainability.ex
```

### Milestone 4.3: Function & Module Metrics

**Deliverables:**
- [ ] Function-level metrics
  - Function length (LoC, statement count)
  - Parameter count
  - Return point count
  - Local variable count
- [ ] Module-level metrics
  - Functions per module
  - Average complexity per module
  - Module coupling metrics
- [ ] Aggregate statistics and trends

**Files to Create:**
```
lib/metastatic/analysis/complexity/function.ex  # Function metrics
lib/metastatic/analysis/complexity/module.ex    # Module metrics
lib/metastatic/analysis/complexity/aggregates.ex # Statistics
```

### Milestone 4.4: CLI Integration & Visualization

**Deliverables:**
- [ ] CLI command: `metastatic complexity <file>`
- [ ] Multiple output formats: table, JSON, detailed report
- [ ] Threshold-based warnings and errors
- [ ] Integration with CI/CD (exit codes for failures)
- [ ] Visual reports (HTML/terminal)
- [ ] Comparison mode: compare metrics across versions

**Files to Create:**
```
lib/mix/tasks/metastatic.complexity.ex          # CLI command
lib/metastatic/analysis/complexity/formatter.ex # Report formatting
lib/metastatic/analysis/complexity/reporter.ex  # Visual reports

test/mix/tasks/metastatic_complexity_test.exs   # 30+ tests
```

**CLI Examples:**
```bash
# Analyze single file
metastatic complexity my_file.py

# Output as JSON
metastatic complexity --format json my_file.py

# Set thresholds
metastatic complexity --max-cyclomatic 10 --max-cognitive 15 my_file.py

# Analyze entire directory
metastatic complexity --recursive lib/

# Compare with previous version
metastatic complexity --compare HEAD~1 my_file.py
```

**Success Criteria:**
- [ ] All six metric types implemented
- [ ] Metrics work for Python, Elixir, Erlang
- [ ] Performance <100ms per 1000 LOC
- [ ] 100+ test cases
- [ ] Documentation with real-world examples
- [ ] CI/CD integration examples

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

**Timeline:** 6-8 months  
**Priority:** MEDIUM - Expand language coverage

### Language Priority Order

1. **Ruby** (Weeks 1-8)
2. **Haskell** (Weeks 9-16)
3. **JavaScript/TypeScript** (Weeks 17-24)
4. **Go** (Weeks 25-30)
5. **Rust** (Weeks 31-36)

### Milestone 6.1: Ruby Adapter

**Rationale:** Dynamic language similar to Python, excellent AST support via Ripper/Parser gems

**Deliverables:**
- [ ] Ruby parser integration (Ripper or Parser gem)
- [ ] Ruby AST → MetaAST (M1 → M2) for all three layers
- [ ] MetaAST → Ruby AST (M2 → M1) for all three layers
- [ ] 50+ Ruby test fixtures
- [ ] Round-trip accuracy >95%
- [ ] Performance <100ms per 1000 LoC

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

### Milestone 6.2: Haskell Adapter

**Rationale:** Pure functional language, excellent for purity analysis validation

**Deliverables:**
- [ ] Haskell parser integration (haskell-src-exts or GHC API)
- [ ] Haskell AST → MetaAST (M1 → M2) for all three layers
- [ ] MetaAST → Haskell AST (M2 → M1) for all three layers
- [ ] 40+ Haskell test fixtures
- [ ] Round-trip accuracy >90% (Haskell syntax complexity)
- [ ] Performance <150ms per 1000 LoC

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

### Advanced Analysis Features

- Dead code detection
- Unused variable analysis
- Control flow graph visualization
- Data flow analysis (taint tracking)
- Security vulnerability detection
- Code smell detection

---

## Success Metrics

### Phase 1: Complete Existing Adapters
- [ ] 100% test pass rate (0 skipped)
- [ ] Assignment round-trip >95% for all adapters
- [ ] Documentation updated

### Phase 2: Supplemental Modules
- [ ] 3+ official supplemental modules
- [ ] Static analysis detects requirements
- [ ] Community can create modules

### Phase 3: Purity Analysis
- [ ] False positive rate <5%
- [ ] False negative rate <10%
- [ ] Performance <200ms per 1000 LOC
- [ ] Works on Python, Elixir, Erlang

### Phase 4: Complexity Metrics
- [ ] All six metric types implemented
- [ ] Performance <100ms per 1000 LoC
- [ ] Works on Python, Elixir, Erlang

### Phase 5: Oeditus Integration
- [ ] Plugin operational in production
- [ ] Performance <30s for 10k LoC
- [ ] 10+ cross-language audit rules

### Phase 6: Additional Languages
- [ ] Five languages implemented (Ruby, Haskell, JS/TS, Go, Rust)
- [ ] Average round-trip accuracy >90%
- [ ] Performance <150ms per 1000 LoC
- [ ] Purity and complexity work on all languages

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

1. **Now:** Phase 1.1 - Implement assignment statements
2. **Week 2:** Phase 1.2 - Complete Python statement types
3. **Week 3:** Phase 2.1 - Design supplemental module API
4. **Month 2:** Phase 2.2-2.4 - Implement supplemental modules
5. **Month 3:** Phase 3.1 - Begin purity analysis core
6. **Month 5:** Phase 3.4 - Complete purity analysis
7. **Month 6:** Phase 4.1 - Begin complexity metrics
8. **Month 8:** Phase 4.4 - Complete complexity metrics
9. **Month 9:** Phase 5 - Oeditus integration
10. **Month 10-16:** Phase 6 - Additional languages

---

**Document Version:** 2.0  
**Created:** 2026-01-21  
**Supersedes:** IMPLEMENTATION_PLAN.md  
**Next Review:** End of Phase 1
