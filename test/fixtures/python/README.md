# Python Test Fixtures

This directory contains Python source code fixtures for testing the Python adapter's transformation capabilities across all MetaAST layers.

## Structure

```
python/
├── core/               # M2.1 Core Layer constructs
├── extended/           # M2.2 Extended Layer constructs
├── native/             # M2.3 Native Layer (language-specific) constructs
└── README.md           # This file
```

## Core Layer Fixtures (M2.1)

Universal constructs present in ALL languages:

- **arithmetic.py** - Arithmetic operations (+, -, *, /, //, %, **)
- **comparisons.py** - Comparison operations (==, !=, <, <=, >, >=, is, is not)
- **boolean_logic.py** - Boolean operations (and, or, not)
- **function_calls.py** - Function and method calls
- **conditionals.py** - If statements and ternary expressions
- **blocks.py** - Statement blocks and sequences

## Extended Layer Fixtures (M2.2)

Common patterns present in MOST languages:

- **loops.py** - While and for loops
- **lambdas.py** - Lambda expressions
- **comprehensions.py** - List/dict/set comprehensions, generator expressions
- **exception_handling.py** - Try-except-finally blocks
- **builtin_functions.py** - Built-in collection operations (map, filter, etc.)

## Native Layer Fixtures (M2.3)

Python-specific constructs preserved as `{:language_specific, :python, ...}`:

- **decorators.py** - Function and class decorators
- **context_managers.py** - With statements
- **generators.py** - Yield and yield from
- **classes.py** - Class definitions with inheritance
- **async_await.py** - Async functions, await, async for, async with
- **imports.py** - Import and from-import statements

## Usage

### In Tests

```elixir
# Parse a fixture file
{:ok, source} = File.read("test/fixtures/python/core/arithmetic.py")
{:ok, ast} = Python.parse(source)
{:ok, meta_ast, _} = Python.to_meta(ast)

# Validate transformation
assert {:binary_op, :arithmetic, _, _, _} = meta_ast
```

### Round-Trip Testing

```elixir
test "round-trip arithmetic fixture" do
  fixture = "test/fixtures/python/core/arithmetic.py"
  {:ok, source} = File.read(fixture)
  
  {:ok, doc} = Builder.from_source(source, PythonAdapter)
  {:ok, result} = Builder.to_source(doc)
  
  # Verify fidelity (allowing for formatting differences)
  assert semantic_equivalence?(source, result)
end
```

### Cross-Language Validation

```elixir
test "Python and Elixir produce equivalent MetaAST" do
  python_fixture = "test/fixtures/python/core/arithmetic.py"
  elixir_fixture = "test/fixtures/elixir/core/arithmetic.ex"
  
  {:ok, py_doc} = Builder.from_source(File.read!(python_fixture), PythonAdapter)
  {:ok, ex_doc} = Builder.from_source(File.read!(elixir_fixture), ElixirAdapter)
  
  # Both should produce same MetaAST structure
  assert same_structure?(py_doc.ast, ex_doc.ast)
end
```

## Adding New Fixtures

When adding new fixture files:

1. **Choose the appropriate layer** - Core, Extended, or Native
2. **Create descriptive filename** - e.g., `pattern_matching.py`
3. **Add doc comment** - Explain what the fixture demonstrates
4. **Include varied examples** - Cover edge cases and common patterns
5. **Keep code simple** - Focus on the construct being demonstrated
6. **Add corresponding tests** - Validate the fixture transforms correctly

Example fixture template:

```python
"""
Layer: Fixture Name

Brief description of what this fixture demonstrates.
"""

# Example 1: Simple case
simple_example()

# Example 2: Complex case
complex_example(arg1, arg2)

# Example 3: Edge case
edge_case()
```

## Validation Criteria

Fixtures should meet these criteria:

- **Parseable** - Valid Python syntax that ast.parse() can handle
- **Focused** - Each fixture demonstrates one category of constructs
- **Comprehensive** - Cover common cases and edge cases
- **Documented** - Include comments explaining non-obvious examples
- **Tested** - Have corresponding test cases

## Layer Assignment Guidelines

**Core (M2.1)** - Can be directly expressed in Python, JavaScript, Elixir, Erlang, Ruby, Go:
- Basic arithmetic and comparison
- Boolean logic
- Function calls
- Simple conditionals
- Variable references

**Extended (M2.2)** - Present in most languages with minor variations:
- Loops (while/for)
- Lambdas/anonymous functions
- Exception handling
- Collection operations (map/filter/reduce)

**Native (M2.3)** - Python-specific features:
- Decorators
- Context managers (with statement)
- Generators (yield)
- Async/await
- Class definitions with Python-specific features
- Import statements
- Comprehensions with complex filters

## Notes

- Fixtures use actual Python syntax, not pseudo-code
- Some constructs may transform to `{:language_specific, ...}` even in Extended layer (e.g., complex comprehensions)
- Round-trip fidelity may not be 100% due to formatting differences, but semantic equivalence should be preserved
- Fixtures are not executable programs - they demonstrate isolated constructs
