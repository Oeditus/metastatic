# Getting Started with Metastatic Development

Welcome to Metastatic! This guide will help you get up and running with the development environment.

## Prerequisites

### Required
- **Elixir 1.19+** and **Erlang/OTP 27+**
- **Git** for version control

### Current Status
**Phase 6 Partial + Advanced Analysis Complete!** All major analysis features are now operational.

- Phase 0: Core Foundation + BEAM/Python Adapters
- Phase 2: Supplemental Modules
- Phase 3: Purity Analysis
- Phase 4: Complexity Metrics
- Phase 6: Ruby & Haskell Adapters (2/5 additional languages)
- **NEW:** Advanced Analysis Features (6 analyzers)
- **Current test count:** 876+ tests passing

**Current Capabilities:**
- Parse and transform code across Python, Elixir, Erlang, Ruby, and Haskell
- Analyze function purity and side effects
- Measure code complexity (6 comprehensive metric types)
- Detect dead code and unreachable branches
- Track unused variables with scope awareness
- Generate control flow graphs (DOT/D3.js formats)
- Perform taint analysis for security vulnerabilities
- Scan for security issues with CWE identifiers
- Detect code smells and maintainability issues
- Semantic operation detection via OpKind (DB, HTTP, file, cache, auth, queue, external API)
- 15+ CLI tools for all analysis operations

### Optional (for future adapter development)
- **Python 3.9+** (Phase 3 - Python adapter)
- **Node.js 16+** (Phase 4 - JavaScript adapter)
- **Go 1.19+** (Phase 5 - Additional languages)
- **Rust 1.65+** (Phase 5 - Additional languages)
- **Ruby 3.0+** (Phase 5 - Additional languages)

## Quick Setup

```bash
# Clone the repository
cd /home/am/Proyectos/Oeditus/metastatic

# Install dependencies
mix deps.get

# Run tests (876+ tests, all passing!)
mix test

# Generate documentation
mix docs

# Run static analysis (optional)
mix format --check-formatted
```

## Project Structure

```
metastatic/
├── lib/
│   └── metastatic/
│       ├── ast.ex                  # ✅ Core MetaAST type definitions
│       ├── document.ex             # ✅ Document wrapper with metadata
│       ├── builder.ex              # ✅ High-level API
│       ├── adapter.ex              # ✅ Adapter behaviour
│       ├── validator.ex            # ✅ Conformance validation
│       ├── adapters/               # ✅ 5 language adapters
│       │   ├── python/             # ✅ Full Python support
│       │   ├── elixir/             # ✅ Full Elixir support
│       │   ├── erlang/             # ✅ Full Erlang support
│       │   ├── ruby/               # ✅ Full Ruby support
│       │   └── haskell/            # ✅ Full Haskell support
│       ├── supplemental/           # ✅ Phase 2 - Cross-language support
│       │   ├── registry.ex         # ✅ Supplemental module registry
│       │   ├── transformer.ex      # ✅ Transformation helper
│       │   └── python/             # ✅ Pykka (actors), Asyncio
│       ├── semantic/               # ✅ Semantic metadata systems
│       │   ├── op_kind.ex          # ✅ Operation kind metadata (DB, HTTP, file, etc.)
│       │   └── enricher.ex         # ✅ Semantic enrichment for AST nodes
│       ├── analysis/               # ✅ Complete analysis suite
│       │   ├── purity.ex           # ✅ Purity analyzer
│       │   ├── purity/             # ✅ Side effect detection
│       │   ├── complexity.ex       # ✅ Complexity analyzer (6 metrics)
│       │   ├── complexity/         # ✅ Metric calculators
│       │   ├── duplication.ex      # ✅ Code duplication detection
│       │   ├── dead_code.ex        # ✅ Dead code detection
│       │   ├── unused_variables.ex # ✅ Unused variable analysis
│       │   ├── control_flow.ex     # ✅ CFG generation
│       │   ├── taint.ex            # ✅ Taint analysis
│       │   ├── security.ex         # ✅ Security scanning
│       │   └── smells.ex           # ✅ Code smell detection
│       └── mix/tasks/              # ✅ CLI tools (15+ tasks)
│           ├── metastatic.translate.ex
│           ├── metastatic.inspect.ex
│           ├── metastatic.purity_check.ex
│           ├── metastatic.complexity.ex
│           ├── metastatic.dead_code.ex
│           ├── metastatic.unused_vars.ex
│           ├── metastatic.control_flow.ex
│           ├── metastatic.taint_check.ex
│           ├── metastatic.security_scan.ex
│           └── metastatic.code_smells.ex
├── test/
│   └── metastatic/                 # ✅ 876+ tests passing
│       ├── ast_test.exs
│       ├── adapters/               # ✅ Python, Elixir, Erlang, Ruby, Haskell
│       ├── supplemental/           # ✅ Supplemental modules
│       ├── analysis/               # ✅ All analyzers
│       └── mix/tasks/              # ✅ CLI tools
├── RESEARCH.md                     # ✅ Research and architecture (826 lines)
├── THEORETICAL_FOUNDATIONS.md      # ✅ Formal theory (953 lines)
├── IMPLEMENTATION_PLAN.md          # ✅ Detailed roadmap (840 lines)
├── GETTING_STARTED.md              # ✅ Developer guide (379 lines)
└── README.md                       # ✅ Project overview
```

