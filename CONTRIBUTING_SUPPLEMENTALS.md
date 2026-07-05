# Contributing Supplemental Modules

This guide explains how to create and contribute supplemental modules to Metastatic.

## What Are Supplemental Modules?

Supplemental modules bridge the gap between languages when certain MetaAST constructs aren't natively supported. They map MetaAST constructs to library-specific implementations.

For example, Python doesn't have native actor model support, but the Pykka supplemental allows actor-based constructs from Elixir to be translated to Python using the Pykka library.

## When to Create a Supplemental

Create a supplemental module when:

1. A MetaAST construct (like `:actor_call`) has no native equivalent in your target language
2. A well-established library provides the missing functionality
3. The library has stable APIs and good adoption
4. The transformation can be automated reliably

Don't create supplementals for:

- Core language features (those belong in adapters)
- Experimental or unstable libraries
- Language-specific idioms that don't translate conceptually

## Quick Start

### 1. Generate the Scaffold

```bash
mix metastatic.gen.supplemental LANGUAGE.LIBRARY_NAME \
  --language LANGUAGE \
  --constructs construct1,construct2 \
  --library library_name \
  --library-version ">=X.Y.Z"
```

Example:

```bash
mix metastatic.gen.supplemental python.requests \
  --language python \
  --constructs http_get,http_post \
  --library requests \
  --library-version ">=2.28.0"
```

This creates:
- `lib/metastatic/supplemental/python/requests.ex`
- `test/metastatic/supplemental/python/requests_test.exs`

### 2. Implement Transform Functions

Edit the generated module and implement the `transform/3` functions for each construct:

```elixir
@impl Metastatic.Supplemental
def transform({:http_get, url}, :from_meta, _opts) do
  # MetaAST → Target language
  # Transform the construct into the target language's native AST
  python_ast = {:function_call, 
    {:attribute_access, {:variable, "requests"}, "get"},
    [url]
  }
  
  {:ok, python_ast}
end

def transform(python_ast, :to_meta, _opts) do
  # Target language → MetaAST
  # Transform the library call back to MetaAST construct
  case python_ast do
    {:function_call, {:attribute_access, {:variable, "requests"}, "get"}, [url]} ->
      {:ok, {:http_get, url}}
    
    _ ->
      {:error, :not_supported}
  end
end
```

### 3. Write Tests

Add comprehensive tests in the test file:

```elixir
describe "transform/3 for :http_get" do
  test "transforms from MetaAST to Python requests call" do
    ast = {:http_get, {:literal, :string, "https://api.example.com"}}
    
    assert {:ok, result} = Requests.transform(ast, :from_meta, [])
    assert match?({:function_call, _, _}, result)
  end
  
  test "round-trips correctly" do
    original = {:http_get, {:literal, :string, "https://api.example.com"}}
    
    {:ok, python_ast} = Requests.transform(original, :from_meta, [])
    {:ok, meta_ast} = Requests.transform(python_ast, :to_meta, [])
    
    assert meta_ast == original
  end
end
```

### 4. Register the Module

Add to `config/config.exs`:

```elixir
config :metastatic,
  supplemental_modules: [
    Metastatic.Supplemental.Python.Requests,
    # ... other modules
  ]
```

### 5. Document Usage

Update your module's `@moduledoc` with:

- Clear examples of the transformations
- Library installation instructions
- Any limitations or edge cases
- Performance considerations

### 6. Run Tests

```bash
mix test test/metastatic/supplemental/python/requests_test.exs
```

## Best Practices

### Naming Conventions

- Module: `Metastatic.Supplemental.{Language}.{LibraryName}`
- File: `lib/metastatic/supplemental/{language}/{library_name}.ex`
- Use PascalCase for module names, snake_case for files

### Info Structure

Provide accurate metadata:

```elixir
def info do
  %Info{
    target_language: :python,  # Symbol for the target language
    constructs: [:http_get, :http_post],  # List of supported constructs
    dependencies: %{
      "requests" => ">=2.28.0"  # Map of library dependencies
    }
  }
end
```

### Error Handling

Return appropriate errors:

```elixir
def transform(ast, direction, opts) do
  case ast do
    {:supported_construct, _} -> 
      {:ok, transformed}
    
    {:unsupported_construct, _} ->
      {:error, :construct_not_supported}
    
    malformed ->
      {:error, {:invalid_ast, malformed}}
  end
end
```

### Documentation

Every public function needs:

- `@doc` with clear description
- `@spec` with type specifications
- Examples in doctests
- Edge cases documented

Example:

