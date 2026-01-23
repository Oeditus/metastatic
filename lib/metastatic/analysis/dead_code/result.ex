defmodule Metastatic.Analysis.DeadCode.Result do
  @moduledoc """
  Result structure for dead code analysis.

  Contains information about detected dead code locations, their types,
  and suggestions for remediation.

  ## Fields

  - `:has_dead_code?` - Boolean indicating if any dead code was found
  - `:dead_locations` - List of dead code locations with details
  - `:summary` - Human-readable summary of findings
  - `:total_dead_statements` - Count of dead statements detected
  - `:by_type` - Map of dead code counts by type

  ## Dead Code Types

  - `:unreachable_after_return` - Code after early return/break
  - `:constant_conditional` - Unreachable branch of constant conditional
  - `:unused_function` - Function defined but never called
  - `:unreachable_code` - Other unreachable code patterns

  ## Examples

      iex> result = Metastatic.Analysis.DeadCode.Result.new([])
      iex> result.has_dead_code?
      false

      iex> locations = [%{type: :unreachable_after_return, line: 42, confidence: :high}]
      iex> result = Metastatic.Analysis.DeadCode.Result.new(locations)
      iex> result.has_dead_code?
      true
      iex> result.total_dead_statements
      1
  """

  @type dead_location :: %{
          type: dead_code_type(),
          reason: String.t(),
          confidence: :high | :medium | :low,
          suggestion: String.t(),
          context: term()
        }

  @type dead_code_type ::
          :unreachable_after_return
          | :constant_conditional
          | :unused_function
          | :unreachable_code

  @type t :: %__MODULE__{
          has_dead_code?: boolean(),
          dead_locations: [dead_location()],
          summary: String.t(),
          total_dead_statements: non_neg_integer(),
          by_type: %{dead_code_type() => non_neg_integer()}
        }

  defstruct has_dead_code?: false,
            dead_locations: [],
            summary: "",
            total_dead_statements: 0,
            by_type: %{}

  @doc """
  Creates a new result from a list of dead code locations.

  ## Examples

      iex> Metastatic.Analysis.DeadCode.Result.new([])
      %Metastatic.Analysis.DeadCode.Result{has_dead_code?: false, summary: "No dead code detected"}

      iex> locations = [%{type: :unreachable_after_return, reason: "test", confidence: :high, suggestion: "remove", context: nil}]
      iex> result = Metastatic.Analysis.DeadCode.Result.new(locations)
      iex> result.has_dead_code?
      true
  """
  @spec new([dead_location()]) :: t()
  def new(dead_locations) when is_list(dead_locations) do
    has_dead_code? = length(dead_locations) > 0
    by_type = count_by_type(dead_locations)

    %__MODULE__{
      has_dead_code?: has_dead_code?,
      dead_locations: dead_locations,
      summary: build_summary(dead_locations, by_type),
      total_dead_statements: length(dead_locations),
      by_type: by_type
    }
  end

  @doc """
  Creates a result with no dead code.

  ## Examples

      iex> result = Metastatic.Analysis.DeadCode.Result.no_dead_code()
      iex> result.has_dead_code?
      false
  """
  @spec no_dead_code() :: t()
  def no_dead_code do
    new([])
  end

  @doc """
  Converts result to JSON-compatible map.

  ## Examples

      iex> result = Metastatic.Analysis.DeadCode.Result.new([])
      iex> map = Metastatic.Analysis.DeadCode.Result.to_map(result)
      iex> is_map(map)
      true
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = result) do
    %{
      has_dead_code: result.has_dead_code?,
      summary: result.summary,
      total_dead_statements: result.total_dead_statements,
      by_type: result.by_type,
      locations: result.dead_locations
    }
  end

  # Private helpers

  defp count_by_type(locations) do
    Enum.reduce(locations, %{}, fn %{type: type}, acc ->
      Map.update(acc, type, 1, &(&1 + 1))
    end)
  end

  defp build_summary([], _by_type) do
    "No dead code detected"
  end

  defp build_summary(locations, by_type) do
    total = length(locations)

    parts =
      by_type
      |> Enum.map(fn {type, count} ->
        "#{count} #{format_type(type)}"
      end)
      |> Enum.join(", ")

    "Found #{total} dead code location(s): #{parts}"
  end

  defp format_type(:unreachable_after_return), do: "unreachable after return"
  defp format_type(:constant_conditional), do: "constant conditional"
  defp format_type(:unused_function), do: "unused function"
  defp format_type(:unreachable_code), do: "unreachable code"
  defp format_type(other), do: to_string(other)
end
