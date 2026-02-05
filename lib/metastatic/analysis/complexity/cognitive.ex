defmodule Metastatic.Analysis.Complexity.Cognitive do
  @moduledoc """
  Cognitive complexity calculation.

  Cognitive complexity measures how difficult code is to understand, taking into
  account nested structures that increase the mental burden on readers.

  ## 3-Tuple Format

  All MetaAST nodes use the uniform 3-tuple structure:
  `{type_atom, keyword_meta, children_or_value}`

  ## Algorithm

  Based on the Sonar cognitive complexity specification:

  - **Base Increments:** Structural elements add to complexity
    - `conditional` - +1 (+nesting level)
    - `loop` - +1 (+nesting level)
    - `binary_op` with `:boolean` and `:and`/`:or` - +1
    - `pattern_match` - +1 (+nesting level per branch)
    - `exception_handling` - +1 (+nesting level)

  - **Nesting Penalty:** Each level of nesting adds to the increment
    - Conditional at level 0: +1
    - Conditional at level 1: +2
    - Conditional at level 2: +3

  ## Difference from Cyclomatic

  Cognitive complexity differs from cyclomatic in that it:
  - Applies nesting penalties (deeper = more complex)
  - Doesn't count boolean operators in conditions the same way
  - Emphasizes understandability over testability

  ## Examples

      # Simple conditional: cognitive = 1
      iex> ast = {:conditional, [], [{:variable, [], "x"}, {:literal, [subtype: :integer], 1}, {:literal, [subtype: :integer], 2}]}
      iex> Metastatic.Analysis.Complexity.Cognitive.calculate(ast)
      1

      # Nested conditional: cognitive = 3 (1 + 2)
      iex> ast = {:conditional, [], [
      ...>   {:variable, [], "x"},
      ...>   {:conditional, [], [{:variable, [], "y"}, {:literal, [subtype: :integer], 1}, {:literal, [subtype: :integer], 2}]},
      ...>   {:literal, [subtype: :integer], 3}]}
      iex> Metastatic.Analysis.Complexity.Cognitive.calculate(ast)
      3
  """

  alias Metastatic.AST

  @doc """
  Calculates cognitive complexity for a MetaAST node.

  Returns the complexity as a non-negative integer (minimum 0).

  ## Examples

      iex> ast = {:literal, [subtype: :integer], 42}
      iex> Metastatic.Analysis.Complexity.Cognitive.calculate(ast)
      0

      iex> ast = {:conditional, [], [
      ...>   {:variable, [], "x"},
      ...>   {:literal, [subtype: :integer], 1},
      ...>   {:literal, [subtype: :integer], 2}]}
      iex> Metastatic.Analysis.Complexity.Cognitive.calculate(ast)
      1
  """
  @spec calculate(AST.meta_ast()) :: non_neg_integer()
  def calculate(ast) do
    walk(ast, 0, 0)
  end

  # Private implementation

  # walk(ast, nesting_level, accumulator) -> accumulator

  # Conditional (3-tuple): +1 +nesting_level
  defp walk({:conditional, _meta, [cond_expr, then_br, else_br]}, nesting, acc) do
    acc = acc + 1 + nesting
    acc = walk(cond_expr, nesting, acc)
    # Increment nesting for branches
    acc = walk(then_br, nesting + 1, acc)
    walk(else_br, nesting + 1, acc)
  end

  # Loop (3-tuple): +1 +nesting_level
  defp walk({:loop, meta, children}, nesting, acc) when is_list(meta) do
    loop_type = Keyword.get(meta, :loop_type)
    acc = acc + 1 + nesting

    case {loop_type, children} do
      {:while, [cond_expr, body]} ->
        acc = walk(cond_expr, nesting, acc)
        walk(body, nesting + 1, acc)

      {_, [iter, coll, body]} ->
        acc = walk(iter, nesting, acc)
        acc = walk(coll, nesting, acc)
        walk(body, nesting + 1, acc)

      _ ->
        Enum.reduce(children, acc, fn child, a -> walk(child, nesting, a) end)
    end
  end

  # Boolean operators (3-tuple) (and/or): +1 (no nesting penalty)
  defp walk({:binary_op, meta, [left, right]}, nesting, acc) when is_list(meta) do
    category = Keyword.get(meta, :category)
    op = Keyword.get(meta, :operator)

    acc =
      if category == :boolean and op in [:and, :or] do
        acc + 1
      else
        acc
      end

    acc = walk(left, nesting, acc)
    walk(right, nesting, acc)
  end

  # Unary operator (3-tuple)
  defp walk({:unary_op, _meta, [operand]}, nesting, acc) do
    walk(operand, nesting, acc)
  end

  # Exception handling (3-tuple): +1 +nesting_level
  defp walk({:exception_handling, _meta, [try_block, catches, else_block]}, nesting, acc) do
    acc = acc + 1 + nesting
    acc = walk(try_block, nesting + 1, acc)

    catches_list = if is_list(catches), do: catches, else: []

    acc =
      Enum.reduce(catches_list, acc, fn
        {:catch_clause, _, [_type, _var, catch_body]}, a ->
          walk(catch_body, nesting + 1, a)

        {_type, _var, catch_body}, a ->
          walk(catch_body, nesting + 1, a)

        other, a ->
          walk(other, nesting + 1, a)
      end)

    walk(else_block, nesting + 1, acc)
  end

  # Pattern match (3-tuple): +1 +nesting_level per branch
  defp walk({:pattern_match, _meta, [value, branches | _]}, nesting, acc) do
    acc = walk(value, nesting, acc)
    branches_list = if is_list(branches), do: branches, else: []

    Enum.reduce(branches_list, acc, fn
      {:match_arm, _, [_pattern, _guard, body]}, a ->
        a = a + 1 + nesting
        walk(body, nesting + 1, a)

      {:pair, _, [_pattern, branch]}, a ->
        a = a + 1 + nesting
        walk(branch, nesting + 1, a)

      {_pattern, branch}, a ->
        a = a + 1 + nesting
        walk(branch, nesting + 1, a)

      other, a ->
        walk(other, nesting, a)
    end)
  end

  # Match arm (3-tuple)
  defp walk({:match_arm, _meta, [_pattern, guard, body]}, nesting, acc) do
    acc = if guard, do: walk(guard, nesting, acc), else: acc
    walk(body, nesting + 1, acc)
  end

  # Block (3-tuple): walk statements at same nesting level
  defp walk({:block, _meta, stmts}, nesting, acc) when is_list(stmts) do
    Enum.reduce(stmts, acc, fn stmt, a -> walk(stmt, nesting, a) end)
  end

  # Function call (3-tuple): walk arguments
  defp walk({:function_call, _meta, args}, nesting, acc) when is_list(args) do
    Enum.reduce(args, acc, fn arg, a -> walk(arg, nesting, a) end)
  end

  # Lambda (3-tuple): increase nesting for body
  defp walk({:lambda, _meta, [body]}, nesting, acc) do
    walk(body, nesting + 1, acc)
  end

  # Collection operations (3-tuple)
  defp walk({:collection_op, _meta, children}, nesting, acc) when is_list(children) do
    Enum.reduce(children, acc, fn child, a -> walk(child, nesting, a) end)
  end

  # Assignment (3-tuple)
  defp walk({:assignment, _meta, [target, value]}, nesting, acc) do
    acc = walk(target, nesting, acc)
    walk(value, nesting, acc)
  end

  # Inline match (3-tuple)
  defp walk({:inline_match, _meta, [pattern, value]}, nesting, acc) do
    acc = walk(pattern, nesting, acc)
    walk(value, nesting, acc)
  end

  # Early return (3-tuple)
  defp walk({:early_return, _meta, [value]}, nesting, acc) do
    walk(value, nesting, acc)
  end

  # List (3-tuple)
  defp walk({:list, _meta, elems}, nesting, acc) when is_list(elems) do
    Enum.reduce(elems, acc, fn elem, a -> walk(elem, nesting, a) end)
  end

  # Map (3-tuple)
  defp walk({:map, _meta, pairs}, nesting, acc) when is_list(pairs) do
    Enum.reduce(pairs, acc, fn
      {:pair, _, [key, value]}, a ->
        a = walk(key, nesting, a)
        walk(value, nesting, a)

      {key, value}, a ->
        a = walk(key, nesting, a)
        walk(value, nesting, a)

      other, a ->
        walk(other, nesting, a)
    end)
  end

  # Async operation (3-tuple)
  defp walk({:async_operation, _meta, [body]}, nesting, acc) do
    walk(body, nesting, acc)
  end

  # M2.2s: Structural/Organizational types (3-tuple format)
  # Container: walk body
  defp walk({:container, _meta, [body]}, nesting, acc) do
    if is_list(body) do
      Enum.reduce(body, acc, fn member, a -> walk(member, nesting, a) end)
    else
      walk(body, nesting, acc)
    end
  end

  # Function definition (3-tuple): walk body
  defp walk({:function_def, meta, [body]}, nesting, acc) when is_list(meta) do
    params = Keyword.get(meta, :params, [])

    acc =
      Enum.reduce(params, acc, fn
        {:param, _, [_name, pattern, default]}, a ->
          a = if pattern, do: walk(pattern, nesting, a), else: a
          if default, do: walk(default, nesting, a), else: a

        _simple_param, a ->
          a
      end)

    acc =
      case Keyword.get(meta, :guards) do
        nil -> acc
        guard -> walk(guard, nesting, acc)
      end

    walk(body, nesting, acc)
  end

  # Attribute access (3-tuple)
  defp walk({:attribute_access, _meta, [receiver, _attribute]}, nesting, acc) do
    walk(receiver, nesting, acc)
  end

  # Augmented assignment (3-tuple)
  defp walk({:augmented_assignment, _meta, [target, value]}, nesting, acc) do
    acc = walk(target, nesting, acc)
    walk(value, nesting, acc)
  end

  # Property (3-tuple)
  defp walk({:property, _meta, [getter, setter]}, nesting, acc) do
    acc = if getter, do: walk(getter, nesting, acc), else: acc
    if setter, do: walk(setter, nesting, acc), else: acc
  end

  # Language-specific (3-tuple)
  defp walk({:language_specific, meta, native_ast}, nesting, acc) when is_list(meta) do
    case native_ast do
      %{body: body} when not is_nil(body) -> walk(body, nesting, acc)
      _ -> acc
    end
  end

  # Literals and variables (3-tuple): no complexity
  defp walk({:literal, _meta, _value}, _nesting, acc), do: acc
  defp walk({:variable, _meta, _name}, _nesting, acc), do: acc

  # Pair (3-tuple)
  defp walk({:pair, _meta, [key, value]}, nesting, acc) do
    acc = walk(key, nesting, acc)
    walk(value, nesting, acc)
  end

  # Nil
  defp walk(nil, _nesting, acc), do: acc

  # Fallback
  defp walk(_, _nesting, acc), do: acc
end