```elixir
@doc """
Transforms HTTP GET requests between MetaAST and Python requests library.

## Examples

    iex> ast = {:http_get, {:literal, :string, "https://example.com"}}
    iex> Requests.transform(ast, :from_meta, [])
    {:ok, {:function_call, ...}}

## Notes

- URLs must be string literals or variables
- Query parameters should be pre-encoded
- Returns error for invalid URL formats
"""
@spec transform(term(), :from_meta | :to_meta, keyword()) :: 
  {:ok, term()} | {:error, term()}
def transform(ast, direction, opts)
```

### Testing Requirements

Your tests must include:

1. Basic transformation tests (MetaAST → Target, Target → MetaAST)
2. Round-trip tests (MetaAST → Target → MetaAST)
3. Edge cases and error conditions
4. Performance tests for complex transformations
5. Integration tests with real library usage (if applicable)

Aim for:
- 90%+ code coverage
- All constructs tested
- All error paths tested

### Performance Guidelines

- Transformations should be O(n) where n is AST size
- Avoid external calls during transformation
- Cache library metadata if needed
- Target <1ms per node transformation

## Code Review Checklist

Before submitting a pull request, ensure:

- [ ] Generated with `mix metastatic.gen.supplemental`
- [ ] All `transform/3` functions implemented
- [ ] `info/0` returns correct metadata
- [ ] Tests written and passing (run `mix test`)
- [ ] Code formatted (run `mix format`)
- [ ] Documentation complete with examples
- [ ] Round-trip fidelity tested
- [ ] Registered in config
- [ ] No compiler warnings
- [ ] Follows existing code style

## Construct Naming

When creating new constructs:

1. Use descriptive, language-agnostic names
   - Good: `:http_get`, `:actor_call`, `:async_await`
   - Bad: `:fetch`, `:server_ask`, `:promise_then`

2. Check for existing similar constructs first
3. Document the semantic meaning clearly
4. Ensure it's not a language-specific idiom

## Common Pitfalls

### 1. Over-abstraction

Don't try to abstract everything. Some language features are fundamentally incompatible.

Bad:
```elixir
# Trying to map Rust ownership to Python
{:rust_borrow, variable}  # This makes no sense in Python
```

Good:
```elixir
# Clear semantic concept that translates
{:actor_call, server, message, timeout}
```

### 2. Tight Coupling

Don't couple to specific library versions or implementations.

Bad:
```elixir
def transform({:actor_call, _}, :from_meta, _) do
  # Hardcoded to Pykka 3.0 specific behavior
  {:ok, {:method_call, "ask_v3", []}}
end
```

Good:
```elixir
def transform({:actor_call, server, msg, timeout}, :from_meta, _) do
  # Works with Pykka 2.x and 3.x
  {:ok, {:method_call, {:variable, server}, "ask", [msg, timeout]}}
end
```

### 3. Insufficient Testing

Always test edge cases:

```elixir
test "handles nil timeout in actor_call" do
  ast = {:actor_call, {:variable, "server"}, {:literal, :atom, :get}, nil}
  assert {:ok, _} = transform(ast, :from_meta, [])
end

test "rejects invalid message types" do
  ast = {:actor_call, "server", 123, nil}
  assert {:error, _} = transform(ast, :from_meta, [])
end
```

## Directory Structure

Your supplemental should follow this structure:

```
lib/metastatic/supplemental/
  python/
    pykka.ex         # Actor model support
    asyncio.ex       # Async support
    requests.ex      # Your new module
  javascript/
    nact.ex
  ruby/
    httparty.ex

test/metastatic/supplemental/
  python/
    pykka_test.exs
    asyncio_test.exs
    requests_test.exs
  javascript/
    nact_test.exs
  ruby/
    httparty_test.exs
```

## Examples

See existing supplementals for reference:

- `lib/metastatic/supplemental/python/pykka.ex` - Actor model (complex)
- `lib/metastatic/supplemental/python/asyncio.ex` - Async patterns (medium)

## Getting Help

- Read `SUPPLEMENTAL_MODULES.md` for detailed architecture
- Check existing supplementals for patterns
- Open a GitHub issue for design questions
- Join our community discussions

## Submission Process

1. Fork the repository
2. Create a feature branch: `git checkout -b supplemental/python-requests`
3. Implement your supplemental
4. Run full test suite: `mix test`
5. Format code: `mix format`
6. Commit with clear message: `git commit -m "Add Python requests supplemental"`
7. Push and open a pull request
8. Respond to code review feedback

## License

By contributing, you agree that your contributions will be licensed under the same license as the Metastatic project.

## Questions?

Open an issue on GitHub or reach out to the maintainers. We're happy to help!
