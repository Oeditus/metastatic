defmodule Metastatic.Analysis.Smells.Result do
  @moduledoc """
  Result structure for code smell detection.

  Contains information about detected code smells, their severity,
  and refactoring suggestions.

  ## Fields

  - `:has_smells?` - Boolean indicating if any code smells were found
  - `:smells` - List of detected smell details
  - `:summary` - Human-readable summary of findings
  - `:total_smells` - Count of detected smells
  - `:by_severity` - Map of counts by severity
  - `:by_type` - Map of counts by smell type

  ## Smell Types

  - `:long_function` - Function with too many statements
  - `:deep_nesting` - Excessive nesting depth
  - `:magic_number` - Unexplained numeric literals
  - `:complex_conditional` - Complex boolean expressions
  - `:long_parameter_list` - Too many parameters
  - `:duplicate_code` - Duplicated logic

  ## Examples

      iex> result = Metastatic.Analysis.Smells.Result.new([])
      iex> result.has_smells?
      false

      iex> smells = [%{type: :long_function, severity: :high, description: "test"}]
      iex> result = Metastatic.Analysis.Smells.Result.new(smells)
      iex> result.has_smells?
      true
      iex> result.total_smells
      1
  """

  @type smell :: %{
          type: smell_type(),
          severity: severity(),
          description: String.t(),
          suggestion: String.t(),
          context: term(),
          location: location() | nil
        }

  @type location :: %{
          optional(:function) => String.t(),
          optional(:module) => String.t(),
          optional(:line) => non_neg_integer(),
          optional(:arity) => non_neg_integer()
        }

  @type smell_type ::
          :long_function
          | :deep_nesting
          | :magic_number
          | :complex_conditional
          | :long_parameter_list
          | :duplicate_code

  @type severity :: :critical | :high | :medium | :low

  @type t :: %__MODULE__{
          has_smells?: boolean(),
          smells: [smell()],
          summary: String.t(),
          total_smells: non_neg_integer(),
          by_severity: %{severity() => non_neg_integer()},
          by_type: %{smell_type() => non_neg_integer()}
        }

  defstruct has_smells?: false,
            smells: [],
            summary: "No code smells detected",
            total_smells: 0,
            by_severity: %{},
            by_type: %{}

  @doc """
  Creates a new result from a list of code smells.

  ## Examples

      iex> Metastatic.Analysis.Smells.Result.new([])
      %Metastatic.Analysis.Smells.Result{has_smells?: false, summary: "No code smells detected"}

      iex> smells = [%{type: :long_function, severity: :high, description: "test", suggestion: "refactor", context: nil}]
      iex> result = Metastatic.Analysis.Smells.Result.new(smells)
      iex> result.has_smells?
      true
  """
  @spec new([smell()]) :: t()
  def new([]), do: %__MODULE__{}

  def new([_ | _] = smells) do
    by_severity = count_by_severity(smells)
    by_type = count_by_type(smells)

    %__MODULE__{
      has_smells?: true,
      smells: smells,
      summary: build_summary(smells, by_severity, by_type),
      total_smells: length(smells),
      by_severity: by_severity,
      by_type: by_type
    }
  end

  @doc """
  Creates a result with no code smells.

  ## Examples

      iex> result = Metastatic.Analysis.Smells.Result.no_smells()
      iex> result.has_smells?
      false
  """
  @spec no_smells() :: t()
  def no_smells do
    new([])
  end

  @doc """
  Converts result to JSON-compatible map.

  ## Examples

      iex> result = Metastatic.Analysis.Smells.Result.new([])
      iex> map = Metastatic.Analysis.Smells.Result.to_map(result)
      iex> is_map(map)
      true
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = result) do
    %{
      has_smells: result.has_smells?,
      summary: result.summary,
      total_smells: result.total_smells,
      by_severity: result.by_severity,
      by_type: result.by_type,
      smells: result.smells
    }
  end

  # Private helpers

  defp count_by_severity(smells) do
    Enum.reduce(smells, %{}, fn %{severity: sev}, acc ->
      Map.update(acc, sev, 1, &(&1 + 1))
    end)
  end

  defp count_by_type(smells) do
    Enum.reduce(smells, %{}, fn %{type: type}, acc ->
      Map.update(acc, type, 1, &(&1 + 1))
    end)
  end

  defp build_summary(smells, by_severity, _by_type) do
    total = length(smells)

    severity_summary =
      by_severity
      |> Enum.sort_by(fn {sev, _} -> severity_order(sev) end, :desc)
      |> Enum.map_join(", ", fn {sev, count} ->
        "#{count} #{sev}"
      end)

    "Found #{total} code smell(s): #{severity_summary}"
  end

  defp severity_order(:critical), do: 4
  defp severity_order(:high), do: 3
  defp severity_order(:medium), do: 2
  defp severity_order(:low), do: 1
end
