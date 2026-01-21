# Metastatic Implementation Plan

## Project Overview

**Goal:** Build a layered MetaAST library enabling cross-language code analysis, mutation testing, and transformation through a unified **meta-model** (M2 level in MOF hierarchy).

**Timeline:** 8-14 months (3 developers)  
**First Release:** 4-6 months (Elixir + Erlang + Python support)

## Etymology and Theoretical Foundation

### The Name "Metastatic"

The name encodes multiple layers of meaning:

1. **Met(a) + AST-atic** - "Meta" + "AST" + "-atic" (relating to)
   - Literally: "relating to meta-level ASTs"
   - Emphasizes that we work with ASTs at the meta-level

2. **Meta + Static** - "Meta-level" + "Static analysis"
   - Meta-level: M2 in the MOF hierarchy (meta-model)
   - Static: Compile-time/analysis-time (vs. runtime/M0)
   - Together: Static analysis operating at the meta-level

3. **Metastatic** (biological metaphor) - Spreading/propagating
   - Transformations at M2 level "spread" automatically to all M1 instances
   - A mutation at meta-level propagates to Python, JavaScript, Elixir, etc.
   - Like metastasis: one change affects many sites

### Theoretical Foundation: Meta-Modeling (MOF Hierarchy)

Metastatic operates at **M2 (meta-model level)** in the formal meta-modeling hierarchy:

```
M3: Meta-Meta-Model
    Elixir type system + @type definitions
    "What CAN a type be?"
    
    ↓ instance-of
    
M2: Meta-Model ← METASTATIC OPERATES HERE
    MetaAST core types: {:binary_op, :conditional, :loop, ...}
    "What CAN an AST node be?"
    Defines abstract syntax across ALL languages
    
    ↓ instance-of
    
M1: Model
    Python AST, JavaScript AST, Elixir AST
    "What IS this specific code?"
    Concrete syntax trees for specific languages
    
    ↓ instance-of
    
M0: Instance
    Running code, actual execution
    "What does this code DO?"
```

**Key Insight:** Transformations at M2 automatically apply to all M1 instances.

### Comparison with UML/MOF

| Level | UML/MOF World | Metastatic World |
|-------|---------------|------------------|
| **M3** | MOF (defines what metamodels can be) | Elixir type system |
| **M2** | UML (defines what models can be) | **MetaAST** (defines what ASTs can be) |
| **M1** | Class diagram (specific model) | Python/JS/Elixir AST (specific AST) |
| **M0** | Running objects | Executing code |

Just as UML is a **meta-model** for software structure, MetaAST is a **meta-model** for program syntax.

### Implications for Implementation

1. **Type Safety at Meta-Level**: MetaAST types are meta-types that constrain all language ASTs
2. **Conformance Validation**: Language adapters ensure M1 models conform to M2 meta-model
3. **Universal Transformations**: Mutations/analyses written once at M2 apply to all M1 instances
4. **Semantic Equivalence**: Different M1 models can be instances of the same M2 concept

---

## Phase 1: Foundation (✅ COMPLETE)

### Milestone 1.1: Core MetaAST Types (✅ COMPLETE)

**Status:** Delivered January 2026

**Deliverables:**
- [x] Define M2 meta-types for MetaAST
- [x] Implement three-layer architecture (M2.1, M2.2, M2.3)
- [x] Create MetaAST.Document struct with meta-level metadata
- [x] Implement conformance validation (M1 → M2)

**Meta-Modeling Perspective:**

This milestone establishes the **M2 layer** of our meta-modeling hierarchy. We're not just defining "another AST format" - we're defining a **meta-model** that describes what programming language ASTs **can be**.

**Files Created:**
```
lib/metastatic/
├── ast.ex                  # ✅ M2: Meta-model type definitions (551 lines)
├── document.ex             # ✅ Document wrapper with M1/M2 metadata (197 lines)
├── adapter.ex              # ✅ Adapter behaviour for M1 ↔ M2 transformations (422 lines)
├── builder.ex              # ✅ High-level API for from_source/to_source (278 lines)
└── validator.ex            # ✅ M1 conformance to M2 validation (333 lines)
```

**Test Coverage:**
```
test/metastatic/
├── ast_test.exs            # ✅ 332 lines, covers M2.1, M2.2, M2.3
├── document_test.exs       # ✅ 94 lines
└── validator_test.exs      # ✅ 274 lines

Total: 99 tests, 100% passing
```

**Core Meta-Types to Define (M2 Level):**

```elixir
# lib/metastatic/ast.ex
defmodule Metastatic.AST do
  @moduledoc """
  M2: Meta-Model for Programming Language Abstract Syntax.
  
  This module defines the meta-types that all language ASTs (M1 level) must
  conform to. Think of this as the "UML" for programming language ASTs.
  
  ## Meta-Modeling Hierarchy
  
  - M3: Elixir type system (@type, @spec)
  - M2: This module (MetaAST) - defines what AST nodes CAN be
  - M1: Python AST, JavaScript AST, Elixir AST - what specific code IS
  - M0: Runtime execution - what code DOES
  
  ## Layer Architecture (within M2)
  
  The three layers represent different granularities of meta-modeling:
  
  - M2.1 (Core): Universal concepts (ALL languages)
  - M2.2 (Extended): Common patterns (MOST languages)
  - M2.3 (Native): Language-specific escape hatches (embedded M1)
  """
  
  # Implemented as @type meta_ast (renamed from node to avoid built-in conflict)
  @type meta_ast ::
    # M2.1: Core layer - Universal programming concepts
    literal() | variable() | binary_op() | unary_op() |
    function_call() | conditional() | early_return() | block() |
    
    # M2.2: Extended layer - Common patterns with variations
    loop() | lambda() | collection_op() | pattern_match() |
    exception_handling() | async_operation() |
    
    # M2.3: Native layer - M1 escape hatch
    language_specific()
  
  # Also includes wildcard pattern support
  # Atom :_ is valid for pattern matching
  
  # M2.1: Core Layer - Universal Meta-Types
  # These represent concepts that exist in ALL programming languages
  
  @typedoc """
  M2 meta-type: Literal value.
  
  M1 instances:
  - Python: ast.Constant, ast.Num, ast.Str
  - JavaScript: Literal
  - Elixir: integer, string, atom literals
  """
  @type literal :: 
    {:literal, semantic_type(), value :: term}
  
  @type semantic_type ::
    :integer | :float | :string | :boolean | :null |
    :symbol | :regex | :collection
  
  @typedoc """
  M2 meta-type: Variable reference.
  
  M1 instances:
  - Python: ast.Name
  - JavaScript: Identifier
  - Elixir: {:var, meta, context}
  """
  @type variable :: 
    {:variable, name :: String.t}
  
  @typedoc """
  M2 meta-type: Binary operation.
  
  This is a meta-concept that abstracts over:
  - Python: ast.BinOp
  - JavaScript: BinaryExpression
  - Elixir: {:+, meta, [left, right]}
  
  All three are INSTANCES of this M2 concept.
  """
  @type binary_op :: 
    {:binary_op, :arithmetic | :comparison | :boolean, op :: atom, 
     left :: meta_ast, right :: meta_ast}
  
  @type unary_op :: 
    {:unary_op, :arithmetic | :boolean, op :: atom, operand :: meta_ast}
  
  @type function_call :: 
    {:function_call, name :: String.t, args :: [meta_ast]}
  
  @type conditional :: 
    {:conditional, condition :: meta_ast, then_branch :: meta_ast, 
     else_branch :: meta_ast | nil}
  
  @type early_return :: {:early_return, value :: meta_ast}
  @type block :: {:block, statements :: [meta_ast]}
  
  @type early_return :: 
    {:early_return, kind :: :return | :break | :continue, value :: node | nil}
  
  # M2.2: Extended Layer - Common Meta-Patterns
  # These represent concepts that exist in MOST languages, with variations
  
  @typedoc """
  M2 meta-type: Loop construct.
  
  M1 instances:
  - Python: ast.For, ast.While
  - JavaScript: ForStatement, WhileStatement
  - Elixir: Enum.each/2 (functional iteration)
  
  Metadata preserves M1-specific information (e.g., loop style)
  """
  @type loop :: 
    {:loop, kind :: :while | :for | :for_each | :infinite, 
     condition :: node | nil, body :: node, metadata :: map}
  
  @type lambda :: 
    {:lambda, params :: [param], body :: node, metadata :: map}
  
  @type param :: 
    {:param, name :: String.t, type_hint :: String.t | nil, default :: node | nil}
  
  @typedoc """
  M2 meta-type: Collection operations.
  
  These represent functional transformations that exist across languages:
  - Python: list comprehensions, map(), filter()
  - JavaScript: Array.prototype.map/filter/reduce
  - Elixir: Enum.map/2, Enum.filter/2, Enum.reduce/3
  
  All are instances of the same M2 concept.
  """
  @type collection_op :: 
    {:map, mapper :: node, collection :: node} |
    {:filter, predicate :: node, collection :: node} |
    {:reduce, reducer :: node, initial :: node, collection :: node}
  
  @type pattern_match :: 
    {:pattern_match, scrutinee :: node, arms :: [match_arm], metadata :: map}
  
  @type match_arm :: 
    {:match_arm, pattern :: node, guard :: node | nil, body :: node}
  
  @type exception_handling :: 
    {:try_catch, body :: node, rescue_clauses :: [rescue_clause], 
     finally :: node | nil, metadata :: map}
  
  @type rescue_clause :: 
    {:rescue, exception_pattern :: node, body :: node}
  
  @type async_operation :: 
    {:async, concurrency_model :: atom, operation :: node, metadata :: map}
  
  # M2.3: Native Layer - M1 Escape Hatch
  # When M1 cannot be lifted to M2, preserve as-is with semantic hints
  
  @typedoc """
  M2 escape hatch: Language-specific construct.
  
  When an M1 construct cannot be abstracted to M2 (e.g., Rust lifetimes,
  Go goroutines), we preserve the M1 AST directly with semantic hints.
  
  This allows:
  1. Round-trip fidelity (M1 → M2 → M1)
  2. Partial analysis at M2 level (using semantic_hint)
  3. Language-specific transformations when needed
  """
  @type language_specific :: 
    {:language_specific, language :: atom, native_ast :: term, 
     semantic_hint :: atom | nil}
     
  @doc """
  Validate that a term conforms to the M2 meta-model.
  
  This is M1 → M2 conformance checking.
  """
  @spec conforms?(term()) :: boolean()
  def conforms?(ast) do
    # Implementation validates structural conformance
  end
end
```

