defmodule Metastatic.Analysis.Analyzers.SimplifyConditional do
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

  @behaviour Metastatic.Analysis.Analyzer

  alias Metastatic.Analysis.Analyzer

  @impl true
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

  @impl true
  def analyze(
        {:conditional, condition, {:literal, :boolean, true}, {:literal, :boolean, false}},
        _context
      ) do
    # Pattern: if condition then true else false => condition
    [
      Analyzer.issue(
        analyzer: __MODULE__,
        category: :refactoring,
        severity: :refactoring_opportunity,
        message: "This conditional can be simplified to just the condition",
        node: {:conditional, condition, {:literal, :boolean, true}, {:literal, :boolean, false}},
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
  end

  def analyze(
        {:conditional, condition, {:literal, :boolean, false}, {:literal, :boolean, true}},
        _context
      ) do
    # Pattern: if condition then false else true => not condition
    negated = {:unary_op, :boolean, :not, condition}

    [
      Analyzer.issue(
        analyzer: __MODULE__,
        category: :refactoring,
        severity: :refactoring_opportunity,
        message: "This conditional can be simplified to the negation of the condition",
        node: {:conditional, condition, {:literal, :boolean, false}, {:literal, :boolean, true}},
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
  end

  def analyze({:conditional, condition, cond_duplicate, {:literal, :boolean, false}}, _context)
      when condition == cond_duplicate do
    # Pattern: if condition then condition else false => condition
    [
      Analyzer.issue(
        analyzer: __MODULE__,
        category: :refactoring,
        severity: :refactoring_opportunity,
        message: "This conditional returns its condition in the then branch and false in else",
        node: {:conditional, condition, cond_duplicate, {:literal, :boolean, false}},
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
  end

  def analyze({:conditional, condition, {:literal, :boolean, true}, cond_duplicate}, _context)
      when condition == cond_duplicate do
    # Pattern: if condition then true else condition => condition
    [
      Analyzer.issue(
        analyzer: __MODULE__,
        category: :refactoring,
        severity: :refactoring_opportunity,
        message: "This conditional returns true in then branch and its condition in else",
        node: {:conditional, condition, {:literal, :boolean, true}, cond_duplicate},
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
  end

  def analyze(_node, _context), do: []

  # ----- Private Helpers -----

  defp format_node({:variable, name}), do: name

  defp format_node({:literal, type, value}) do
    case type do
      :integer -> to_string(value)
      :float -> to_string(value)
      :string -> ~s("#{value}")
      :boolean -> to_string(value)
      :null -> "null"
      _ -> inspect(value)
    end
  end

  defp format_node({:binary_op, _, op, left, right}) do
    "#{format_node(left)} #{op} #{format_node(right)}"
  end

  defp format_node({:unary_op, _, op, operand}) do
    "#{op} #{format_node(operand)}"
  end

  defp format_node({:function_call, name, args}) do
    args_str = Enum.map_join(args, ", ", &format_node/1)
    "#{name}(#{args_str})"
  end

  defp format_node(_), do: "expression"
end
