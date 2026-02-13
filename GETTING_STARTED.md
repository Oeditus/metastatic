# Getting Started with Metastatic Development

Welcome to Metastatic! This guide will help you get up and running with the development environment.

## Prerequisites

### Required
- **Elixir 1.19+** and **Erlang/OTP 27+**
- **Git** for version control

### Current Status
Metastatic is production-ready with comprehensive analysis capabilities.

- **Test coverage:** 1764 tests passing (1523 tests + 241 doctests)
- **Language adapters:** Python, Elixir, Erlang, Ruby, Haskell
- **Static analyzers:** 9 core analyzers + 32 business logic analyzers
- **CWE coverage:** 15 CWE Top 25 vulnerabilities detected

**Current Capabilities:**
- Parse and transform code across Python, Elixir, Erlang, Ruby, and Haskell
- Analyze function purity and side effects
- Measure code complexity (6 comprehensive metric types)
- Detect dead code and unreachable branches
- Track unused variables with scope awareness
- Generate control flow graphs (DOT/D3.js formats)
- Perform taint analysis for security vulnerabilities
- Scan for security issues with CWE identifiers (CWE Top 25 coverage)
- Detect code smells and maintainability issues
- 32 language-agnostic business logic analyzers
- Semantic operation detection via OpKind (DB, HTTP, file, cache, auth, queue, external API)
- 15+ CLI tools for all analysis operations

### Optional (for extended language support)
- **Python 3.9+** for Python adapter
- **Node.js 16+** for JavaScript adapter (future)
- **Go 1.19+** for Go adapter (future)
- **Rust 1.65+** for Rust adapter (future)
- **Ruby 3.0+** for Ruby adapter

## Quick Setup

```bash
# Clone the repository
cd /home/am/Proyectos/Oeditus/metastatic

# Install dependencies
mix deps.get

# Run all tests
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
│       ├── ast.ex                  # Core MetaAST type definitions (3-tuple format)
│       ├── document.ex             # Document wrapper with metadata
│       ├── builder.ex              # High-level API
│       ├── adapter.ex              # Adapter behaviour
│       ├── validator.ex            # Conformance validation
│       ├── adapters/               # 5 language adapters
│       │   ├── python/             # Full Python support
│       │   ├── elixir/             # Full Elixir support
│       │   ├── erlang/             # Full Erlang support
│       │   ├── ruby/               # Full Ruby support
│       │   └── haskell/            # Full Haskell support
│       ├── supplemental/           # Cross-language construct support
│       │   ├── registry.ex         # Supplemental module registry
│       │   ├── transformer.ex      # Transformation helper
│       │   └── python/             # Pykka (actors), Asyncio
│       ├── semantic/               # Semantic metadata systems
│       │   ├── op_kind.ex          # Operation kind metadata (DB, HTTP, file, etc.)
│       │   └── enricher.ex         # Semantic enrichment for AST nodes
│       ├── analysis/               # Complete analysis suite
│       │   ├── purity.ex           # Purity analyzer
│       │   ├── complexity.ex       # Complexity analyzer (6 metrics)
│       │   ├── duplication.ex      # Code duplication detection
│       │   ├── dead_code.ex        # Dead code detection
│       │   ├── unused_variables.ex # Unused variable analysis
│       │   ├── control_flow.ex     # CFG generation
│       │   ├── taint.ex            # Taint analysis
│       │   ├── security.ex         # Security scanning
│       │   ├── smells.ex           # Code smell detection
│       │   └── business_logic/     # 32 language-agnostic analyzers
│       │       ├── callback_hell.ex
│       │       ├── sql_injection.ex
│       │       ├── xss_vulnerability.ex
│       │       └── ... (32 total)
│       └── mix/tasks/              # CLI tools (15+ tasks)
│           ├── metastatic.translate.ex
│           ├── metastatic.inspect.ex
│           ├── metastatic.purity_check.ex
│           ├── metastatic.complexity.ex
│           └── ... (15+ total)
├── test/
│   └── metastatic/                 # 1764 tests (1523 + 241 doctests)
│       ├── ast_test.exs
│       ├── adapters/               # Python, Elixir, Erlang, Ruby, Haskell
│       ├── supplemental/           # Supplemental modules
│       ├── analysis/               # All analyzers
│       └── mix/tasks/              # CLI tools
├── RESEARCH.md                     # Research and architecture
├── THEORETICAL_FOUNDATIONS.md      # Formal theory
├── IMPLEMENTATION_PLAN.md          # Detailed roadmap
├── GETTING_STARTED.md              # Developer guide (this file)
└── README.md                       # Project overview
```

## Development Workflow

### 1. Understanding the Architecture

Before diving in, read these documents in order:

1. **README.md** - High-level overview and current status
2. **RESEARCH.md** - Deep dive into the MetaAST design decisions
3. **THEORETICAL_FOUNDATIONS.md** - Formal meta-modeling theory with proofs
4. **IMPLEMENTATION_PLAN.md** - Roadmap and milestones

