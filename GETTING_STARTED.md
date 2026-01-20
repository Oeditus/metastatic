# Getting Started with Metastatic Development

Welcome to Metastatic! This guide will help you get up and running with the development environment.

## Prerequisites

### Required
- **Elixir 1.19+** and **Erlang/OTP 27+**
- **Git** for version control

### Phase 1 Complete!
Phase 1 (Core Foundation) is complete with 99 passing tests. Language adapters (Python, JavaScript, etc.) coming in Phase 2.

### Optional (for future adapter development)
- **Python 3.9+** (Phase 2 - Python adapter)
- **Node.js 16+** (Phase 3 - JavaScript adapter)
- **Go 1.19+** (Phase 5 - Go adapter)
- **Rust 1.65+** (Phase 5 - Rust adapter)
- **Ruby 3.0+** (Phase 5 - Ruby adapter)

## Quick Setup

```bash
# Clone the repository
cd /home/am/Proyectos/Oeditus/metastatic

# Install dependencies
mix deps.get

# Run tests (99 tests, all passing!)
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
│       ├── adapters/               # 🚧 Phase 2 - Coming soon!
│       │   ├── python.ex           # (Planned)
│       │   ├── javascript.ex       # (Planned)
│       │   └── elixir.ex           # (Planned)
│       ├── mutator.ex              # 🚧 Phase 3 - Mutation engine
│       └── purity_analyzer.ex      # 🚧 Phase 3 - Side effect detection
├── test/
│   └── metastatic/                 # ✅ 99 tests, 100% passing
│       ├── ast_test.exs            # ✅ 332 lines
│       ├── document_test.exs       # ✅ 94 lines
│       └── validator_test.exs      # ✅ 274 lines
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
# Run all tests (99 tests, all passing!)
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

### Adding a New Language Adapter (Phase 2+)

Language adapters are coming in Phase 2. See IMPLEMENTATION_PLAN.md for the roadmap.

### Adding a New Mutator

1. **Create mutator module**: `lib/metastatic/mutators/my_mutator.ex`
2. **Implement mutation logic**: Use `Macro.postwalk/2`
3. **Add tests**: Test on multiple languages
4. **Document**: Include examples

### Adding Test Fixtures

```bash
# Create fixture directory
mkdir -p test/fixtures/python/

# Add source file
echo 'def add(x, y): return x + y' > test/fixtures/python/simple_add.py

# Add expected MetaAST
cat > test/fixtures/python/expected/simple_add.exs << 'EOF'
{:function_def, "add",
  params: [
    {:param, "x", nil},
    {:param, "y", nil}
  ],
  body: {:return, {:binary_op, :arithmetic, :+, {:variable, "x"}, {:variable, "y"}}}
}
EOF
```

## Testing Philosophy

### Unit Tests
Test individual transformations and functions:

```elixir
test "transforms Python addition to MetaAST" do
  python_ast = %{"_type" => "BinOp", "op" => "Add", ...}
  {:ok, meta_ast} = Python.to_meta(python_ast)
  assert {:binary_op, :arithmetic, :+, _, _} = meta_ast
end
```

### Integration Tests
Test full round-trips:

```elixir
test "round-trip Python source through MetaAST" do
  source = "x = 1 + 2"
  {:ok, doc} = Builder.from_source(source, :python)
  {:ok, result} = Builder.to_source(doc)
  # Allow for formatting differences
  assert normalize(result) == normalize(source)
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
iex> source = "x = 1 + 2"
iex> {:ok, doc} = Metastatic.Builder.from_source(source, :python)
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

### Debugging External Parsers

```bash
# Test Python parser directly
echo 'x = 1 + 2' | python3 parsers/python/parser.py | jq .

# Test JavaScript parser directly
echo 'const x = 1 + 2' | node parsers/javascript/parser.js | jq .
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
:fprof.apply(&Metastatic.Builder.from_source/2, [source, :python])
:fprof.profile()
:fprof.analyse()
```

### Benchmarking

```elixir
# Use Benchee for benchmarking
Benchee.run(%{
  "parse python" => fn -> Metastatic.Builder.from_source(source, :python) end,
  "parse javascript" => fn -> Metastatic.Builder.from_source(source, :javascript) end
})
```

## Troubleshooting

### Common Issues

**Issue: Python parser not found**
```
Error: Python parser failed: python3: command not found
```
**Solution:** Install Python 3.9+ or configure Python path in config

**Issue: Jason decode error**
```
Error: Jason.decode failed
```
**Solution:** Check that external parser outputs valid JSON

**Issue: Tests failing after rebase**
```
Error: test/fixtures/python/... failed
```
**Solution:** Regenerate expected outputs with `mix metastatic.fixtures.update`

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
