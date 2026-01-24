defmodule Metastatic.Analysis.Analyzers.UnusedVariables do
  @moduledoc """
  Detects variables that are assigned but never used.

  This analyzer tracks all variable assignments and usages across the AST,
  then reports any variables that were assigned but never referenced.

  ## Configuration

  - `:ignore_prefix` - Ignore variables starting with this prefix (default: `"_"`)
  - `:ignore_names` - List of variable names to ignore (default: `[]`)

  ## Examples

      # Will be flagged
      x = 5
      y = 10
      return y  # x is unused

      # Will not be flagged (underscore prefix)
      _temp = compute()
      result = process()
      return result
  """

  @behaviour Metastatic.Analysis.Analyzer

  alias Metastatic.Analysis.Analyzer

  @impl true
  def info do
    %{
      name: :unused_variables,
      category: :correctness,
      description: "Detects variables that are assigned but never used",
      severity: :warning,
      explanation: """
      Variables that are assigned but never referenced add noise to the code
      and may indicate bugs, incomplete code, or forgotten cleanup.

      Consider removing unused variables or prefixing them with underscore
      if they must exist for API compatibility.
      """,
      configurable: true
    }
  end

  @impl true
  def analyze(_node, _context), do: []

  @impl true
  def run_after(context, issues) do
    # Collect assignments and usages from the full AST
    {assigned, used} = collect_variables(context.document.ast)

    # Get configuration
    config = context.config
    ignore_prefix = Map.get(config, :ignore_prefix, "_")
    ignore_names = Map.get(config, :ignore_names, [])

    # Find unused variables
    unused =
      assigned
      |> MapSet.difference(used)
      |> Enum.filter(&(not should_ignore?(&1, ignore_prefix, ignore_names)))

    # Generate issues
    new_issues =
      Enum.map(unused, fn var ->
        Analyzer.issue(
          analyzer: __MODULE__,
          category: :correctness,
          severity: :warning,
          message: "Variable '#{var}' is assigned but never used",
          node: {:variable, var},
          location: %{line: nil, column: nil, path: nil},
          suggestion:
            Analyzer.suggestion(
              type: :remove,
              replacement: nil,
              message:
                "Consider removing this unused variable or prefixing with '#{ignore_prefix}'"
            ),
          metadata: %{variable: var}
        )
      end)

    issues ++ new_issues
  end

  # ----- Private Helpers -----

  defp collect_variables(ast) do
    walk_collect(ast, {MapSet.new(), MapSet.new()})
  end

  defp walk_collect({:assignment, {:variable, name}, value}, {assigned, used}) do
    # Variable is assigned
    assigned = MapSet.put(assigned, name)
    # Check if value references other variables
    {assigned, used} = walk_collect(value, {assigned, used})
    {assigned, used}
  end

  defp walk_collect({:variable, name}, {assigned, used}) do
    # Variable is used
    used = MapSet.put(used, name)
    {assigned, used}
  end

  defp walk_collect({:binary_op, _, _, left, right}, acc) do
    acc = walk_collect(left, acc)
    walk_collect(right, acc)
  end

  defp walk_collect({:unary_op, _, _, operand}, acc) do
    walk_collect(operand, acc)
  end

  defp walk_collect({:conditional, cond, then_br, else_br}, acc) do
    acc = walk_collect(cond, acc)
    acc = walk_collect(then_br, acc)
    walk_collect(else_br, acc)
  end

  defp walk_collect({:block, stmts}, acc) when is_list(stmts) do
    Enum.reduce(stmts, acc, fn stmt, a -> walk_collect(stmt, a) end)
  end

  defp walk_collect({:function_call, _name, args}, acc) do
    Enum.reduce(args, acc, fn arg, a -> walk_collect(arg, a) end)
  end

  defp walk_collect({:loop, :while, cond, body}, acc) do
    acc = walk_collect(cond, acc)
    walk_collect(body, acc)
  end

  defp walk_collect({:loop, _, iter, coll, body}, acc) do
    acc = walk_collect(iter, acc)
    acc = walk_collect(coll, acc)
    walk_collect(body, acc)
  end

  defp walk_collect({:lambda, _params, body}, acc) do
    walk_collect(body, acc)
  end

  defp walk_collect({:collection_op, _, func, coll}, acc) do
    acc = walk_collect(func, acc)
    walk_collect(coll, acc)
  end

  defp walk_collect({:collection_op, _, func, coll, init}, acc) do
    acc = walk_collect(func, acc)
    acc = walk_collect(coll, acc)
    walk_collect(init, acc)
  end

  defp walk_collect({:early_return, value}, acc) do
    walk_collect(value, acc)
  end

  defp walk_collect({:inline_match, pattern, value}, acc) do
    acc = walk_collect(pattern, acc)
    walk_collect(value, acc)
  end

  defp walk_collect({:attribute_access, obj, _attr}, acc) do
    walk_collect(obj, acc)
  end

  defp walk_collect({:augmented_assignment, target, _op, value}, acc) do
    acc = walk_collect(target, acc)
    walk_collect(value, acc)
  end

  defp walk_collect(list, acc) when is_list(list) do
    Enum.reduce(list, acc, fn item, a -> walk_collect(item, a) end)
  end

  defp walk_collect(_other, acc), do: acc

  defp should_ignore?(var_name, ignore_prefix, ignore_names) do
    String.starts_with?(var_name, ignore_prefix) or var_name in ignore_names
  end
end
