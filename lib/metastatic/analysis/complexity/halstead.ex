defmodule Metastatic.Analysis.Complexity.Halstead do
  @moduledoc """
  Halstead complexity metrics calculation.

  Halstead metrics measure program complexity based on the count of operators
  and operands in the code.

  ## Metrics Calculated

  - **n1**: Number of distinct operators
  - **n2**: Number of distinct operands
  - **N1**: Total operators
  - **N2**: Total operands
  - **Vocabulary (n)**: n1 + n2
  - **Length (N)**: N1 + N2
  - **Volume (V)**: N × log2(n)
  - **Difficulty (D)**: (n1/2) × (N2/n2)
  - **Effort (E)**: D × V

  ## What Counts as Operator/Operand

  **Operators:**
  - Binary operators (+, -, *, /, >, <, ==, and, or, etc.)
  - Unary operators (-, not)
  - Assignment (=)
  - Function call operator ()
  - Control flow (if, while, for, try, case)

  **Operands:**
  - Variables
  - Literals (numbers, strings, booleans)
  - Function names

  ## Examples

      iex> ast = {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}}
      iex> metrics = Metastatic.Analysis.Complexity.Halstead.calculate(ast)
      iex> metrics.distinct_operators
      1
      iex> metrics.distinct_operands
      2
  """

  alias Metastatic.AST

  @type t :: %{
          distinct_operators: non_neg_integer(),
          distinct_operands: non_neg_integer(),
          total_operators: non_neg_integer(),
          total_operands: non_neg_integer(),
          vocabulary: non_neg_integer(),
          length: non_neg_integer(),
          volume: float(),
          difficulty: float(),
          effort: float()
        }

  @doc """
  Calculates Halstead metrics for a MetaAST node.

  Returns a map with all Halstead metrics.

  ## Examples

      iex> ast = {:literal, :integer, 42}
      iex> metrics = Metastatic.Analysis.Complexity.Halstead.calculate(ast)
      iex> metrics.total_operands
      1
      iex> metrics.total_operators
      0
  """
  @spec calculate(AST.meta_ast()) :: t()
  def calculate(ast) do
    %{operators: operators, operands: operands} = walk(ast, %{operators: [], operands: []})

    # Count distinct and total
    distinct_operators = operators |> Enum.uniq() |> length()
    distinct_operands = operands |> Enum.uniq() |> length()
    total_operators = length(operators)
    total_operands = length(operands)

    # Calculate derived metrics
    n = distinct_operators + distinct_operands
    big_n = total_operators + total_operands

    volume = calculate_volume(big_n, n)
    difficulty = calculate_difficulty(distinct_operators, total_operands, distinct_operands)
    effort = difficulty * volume

    %{
      distinct_operators: distinct_operators,
      distinct_operands: distinct_operands,
      total_operators: total_operators,
      total_operands: total_operands,
      vocabulary: n,
      length: big_n,
      volume: volume,
      difficulty: difficulty,
      effort: effort
    }
  end

  # Private implementation

  defp walk(ast, acc) do
    case ast do
      # Binary operators
      {:binary_op, category, op, left, right} ->
        operator = operator_name(category, op)
        acc = %{acc | operators: [operator | acc.operators]}
        acc = walk(left, acc)
        walk(right, acc)

      # Unary operators
      {:unary_op, category, op, operand} ->
        operator = operator_name(category, op)
        acc = %{acc | operators: [operator | acc.operators]}
        walk(operand, acc)

      # Conditional (if operator)
      {:conditional, cond, then_br, else_br} ->
        acc = %{acc | operators: ["if" | acc.operators]}
        acc = walk(cond, acc)
        acc = walk(then_br, acc)
        walk(else_br, acc)

      # Loop (while/for operator)
      {:loop, :while, cond, body} ->
        acc = %{acc | operators: ["while" | acc.operators]}
        acc = walk(cond, acc)
        walk(body, acc)

      {:loop, :for, iter, coll, body} ->
        acc = %{acc | operators: ["for" | acc.operators]}
        acc = walk(iter, acc)
        acc = walk(coll, acc)
        walk(body, acc)

      {:loop, type, iter, coll, body} ->
        acc = %{acc | operators: [to_string(type) | acc.operators]}
        acc = walk(iter, acc)
        acc = walk(coll, acc)
        walk(body, acc)

      # Assignment (= operator)
      {:assignment, target, value} ->
        acc = %{acc | operators: ["=" | acc.operators]}
        acc = walk(target, acc)
        walk(value, acc)

      # Inline match (= operator)
      {:inline_match, pattern, value} ->
        acc = %{acc | operators: ["=" | acc.operators]}
        acc = walk(pattern, acc)
        walk(value, acc)

      # Function call (function name is operand, () is operator)
      {:function_call, name, args} ->
        acc = %{acc | operators: ["()" | acc.operators]}
        acc = %{acc | operands: [name | acc.operands]}
        Enum.reduce(args, acc, fn arg, a -> walk(arg, a) end)

      # Exception handling (try operator)
      {:exception_handling, try_block, catches, else_block} ->
        acc = %{acc | operators: ["try" | acc.operators]}
        acc = walk(try_block, acc)

        acc =
          Enum.reduce(catches, acc, fn {_type, var, catch_body}, a ->
            a = walk(var, a)
            walk(catch_body, a)
          end)

        walk(else_block, acc)

      # Pattern match (case operator)
      {:pattern_match, value, branches} ->
        acc = %{acc | operators: ["case" | acc.operators]}
        acc = walk(value, acc)

        Enum.reduce(branches, acc, fn {pattern, branch}, a ->
          a = walk(pattern, a)
          walk(branch, a)
        end)

      # Early return
      {:early_return, value} ->
        acc = %{acc | operators: ["return" | acc.operators]}
        walk(value, acc)

      # Block
      {:block, stmts} when is_list(stmts) ->
        Enum.reduce(stmts, acc, fn stmt, a -> walk(stmt, a) end)

      # Lambda
      {:lambda, params, body} ->
        acc = %{acc | operators: ["lambda" | acc.operators]}
        acc = Enum.reduce(params, acc, fn param, a -> walk(param, a) end)
        walk(body, acc)

      # Collection operations
      {:collection_op, op, func, coll} ->
        acc = %{acc | operators: [to_string(op) | acc.operators]}
        acc = walk(func, acc)
        walk(coll, acc)

      {:collection_op, op, func, coll, init} ->
        acc = %{acc | operators: [to_string(op) | acc.operators]}
        acc = walk(func, acc)
        acc = walk(coll, acc)
        walk(init, acc)

      # Tuple/List
      {:tuple, elems} when is_list(elems) ->
        acc = %{acc | operators: ["tuple" | acc.operators]}
        Enum.reduce(elems, acc, fn elem, a -> walk(elem, a) end)

      {:list, elems} when is_list(elems) ->
        acc = %{acc | operators: ["list" | acc.operators]}
        Enum.reduce(elems, acc, fn elem, a -> walk(elem, a) end)

      # Async operation
      {:async_operation, type, body} ->
        acc = %{acc | operators: [to_string(type) | acc.operators]}
        walk(body, acc)

      # Literal (operand)
      {:literal, _type, value} ->
        %{acc | operands: [inspect(value) | acc.operands]}

      # Variable (operand)
      {:variable, name} ->
        %{acc | operands: [name | acc.operands]}

      # Language-specific: count as single operator
      {:language_specific, _, _} ->
        %{acc | operators: ["native" | acc.operators]}

      {:language_specific, _, _, _} ->
        %{acc | operators: ["native" | acc.operators]}

      # Nil
      nil ->
        acc

      # Fallback
      _ ->
        acc
    end
  end

  defp operator_name(:arithmetic, op), do: to_string(op)
  defp operator_name(:comparison, op), do: to_string(op)
  defp operator_name(:boolean, op), do: to_string(op)
  defp operator_name(_category, op), do: to_string(op)

  defp calculate_volume(_n, 0), do: 0.0
  defp calculate_volume(0, _vocab), do: 0.0

  defp calculate_volume(n, vocab) do
    n * :math.log2(vocab)
  end

  defp calculate_difficulty(_n1, _n2, 0), do: 0.0
  defp calculate_difficulty(0, _n2, _distinct_operands), do: 0.0

  defp calculate_difficulty(distinct_operators, total_operands, distinct_operands) do
    distinct_operators / 2.0 * (total_operands / distinct_operands)
  end
end
