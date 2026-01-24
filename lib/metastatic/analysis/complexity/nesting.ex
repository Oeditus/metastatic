defmodule Metastatic.Analysis.Complexity.Nesting do
  @moduledoc """
  Maximum nesting depth calculation.

  Nesting depth measures how many levels deep the code is nested, which
  affects readability and maintainability. Deeply nested code is harder
  to understand and reason about.

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
      iex> ast = {:literal, :integer, 42}
      iex> Metastatic.Analysis.Complexity.Nesting.calculate(ast)
      0

      # Single conditional: depth = 1
      iex> ast = {:conditional, {:variable, "x"}, {:literal, :integer, 1}, {:literal, :integer, 2}}
      iex> Metastatic.Analysis.Complexity.Nesting.calculate(ast)
      1

      # Nested conditional: depth = 2
      iex> ast = {:conditional, {:variable, "x"},
      ...>   {:conditional, {:variable, "y"}, {:literal, :integer, 1}, {:literal, :integer, 2}},
      ...>   {:literal, :integer, 3}}
      iex> Metastatic.Analysis.Complexity.Nesting.calculate(ast)
      2
  """

  alias Metastatic.AST

  @doc """
  Calculates maximum nesting depth for a MetaAST node.

  Returns the depth as a non-negative integer (minimum 0).

  ## Examples

      iex> ast = {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}}
      iex> Metastatic.Analysis.Complexity.Nesting.calculate(ast)
      0

      iex> ast = {:loop, :while, {:variable, "condition"}, {:literal, :integer, 1}}
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

  # Conditional: increment depth for branches
  defp walk({:conditional, cond, then_br, else_br}, current, max) do
    {_, max} = walk(cond, current, max)
    {_, max} = walk(then_br, current + 1, max)
    {_, max} = walk(else_br, current + 1, max)
    {current, max}
  end

  # Loop: increment depth for body
  defp walk({:loop, :while, cond, body}, current, max) do
    {_, max} = walk(cond, current, max)
    {_, max} = walk(body, current + 1, max)
    {current, max}
  end

  defp walk({:loop, _, iter, coll, body}, current, max) do
    {_, max} = walk(iter, current, max)
    {_, max} = walk(coll, current, max)
    {_, max} = walk(body, current + 1, max)
    {current, max}
  end

  # Binary operators: no depth change
  defp walk({:binary_op, _, _, left, right}, current, max) do
    {_, max} = walk(left, current, max)
    {_, max} = walk(right, current, max)
    {current, max}
  end

  # Unary operator
  defp walk({:unary_op, _, operand}, current, max) do
    walk(operand, current, max)
  end

  # Exception handling: increment depth for blocks
  defp walk({:exception_handling, try_block, catches, else_block}, current, max) do
    {_, max} = walk(try_block, current + 1, max)

    {_, max} =
      Enum.reduce(catches, {current, max}, fn {_type, _var, catch_body}, {_c, m} ->
        walk(catch_body, current + 1, m)
      end)

    {_, max} = walk(else_block, current + 1, max)
    {current, max}
  end

  # Pattern match: increment depth for branches
  defp walk({:pattern_match, value, branches}, current, max) do
    {_, max} = walk(value, current, max)

    {_, max} =
      Enum.reduce(branches, {current, max}, fn
        {:match_arm, _pattern, _guard, body}, {_c, m} ->
          walk(body, current + 1, m)

        {_pattern, branch}, {_c, m} ->
          walk(branch, current + 1, m)
      end)

    {current, max}
  end

  # Match arm: increment depth for body
  defp walk({:match_arm, _pattern, guard, body}, current, max) do
    {_, max} = if guard, do: walk(guard, current, max), else: {current, max}
    walk(body, current + 1, max)
  end

  # Block: walk statements at same depth
  defp walk({:block, stmts}, current, max) when is_list(stmts) do
    max = Enum.max([current, max])

    {_, max} =
      Enum.reduce(stmts, {current, max}, fn stmt, {c, m} ->
        walk(stmt, c, m)
      end)

    {current, max}
  end

  # Function call: walk arguments
  defp walk({:function_call, _name, args}, current, max) do
    {_, max} =
      Enum.reduce(args, {current, max}, fn arg, {c, m} ->
        walk(arg, c, m)
      end)

    {current, max}
  end

  # Lambda: increment depth for body
  defp walk({:lambda, _params, body}, current, max) do
    {_, max} = walk(body, current + 1, max)
    {current, max}
  end

  # M2.2s: Structural/Organizational Types

  # Container: walk all members at same depth
  defp walk({:container, _type, _name, _metadata, members}, current, max) when is_list(members) do
    max = Enum.max([current, max])

    {_, max} =
      Enum.reduce(members, {current, max}, fn member, {c, m} ->
        walk(member, c, m)
      end)

    {current, max}
  end

  # Function definition: walk parameters, guards, and body
  defp walk({:function_def, _visibility, _name, params, metadata, body}, current, max) do
    # Walk parameters
    {_, max} =
      Enum.reduce(params, {current, max}, fn
        {:pattern, pattern}, {c, m} -> walk(pattern, c, m)
        {:default, _name, default}, {c, m} -> walk(default, c, m)
        _simple_param, {c, m} -> {c, m}
      end)

    # Walk guards if present
    {_, max} =
      case Map.get(metadata, :guards) do
        nil -> {current, max}
        guard -> walk(guard, current, max)
      end

    # Walk body with incremented depth (function introduces scope)
    walk(body, current + 1, max)
  end

  # Attribute access: walk object
  defp walk({:attribute_access, obj, _attr}, current, max) do
    walk(obj, current, max)
  end

  # Augmented assignment: walk value
  defp walk({:augmented_assignment, _op, _target, value}, current, max) do
    walk(value, current, max)
  end

  # Property: walk getter and setter bodies
  defp walk({:property, _name, getter, setter, _metadata}, current, max) do
    {_, max} = if getter, do: walk(getter, current + 1, max), else: {current, max}
    {_, max} = if setter, do: walk(setter, current + 1, max), else: {current, max}
    {current, max}
  end

  # Collection operations
  defp walk({:collection_op, _, func, coll}, current, max) do
    {_, max} = walk(func, current, max)
    {_, max} = walk(coll, current, max)
    {current, max}
  end

  defp walk({:collection_op, _, func, coll, init}, current, max) do
    {_, max} = walk(func, current, max)
    {_, max} = walk(coll, current, max)
    {_, max} = walk(init, current, max)
    {current, max}
  end

  # Assignment
  defp walk({:assignment, target, value}, current, max) do
    {_, max} = walk(target, current, max)
    {_, max} = walk(value, current, max)
    {current, max}
  end

  # Inline match
  defp walk({:inline_match, pattern, value}, current, max) do
    {_, max} = walk(pattern, current, max)
    {_, max} = walk(value, current, max)
    {current, max}
  end

  # Early return
  defp walk({:early_return, value}, current, max) do
    walk(value, current, max)
  end

  # Tuple
  defp walk({:tuple, elems}, current, max) when is_list(elems) do
    {_, max} =
      Enum.reduce(elems, {current, max}, fn elem, {c, m} ->
        walk(elem, c, m)
      end)

    {current, max}
  end

  # List
  defp walk({:list, elems}, current, max) when is_list(elems) do
    {_, max} =
      Enum.reduce(elems, {current, max}, fn elem, {c, m} ->
        walk(elem, c, m)
      end)

    {current, max}
  end

  # Map
  defp walk({:map, pairs}, current, max) when is_list(pairs) do
    {_, max} =
      Enum.reduce(pairs, {current, max}, fn {key, value}, {c, m} ->
        {_, m} = walk(key, c, m)
        walk(value, c, m)
      end)

    {current, max}
  end

  # Async operation
  defp walk({:async_operation, _type, body}, current, max) do
    walk(body, current, max)
  end

  # Language-specific: traverse embedded body if present
  defp walk({:language_specific, _, _, _, metadata}, current, max) when is_map(metadata) do
    case Map.get(metadata, :body) do
      nil -> {current, max}
      body -> walk(body, current, max)
    end
  end

  defp walk({:language_specific, _, _, _}, current, max), do: {current, max}
  defp walk({:language_specific, _, _}, current, max), do: {current, max}

  # Literals and variables: update max if current is higher
  defp walk({:literal, _, _}, current, max), do: {current, Enum.max([current, max])}
  defp walk({:variable, _}, current, max), do: {current, Enum.max([current, max])}

  # Nil
  defp walk(nil, current, max), do: {current, max}

  # Fallback
  defp walk(_, current, max), do: {current, max}
end
