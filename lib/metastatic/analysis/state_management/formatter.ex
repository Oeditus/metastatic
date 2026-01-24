defmodule Metastatic.Analysis.StateManagement.Formatter do
  @moduledoc """
  Formatters for state management analysis results.
  """

  alias Metastatic.Analysis.StateManagement.Result

  @spec format(Result.t(), :text | :json | :detailed) :: String.t()
  def format(result, :text), do: format_text(result)
  def format(result, :json), do: format_json(result)
  def format(result, :detailed), do: format_detailed(result)

  defp format_text(result) do
    "#{result.container_name}: #{format_pattern(result.pattern)} (#{result.state_count} state vars, #{result.mutation_count} mutations)"
  end

  defp format_json(result) do
    Jason.encode!(%{
      container_name: result.container_name,
      pattern: result.pattern,
      assessment: result.assessment,
      state_count: result.state_count,
      mutation_count: result.mutation_count,
      initialized_state: result.initialized_state,
      mutable_state: result.mutable_state,
      warnings: result.warnings,
      recommendations: result.recommendations
    })
  end

  defp format_detailed(result) do
    lines = [
      "State Management Analysis: #{result.container_name}",
      "",
      "Pattern: #{format_pattern(result.pattern)} - #{format_assessment(result.assessment)}",
      "",
      "Metrics:",
      "  Total State: #{result.state_count} variables",
      "  Mutations: #{result.mutation_count}",
      "  Read-Only: #{length(result.read_only_state)}",
      "  Mutable: #{length(result.mutable_state)}",
      "  Initialized: #{length(result.initialized_state)}",
      ""
    ]

    lines =
      if Enum.empty?(result.warnings) do
        lines ++ ["No warnings"]
      else
        lines ++ ["Warnings:"] ++ Enum.map(result.warnings, fn w -> "  - #{w}" end)
      end

    lines =
      lines ++
        ["", "Recommendations:"] ++ Enum.map(result.recommendations, fn r -> "  - #{r}" end)

    Enum.join(lines, "\n")
  end

  defp format_pattern(pattern) do
    case pattern do
      :stateless -> "Stateless"
      :immutable_state -> "Immutable State"
      :controlled_mutation -> "Controlled Mutation"
      :uncontrolled_mutation -> "Uncontrolled Mutation"
      :mixed -> "Mixed"
    end
  end

  defp format_assessment(assessment) do
    case assessment do
      :excellent -> "Excellent"
      :good -> "Good"
      :fair -> "Fair"
      :poor -> "Poor"
    end
  end
end
