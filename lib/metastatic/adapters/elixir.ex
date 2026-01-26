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

        {:error,
         "Syntax error at line #{line}, column #{column}: #{inspect(message)}#{inspect(token)}"}
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

  @impl true
  def extract_children(ast) when is_tuple(ast) do
    case ast do
      # Module definition: {:defmodule, meta, [name, [do: body]]}
      {:defmodule, _meta, [_name, [do: body]]} ->
        [body]

      # Function definition: {:def/:defp, meta, [signature, [do: body]]}
      {func_type, _meta, [_signature, [do: body]]}
      when func_type in [:def, :defp, :defmacro, :defmacrop] ->
        [body]

      # Block: {:__block__, [], statements}
      {:__block__, _, statements} when is_list(statements) ->
        statements

      # Pipe operator: {:|>, meta, [left, right]}
      {:|>, _meta, [left, right]} ->
        [left, right]

      # Function call: {:function, meta, args}
      {func, _meta, args} when is_atom(func) and is_list(args) ->
        args

      # Remote call: {{:., meta1, [module, func]}, meta2, args}
      {{:., _meta1, [_module, _func]}, _meta2, args} when is_list(args) ->
        args

      # Match operator: {:=, meta, [left, right]}
      {:=, _meta, [left, right]} ->
        [left, right]

      # Try/rescue: {:try, meta, [[do: body, rescue: handlers]]}
      {:try, _meta, [[do: body, rescue: handlers]]} when is_list(handlers) ->
        [body | Enum.map(handlers, fn {:->, _, [_pattern, handler_body]} -> handler_body end)]

      # Module attribute: {:@, meta, [{name, meta2, [value]}]}
      {:@, _meta, [{_name, _meta2, [value]}]} ->
        [value]

      # List
      list when is_list(list) ->
        list

      # Literal or unknown - no children
      _ when is_atom(ast) or is_number(ast) or is_binary(ast) ->
        []

      # Other tuples - try to extract all elements except metadata
      {_tag, _meta, elements} when is_list(elements) ->
        elements

      _ ->
        []
    end
  end

  def extract_children(list) when is_list(list), do: list
  def extract_children(_), do: []
end
