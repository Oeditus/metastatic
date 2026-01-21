defmodule Metastatic.Adapters.Python do
  @moduledoc """
  Python language adapter for MetaAST transformations.

  Bridges between Python AST (M1) and MetaAST (M2), enabling cross-language
  code analysis and transformation for Python source code.

  ## Python AST Structure (M1)

  Python's `ast` module represents AST as nested dictionaries with a `_type` field:

      %{"_type" => "BinOp", "op" => %{"_type" => "Add"}, "left" => ..., "right" => ...}

  ### Examples

      # Integer literal
      %{"_type" => "Constant", "value" => 42}

      # Variable
      %{"_type" => "Name", "id" => "x", "ctx" => %{"_type" => "Load"}}

      # Addition
      %{"_type" => "BinOp",
        "op" => %{"_type" => "Add"},
        "left" => %{"_type" => "Name", "id" => "x"},
        "right" => %{"_type" => "Constant", "value" => 5}}

      # Function call
      %{"_type" => "Call",
        "func" => %{"_type" => "Name", "id" => "foo"},
        "args" => [...]}

  ## M1 ↔ M2 Transformations

  This adapter performs bidirectional transformations between Python AST (M1)
  and MetaAST (M2):

  ### Literals

      # M1 → M2
      %{"_type" => "Constant", "value" => 42}    → {:literal, :integer, 42}
      %{"_type" => "Constant", "value" => 3.14}  → {:literal, :float, 3.14}
      %{"_type" => "Constant", "value" => "hi"}  → {:literal, :string, "hi"}
      %{"_type" => "Constant", "value" => true}  → {:literal, :boolean, true}
      %{"_type" => "Constant", "value" => nil}   → {:literal, :null, nil}

  ### Variables

      %{"_type" => "Name", "id" => "x"}          → {:variable, "x"}

  ### Binary Operations

      BinOp(op=Add())                            → {:binary_op, :arithmetic, :+, left, right}
      Compare(ops=[Eq()])                        → {:binary_op, :comparison, :==, left, right}
      BoolOp(op=And())                           → {:binary_op, :boolean, :and, left, right}

  ### Function Calls

      Call(func=Name("foo"), args=[...])         → {:function_call, "foo", [...]}

  ### Conditionals

      If(test=..., body=..., orelse=...)         → {:conditional, test, body, orelse}
      IfExp(test=..., body=..., orelse=...)      → {:conditional, test, body, orelse}

  ## Communication Strategy

  Since Python parsing requires the `ast` module, this adapter uses subprocess
  communication:

  1. **Parse**: Spawn `priv/parsers/python/parser.py` → receives JSON AST
  2. **Unparse**: Spawn `priv/parsers/python/unparser.py` → receives source

  All communication uses stdin/stdout with JSON serialization.

  ## Round-Trip Fidelity

  Target >90% round-trip fidelity (Python's AST is lossy for formatting).
  Metadata preserves:
  - Line numbers (`lineno`, `col_offset`)
  - End positions (`end_lineno`, `end_col_offset`)

  ## Usage

      # Parse Python source
      {:ok, ast} = Metastatic.Adapters.Python.parse("x + 5")

      # Transform to MetaAST
      {:ok, meta_ast, metadata} = Metastatic.Adapters.Python.to_meta(ast)

      # Transform back to Python AST
      {:ok, ast2} = Metastatic.Adapters.Python.from_meta(meta_ast, metadata)

      # Unparse to source
      {:ok, source} = Metastatic.Adapters.Python.unparse(ast2)

  ## Theory

  This adapter implements the Galois connection:

      α_Python: AS_Python → MetaAST × Metadata
      ρ_Python: MetaAST × Metadata → AS_Python

  Where:
  - `α_Python` is `to_meta/1` (abstraction)
  - `ρ_Python` is `from_meta/2` (reification)

  Python and Elixir/Erlang produce semantically equivalent MetaAST for
  equivalent code:

      # Python: x + 5
      # Elixir: x + 5
      # Erlang: X + 5.
      # All → {:binary_op, :arithmetic, :+, {:variable, _}, {:literal, :integer, 5}}
  """

  @behaviour Metastatic.Adapter

  alias Metastatic.Adapters.Python.{Subprocess, ToMeta, FromMeta}

  @impl true
  def parse(source) when is_binary(source) do
    Subprocess.parse(source)
  end

  @impl true
  def to_meta(python_ast) do
    ToMeta.transform(python_ast)
  end

  @impl true
  def from_meta(meta_ast, metadata) do
    FromMeta.transform(meta_ast, metadata)
  end

  @impl true
  def unparse(python_ast) do
    Subprocess.unparse(python_ast)
  end

  @impl true
  def file_extensions do
    [".py", ".pyw"]
  end
end