## Development Workflow

### 1. Understanding the Architecture

Before diving in, read these documents in order:

1. **README.md** - High-level overview and current status
2. **RESEARCH.md** - Deep dive into the MetaAST design decisions (826 lines)
3. **THEORETICAL_FOUNDATIONS.md** - Formal meta-modeling theory with proofs (953 lines)
4. **IMPLEMENTATION_PLAN.md** - Roadmap and milestones (Phase 1 complete!)

### 2. Running Tests

```bash
# Run all tests (876+ tests, all passing!)
mix test

# Run specific test file
mix test test/metastatic/ast_test.exs

# Run with verbose output
mix test --trace

# Generate documentation
mix docs

# Open documentation in browser
open doc/index.html
```

### 3. Working on a Feature

Follow this process:

```bash
# 1. Create a feature branch
git checkout -b feature/my-feature

# 2. Make your changes
# Edit files in lib/ and test/

# 3. Run tests frequently
mix test

# 4. Format code
mix format

# 5. Run static analysis
mix credo

# 6. Commit with descriptive messages
git commit -m "Add support for X in MetaAST"

# 7. Push and create PR
git push origin feature/my-feature
```

### 4. Code Style

We follow standard Elixir conventions:

- **Formatting**: Use `mix format` (configured in `.formatter.exs`)
- **Documentation**: All public functions must have `@doc` and examples
- **Typespecs**: All public functions must have `@spec`
- **Tests**: Aim for >90% coverage
- **Naming**: Use descriptive names, avoid abbreviations

**Example:**

```elixir
@doc """
Transform a Python binary operation to MetaAST.

## Examples

    iex> transform_binop(%{"_type" => "Add"})
    {:binary_op, :arithmetic, :+, left, right}

"""
@spec transform_binop(map()) :: {:ok, MetaAST.node()} | {:error, term()}
def transform_binop(%{"_type" => op_type, "left" => left, "right" => right}) do
  # Implementation
end
```

## Common Tasks

### Working with MetaAST (Phase 1 - Available Now!)

```elixir
alias Metastatic.{AST, Document, Validator}

# Create a MetaAST manually
ast = {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}}

# Check conformance
AST.conforms?(ast)  # => true

# Extract variables
AST.variables(ast)  # => MapSet.new(["x"])

# Wrap in a document
doc = Document.new(ast, :python)

# Validate with metadata
{:ok, meta} = Validator.validate(doc)
meta.level  # => :core
meta.depth  # => 2
meta.variables  # => MapSet.new(["x"])
```

