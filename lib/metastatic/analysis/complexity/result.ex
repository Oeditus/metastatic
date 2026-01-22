defmodule Metastatic.Analysis.Complexity.Result do
  @moduledoc """
  Result structure for complexity analysis.

  Contains comprehensive code complexity metrics calculated at the MetaAST level,
  working uniformly across all supported languages.

  ## Fields

  - `:cyclomatic` - McCabe cyclomatic complexity (decision points + 1)
  - `:cognitive` - Cognitive complexity score (structural complexity with nesting penalties)
  - `:max_nesting` - Maximum nesting depth
  - `:halstead` - Halstead metrics map (volume, difficulty, effort)
  - `:loc` - Lines of code metrics map (physical, logical, comments)
  - `:function_metrics` - Function-level metrics map (statements, returns, variables)
  - `:warnings` - List of threshold violation warnings
  - `:summary` - Human-readable summary string

  ## Examples

      iex> %Metastatic.Analysis.Complexity.Result{
      ...>   cyclomatic: 5,
      ...>   cognitive: 7,
      ...>   max_nesting: 2,
      ...>   halstead: %{volume: 100.0, difficulty: 5.0, effort: 500.0},
      ...>   loc: %{logical: 20, physical: 30},
      ...>   function_metrics: %{statement_count: 20, return_points: 1, variable_count: 5},
      ...>   warnings: [],
      ...>   summary: "Code has low complexity"
      ...> }
  """

  @enforce_keys [:cyclomatic, :cognitive, :max_nesting, :halstead, :loc, :function_metrics]
  defstruct cyclomatic: 0,
            cognitive: 0,
            max_nesting: 0,
            halstead: %{},
            loc: %{},
            function_metrics: %{},
            per_function: [],
            warnings: [],
            summary: ""

  @type halstead_metrics :: %{
          distinct_operators: non_neg_integer(),
          distinct_operands: non_neg_integer(),
          total_operators: non_neg_integer(),
          total_operands: non_neg_integer(),
          vocabulary: non_neg_integer(),
          length: non_neg_integer(),
          volume: float(),
          difficulty: float(),
          effort: float()
        }

  @type loc_metrics :: %{
          physical: non_neg_integer(),
          logical: non_neg_integer(),
          comments: non_neg_integer(),
          blank: non_neg_integer()
        }

  @type function_metrics :: %{
          statement_count: non_neg_integer(),
          return_points: non_neg_integer(),
          variable_count: non_neg_integer(),
          parameter_count: non_neg_integer()
        }

  @type per_function_metrics :: %{
          name: String.t(),
          cyclomatic: non_neg_integer(),
          cognitive: non_neg_integer(),
          max_nesting: non_neg_integer(),
          statements: non_neg_integer(),
          variables: non_neg_integer()
        }

  @type t :: %__MODULE__{
          cyclomatic: non_neg_integer(),
          cognitive: non_neg_integer(),
          max_nesting: non_neg_integer(),
          halstead: halstead_metrics(),
          loc: loc_metrics(),
          function_metrics: function_metrics(),
          per_function: [per_function_metrics()],
          warnings: [String.t()],
          summary: String.t()
        }

  @doc """
  Creates a new complexity result from metrics map.

  ## Examples

      iex> Metastatic.Analysis.Complexity.Result.new(%{
      ...>   cyclomatic: 5,
      ...>   cognitive: 7,
      ...>   max_nesting: 2,
      ...>   halstead: %{volume: 100.0, difficulty: 5.0, effort: 500.0},
      ...>   loc: %{logical: 20, physical: 30},
      ...>   function_metrics: %{statement_count: 20}
      ...> })
      %Metastatic.Analysis.Complexity.Result{
        cyclomatic: 5,
        cognitive: 7,
        max_nesting: 2,
        halstead: %{volume: 100.0, difficulty: 5.0, effort: 500.0},
        loc: %{logical: 20, physical: 30},
        function_metrics: %{statement_count: 20},
        warnings: [],
        summary: "Code has low complexity"
      }
  """
  @spec new(map()) :: t()
  def new(metrics) do
    %__MODULE__{
      cyclomatic: Map.get(metrics, :cyclomatic, 0),
      cognitive: Map.get(metrics, :cognitive, 0),
      max_nesting: Map.get(metrics, :max_nesting, 0),
      halstead: Map.get(metrics, :halstead, %{}),
      loc: Map.get(metrics, :loc, %{}),
      function_metrics: Map.get(metrics, :function_metrics, %{}),
      per_function: Map.get(metrics, :per_function, []),
      warnings: Map.get(metrics, :warnings, []),
      summary: generate_summary(metrics)
    }
  end

  @doc """
  Adds a warning to the result.

  ## Examples

      iex> result = Metastatic.Analysis.Complexity.Result.new(%{
      ...>   cyclomatic: 5,
      ...>   cognitive: 7,
      ...>   max_nesting: 2,
      ...>   halstead: %{},
      ...>   loc: %{},
      ...>   function_metrics: %{}
      ...> })
      iex> result = Metastatic.Analysis.Complexity.Result.add_warning(result, "High complexity detected")
      iex> result.warnings
      ["High complexity detected"]
  """
  @spec add_warning(t(), String.t()) :: t()
  def add_warning(%__MODULE__{} = result, warning) do
    %{result | warnings: result.warnings ++ [warning]}
  end

  @doc """
  Merges multiple complexity results.

  Uses maximum values for metrics (worst case).

  ## Examples

      iex> r1 = Metastatic.Analysis.Complexity.Result.new(%{
      ...>   cyclomatic: 5,
      ...>   cognitive: 7,
      ...>   max_nesting: 2,
      ...>   halstead: %{volume: 100.0},
      ...>   loc: %{logical: 20},
      ...>   function_metrics: %{statement_count: 20}
      ...> })
      iex> r2 = Metastatic.Analysis.Complexity.Result.new(%{
      ...>   cyclomatic: 8,
      ...>   cognitive: 10,
      ...>   max_nesting: 3,
      ...>   halstead: %{volume: 150.0},
      ...>   loc: %{logical: 30},
      ...>   function_metrics: %{statement_count: 30}
      ...> })
      iex> result = Metastatic.Analysis.Complexity.Result.merge([r1, r2])
      iex> result.cyclomatic
      8
      iex> result.cognitive
      10
      iex> result.max_nesting
      3
  """
  @spec merge([t()]) :: t()
  def merge([]), do: new(%{})

  def merge(results) do
    cyclomatic = results |> Enum.map(& &1.cyclomatic) |> Enum.max()
    cognitive = results |> Enum.map(& &1.cognitive) |> Enum.max()
    max_nesting = results |> Enum.map(& &1.max_nesting) |> Enum.max()

    halstead =
      results
      |> Enum.map(& &1.halstead)
      |> Enum.reduce(%{}, fn h, acc ->
        Map.merge(acc, h, fn _k, v1, v2 -> max(v1, v2) end)
      end)

    loc =
      results
      |> Enum.map(& &1.loc)
      |> Enum.reduce(%{}, fn l, acc ->
        Map.merge(acc, l, fn _k, v1, v2 -> v1 + v2 end)
      end)

    function_metrics =
      results
      |> Enum.map(& &1.function_metrics)
      |> Enum.reduce(%{}, fn f, acc ->
        Map.merge(acc, f, fn _k, v1, v2 -> v1 + v2 end)
      end)

    warnings = results |> Enum.flat_map(& &1.warnings) |> Enum.uniq()

    new(%{
      cyclomatic: cyclomatic,
      cognitive: cognitive,
      max_nesting: max_nesting,
      halstead: halstead,
      loc: loc,
      function_metrics: function_metrics,
      warnings: warnings
    })
  end

  @doc """
  Applies thresholds and generates warnings.

  ## Thresholds

  - `:cyclomatic_warning` - Default: 10
  - `:cyclomatic_error` - Default: 20
  - `:cognitive_warning` - Default: 15
  - `:cognitive_error` - Default: 30
  - `:nesting_warning` - Default: 3
  - `:nesting_error` - Default: 5
  - `:loc_warning` - Default: 50 (logical lines)
  - `:loc_error` - Default: 100 (logical lines)

  ## Examples

      iex> result = Metastatic.Analysis.Complexity.Result.new(%{
      ...>   cyclomatic: 12,
      ...>   cognitive: 18,
      ...>   max_nesting: 2,
      ...>   halstead: %{},
      ...>   loc: %{logical: 45},
      ...>   function_metrics: %{}
      ...> })
      iex> result = Metastatic.Analysis.Complexity.Result.apply_thresholds(result, %{})
      iex> length(result.warnings)
      2
      iex> Enum.any?(result.warnings, &String.contains?(&1, "Cyclomatic"))
      true
      iex> Enum.any?(result.warnings, &String.contains?(&1, "Cognitive"))
      true
  """
  @spec apply_thresholds(t(), map()) :: t()
  def apply_thresholds(%__MODULE__{} = result, thresholds \\ %{}) do
    thresholds = default_thresholds() |> Map.merge(thresholds)

    result
    |> check_cyclomatic(thresholds)
    |> check_cognitive(thresholds)
    |> check_nesting(thresholds)
    |> check_loc(thresholds)
    |> update_summary()
  end

  # Private helpers

  defp default_thresholds do
    %{
      cyclomatic_warning: 10,
      cyclomatic_error: 20,
      cognitive_warning: 15,
      cognitive_error: 30,
      nesting_warning: 3,
      nesting_error: 5,
      loc_warning: 50,
      loc_error: 100
    }
  end

  defp check_cyclomatic(result, thresholds) do
    cond do
      result.cyclomatic >= thresholds.cyclomatic_error ->
        add_warning(
          result,
          "Cyclomatic complexity (#{result.cyclomatic}) exceeds error threshold (#{thresholds.cyclomatic_error})"
        )

      result.cyclomatic >= thresholds.cyclomatic_warning ->
        add_warning(
          result,
          "Cyclomatic complexity (#{result.cyclomatic}) exceeds warning threshold (#{thresholds.cyclomatic_warning})"
        )

      true ->
        result
    end
  end

  defp check_cognitive(result, thresholds) do
    cond do
      result.cognitive >= thresholds.cognitive_error ->
        add_warning(
          result,
          "Cognitive complexity (#{result.cognitive}) exceeds error threshold (#{thresholds.cognitive_error})"
        )

      result.cognitive >= thresholds.cognitive_warning ->
        add_warning(
          result,
          "Cognitive complexity (#{result.cognitive}) exceeds warning threshold (#{thresholds.cognitive_warning})"
        )

      true ->
        result
    end
  end

  defp check_nesting(result, thresholds) do
    cond do
      result.max_nesting >= thresholds.nesting_error ->
        add_warning(
          result,
          "Nesting depth (#{result.max_nesting}) exceeds error threshold (#{thresholds.nesting_error})"
        )

      result.max_nesting >= thresholds.nesting_warning ->
        add_warning(
          result,
          "Nesting depth (#{result.max_nesting}) exceeds warning threshold (#{thresholds.nesting_warning})"
        )

      true ->
        result
    end
  end

  defp check_loc(result, thresholds) do
    logical = get_in(result.loc, [:logical]) || 0

    cond do
      logical >= thresholds.loc_error ->
        add_warning(
          result,
          "Logical lines of code (#{logical}) exceeds error threshold (#{thresholds.loc_error})"
        )

      logical >= thresholds.loc_warning ->
        add_warning(
          result,
          "Logical lines of code (#{logical}) exceeds warning threshold (#{thresholds.loc_warning})"
        )

      true ->
        result
    end
  end

  defp update_summary(result) do
    %{result | summary: generate_summary_from_result(result)}
  end

  defp generate_summary(metrics) do
    cyc = Map.get(metrics, :cyclomatic, 0)
    cog = Map.get(metrics, :cognitive, 0)
    nest = Map.get(metrics, :max_nesting, 0)

    cond do
      cyc <= 5 and cog <= 7 and nest <= 2 -> "Code has low complexity"
      cyc <= 10 and cog <= 15 and nest <= 3 -> "Code has moderate complexity"
      cyc <= 20 and cog <= 30 and nest <= 5 -> "Code has high complexity"
      true -> "Code has very high complexity"
    end
  end

  defp generate_summary_from_result(%__MODULE__{} = result) do
    warning_count = length(result.warnings)

    cond do
      warning_count == 0 ->
        generate_summary(%{
          cyclomatic: result.cyclomatic,
          cognitive: result.cognitive,
          max_nesting: result.max_nesting
        })

      warning_count == 1 ->
        "Code has moderate complexity with 1 warning"

      true ->
        "Code has high complexity with #{warning_count} warnings"
    end
  end
end
