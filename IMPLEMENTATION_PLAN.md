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
- [ ] Define MetaAST.Adapter behaviour (M1 ↔ M2 transformations)
- [ ] Create adapter registry with conformance validation
- [ ] Implement M1 → M2 → M1 round-trip testing framework

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
- [ ] Implement MetaAST.Builder
- [ ] Implement MetaAST.Document
- [ ] Round-trip testing framework

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
- [ ] Test fixture framework
- [ ] Round-trip test generator
- [ ] Benchmark suite
- [ ] CI/CD setup

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

## Phase 2: Language Adapters - BEAM Ecosystem (Months 2-3)

### Strategic Rationale: Elixir First

We're starting with Elixir (then Erlang) rather than Python for several key reasons:

1. **Zero External Dependencies**: Direct access to `Code.string_to_quoted!/2` and `Macro.to_string/1` - no parser subprocess needed
2. **Type System Alignment**: Elixir AST is already tuple-based, matching MetaAST structure exactly
3. **Dogfooding**: Building the first adapter in the same language as the meta-library enables rapid iteration on the `Metastatic.Adapter` behaviour
4. **Trivial Round-Trip Validation**: Native quote/unquote cycle makes testing straightforward
5. **Erlang Comes ~80% Free**: Shared BEAM tuple structure means second adapter is minimal delta
6. **Immediate Practical Value**: Enables muex/propwise cross-language support (original motivation)

Once the BEAM ecosystem is proven (Weeks 13-20), Python adapter (Weeks 21-28) will benefit from battle-tested M2 design.

### Milestone 2.1: Elixir Adapter - Foundation (Weeks 13-16)

**Deliverables:**
- [ ] Elixir AST → MetaAST transformer (M1 → M2)
- [ ] MetaAST → Elixir AST transformer (M2 → M1)
- [ ] Parse/unparse using native `Code` module
- [ ] Register adapter in Adapter.Registry

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
  
  Elixir represents AST as three-element tuples:
  ```elixir
  {form, metadata, arguments}
  ```
  
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

### Milestone 2.2: Elixir Adapter - Core Constructs (Weeks 17-18)

**Deliverables:**
- [ ] Handle all M2.1 (Core) constructs: literals, variables, binary_op, unary_op, function_call, conditional, block, early_return
- [ ] Handle M2.2 (Extended) constructs: lambda, collection_op (Enum.map/filter/reduce)
- [ ] 30+ test fixtures covering Elixir patterns
- [ ] Round-trip accuracy >95%

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

### Milestone 2.3: Erlang Adapter (Weeks 19-20)

**Deliverables:**
- [ ] Erlang AST → MetaAST transformer
- [ ] MetaAST → Erlang AST transformer  
- [ ] Parse using `:erl_scan` + `:erl_parse`
- [ ] Unparse using `:erl_prettypr`
- [ ] 20+ Erlang test fixtures

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

## Phase 3: Python Adapter (Weeks 21-28)

### Milestone 3.1: Python Parser Integration (Weeks 21-23)

**Deliverables:**
- [ ] Python helper script for AST parsing  
- [ ] JSON serialization of Python AST
- [ ] Subprocess-based communication
- [ ] Elixir wrapper with error handling

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

### Milestone 3.2: Python AST Transformation (Weeks 24-26)

**Deliverables:**
- [ ] Python AST → MetaAST (M1 → M2)
- [ ] MetaAST → Python AST (M2 → M1)
- [ ] Handle M2.1 core constructs
- [ ] Handle Python-specific patterns (list comprehensions, decorators)

**Key Transformations:**
- `ast.BinOp` → `{:binary_op, category, op, left, right}`
- `ast.Name` → `{:variable, name}`
- `ast.Constant` → `{:literal, type, value}`
- `ast.ListComp` → `{:collection_op, :map, lambda, collection}` (with optional filter)
- `ast.For`/`ast.While` → `{:loop, kind, condition, body}`

### Milestone 3.3: Python Round-Trip Testing (Weeks 27-28)

