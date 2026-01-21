defmodule Metastatic.Analysis.Purity.Formatter do
  @moduledoc """
  Formats purity analysis results for display.

  Supports multiple output formats: text, JSON, and detailed.
  """

  alias Metastatic.Analysis.Purity.Result

  @doc """
  Formats a purity result as text (default format).

  ## Examples

      iex> result = Metastatic.Analysis.Purity.Result.pure()
      iex> Metastatic.Analysis.Purity.Formatter.format(result, :text)
      "PURE"

      iex> result = Metastatic.Analysis.Purity.Result.impure([:io], [])
      iex> Metastatic.Analysis.Purity.Formatter.format(result, :text)
      "IMPURE: I/O operations"
  """
  @spec format(Result.t(), atom()) :: String.t()
  def format(%Result{pure?: true}, :text), do: "PURE"

  def format(%Result{pure?: false, summary: summary}, :text) do
    "IMPURE: #{summary |> String.replace("Function is impure due to ", "")}"
  end

  @doc """
  Formats a purity result as JSON.
  """
  def format(result, :json) do
    Jason.encode!(%{
      pure: result.pure?,
      effects: result.effects,
      confidence: result.confidence,
      summary: result.summary,
      unknown_calls: result.unknown_calls,
      impure_locations: format_locations(result.impure_locations)
    })
  end

  @doc """
  Formats a purity result with detailed information.
  """
  def format(result, :detailed) do
    lines = [
      "Purity Analysis Result",
      "=" <> String.duplicate("=", 40),
      "",
      "Status: #{if result.pure?, do: "PURE", else: "IMPURE"}",
      "Confidence: #{result.confidence}",
      ""
    ]

    lines =
      if result.pure? do
        lines ++ ["No side effects detected."]
      else
        effects_section =
          if Enum.any?(result.effects) do
            [
              "Effects Detected:",
              format_effects_list(result.effects),
              ""
            ]
          else
            []
          end

        unknown_section =
          if Enum.any?(result.unknown_calls) do
            [
              "Unknown Function Calls:",
              format_unknown_list(result.unknown_calls),
              ""
            ]
          else
            []
          end

        lines ++ effects_section ++ unknown_section ++ ["Summary: #{result.summary}"]
      end

    Enum.join(lines, "\n")
  end

  # Private helpers

  defp format_locations(locations) do
    Enum.map(locations, fn {:line, line, effect} ->
      %{line: line, effect: effect}
    end)
  end

  defp format_effects_list(effects) do
    effects
    |> Enum.map(fn effect ->
      "  - #{effect_name(effect)}"
    end)
    |> Enum.join("\n")
  end

  defp format_unknown_list(calls) do
    calls
    |> Enum.map(fn call ->
      "  - #{call}"
    end)
    |> Enum.join("\n")
  end

  defp effect_name(:io), do: "I/O operations"
  defp effect_name(:mutation), do: "Mutations"
  defp effect_name(:random), do: "Random operations"
  defp effect_name(:time), do: "Time operations"
  defp effect_name(:network), do: "Network operations"
  defp effect_name(:database), do: "Database operations"
  defp effect_name(:exception), do: "Exception handling"
  defp effect_name(:unknown), do: "Unknown operations"
end
