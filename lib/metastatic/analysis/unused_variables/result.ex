defmodule Metastatic.Analysis.UnusedVariables.Result do
  @moduledoc """
  Result structure for unused variable analysis.

  Contains information about variables that are assigned but never read,
  including their locations, types, and suggestions for remediation.

  ## Fields

  - `:has_unused?` - Boolean indicating if any unused variables were found
  - `:unused_variables` - List of unused variable details
  - `:summary` - Human-readable summary of findings
  - `:total_unused` - Count of unused variables
  - `:by_category` - Map of counts by category

  ## Variable Categories

  - `:local` - Local variable assigned but not read
  - `:parameter` - Function parameter never used
  - `:iterator` - Loop iterator never accessed
  - `:pattern` - Pattern match binding never used

  ## Examples

      iex> result = Metastatic.Analysis.UnusedVariables.Result.new([])
      iex> result.has_unused?
      false

      iex> vars = [%{name: "x", category: :local, line: 10}]
      iex> result = Metastatic.Analysis.UnusedVariables.Result.new(vars)
      iex> result.has_unused?
      true
      iex> result.total_unused
      1
  """

  @type unused_variable :: %{
          name: String.t(),
          category: category(),
          suggestion: String.t(),
          context: term()
        }

  @type category :: :local | :parameter | :iterator | :pattern

  @type t :: %__MODULE__{
          has_unused?: boolean(),
          unused_variables: [unused_variable()],
          summary: String.t(),
          total_unused: non_neg_integer(),
          by_category: %{category() => non_neg_integer()}
        }

  defstruct has_unused?: false,
            unused_variables: [],
            summary: "",
            total_unused: 0,
            by_category: %{}

  @doc """
  Creates a new result from a list of unused variables.

  ## Examples

      iex> Metastatic.Analysis.UnusedVariables.Result.new([])
      %Metastatic.Analysis.UnusedVariables.Result{has_unused?: false, summary: "No unused variables detected"}

      iex> vars = [%{name: "x", category: :local, suggestion: "remove", context: nil}]
      iex> result = Metastatic.Analysis.UnusedVariables.Result.new(vars)
      iex> result.has_unused?
      true
  """
  @spec new([unused_variable()]) :: t()
  def new(unused_variables) when is_list(unused_variables) do
    has_unused? = length(unused_variables) > 0
    by_category = count_by_category(unused_variables)

    %__MODULE__{
      has_unused?: has_unused?,
      unused_variables: unused_variables,
      summary: build_summary(unused_variables, by_category),
      total_unused: length(unused_variables),
      by_category: by_category
    }
  end

  @doc """
  Creates a result with no unused variables.

  ## Examples

      iex> result = Metastatic.Analysis.UnusedVariables.Result.no_unused()
      iex> result.has_unused?
      false
  """
  @spec no_unused() :: t()
  def no_unused do
    new([])
  end

  @doc """
  Converts result to JSON-compatible map.

  ## Examples

      iex> result = Metastatic.Analysis.UnusedVariables.Result.new([])
      iex> map = Metastatic.Analysis.UnusedVariables.Result.to_map(result)
      iex> is_map(map)
      true
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = result) do
    %{
      has_unused: result.has_unused?,
      summary: result.summary,
      total_unused: result.total_unused,
      by_category: result.by_category,
      variables: result.unused_variables
    }
  end

  # Private helpers

  defp count_by_category(vars) do
    Enum.reduce(vars, %{}, fn %{category: cat}, acc ->
      Map.update(acc, cat, 1, &(&1 + 1))
    end)
  end

  defp build_summary([], _by_category) do
    "No unused variables detected"
  end

  defp build_summary(vars, by_category) do
    total = length(vars)

    parts =
      by_category
      |> Enum.map(fn {category, count} ->
        "#{count} #{format_category(category)}"
      end)
      |> Enum.join(", ")

    "Found #{total} unused variable(s): #{parts}"
  end

  defp format_category(:local), do: "local"
  defp format_category(:parameter), do: "parameter"
  defp format_category(:iterator), do: "iterator"
  defp format_category(:pattern), do: "pattern"
  defp format_category(other), do: to_string(other)
end
