# Test Fixtures

This directory contains test fixtures for validating language adapters.

## Structure

```
fixtures/
├── python/
│   ├── simple_arithmetic.py
│   ├── complex_function.py
│   └── expected/
│       ├── simple_arithmetic.exs  # Expected MetaAST
│       └── complex_function.exs
├── javascript/
│   └── ...
└── elixir/
    └── ...
```

## Usage

Fixtures are automatically loaded by the `FixtureHelper` module:

```elixir
# Load all fixtures for a language
fixtures = Metastatic.Test.FixtureHelper.load_language(:python)

# Load a specific fixture
{:ok, fixture} = Metastatic.Test.FixtureHelper.load_fixture(:python, "simple_arithmetic")

# The fixture contains:
# - name: "simple_arithmetic"
# - source: the actual source code
# - expected_ast: the expected MetaAST (if expected/*.exs exists)
# - language: :python
```

## Adding Fixtures

To add a new fixture:

1. Create the source file in the appropriate language directory
2. Optionally create the expected MetaAST in the `expected/` subdirectory

Example:

```bash
# Create Python fixture
echo "x = 1 + 2" > test/fixtures/python/variable_assignment.py

# Create expected AST (optional)
cat > test/fixtures/python/expected/variable_assignment.exs << 'EOF'
{:block, [
  {:binary_op, :arithmetic, :+,
    {:literal, :integer, 1},
    {:literal, :integer, 2}}
]}
EOF
```

## Testing with Fixtures

```elixir
test "adapter parses simple arithmetic correctly" do
  {:ok, fixture} = FixtureHelper.load_fixture(:python, "simple_arithmetic")
  
  # Parse with adapter
  {:ok, doc} = Builder.from_source(fixture.source, :python)
  
  # Validate against expected AST
  assert FixtureHelper.validate_fixture(fixture, doc.ast) == :ok
end
```

## Conventions

- Source files should use the standard extension for their language
- Expected AST files should be valid Elixir terms
- Keep fixtures simple and focused on specific language features
- Document non-obvious test cases