### Using Language Adapters (Phase 2 - Available Now!)

#### Elixir Adapter

```elixir
alias Metastatic.Adapters.Elixir, as: ElixirAdapter
alias Metastatic.Builder

# Parse Elixir source to MetaAST
source = "x + 5"
{:ok, doc} = Builder.from_source(source, ElixirAdapter)

# doc.ast will be:
# {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}}

# Convert back to Elixir source
{:ok, result} = Builder.to_source(doc)
# => "x + 5"

# Round-trip validation
{:ok, doc} = Builder.round_trip(source, ElixirAdapter)
```

#### Erlang Adapter

```elixir
alias Metastatic.Adapters.Erlang, as: ErlangAdapter

# Parse Erlang source to MetaAST
source = "X + 5."
{:ok, doc} = Builder.from_source(source, ErlangAdapter)

# Same MetaAST as Elixir!
# {:binary_op, :arithmetic, :+, {:variable, "X"}, {:literal, :integer, 5}}

# Convert to Erlang source
{:ok, result} = Builder.to_source(doc)
# => "X + 5"
```

### Cross-Language Equivalence

```elixir
# Parse Elixir
elixir_source = "x + 5"
{:ok, elixir_doc} = Builder.from_source(elixir_source, ElixirAdapter)

# Parse semantically equivalent Erlang
erlang_source = "X + 5."
{:ok, erlang_doc} = Builder.from_source(erlang_source, ErlangAdapter)

# Normalize variable names for comparison
elixir_vars = elixir_doc.ast |> normalize_vars()
erlang_vars = erlang_doc.ast |> normalize_vars()

# Same MetaAST structure!
assert elixir_vars == erlang_vars
```

### Using Advanced Analyzers (Available Now!)

Metastatic includes six advanced static analysis capabilities:

#### Dead Code Detection

```elixir
alias Metastatic.Analysis.DeadCode

# Detect code after return
ast = {:block, [
  {:early_return, {:literal, :integer, 42}},
  {:function_call, "print", [{:literal, :string, "hello"}]}  # unreachable!
]}
doc = Document.new(ast, :python)
{:ok, result} = DeadCode.analyze(doc)

result.has_dead_code?  # => true
result.issues          # => [{:code_after_return, :high, "Code after return statement", ...}]

# CLI usage
# mix metastatic.dead_code my_file.py
# mix metastatic.dead_code my_file.ex --format json
```

#### Unused Variables

```elixir
alias Metastatic.Analysis.UnusedVariables

# Track variable usage
ast = {:block, [
  {:assignment, {:variable, "x"}, {:literal, :integer, 5}},
  {:assignment, {:variable, "y"}, {:literal, :integer, 10}},
  {:binary_op, :arithmetic, :+, {:variable, "y"}, {:literal, :integer, 1}}
]}
doc = Document.new(ast, :elixir)
{:ok, result} = UnusedVariables.analyze(doc)

result.has_unused?  # => true
result.unused       # => MapSet.new(["x"])
result.defined      # => MapSet.new(["x", "y"])
result.used         # => MapSet.new(["y"])

# CLI usage
# mix metastatic.unused_vars my_file.ex
# mix metastatic.unused_vars my_file.py --ignore-underscore
```

#### Control Flow Graph

```elixir
alias Metastatic.Analysis.ControlFlow

# Build CFG
ast = {:conditional, {:variable, "x"},
  {:early_return, {:literal, :integer, 1}},
  {:literal, :integer, 2}
}
doc = Document.new(ast, :python)
{:ok, result} = ControlFlow.analyze(doc)

result.node_count   # => 5
result.edge_count   # => 4
result.has_cycles?  # => false

# Export to DOT for Graphviz
dot_graph = result.to_dot()
# "digraph CFG {\n  0 [label=\"ENTRY\"];\n  ...

# Export to D3.js JSON
json_data = result.to_d3_json()
# %{nodes: [%{id: 0, label: "ENTRY", type: "entry", group: 1}, ...],
#   links: [%{source: 0, target: 1, label: nil, type: "normal"}, ...]}

# CLI usage
# mix metastatic.control_flow my_file.py --format dot
# mix metastatic.control_flow my_file.ex --format d3 --output cfg.json
```

