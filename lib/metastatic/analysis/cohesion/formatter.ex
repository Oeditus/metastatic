defmodule Metastatic.Analysis.Cohesion.Formatter do
  @moduledoc """
  Formatters for cohesion analysis results.

  Supports multiple output formats:
  - `:text` - Human-readable text format
  - `:json` - Machine-readable JSON format
  - `:detailed` - Detailed text with all metrics and recommendations

  ## Examples

      iex> result = %Metastatic.Analysis.Cohesion.Result{
      ...>   container_name: "Calculator",
      ...>   lcom: 0,
      ...>   tcc: 1.0,
      ...>   assessment: :excellent
      ...> }
      iex> Metastatic.Analysis.Cohesion.Formatter.format(result, :text)
      "Calculator: Excellent cohesion (LCOM: 0, TCC: 1.00)"
  """

  alias Metastatic.Analysis.Cohesion.Result

  @doc """
  Format cohesion analysis result.

  ## Formats

  - `:text` - Single line summary
  - `:json` - JSON object
  - `:detailed` - Multi-line detailed report

  ## Examples

      iex> result = %Metastatic.Analysis.Cohesion.Result{container_name: "Foo", lcom: 0, tcc: 1.0, assessment: :excellent}
      iex> Metastatic.Analysis.Cohesion.Formatter.format(result, :text)
      "Foo: Excellent cohesion (LCOM: 0, TCC: 1.00)"
  """
  @spec format(Result.t(), :text | :json | :detailed) :: String.t()
  def format(result, :text), do: format_text(result)
  def format(result, :json), do: format_json(result)
  def format(result, :detailed), do: format_detailed(result)

  # Private formatters

  defp format_text(result) do
    assessment_text = format_assessment(result.assessment)

    "#{result.container_name}: #{assessment_text} cohesion (LCOM: #{result.lcom}, TCC: #{format_float(result.tcc)})"
  end

  defp format_json(result) do
    Jason.encode!(%{
      container_name: result.container_name,
      container_type: result.container_type,
      metrics: %{
        lcom: result.lcom,
        tcc: result.tcc,
        lcc: result.lcc,
        method_count: result.method_count,
        method_pairs: result.method_pairs,
        connected_pairs: result.connected_pairs
      },
      shared_state: result.shared_state,
      assessment: result.assessment,
      warnings: result.warnings,
      recommendations: result.recommendations
    })
  end

  defp format_detailed(result) do
    lines = [
      "Cohesion Analysis: #{result.container_name} (#{result.container_type})",
      "",
      "Metrics:",
      "  LCOM (Lack of Cohesion): #{result.lcom}",
      "  TCC (Tight Class Cohesion): #{format_float(result.tcc)} (#{format_percentage(result.tcc)})",
      "  LCC (Loose Class Cohesion): #{format_float(result.lcc)} (#{format_percentage(result.lcc)})",
      "  Methods: #{result.method_count}",
      "  Method Pairs: #{result.method_pairs}",
      "  Connected Pairs: #{result.connected_pairs}",
      "",
      "Shared State Variables: #{format_list(result.shared_state)}",
      "",
      "Assessment: #{format_assessment(result.assessment)}"
    ]

    lines =
      if Enum.empty?(result.warnings) do
        lines
      else
        lines ++
          [
            "",
            "Warnings:"
          ] ++ Enum.map(result.warnings, fn w -> "  - #{w}" end)
      end

    lines =
      if Enum.empty?(result.recommendations) do
        lines
      else
        lines ++
          [
            "",
            "Recommendations:"
          ] ++ Enum.map(result.recommendations, fn r -> "  - #{r}" end)
      end

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

  defp format_float(value) when is_float(value), do: :erlang.float_to_binary(value, decimals: 2)
  defp format_float(value), do: to_string(value)

  defp format_percentage(value) when is_float(value) do
    percentage = value * 100
    "#{:erlang.float_to_binary(percentage, decimals: 0)}%"
  end

  defp format_list([]), do: "none"
  defp format_list(items), do: Enum.join(items, ", ")
end
