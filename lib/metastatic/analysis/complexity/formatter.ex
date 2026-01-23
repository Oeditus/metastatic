defmodule Metastatic.Analysis.Complexity.Formatter do
  @moduledoc """
  Formats complexity analysis results for different output formats.

  Supports three output formats:
  - `:text` - Human-readable text format with ANSI colors
  - `:json` - Machine-readable JSON format
  - `:detailed` - Extended text format with recommendations
  """

  alias Metastatic.Analysis.Complexity.Result

  @doc """
  Formats a complexity result in the specified format.

  ## Formats

  - `:text` - Default human-readable format
  - `:json` - JSON format for programmatic use
  - `:detailed` - Extended format with analysis breakdown

  ## Examples

      iex> result = Metastatic.Analysis.Complexity.Result.new(%{
      ...>   cyclomatic: 5,
      ...>   cognitive: 7,
      ...>   max_nesting: 2,
      ...>   halstead: %{volume: 100.0, difficulty: 5.0, effort: 500.0},
      ...>   loc: %{logical: 20, physical: 30},
      ...>   function_metrics: %{statement_count: 20, return_points: 1, variable_count: 5}
      ...> })
      iex> output = Metastatic.Analysis.Complexity.Formatter.format(result, :text)
      iex> String.contains?(output, "Cyclomatic Complexity")
      true
  """
  @spec format(Result.t(), atom()) :: String.t()
  def format(result, :text), do: format_text(result)
  def format(result, :json), do: format_json(result)
  def format(result, :detailed), do: format_detailed(result)

  # Private implementation

  defp format_text(result) do
    per_function_section = format_per_function(result.per_function)

    """
    Complexity Analysis Results:

    Cyclomatic Complexity: #{result.cyclomatic}#{warning_indicator(result, :cyclomatic)}
    Cognitive Complexity: #{result.cognitive}#{warning_indicator(result, :cognitive)}
    Max Nesting Depth: #{result.max_nesting}#{warning_indicator(result, :nesting)}

    Halstead Metrics:
      Volume: #{format_float(result.halstead[:volume])}
      Difficulty: #{format_float(result.halstead[:difficulty])}
      Effort: #{format_float(result.halstead[:effort])}

    Lines of Code:
      Logical: #{result.loc[:logical] || 0}#{warning_indicator(result, :loc)}
      Physical: #{result.loc[:physical] || 0}

    Function Metrics:
      Statements: #{result.function_metrics[:statement_count] || 0}
      Return Points: #{result.function_metrics[:return_points] || 0}
      Variables: #{result.function_metrics[:variable_count] || 0}
    #{per_function_section}
    Summary: #{result.summary}
    """
    |> String.trim()
  end

  defp format_per_function([]), do: ""

  defp format_per_function(functions) do
    formatted =
      Enum.map_join(functions, "\n", fn func ->
        "    #{func.name}: CC=#{func.cyclomatic}, Cog=#{func.cognitive}, Nest=#{func.max_nesting}, Stmts=#{func.statements}, Vars=#{func.variables}"
      end)

    "\n  Per-Function Breakdown:\n" <> formatted <> "\n"
  end

  defp format_json(result) do
    data = %{
      cyclomatic: result.cyclomatic,
      cognitive: result.cognitive,
      max_nesting: result.max_nesting,
      halstead: result.halstead,
      loc: result.loc,
      function_metrics: result.function_metrics,
      per_function: result.per_function,
      warnings: result.warnings,
      summary: result.summary
    }

    Jason.encode!(data, pretty: true)
  end

  defp format_detailed(result) do
    text = format_text(result)

    warnings_section =
      if Enum.empty?(result.warnings) do
        "\n\nNo warnings detected."
      else
        warnings = Enum.map_join(result.warnings, "\n  - ", & &1)
        "\n\nWarnings:\n  - #{warnings}"
      end

    recommendations = generate_recommendations(result)

    recommendations_section =
      if Enum.empty?(recommendations) do
        ""
      else
        recs = Enum.map_join(recommendations, "\n  - ", & &1)
        "\n\nRecommendations:\n  - #{recs}"
      end

    text <> warnings_section <> recommendations_section
  end

  defp warning_indicator(result, type) do
    relevant_warnings =
      result.warnings
      |> Enum.filter(fn warning ->
        case type do
          :cyclomatic -> String.contains?(warning, "Cyclomatic")
          :cognitive -> String.contains?(warning, "Cognitive")
          :nesting -> String.contains?(warning, "Nesting")
          :loc -> String.contains?(warning, "Logical lines")
          _ -> false
        end
      end)

    if Enum.empty?(relevant_warnings) do
      ""
    else
      " [WARNING]"
    end
  end

  defp format_float(nil), do: "0.0"
  defp format_float(value) when is_float(value), do: :erlang.float_to_binary(value, decimals: 1)
  defp format_float(value), do: to_string(value)

  defp generate_recommendations(result) do
    recommendations = []

    recommendations =
      if result.cyclomatic > 10 do
        [
          "Consider breaking down complex logic (cyclomatic > 10) into smaller functions"
          | recommendations
        ]
      else
        recommendations
      end

    recommendations =
      if result.cognitive > 15 do
        [
          "Reduce nesting depth and conditional complexity (cognitive > 15) for better readability"
          | recommendations
        ]
      else
        recommendations
      end

    recommendations =
      if result.max_nesting > 3 do
        [
          "Deeply nested code (depth > 3) is hard to understand. Extract nested logic into functions"
          | recommendations
        ]
      else
        recommendations
      end

    logical_loc = get_in(result.loc, [:logical]) || 0

    recommendations =
      if logical_loc > 50 do
        [
          "Function length (#{logical_loc} LoC) exceeds 50 lines. Consider splitting it"
          | recommendations
        ]
      else
        recommendations
      end

    Enum.reverse(recommendations)
  end
end