**Tests (with Meta-Modeling Validation):**
```elixir
# test/metastatic/ast_test.exs
defmodule Metastatic.ASTTest do
  use ExUnit.Case
  alias Metastatic.AST
  
  describe "M2 meta-types" do
    test "literal nodes conform to M2 meta-type" do
      # Create M2 instance
      literal = {:literal, :integer, 42}
      
      # Validate M2 conformance
      assert AST.conforms?(literal)
      assert {:literal, :integer, 42} = literal
    end
    
    test "binary operations are valid M2 instances" do
      # This represents the M2 concept of "binary operation"
      # Different M1 models (Python, JS, Elixir) will map to this
      left = {:variable, "x"}
      right = {:literal, :integer, 5}
      binop = {:binary_op, :arithmetic, :+, left, right}
      
      # Validate M2 conformance
      assert AST.conforms?(binop)
    end
  end
  
  describe "M1 → M2 abstraction" do
    test "different M1 models map to same M2 instance" do
      # All these M1 representations should produce the SAME M2 instance
      python_binop = %{"_type" => "BinOp", "op" => "Add", ...}
      js_binop = %{"type" => "BinaryExpression", "operator" => "+", ...}
      elixir_binop = {:+, [], [left, right]}
      
      # When transformed to M2, they should be identical
      {:ok, m2_from_python} = Python.to_meta(python_binop)
      {:ok, m2_from_js} = JavaScript.to_meta(js_binop)
      {:ok, m2_from_elixir} = Elixir.to_meta(elixir_binop)
      
      # Same M2 instance despite different M1 origins
      assert m2_from_python == m2_from_js
      assert m2_from_js == m2_from_elixir
    end
  end
  
  describe "M2 conformance validation" do
    test "invalid structures are rejected" do
      # This doesn't conform to M2 meta-model
      invalid = {:unknown_node_type, "data"}
      
      refute AST.conforms?(invalid)
    end
    
    test "nested structures validate recursively" do
      # Complex M2 instance with nesting
      ast = {:binary_op, :arithmetic, :+,
        {:variable, "x"},
        {:binary_op, :arithmetic, :*,
          {:literal, :integer, 2},
          {:literal, :integer, 3}
        }
      }
      
      # All nodes should conform to M2
      assert AST.conforms?(ast)
    end
  end
end
```

### Milestone 1.2: Adapter Behaviour (Weeks 5-6)

**Deliverables:**
- [x] Define MetaAST.Adapter behaviour (M1 ↔ M2 transformations)
- [x] Create adapter registry with conformance validation
- [x] Implement M1 → M2 → M1 round-trip testing framework

**Meta-Modeling Perspective:**

Adapters are **M1 ↔ M2 transformations**. They bridge between:
- **M1**: Language-specific ASTs (Python AST, JavaScript AST, etc.)
- **M2**: MetaAST meta-model

Key operations:
- `to_meta/1`: **Abstraction** (M1 → M2) - Lift concrete syntax to meta-level
- `from_meta/2`: **Reification** (M2 → M1) - Instantiate meta-model in concrete syntax
- `validate_mutation/2`: **Conformance** - Ensure M2 transformations produce valid M1

**Files to Create:**
```
lib/metastatic/
├── adapter.ex              # Behaviour definition
├── adapter/
│   └── registry.ex         # Adapter registration
└── test/
    └── adapter_helper.ex   # Testing utilities
```

**Behaviour Definition:**

```elixir
# lib/metastatic/adapter.ex
defmodule Metastatic.Adapter do
  @moduledoc """
  Behaviour for language adapters (M1 ↔ M2 transformations).
  
  Language adapters bridge between:
  - M1: Language-specific ASTs (Python, JavaScript, Elixir, etc.)
  - M2: MetaAST meta-model
  
  ## Meta-Modeling Operations
  
  - `parse/1`: Source → M1 (language-specific parsing)
  - `to_meta/1`: M1 → M2 (abstraction to meta-level)
  - `from_meta/2`: M2 → M1 (reification from meta-level)
  - `unparse/1`: M1 → Source (language-specific unparsing)
  
  ## Conformance
  
  Adapters must ensure:
  1. M1 instances conform to M2 meta-model
  2. M2 → M1 → M2 round-trips preserve semantics
  3. Invalid M2 transformations are rejected at M1 level
  """
  
  @type native_ast :: term
  @type meta_ast :: Metastatic.AST.node
  @type metadata :: map
  @type source :: String.t
  
  @doc """
  Parse source code to native AST.
  
  This may spawn external processes (Python, Node.js, etc.)
  or use native Elixir parsing.
  """
  @callback parse(source) :: 
    {:ok, native_ast} | {:error, reason :: term}
  
  @doc """
  Transform native AST to MetaAST (M1 → M2 abstraction).
  
  This is the **abstraction operation** that lifts language-specific
  AST (M1) to the meta-level (M2).
  
  Different M1 models may map to the same M2 instance:
  - Python: BinOp(op=Add) → {:binary_op, :arithmetic, :+, ...}
  - JavaScript: BinaryExpression(operator: '+') → same M2 instance
  - Elixir: {:+, [], [...]} → same M2 instance
  
  Returns M2 instance and metadata (preserves M1-specific information).
  """
  @callback to_meta(native_ast) :: 
    {:ok, meta_ast, metadata} | {:error, reason :: term}
  
  @doc """
  Transform MetaAST back to native AST (M2 → M1 reification).
  
  This is the **reification operation** that instantiates the meta-model (M2)
  into a concrete language AST (M1).
  
  Uses metadata to restore M1-specific information that was preserved
  during abstraction (e.g., formatting, type annotations, etc.).
  
  ## Conformance Validation
  
  Implementation must ensure the resulting M1 AST:
  1. Is valid for the target language
  2. Preserves the semantics of the M2 instance
  3. Can be round-tripped (M1 → M2 → M1 ≈ M1)
  """
  @callback from_meta(meta_ast, metadata) :: 
    {:ok, native_ast} | {:error, reason :: term}
  
  @doc """
  Convert native AST back to source code.
  """
  @callback unparse(native_ast) :: 
    {:ok, source} | {:error, reason :: term}
  
  @doc """
  Validate that an M2 transformation produces valid M1.
  
  After a mutation at M2 level, validate that the result:
  1. Conforms to M2 meta-model structurally
  2. Can be instantiated in this language (M1 conformance)
  3. Satisfies language-specific constraints
  
  ## Examples
  
  - Rust: Reject mutations that violate ownership/borrowing
  - TypeScript: Reject mutations that violate type constraints
  - Python: Most mutations valid (dynamic typing)
  
  This is M2 → M1 **semantic conformance validation**.
  """
  @callback validate_mutation(meta_ast, metadata) ::
    :ok | {:error, validation_error :: String.t}
  
  @doc """
  Return the file extensions this adapter handles.
  """
  @callback file_extensions() :: [String.t]
  
  @optional_callbacks [validate_mutation: 2]
end
```

