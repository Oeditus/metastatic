defmodule Metastatic.Adapters.Erlang do
  @moduledoc """
  Erlang language adapter for MetaAST transformations.

  Bridges between Erlang AST (M1) and MetaAST (M2), enabling cross-language
  code analysis and transformation for Erlang source code.

  ## Erlang AST Structure (M1)

  Erlang represents AST as tuples with specific structures. The format varies
  by construct but generally follows patterns like:

      {Type, Line, Value}
      {Type, Line, Left, Right}

  ### Examples

      # Integer literal
      {:integer, 1, 42}

      # Variable
      {:var, 1, :X}

      # Binary operation (addition)
      {:op, 1, :+, {:var, 1, :X}, {:integer, 1, 5}}

      # Function call
      {:call, 1, {:atom, 1, :foo}, [{:integer, 1, 1}, {:integer, 1, 2}]}

      # Case expression
      {:case, 1, {:var, 1, :X},
       [{:clause, 1, [{:integer, 1, 1}], [], [{:atom, 1, :ok}]}]}

  ## M1 ↔ M2 Transformations

  This adapter performs bidirectional transformations between Erlang AST (M1)
  and MetaAST (M2):

  ### Literals

      # M1 → M2
      {:integer, _, 42}           → {:literal, :integer, 42}
      {:float, _, 3.14}           → {:literal, :float, 3.14}
      {:string, _, 'hello'}       → {:literal, :string, "hello"}
      {:atom, _, true}            → {:literal, :boolean, true}
      {:atom, _, undefined}       → {:literal, :null, nil}

  ### Variables

      {:var, _, :X}               → {:variable, "X"}

  ### Binary Operations

      {:op, _, :+, left, right}   → {:binary_op, :arithmetic, :+, left, right}
      {:op, _, :==, left, right}  → {:binary_op, :comparison, :==, left, right}

  ### Function Calls

      {:call, _, func, args}      → {:function_call, "func", args}

  ## Round-Trip Fidelity

  The adapter achieves >90% round-trip fidelity for M2.1 (Core) constructs.
  Metadata preserves:
  - Line numbers
  - Variable names (case-sensitive)
  - Erlang-specific type information

  ## Usage

      # Parse Erlang source
      {:ok, ast} = Metastatic.Adapters.Erlang.parse("X + 5.")

      # Transform to MetaAST
      {:ok, meta_ast, metadata} = Metastatic.Adapters.Erlang.to_meta(ast)

      # Transform back to Erlang AST
      {:ok, ast2} = Metastatic.Adapters.Erlang.from_meta(meta_ast, metadata)

      # Unparse to source
      {:ok, source} = Metastatic.Adapters.Erlang.unparse(ast2)

  ## Theory

  This adapter implements the Galois connection:

      α_Erlang: AS_Erlang → MetaAST × Metadata
      ρ_Erlang: MetaAST × Metadata → AS_Erlang

  Where:
  - `α_Erlang` is `to_meta/1` (abstraction)
  - `ρ_Erlang` is `from_meta/2` (reification)
  """

  @behaviour Metastatic.Adapter

  alias Metastatic.Adapters.Erlang.{ToMeta, FromMeta}

  @impl true
  def parse(source) when is_binary(source) do
    # Erlang parsing pipeline:
    # 1. Tokenize with :erl_scan
    # 2. Parse expressions with :erl_parse
    charlist = String.to_charlist(source)

    with {:ok, tokens, _} <- :erl_scan.string(charlist),
         {:ok, exprs} <- :erl_parse.parse_exprs(tokens) do
      # For single expression, return it directly
      # For multiple expressions, return as list
      case exprs do
        [single] -> {:ok, single}
        multiple -> {:ok, {:block, multiple}}
      end
    else
      {:error, {_line, _module, reason}, _} ->
        {:error, "Syntax error: #{inspect(reason)}"}

      {:error, {_line, _module, reason}} ->
        {:error, "Parse error: #{inspect(reason)}"}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  @impl true
  def to_meta(erlang_ast) do
    ToMeta.transform(erlang_ast)
  end

  @impl true
  def from_meta(meta_ast, metadata) do
    FromMeta.transform(meta_ast, metadata)
  end

  @impl true
  def unparse(erlang_ast) do
    # Use erl_pp (Erlang pretty printer) to format the AST
    # Wrap in a function form for proper formatting
    try do
      # Convert single expression to iolist and then to string
      iolist = :erl_pp.expr(erlang_ast)
      result = IO.iodata_to_binary(iolist)
      {:ok, String.trim(result)}
    rescue
      e -> {:error, "Unparse failed: #{Exception.message(e)}"}
    end
  end

  @impl true
  def file_extensions do
    [".erl", ".hrl"]
  end
end