### 2. Running Tests

```bash
# Run all tests (1764 tests: 1523 tests + 241 doctests)
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

### Working with MetaAST

MetaAST uses a uniform 3-tuple format: `{type_atom, keyword_meta, children_or_value}`

```elixir
alias Metastatic.{AST, Document, Validator}

# Create a MetaAST manually (3-tuple format)
ast = {:binary_op, [category: :arithmetic, operator: :+], [
  {:variable, [], "x"},
  {:literal, [subtype: :integer], 5}
]}

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

### Using Language Adapters

#### Elixir Adapter

```elixir
alias Metastatic.Adapters.Elixir, as: ElixirAdapter
alias Metastatic.Builder

# Parse Elixir source to MetaAST
source = "x + 5"
{:ok, doc} = Builder.from_source(source, ElixirAdapter)

# doc.ast uses the uniform 3-tuple format:
# {:binary_op, [category: :arithmetic, operator: :+], [
#   {:variable, [], "x"},
#   {:literal, [subtype: :integer], 5}
# ]}

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

# Same MetaAST structure as Elixir (only variable name differs)!
# {:binary_op, [category: :arithmetic, operator: :+], [
#   {:variable, [], "X"},
#   {:literal, [subtype: :integer], 5}
# ]}

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

### Using Advanced Analyzers

Metastatic includes nine core static analysis capabilities:

#### Dead Code Detection

```elixir
alias Metastatic.Analysis.DeadCode

# Detect code after return (3-tuple format)
ast = {:block, [], [
  {:early_return, [], [{:literal, [subtype: :integer], 42}]},
  {:function_call, [name: "print"], [{:literal, [subtype: :string], "hello"}]}  # unreachable!
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

# Track variable usage (3-tuple format)
ast = {:block, [], [
  {:assignment, [], [{:variable, [], "x"}, {:literal, [subtype: :integer], 5}]},
  {:assignment, [], [{:variable, [], "y"}, {:literal, [subtype: :integer], 10}]},
  {:binary_op, [category: :arithmetic, operator: :+], [
    {:variable, [], "y"},
    {:literal, [subtype: :integer], 1}
  ]}
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

# Build CFG (3-tuple format)
ast = {:conditional, [], [
  {:variable, [], "x"},
  {:early_return, [], [{:literal, [subtype: :integer], 1}]},
  {:literal, [subtype: :integer], 2}
]}
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

# Detect taint vulnerabilities (3-tuple format)
ast = {:function_call, [name: "eval"], [
  {:function_call, [name: "input"], []}  # Dangerous: eval(input())
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

# Detect security issues (3-tuple format)
ast = {:assignment, [], [{:variable, [], "password"}, {:literal, [subtype: :string], "admin123"}]}
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

# Detect code smells (3-tuple format)
ast = {:block, [], [
  {:conditional, [], [{:variable, [], "a"}, {:literal, [subtype: :integer], 1}, {:literal, [subtype: :integer], 2}]},
  {:conditional, [], [{:variable, [], "b"}, {:literal, [subtype: :integer], 3}, {:literal, [subtype: :integer], 4}]},
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

### Business Logic Analyzers (32 analyzers)

Metastatic includes 32 language-agnostic business logic analyzers that detect anti-patterns across all supported languages. These include:

**Security (CWE Top 25 coverage):**
- SQLInjection (CWE-89), XSSVulnerability (CWE-79), PathTraversal (CWE-22)
- MissingAuthorization (CWE-862), SSRFVulnerability (CWE-918)
- SensitiveDataExposure (CWE-200), UnrestrictedFileUpload (CWE-434)
- MissingAuthentication (CWE-306), MissingCSRFProtection (CWE-352)
- IncorrectAuthorization (CWE-863), ImproperInputValidation (CWE-20)
- InsecureDirectObjectReference (CWE-639)

**Anti-patterns:**
- CallbackHell, MissingErrorHandling, SilentErrorCase, SwallowingException
- HardcodedValue, NPlusOneQuery, InefficientFilter, UnmanagedTask
- BlockingInPlug, SyncOverAsync, DirectStructUpdate, MissingPreload
- InlineJavascript, MissingThrottle, TOCTOU, and more

```elixir
alias Metastatic.Analysis.Runner
alias Metastatic.Document

# Run all business logic analyzers
ast = {:function_call, [name: "execute"], [
  {:binary_op, [category: :arithmetic, operator: :+], [
    {:literal, [subtype: :string], "SELECT * FROM users WHERE id = "},
    {:variable, [], "user_input"}
  ]}
]}
doc = Document.new(ast, :python)

{:ok, issues} = Runner.run(doc)
# Returns SQLInjection warning about string concatenation in SQL
```

### Adding a New Language Adapter

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
  # 3-tuple format: {type, keyword_meta, children_or_value}
  assert {:binary_op, [category: :arithmetic, operator: :+], [
    {:variable, [], "x"},
    {:literal, [subtype: :integer], 5}
  ]} = meta_ast
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

Welcome aboard!