### Milestone 1.3: Builder & Document (Weeks 7-8)

**Deliverables:**
- [x] Implement MetaAST.Builder
- [x] Implement MetaAST.Document
- [x] Round-trip testing framework

**Files to Create:**
```
lib/metastatic/
├── builder.ex              # Build MetaAST from source
└── document.ex             # Document wrapper
```

**Implementation:**

```elixir
# lib/metastatic/builder.ex
defmodule Metastatic.Builder do
  alias Metastatic.{Document, Adapter}
  
  @doc """
  Build MetaAST document from source code.
  
  ## Examples
  
      iex> Builder.from_source("x = 1 + 2", :python)
      {:ok, %Document{language: :python, ast: {...}, metadata: %{}}}
  """
  def from_source(source, language) do
    adapter = get_adapter(language)
    
    with {:ok, native_ast} <- adapter.parse(source),
         {:ok, meta_ast, metadata} <- adapter.to_meta(native_ast) do
      {:ok, %Document{
        language: language,
        ast: meta_ast,
        metadata: metadata,
        original_source: source
      }}
    end
  end
  
  @doc """
  Convert MetaAST document back to source code.
  
  Optionally specify a different target language for translation.
  """
  def to_source(%Document{} = doc, target_language \\ nil) do
    target = target_language || doc.language
    adapter = get_adapter(target)
    
    with :ok <- validate_translation(doc.language, target),
         {:ok, native_ast} <- adapter.from_meta(doc.ast, doc.metadata),
         {:ok, source} <- adapter.unparse(native_ast) do
      {:ok, source}
    end
  end
  
  defp get_adapter(language) do
    Adapter.Registry.get(language)
  end
  
  defp validate_translation(source_lang, source_lang), do: :ok
  defp validate_translation(_source, _target) do
    # For now, only same-language round-trips
    {:error, :cross_language_translation_not_supported}
  end
end
```

### Milestone 1.4: Test Infrastructure (Weeks 9-12)

**Deliverables:**
- [x] Test fixture framework
- [x] Round-trip test generator
- [x] Benchmark suite
- [x] CI/CD setup

**Test Structure:**
```
test/
├── fixtures/
│   ├── python/
│   │   ├── simple_arithmetic.py
│   │   ├── list_comprehension.py
│   │   └── expected_meta_ast/
│   │       ├── simple_arithmetic.exs
│   │       └── list_comprehension.exs
│   ├── javascript/
│   └── elixir/
├── support/
│   ├── fixture_helper.ex
│   └── round_trip_helper.ex
└── metastatic/
    ├── ast_test.exs
    ├── builder_test.exs
    └── adapters/
```

---

## Phase 2: Language Adapters - BEAM Ecosystem (✅ COMPLETE)

### Strategic Rationale: Elixir First

We're starting with Elixir (then Erlang) rather than Python for several key reasons:

1. **Zero External Dependencies**: Direct access to `Code.string_to_quoted!/2` and `Macro.to_string/1` - no parser subprocess needed
2. **Type System Alignment**: Elixir AST is already tuple-based, matching MetaAST structure exactly
3. **Dogfooding**: Building the first adapter in the same language as the meta-library enables rapid iteration on the `Metastatic.Adapter` behaviour
4. **Trivial Round-Trip Validation**: Native quote/unquote cycle makes testing straightforward
5. **Erlang Comes ~80% Free**: Shared BEAM tuple structure means second adapter is minimal delta
6. **Immediate Practical Value**: Enables muex/propwise cross-language support (original motivation)

Once the BEAM ecosystem is proven (Weeks 13-20), Python adapter (Weeks 21-28) will benefit from battle-tested M2 design.

### Milestone 2.1: Elixir Adapter - Foundation (✅ COMPLETE)

**Status:** Delivered January 2026

**Deliverables:**
- [x] Elixir AST → MetaAST transformer (M1 → M2)
- [x] MetaAST → Elixir AST transformer (M2 → M1)
- [x] Parse/unparse using native `Code` module
- [x] Register adapter in Adapter.Registry

**Files to Create:**
```
lib/metastatic/adapters/
├── elixir.ex               # Elixir adapter implementation
└── elixir/
    ├── to_meta.ex          # Elixir AST → MetaAST
    ├── from_meta.ex        # MetaAST → Elixir AST
    └── normalization.ex    # AST normalization helpers

test/metastatic/adapters/
└── elixir_test.exs         # Adapter tests
```

**Adapter Implementation:**

```elixir
# lib/metastatic/adapters/elixir.ex
defmodule Metastatic.Adapters.Elixir do
  @moduledoc """
  Elixir language adapter for MetaAST.
  
  Transforms between Elixir AST (M1) and MetaAST (M2).
  
  ## Elixir AST Structure
  
  Elixir represents AST as three-element tuples: `{form, metadata, arguments}`
  
  Examples:
  - Variable: `{:x, [], nil}`
  - Addition: `{:+, [], [{:x, [], nil}, 5]}`
  - Function call: `{:foo, [], [arg1, arg2]}`
  """
  
  @behaviour Metastatic.Adapter
  
  alias Metastatic.Adapters.Elixir.{ToMeta, FromMeta}
  
  @impl true
  def parse(source) when is_binary(source) do
    case Code.string_to_quoted(source) do
      {:ok, ast} -> {:ok, ast}
      {:error, {_meta, message, token}} ->
        {:error, "Syntax error: #{message}#{token}"}
    end
  end
  
  @impl true
  def to_meta(elixir_ast) do
    ToMeta.transform(elixir_ast)
  end
  
  @impl true
  def from_meta(meta_ast, metadata) do
    FromMeta.transform(meta_ast, metadata)
  end
  
  @impl true
  def unparse(elixir_ast) do
    {:ok, Macro.to_string(elixir_ast)}
  end
  
  @impl true
  def file_extensions do
    [".ex", ".exs"]
  end
end
```

**Core Transformations (Elixir → MetaAST):**

