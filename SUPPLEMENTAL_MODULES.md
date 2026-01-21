# Supplemental Modules Guide

This guide explains Metastatic's supplemental module system - a mechanism for extending MetaAST with language-specific library integrations.

## Table of Contents

- [Overview](#overview)
- [Core Concepts](#core-concepts)
- [Architecture](#architecture)
- [Using Supplementals](#using-supplementals)
- [Available Supplementals](#available-supplementals)
- [Creating Supplementals](#creating-supplementals)
- [Best Practices](#best-practices)
- [API Reference](#api-reference)

## Overview

Supplemental modules bridge the gap between MetaAST's language-agnostic representation and real-world library ecosystems. They enable:

- **Cross-language transformations** - Express actor patterns in Python/Erlang/JavaScript
- **Library integrations** - Map MetaAST constructs to third-party APIs (Pykka, asyncio, etc.)
- **Semantic preservation** - Maintain intent while adapting to language-specific idioms

### Example

```elixir
# MetaAST representing an actor call
ast = {:actor_call, {:variable, "worker"}, "process", [data]}

# Transform using Pykka supplemental for Python
{:ok, python_ast} = Metastatic.Supplemental.Transformer.transform(ast, :python)
# Result: {:function_call, "worker.ask", ["process", data]}

# Same AST, different supplemental for Erlang
{:ok, erlang_ast} = Metastatic.Supplemental.Transformer.transform(ast, :erlang)
# Result: {:function_call, "gen_server:call", [worker, {:process, data}]}
```

## Core Concepts

### M2 Layer Extension

Supplementals operate **at the M2 meta-model level**, adding optional constructs beyond Core/Extended/Native:

```
M2 Core    - Universals (literals, variables, operators, conditionals)
M2 Extended - Common patterns (loops, lambdas, collections)
M2 Native  - Language escapes
M2 Supplemental - Library-specific extensions (actors, async, etc.)
```

Supplemental constructs are **not part of the base MetaAST grammar** - they're opt-in extensions that require explicit transformation.

### Semantic Contract

Each supplemental defines:
- **Constructs** - Which MetaAST node types it handles (e.g., `:actor_call`, `:async_await`)
- **Target language** - Single language it generates code for (`:python`, `:javascript`, etc.)
- **Dependencies** - External libraries required (`"pykka >= 3.0"`, `"asyncio"`)
- **Transformation** - How to convert supplemental constructs to concrete code

### Registry System

A centralized GenServer registry maintains all available supplementals, enabling:
- Fast lookup by construct type
- Language compatibility checking
- Conflict detection between competing supplementals
- Runtime registration/deregistration

## Architecture

### Components

```
┌─────────────────────────────────────────────────────────┐
│                  Supplemental System                    │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  ┌──────────────┐     ┌──────────────┐                │
│  │  Behaviour   │────▶│     Info     │                │
│  │   (spec)     │     │  (metadata)  │                │
│  └──────────────┘     └──────────────┘                │
│         │                                               │
│         ▼                                               │
│  ┌─────────────────────────────────────┐              │
│  │         Registry (GenServer)         │              │
│  │  - by_construct index                │              │
│  │  - by_language index                 │              │
│  │  - conflict detection                │              │
│  └─────────────────────────────────────┘              │
│         │                                               │
│         ▼                                               │
│  ┌─────────────────────────────────────┐              │
│  │         Transformer                  │              │
│  │  - lookup + invoke supplementals     │              │
│  │  - error handling                    │              │
│  └─────────────────────────────────────┘              │
│         │                                               │
│         ▼                                               │
│  ┌─────────────────────────────────────┐              │
│  │  Concrete Supplementals              │              │
│  │  - Python.Pykka                      │              │
│  │  - Python.Asyncio                    │              │
│  │  - ... (extensible)                  │              │
│  └─────────────────────────────────────┘              │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

### Data Flow

```
User AST with supplemental constructs
         ↓
   [Validator]
         ↓
  Identify required supplementals
         ↓
   [Registry lookup]
         ↓
   [Transformer]
         ↓
  Invoke supplemental.transform/3
         ↓
  Concrete language AST
```

## Using Supplementals

### Basic Usage

```elixir
alias Metastatic.Supplemental.Transformer

# Single construct transformation
ast = {:actor_call, {:variable, "worker"}, "process", [data]}
{:ok, result} = Transformer.transform(ast, :python)

# Check availability before transforming
if Transformer.available?(:actor_call, :python) do
  {:ok, transformed} = Transformer.transform(ast, :python)
end

# Get all supported constructs for a language
constructs = Transformer.supported_constructs(:python)
# => [:actor_call, :actor_cast, :spawn_actor, :async_await, :async_context, :gather]
```

### With Adapters

Supplementals integrate automatically when using the adapter pipeline:

```elixir
alias Metastatic.Builder

# Source with supplemental constructs
source = """
actor = spawn_actor(Worker, [config])
result = actor_call(actor, "process", [data])
"""

# Adapter automatically uses supplementals during transformation
{:ok, doc} = Builder.from_source(source, :python)

# Round-trip preserves supplemental transformations
{:ok, output} = Builder.to_source(doc)
```

### Configuration

Configure auto-registration in `config/config.exs`:

```elixir
config :metastatic, :supplementals,
  auto_register: [
    Metastatic.Supplemental.Python.Pykka,
    Metastatic.Supplemental.Python.Asyncio
  ]
```

### Validation

Use the validator to detect required supplementals in a document:

```elixir
alias Metastatic.{Document, Supplemental.Validator}

doc = Document.new(ast, :python)
{:ok, analysis} = Validator.validate(doc)

# Check what supplementals are needed
analysis.required_supplementals
# => [:pykka, :asyncio]

# Get warnings about missing supplementals
analysis.warnings
# => ["Document requires supplemental ':pykka' which is not registered"]
```

## Available Supplementals

### Python.Pykka

**Actor model support via Pykka library**

**Constructs:**
- `:actor_call` - Synchronous actor message (ask pattern)
- `:actor_cast` - Asynchronous actor message (tell pattern)
- `:spawn_actor` - Create new actor instance

**Dependencies:** `pykka >= 3.0`

**Example:**

```elixir
# Actor call
{:actor_call, {:variable, "worker"}, "process", [data]}
# Transforms to: worker.ask({'process': data})

# Actor cast
{:actor_cast, {:variable, "worker"}, "log", [message]}
# Transforms to: worker.tell({'log': message})

# Spawn actor
{:spawn_actor, "WorkerActor", [config]}
# Transforms to: WorkerActor.start(config)
```

### Python.Asyncio

**Async/await patterns via asyncio library**

**Constructs:**
- `:async_await` - Async function execution
- `:async_context` - Async context managers
- `:gather` - Parallel task execution

**Dependencies:** `asyncio` (stdlib)

**Example:**

```elixir
# Async await
{:async_operation, :async_await, 
  {:function_call, "fetch_data", [url]}}
# Transforms to: asyncio.run(fetch_data(url))

# Gather
{:async_operation, :gather, [
  {:function_call, "fetch_user", [1]},
  {:function_call, "fetch_posts", [1]}
]}
# Transforms to: asyncio.gather(fetch_user(1), fetch_posts(1))
```

## Creating Supplementals

### Step 1: Implement the Behaviour

```elixir
defmodule MyProject.Supplemental.Python.MyLibrary do
  @behaviour Metastatic.Supplemental
  
  alias Metastatic.Supplemental.Info
  
  @impl true
  def info do
    %Info{
      name: :my_library,
      language: :python,
      constructs: [:my_construct],
      requires: ["my-library >= 1.0"],
      description: "My library integration"
    }
  end
  
  @impl true
  def transform(ast, language, opts)
  
  def transform({:my_construct, args}, :python, _opts) do
    # Transform logic here
    result = {:function_call, "my_library.do_thing", args}
    {:ok, result}
  end
  
  def transform(_ast, :python, _opts) do
    {:error, {:unsupported_construct, "..."}}
  end
  
  def transform(_ast, language, _opts) do
    {:error, {:incompatible_language, "..."}}
  end
end
```

### Step 2: Write Tests

```elixir
defmodule MyProject.Supplemental.Python.MyLibraryTest do
  use ExUnit.Case, async: true
  
  alias MyProject.Supplemental.Python.MyLibrary
  
  describe "info/0" do
    test "returns correct metadata" do
      info = MyLibrary.info()
      assert info.name == :my_library
      assert info.language == :python
    end
  end
  
  describe "transform/3" do
    test "transforms my_construct correctly" do
      ast = {:my_construct, [{:literal, :string, "arg"}]}
      assert {:ok, result} = MyLibrary.transform(ast, :python)
      assert result == {:function_call, "my_library.do_thing", 
                        [{:literal, :string, "arg"}]}
    end
    
    test "returns error for wrong language" do
      ast = {:my_construct, []}
      assert {:error, {:incompatible_language, _}} = 
               MyLibrary.transform(ast, :javascript)
    end
  end
end
```

### Step 3: Register

```elixir
# Manual registration
alias Metastatic.Supplemental.Registry

{:ok, _} = Registry.register(MyProject.Supplemental.Python.MyLibrary)

# Or via config (auto-registers on startup)
config :metastatic, :supplementals,
  auto_register: [MyProject.Supplemental.Python.MyLibrary]
```

### Step 4: Document

Add module documentation with:
- Clear description of what library/pattern it supports
- List of all constructs handled
- Examples showing MetaAST input and output
- Dependency requirements
- Any caveats or limitations

## Best Practices

### Design Guidelines

1. **Single Responsibility** - One supplemental per library/pattern
2. **Explicit Constructs** - Use distinct construct atoms (`:actor_call` not `:call`)
3. **Language Specific** - Target exactly one language per supplemental
4. **Idiomatic Output** - Generate natural, idiomatic code for target language
5. **Comprehensive Tests** - Test all constructs, error cases, edge cases

### Naming Conventions

**Modules:**
```
Metastatic.Supplemental.<Language>.<Library>
  ├── Python.Pykka       (library name)
  ├── Python.Asyncio     (pattern name)
  └── JavaScript.RxJS    (library name)
```

**Construct atoms:**
```
:actor_call          (prefixed by domain)
:async_await         (verb describing action)
:spawn_actor         (specific, unambiguous)
```

**Info names:**
```
name: :pykka         (short, lowercase atom)
name: :asyncio       (match library name)
```

### Error Handling

Return specific errors for different failure modes:

```elixir
# Unsupported construct
{:error, {:unsupported_construct, "Pykka does not support: #{inspect(ast)}"}}

# Wrong language
{:error, {:incompatible_language, "Pykka only supports Python, got: #{language}"}}

# Invalid options
{:error, {:invalid_options, "Unknown option: #{inspect(key)}"}}
```

### Version Constraints

Use semantic versioning in `requires`:

```elixir
requires: [
  "pykka >= 3.0, < 4.0",  # Major version constraint
  "asyncio",               # Stdlib, no version needed
  "aiohttp >= 3.8"         # Minimum version only
]
```

### Testing Strategy

Cover these scenarios:

1. **Info validation** - Correct metadata structure
2. **Happy path** - Each construct transforms correctly
3. **Error cases** - Wrong language, unsupported constructs
4. **Edge cases** - Empty arguments, nested structures, complex types
5. **Options** - Handle all option variations
6. **Idempotency** - Multiple transformations don't break

### Performance Considerations

- Keep transformations fast (<1ms per node)
- Avoid heavy computation in `info/0` (called frequently)
- Use pattern matching for dispatch (faster than conditionals)
- Don't validate AST structure (adapters already do this)

## API Reference

### Behaviour Callbacks

**`info/0`**

Returns metadata about the supplemental.

```elixir
@callback info() :: Info.t()
```

**`transform/3`**

Transforms a supplemental construct to target language AST.

```elixir
@callback transform(
  ast :: AST.meta_ast(),
  language :: atom(),
  opts :: map()
) :: {:ok, AST.meta_ast()} | {:error, term()}
```

### Registry Functions

**`register/1`**

Register a supplemental module.

```elixir
Registry.register(MySupplemental)
# => {:ok, :pykka} | {:error, {:already_registered, :pykka}}
```

**`lookup/2`**

Find supplemental for construct and language.

```elixir
Registry.lookup(:actor_call, :python)
# => {:ok, Metastatic.Supplemental.Python.Pykka} | 
#    {:error, :not_found}
```

**`all/0`**

List all registered supplementals.

```elixir
Registry.all()
# => [Metastatic.Supplemental.Python.Pykka, ...]
```

### Transformer Functions

**`transform/3`**

Transform a construct using registered supplementals.

```elixir
Transformer.transform(ast, :python)
# => {:ok, transformed_ast} | {:error, reason}
```

**`available?/2`**

Check if a construct is supported for a language.

```elixir
Transformer.available?(:actor_call, :python)
# => true | false
```

**`supported_constructs/1`**

Get all supported constructs for a language.

```elixir
Transformer.supported_constructs(:python)
# => [:actor_call, :actor_cast, :spawn_actor, ...]
```

### Validator Functions

**`validate/1`**

Analyze a document to detect required supplementals.

```elixir
Validator.validate(document)
# => {:ok, %{required_supplementals: [...], warnings: [...]}}
```

## Advanced Topics

### Conflict Resolution

When multiple supplementals claim the same construct+language:

```elixir
# Registry detects conflicts
Registry.register(AlternativePykka)
# => {:error, {:conflict, existing: Pykka, new: AlternativePykka}}

# Unregister old, register new
Registry.unregister(Pykka)
Registry.register(AlternativePykka)
```

### Chaining Transformations

Supplementals can compose:

```elixir
# First supplemental adds intermediate construct
{:ok, ast1} = Supplemental1.transform(input, :python)

# Second supplemental further transforms
{:ok, ast2} = Supplemental2.transform(ast1, :python)
```

### Stateful Transformations

Pass state via options:

```elixir
opts = %{
  actor_prefix: "my_app",
  async_mode: :gather
}

Transformer.transform(ast, :python, opts)
```

### Testing with Fixtures

Create test fixtures for complex scenarios:

```python
# test/fixtures/python/supplemental/pykka_actors.py
class Worker(pykka.ThreadingActor):
    def process(self, data):
        return data * 2

worker = Worker.start()
result = worker.ask({'process': 42})
```

## Contributing

Want to add a supplemental?

Use the generator to scaffold a new supplemental:

```bash
mix metastatic.gen.supplemental Python MyLibrary
```

## Future Work

Planned supplementals:

- **Python.Celery** - Distributed task queue
- **JavaScript.RxJS** - Reactive programming
- **Ruby.Concurrent** - Concurrency primitives
- **Go.Channels** - CSP-style communication
- **Rust.Tokio** - Async runtime