#### Taint Analysis

```elixir
alias Metastatic.Analysis.Taint

# Detect taint vulnerabilities
ast = {:function_call, "eval", [
  {:function_call, "input", []}  # Dangerous: eval(input())
]}
doc = Document.new(ast, :python)
{:ok, result} = Taint.analyze(doc)

result.has_vulnerabilities?  # => true
result.vulnerabilities       # => [{:code_injection, "eval called with untrusted source", :high}]

# CLI usage
# mix metastatic.taint_check my_file.py
# mix metastatic.taint_check my_file.ex --format json
```

#### Security Scanning

```elixir
alias Metastatic.Analysis.Security

# Detect security issues
ast = {:assignment, {:variable, "password"}, {:literal, :string, "admin123"}}
doc = Document.new(ast, :python)
{:ok, result} = Security.analyze(doc)

result.has_vulnerabilities?  # => true
vuln = hd(result.vulnerabilities)
vuln.type      # => :hardcoded_secret
vuln.severity  # => :high
vuln.cwe       # => "CWE-798"
vuln.location  # => "Variable: password"

# CLI usage
# mix metastatic.security_scan my_file.py
# mix metastatic.security_scan my_file.ex --format json
```

#### Code Smell Detection

```elixir
alias Metastatic.Analysis.Smells

# Detect code smells (requires complexity metrics first)
ast = {:block, [
  {:conditional, {:variable, "a"}, {:literal, :integer, 1}, {:literal, :integer, 2}},
  {:conditional, {:variable, "b"}, {:literal, :integer, 3}, {:literal, :integer, 4}},
  # ... many more statements creating long function and deep nesting
]}
doc = Document.new(ast, :python)
{:ok, result} = Smells.analyze(doc)

result.has_smells?  # => true (if thresholds exceeded)
result.smells       # => [:long_function, :deep_nesting] (if detected)
result.severity     # => :medium or :high

# CLI usage
# mix metastatic.code_smells my_file.py
# mix metastatic.code_smells my_file.ex --format detailed
```

### Adding a New Language Adapter (Phase 3+)

See existing Elixir and Erlang adapters as reference implementations.

### Adding a New Mutator

1. **Create mutator module**: `lib/metastatic/mutators/my_mutator.ex`
2. **Implement mutation logic**: Use `Macro.postwalk/2`
3. **Add tests**: Test on multiple languages
4. **Document**: Include examples

### Adding Test Fixtures

```bash
# Create fixture directory
mkdir -p test/fixtures/elixir/

# Add source file
echo 'x + y' > test/fixtures/elixir/simple_add.ex

# Add expected MetaAST
cat > test/fixtures/elixir/expected/simple_add.exs << 'EOF'
{:binary_op, :arithmetic, :+, {:variable, "x"}, {:variable, "y"}}
EOF
```

## Testing Philosophy

### Unit Tests
Test individual transformations and functions:

```elixir
test "transforms Elixir addition to MetaAST" do
  elixir_ast = {:+, [], [{:x, [], nil}, 5]}
  {:ok, meta_ast} = Metastatic.Adapters.Elixir.ToMeta.transform(elixir_ast)
  assert {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}} = meta_ast
end
```

### Integration Tests
Test full round-trips:

```elixir
test "round-trip Elixir source through MetaAST" do
  source = "x + 5"
  alias Metastatic.Adapters.Elixir, as: ElixirAdapter
  {:ok, doc} = Builder.from_source(source, ElixirAdapter)
  {:ok, result} = Builder.to_source(doc)
  assert result == source
end
```

### Property Tests
Use StreamData for property-based testing:

```elixir
property "all arithmetic mutations are valid" do
  check all ast <- ast_generator() do
    mutations = Mutator.arithmetic_inverse(ast)
    assert Enum.all?(mutations, &valid_ast?/1)
  end
end
```

## Debugging Tips

### Inspecting ASTs

```elixir
# In IEx
iex> alias Metastatic.Adapters.Elixir, as: ElixirAdapter
iex> source = "x + 5"
iex> {:ok, doc} = Metastatic.Builder.from_source(source, ElixirAdapter)
iex> IO.inspect(doc.ast, label: "MetaAST")
iex> IO.inspect(doc.metadata, label: "Metadata")
```

### Using IEx for Development

```bash
# Start IEx with project loaded
iex -S mix

# Reload changed modules
iex> recompile()

# Run specific test
iex> ExUnit.run()
```

### Testing Adapters

```bash
# Test Elixir adapter
mix test test/metastatic/adapters/elixir_test.exs

# Test Erlang adapter
mix test test/metastatic/adapters/erlang_test.exs

# Test specific feature
mix test test/metastatic/adapters/elixir_test.exs:45
```

## Documentation

### Writing Docs

All public functions must have:

```elixir
@doc """
Brief one-line description.

Longer explanation if needed. Explain what the function does,
not how it does it.

## Examples

    iex> MyModule.my_function(arg)
    expected_result

## Options

- `:option1` - Description
- `:option2` - Description

"""
@spec my_function(arg_type()) :: return_type()
def my_function(arg) do
  # Implementation
end
```

### Generating Docs

```bash
# Generate HTML documentation
mix docs

# Open in browser
open doc/index.html
```

## Performance Considerations

### Profiling

```elixir
# Use :fprof for profiling
alias Metastatic.Adapters.Elixir, as: ElixirAdapter
source = "x + 5"
:fprof.apply(&Metastatic.Builder.from_source/2, [source, ElixirAdapter])
:fprof.profile()
:fprof.analyse()
```

### Benchmarking

```elixir
# Use Benchee for benchmarking
alias Metastatic.Adapters.{Elixir, Erlang}
source_ex = "x + 5"
source_erl = "X + 5."

Benchee.run(%{
  "parse elixir" => fn -> Metastatic.Builder.from_source(source_ex, Elixir) end,
  "parse erlang" => fn -> Metastatic.Builder.from_source(source_erl, Erlang) end
})
```

## Troubleshooting

### Common Issues

**Issue: Elixir parse error**
```
Error: Code.string_to_quoted/1 failed with syntax error
```
**Solution:** Ensure Elixir source is syntactically valid

**Issue: Erlang parse error**
```
Error: :erl_parse.parse_exprs failed
```
**Solution:** Ensure Erlang expressions end with a period (`.`)

**Issue: Tests failing after changes**
```
Error: test/metastatic/adapters/... failed
```
**Solution:** Check MetaAST structure matches expected format; run `mix format` to ensure consistent formatting

## Getting Help

- **Issues**: Open a GitHub issue for bugs or feature requests
- **Discussions**: Use GitHub Discussions for questions
- **Slack**: Join #metastatic channel (internal)
- **Documentation**: Check RESEARCH.md and IMPLEMENTATION_PLAN.md

## Contributing Checklist

Before submitting a PR:

- [ ] Code is formatted (`mix format`)
- [ ] Tests pass (`mix test`)
- [ ] Coverage > 90% for new code
- [ ] Credo passes (`mix credo --strict`)
- [ ] Dialyzer passes (`mix dialyzer`)
- [ ] Documentation added/updated
- [ ] CHANGELOG.md updated
- [ ] Commit messages are descriptive

## Next Steps

1. **Read the research**: Start with RESEARCH.md to understand the "why"
2. **Pick a task**: Check IMPLEMENTATION_PLAN.md for current priorities
3. **Set up environment**: Install required runtimes
4. **Run tests**: Make sure everything works
5. **Start coding**: Pick an issue or feature from the roadmap

Welcome aboard! 🚀
