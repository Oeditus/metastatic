defmodule Metastatic.Analysis.Complexity.LoC do
  @moduledoc """
  Lines of Code (LoC) metrics calculation.

  Calculates logical lines of code by counting statements in the MetaAST,
  and extracts physical/comment lines from metadata when available.

  ## Metrics

  - **Logical LoC**: Count of executable statements at M2 level
  - **Physical LoC**: Raw line count from source (from metadata)
  - **Comment lines**: Lines containing only comments (from metadata)
  - **Blank lines**: Physical - Logical - Comments

  ## What Counts as Logical Line

  Each statement counts as one logical line:
  - Assignments
  - Function calls
  - Early returns
  - Conditionals
  - Loops
  - Pattern matches
  - Exception handling

  Expressions within statements don't count separately.

  ## Examples

      iex> ast = {:literal, :integer, 42}
      iex> metrics = Metastatic.Analysis.Complexity.LoC.calculate(ast)
      iex> metrics.logical
      0
  """

  alias Metastatic.AST

  @type t :: %{
          physical: non_neg_integer(),
          logical: non_neg_integer(),
          comments: non_neg_integer(),
          blank: non_neg_integer()
        }

  @doc """
  Calculates LoC metrics for a MetaAST node.

  Optionally takes metadata map which may contain:
  - `:line_count` - Physical line count
  - `:comment_lines` - Number of comment lines

  ## Examples

      iex> ast = {:assignment, {:variable, "x"}, {:literal, :integer, 5}}
      iex> metrics = Metastatic.Analysis.Complexity.LoC.calculate(ast)
      iex> metrics.logical
      1

      iex> ast = {:block, [{:variable, "x"}, {:variable, "y"}]}
      iex> metrics = Metastatic.Analysis.Complexity.LoC.calculate(ast)
      iex> metrics.logical
      0
  """
  @spec calculate(AST.meta_ast(), map()) :: t()
  def calculate(ast, metadata \\ %{}) do
    logical = count_logical_lines(ast)

    # Extract from metadata or estimate
    physical = Map.get(metadata, :line_count, logical)
    comments = Map.get(metadata, :comment_lines, 0)
    blank = max(0, physical - logical - comments)

    %{
      physical: physical,
      logical: logical,
      comments: comments,
      blank: blank
    }
  end

  # Private implementation

  defp count_logical_lines(ast) do
    walk(ast, 0)
  end

  # Statements count as logical lines

  defp walk({:assignment, target, value}, count) do
    count = count + 1
    count = walk_expr(target, count)
    walk_expr(value, count)
  end

  defp walk({:inline_match, pattern, value}, count) do
    count = count + 1
    count = walk_expr(pattern, count)
    walk_expr(value, count)
  end

  defp walk({:function_call, _name, args}, count) do
    count = count + 1
    Enum.reduce(args, count, fn arg, c -> walk_expr(arg, c) end)
  end

  defp walk({:early_return, value}, count) do
    count = count + 1
    walk_expr(value, count)
  end

  defp walk({:conditional, cond, then_br, else_br}, count) do
    count = count + 1
    count = walk_expr(cond, count)
    count = walk(then_br, count)
    walk(else_br, count)
  end

  defp walk({:loop, :while, cond, body}, count) do
    count = count + 1
    count = walk_expr(cond, count)
    walk(body, count)
  end

  defp walk({:loop, _, iter, coll, body}, count) do
    count = count + 1
    count = walk_expr(iter, count)
    count = walk_expr(coll, count)
    walk(body, count)
  end

  defp walk({:exception_handling, try_block, catches, else_block}, count) do
    count = count + 1
    count = walk(try_block, count)

    count =
      Enum.reduce(catches, count, fn {_type, var, catch_body}, c ->
        c = walk_expr(var, c)
        walk(catch_body, c)
      end)

    walk(else_block, count)
  end

  defp walk({:pattern_match, value, branches}, count) do
    count = count + 1
    count = walk_expr(value, count)

    Enum.reduce(branches, count, fn
      {:match_arm, pattern, guard, body}, c ->
        c = walk_expr(pattern, c)
        c = if guard, do: walk_expr(guard, c), else: c
        walk(body, c)

      {pattern, branch}, c ->
        c = walk_expr(pattern, c)
        walk(branch, c)
    end)
  end

  defp walk({:match_arm, pattern, guard, body}, count) do
    count = walk_expr(pattern, count)
    count = if guard, do: walk_expr(guard, count), else: count
    walk(body, count)
  end

  defp walk({:lambda, _params, body}, count) do
    # Lambda definition is a statement
    count = count + 1
    walk(body, count)
  end

  defp walk({:block, stmts}, count) when is_list(stmts) do
    Enum.reduce(stmts, count, fn stmt, c -> walk(stmt, c) end)
  end

  # M2.2s: Structural/Organizational Types

  defp walk({:container, _type, _name, _metadata, members}, count) when is_list(members) do
    count = count + 1
    Enum.reduce(members, count, fn member, c -> walk(member, c) end)
  end

  defp walk({:function_def, _visibility, _name, params, metadata, body}, count) do
    count = count + 1

    # Walk parameters
    count =
      Enum.reduce(params, count, fn
        {:pattern, pattern}, c -> walk_expr(pattern, c)
        {:default, _name, default}, c -> walk_expr(default, c)
        _simple_param, c -> c
      end)

    # Walk guards if present
    count =
      case Map.get(metadata, :guards) do
        nil -> count
        guard -> walk_expr(guard, count)
      end

    # Walk body
    walk(body, count)
  end

  defp walk({:attribute_access, obj, _attr}, count) do
    # Attribute access is not a statement, walk as expression
    walk_expr(obj, count)
  end

  defp walk({:augmented_assignment, _op, _target, value}, count) do
    count = count + 1
    walk_expr(value, count)
  end

  defp walk({:property, _name, getter, setter, _metadata}, count) do
    count = count + 1
    count = if getter, do: walk(getter, count), else: count
    if setter, do: walk(setter, count), else: count
  end

  defp walk({:collection_op, _, func, coll}, count) do
    count = walk_expr(func, count)
    walk_expr(coll, count)
  end

  defp walk({:collection_op, _, func, coll, init}, count) do
    count = walk_expr(func, count)
    count = walk_expr(coll, count)
    walk_expr(init, count)
  end

  defp walk({:async_operation, _type, body}, count) do
    count = count + 1
    walk(body, count)
  end

  # Language-specific: traverse embedded body if present
  defp walk({:language_specific, _, _, _, metadata}, count) when is_map(metadata) do
    count = count + 1

    case Map.get(metadata, :body) do
      nil -> count
      body -> walk(body, count)
    end
  end

  defp walk({:language_specific, _, _, _}, count), do: count + 1
  defp walk({:language_specific, _, _}, count), do: count + 1

  # Expressions don't count
  defp walk(expr, count), do: walk_expr(expr, count)

  # walk_expr: traverse expressions without counting them as lines

  defp walk_expr({:binary_op, _, _, left, right}, count) do
    count = walk_expr(left, count)
    walk_expr(right, count)
  end

  defp walk_expr({:unary_op, _, operand}, count) do
    walk_expr(operand, count)
  end

  defp walk_expr({:tuple, elems}, count) when is_list(elems) do
    Enum.reduce(elems, count, fn elem, c -> walk_expr(elem, c) end)
  end

  defp walk_expr({:list, elems}, count) when is_list(elems) do
    Enum.reduce(elems, count, fn elem, c -> walk_expr(elem, c) end)
  end

  defp walk_expr({:map, pairs}, count) when is_list(pairs) do
    Enum.reduce(pairs, count, fn {key, value}, c ->
      c = walk_expr(key, c)
      walk_expr(value, c)
    end)
  end

  defp walk_expr({:literal, _, _}, count), do: count
  defp walk_expr({:variable, _}, count), do: count
  defp walk_expr(nil, count), do: count
  defp walk_expr(_, count), do: count
end
