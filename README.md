# Metastatic

**Cross-language code analysis through unified MetaAST representation**

Metastatic is a library that provides a unified MetaAST (Meta-level Abstract Syntax Tree) intermediate representation for parsing, transforming, and analyzing code across multiple programming languages using a three-layer meta-model architecture.

## Vision

Build tools once, apply them everywhere. Create a universal meta-model for program syntax that enables cross-language code analysis, transformation, and tooling.

**Metastatic provides the foundation** - the MetaAST meta-model and language adapters. Tools that leverage this foundation (mutation testing, purity analysis, complexity metrics) are built separately.

**Note:** Mutation testing functionality will be implemented in the separate [`muex`](https://github.com/Oeditus/muex) library, which will leverage Metastatic's MetaAST as its foundation.

## Key Features

- **Layered Architecture**: Three-layer MetaAST design (M2.1 Core, M2.2 Extended, M2.3 Native)
- **Language Adapters**: Bidirectional M1 ↔ M2 transformations for multiple languages
- **Round-Trip Fidelity**: Transform source → MetaAST → source with >90% accuracy
- **Meta-Model Foundation**: MOF-based meta-modeling (M2 level) for universal AST representation
- **Cross-Language Equivalence**: Semantically equivalent code produces identical MetaAST across languages

## Scope

**What Metastatic Provides:**
- MetaAST meta-model (M2 level) with three layers
- Language adapters (Python, Elixir, Erlang, more planned)
- Parsing, transformation, and unparsing infrastructure
- Cross-language semantic equivalence validation

**What Metastatic Does NOT Provide:**
- Mutation testing (see [`muex`](https://github.com/Oeditus/muex) library)
- Purity analysis (planned for separate library)
- Complexity metrics (planned for separate library)
- Code quality auditing (see Oeditus ecosystem)

Metastatic is a **foundation library** that other tools build upon.

## Current Status

**Phase:** Phase 5 Milestone 5.1 Complete 🎉 - CLI Tools!  
**Version:** 0.5.0-dev  
**Completed:** Phase 1 (Foundation) + Phase 2 (BEAM Adapters) + Phase 3 (Python Adapter) + Phase 5.1 (CLI Tools)  
**Tests:** 477 passing (21 doctests + 456 tests), 99.4% pass rate, 0 failures  
**Next:** Phase 4 - JavaScript Adapter (planned)  
**Languages Supported:**
- Elixir ✅ (all 3 layers: Core, Extended, Native)
- Erlang ✅ (all 3 layers: Core, Extended, Native)
- Python ✅ (all 3 layers: Core, Extended, Native)

**Languages Planned:** JavaScript, TypeScript, Ruby, Go, Rust

## Quick Start

### CLI Tools

Metastatic provides command-line tools for cross-language translation, AST inspection, and semantic analysis:

```bash
# Cross-language translation
mix metastatic.translate --from python --to elixir hello.py
mix metastatic.translate --from elixir --to python lib/module.ex --output py_output/

# AST inspection (tree format)
mix metastatic.inspect hello.py

# AST inspection (JSON format)
mix metastatic.inspect --format json hello.py

# Filter by layer
mix metastatic.inspect --layer core hello.py

# Extract variables only
mix metastatic.inspect --variables hello.py

# Analyze MetaAST metrics
mix metastatic.analyze hello.py

# Validate with strict mode
mix metastatic.analyze --validate strict hello.py

# Check semantic equivalence
mix metastatic.validate_equivalence hello.py hello.ex

# Show detailed differences
mix metastatic.validate_equivalence --verbose file1.py file2.ex
```

### Using Language Adapters (Elixir & Erlang)

```elixir
alias Metastatic.Adapters.{Elixir, Erlang}
alias Metastatic.{Adapter, Document}

# Parse Elixir source code
{:ok, doc} = Adapter.abstract(Elixir, "x + 5", :elixir)
doc.ast  # => {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}}

# Parse Erlang source code
{:ok, doc} = Adapter.abstract(Erlang, "X + 5.", :erlang)
doc.ast  # => {:binary_op, :arithmetic, :+, {:variable, "X"}, {:literal, :integer, 5}}

# Round-trip transformation
source = "x + y * 2"
{:ok, result} = Adapter.round_trip(Elixir, source)
result == source  # => true

# Convert back to source
{:ok, source} = Adapter.reify(Elixir, doc)

# Cross-language equivalence
elixir_source = "x + 5"
erlang_source = "X + 5."

{:ok, elixir_doc} = Adapter.abstract(Elixir, elixir_source, :elixir)
{:ok, erlang_doc} = Adapter.abstract(Erlang, erlang_source, :erlang)

# Both produce semantically equivalent MetaAST!
# (only variable naming differs: "x" vs "X")
```

### Working with MetaAST Directly

```elixir
alias Metastatic.{AST, Document, Validator}

# Create a MetaAST document
ast = {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}}
doc = Document.new(ast, :elixir)

# Validate conformance
{:ok, meta} = Validator.validate(doc)
meta.level  # => :core
meta.variables  # => MapSet.new(["x"])

# Extract variables
AST.variables(ast)  # => MapSet.new(["x"])

# Check conformance
AST.conforms?(ast)  # => true
```

### Supplemental Modules

Supplemental modules extend MetaAST with library-specific integrations, enabling cross-language transformations:

```elixir
alias Metastatic.Supplemental.Transformer

# Transform actor patterns to Python Pykka library calls
ast = {:actor_call, {:variable, "worker"}, "process", [data]}
{:ok, python_ast} = Transformer.transform(ast, :python)
# Result: {:function_call, "worker.ask", [{:literal, :string, "process"}, data]}

# Check what supplementals are available for a language
Transformer.supported_constructs(:python)
# => [:actor_call, :actor_cast, :spawn_actor, :async_await, :async_context, :gather]

# Validate what supplementals a document needs
alias Metastatic.Supplemental.Validator
{:ok, analysis} = Validator.validate(doc)
analysis.required_supplementals  # => [:pykka, :asyncio]
```

**Available supplementals:**
- **Python.Pykka** - Actor model support (`:actor_call`, `:actor_cast`, `:spawn_actor`)
- **Python.Asyncio** - Async/await patterns (`:async_await`, `:async_context`, `:gather`)

See **[SUPPLEMENTAL_MODULES.md](SUPPLEMENTAL_MODULES.md)** for comprehensive guide on using and creating supplementals.

### Purity Analysis

Analyze code for side effects and functional purity across all supported languages:

```bash
# Check if code is pure
mix metastatic.purity_check my_file.py
# Output: PURE or IMPURE: [effects]

# Detailed analysis
mix metastatic.purity_check my_file.ex --format detailed

# JSON output for CI/CD
mix metastatic.purity_check my_file.erl --format json
```

```elixir
alias Metastatic.{Document, Analysis.Purity}

# Pure arithmetic
ast = {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}}
doc = Document.new(ast, :python)
{:ok, result} = Purity.analyze(doc)

result.pure?              # => true
result.effects            # => []
result.confidence         # => :high

# Impure with I/O
ast = {:function_call, "print", [{:literal, :string, "hello"}]}
doc = Document.new(ast, :python)
{:ok, result} = Purity.analyze(doc)

result.pure?              # => false
result.effects            # => [:io]
result.summary            # => "Function is impure due to I/O operations"
```

**Detected Effects:**
- I/O operations (print, file access, network, database)
- Mutations (assignments in loops)
- Random operations (random, rand)
- Time operations (time, date, now)
- Exception handling (try/catch)
- Unknown function calls (low confidence)

### Complexity Analysis

Analyze code complexity with six comprehensive metrics that work uniformly across all supported languages:

```bash
# Analyze complexity
mix metastatic.complexity my_file.py

# JSON output
mix metastatic.complexity my_file.ex --format json

# Detailed report with recommendations
mix metastatic.complexity my_file.erl --format detailed

# Custom thresholds
mix metastatic.complexity my_file.py --max-cyclomatic 15 --max-cognitive 20
```

```elixir
alias Metastatic.{Document, Analysis.Complexity}

# Analyze all metrics
ast = {:conditional, {:variable, "x"}, 
  {:conditional, {:variable, "y"}, {:literal, :integer, 1}, {:literal, :integer, 2}},
  {:literal, :integer, 3}}
doc = Document.new(ast, :python)
{:ok, result} = Complexity.analyze(doc)

result.cyclomatic      # => 3 (McCabe complexity)
result.cognitive       # => 3 (with nesting penalties)
result.max_nesting     # => 2
result.halstead.volume # => 45.6 (program volume)
result.loc.logical     # => 2
result.warnings        # => []
result.summary         # => "Code has low complexity"
```

**Available Metrics:**
- **Cyclomatic Complexity** - McCabe metric measuring decision points
- **Cognitive Complexity** - Measures understandability with nesting penalties
- **Nesting Depth** - Maximum nesting level
- **Halstead Metrics** - Volume, difficulty, and effort calculations
- **Lines of Code** - Physical, logical, and comment line counts
- **Function Metrics** - Statement count, return points, variable count

**Default Thresholds:**
- Cyclomatic: 10 (warning), 20 (error)
- Cognitive: 15 (warning), 30 (error)
- Nesting: 3 (warning), 5 (error)
- Logical LoC: 50 (warning), 100 (error)

## Documentation

- **[RESEARCH.md](RESEARCH.md)** - Comprehensive research analysis and architectural decisions
- **[THEORETICAL_FOUNDATIONS.md](THEORETICAL_FOUNDATIONS.md)** - Formal meta-modeling theory and proofs
- **[IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md)** - Detailed 14-month implementation roadmap
- **[GETTING_STARTED.md](GETTING_STARTED.md)** - Developer onboarding guide
- **[SUPPLEMENTAL_MODULES.md](SUPPLEMENTAL_MODULES.md)** - Guide to using and creating supplemental modules
- **API Documentation** - Generate with `mix docs`

## Architecture

### Three-Layer MetaAST

**Layer 1: Core** (always normalized)  
Common constructs: literals, variables, operators, conditionals, function calls

**Layer 2: Extended** (normalized with hints)  
Common patterns: loops, lambdas, collection operations, pattern matching

**Layer 3: Native** (preserved as-is)  
Language-specific: lifetimes, async models, type systems, metaprogramming

### Coverage

- ✅ 95%+ of mutation testing use cases
- ✅ 100% of core operators and control flow
- ✅ Purity analysis across all languages
- ✅ Complexity metrics uniformly applicable

## Roadmap

### ✅ Phase 1: Foundation (Complete!)
**Milestone 1.1: Core MetaAST Types**
- ✅ Core MetaAST types (M2.1, M2.2, M2.3)
- ✅ Document wrapper with metadata
- ✅ Validator with conformance checking
- ✅ 99 tests with 100% coverage

**Milestone 1.2: Adapter Registry & Testing**
- ✅ GenServer-based Adapter Registry
- ✅ Round-trip testing framework (AdapterHelper)
- ✅ 44 additional tests

**Milestone 1.3: Builder API**
- ✅ Builder module (from_source/to_source API)
- ✅ Registry integration
- ✅ 32 comprehensive Builder tests

**Milestone 1.4: Test Infrastructure**
- ✅ Fixture framework (FixtureHelper)
- ✅ Performance benchmarks (AST & Validation)
- ✅ CI/CD pipeline (GitHub Actions)
- ✅ Test fixture directories for all languages

**Total: 175 tests, 2,660 LOC, 3,648 lines documentation**

### ✅ Phase 2: BEAM Ecosystem Adapters (Complete!)
**Milestone 2.1: Elixir Adapter - Foundation**
- ✅ Full M1 ↔ M2 bidirectional transformations
- ✅ Parse/unparse using native `Code` module
- ✅ 66 comprehensive tests covering M2.1 (Core) constructs
- ✅ Support for anonymous functions (M2.2 Extended)
- ✅ Round-trip fidelity >95%

**Milestone 2.2: Elixir Adapter - Extended Constructs**
- ✅ Anonymous functions (fn)
- ✅ Pattern matching (case)
- ✅ Collection operations (Enum.map/filter/reduce)
- ✅ List comprehensions (for)

**Milestone 2.4: Elixir Adapter - Native Constructs**
- ✅ Pipe operator (|>) as language_specific
- ✅ with expressions as language_specific
- ✅ Test fixtures for all three layers

**Milestone 2.3: Erlang Adapter**
- ✅ Full M1 ↔ M2 transformations
- ✅ Parse using :erl_scan + :erl_parse
- ✅ Unparse using :erl_pp
- ✅ 33 comprehensive tests
- ✅ Operator normalization (Erlang → standard)
- ✅ Round-trip fidelity >90%
- ✅ Cross-language validation (Elixir ≈ Erlang at M2 level)

**Total Phase 2: 105 new tests (259 total), +2,200 LOC, comprehensive test fixtures**

### ✅ Phase 3: Python Adapter (Complete!)
**Milestone 3.1: Parser Integration**
- ✅ Python AST parsing via subprocess
- ✅ JSON serialization with robust error handling
- ✅ 110 Python adapter tests

**Milestone 3.2: Core Layer (M2.1)**
- ✅ All Core constructs (literals, variables, operators, conditionals, blocks)
- ✅ 45 Core layer tests, 100% passing

**Milestone 3.3: Extended Layer (M2.2)**
- ✅ Loops, lambdas, collection operations, exception handling
- ✅ 23 Extended layer tests, 100% passing

**Milestone 3.4: Native Layer (M2.3) & Fixtures**
- ✅ 21 language_specific patterns
- ✅ 17 test fixtures with comprehensive documentation
- ✅ 25 Native layer tests + 18 integration tests + 6 cross-language tests
- ✅ Performance validation (<100ms per 1000 LOC)

**Total Phase 3: 136 new tests (395 total), +1,335 LOC, zero regressions**

### ✅ Phase 5 Milestone 5.1: CLI Tools (Complete!)
**Deliverables:**
- ✅ `mix metastatic.translate` - Cross-language code translation
- ✅ `mix metastatic.inspect` - AST inspection with multiple formats
- ✅ `mix metastatic.analyze` - MetaAST metrics and validation
- ✅ `mix metastatic.validate_equivalence` - Semantic equivalence checking
- ✅ 82 comprehensive CLI tests (18 + 29 + 19 + 16)
- ✅ Tree, JSON, and plain output formats
- ✅ Layer filtering (core/extended/native)
- ✅ Validation modes (strict/standard/permissive)
- ✅ Colored ANSI terminal output

**Total Phase 5.1: 82 new tests (477 total), +3,179 LOC, 100% passing**

### Phase 4: JavaScript Adapter (Months 4-6)
- JavaScript adapter with Babel parser integration
- M1 ↔ M2 bidirectional transformations
- Cross-language validation (JavaScript ≡ Python ≡ Elixir)

### Phase 6: Additional Languages (Months 7-12)
- TypeScript adapter
- Ruby adapter
- Go adapter
- Rust adapter (optional)

### Phase 6: Supplemental Modules (Months 13-18)
- Supplemental module API for cross-language feature gaps
- Official supplemental modules (pykka, nact, asyncio)
- Static analysis and discovery tools
- Community infrastructure

See [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) for complete roadmap.

## Examples

### Shopping Cart Example

A comprehensive real-world example demonstrating metastatic's capabilities using an e-commerce shopping cart:

```bash
# From project root
mix compile

# Run interactive demo
elixir examples/shopping_cart/demo.exs

# Visualize MetaAST tree structures
elixir examples/shopping_cart/visualize_ast.exs
```

**What you'll learn:**
- How MetaAST represents real business logic (pricing, discounts, validation)
- Cross-language semantic equivalence (same logic in Python, JavaScript, Elixir, etc.)
- Foundation for universal tools (mutation testing, purity analysis, complexity metrics)
- Three-layer architecture in practice (Core/Extended/Native)

**Files:**
- `examples/shopping_cart/README.md` - Comprehensive 500-line guide
- `examples/shopping_cart/lib/` - Product and Cart modules with rich business logic
- `examples/shopping_cart/demo.exs` - Interactive MetaAST operations demo
- `examples/shopping_cart/visualize_ast.exs` - Tree visualization with annotations

See [examples/README.md](examples/README.md) for more details.

## Use Cases

### Foundation for Cross-Language Tools
Metastatic provides the MetaAST foundation that other tools build upon:

```elixir
# Mutation testing (in muex library)
Muex.mutate_file("src/calculator.py", :python)
Muex.mutate_file("src/calculator.js", :javascript)
# Both use Metastatic's MetaAST under the hood!
```

### Cross-Language Code Transformation
Transform code between languages (for supported constructs):

```elixir
# Parse Python
{:ok, doc} = Metastatic.Builder.from_source(python_source, :python)

# Transform to Elixir (with supplemental modules for unsupported constructs)
{:ok, elixir_source} = Metastatic.Builder.to_source(doc, :elixir)
```

### Semantic Equivalence Validation
Verify that code across languages has identical semantics:

```elixir
{:ok, py_doc} = Metastatic.Builder.from_source("x + 5", :python)
{:ok, ex_doc} = Metastatic.Builder.from_source("x + 5", :elixir)

py_doc.ast == ex_doc.ast  # => true (same MetaAST)
```

### AST Analysis Infrastructure
Build language-agnostic analysis tools:

```elixir
# Extract all variables from any supported language
{:ok, doc} = Metastatic.Builder.from_source(source, language)
variables = Metastatic.AST.variables(doc.ast)
```

## Contributing

This project is currently in the research/foundation phase. Contributions welcome!

See [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) for detailed roadmap and contribution opportunities.

## Research Background

Metastatic is inspired by research from:
- **muex** - Multi-language mutation testing analysis
- **propwise** - Property-based testing candidate identification

See [RESEARCH.md](RESEARCH.md) for the complete analysis of cross-language AST transformation approaches.

## License

Apache 2.0 - See LICENSE file for details

## Credits

Created as part of the Oeditus code quality tooling ecosystem.

Research synthesis from muex and propwise multi-language analysis projects.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `metastatic` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:metastatic, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/metastatic>.

