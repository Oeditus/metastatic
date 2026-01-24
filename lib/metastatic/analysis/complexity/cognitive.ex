defmodule Metastatic.Analysis.Complexity.Cognitive do
  @moduledoc """
  Cognitive complexity calculation.

  Cognitive complexity measures how difficult code is to understand, taking into
  account nested structures that increase the mental burden on readers.

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
      iex> ast = {:conditional, {:variable, "x"}, {:literal, :integer, 1}, {:literal, :integer, 2}}
      iex> Metastatic.Analysis.Complexity.Cognitive.calculate(ast)
      1

      # Nested conditional: cognitive = 3 (1 + 2)
      iex> ast = {:conditional, {:variable, "x"},
      ...>   {:conditional, {:variable, "y"}, {:literal, :integer, 1}, {:literal, :integer, 2}},
      ...>   {:literal, :integer, 3}}
      iex> Metastatic.Analysis.Complexity.Cognitive.calculate(ast)
      3
  """

  alias Metastatic.AST

  @doc """
  Calculates cognitive complexity for a MetaAST node.

  Returns the complexity as a non-negative integer (minimum 0).

  ## Examples

      iex> ast = {:literal, :integer, 42}
      iex> Metastatic.Analysis.Complexity.Cognitive.calculate(ast)
      0

      iex> ast = {:conditional, {:variable, "x"},
      ...>   {:literal, :integer, 1},
      ...>   {:literal, :integer, 2}}
      iex> Metastatic.Analysis.Complexity.Cognitive.calculate(ast)
      1
  """
  @spec calculate(AST.meta_ast()) :: non_neg_integer()
  def calculate(ast) do
    walk(ast, 0, 0)
  end

  # Private implementation

  # walk(ast, nesting_level, accumulator) -> accumulator

  # Conditional: +1 +nesting_level
  defp walk({:conditional, cond, then_br, else_br}, nesting, acc) do
    acc = acc + 1 + nesting
    acc = walk(cond, nesting, acc)
    # Increment nesting for branches
    acc = walk(then_br, nesting + 1, acc)
    walk(else_br, nesting + 1, acc)
  end

  # Loop: +1 +nesting_level
  defp walk({:loop, :while, cond, body}, nesting, acc) do
    acc = acc + 1 + nesting
    acc = walk(cond, nesting, acc)
    walk(body, nesting + 1, acc)
  end

  defp walk({:loop, _, iter, coll, body}, nesting, acc) do
    acc = acc + 1 + nesting
    acc = walk(iter, nesting, acc)
    acc = walk(coll, nesting, acc)
    walk(body, nesting + 1, acc)
  end

  # Boolean operators (and/or): +1 (no nesting penalty)
  defp walk({:binary_op, :boolean, op, left, right}, nesting, acc) when op in [:and, :or] do
    acc = acc + 1
    acc = walk(left, nesting, acc)
    walk(right, nesting, acc)
  end

  # Other binary operators: no complexity
  defp walk({:binary_op, _, _, left, right}, nesting, acc) do
    acc = walk(left, nesting, acc)
    walk(right, nesting, acc)
  end

  # Unary operator
  defp walk({:unary_op, _, operand}, nesting, acc) do
    walk(operand, nesting, acc)
  end

  # Exception handling: +1 +nesting_level
  defp walk({:exception_handling, try_block, catches, else_block}, nesting, acc) do
    acc = acc + 1 + nesting
    acc = walk(try_block, nesting + 1, acc)

    acc =
      Enum.reduce(catches, acc, fn {_type, _var, catch_body}, a ->
        walk(catch_body, nesting + 1, a)
      end)

    walk(else_block, nesting + 1, acc)
  end

  # Pattern match: +1 +nesting_level per branch
  defp walk({:pattern_match, value, branches}, nesting, acc) do
    acc = walk(value, nesting, acc)

    Enum.reduce(branches, acc, fn
      {:match_arm, _pattern, _guard, body}, a ->
        a = a + 1 + nesting
        walk(body, nesting + 1, a)

      {_pattern, branch}, a ->
        a = a + 1 + nesting
        walk(branch, nesting + 1, a)
    end)
  end

  # Match arm (used in pattern matching and guarded functions)
  defp walk({:match_arm, _pattern, guard, body}, nesting, acc) do
    acc = if guard, do: walk(guard, nesting, acc), else: acc
    walk(body, nesting + 1, acc)
  end

  # Block: walk statements at same nesting level
  defp walk({:block, stmts}, nesting, acc) when is_list(stmts) do
    Enum.reduce(stmts, acc, fn stmt, a -> walk(stmt, nesting, a) end)
  end

  # Function call: walk arguments
  defp walk({:function_call, _name, args}, nesting, acc) do
    Enum.reduce(args, acc, fn arg, a -> walk(arg, nesting, a) end)
  end

  # Lambda: increase nesting for body
  defp walk({:lambda, _params, body}, nesting, acc) do
    walk(body, nesting + 1, acc)
  end

  # Collection operations
  defp walk({:collection_op, _, func, coll}, nesting, acc) do
    acc = walk(func, nesting, acc)
    walk(coll, nesting, acc)
  end

  defp walk({:collection_op, _, func, coll, init}, nesting, acc) do
    acc = walk(func, nesting, acc)
    acc = walk(coll, nesting, acc)
    walk(init, nesting, acc)
  end

  # Assignment
  defp walk({:assignment, target, value}, nesting, acc) do
    acc = walk(target, nesting, acc)
    walk(value, nesting, acc)
  end

  # Inline match
  defp walk({:inline_match, pattern, value}, nesting, acc) do
    acc = walk(pattern, nesting, acc)
    walk(value, nesting, acc)
  end

  # Early return
  defp walk({:early_return, value}, nesting, acc) do
    walk(value, nesting, acc)
  end

  # Tuple
  defp walk({:tuple, elems}, nesting, acc) when is_list(elems) do
    Enum.reduce(elems, acc, fn elem, a -> walk(elem, nesting, a) end)
  end

  # List
  defp walk({:list, elems}, nesting, acc) when is_list(elems) do
    Enum.reduce(elems, acc, fn elem, a -> walk(elem, nesting, a) end)
  end

  # Map
  defp walk({:map, pairs}, nesting, acc) when is_list(pairs) do
    Enum.reduce(pairs, acc, fn {key, value}, a ->
      a = walk(key, nesting, a)
      walk(value, nesting, a)
    end)
  end

  # Async operation
  defp walk({:async_operation, _type, body}, nesting, acc) do
    walk(body, nesting, acc)
  end

  # M2.2s: Structural/Organizational types
  defp walk({:container, _type, _name, _metadata, members}, nesting, acc) when is_list(members) do
    Enum.reduce(members, acc, fn member, a -> walk(member, nesting, a) end)
  end

  defp walk({:function_def, _visibility, _name, params, metadata, body}, nesting, acc)
       when is_list(params) do
    acc =
      Enum.reduce(params, acc, fn
        {:pattern, pattern}, a -> walk(pattern, nesting, a)
        {:default, _name, default}, a -> walk(default, nesting, a)
        _simple_param, a -> a
      end)

    acc =
      case Map.get(metadata, :guards) do
        nil -> acc
        guard -> walk(guard, nesting, acc)
      end

    walk(body, nesting, acc)
  end

  defp walk({:attribute_access, receiver, _attribute}, nesting, acc) do
    walk(receiver, nesting, acc)
  end

  defp walk({:augmented_assignment, _op, target, value}, nesting, acc) do
    acc = walk(target, nesting, acc)
    walk(value, nesting, acc)
  end

  defp walk({:property, _name, getter, setter, _metadata}, nesting, acc) do
    acc = if getter, do: walk(getter, nesting, acc), else: acc
    if setter, do: walk(setter, nesting, acc), else: acc
  end

  # Language-specific: traverse embedded body if present
  defp walk({:language_specific, _, _, _, metadata}, nesting, acc) when is_map(metadata) do
    case Map.get(metadata, :body) do
      nil -> acc
      body -> walk(body, nesting, acc)
    end
  end

  defp walk({:language_specific, _, _, _}, _nesting, acc), do: acc
  defp walk({:language_specific, _, _}, _nesting, acc), do: acc

  # Literals and variables: no complexity
  defp walk({:literal, _, _}, _nesting, acc), do: acc
  defp walk({:variable, _}, _nesting, acc), do: acc

  # Nil
  defp walk(nil, _nesting, acc), do: acc

  # Fallback
  defp walk(_, _nesting, acc), do: acc
end
