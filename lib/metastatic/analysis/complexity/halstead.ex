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

      iex> ast = {:binary_op, [category: :arithmetic, operator: :+], [{:variable, [], "x"}, {:literal, [subtype: :integer], 5}]}
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

      iex> ast = {:literal, [subtype: :integer], 42}
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
      # Binary operators (3-tuple)
      {:binary_op, meta, [left, right]} when is_list(meta) ->
        category = Keyword.get(meta, :category)
        op = Keyword.get(meta, :operator)
        operator = operator_name(category, op)
        acc = %{acc | operators: [operator | acc.operators]}
        acc = walk(left, acc)
        walk(right, acc)

      # Unary operators (3-tuple)
      {:unary_op, meta, [operand]} when is_list(meta) ->
        category = Keyword.get(meta, :category)
        op = Keyword.get(meta, :operator)
        operator = operator_name(category, op)
        acc = %{acc | operators: [operator | acc.operators]}
        walk(operand, acc)

      # Conditional (3-tuple)
      {:conditional, _meta, [cond_expr, then_br, else_br]} ->
        acc = %{acc | operators: ["if" | acc.operators]}
        acc = walk(cond_expr, acc)
        acc = walk(then_br, acc)
        walk(else_br, acc)

      # Loop (3-tuple)
      {:loop, meta, children} when is_list(meta) ->
        loop_type = Keyword.get(meta, :loop_type, :for)
        acc = %{acc | operators: [to_string(loop_type) | acc.operators]}
        Enum.reduce(children, acc, fn child, a -> walk(child, a) end)

      # Assignment (3-tuple)
      {:assignment, _meta, [target, value]} ->
        acc = %{acc | operators: ["=" | acc.operators]}
        acc = walk(target, acc)
        walk(value, acc)

      # Inline match (3-tuple)
      {:inline_match, _meta, [pattern, value]} ->
        acc = %{acc | operators: ["=" | acc.operators]}
        acc = walk(pattern, acc)
        walk(value, acc)

      # Function call (3-tuple)
      {:function_call, meta, args} when is_list(meta) and is_list(args) ->
        name = Keyword.get(meta, :name, "anonymous")
        acc = %{acc | operators: ["()" | acc.operators]}
        acc = %{acc | operands: [name | acc.operands]}
        Enum.reduce(args, acc, fn arg, a -> walk(arg, a) end)

      # Exception handling (3-tuple)
      {:exception_handling, _meta, [try_block, catches, else_block]} ->
        acc = %{acc | operators: ["try" | acc.operators]}
        acc = walk(try_block, acc)

        catches_list = if is_list(catches), do: catches, else: []

        acc =
          Enum.reduce(catches_list, acc, fn catch_clause, a ->
            walk(catch_clause, a)
          end)

        walk(else_block, acc)

      # Pattern match (3-tuple)
      {:pattern_match, _meta, [value, branches | _]} ->
        acc = %{acc | operators: ["case" | acc.operators]}
        acc = walk(value, acc)

        branches_list = if is_list(branches), do: branches, else: []

        Enum.reduce(branches_list, acc, fn
          {:match_arm, _, [pattern, guard, body]}, a ->
            a = walk(pattern, a)
            a = if guard, do: walk(guard, a), else: a
            walk(body, a)

          {:pair, _, [pattern, branch]}, a ->
            a = walk(pattern, a)
            walk(branch, a)

          other, a ->
            walk(other, a)
        end)

      # Match arm (3-tuple)
      {:match_arm, _meta, [pattern, guard, body]} ->
        acc = walk(pattern, acc)
        acc = if guard, do: walk(guard, acc), else: acc
        walk(body, acc)

      # Early return (3-tuple)
      {:early_return, _meta, [value]} ->
        acc = %{acc | operators: ["return" | acc.operators]}
        walk(value, acc)

      # Block (3-tuple)
      {:block, _meta, stmts} when is_list(stmts) ->
        Enum.reduce(stmts, acc, fn stmt, a -> walk(stmt, a) end)

      # Lambda (3-tuple)
      {:lambda, meta, [body]} when is_list(meta) ->
        params = Keyword.get(meta, :params, [])
        acc = %{acc | operators: ["lambda" | acc.operators]}

        acc =
          Enum.reduce(params, acc, fn param, a ->
            %{a | operands: [param | a.operands]}
          end)

        walk(body, acc)

      # M2.2s: Structural/Organizational Types (3-tuple format)

      # Container (3-tuple)
      {:container, meta, [body]} when is_list(meta) ->
        container_type = Keyword.get(meta, :container_type, :class)
        name = Keyword.get(meta, :name, "anonymous")
        acc = %{acc | operators: [to_string(container_type) | acc.operators]}
        acc = %{acc | operands: [name | acc.operands]}

        members = if is_list(body), do: body, else: [body]
        Enum.reduce(members, acc, fn member, a -> walk(member, a) end)

      # Function definition (3-tuple)
      {:function_def, meta, [body]} when is_list(meta) ->
        name = Keyword.get(meta, :name, "anonymous")
        params = Keyword.get(meta, :params, [])
        visibility = Keyword.get(meta, :visibility, :public)
        acc = %{acc | operators: ["def", to_string(visibility) | acc.operators]}
        acc = %{acc | operands: [name | acc.operands]}

        # Walk parameters
        acc =
          Enum.reduce(params, acc, fn
            {:param, meta, param_name}, a when is_list(meta) and is_binary(param_name) ->
              pattern = Keyword.get(meta, :pattern)
              default = Keyword.get(meta, :default)
              a = %{a | operands: [param_name | a.operands]}
              a = if pattern, do: walk(pattern, a), else: a
              if default, do: walk(default, a), else: a

            param_name, a when is_binary(param_name) ->
              %{a | operands: [param_name | a.operands]}

            other, a ->
              walk(other, a)
          end)

        # Walk guards if present
        acc =
          case Keyword.get(meta, :guards) do
            nil -> acc
            guard -> walk(guard, acc)
          end

        walk(body, acc)

      # Attribute access (3-tuple)
      {:attribute_access, _meta, [obj, attr]} ->
        acc = %{acc | operators: ["." | acc.operators]}
        acc = %{acc | operands: [attr | acc.operands]}
        walk(obj, acc)

      # Augmented assignment (3-tuple)
      {:augmented_assignment, meta, [target, value]} when is_list(meta) ->
        op = Keyword.get(meta, :operator, :"+=")
        acc = %{acc | operators: [to_string(op) | acc.operators]}
        acc = walk(target, acc)
        walk(value, acc)

      # Property (3-tuple)
      {:property, meta, [getter, setter]} when is_list(meta) ->
        name = Keyword.get(meta, :name, "property")
        acc = %{acc | operators: ["property" | acc.operators]}
        acc = %{acc | operands: [name | acc.operands]}
        acc = if getter, do: walk(getter, acc), else: acc
        if setter, do: walk(setter, acc), else: acc

      # Collection operations (3-tuple)
      {:collection_op, meta, children} when is_list(meta) and is_list(children) ->
        op = Keyword.get(meta, :op, :map)
        acc = %{acc | operators: [to_string(op) | acc.operators]}
        Enum.reduce(children, acc, fn child, a -> walk(child, a) end)

      # List (3-tuple)
      {:list, _meta, elems} when is_list(elems) ->
        acc = %{acc | operators: ["list" | acc.operators]}
        Enum.reduce(elems, acc, fn elem, a -> walk(elem, a) end)

      # Map (3-tuple)
      {:map, _meta, pairs} when is_list(pairs) ->
        acc = %{acc | operators: ["map" | acc.operators]}

        Enum.reduce(pairs, acc, fn
          {:pair, _, [key, value]}, a ->
            a = walk(key, a)
            walk(value, a)

          other, a ->
            walk(other, a)
        end)

      # Async operation (3-tuple)
      {:async_operation, meta, [body]} when is_list(meta) ->
        async_type = Keyword.get(meta, :async_type, :async)
        acc = %{acc | operators: [to_string(async_type) | acc.operators]}
        walk(body, acc)

      # Literal (3-tuple)
      {:literal, _meta, value} ->
        %{acc | operands: [inspect(value) | acc.operands]}

      # Variable (3-tuple)
      {:variable, _meta, name} ->
        %{acc | operands: [name | acc.operands]}

      # Pair (3-tuple)
      {:pair, _meta, [key, value]} ->
        acc = walk(key, acc)
        walk(value, acc)

      # Language-specific (3-tuple)
      {:language_specific, meta, native_ast} when is_list(meta) ->
        acc = %{acc | operators: ["native" | acc.operators]}

        case native_ast do
          %{body: body} when not is_nil(body) -> walk(body, acc)
          _ -> acc
        end

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
