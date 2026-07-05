<img src="https://raw.githubusercontent.com/Oeditus/metastatic/v0.13.0/stuff/img/logo-128x128.png" alt="Metastatic" width="128" align="right">

# Metastatic

**Cross-language code meta-model library using unified MetaAST representation**

Metastatic provides a unified MetaAST (Meta-level Abstract Syntax Tree) intermediate representation for parsing, transforming, and translating code across multiple programming languages using a three-layer meta-model architecture.

## Vision

Parse once, use everywhere. A universal meta-model for program syntax that enables cross-language code transformation and tooling.

**Metastatic provides the foundation** - the MetaAST meta-model and language adapters. Analysis tools are provided by the companion library [MetaCredo](https://github.com/Oeditus/metacredo).

## Key Features

- **Layered Architecture**: Three-layer MetaAST design (M2.1 Core, M2.2 Extended, M2.3 Native)
- **Language Adapters**: Bidirectional M1 ↔ M2 transformations for multiple languages
- **Round-Trip Fidelity**: Transform source → MetaAST → source with >90% accuracy
- **Meta-Model Foundation**: MOF-based meta-modeling (M2 level) for universal AST representation
- **Cross-Language Equivalence**: Semantically equivalent code produces identical MetaAST across languages
- **Semantic Enrichment**: OpKind metadata system for accurate operation detection (DB, HTTP, file, cache, auth, queue, external API)

## Scope

**What Metastatic Provides:**
- MetaAST meta-model (M2 level) with three layers
- Language adapters (Python, Elixir, Erlang, Ruby, Haskell)
- Parsing, transformation, and unparsing infrastructure
- Cross-language semantic equivalence validation
- Semantic enrichment (OpKind metadata)

**What Metastatic Does NOT Provide:**
- Static analysis (see [MetaCredo](https://github.com/Oeditus/metacredo))

Metastatic is a **foundation library** that other tools build upon.

## Quick Start

### CLI Tools

Metastatic provides command-line tools for cross-language translation, AST inspection, and equivalence validation:

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

# Check semantic equivalence
mix metastatic.validate_equivalence hello.py hello.ex

# Show detailed differences
mix metastatic.validate_equivalence --verbose file1.py file2.ex
```

### Using Language Adapters

Metastatic currently supports 5 language adapters: Python, Elixir, Erlang, Ruby, and Haskell.

#### Elixir & Erlang

```elixir
alias Metastatic.Adapters.{Elixir, Erlang}
alias Metastatic.{Adapter, Document}

# Parse Elixir source code
{:ok, doc} = Adapter.abstract(Elixir, "x + 5", :elixir)
doc.ast  # => {:binary_op, [category: :arithmetic, operator: :+], 
         #      [{:variable, [], "x"}, {:literal, [subtype: :integer], 5}]}

# Parse Erlang source code
{:ok, doc} = Adapter.abstract(Erlang, "X + 5.", :erlang)
doc.ast  # => {:binary_op, [category: :arithmetic, operator: :+], 
         #      [{:variable, [], "X"}, {:literal, [subtype: :integer], 5}]}

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

#### Python

```elixir
alias Metastatic.Adapters.Python

# Parse Python arithmetic
{:ok, doc} = Adapter.abstract(Python, "x + 5", :python)
doc.ast  # => {:binary_op, [category: :arithmetic, operator: :+], 
         #      [{:variable, [], "x"}, {:literal, [subtype: :integer], 5}]}

# Parse Python class
source = """
class Calculator:
    def __init__(self, value=0):
        self.value = value
    
    def add(self, x):
        self.value += x
        return self
"""
{:ok, doc} = Adapter.abstract(Python, source, :python)
# doc.ast contains {:language_specific, :python, ...} for class definition
```

#### Ruby

```elixir
alias Metastatic.Adapters.Ruby

# Parse Ruby code
{:ok, doc} = Adapter.abstract(Ruby, "x + 5", :ruby)
doc.ast  # => {:binary_op, [category: :arithmetic, operator: :+], 
         #      [{:variable, [], "x"}, {:literal, [subtype: :integer], 5}]}

# Parse Ruby class with method chaining
source = """
class Calculator
  attr_reader :value
  
  def initialize(initial = 0)
    @value = initial
  end
  
  def add(x)
    @value += x
    self
  end
end
"""
{:ok, doc} = Adapter.abstract(Ruby, source, :ruby)
# doc.ast contains {:language_specific, :ruby, ...} for class definition
```

#### Haskell

```elixir
alias Metastatic.Adapters.Haskell

# Parse Haskell arithmetic
{:ok, doc} = Adapter.abstract(Haskell, "x + 5", :haskell)
doc.ast  # => {:binary_op, [category: :arithmetic, operator: :+], 
         #      [{:variable, [], "x"}, {:literal, [subtype: :integer], 5}]}

# Parse Haskell function with type signature
source = """
factorial :: Int -> Int
factorial 0 = 1
factorial n = n * factorial (n - 1)
"""
{:ok, doc} = Adapter.abstract(Haskell, source, :haskell)
# doc.ast contains {:language_specific, :haskell, ...} for type signature and function

# Parse data type definition
source = "data Maybe a = Nothing | Just a"
{:ok, doc} = Adapter.abstract(Haskell, source, :haskell)
# doc.ast contains {:language_specific, :haskell, ...} for algebraic data type
```

### Working with MetaAST Directly

```elixir
alias Metastatic.{AST, Document, Validator}

# Create a MetaAST document (uniform 3-tuple format)
ast = {:binary_op, [category: :arithmetic, operator: :+], 
       [{:variable, [], "x"}, {:literal, [subtype: :integer], 5}]}
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

### AST Traversal & Manipulation

MetaAST trees need to be walked, searched, and transformed -- for refactoring,
linting, or building new cross-language tools. Metastatic provides a
full set of traversal and manipulation functions that mirror Elixir's `Macro` module,
adapted for the MetaAST 3-tuple format. All are available both on `Metastatic.AST`
(canonical) and as convenience wrappers on the `Metastatic` module itself.

#### Why traversal matters

Unlike Elixir's native AST, MetaAST nodes come from many languages. A single
traversal API means you write a variable renamer or a refactoring tool *once*
and it works on Python, Ruby, Erlang, Haskell, and Elixir code.

#### Walking the tree

```elixir
alias Metastatic.AST

{:ok, ast} = Metastatic.quote("x + y * 2", :python)

# Transform-only walk (no accumulator) -- like Macro.postwalk/2
new_ast = Metastatic.postwalk(ast, fn
  {:variable, meta, name} -> {:variable, meta, String.upcase(name)}
  node -> node
end)

# Walk with accumulator -- like Macro.prewalk/3
{_ast, var_names} = Metastatic.prewalk(ast, [], fn
  {:variable, _, name} = node, acc -> {node, [name | acc]}
  node, acc -> {node, acc}
end)
# var_names => ["y", "x"]

# Full pre+post traverse -- like Macro.traverse/4
{_ast, count} = Metastatic.traverse(ast, 0,
  fn node, acc -> {node, acc + 1} end,   # pre
  fn node, acc -> {node, acc} end         # post
)
```

#### Lazy enumeration

```elixir
# Stream all nodes depth-first -- like Macro.prewalker/1
ast |> Metastatic.prewalker() |> Enum.filter(&AST.operator?/1)

# Post-order stream -- like Macro.postwalker/1
ast |> Metastatic.postwalker() |> Enum.count()
```

#### Finding nodes

```elixir
# Path from a matching node up to the root -- like Macro.path/2
path = Metastatic.path(ast, fn
  {:literal, _, 42} -> true
  _ -> false
end)
# => [{:literal, ...42}, {:binary_op, ...}, ...root]
```

#### Pipe utilities

```elixir
# Decompose pipe chains -- like Macro.unpipe/1
steps = Metastatic.unpipe(pipe_ast)
# => [{initial_expr, 0}, {call1, 0}, {call2, 0}]

# Inject an expression into a function call -- like Macro.pipe/3
Metastatic.pipe_into(expr, call_node, 0)
```

#### Predicates and inspection

```elixir
# Is the whole subtree purely literal? -- like Macro.quoted_literal?/1
Metastatic.literal?({:list, [], [{:literal, [subtype: :integer], 1}]})  # => true

# Is it an operator node?
Metastatic.operator?(ast)  # => true for :binary_op / :unary_op

# Human-readable representation -- like Macro.to_string/1
Metastatic.to_string(ast)  # => "x + y * 2"

# Decompose a function call -- like Macro.decompose_call/1
Metastatic.decompose_call(call_node)  # => {"add", [arg1, arg2]}

# Validate structure with diagnostics -- like Macro.validate/1
Metastatic.validate(ast)  # => :ok | {:error, {:invalid_node, ...}}

# Generate a fresh variable for transformations -- like Macro.unique_var/2
Metastatic.unique_var("tmp")  # => {:variable, [], "tmp_42"}
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

See **[Supplemental Modules](SUPPLEMENTAL_MODULES.md)** for comprehensive guide on using and creating supplementals.

## Documentation

- **[Theoretical Foundations](THEORETICAL_FOUNDATIONS.md)** - Formal meta-modeling theory and proofs
- **[Supplemental Modules](SUPPLEMENTAL_MODULES.md)** - Guide to using and creating supplemental modules
- **API Documentation** - Generate with `mix docs`

## Architecture

### Three-Layer MetaAST

**Layer 1: Core (M2.1)** - Universal concepts (ALL languages)  
Common constructs: literals, variables, operators, conditionals, function calls, assignments

**Layer 2: Extended (M2.2)** - Common patterns (MOST languages)  
Control flow: loops, lambdas, collection operations, pattern matching, exception handling

**Layer 2s: Structural/Organizational (M2.2s)** - Top-level constructs (MOST languages)  
Organizational: containers (modules/classes/namespaces), function definitions, properties, attribute access, augmented assignments

**Layer 3: Native (M2.3)** - Language-specific escape hatches  
Language-specific: lifetimes, async models, advanced type systems, metaprogramming

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
# Mutation testing (in muex library, NYI)
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

### AST Infrastructure
Build language-agnostic tools on top of MetaAST:

```elixir
# Extract all variables from any supported language
{:ok, doc} = Metastatic.Builder.from_source(source, language)
variables = Metastatic.AST.variables(doc.ast)
```

For static analysis, see [MetaCredo](https://github.com/Oeditus/metacredo) which provides 72 checks built on MetaAST.

## Contributing

This project is currently in the research/foundation phase. Contributions welcome!

## Research Background

Metastatic is inspired by research from:
- **muex** - Multi-language mutation testing analysis
- **propwise** - Property-based testing candidate identification

## Credits

Created as part of the Oeditus code quality tooling ecosystem.

Research synthesis from muex and propwise multi-language projects.

## Installation

```elixir
def deps do
  [
    {:metastatic, "~> 0.12"}
  ]
end
```

[Documentation](https://hexdocs.pm/metastatic).

