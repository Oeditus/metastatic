defmodule Metastatic.Analysis.SimplifyConditional do
  @moduledoc """
  Suggests simplification of redundant conditionals.

  Detects conditionals that return boolean literals and can be simplified
  to direct boolean expressions.

  ## Patterns Detected

  1. `if condition then true else false` → `condition`
  2. `if condition then false else true` → `not condition`
  3. `if condition then condition else false` → `condition`
  4. `if condition then true else condition` → `condition`

  ## Examples

      # Before
      if x > 5 then true else false

      # After
      x > 5

      # Before
      if is_valid then false else true

      # After
      not is_valid
  """

  alias Metastatic.Analysis.Analyzer
  @behaviour Analyzer

  @impl Analyzer
  def info do
    %{
      name: :simplify_conditional,
      category: :refactoring,
      description: "Suggests simplification of redundant conditionals",
      severity: :refactoring_opportunity,
      explanation: """
      Conditionals that return boolean literals can often be simplified
      to direct boolean expressions, making the code more concise and easier
      to understand.

      This is especially common in guard clauses or validation logic.
      """,
      configurable: false
    }
  end

  @impl Analyzer
  def analyze({:conditional, _meta, [condition, then_branch, else_branch]} = node, _context) do
    # Check for simplifiable patterns
    case {then_branch, else_branch} do
      # Pattern: if condition then true else false => condition
      {{:literal, then_meta, true}, {:literal, else_meta, false}} ->
        if boolean_literal?(then_meta) and boolean_literal?(else_meta) do
          [
            Analyzer.issue(
              analyzer: __MODULE__,
              category: :refactoring,
              severity: :refactoring_opportunity,
              message: "This conditional can be simplified to just the condition",
              node: node,
              location: %{line: nil, column: nil, path: nil},
              suggestion:
                Analyzer.suggestion(
                  type: :replace,
                  replacement: condition,
                  message: "Replace with: #{format_node(condition)}"
                ),
              metadata: %{pattern: :true_false, simplified: condition}
            )
          ]
        else
          []
        end

      # Pattern: if condition then false else true => not condition
      {{:literal, then_meta, false}, {:literal, else_meta, true}} ->
        if boolean_literal?(then_meta) and boolean_literal?(else_meta) do
          negated = {:unary_op, [category: :boolean, operator: :not], [condition]}

          [
            Analyzer.issue(
              analyzer: __MODULE__,
              category: :refactoring,
              severity: :refactoring_opportunity,
              message: "This conditional can be simplified to the negation of the condition",
              node: node,
              location: %{line: nil, column: nil, path: nil},
              suggestion:
                Analyzer.suggestion(
                  type: :replace,
                  replacement: negated,
                  message: "Replace with: not #{format_node(condition)}"
                ),
              metadata: %{pattern: :false_true, simplified: negated}
            )
          ]
        else
          []
        end

      # Pattern: if condition then condition else false => condition
      {cond_duplicate, {:literal, else_meta, false}} when condition == cond_duplicate ->
        if boolean_literal?(else_meta) do
          [
            Analyzer.issue(
              analyzer: __MODULE__,
              category: :refactoring,
              severity: :refactoring_opportunity,
              message:
                "This conditional returns its condition in the then branch and false in else",
              node: node,
              location: %{line: nil, column: nil, path: nil},
              suggestion:
                Analyzer.suggestion(
                  type: :replace,
                  replacement: condition,
                  message: "Replace with: #{format_node(condition)}"
                ),
              metadata: %{pattern: :condition_false, simplified: condition}
            )
          ]
        else
          []
        end

      # Pattern: if condition then true else condition => condition
      {{:literal, then_meta, true}, cond_duplicate} when condition == cond_duplicate ->
        if boolean_literal?(then_meta) do
          [
            Analyzer.issue(
              analyzer: __MODULE__,
              category: :refactoring,
              severity: :refactoring_opportunity,
              message: "This conditional returns true in then branch and its condition in else",
              node: node,
              location: %{line: nil, column: nil, path: nil},
              suggestion:
                Analyzer.suggestion(
                  type: :replace,
                  replacement: condition,
                  message: "Replace with: #{format_node(condition)}"
                ),
              metadata: %{pattern: :true_condition, simplified: condition}
            )
          ]
        else
          []
        end

      _ ->
        []
    end
  end

  def analyze(_node, _context), do: []

  defp boolean_literal?(meta) when is_list(meta) do
    Keyword.get(meta, :subtype) == :boolean
  end

  defp boolean_literal?(_), do: false

  # ----- Private Helpers -----

  defp format_node({:variable, _meta, name}), do: name

  defp format_node({:literal, meta, value}) when is_list(meta) do
    subtype = Keyword.get(meta, :subtype)

    case subtype do
      :integer -> to_string(value)
      :float -> to_string(value)
      :string -> ~s("#{value}")
      :boolean -> to_string(value)
      :null -> "null"
      _ -> inspect(value)
    end
  end

  defp format_node({:binary_op, meta, [left, right]}) when is_list(meta) do
    op = Keyword.get(meta, :operator)
    "#{format_node(left)} #{op} #{format_node(right)}"
  end

  defp format_node({:unary_op, meta, [operand]}) when is_list(meta) do
    op = Keyword.get(meta, :operator)
    "#{op} #{format_node(operand)}"
  end

  defp format_node({:function_call, meta, args}) when is_list(meta) do
    name = Keyword.get(meta, :name)
    args_str = Enum.map_join(args, ", ", &format_node/1)
    "#{name}(#{args_str})"
  end

  defp format_node(_), do: "expression"
end
