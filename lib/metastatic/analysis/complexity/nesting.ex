defmodule Metastatic.Analysis.Complexity.Nesting do
  @moduledoc """
  Maximum nesting depth calculation.

  Nesting depth measures how many levels deep the code is nested, which
  affects readability and maintainability. Deeply nested code is harder
  to understand and reason about.

  ## 3-Tuple Format

  All MetaAST nodes use the uniform 3-tuple structure:
  `{type_atom, keyword_meta, children_or_value}`

  ## What Increases Nesting

  - `conditional` branches
  - `loop` bodies
  - `lambda` bodies
  - `exception_handling` blocks
  - Nested `block` structures (when inside above)

  ## Thresholds

  - 0-2: Good, easy to understand
  - 3-4: Moderate, acceptable
  - 5+: High, should be refactored

  ## Examples

      # No nesting: depth = 0
      iex> ast = {:literal, [subtype: :integer], 42}
      iex> Metastatic.Analysis.Complexity.Nesting.calculate(ast)
      0

      # Single conditional: depth = 1
      iex> ast = {:conditional, [], [{:variable, [], "x"}, {:literal, [subtype: :integer], 1}, {:literal, [subtype: :integer], 2}]}
      iex> Metastatic.Analysis.Complexity.Nesting.calculate(ast)
      1

      # Nested conditional: depth = 2
      iex> ast = {:conditional, [], [
      ...>   {:variable, [], "x"},
      ...>   {:conditional, [], [{:variable, [], "y"}, {:literal, [subtype: :integer], 1}, {:literal, [subtype: :integer], 2}]},
      ...>   {:literal, [subtype: :integer], 3}]}
      iex> Metastatic.Analysis.Complexity.Nesting.calculate(ast)
      2
  """

  alias Metastatic.AST

  @doc """
  Calculates maximum nesting depth for a MetaAST node.

  Returns the depth as a non-negative integer (minimum 0).

  ## Examples

      iex> ast = {:binary_op, [category: :arithmetic, operator: :+], [{:variable, [], "x"}, {:literal, [subtype: :integer], 5}]}
      iex> Metastatic.Analysis.Complexity.Nesting.calculate(ast)
      0

      iex> ast = {:loop, [loop_type: :while], [{:variable, [], "condition"}, {:literal, [subtype: :integer], 1}]}
      iex> Metastatic.Analysis.Complexity.Nesting.calculate(ast)
      1
  """
  @spec calculate(AST.meta_ast()) :: non_neg_integer()
  def calculate(ast) do
    {_current, max} = walk(ast, 0, 0)
    max
  end

  # Private implementation

  # walk(ast, current_depth, max_depth) -> {current_depth, max_depth}

  # Conditional (3-tuple): increment depth for branches
  defp walk({:conditional, _meta, [cond_expr, then_br, else_br]}, current, max) do
    {_, max} = walk(cond_expr, current, max)
    {_, max} = walk(then_br, current + 1, max)
    {_, max} = walk(else_br, current + 1, max)
    {current, max}
  end

  # Loop (3-tuple): increment depth for body
  defp walk({:loop, meta, children}, current, max) when is_list(meta) do
    loop_type = Keyword.get(meta, :loop_type)

    case {loop_type, children} do
      {:while, [cond_expr, body]} ->
        {_, max} = walk(cond_expr, current, max)
        {_, max} = walk(body, current + 1, max)
        {current, max}

      {_, [iter, coll, body]} ->
        {_, max} = walk(iter, current, max)
        {_, max} = walk(coll, current, max)
        {_, max} = walk(body, current + 1, max)
        {current, max}

      _ ->
        {_, max} =
          Enum.reduce(children, {current, max}, fn child, {c, m} ->
            walk(child, c + 1, m)
          end)

        {current, max}
    end
  end

  # Binary operators (3-tuple): no depth change
  defp walk({:binary_op, _meta, [left, right]}, current, max) do
    {_, max} = walk(left, current, max)
    {_, max} = walk(right, current, max)
    {current, max}
  end

  # Unary operator (3-tuple)
  defp walk({:unary_op, _meta, [operand]}, current, max) do
    walk(operand, current, max)
  end

  # Exception handling (3-tuple): increment depth for blocks
  defp walk({:exception_handling, _meta, [try_block, catches, else_block]}, current, max) do
    {_, max} = walk(try_block, current + 1, max)

    catches_list = if is_list(catches), do: catches, else: []

    {_, max} =
      Enum.reduce(catches_list, {current, max}, fn
        {:catch_clause, _, [_type, _var, catch_body]}, {_c, m} ->
          walk(catch_body, current + 1, m)

        {_type, _var, catch_body}, {_c, m} ->
          walk(catch_body, current + 1, m)

        other, {_c, m} ->
          walk(other, current + 1, m)
      end)

    {_, max} = walk(else_block, current + 1, max)
    {current, max}
  end

  # Pattern match (3-tuple): increment depth for branches
  defp walk({:pattern_match, _meta, [value, branches | _]}, current, max) do
    {_, max} = walk(value, current, max)
    branches_list = if is_list(branches), do: branches, else: []

    {_, max} =
      Enum.reduce(branches_list, {current, max}, fn
        {:match_arm, _, [_pattern, _guard, body]}, {_c, m} ->
          walk(body, current + 1, m)

        {:pair, _, [_pattern, branch]}, {_c, m} ->
          walk(branch, current + 1, m)

        {_pattern, branch}, {_c, m} ->
          walk(branch, current + 1, m)

        other, {_c, m} ->
          walk(other, current, m)
      end)

    {current, max}
  end

  # Match arm (3-tuple): increment depth for body
  defp walk({:match_arm, _meta, [_pattern, guard, body]}, current, max) do
    {_, max} = if guard, do: walk(guard, current, max), else: {current, max}
    walk(body, current + 1, max)
  end

  # Block (3-tuple): walk statements at same depth
  defp walk({:block, _meta, stmts}, current, max) when is_list(stmts) do
    max = Enum.max([current, max])

    {_, max} =
      Enum.reduce(stmts, {current, max}, fn stmt, {c, m} ->
        walk(stmt, c, m)
      end)

    {current, max}
  end

  # Function call (3-tuple): walk arguments
  defp walk({:function_call, _meta, args}, current, max) when is_list(args) do
    {_, max} =
      Enum.reduce(args, {current, max}, fn arg, {c, m} ->
        walk(arg, c, m)
      end)

    {current, max}
  end

  # Lambda (3-tuple): increment depth for body
  defp walk({:lambda, _meta, [body]}, current, max) do
    {_, max} = walk(body, current + 1, max)
    {current, max}
  end

  # M2.2s: Structural/Organizational Types (3-tuple format)

  # Container: walk body at same depth
  defp walk({:container, _meta, [body]}, current, max) do
    max = Enum.max([current, max])

    {_, max} =
      if is_list(body) do
        Enum.reduce(body, {current, max}, fn member, {c, m} ->
          walk(member, c, m)
        end)
      else
        walk(body, current, max)
      end

    {current, max}
  end

  # Function definition (3-tuple): walk body
  defp walk({:function_def, meta, [body]}, current, max) when is_list(meta) do
    params = Keyword.get(meta, :params, [])

    # Walk parameters
    {_, max} =
      Enum.reduce(params, {current, max}, fn
        {:param, meta, _name}, {c, m} when is_list(meta) ->
          pattern = Keyword.get(meta, :pattern)
          default = Keyword.get(meta, :default)
          {_, m} = if pattern, do: walk(pattern, c, m), else: {c, m}
          if default, do: walk(default, c, m), else: {c, m}

        _simple_param, {c, m} ->
          {c, m}
      end)

    # Walk guards if present
    {_, max} =
      case Keyword.get(meta, :guards) do
        nil -> {current, max}
        guard -> walk(guard, current, max)
      end

    # Walk body with incremented depth (function introduces scope)
    walk(body, current + 1, max)
  end

  # Attribute access (3-tuple): walk object
  defp walk({:attribute_access, _meta, [obj, _attr]}, current, max) do
    walk(obj, current, max)
  end

  # Augmented assignment (3-tuple): walk value
  defp walk({:augmented_assignment, _meta, [_target, value]}, current, max) do
    walk(value, current, max)
  end

  # Property (3-tuple): walk getter and setter bodies
  defp walk({:property, _meta, [getter, setter]}, current, max) do
    {_, max} = if getter, do: walk(getter, current + 1, max), else: {current, max}
    {_, max} = if setter, do: walk(setter, current + 1, max), else: {current, max}
    {current, max}
  end

  # Collection operations (3-tuple)
  defp walk({:collection_op, _meta, children}, current, max) when is_list(children) do
    {_, max} =
      Enum.reduce(children, {current, max}, fn child, {c, m} ->
        walk(child, c, m)
      end)

    {current, max}
  end

  # Assignment (3-tuple)
  defp walk({:assignment, _meta, [target, value]}, current, max) do
    {_, max} = walk(target, current, max)
    {_, max} = walk(value, current, max)
    {current, max}
  end

  # Inline match (3-tuple)
  defp walk({:inline_match, _meta, [pattern, value]}, current, max) do
    {_, max} = walk(pattern, current, max)
    {_, max} = walk(value, current, max)
    {current, max}
  end

  # Early return (3-tuple)
  defp walk({:early_return, _meta, [value]}, current, max) do
    walk(value, current, max)
  end

  # List (3-tuple)
  defp walk({:list, _meta, elems}, current, max) when is_list(elems) do
    {_, max} =
      Enum.reduce(elems, {current, max}, fn elem, {c, m} ->
        walk(elem, c, m)
      end)

    {current, max}
  end

  # Map (3-tuple)
  defp walk({:map, _meta, pairs}, current, max) when is_list(pairs) do
    {_, max} =
      Enum.reduce(pairs, {current, max}, fn
        {:pair, _, [key, value]}, {c, m} ->
          {_, m} = walk(key, c, m)
          walk(value, c, m)

        {key, value}, {c, m} ->
          {_, m} = walk(key, c, m)
          walk(value, c, m)

        other, {c, m} ->
          walk(other, c, m)
      end)

    {current, max}
  end

  # Async operation (3-tuple)
  defp walk({:async_operation, _meta, [body]}, current, max) do
    walk(body, current, max)
  end

  # Language-specific (3-tuple)
  defp walk({:language_specific, meta, native_ast}, current, max) when is_list(meta) do
    case native_ast do
      %{body: body} when not is_nil(body) -> walk(body, current, max)
      _ -> {current, max}
    end
  end

  # Literals and variables (3-tuple): update max if current is higher
  defp walk({:literal, _meta, _value}, current, max), do: {current, Enum.max([current, max])}
  defp walk({:variable, _meta, _name}, current, max), do: {current, Enum.max([current, max])}

  # Pair (3-tuple)
  defp walk({:pair, _meta, [key, value]}, current, max) do
    {_, max} = walk(key, current, max)
    walk(value, current, max)
  end

  # Nil
  defp walk(nil, current, max), do: {current, max}

  # Fallback
  defp walk(_, current, max), do: {current, max}
end
