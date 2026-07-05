# Elixir Test Fixtures

This directory contains Elixir source code fixtures organized by MetaAST layer.

## Directory Structure

### `core/` - M2.1 Core Layer
Universal constructs present in ALL languages:
- `arithmetic.ex` - Binary and unary arithmetic operations
- `conditionals.ex` - if/unless/case expressions

### `extended/` - M2.2 Extended Layer
Common patterns present in MOST languages:
- `enum_operations.ex` - Enum.map/filter/reduce and comprehensions

### `native/` - M2.3 Native Layer
Elixir-specific constructs:
- `pipe_and_with.ex` - Pipe operator (|>) and with expressions

## Usage

These fixtures serve as:
1. **Examples** for developers learning the adapter
2. **Test data** for round-trip validation
3. **Documentation** of supported constructs

## Testing with Fixtures

```elixir
alias Metastatic.{Builder, Adapters.Elixir}

# Read fixture
source = File.read!("test/fixtures/elixir/core/arithmetic.ex")

# Parse to MetaAST
{:ok, doc} = Builder.from_source(source, Elixir)

# Convert back to source
{:ok, result} = Builder.to_source(doc)

# Validate round-trip (allowing for formatting differences)
assert normalize(source) == normalize(result)
```

## Adding New Fixtures

When adding support for new constructs:
1. Add example code to the appropriate layer directory
2. Include comments explaining the construct
3. Test the round-trip transformation
4. Update this README with the new fixture
