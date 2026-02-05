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

      iex> ast = {:literal, [subtype: :integer], 42}
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

      iex> ast = {:assignment, [], [{:variable, [], "x"}, {:literal, [subtype: :integer], 5}]}
      iex> metrics = Metastatic.Analysis.Complexity.LoC.calculate(ast)
      iex> metrics.logical
      1

      iex> ast = {:block, [], [{:variable, [], "x"}, {:variable, [], "y"}]}
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

  # Statements count as logical lines (3-tuple format)

  defp walk({:assignment, _meta, [target, value]}, count) do
    count = count + 1
    count = walk_expr(target, count)
    walk_expr(value, count)
  end

  defp walk({:inline_match, _meta, [pattern, value]}, count) do
    count = count + 1
    count = walk_expr(pattern, count)
    walk_expr(value, count)
  end

  defp walk({:function_call, _meta, args}, count) when is_list(args) do
    count = count + 1
    Enum.reduce(args, count, fn arg, c -> walk_expr(arg, c) end)
  end

  defp walk({:early_return, _meta, [value]}, count) do
    count = count + 1
    walk_expr(value, count)
  end

  defp walk({:conditional, _meta, [cond_expr, then_br, else_br]}, count) do
    count = count + 1
    count = walk_expr(cond_expr, count)
    count = walk(then_br, count)
    walk(else_br, count)
  end

  defp walk({:loop, meta, children}, count) when is_list(meta) and is_list(children) do
    count = count + 1
    Enum.reduce(children, count, fn child, c -> walk(child, c) end)
  end

  defp walk({:exception_handling, _meta, [try_block, catches, else_block]}, count) do
    count = count + 1
    count = walk(try_block, count)

    catches_list = if is_list(catches), do: catches, else: []

    count =
      Enum.reduce(catches_list, count, fn catch_clause, c ->
        walk(catch_clause, c)
      end)

    walk(else_block, count)
  end

  defp walk({:pattern_match, _meta, [value, branches | _]}, count) do
    count = count + 1
    count = walk_expr(value, count)

    branches_list = if is_list(branches), do: branches, else: []

    Enum.reduce(branches_list, count, fn
      {:match_arm, _, [pattern, guard, body]}, c ->
        c = walk_expr(pattern, c)
        c = if guard, do: walk_expr(guard, c), else: c
        walk(body, c)

      {:pair, _, [pattern, branch]}, c ->
        c = walk_expr(pattern, c)
        walk(branch, c)

      other, c ->
        walk(other, c)
    end)
  end

  defp walk({:match_arm, _meta, [pattern, guard, body]}, count) do
    count = walk_expr(pattern, count)
    count = if guard, do: walk_expr(guard, count), else: count
    walk(body, count)
  end

  defp walk({:lambda, _meta, [body]}, count) do
    # Lambda definition is a statement
    count = count + 1
    walk(body, count)
  end

  defp walk({:block, _meta, stmts}, count) when is_list(stmts) do
    Enum.reduce(stmts, count, fn stmt, c -> walk(stmt, c) end)
  end

  # M2.2s: Structural/Organizational Types (3-tuple format)

  # Container (3-tuple)
  defp walk({:container, meta, [body]}, count) when is_list(meta) do
    count = count + 1

    if is_list(body) do
      Enum.reduce(body, count, fn member, c -> walk(member, c) end)
    else
      walk(body, count)
    end
  end

  # Function definition (3-tuple)
  defp walk({:function_def, meta, [body]}, count) when is_list(meta) do
    count = count + 1
    params = Keyword.get(meta, :params, [])

    # Walk parameters
    count =
      Enum.reduce(params, count, fn
        {:param, _, [_name, pattern, default]}, c ->
          c = if pattern, do: walk_expr(pattern, c), else: c
          if default, do: walk_expr(default, c), else: c

        _simple_param, c ->
          c
      end)

    # Walk guards if present
    count =
      case Keyword.get(meta, :guards) do
        nil -> count
        guard -> walk_expr(guard, count)
      end

    # Walk body
    walk(body, count)
  end

  defp walk({:attribute_access, _meta, [obj, _attr]}, count) do
    # Attribute access is not a statement, walk as expression
    walk_expr(obj, count)
  end

  defp walk({:augmented_assignment, _meta, [_target, value]}, count) do
    count = count + 1
    walk_expr(value, count)
  end

  defp walk({:property, _meta, [getter, setter]}, count) do
    count = count + 1
    count = if getter, do: walk(getter, count), else: count
    if setter, do: walk(setter, count), else: count
  end

  defp walk({:collection_op, _meta, children}, count) when is_list(children) do
    Enum.reduce(children, count, fn child, c -> walk_expr(child, c) end)
  end

  defp walk({:async_operation, _meta, [body]}, count) do
    count = count + 1
    walk(body, count)
  end

  # Language-specific (3-tuple)
  defp walk({:language_specific, meta, native_ast}, count) when is_list(meta) do
    count = count + 1

    case native_ast do
      %{body: body} when not is_nil(body) -> walk(body, count)
      _ -> count
    end
  end

  # Expressions don't count
  defp walk(expr, count), do: walk_expr(expr, count)

  # walk_expr: traverse expressions without counting them as lines (3-tuple format)

  defp walk_expr({:binary_op, _meta, [left, right]}, count) do
    count = walk_expr(left, count)
    walk_expr(right, count)
  end

  defp walk_expr({:unary_op, _meta, [operand]}, count) do
    walk_expr(operand, count)
  end

  defp walk_expr({:list, _meta, elems}, count) when is_list(elems) do
    Enum.reduce(elems, count, fn elem, c -> walk_expr(elem, c) end)
  end

  defp walk_expr({:map, _meta, pairs}, count) when is_list(pairs) do
    Enum.reduce(pairs, count, fn
      {:pair, _, [key, value]}, c ->
        c = walk_expr(key, c)
        walk_expr(value, c)

      other, c ->
        walk_expr(other, c)
    end)
  end

  defp walk_expr({:literal, _, _}, count), do: count
  defp walk_expr({:variable, _, _}, count), do: count
  defp walk_expr(nil, count), do: count
  defp walk_expr(_, count), do: count
end