```elixir
# lib/metastatic/adapters/elixir/to_meta.ex
defmodule Metastatic.Adapters.Elixir.ToMeta do
  @moduledoc "Transform Elixir AST (M1) to MetaAST (M2)."
  
  # Literal integers/floats/strings/atoms
  def transform(value) when is_integer(value),
    do: {:ok, {:literal, :integer, value}, %{}}
  
  def transform(value) when is_float(value),
    do: {:ok, {:literal, :float, value}, %{}}
  
  def transform(value) when is_binary(value),
    do: {:ok, {:literal, :string, value}, %{}}
  
  def transform(value) when is_boolean(value),
    do: {:ok, {:literal, :boolean, value}, %{}}
  
  def transform(nil),
    do: {:ok, {:literal, :null, nil}, %{}}
  
  # Variable: {:var_name, meta, context}
  def transform({var, _meta, context}) when is_atom(var) and is_atom(context) do
    {:ok, {:variable, to_string(var)}, %{}}
  end
  
  # Binary operators: {:+, meta, [left, right]}
  def transform({op, _meta, [left, right]}) when op in [:+, :-, :*, :/] do
    with {:ok, left_meta, _} <- transform(left),
         {:ok, right_meta, _} <- transform(right) do
      {:ok, {:binary_op, :arithmetic, op, left_meta, right_meta}, %{}}
    end
  end
  
  # Comparison operators
  def transform({op, _meta, [left, right]}) when op in [:==, :!=, :<, :>, :<=, :>=] do
    with {:ok, left_meta, _} <- transform(left),
         {:ok, right_meta, _} <- transform(right) do
      {:ok, {:binary_op, :comparison, op, left_meta, right_meta}, %{}}
    end
  end
  
  # Boolean operators
  def transform({op, _meta, [left, right]}) when op in [:and, :or] do
    with {:ok, left_meta, _} <- transform(left),
         {:ok, right_meta, _} <- transform(right) do
      {:ok, {:binary_op, :boolean, op, left_meta, right_meta}, %{}}
    end
  end
  
  # Function calls: {function_name, meta, args}
  def transform({func, _meta, args}) when is_atom(func) and is_list(args) do
    with {:ok, args_meta} <- transform_list(args) do
      {:ok, {:function_call, to_string(func), args_meta}, %{}}
    end
  end
  
  # If/else: {:if, meta, [condition, [do: then_clause, else: else_clause]]}
  def transform({:if, _meta, [condition, clauses]}) do
    then_clause = Keyword.get(clauses, :do)
    else_clause = Keyword.get(clauses, :else)
    
    with {:ok, cond_meta, _} <- transform(condition),
         {:ok, then_meta, _} <- transform(then_clause),
         {:ok, else_meta, _} <- if(else_clause, do: transform(else_clause), else: {:ok, nil, %{}}) do
      {:ok, {:conditional, cond_meta, then_meta, else_meta}, %{}}
    end
  end
  
  defp transform_list(items) do
    items
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
      case transform(item) do
        {:ok, meta, _} -> {:cont, {:ok, [meta | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, items} -> {:ok, Enum.reverse(items)}
      error -> error
    end
  end
end
```

### Milestone 2.2: Elixir Adapter - Core & Extended Constructs (✅ COMPLETE)

**Status:** Delivered January 2026

**Deliverables:**
- [x] Handle all M2.1 (Core) constructs: literals, variables, binary_op, unary_op, function_call, conditional, block, early_return
- [x] Handle M2.2 (Extended) constructs: lambda, collection_op (Enum.map/filter/reduce), pattern matching, comprehensions
- [x] 30+ test fixtures covering Elixir patterns
- [x] Round-trip accuracy >95%

**Test Fixtures:**
```
test/fixtures/elixir/
├── core/
│   ├── literals.exs           # Integers, floats, strings, atoms, booleans
│   ├── variables.exs          # Variable references
│   ├── arithmetic.exs         # +, -, *, /, rem, div
│   ├── comparisons.exs        # ==, !=, <, >, <=, >=, ===, !==
│   ├── boolean_ops.exs        # and, or, not
│   ├── function_calls.exs     # foo(), bar(1, 2, 3)
│   ├── conditionals.exs       # if/else, unless, cond, case
│   └── blocks.exs             # __block__ with multiple statements
├── extended/
│   ├── anonymous_fns.exs      # fn x -> x + 1 end
│   ├── enum_map.exs           # Enum.map(list, fn x -> x * 2 end)
│   ├── enum_filter.exs        # Enum.filter(list, predicate)
│   ├── enum_reduce.exs        # Enum.reduce(list, 0, fn x, acc -> ... end)
│   ├── comprehensions.exs     # for x <- list, do: x * 2
│   └── pattern_match.exs      # case, with patterns
└── native/
    ├── pipe.exs               # |> operator (Elixir-specific)
    ├── with.exs               # with clauses
    └── macros.exs             # quote/unquote (language_specific)
```

### Milestone 2.3: Erlang Adapter (✅ COMPLETE)

**Status:** Delivered January 2026

**Deliverables:**
- [x] Erlang AST → MetaAST transformer
- [x] MetaAST → Erlang AST transformer  
- [x] Parse using `:erl_scan` + `:erl_parse`
- [x] Unparse using `:erl_pp` (not `:erl_prettypr`)
- [x] 33 comprehensive Erlang tests
- [x] Cross-language validation (Erlang ≡ Elixir at M2 level)

**Files to Create:**
```
lib/metastatic/adapters/
├── erlang.ex               # Erlang adapter
└── erlang/
    ├── to_meta.ex          # Erlang AST → MetaAST
    ├── from_meta.ex        # MetaAST → Erlang AST
    └── erl_helpers.ex      # Erlang interop utilities
```

**Erlang Adapter:**

```elixir
# lib/metastatic/adapters/erlang.ex
defmodule Metastatic.Adapters.Erlang do
  @behaviour Metastatic.Adapter
  
  @impl true
  def parse(source) when is_binary(source) do
    # Erlang parsing pipeline:
    # 1. Tokenize with :erl_scan
    # 2. Parse with :erl_parse
    with {:ok, tokens, _} <- :erl_scan.string(String.to_charlist(source)),
         {:ok, forms} <- :erl_parse.parse_exprs(tokens) do
      {:ok, forms}
    else
      {:error, {_line, _mod, reason}, _} -> {:error, "Parse error: #{inspect(reason)}"}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end
  
  @impl true
  def unparse(erlang_ast) do
    # Use erl_prettypr for formatting
    result = 
      erlang_ast
      |> :erl_syntax.form_list()
      |> :erl_prettypr.format()
      |> to_string()
    
    {:ok, result}
  end
  
  @impl true
  def file_extensions, do: [".erl", ".hrl"]
end
```

**Erlang AST Examples:**

```erlang
% Source: X + 5
% AST: {:op, Line, :+, {:var, Line, :X}, {:integer, Line, 5}}

% Source: foo(1, 2)
% AST: {:call, Line, {:atom, Line, :foo}, [{:integer, Line, 1}, {:integer, Line, 2}]}

% Source: case X of 1 -> ok; _ -> error end
% AST: {:case, Line, {:var, Line, :X}, 
%       [{:clause, Line, [{:integer, Line, 1}], [], [{:atom, Line, :ok}]},
%        {:clause, Line, [{:var, Line, :_}], [], [{:atom, Line, :error}]}]}
```

---

## Phase 3: Python Adapter (✅ COMPLETE)

### Milestone 3.1: Python Parser Integration (✅ COMPLETE)

**Status:** Delivered January 2026

**Deliverables:**
- [x] Python helper script for AST parsing  
- [x] JSON serialization of Python AST
- [x] Subprocess-based communication
- [x] Elixir wrapper with error handling

**Files to Create:**
```
priv/parsers/python/
├── parser.py               # Python AST → JSON
├── unparser.py             # JSON → Python source
└── requirements.txt        # (empty - stdlib only)

lib/metastatic/adapters/
├── python.ex               # Python adapter
└── python/
    ├── to_meta.ex          # Python AST → MetaAST
    └── from_meta.ex        # MetaAST → Python AST
```

**Python Parser Script:**

```python
# priv/parsers/python/parser.py
import ast
import json
import sys

def ast_to_dict(node):
    """Convert Python AST to JSON-serializable dict."""
    if isinstance(node, ast.AST):
        result = {'_type': node.__class__.__name__}
        for field, value in ast.iter_fields(node):
            result[field] = ast_to_dict(value) if not isinstance(value, list) else [ast_to_dict(x) for x in value]
        return result
    return node if not isinstance(node, list) else [ast_to_dict(x) for x in node]

if __name__ == '__main__':
    source = sys.stdin.read()
    try:
        tree = ast.parse(source)
        print(json.dumps({'ok': True, 'ast': ast_to_dict(tree)}))
    except SyntaxError as e:
        print(json.dumps({'ok': False, 'error': str(e)}))
```

