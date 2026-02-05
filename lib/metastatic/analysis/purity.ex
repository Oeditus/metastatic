defmodule Metastatic.Analysis.Purity do
  @moduledoc """
  Function purity analysis at the MetaAST level.

  Analyzes code to determine if it's pure (no side effects) or impure
  (has side effects like I/O, mutations, random operations, etc.).

  Works across all supported languages by operating on the unified MetaAST
  representation.

  ## Purity Definition

  A **pure function**:
  - Always returns the same output for the same input (deterministic)
  - Has no side effects (no I/O, no mutations, no global state access)
  - Doesn't depend on external state

  An **impure function** has one or more of:
  - I/O operations (print, file access, network, database)
  - Mutations (modifying variables, especially in loops)
  - Non-deterministic operations (random, time/date)
  - Exception handling (raising/catching exceptions)

  ## Usage

      alias Metastatic.{Document, Analysis.Purity}

      # Analyze a document
      ast = {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}}
      doc = Document.new(ast, :elixir)
      {:ok, result} = Purity.analyze(doc)

      result.pure?              # => true
      result.effects            # => []
      result.confidence         # => :high
      result.summary            # => "Function is pure"

  ## Examples

      # Pure arithmetic
      iex> ast = {:binary_op, [category: :arithmetic, operator: :+], [{:literal, [subtype: :integer], 1}, {:literal, [subtype: :integer], 2}]}
      iex> doc = Metastatic.Document.new(ast, :python)
      iex> {:ok, result} = Metastatic.Analysis.Purity.analyze(doc)
      iex> result.pure?
      true

      # Impure I/O
      iex> ast = {:function_call, [name: "print"], [{:literal, [subtype: :string], "hello"}]}
      iex> doc = Metastatic.Document.new(ast, :python)
      iex> {:ok, result} = Metastatic.Analysis.Purity.analyze(doc)
      iex> result.pure?
      false
      iex> result.effects
      [:io]
  """

  alias Metastatic.Analysis.Purity.{Effects, Result}
  alias Metastatic.Document

  use Metastatic.Document.Analyzer,
    doc: """
    Analyzes a document for purity.

    Accepts either:
    - A `Metastatic.Document` struct
    - A `{language, native_ast}` tuple

    Returns `{:ok, result}` where result is a `Metastatic.Analysis.Purity.Result` struct.

    ## Examples

        # Using Document
        iex> ast = {:literal, [subtype: :integer], 42}
        iex> doc = Metastatic.Document.new(ast, :elixir)
        iex> {:ok, result} = Metastatic.Analysis.Purity.analyze(doc)
        iex> result.pure?
        true

        # Using {language, native_ast} tuple
        iex> python_ast = %{"_type" => "Constant", "value" => 42}
        iex> {:ok, result} = Metastatic.Analysis.Purity.analyze(:python, python_ast)
        iex> result.pure?
        true
    """

  @impl Metastatic.Document.Analyzer
  def handle_analyze(%Document{ast: ast}, _opts \\ []) do
    result =
      ast
      |> walk(%{in_loop: false, effects: [], locations: [], unknown: []})
      |> build_result()

    {:ok, result}
  end

  # Private implementation

  defp walk(ast, ctx) do
    # Detect effects in current node
    effects = Effects.detect(ast)
    ctx = add_effects(ctx, effects)

    # Recurse based on node type
    walk_node(ast, ctx)
  end

  # Binary op (3-tuple)
  defp walk_node({:binary_op, _meta, [left, right]}, ctx) do
    ctx = walk(left, ctx)
    walk(right, ctx)
  end

  # Unary op (3-tuple)
  defp walk_node({:unary_op, _meta, [operand]}, ctx), do: walk(operand, ctx)

  # Conditional (3-tuple)
  defp walk_node({:conditional, _meta, [cond_expr, then_br, else_br]}, ctx) do
    ctx = walk(cond_expr, ctx)
    ctx = walk(then_br, ctx)
    walk(else_br, ctx)
  end

  # Block (3-tuple)
  defp walk_node({:block, _meta, stmts}, ctx) when is_list(stmts) do
    Enum.reduce(stmts, ctx, fn stmt, c -> walk(stmt, c) end)
  end

  # Loop (3-tuple)
  defp walk_node({:loop, meta, children}, ctx) when is_list(meta) do
    loop_type = Keyword.get(meta, :loop_type)
    loop_ctx = %{ctx | in_loop: true}

    case {loop_type, children} do
      {:while, [cond_expr, body]} ->
        loop_ctx = walk(cond_expr, loop_ctx)
        walk(body, loop_ctx)

      {_, [iter, coll, body]} ->
        loop_ctx = walk(iter, loop_ctx)
        loop_ctx = walk(coll, loop_ctx)
        walk(body, loop_ctx)

      _ ->
        Enum.reduce(children, loop_ctx, fn child, c -> walk(child, c) end)
    end
  end

  # Assignment (3-tuple)
  defp walk_node({:assignment, _meta, [target, value]}, ctx) do
    ctx = if ctx.in_loop, do: add_effects(ctx, [:mutation]), else: ctx
    ctx = walk(target, ctx)
    walk(value, ctx)
  end

  # Inline match (3-tuple)
  defp walk_node({:inline_match, _meta, [pattern, value]}, ctx) do
    ctx = walk(pattern, ctx)
    walk(value, ctx)
  end

  # Function call (3-tuple)
  defp walk_node({:function_call, meta, args}, ctx) when is_list(meta) and is_list(args) do
    name = Keyword.get(meta, :name)

    ctx =
      if Effects.detect({:function_call, meta, args}) == [] and is_binary(name) do
        %{ctx | unknown: [name | ctx.unknown]}
      else
        ctx
      end

    Enum.reduce(args, ctx, fn arg, c -> walk(arg, c) end)
  end

  # Lambda (3-tuple)
  defp walk_node({:lambda, _meta, [body]}, ctx), do: walk(body, ctx)

  # Collection operations (3-tuple)
  defp walk_node({:collection_op, _meta, children}, ctx) when is_list(children) do
    Enum.reduce(children, ctx, fn child, c -> walk(child, c) end)
  end

  # Exception handling (3-tuple)
  defp walk_node({:exception_handling, _meta, [try_b, catches, else_b]}, ctx) do
    ctx = walk(try_b, ctx)
    catches_list = if is_list(catches), do: catches, else: []
    ctx = Enum.reduce(catches_list, ctx, fn catch_clause, c -> walk(catch_clause, c) end)
    walk(else_b, ctx)
  end

  # Early return (3-tuple)
  defp walk_node({:early_return, _meta, [value]}, ctx), do: walk(value, ctx)

  # List (3-tuple)
  defp walk_node({:list, _meta, elems}, ctx) when is_list(elems) do
    Enum.reduce(elems, ctx, fn elem, c -> walk(elem, c) end)
  end

  # Map (3-tuple)
  defp walk_node({:map, _meta, pairs}, ctx) when is_list(pairs) do
    Enum.reduce(pairs, ctx, fn
      {:pair, _, [key, value]}, c ->
        c = walk(key, c)
        walk(value, c)

      {key, value}, c ->
        c = walk(key, c)
        walk(value, c)

      other, c ->
        walk(other, c)
    end)
  end

  # Language-specific (3-tuple)
  defp walk_node({:language_specific, _meta, _native_ast}, ctx), do: ctx

  # Literals and variables (3-tuple)
  defp walk_node({:literal, _meta, _value}, ctx), do: ctx
  defp walk_node({:variable, _meta, _name}, ctx), do: ctx

  # Pair (3-tuple)
  defp walk_node({:pair, _meta, [key, value]}, ctx) do
    ctx = walk(key, ctx)
    walk(value, ctx)
  end

  # Nil
  defp walk_node(nil, ctx), do: ctx

  # Fallback
  defp walk_node(_, ctx), do: ctx

  defp add_effects(ctx, []), do: ctx
  defp add_effects(ctx, effects), do: %{ctx | effects: ctx.effects ++ effects}

  defp build_result(%{effects: [], unknown: []}), do: Result.pure()

  defp build_result(%{effects: [], unknown: unknown}) when unknown != [],
    do: Result.unknown(Enum.uniq(unknown))

  defp build_result(%{effects: effects, locations: _}), do: Result.impure(Enum.uniq(effects), [])
end
