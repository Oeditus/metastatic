defmodule Metastatic.Analysis.Complexity.FunctionMetrics do
  @moduledoc """
  Function-level complexity metrics.

  Note: MetaAST currently doesn't have a function_definition construct.
  For Phase 4, we analyze the entire document as a single "function".

  Future enhancement: Add function_definition to MetaAST M2.2 Extended layer
  for per-function analysis.

  ## Metrics

  - **Statement count**: Number of executable statements
  - **Return points**: Number of early_return nodes
  - **Variable count**: Number of distinct variables used
  - **Parameter count**: 0 (not applicable without function_definition)

  ## Examples

      iex> ast = {:assignment, [], [{:variable, [], "x"}, {:literal, [subtype: :integer], 5}]}
      iex> metrics = Metastatic.Analysis.Complexity.FunctionMetrics.calculate(ast)
      iex> metrics.statement_count
      1
      iex> metrics.variable_count
      1
  """

  alias Metastatic.AST

  @type t :: %{
          statement_count: non_neg_integer(),
          return_points: non_neg_integer(),
          variable_count: non_neg_integer(),
          parameter_count: non_neg_integer()
        }

  @doc """
  Calculates function-level metrics for a MetaAST node.

  ## Examples

      iex> ast = {:early_return, [], [{:variable, [], "x"}]}
      iex> metrics = Metastatic.Analysis.Complexity.FunctionMetrics.calculate(ast)
      iex> metrics.return_points
      1
  """
  @spec calculate(AST.meta_ast()) :: t()
  def calculate(ast) do
    statement_count = count_statements(ast)
    return_points = count_returns(ast)
    variables = AST.variables(ast)
    variable_count = MapSet.size(variables)

    %{
      statement_count: statement_count,
      return_points: return_points,
      variable_count: variable_count,
      parameter_count: 0
    }
  end

  # Private implementation

  defp count_statements(ast) do
    walk_statements(ast, 0)
  end

  # 3-tuple format patterns
  defp walk_statements({:assignment, _meta, _children}, count), do: count + 1
  defp walk_statements({:inline_match, _meta, _children}, count), do: count + 1
  defp walk_statements({:function_call, _meta, _args}, count), do: count + 1
  defp walk_statements({:early_return, _meta, _children}, count), do: count + 1

  defp walk_statements({:conditional, _meta, [_cond, then_br, else_br]}, count) do
    count = count + 1
    count = walk_statements(then_br, count)
    walk_statements(else_br, count)
  end

  defp walk_statements({:loop, meta, children}, count) when is_list(meta) and is_list(children) do
    count = count + 1
    Enum.reduce(children, count, fn child, c -> walk_statements(child, c) end)
  end

  defp walk_statements({:exception_handling, _meta, [try_block, catches, else_block]}, count) do
    count = count + 1
    count = walk_statements(try_block, count)

    catches_list = if is_list(catches), do: catches, else: []

    count =
      Enum.reduce(catches_list, count, fn catch_clause, c ->
        walk_statements(catch_clause, c)
      end)

    walk_statements(else_block, count)
  end

  defp walk_statements({:pattern_match, _meta, [_value, branches | _]}, count) do
    count = count + 1

    branches_list = if is_list(branches), do: branches, else: []

    Enum.reduce(branches_list, count, fn
      {:match_arm, _, [_pattern, _guard, body]}, c -> walk_statements(body, c)
      {:pair, _, [_, branch]}, c -> walk_statements(branch, c)
      other, c -> walk_statements(other, c)
    end)
  end

  defp walk_statements({:match_arm, _meta, [_pattern, guard, body]}, count) do
    count = if guard, do: walk_statements(guard, count), else: count
    walk_statements(body, count)
  end

  defp walk_statements({:lambda, _meta, [body]}, count) do
    count = count + 1
    walk_statements(body, count)
  end

  defp walk_statements({:block, _meta, stmts}, count) when is_list(stmts) do
    Enum.reduce(stmts, count, fn stmt, c -> walk_statements(stmt, c) end)
  end

  # M2.2s: Structural/Organizational Types (3-tuple format)

  # Container (3-tuple)
  defp walk_statements({:container, meta, [body]}, count) when is_list(meta) do
    count = count + 1
    walk_statements(body, count)
  end

  # Function definition (3-tuple)
  defp walk_statements({:function_def, meta, [body]}, count) when is_list(meta) do
    count = count + 1
    params = Keyword.get(meta, :params, [])

    # Walk parameters
    count =
      Enum.reduce(params, count, fn
        {:param, _, [_name, pattern, default]}, c ->
          c = if pattern, do: walk_statements(pattern, c), else: c
          if default, do: walk_statements(default, c), else: c

        _simple_param, c ->
          c
      end)

    # Walk guards if present
    count =
      case Keyword.get(meta, :guards) do
        nil -> count
        guard -> walk_statements(guard, count)
      end

    # Walk body
    walk_statements(body, count)
  end

  defp walk_statements({:attribute_access, _meta, [obj, _attr]}, count) do
    walk_statements(obj, count)
  end

  defp walk_statements({:augmented_assignment, _meta, [_target, value]}, count) do
    count = count + 1
    walk_statements(value, count)
  end

  defp walk_statements({:property, _meta, [getter, setter]}, count) do
    count = count + 1
    count = if getter, do: walk_statements(getter, count), else: count
    if setter, do: walk_statements(setter, count), else: count
  end

  defp walk_statements({:async_operation, _meta, [body]}, count) do
    count = count + 1
    walk_statements(body, count)
  end

  # Language-specific (3-tuple)
  defp walk_statements({:language_specific, meta, native_ast}, count) when is_list(meta) do
    count = count + 1

    case native_ast do
      %{body: body} when not is_nil(body) -> walk_statements(body, count)
      _ -> count
    end
  end

  defp walk_statements(nil, count), do: count
  defp walk_statements(_, count), do: count

  defp count_returns(ast) do
    walk_returns(ast, 0)
  end

  defp walk_returns({:early_return, _meta, _children}, count), do: count + 1

  defp walk_returns({:conditional, _meta, [_cond, then_br, else_br]}, count) do
    count = walk_returns(then_br, count)
    walk_returns(else_br, count)
  end

  defp walk_returns({:loop, meta, children}, count) when is_list(meta) and is_list(children) do
    Enum.reduce(children, count, fn child, c -> walk_returns(child, c) end)
  end

  defp walk_returns({:exception_handling, _meta, [try_block, catches, else_block]}, count) do
    count = walk_returns(try_block, count)

    catches_list = if is_list(catches), do: catches, else: []

    count =
      Enum.reduce(catches_list, count, fn catch_clause, c ->
        walk_returns(catch_clause, c)
      end)

    walk_returns(else_block, count)
  end

  defp walk_returns({:pattern_match, _meta, [_value, branches | _]}, count) do
    branches_list = if is_list(branches), do: branches, else: []

    Enum.reduce(branches_list, count, fn
      {:match_arm, _, [_pattern, _guard, body]}, c -> walk_returns(body, c)
      {:pair, _, [_, branch]}, c -> walk_returns(branch, c)
      other, c -> walk_returns(other, c)
    end)
  end

  defp walk_returns({:match_arm, _meta, [_pattern, guard, body]}, count) do
    count = if guard, do: walk_returns(guard, count), else: count
    walk_returns(body, count)
  end

  defp walk_returns({:lambda, _meta, [body]}, count), do: walk_returns(body, count)

  defp walk_returns({:block, _meta, stmts}, count) when is_list(stmts) do
    Enum.reduce(stmts, count, fn stmt, c -> walk_returns(stmt, c) end)
  end

  # M2.2s: Structural/Organizational Types (3-tuple format)

  # Container (3-tuple)
  defp walk_returns({:container, meta, [body]}, count) when is_list(meta) do
    walk_returns(body, count)
  end

  # Function definition (3-tuple)
  defp walk_returns({:function_def, meta, [body]}, count) when is_list(meta) do
    params = Keyword.get(meta, :params, [])

    # Walk parameters
    count =
      Enum.reduce(params, count, fn
        {:param, _, [_name, pattern, default]}, c ->
          c = if pattern, do: walk_returns(pattern, c), else: c
          if default, do: walk_returns(default, c), else: c

        _simple_param, c ->
          c
      end)

    # Walk guards if present
    count =
      case Keyword.get(meta, :guards) do
        nil -> count
        guard -> walk_returns(guard, count)
      end

    # Walk body
    walk_returns(body, count)
  end

  defp walk_returns({:attribute_access, _meta, [obj, _attr]}, count) do
    walk_returns(obj, count)
  end

  defp walk_returns({:augmented_assignment, _meta, [_target, value]}, count) do
    walk_returns(value, count)
  end

  defp walk_returns({:property, _meta, [getter, setter]}, count) do
    count = if getter, do: walk_returns(getter, count), else: count
    if setter, do: walk_returns(setter, count), else: count
  end

  defp walk_returns({:async_operation, _meta, [body]}, count), do: walk_returns(body, count)

  # Language-specific (3-tuple)
  defp walk_returns({:language_specific, meta, native_ast}, count) when is_list(meta) do
    case native_ast do
      %{body: body} when not is_nil(body) -> walk_returns(body, count)
      _ -> count
    end
  end

  defp walk_returns(nil, count), do: count
  defp walk_returns(_, count), do: count
end
