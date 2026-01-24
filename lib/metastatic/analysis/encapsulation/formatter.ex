defmodule Metastatic.Analysis.Encapsulation.Formatter do
  @moduledoc """
  Formatters for encapsulation analysis results.

  Supports `:text`, `:json`, and `:detailed` output formats.
  """

  alias Metastatic.Analysis.Encapsulation.Result

  @spec format(Result.t(), :text | :json | :detailed) :: String.t()
  def format(result, :text), do: format_text(result)
  def format(result, :json), do: format_json(result)
  def format(result, :detailed), do: format_detailed(result)

  defp format_text(result) do
    "#{result.container_name}: #{format_assessment(result.assessment)} encapsulation (Score: #{result.score}/100, #{length(result.violations)} violations)"
  end

  defp format_json(result) do
    Jason.encode!(%{
      container_name: result.container_name,
      container_type: result.container_type,
      score: result.score,
      assessment: result.assessment,
      violations: result.violations,
      public_methods: result.public_methods,
      private_methods: result.private_methods,
      accessor_count: result.accessor_count,
      state_variables: result.state_variables,
      recommendations: result.recommendations
    })
  end

  defp format_detailed(result) do
    lines = [
      "Encapsulation Analysis: #{result.container_name} (#{result.container_type})",
      "",
      "Score: #{result.score}/100 - #{format_assessment(result.assessment)}",
      "",
      "Metrics:",
      "  Public Methods: #{result.public_methods}",
      "  Private Methods: #{result.private_methods}",
      "  Accessors: #{result.accessor_count}",
      "  State Variables: #{length(result.state_variables)}",
      ""
    ]

    lines =
      if Enum.empty?(result.violations) do
        lines ++ ["No violations detected"]
      else
        lines ++
          ["Violations (#{length(result.violations)}):"] ++
          Enum.map(result.violations, fn v ->
            "  [#{String.upcase(to_string(v.severity))}] #{v.message}" <>
              if v.suggestion, do: "\n    → #{v.suggestion}", else: ""
          end)
      end

    lines =
      lines ++
        [
          "",
          "Recommendations:"
        ] ++ Enum.map(result.recommendations, fn r -> "  - #{r}" end)

    Enum.join(lines, "\n")
  end

  defp format_assessment(assessment) do
    case assessment do
      :excellent -> "Excellent"
      :good -> "Good"
      :fair -> "Fair"
      :poor -> "Poor"
      :very_poor -> "Very Poor"
    end
  end
end
