defmodule Metastatic.Analysis.Complexity.Cyclomatic do
  @moduledoc """
  Cyclomatic complexity calculation (McCabe metric).

  Cyclomatic complexity measures the number of linearly independent paths
  through a program's source code. It is calculated as the number of
  decision points plus one.

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
      iex> ast = {:literal, :integer, 42}
      iex> Metastatic.Analysis.Complexity.Cyclomatic.calculate(ast)
      1

      # Single conditional: complexity = 2
      iex> ast = {:conditional, {:variable, "x"}, {:literal, :integer, 1}, {:literal, :integer, 2}}
      iex> Metastatic.Analysis.Complexity.Cyclomatic.calculate(ast)
      2

      # Conditional with loop: complexity = 3
      iex> ast = {:conditional, {:variable, "x"},
      ...>   {:loop, :while, {:variable, "y"}, {:literal, :integer, 1}},
      ...>   {:literal, :integer, 2}}
      iex> Metastatic.Analysis.Complexity.Cyclomatic.calculate(ast)
      3
  """

  alias Metastatic.AST

  @doc """
  Calculates cyclomatic complexity for a MetaAST node.

  Returns the complexity as a non-negative integer (minimum 1).

  ## Examples

      iex> ast = {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}}
      iex> Metastatic.Analysis.Complexity.Cyclomatic.calculate(ast)
      1

      iex> ast = {:conditional, {:variable, "condition"},
      ...>   {:literal, :integer, 1},
      ...>   {:literal, :integer, 2}}
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

  # Conditional: +1 decision point
  defp walk({:conditional, cond, then_br, else_br}, count) do
    count = count + 1
    count = walk(cond, count)
    count = walk(then_br, count)
    walk(else_br, count)
  end

  # Loop: +1 decision point
  defp walk({:loop, :while, cond, body}, count) do
    count = count + 1
    count = walk(cond, count)
    walk(body, count)
  end

  defp walk({:loop, _, iter, coll, body}, count) do
    count = count + 1
    count = walk(iter, count)
    count = walk(coll, count)
    walk(body, count)
  end

  # Boolean operators (and/or): +1 each
  defp walk({:binary_op, :boolean, op, left, right}, count) when op in [:and, :or] do
    count = count + 1
    count = walk(left, count)
    walk(right, count)
  end

  # Other binary operators: no decision point
  defp walk({:binary_op, _, _, left, right}, count) do
    count = walk(left, count)
    walk(right, count)
  end

  # Unary operator
  defp walk({:unary_op, _, operand}, count) do
    walk(operand, count)
  end

  # Exception handling: +1 per catch clause
  defp walk({:exception_handling, try_block, catches, else_block}, count) do
    count = count + length(catches)
    count = walk(try_block, count)
    count = Enum.reduce(catches, count, fn catch_clause, c -> walk(catch_clause, c) end)
    walk(else_block, count)
  end

  # Pattern match: +1 per branch
  defp walk({:pattern_match, value, branches}, count) do
    count = count + length(branches)
    count = walk(value, count)

    Enum.reduce(branches, count, fn
      {:match_arm, _pattern, _guard, body}, c -> walk(body, c)
      {_pattern, branch}, c -> walk(branch, c)
    end)
  end

  # Match arm (used in pattern matching and guarded functions)
  defp walk({:match_arm, _pattern, guard, body}, count) do
    count = if guard, do: walk(guard, count), else: count
    walk(body, count)
  end

  # Block: walk statements
  defp walk({:block, stmts}, count) when is_list(stmts) do
    Enum.reduce(stmts, count, fn stmt, c -> walk(stmt, c) end)
  end

  # Function call: walk arguments
  defp walk({:function_call, _name, args}, count) do
    Enum.reduce(args, count, fn arg, c -> walk(arg, c) end)
  end

  # Lambda: walk body
  defp walk({:lambda, _params, body}, count) do
    walk(body, count)
  end

  # Collection operations
  defp walk({:collection_op, _, func, coll}, count) do
    count = walk(func, count)
    walk(coll, count)
  end

  defp walk({:collection_op, _, func, coll, init}, count) do
    count = walk(func, count)
    count = walk(coll, count)
    walk(init, count)
  end

  # Assignment
  defp walk({:assignment, target, value}, count) do
    count = walk(target, count)
    walk(value, count)
  end

  # Inline match
  defp walk({:inline_match, pattern, value}, count) do
    count = walk(pattern, count)
    walk(value, count)
  end

  # Early return
  defp walk({:early_return, value}, count) do
    walk(value, count)
  end

  # Tuple
  defp walk({:tuple, elems}, count) when is_list(elems) do
    Enum.reduce(elems, count, fn elem, c -> walk(elem, c) end)
  end

  # List
  defp walk({:list, elems}, count) when is_list(elems) do
    Enum.reduce(elems, count, fn elem, c -> walk(elem, c) end)
  end

  # Async operation
  defp walk({:async_operation, type, body}, count) do
    _ = type
    walk(body, count)
  end

  # Language-specific: traverse embedded body if present
  defp walk({:language_specific, _, _, _, metadata}, count) when is_map(metadata) do
    # If there's a body in metadata (e.g., module/function definitions), traverse it
    case Map.get(metadata, :body) do
      nil -> count
      body -> walk(body, count)
    end
  end

  defp walk({:language_specific, _, _, _}, count), do: count
  defp walk({:language_specific, _, _}, count), do: count

  # Literals and variables: no decision points
  defp walk({:literal, _, _}, count), do: count
  defp walk({:variable, _}, count), do: count

  # Nil (else branch)
  defp walk(nil, count), do: count

  # Fallback for unknown nodes
  defp walk(_, count), do: count
end