**Deliverables:**
- [ ] 40+ Python test fixtures
- [ ] Round-trip accuracy >90% (Python's AST lossy for formatting)
- [ ] Cross-language validation: same MetaAST from semantically equivalent Elixir/Erlang/Python

**Test Coverage:**
- Arithmetic, comparisons, boolean logic
- List/dict comprehensions
- Function definitions (def, lambda)
- Conditionals (if/elif/else)
- Loops (for, while, break, continue)
- Exception handling (try/except/finally)
- Decorators (as `language_specific`)

---

## Phase 4: Cross-Language Tools (Months 4-6)

### Milestone 4.1: Mutation Engine (Weeks 29-32)

**Deliverables:**
- [ ] Core mutators (arithmetic, comparison, boolean)
- [ ] Extended mutators (collection ops, conditionals)
- [ ] Mutation validation per language
- [ ] Mutation test framework

**Files to Create:**
```
lib/metastatic/
├── mutator.ex              # Core mutation engine
├── mutators/
│   ├── arithmetic.ex       # Arithmetic mutations
│   ├── comparison.ex       # Comparison mutations
│   ├── boolean.ex          # Boolean mutations
│   ├── conditional.ex      # Conditional mutations
│   └── collection.ex       # Collection mutations
└── mutation_validator.ex   # Validate mutations
```

**Implementation:**

```elixir
# lib/metastatic/mutators/arithmetic.ex
defmodule Metastatic.Mutators.Arithmetic do
  @moduledoc """
  Arithmetic operator mutations.
  Works for ALL supported languages.
  """
  
  @mutations [
    {:+, :-},
    {:-, :+},
    {:*, :/},
    {:/, :*},
    {:%, :*}
  ]
  
  def mutate(ast) do
    Enum.flat_map(@mutations, fn {from, to} ->
      mutate_operator(ast, from, to)
    end)
  end
  
  defp mutate_operator(ast, from, to) do
    mutations = []
    
    transformed = Macro.postwalk(ast, fn
      {:binary_op, :arithmetic, ^from, left, right} = node ->
        mutations = [{:binary_op, :arithmetic, to, left, right} | mutations]
        node
      
      node ->
        node
    end)
    
    mutations
  end
end
```

### Milestone 3.2: Purity Analyzer (Weeks 29-30)

**Deliverables:**
- [ ] Side effect detection
- [ ] Pure function identification
- [ ] Known pure function registry
- [ ] Language-specific side effect patterns

**Files to Create:**
```
lib/metastatic/
├── purity_analyzer.ex      # Main analyzer
└── side_effects/
    ├── core.ex             # Core side effects
    ├── python.ex           # Python-specific
    └── javascript.ex       # JavaScript-specific
```

### Milestone 3.3: JavaScript Adapter (Weeks 31-36)

**Deliverables:**
- [ ] Babel parser integration
- [ ] JavaScript → MetaAST transformer
- [ ] MetaAST → JavaScript transformer
- [ ] 50+ JavaScript test fixtures
- [ ] Cross-language mutation tests

**Validate:**
- Same mutation applied to Python and JavaScript produces equivalent behavior
- Purity analyzer works identically on both languages
- Round-trip accuracy > 95%

### Milestone 3.4: Elixir Adapter (Weeks 37-40)

**Deliverables:**
- [ ] Elixir AST → MetaAST transformer
- [ ] MetaAST → Elixir AST transformer
- [ ] Self-hosting tests
- [ ] Dogfooding: Use Metastatic to analyze itself

**Self-Hosting Validation:**
```elixir
# Can Metastatic analyze its own code?
{:ok, doc} = Metastatic.Builder.from_source(
  File.read!("lib/metastatic/ast.ex"),
  :elixir
)

mutations = Metastatic.Mutator.arithmetic_inverse(doc.ast)
assert length(mutations) > 0
```

---

## Phase 4: Integration & Tooling (Months 7-8)

### Milestone 4.1: CLI Tool (Weeks 41-44)

**Deliverables:**
- [ ] Command-line interface
- [ ] Mutation testing command
- [ ] Purity analysis command
- [ ] Complexity metrics command

**CLI Design:**

```bash
# Analyze purity
metastatic analyze --purity my_file.py

# Run mutation testing
metastatic mutate --language python --test-command "pytest" src/

# Show complexity metrics
metastatic complexity --threshold 10 src/

# Convert between languages (experimental)
metastatic translate --from python --to javascript my_file.py
```

### Milestone 4.2: Oeditus Integration (Weeks 45-48)

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
