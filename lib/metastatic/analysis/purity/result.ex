defmodule Metastatic.Analysis.Purity.Result do
  @moduledoc """
  Result structure for purity analysis.

  Contains information about whether a function/code block is pure or impure,
  what side effects were detected, confidence level, and locations of impure operations.

  ## Fields

  - `:pure?` - Boolean indicating if the code is pure (no side effects detected)
  - `:effects` - List of detected effect atoms (`:io`, `:mutation`, `:random`, `:time`, `:network`, `:database`, `:exception`)
  - `:confidence` - Confidence level (`:high`, `:medium`, `:low`)
  - `:impure_locations` - List of `{:line, line_number, effect_type}` tuples
  - `:summary` - Human-readable summary string
  - `:unknown_calls` - List of function calls that couldn't be classified

  ## Examples

      # Pure function
      iex> %Metastatic.Analysis.Purity.Result{
      ...>   pure?: true,
      ...>   effects: [],
      ...>   confidence: :high,
      ...>   impure_locations: [],
      ...>   summary: "Function is pure"
      ...> }

      # Impure function with I/O
      iex> %Metastatic.Analysis.Purity.Result{
      ...>   pure?: false,
      ...>   effects: [:io],
      ...>   confidence: :high,
      ...>   impure_locations: [{:line, 42, :io}],
      ...>   summary: "Function is impure due to I/O operations"
      ...> }

      # Unknown purity (unclassified function calls)
      iex> %Metastatic.Analysis.Purity.Result{
      ...>   pure?: false,
      ...>   effects: [],
      ...>   confidence: :low,
      ...>   impure_locations: [],
      ...>   summary: "Function purity unknown - contains unclassified calls",
      ...>   unknown_calls: ["custom_function"]
      ...> }
  """

  @enforce_keys [:pure?, :effects, :confidence]
  defstruct pure?: true,
            effects: [],
            confidence: :high,
            impure_locations: [],
            summary: "",
            unknown_calls: []

  @type effect ::
          :io | :mutation | :random | :time | :network | :database | :exception | :unknown

  @type confidence :: :high | :medium | :low

  @type location :: {:line, non_neg_integer(), effect()}

  @type t :: %__MODULE__{
          pure?: boolean(),
          effects: [effect()],
          confidence: confidence(),
          impure_locations: [location()],
          summary: String.t(),
          unknown_calls: [String.t()]
        }

  @doc """
  Creates a new pure result.

  ## Examples

      iex> Metastatic.Analysis.Purity.Result.pure()
      %Metastatic.Analysis.Purity.Result{
        pure?: true,
        effects: [],
        confidence: :high,
        impure_locations: [],
        summary: "Function is pure",
        unknown_calls: []
      }
  """
  @spec pure() :: t()
  def pure do
    %__MODULE__{
      pure?: true,
      effects: [],
      confidence: :high,
      impure_locations: [],
      summary: "Function is pure",
      unknown_calls: []
    }
  end

  @doc """
  Creates a new impure result with the given effects and locations.

  ## Examples

      iex> Metastatic.Analysis.Purity.Result.impure([:io], [{:line, 10, :io}])
      %Metastatic.Analysis.Purity.Result{
        pure?: false,
        effects: [:io],
        confidence: :high,
        impure_locations: [{:line, 10, :io}],
        summary: "Function is impure due to I/O operations",
        unknown_calls: []
      }
  """
  @spec impure([effect()], [location()]) :: t()
  def impure(effects, locations) do
    %__MODULE__{
      pure?: false,
      effects: Enum.uniq(effects),
      confidence: :high,
      impure_locations: locations,
      summary: build_summary(effects),
      unknown_calls: []
    }
  end

  @doc """
  Creates a result with unknown purity (low confidence).

  ## Examples

      iex> Metastatic.Analysis.Purity.Result.unknown(["custom_func"])
      %Metastatic.Analysis.Purity.Result{
        pure?: false,
        effects: [],
        confidence: :low,
        impure_locations: [],
        summary: "Function purity unknown - contains unclassified calls: custom_func",
        unknown_calls: ["custom_func"]
      }
  """
  @spec unknown([String.t()]) :: t()
  def unknown(calls) do
    %__MODULE__{
      pure?: false,
      effects: [],
      confidence: :low,
      impure_locations: [],
      summary: "Function purity unknown - contains unclassified calls: #{Enum.join(calls, ", ")}",
      unknown_calls: calls
    }
  end

  @doc """
  Merges multiple results, keeping impurity if any result is impure.

  ## Examples

      iex> r1 = Metastatic.Analysis.Purity.Result.pure()
      iex> r2 = Metastatic.Analysis.Purity.Result.impure([:io], [{:line, 10, :io}])
      iex> result = Metastatic.Analysis.Purity.Result.merge([r1, r2])
      iex> result.pure?
      false
      iex> result.effects
      [:io]
  """
  @spec merge([t()]) :: t()
  def merge(results) do
    pure? = Enum.all?(results, & &1.pure?)
    effects = results |> Enum.flat_map(& &1.effects) |> Enum.uniq()
    locations = results |> Enum.flat_map(& &1.impure_locations) |> Enum.uniq()
    unknown = results |> Enum.flat_map(& &1.unknown_calls) |> Enum.uniq()

    confidence =
      cond do
        pure? and Enum.empty?(unknown) -> :high
        not Enum.empty?(unknown) -> :low
        true -> :medium
      end

    summary =
      cond do
        pure? -> "Function is pure"
        not Enum.empty?(effects) -> build_summary(effects)
        not Enum.empty?(unknown) -> "Function purity unknown - contains unclassified calls"
        true -> "Function may be impure"
      end

    %__MODULE__{
      pure?: pure?,
      effects: effects,
      confidence: confidence,
      impure_locations: locations,
      summary: summary,
      unknown_calls: unknown
    }
  end

  # Private helpers

  defp build_summary(effects) when effects == [] do
    "Function is pure"
  end

  defp build_summary(effects) do
    effect_names =
      effects
      |> Enum.map(&effect_to_string/1)
      |> Enum.join(", ")

    "Function is impure due to #{effect_names}"
  end

  defp effect_to_string(:io), do: "I/O operations"
  defp effect_to_string(:mutation), do: "mutations"
  defp effect_to_string(:random), do: "random operations"
  defp effect_to_string(:time), do: "time operations"
  defp effect_to_string(:network), do: "network operations"
  defp effect_to_string(:database), do: "database operations"
  defp effect_to_string(:exception), do: "exception handling"
  defp effect_to_string(:unknown), do: "unknown operations"
end