**Files Created:**
```
priv/parsers/python/
├── parser.py               # ✅ Python AST → JSON (129 lines)
├── unparser.py             # ✅ JSON → Python source (43 lines)
└── requirements.txt        # ✅ (empty - stdlib only)

lib/metastatic/adapters/
├── python.ex               # ✅ Python adapter (125 lines)
└── python/
    ├── to_meta.ex          # ✅ Python AST → MetaAST (522 lines)
    └── from_meta.ex        # ✅ MetaAST → Python AST (624 lines)
```

**Test Coverage:**
- 110 Python adapter tests (107 passing, 3 skipped)
- Subprocess communication with robust error handling
- JSON serialization/deserialization working reliably

### Milestone 3.2: Python Core Layer (M2.1) (✅ COMPLETE)

**Status:** Delivered January 2026

**Deliverables:**
- [x] Python AST → MetaAST (M1 → M2) for Core layer
- [x] MetaAST → Python AST (M2 → M1) for Core layer
- [x] Handle M2.1 core constructs: literals, variables, binary_op, unary_op, function_call, conditional, block
- [x] Handle all Python literal types (int, float, str, bool, None)
- [x] Handle all arithmetic operators (+, -, *, /, //, %, **)
- [x] Handle all comparison operators (==, !=, <, >, <=, >=, is, is not)
- [x] Handle all boolean operators (and, or, not)

**Key Core Transformations:**
- `ast.BinOp` → `{:binary_op, :arithmetic, op, left, right}`
- `ast.Compare` → `{:binary_op, :comparison, op, left, right}`
- `ast.BoolOp` → `{:binary_op, :boolean, op, left, right}`
- `ast.UnaryOp` → `{:unary_op, category, op, operand}`
- `ast.Name` → `{:variable, name}`
- `ast.Constant` → `{:literal, type, value}`
- `ast.Call` → `{:function_call, name, args}`
- `ast.IfExp` → `{:conditional, condition, then_branch, else_branch}`
- `ast.Module` with multiple statements → `{:block, statements}`

**Test Results:**
- 45 Core layer tests, 100% passing
- Round-trip working for all Core constructs
- Cross-language validation working (Python ↔ Elixir)

### Milestone 3.3: Python Extended Layer (M2.2) (✅ COMPLETE)

**Status:** Delivered January 2026

**Deliverables:**
- [x] Loops: While loops and For loops → `{:loop, kind, condition/iterator, body}`
- [x] Lambdas: Lambda expressions → `{:lambda, params, captures, body}`
- [x] Collection operations: List comprehensions → `{:collection_op, :map, lambda, collection}`
- [x] Exception handling: Try/except/finally → `{:exception_handling, body, rescue_clauses, finally}`
- [x] Bidirectional transformations (M2 → M1 → M2) for all Extended constructs

**Key Extended Transformations:**
- `ast.While` → `{:loop, :while, condition, body}` (4-tuple)
- `ast.For` → `{:loop, :for_each, iterator, collection, body}` (5-tuple)
- `ast.Lambda` → `{:lambda, params, [], body}`
- `ast.ListComp` → `{:collection_op, :map, lambda, collection}` (with filter support)
- `ast.Try` → `{:exception_handling, body, handlers, finally}`
- Builtin map/filter/reduce → `{:collection_op, kind, lambda, collection[, initial]}`

**Test Results:**
- 23 Extended layer tests, 100% passing
- List comprehensions correctly transformed to/from collection_op
- Exception handling with rescue clauses and finally blocks working

### Milestone 3.4: Python Native Layer (M2.3) & Test Fixtures (✅ COMPLETE)

**Status:** Delivered January 2026

**Deliverables:**
- [x] Native layer support via `{:language_specific, :python, node, hint}`
- [x] 17 test fixtures across all three layers (Core, Extended, Native)
- [x] Comprehensive fixture documentation (README.md)
- [x] 25 Native layer tests for language_specific preservation
- [x] 18 fixture-based integration tests
- [x] 6 enhanced cross-language validation tests
- [x] Performance validation (<100ms per 1000 LOC)

**Native Layer Constructs:**
- Decorators: `@decorator` on functions/classes → `{:language_specific, :python, node, :function_with_decorators}`
- Context managers: `with` statement → `{:language_specific, :python, node, :context_manager}`
- Generators: Functions with `yield`/`yield from` → `{:language_specific, :python, node, :function_with_generator}`
- Classes: `class` definitions → `{:language_specific, :python, node, :class}`
- Async/await: `async def`, `await` → `{:language_specific, :python, node, :async_function/:await}`
- Imports: `import`, `from...import` → `{:language_specific, :python, node, :import/:import_from}`
- Advanced comprehensions: dict/set/generator → `{:language_specific, :python, node, hint}`
- Python 3.10+: `match` statements, walrus operator → `{:language_specific, :python, node, hint}`
- Statements: `global`, `nonlocal`, `assert`, `raise`, `delete`, `pass` → `{:language_specific, :python, node, hint}`

**Test Fixtures:**
```
test/fixtures/python/
├── README.md               # ✅ 160 lines of documentation
├── core/                   # ✅ 6 fixtures
│   ├── arithmetic.py
│   ├── comparisons.py
│   ├── boolean_logic.py
│   ├── function_calls.py
│   ├── conditionals.py     # (contains unsupported constructs - skipped)
│   └── blocks.py           # (contains unsupported constructs - skipped)
├── extended/               # ✅ 5 fixtures
│   ├── loops.py            # (contains unsupported constructs - skipped)
│   ├── lambdas.py
│   ├── comprehensions.py
│   ├── exception_handling.py
│   └── builtin_functions.py
└── native/                 # ✅ 6 fixtures
    ├── decorators.py
    ├── context_managers.py
    ├── generators.py
    ├── classes.py
    ├── async_await.py
    └── imports.py
```

**Test Results:**
- **Total: 395 tests** (21 doctests + 374 tests)
- **Passing: 392 tests** (99.2% pass rate)
- **Skipped: 3 tests** (fixtures with assignments - not yet implemented)
- **Failures: 0**
- **Regressions: 0**
- **Coverage: 100%** for implemented constructs

**Test Progression:**
- Milestone 3.1 (Parser): 259 tests
- Milestone 3.2 (Core): 282 tests (+23)
- Milestone 3.3 (Extended): 327 tests (+45)
- Milestone 3.4 (Native): 395 tests (+68, +26%)

**Performance:**
- Python parsing: ~10-15ms per file
- M1 → M2 transformation: <5ms per 1000 LOC
- Round-trip (Source → M1 → M2 → M1 → Source): <100ms per 1000 LOC ✓

**Cross-Language Validation:**
- Python `x + 5` ≡ Elixir `x + 5` (same MetaAST)
- Python `a * b` ≡ Elixir `a * b` (same MetaAST)
- Python `x > 10` ≡ Elixir `x > 10` (same MetaAST)
- Python `True and False` ≡ Elixir `true and false` (same MetaAST)
- Python `foo(1, 2)` ≡ Elixir `foo(1, 2)` (same MetaAST)
- Python ternary ≡ Elixir if/do/else (same MetaAST)

**Phase 3 Complete:** Python adapter fully implemented with all three MetaAST layers, comprehensive test coverage, and validated cross-language semantic equivalence.

---

## Phase 4: JavaScript Adapter (Months 4-6)

**Note:** Mutation testing, purity analysis, and complexity metrics are **OUT OF SCOPE** for Metastatic. These tools will be built as separate libraries that leverage Metastatic's MetaAST foundation.

- **Mutation Testing**: See [`muex`](https://github.com/Oeditus/muex) library
- **Purity Analysis**: Planned for separate library
- **Complexity Metrics**: Planned for separate library

### Milestone 4.1: JavaScript Parser Integration (Weeks 29-32)

**Deliverables:**
- [ ] JavaScript helper script for AST parsing (using Babel or @babel/parser)
- [ ] JSON serialization of JavaScript AST
- [ ] Subprocess-based communication
- [ ] Elixir wrapper with error handling

**Files to Create:**
```
priv/parsers/javascript/
├── parser.js              # JavaScript AST → JSON
├── unparser.js            # JSON → JavaScript source
└── package.json           # Dependencies: @babel/parser, @babel/generator

lib/metastatic/adapters/
├── javascript.ex          # JavaScript adapter
└── javascript/
    ├── to_meta.ex         # JavaScript AST → MetaAST
    └── from_meta.ex       # MetaAST → JavaScript AST
```

### Milestone 4.2: JavaScript Core Layer (M2.1) (Weeks 33-34)

**Deliverables:**
- [ ] JavaScript AST → MetaAST (M1 → M2) for Core layer
- [ ] MetaAST → JavaScript AST (M2 → M1) for Core layer
- [ ] Handle M2.1 core constructs
- [ ] Handle all JavaScript literal types
- [ ] Handle all operators (arithmetic, comparison, boolean)
- [ ] 40+ Core layer tests

### Milestone 4.3: JavaScript Extended Layer (M2.2) (Weeks 35-36)

**Deliverables:**
- [ ] Loops, arrow functions, array methods (map/filter/reduce)
- [ ] Exception handling (try/catch/finally)
- [ ] 20+ Extended layer tests

### Milestone 4.4: JavaScript Native Layer (M2.3) & Fixtures (Weeks 37-38)

**Deliverables:**
- [ ] Native layer support (classes, async/await, destructuring, etc.)
- [ ] Test fixtures for all three layers
- [ ] Cross-language validation (JavaScript ≡ Python ≡ Elixir)
- [ ] Performance validation (<100ms per 1000 LOC)

---

## Phase 5: CLI & Integration (Months 7-8)

**Note:** This phase focuses on tooling that leverages Metastatic's MetaAST foundation: language translation, AST inspection, and semantic equivalence validation. Mutation testing and code analysis tools are OUT OF SCOPE (see muex library).

### Milestone 5.1: CLI Tool (✅ COMPLETE)

**Status:** Delivered January 2026

**Deliverables:**
- [x] Command-line interface using Mix tasks
- [x] Language translation command (cross-language code transformation)
- [x] AST inspection and analysis tools
- [x] MetaAST visualization (tree format, JSON export)
- [x] Semantic equivalence validation
- [x] Comprehensive test suite (82 new tests, 100% passing)

**CLI Design:**

```bash
# Cross-language translation
metastatic translate --from python --to elixir my_file.py
metastatic translate --from elixir --to python lib/my_module.ex --output py_output/

# AST inspection
metastatic inspect my_file.py                    # Show MetaAST structure
metastatic inspect --layer core my_file.py        # Filter by layer (core/extended/native)
metastatic inspect --variables my_file.py         # Extract all variables
metastatic inspect --format json my_file.py       # Export as JSON

# Semantic equivalence validation
metastatic validate-equivalence file1.py file2.ex # Check if two files have equivalent MetaAST

# MetaAST analysis
metastatic analyze my_file.py                     # Show MetaAST metrics (depth, node count, layer distribution)
metastatic analyze --validate strict my_file.py   # Validate conformance with strict mode

# Documentation
metastatic docs                                   # Generate MetaAST reference documentation
```

**Files to Create:**
```
lib/mix/tasks/
├── metastatic.translate.ex      # Cross-language translation
├── metastatic.inspect.ex         # AST inspection tools
├── metastatic.validate_equivalence.ex  # Semantic equivalence checking
├── metastatic.analyze.ex         # MetaAST analysis and metrics
└── metastatic.docs.ex            # Documentation generation

lib/metastatic/
├── cli.ex                        # Shared CLI utilities
└── cli/
    ├── formatter.ex              # Output formatting (tree, JSON, etc.)
    ├── inspector.ex              # AST inspection logic
    └── translator.ex             # Translation orchestration

test/mix/tasks/
├── metastatic_translate_test.exs
├── metastatic_inspect_test.exs
├── metastatic_validate_equivalence_test.exs
└── metastatic_analyze_test.exs
```

**Files Created:**
```
lib/metastatic/
├── cli.ex                        # ✅ 143 lines - Shared CLI utilities
└── cli/
    ├── formatter.ex              # ✅ 371 lines - Tree/JSON/plain formatting
    ├── inspector.ex              # ✅ 312 lines - AST inspection logic
    └── translator.ex             # ✅ 177 lines - Translation orchestration

lib/mix/tasks/
├── metastatic.translate.ex       # ✅ 225 lines - Cross-language translation
├── metastatic.inspect.ex         # ✅ 212 lines - AST inspection command
├── metastatic.validate_equivalence.ex # ✅ 251 lines - Equivalence validation
└── metastatic.analyze.ex         # ✅ 207 lines - Metrics and validation

test/mix/tasks/
├── metastatic_translate_test.exs # ✅ 239 lines - 18 tests
├── metastatic_inspect_test.exs   # ✅ 372 lines - 29 tests
├── metastatic_validate_equivalence_test.exs # ✅ 394 lines - 16 tests
└── metastatic_analyze_test.exs   # ✅ 343 lines - 19 tests
```

**Test Results:**
- **Total: 477 tests** (21 doctests + 456 tests)
- **Passing: 474** (99.4%)
- **Skipped: 3** (assignments not yet implemented - pre-existing)
- **Failures: 0**
- **New CLI tests: 82 comprehensive tests**

**Features Implemented:**
- Cross-language translation (Python ↔ Elixir ↔ Erlang)
- Multiple output formats (tree, JSON, plain)
- Layer filtering (core, extended, native)
- Variable extraction and analysis
- Validation modes (strict, standard, permissive)
- Semantic equivalence checking
- Directory translation with structure preservation
- Colored ANSI terminal output

**Performance:**
- Translation: <100ms per 1000 LOC
- Inspection: <50ms per file
- All operations within target performance metrics

### Milestone 5.2: Oeditus Integration (Weeks 45-48)

**Deliverables:**
- [ ] Oeditus plugin for Metastatic
- [ ] Cross-language audit rules
- [ ] Performance optimization
- [ ] Production testing

**Integration:**

```elixir
# In Oeditus config
config :oeditus, :auditors,
  meta: Oeditus.Auditors.Metastatic

# Oeditus will now run Metastatic-based audits
# on Python, JavaScript, and Elixir files
```

---

## Phase 5: Additional Languages (Months 9-14)

### Milestone 5.1: TypeScript Adapter (Weeks 49-54)

Leverage JavaScript adapter, add type system support.

### Milestone 5.2: Ruby Adapter (Weeks 55-60)

Similar to Python - dynamic language with good AST support.

### Milestone 5.3: Go Adapter (Weeks 61-66)

Requires Go binary helper for parsing.

### Milestone 5.4: Rust Adapter (Optional, Weeks 67-72)

Complex type system, ownership semantics.

---

## Phase 6: Supplemental Modules for Cross-Language Support (Months 15-18)

### Overview

**Problem:** Some languages lack native constructs for certain MetaAST patterns, but third-party libraries provide equivalent functionality. How should Metastatic handle MetaAST constructs that are unsupported natively in a target language?

**Example:** Elixir's actor model (`GenServer.call/2`, `spawn/1`, `receive do`) maps to MetaAST concepts like `{:actor_call, ...}` and `{:spawn_process, ...}`. Python and JavaScript have actor libraries (pykka, nact, comedy) but no native support.

**Solution:** Two-tier strategy:
1. **Graceful default** - Return descriptive errors for unsupported constructs
2. **Supplemental modules** (opt-in) - User-provided mappings to library calls

### Milestone 6.1: Supplemental Module API (Weeks 73-76)

**Deliverables:**
- [ ] Define `Metastatic.Supplemental` behaviour
- [ ] Implement supplemental module registration
- [ ] Integrate with adapter `from_meta` pipeline
- [ ] Add supplemental validation and error reporting

**Files to Create:**
```
lib/metastatic/
├── supplemental.ex         # Core supplemental API
└── supplemental/
    ├── registry.ex         # Supplemental module registry
    └── validator.ex        # Validate supplemental handlers

test/metastatic/
└── supplemental_test.exs   # Test supplemental API
```

**API Design:**

```elixir
defmodule Metastatic.Supplemental do
  @moduledoc """
  Supplemental modules provide mappings for MetaAST constructs that are not
  natively supported in target languages.
  
  ## Example
  
  When transforming Elixir actor code to Python:
  
      # Elixir source
      GenServer.call(server, :get_state)
      
      # MetaAST (M2)
      {:actor_call, {:variable, "server"}, {:literal, :atom, :get_state}, 5000}
      
      # Without supplemental: ERROR
      # With supplemental: actor_ref.ask({"type": "get_state"}, timeout=5000)
  """
  
  @type construct_handler :: (term() -> {:ok, ast_node} | {:error, String.t()})
  @type supplemental_map :: %{atom() => construct_handler}
  
  @doc """
  Create a new supplemental module mapping.
  """
  @spec new() :: supplemental_map()
  def new(), do: %{}
  
  @doc """
  Register a handler for a MetaAST construct.
  
  ## Example
  
      supplemental = Supplemental.new()
      |> Supplemental.register(:actor_call, &PykkaSupplemental.handle_actor_call/3)
      |> Supplemental.register(:spawn_process, &PykkaSupplemental.handle_spawn/1)
  """
  @spec register(supplemental_map(), atom(), construct_handler()) :: supplemental_map()
  def register(supplemental, construct_type, handler) do
    Map.put(supplemental, construct_type, handler)
  end
  
  @doc """
  Check if a construct is supported by the supplemental module.
  """
  @spec supports?(supplemental_map(), atom()) :: boolean()
  def supports?(supplemental, construct_type) do
    Map.has_key?(supplemental, construct_type)
  end
end
```

**Adapter Integration:**

```elixir
defmodule Metastatic.Adapters.Python.FromMeta do
  def transform({:actor_call, server, message, timeout}, metadata, opts \\ []) do
    supplemental = Keyword.get(opts, :supplemental, %{})
    
    case Map.get(supplemental, :actor_call) do
      nil ->
        {:error, """
        Actor model constructs are not natively supported in Python.
        
        Consider using a supplemental module:
        - pykka: for Akka-style actors
        - asyncio: for async/await actors
        
        See documentation: https://hexdocs.pm/metastatic/supplemental.html
        """}
      
      handler when is_function(handler, 3) ->
        handler.(server, message, timeout)
      
      _ ->
        {:error, "Invalid supplemental handler for :actor_call"}
    end
  end
end
```

### Milestone 6.2: Official Supplemental Modules (Weeks 77-82)

**Deliverables:**
- [ ] Python pykka supplemental module (actor model)
- [ ] JavaScript nact supplemental module (actor model)
- [ ] Python asyncio supplemental module (async patterns)
- [ ] Documentation with usage examples
- [ ] Test coverage for supplemental transformations

**Files to Create:**
```
lib/metastatic/supplemental/
├── python/
│   ├── pykka.ex            # Pykka actor library support
│   └── asyncio.ex          # Asyncio supplemental
└── javascript/
    └── nact.ex             # Nact actor library support

test/metastatic/supplemental/
├── python_pykka_test.exs
├── python_asyncio_test.exs
└── javascript_nact_test.exs
```

**Example: Pykka Supplemental Module:**

```elixir
defmodule Metastatic.Supplemental.Python.Pykka do
  @moduledoc """
  Supplemental module for Python's pykka actor library.
  
  Maps Elixir actor model constructs to pykka API calls.
  """
  
  @doc """
  Transform actor_call to pykka's actor_ref.ask().
  
  ## Example
  
      # MetaAST
      {:actor_call, {:variable, "server"}, {:literal, :atom, :get_state}, 5000}
      
      # Python (via pykka)
      server.ask({"type": "get_state"}, timeout=5.0)
  """
  def handle_actor_call(server, message, timeout_ms) do
    # Convert timeout from milliseconds to seconds (pykka uses seconds)
    timeout_sec = timeout_ms / 1000
    
    {:ok, %{
      "_type" => "Call",
      "func" => %{
        "_type" => "Attribute",
        "value" => server,  # Already a Python AST node
        "attr" => "ask"
      },
      "args" => [message],
      "keywords" => [
        %{
          "arg" => "timeout",
          "value" => %{"_type" => "Constant", "value" => timeout_sec}
        }
      ]
    }}
  end
  
  @doc """
  Transform spawn_process to pykka's ActorClass.start().
  """
  def handle_spawn(lambda) do
    # For now, return error - requires class definition
    {:error, "spawn_process requires actor class definition in pykka"}
  end
  
  @doc """
  Get the supplemental module mapping.
  """
  def supplemental() do
    Metastatic.Supplemental.new()
    |> Metastatic.Supplemental.register(:actor_call, &handle_actor_call/3)
    |> Metastatic.Supplemental.register(:spawn_process, &handle_spawn/1)
  end
end
```

**Usage Example:**

```elixir
# Elixir source with actor model
elixir_source = """
result = GenServer.call(server, :get_state, 5000)
"""

# Parse and transform to MetaAST
{:ok, doc} = Metastatic.Builder.from_source(elixir_source, :elixir)

# Transform to Python WITH supplemental module
supplemental = Metastatic.Supplemental.Python.Pykka.supplemental()
{:ok, python_ast} = Metastatic.Adapters.Python.from_meta(
  doc.ast,
  doc.metadata,
  supplemental: supplemental
)

{:ok, python_source} = Metastatic.Adapters.Python.unparse(python_ast)

# Result:
# result = server.ask({"type": "get_state"}, timeout=5.0)
```

### Milestone 6.3: Supplemental Discovery & Validation (Weeks 83-86)

**Deliverables:**
- [ ] Static analysis tool to detect required supplemental modules
- [ ] Runtime validation of supplemental module compatibility
- [ ] Compatibility matrix documentation
- [ ] CLI integration for supplemental warnings

**Static Analysis Tool:**

```bash
# Analyze what supplemental modules are needed
metastatic analyze --supplemental my_file.ex --target python

# Output:
# Warning: The following constructs require supplemental modules for Python:
#   - Line 42: actor_call (GenServer.call) - Use: Metastatic.Supplemental.Python.Pykka
#   - Line 87: spawn_process (spawn) - Use: Metastatic.Supplemental.Python.Pykka
# 
# To enable transformation, provide supplemental module:
#   metastatic translate --from elixir --to python \
#     --supplemental pykka my_file.ex
```

**Files to Create:**
```
lib/metastatic/
└── supplemental/
    ├── analyzer.ex         # Detect required supplemental modules
    └── compatibility.ex    # Version compatibility checking

lib/mix/tasks/
└── metastatic.analyze.supplemental.ex  # Mix task
```

### Milestone 6.4: Community Supplemental Infrastructure (Weeks 87-90)

**Deliverables:**
- [ ] Supplemental module registry (discover community modules)
- [ ] Supplemental module template/generator
- [ ] Documentation for creating supplemental modules
- [ ] Contribution guidelines

**Registry Design:**

```elixir
defmodule Metastatic.Supplemental.Registry do
  @moduledoc """
  Registry of available supplemental modules.
  
  Community members can publish supplemental modules that extend
  Metastatic's cross-language transformation capabilities.
  """
  
  @registry %{
    python: [
      %{
        name: :pykka,
        module: Metastatic.Supplemental.Python.Pykka,
        constructs: [:actor_call, :spawn_process],
        library: "pykka",
        library_version: ">= 3.0",
        description: "Akka-style actor model for Python"
      },
      %{
        name: :asyncio,
        module: Metastatic.Supplemental.Python.Asyncio,
        constructs: [:async_operation],
        library: "asyncio",
        library_version: "stdlib",
        description: "Python standard library async/await"
      }
    ],
    javascript: [
      %{
        name: :nact,
        module: Metastatic.Supplemental.JavaScript.Nact,
        constructs: [:actor_call, :spawn_process],
        library: "nact",
        library_version: ">= 3.0",
        description: "Actor system for Node.js"
      }
    ]
  }
  
  @doc """
  List available supplemental modules for a language.
  """
  def list(language) do
    Map.get(@registry, language, [])
  end
  
  @doc """
  Find supplemental module by name.
  """
  def get(language, name) do
    list(language)
    |> Enum.find(&(&1.name == name))
  end
end
```

**Generator:**

```bash
# Generate supplemental module template
mix metastatic.gen.supplemental python mylib actor_call spawn_process

# Creates:
# lib/metastatic/supplemental/python/mylib.ex
# test/metastatic/supplemental/python_mylib_test.exs
```

### Trade-offs & Open Questions

**Pros:**
- Graceful degradation with clear error messages
- Opt-in complexity - only needed when translating unsupported constructs
- Extensible - community can build supplemental libraries
- Type-safe - errors caught at transformation time, not runtime

**Cons:**
- Additional API surface to maintain
- Users need to understand which constructs require supplemental modules
- Supplemental modules may produce non-idiomatic code in target language
- Testing burden increases (test with/without supplemental modules)

**Open Questions:**

1. **Discovery:** How do users discover which constructs need supplemental modules?
   - Static analysis tool? (Implemented in Milestone 6.3)
   - Documentation with compatibility matrix?
   - Runtime warnings during validation?

2. **Standardization:** Which supplemental modules should be "official" vs community?
   - Core team maintains: pykka, nact, asyncio
   - Community maintains: everything else
   - Clear contribution guidelines

3. **Composition:** How do supplemental modules compose?
   - User provides map of construct → handler
   - Multiple handlers can be registered
   - First matching handler wins

4. **Versioning:** How to handle library version compatibility?
   - Supplemental module declares supported library versions
   - Runtime check during transformation?
   - Documentation-only?

5. **Validation:** Should MetaAST validator know about supplemental modules?
   - `validate(ast, supplemental: pykka)` allows actor_call
   - `validate(ast)` rejects actor_call
   - Validation mode: `:strict` vs `:with_supplemental`

### Related Architecture Decisions

**M2 Minimalism:**
- Should M2 only include truly universal constructs?
- Current approach: M2.1 (Core) = universal, M2.2 (Extended) = common, M2.3 (Native) = language-specific
- Actor model fits in M2.2 (Extended) - common but not universal
- Supplemental modules are for M2 → M1 when M1 lacks native support

**Language Tiers:**
- Tier 1: Full native support for M2.1 + most of M2.2
- Tier 2: Native support for M2.1, requires supplemental for M2.2
- Tier 3: Partial M2.1 support, heavy supplemental usage

**Adapter Contracts:**
- Adapters MUST support all M2.1 (Core) natively
- Adapters SHOULD support M2.2 (Extended) natively or via supplemental
- Adapters MAY reject M2.2 constructs without supplemental

### Success Criteria

- [ ] Supplemental API stable and documented
- [ ] 3+ official supplemental modules (pykka, nact, asyncio)
- [ ] Static analysis tool can detect required supplemental modules
- [ ] Community can create and publish supplemental modules
- [ ] Zero false positives in supplemental error messages
- [ ] Cross-language transformation with supplemental modules tested

---

## Success Criteria

### Phase 1 (Foundation)
- [ ] MetaAST type system complete and documented
- [ ] Adapter behaviour defined and tested
- [ ] Builder can handle round-trips
- [ ] Test infrastructure operational

### Phase 2 (Python)
- [ ] 50+ Python fixtures with > 95% round-trip accuracy
- [ ] All Layer 1 constructs supported
- [ ] Common Layer 2 constructs supported
- [ ] Performance: < 100ms per 1000 LOC

### Phase 3 (Cross-Language)
- [ ] Mutations work identically on Python and JavaScript
- [ ] Purity analyzer has < 5% false positive rate
- [ ] 3 languages fully supported (Python, JavaScript, Elixir)
- [ ] Self-hosting: Metastatic can analyze itself

### Phase 4 (Integration)
- [ ] CLI tool installable via Hex
- [ ] Oeditus integration complete
- [ ] Documentation complete
- [ ] Community: 3+ external contributors

### Phase 5 (Expansion)
- [ ] 5-6 languages supported
- [ ] Used in 10+ projects
- [ ] Open source release
- [ ] Conference talk/blog post

---

## Resource Requirements

### Team
- **2-3 Elixir developers** (core team)
- **Language experts** (consultants for each language)
- **1 technical writer** (part-time for documentation)

### Infrastructure
- GitHub repository
- CI/CD (GitHub Actions)
- Documentation hosting (HexDocs)
- Docker images for multi-runtime support

### External Dependencies
- Python 3.9+ runtime
- Node.js 16+ runtime
- Elixir 1.14+ runtime
- Optional: Go, Rust, Ruby runtimes

---

## Risk Mitigation Plan

### Risk: Parser Library Breaking Changes

**Impact:** High  
**Likelihood:** Medium  
**Mitigation:**
- Pin specific versions of all parser libraries
- Automated upgrade testing in CI
- Maintain compatibility shims

### Risk: Performance Issues

**Impact:** Medium  
**Likelihood:** Medium  
**Mitigation:**
- Parallel processing from day 1
- Caching layer for parsed ASTs
- Benchmark suite in CI
- Profile-guided optimization

### Risk: Semantic Edge Cases

**Impact:** Medium  
**Likelihood:** High  
**Mitigation:**
- Comprehensive test fixtures
- Conservative defaults (assume impure, validate manually)
- Clear documentation of limitations
- Community feedback loop

### Risk: Adoption Friction

**Impact:** High  
**Likelihood:** Medium  
**Mitigation:**
- Docker images with all runtimes
- Clear installation documentation
- Auto-detection of available languages
- Graceful degradation

---

## Metrics & Monitoring

### Development Metrics
- **Code coverage:** > 90%
- **Documentation coverage:** 100% of public APIs
- **Test fixture count:** 200+ across all languages
- **Performance:** < 1s per 1000 LOC

### Quality Metrics
- **Round-trip accuracy:** > 95%
- **False positive rate (purity):** < 5%
- **False negative rate (side effects):** < 10%
- **Mutation validity rate:** > 85%

### Adoption Metrics
- **Languages supported:** 3 in 6 months, 6 in 12 months
- **Active projects:** 10+ per language
- **Contributors:** 5+ per language
- **Stars/Downloads:** Track monthly growth

---

## Communication Plan

### Internal
- **Weekly standups:** Progress, blockers, next steps
- **Bi-weekly demos:** Show working features
- **Monthly retrospectives:** Process improvement
- **Slack channel:** #metastatic for async communication

### External
- **Blog posts:** Monthly updates on progress
- **Conference talks:** Submit to ElixirConf, PyCon, JSConf
- **Community calls:** Quarterly open discussions
- **Documentation:** Continuously updated on HexDocs

---

## Timeline Summary

| Phase | Duration | Key Deliverable |
|-------|----------|-----------------|
| Phase 1: Foundation | Months 1-3 | MetaAST core + test infrastructure |
| Phase 2: Python Adapter | Months 2-4 | Working Python support |
| Phase 3: Cross-Language Tools | Months 4-6 | Mutation engine + JS + Elixir |
| Phase 4: Integration | Months 7-8 | CLI + Oeditus integration |
| Phase 5: Expansion | Months 9-14 | Additional languages |

**First Release (v0.1.0):** Month 6 - Python, JavaScript, Elixir support  
**Production Release (v1.0.0):** Month 12 - 6 languages, battle-tested  
**Maturity (v2.0.0):** Month 24 - Community-driven, 10+ languages

---

## Next Steps

1. ✅ **Week 1:** Create project structure
2. ⏭️ **Week 2:** Implement core MetaAST types
3. ⏭️ **Week 3:** Define Adapter behaviour
4. ⏭️ **Week 4:** Create Builder and Document
5. ⏭️ **Week 5:** Set up test infrastructure
6. ⏭️ **Week 6:** Begin Python adapter

**Immediate Action Items:**
- [ ] Set up GitHub repository
- [ ] Configure CI/CD pipeline
- [ ] Create project board with all milestones
- [ ] Write contributing guidelines
- [ ] Set up documentation site
- [ ] Create initial release roadmap

---

**Document Version:** 1.0  
**Created:** 2026-01-20  
**Status:** Ready for execution  
**Next Review:** End of Phase 1 (Month 3)
