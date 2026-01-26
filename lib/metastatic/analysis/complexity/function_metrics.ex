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

      iex> ast = {:assignment, {:variable, "x"}, {:literal, :integer, 5}}
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

      iex> ast = {:early_return, {:variable, "x"}}
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

  defp walk_statements({:assignment, _, _}, count), do: count + 1
  defp walk_statements({:inline_match, _, _}, count), do: count + 1
  defp walk_statements({:function_call, _, _}, count), do: count + 1
  defp walk_statements({:early_return, _}, count), do: count + 1

  defp walk_statements({:conditional, _, then_br, else_br}, count) do
    count = count + 1
    count = walk_statements(then_br, count)
    walk_statements(else_br, count)
  end

  defp walk_statements({:loop, :while, _, body}, count) do
    count = count + 1
    walk_statements(body, count)
  end

  defp walk_statements({:loop, _, _, _, body}, count) do
    count = count + 1
    walk_statements(body, count)
  end

  defp walk_statements({:exception_handling, try_block, catches, else_block}, count) do
    count = count + 1
    count = walk_statements(try_block, count)

    count =
      Enum.reduce(catches, count, fn {_, _, catch_body}, c ->
        walk_statements(catch_body, c)
      end)

    walk_statements(else_block, count)
  end

  defp walk_statements({:pattern_match, _, branches}, count) do
    count = count + 1

    Enum.reduce(branches, count, fn
      {:match_arm, _pattern, _guard, body}, c -> walk_statements(body, c)
      {_, branch}, c -> walk_statements(branch, c)
    end)
  end

  defp walk_statements({:match_arm, _pattern, guard, body}, count) do
    count = if guard, do: walk_statements(guard, count), else: count
    walk_statements(body, count)
  end

  defp walk_statements({:lambda, _, body}, count) do
    count = count + 1
    walk_statements(body, count)
  end

  defp walk_statements({:block, stmts}, count) when is_list(stmts) do
    Enum.reduce(stmts, count, fn stmt, c -> walk_statements(stmt, c) end)
  end

  # M2.2s: Structural/Organizational Types

  # {:container, type, name, parent, type_params, implements, body}
  defp walk_statements(
         {:container, _type, _name, _parent, _type_params, _implements, body},
         count
       ) do
    count = count + 1
    walk_statements(body, count)
  end

  # {:function_def, name, params, ret_type, opts, body}
  defp walk_statements({:function_def, _name, params, _ret_type, opts, body}, count) do
    count = count + 1

    # Walk parameters (new format: {:param, name, pattern, default})
    count =
      Enum.reduce(params, count, fn
        {:param, _name, pattern, default}, c ->
          c = if pattern, do: walk_statements(pattern, c), else: c
          if default, do: walk_statements(default, c), else: c

        _simple_param, c ->
          c
      end)

    # Walk guards if present (now in opts map)
    count =
      if is_map(opts) do
        case Map.get(opts, :guards) do
          nil -> count
          guard -> walk_statements(guard, count)
        end
      else
        count
      end

    # Walk body
    walk_statements(body, count)
  end

  defp walk_statements({:attribute_access, obj, _attr}, count) do
    walk_statements(obj, count)
  end

  defp walk_statements({:augmented_assignment, _op, _target, value}, count) do
    count = count + 1
    walk_statements(value, count)
  end

  defp walk_statements({:property, _name, getter, setter, _metadata}, count) do
    count = count + 1
    count = if getter, do: walk_statements(getter, count), else: count
    if setter, do: walk_statements(setter, count), else: count
  end

  defp walk_statements({:async_operation, _, body}, count) do
    count = count + 1
    walk_statements(body, count)
  end

  # Language-specific: traverse embedded body if present
  defp walk_statements({:language_specific, _, _, _, metadata}, count) when is_map(metadata) do
    count = count + 1

    case Map.get(metadata, :body) do
      nil -> count
      body -> walk_statements(body, count)
    end
  end

  defp walk_statements({:language_specific, _, _, _}, count), do: count + 1
  defp walk_statements({:language_specific, _, _}, count), do: count + 1
  defp walk_statements(nil, count), do: count
  defp walk_statements(_, count), do: count

  defp count_returns(ast) do
    walk_returns(ast, 0)
  end

  defp walk_returns({:early_return, _}, count), do: count + 1

  defp walk_returns({:conditional, _, then_br, else_br}, count) do
    count = walk_returns(then_br, count)
    walk_returns(else_br, count)
  end

  defp walk_returns({:loop, :while, _, body}, count), do: walk_returns(body, count)
  defp walk_returns({:loop, _, _, _, body}, count), do: walk_returns(body, count)

  defp walk_returns({:exception_handling, try_block, catches, else_block}, count) do
    count = walk_returns(try_block, count)

    count =
      Enum.reduce(catches, count, fn {_, _, catch_body}, c ->
        walk_returns(catch_body, c)
      end)

    walk_returns(else_block, count)
  end

  defp walk_returns({:pattern_match, _, branches}, count) do
    Enum.reduce(branches, count, fn
      {:match_arm, _pattern, _guard, body}, c -> walk_returns(body, c)
      {_, branch}, c -> walk_returns(branch, c)
    end)
  end

  defp walk_returns({:match_arm, _pattern, guard, body}, count) do
    count = if guard, do: walk_returns(guard, count), else: count
    walk_returns(body, count)
  end

  defp walk_returns({:lambda, _, body}, count), do: walk_returns(body, count)

  defp walk_returns({:block, stmts}, count) when is_list(stmts) do
    Enum.reduce(stmts, count, fn stmt, c -> walk_returns(stmt, c) end)
  end

  # M2.2s: Structural/Organizational Types

  # {:container, type, name, parent, type_params, implements, body}
  defp walk_returns({:container, _type, _name, _parent, _type_params, _implements, body}, count) do
    walk_returns(body, count)
  end

  # {:function_def, name, params, ret_type, opts, body}
  defp walk_returns({:function_def, _name, params, _ret_type, opts, body}, count) do
    # Walk parameters (new format: {:param, name, pattern, default})
    count =
      Enum.reduce(params, count, fn
        {:param, _name, pattern, default}, c ->
          c = if pattern, do: walk_returns(pattern, c), else: c
          if default, do: walk_returns(default, c), else: c

        _simple_param, c ->
          c
      end)

    # Walk guards if present (now in opts map)
    count =
      if is_map(opts) do
        case Map.get(opts, :guards) do
          nil -> count
          guard -> walk_returns(guard, count)
        end
      else
        count
      end

    # Walk body
    walk_returns(body, count)
  end

  defp walk_returns({:attribute_access, obj, _attr}, count) do
    walk_returns(obj, count)
  end

  defp walk_returns({:augmented_assignment, _op, _target, value}, count) do
    walk_returns(value, count)
  end

  defp walk_returns({:property, _name, getter, setter, _metadata}, count) do
    count = if getter, do: walk_returns(getter, count), else: count
    if setter, do: walk_returns(setter, count), else: count
  end

  defp walk_returns({:async_operation, _, body}, count), do: walk_returns(body, count)

  # Language-specific: traverse embedded body if present
  defp walk_returns({:language_specific, _, _, _, metadata}, count) when is_map(metadata) do
    case Map.get(metadata, :body) do
      nil -> count
      body -> walk_returns(body, count)
    end
  end

  defp walk_returns({:language_specific, _, _, _}, count), do: count
  defp walk_returns({:language_specific, _, _}, count), do: count
  defp walk_returns(nil, count), do: count
  defp walk_returns(_, count), do: count
end
