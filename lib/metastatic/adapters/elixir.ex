defmodule Metastatic.Adapters.Elixir do
  @moduledoc """
  Elixir language adapter for MetaAST transformations.

  Bridges between Elixir AST (M1) and MetaAST (M2), enabling cross-language
  code analysis and transformation for Elixir source code.

  ## Elixir AST Structure (M1)

  Elixir represents AST as three-element tuples:

      {form, metadata, arguments}

  Where:
  - `form` is an atom representing the syntactic construct
  - `metadata` is a keyword list with line numbers and other info
  - `arguments` vary by construct type

  ### Examples

      # Variable
      {:x, [], nil}

      # Addition
      {:+, [], [{:x, [], nil}, 5]}

      # Function call
      {:foo, [], [arg1, arg2]}

      # If expression
      {:if, [], [condition, [do: then_clause, else: else_clause]]}

  ## M1 ↔ M2 Transformations

  This adapter performs bidirectional transformations between Elixir AST (M1)
  and MetaAST (M2):

  ### Literals

      # M1 → M2
      42                          → {:literal, :integer, 42}
      3.14                        → {:literal, :float, 3.14}
      "hello"                     → {:literal, :string, "hello"}
      true                        → {:literal, :boolean, true}
      nil                         → {:literal, :null, nil}
      :atom                       → {:literal, :symbol, :atom}

  ### Variables

      {:x, [], Elixir}            → {:variable, "x"}

  ### Binary Operations

      {:+, _, [left, right]}      → {:binary_op, :arithmetic, :+, left, right}
      {:==, _, [left, right]}     → {:binary_op, :comparison, :==, left, right}
      {:and, _, [left, right]}    → {:binary_op, :boolean, :and, left, right}

  ### Function Calls

      {:foo, _, [a, b]}           → {:function_call, "foo", [a, b]}

  ### Conditionals

      {:if, _, [cond, [do: t]]}   → {:conditional, cond, t, nil}

  ## Round-Trip Fidelity

  The adapter achieves >95% round-trip fidelity for M2.1 (Core) constructs.
  Metadata preserves information like:
  - Line numbers
  - Variable contexts
  - Formatting hints

  ## Usage

      # Parse Elixir source
      {:ok, ast} = Metastatic.Adapters.Elixir.parse("x + 5")

      # Transform to MetaAST
      {:ok, meta_ast, metadata} = Metastatic.Adapters.Elixir.to_meta(ast)

      # Transform back to Elixir AST
      {:ok, ast2} = Metastatic.Adapters.Elixir.from_meta(meta_ast, metadata)

      # Unparse to source
      {:ok, source} = Metastatic.Adapters.Elixir.unparse(ast2)

  ## Theory

  This adapter implements the Galois connection:

      α_Elixir: AS_Elixir → MetaAST × Metadata
      ρ_Elixir: MetaAST × Metadata → AS_Elixir

  Where:
  - `α_Elixir` is `to_meta/1` (abstraction)
  - `ρ_Elixir` is `from_meta/2` (reification)
  """

  @behaviour Metastatic.Adapter

  alias Metastatic.Adapters.Elixir.{FromMeta, ToMeta}

  @impl true
  def parse(source) when is_binary(source) do
    case Code.string_to_quoted(source) do
      {:ok, ast} ->
        {:ok, ast}

      {:error, {meta, message, token}} ->
        line = Keyword.get(meta, :line, 0)
        column = Keyword.get(meta, :column, 0)
        {:error, "Syntax error at line #{line}, column #{column}: #{message}#{token}"}
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
  rescue
    e -> {:error, "Unparse failed: #{Exception.message(e)}"}
  end

  @impl true
  def file_extensions do
    [".ex", ".exs"]
  end
end
