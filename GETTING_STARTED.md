# Getting Started with Metastatic Development

Welcome to Metastatic! This guide will help you get up and running with the development environment.

## Prerequisites

### Required
- **Elixir 1.19+** and **Erlang/OTP 27+**
- **Git** for version control

### Current Status
**Phase 2 Complete!** Both Elixir and Erlang adapters are fully functional with 253 passing tests.

- Phase 1: Core Foundation (154 tests)
- Phase 2: BEAM Ecosystem Adapters - Elixir (66 tests) + Erlang (33 tests)

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

# Run tests (253 tests, all passing!)
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
│       ├── ast.ex                  # ✅ Core MetaAST type definitions (551 lines)
│       ├── document.ex             # ✅ Document wrapper with metadata (197 lines)
│       ├── builder.ex              # ✅ High-level API (278 lines)
│       ├── adapter.ex              # ✅ Adapter behaviour (422 lines)
│       ├── validator.ex            # ✅ Conformance validation (333 lines)
│       ├── adapters/               # ✅ Phase 2 - BEAM Adapters Complete!
│       │   ├── elixir.ex           # ✅ (154 lines, 66 tests)
│       │   ├── elixir/
│       │   │   ├── to_meta.ex      # ✅ M1→M2 (412 lines)
│       │   │   └── from_meta.ex    # ✅ M2→M1 (296 lines)
│       │   ├── erlang.ex           # ✅ (154 lines, 33 tests)
│       │   ├── erlang/
│       │   │   ├── to_meta.ex      # ✅ M1→M2 (307 lines)
│       │   │   └── from_meta.ex    # ✅ M2→M1 (270 lines)
│       │   ├── python.ex           # 🚧 Phase 3 - Planned
│       │   └── javascript.ex       # 🚧 Phase 4 - Planned
│       ├── mutator.ex              # 🚧 Phase 3 - Mutation engine
│       └── purity_analyzer.ex      # 🚧 Phase 3 - Side effect detection
├── test/
│   └── metastatic/                 # ✅ 253 tests, 100% passing
│       ├── ast_test.exs            # ✅ Phase 1 (332 lines)
│       ├── document_test.exs       # ✅ Phase 1 (94 lines)
│       ├── validator_test.exs      # ✅ Phase 1 (274 lines)
│       └── adapters/               # ✅ Phase 2
│           ├── elixir_test.exs     # ✅ (444 lines, 66 tests)
│           └── erlang_test.exs     # ✅ (242 lines, 33 tests)
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
# Run all tests (253 tests, all passing!)
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

#### Cross-Language Equivalence

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
