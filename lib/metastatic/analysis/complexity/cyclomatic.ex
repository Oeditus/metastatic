defmodule Metastatic.Analysis.Complexity.Cyclomatic do
  @moduledoc """
  Cyclomatic complexity calculation (McCabe metric).

  Cyclomatic complexity measures the number of linearly independent paths
  through a program's source code. It is calculated as the number of
  decision points plus one.

  ## 3-Tuple Format

  All MetaAST nodes use the uniform 3-tuple structure:
  `{type_atom, keyword_meta, children_or_value}`

  ## Decision Points

  - `conditional` - if/else statements (+1)
  - `loop` - while/for loops (+1)
  - `binary_op` with `:boolean` and `:or`/`:and` operators (+1 each)
  - `exception_handling` - try/catch blocks (+1 per catch clause)
  - `pattern_match` - case statements (+1 per branch)

  ## Thresholds

  - 1-10: Simple, low risk
  - 11-20: More complex, moderate risk
  - 21-50: Complex, high risk
  - 51+: Untestable, very high risk

  ## Examples

      # Simple sequence: complexity = 1
      iex> ast = {:literal, [subtype: :integer], 42}
      iex> Metastatic.Analysis.Complexity.Cyclomatic.calculate(ast)
      1

      # Single conditional: complexity = 2
      iex> ast = {:conditional, [], [{:variable, [], "x"}, {:literal, [subtype: :integer], 1}, {:literal, [subtype: :integer], 2}]}
      iex> Metastatic.Analysis.Complexity.Cyclomatic.calculate(ast)
      2

      # Conditional with loop: complexity = 3
      iex> ast = {:conditional, [], [
      ...>   {:variable, [], "x"},
      ...>   {:loop, [loop_type: :while], [{:variable, [], "y"}, {:literal, [subtype: :integer], 1}]},
      ...>   {:literal, [subtype: :integer], 2}]}
      iex> Metastatic.Analysis.Complexity.Cyclomatic.calculate(ast)
      3
  """

  alias Metastatic.AST

  @doc """
  Calculates cyclomatic complexity for a MetaAST node.

  Returns the complexity as a non-negative integer (minimum 1).

  ## Examples

      iex> ast = {:binary_op, [category: :arithmetic, operator: :+], [{:variable, [], "x"}, {:literal, [subtype: :integer], 5}]}
      iex> Metastatic.Analysis.Complexity.Cyclomatic.calculate(ast)
      1

      iex> ast = {:conditional, [], [
      ...>   {:variable, [], "condition"},
      ...>   {:literal, [subtype: :integer], 1},
      ...>   {:literal, [subtype: :integer], 2}]}
      iex> Metastatic.Analysis.Complexity.Cyclomatic.calculate(ast)
      2
  """
  @spec calculate(AST.meta_ast()) :: non_neg_integer()
  def calculate(ast) do
    1 + count_decision_points(ast)
  end

  # Private implementation

  defp count_decision_points(ast) do
    walk(ast, 0)
  end

  # Conditional (3-tuple): +1 decision point
  defp walk({:conditional, _meta, [cond_expr, then_br, else_br]}, count) do
    count = count + 1
    count = walk(cond_expr, count)
    count = walk(then_br, count)
    walk(else_br, count)
  end

  # Loop (3-tuple): +1 decision point
  defp walk({:loop, meta, children}, count) when is_list(meta) do
    loop_type = Keyword.get(meta, :loop_type)
    count = count + 1

    case {loop_type, children} do
      {:while, [cond_expr, body]} ->
        count = walk(cond_expr, count)
        walk(body, count)

      {_, [iter, coll, body]} ->
        count = walk(iter, count)
        count = walk(coll, count)
        walk(body, count)

      _ ->
        Enum.reduce(children, count, fn child, c -> walk(child, c) end)
    end
  end

  # Binary operators (3-tuple)
  defp walk({:binary_op, meta, [left, right]}, count) when is_list(meta) do
    category = Keyword.get(meta, :category)
    op = Keyword.get(meta, :operator)

    count =
      if category == :boolean and op in [:and, :or] do
        count + 1
      else
        count
      end

    count = walk(left, count)
    walk(right, count)
  end

  # Unary operator (3-tuple)
  defp walk({:unary_op, _meta, [operand]}, count) do
    walk(operand, count)
  end

  # Exception handling (3-tuple): +1 per catch clause
  defp walk({:exception_handling, _meta, [try_block, catches, else_block]}, count) do
    catches_list = if is_list(catches), do: catches, else: []
    count = count + length(catches_list)
    count = walk(try_block, count)
    count = Enum.reduce(catches_list, count, fn catch_clause, c -> walk(catch_clause, c) end)
    walk(else_block, count)
  end

  # Pattern match (3-tuple): +1 per branch
  defp walk({:pattern_match, _meta, [value, branches | _]}, count) do
    branches_list = if is_list(branches), do: branches, else: []
    count = count + length(branches_list)
    count = walk(value, count)

    Enum.reduce(branches_list, count, fn
      {:match_arm, _, [_pattern, _guard, body]}, c -> walk(body, c)
      {:pair, _, [_pattern, branch]}, c -> walk(branch, c)
      {_pattern, branch}, c -> walk(branch, c)
      other, c -> walk(other, c)
    end)
  end

  # Match arm (3-tuple)
  defp walk({:match_arm, _meta, [_pattern, guard, body]}, count) do
    count = if guard, do: walk(guard, count), else: count
    walk(body, count)
  end

  # Block (3-tuple): walk statements
  defp walk({:block, _meta, stmts}, count) when is_list(stmts) do
    Enum.reduce(stmts, count, fn stmt, c -> walk(stmt, c) end)
  end

  # Function call (3-tuple): walk arguments
  defp walk({:function_call, _meta, args}, count) when is_list(args) do
    Enum.reduce(args, count, fn arg, c -> walk(arg, c) end)
  end

  # Lambda (3-tuple): walk body
  defp walk({:lambda, _meta, [body]}, count) do
    walk(body, count)
  end

  # Collection operations (3-tuple)
  defp walk({:collection_op, _meta, children}, count) when is_list(children) do
    Enum.reduce(children, count, fn child, c -> walk(child, c) end)
  end

  # Assignment (3-tuple)
  defp walk({:assignment, _meta, [target, value]}, count) do
    count = walk(target, count)
    walk(value, count)
  end

  # Inline match (3-tuple)
  defp walk({:inline_match, _meta, [pattern, value]}, count) do
    count = walk(pattern, count)
    walk(value, count)
  end

  # Early return (3-tuple)
  defp walk({:early_return, _meta, [value]}, count) do
    walk(value, count)
  end

  # List (3-tuple)
  defp walk({:list, _meta, elems}, count) when is_list(elems) do
    Enum.reduce(elems, count, fn elem, c -> walk(elem, c) end)
  end

  # Map (3-tuple)
  defp walk({:map, _meta, pairs}, count) when is_list(pairs) do
    Enum.reduce(pairs, count, fn
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

  # Async operation (3-tuple)
  defp walk({:async_operation, _meta, [body]}, count) do
    walk(body, count)
  end

  # M2.2s: Structural/Organizational types (3-tuple format)
  # Container: walk body
  defp walk({:container, _meta, [body]}, count) do
    if is_list(body) do
      Enum.reduce(body, count, fn member, c -> walk(member, c) end)
    else
      walk(body, count)
    end
  end

  # Function definition (3-tuple): walk body
  defp walk({:function_def, meta, [body]}, count) when is_list(meta) do
    params = Keyword.get(meta, :params, [])

    # Walk parameters (for pattern params with embedded conditionals)
    count =
      Enum.reduce(params, count, fn
        {:param, meta, _name}, c when is_list(meta) ->
          pattern = Keyword.get(meta, :pattern)
          default = Keyword.get(meta, :default)
          c = if pattern, do: walk(pattern, c), else: c
          if default, do: walk(default, c), else: c

        _simple_param, c ->
          c
      end)

    # Walk guards if present in meta
    count =
      case Keyword.get(meta, :guards) do
        nil -> count
        guard -> walk(guard, count)
      end

    # Walk body
    walk(body, count)
  end

  # Attribute access (3-tuple): walk receiver
  defp walk({:attribute_access, _meta, [receiver, _attribute]}, count) do
    walk(receiver, count)
  end

  # Augmented assignment (3-tuple): walk target and value
  defp walk({:augmented_assignment, _meta, [target, value]}, count) do
    count = walk(target, count)
    walk(value, count)
  end

  # Property (3-tuple): walk getter and setter
  defp walk({:property, _meta, [getter, setter]}, count) do
    count = if getter, do: walk(getter, count), else: count
    if setter, do: walk(setter, count), else: count
  end

  # Language-specific (3-tuple)
  defp walk({:language_specific, meta, native_ast}, count) when is_list(meta) do
    # If native_ast is a map with body, traverse it
    case native_ast do
      %{body: body} when not is_nil(body) -> walk(body, count)
      _ -> count
    end
  end

  # Literals and variables (3-tuple): no decision points
  defp walk({:literal, _meta, _value}, count), do: count
  defp walk({:variable, _meta, _name}, count), do: count

  # Pair (3-tuple) - for map entries, pattern match branches, etc.
  defp walk({:pair, _meta, [key, value]}, count) do
    count = walk(key, count)
    walk(value, count)
  end

  # Nil (else branch)
  defp walk(nil, count), do: count

  # Fallback for unknown nodes
  defp walk(_, count), do: count
end
