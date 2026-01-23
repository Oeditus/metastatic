defmodule Metastatic.Analysis.Duplication.Result do
  @moduledoc """
  Result struct for code duplication detection analysis.

  Contains information about detected clones including type, similarity score,
  locations, and metrics.

  ## Fields

  - `duplicate?` - Whether code is duplicated
  - `clone_type` - Type of clone detected (`:type_i`, `:type_ii`, `:type_iii`, `:type_iv`, or `nil`)
  - `similarity_score` - Similarity score between 0.0 and 1.0
  - `differences` - List of differences for Type III clones
  - `locations` - Source locations of the clones
  - `fingerprints` - Structural fingerprints of the clones
  - `metrics` - Size and complexity metrics
  - `summary` - Human-readable summary

  ## Examples

      iex> result = Metastatic.Analysis.Duplication.Result.no_duplicate()
      iex> result.duplicate?
      false

      iex> result = Metastatic.Analysis.Duplication.Result.exact_clone()
      iex> result.clone_type
      :type_i
      iex> result.similarity_score
      1.0
  """

  alias Metastatic.Analysis.Duplication.Types

  @typedoc """
  Location information for a code clone.
  """
  @type location :: %{
          file: String.t() | nil,
          start_line: non_neg_integer() | nil,
          end_line: non_neg_integer() | nil,
          language: atom() | nil
        }

  @typedoc """
  Difference information for Type III clones.
  """
  @type difference :: %{
          type: atom(),
          description: String.t(),
          location: location() | nil
        }

  @typedoc """
  Metrics information for clones.
  """
  @type metrics :: %{
          size: non_neg_integer(),
          complexity: non_neg_integer() | nil,
          variables: non_neg_integer() | nil
        }

  @typedoc """
  Result struct for duplication detection.
  """
  @type t :: %__MODULE__{
          duplicate?: boolean(),
          clone_type: Types.clone_type() | nil,
          similarity_score: float(),
          differences: [difference()],
          locations: [location()],
          fingerprints: %{exact: String.t() | nil, normalized: String.t() | nil},
          metrics: metrics() | nil,
          summary: String.t()
        }

  @enforce_keys [:duplicate?, :similarity_score]
  defstruct duplicate?: false,
            clone_type: nil,
            similarity_score: 0.0,
            differences: [],
            locations: [],
            fingerprints: %{exact: nil, normalized: nil},
            metrics: nil,
            summary: ""

  @doc """
  Creates a new result indicating no duplication.

  ## Examples

      iex> result = Metastatic.Analysis.Duplication.Result.no_duplicate()
      iex> result.duplicate?
      false
      iex> result.similarity_score
      0.0
  """
  @spec no_duplicate() :: t()
  def no_duplicate do
    %__MODULE__{
      duplicate?: false,
      clone_type: nil,
      similarity_score: 0.0,
      summary: "No duplication detected"
    }
  end

  @doc """
  Creates a new result indicating an exact clone (Type I).

  ## Examples

      iex> result = Metastatic.Analysis.Duplication.Result.exact_clone()
      iex> result.duplicate?
      true
      iex> result.clone_type
      :type_i
      iex> result.similarity_score
      1.0
  """
  @spec exact_clone() :: t()
  def exact_clone do
    %__MODULE__{
      duplicate?: true,
      clone_type: :type_i,
      similarity_score: 1.0,
      summary: "Exact clone detected (Type I)"
    }
  end

  @doc """
  Creates a new result indicating a renamed clone (Type II).

  ## Examples

      iex> result = Metastatic.Analysis.Duplication.Result.renamed_clone()
      iex> result.duplicate?
      true
      iex> result.clone_type
      :type_ii
      iex> result.similarity_score
      1.0
  """
  @spec renamed_clone() :: t()
  def renamed_clone do
    %__MODULE__{
      duplicate?: true,
      clone_type: :type_ii,
      similarity_score: 1.0,
      summary: "Renamed clone detected (Type II)"
    }
  end

  @doc """
  Creates a new result indicating a near-miss clone (Type III).

  ## Examples

      iex> result = Metastatic.Analysis.Duplication.Result.near_miss_clone(0.85)
      iex> result.duplicate?
      true
      iex> result.clone_type
      :type_iii
      iex> result.similarity_score
      0.85
  """
  @spec near_miss_clone(float()) :: t()
  def near_miss_clone(similarity) when is_float(similarity) do
    %__MODULE__{
      duplicate?: true,
      clone_type: :type_iii,
      similarity_score: similarity,
      summary:
        "Near-miss clone detected (Type III) - #{Float.round(similarity * 100, 1)}% similar"
    }
  end

  @doc """
  Creates a new result indicating a semantic clone (Type IV).

  ## Examples

      iex> result = Metastatic.Analysis.Duplication.Result.semantic_clone(0.9)
      iex> result.duplicate?
      true
      iex> result.clone_type
      :type_iv
      iex> result.similarity_score
      0.9
  """
  @spec semantic_clone(float()) :: t()
  def semantic_clone(similarity) when is_float(similarity) do
    %__MODULE__{
      duplicate?: true,
      clone_type: :type_iv,
      similarity_score: similarity,
      summary: "Semantic clone detected (Type IV) - #{Float.round(similarity * 100, 1)}% similar"
    }
  end

  @doc """
  Adds location information to a result.

  ## Examples

      iex> result = Metastatic.Analysis.Duplication.Result.exact_clone()
      iex> location = %{file: "test.ex", start_line: 10, end_line: 20, language: :elixir}
      iex> result = Metastatic.Analysis.Duplication.Result.with_location(result, location)
      iex> [loc] = result.locations
      iex> loc.file
      "test.ex"
  """
  @spec with_location(t(), location()) :: t()
  def with_location(%__MODULE__{} = result, location) when is_map(location) do
    %{result | locations: [location | result.locations]}
  end

  @doc """
  Adds multiple locations to a result.

  ## Examples

      iex> result = Metastatic.Analysis.Duplication.Result.exact_clone()
      iex> locations = [
      ...>   %{file: "test1.ex", start_line: 10, end_line: 20, language: :elixir},
      ...>   %{file: "test2.ex", start_line: 30, end_line: 40, language: :elixir}
      ...> ]
      iex> result = Metastatic.Analysis.Duplication.Result.with_locations(result, locations)
      iex> length(result.locations)
      2
  """
  @spec with_locations(t(), [location()]) :: t()
  def with_locations(%__MODULE__{} = result, locations) when is_list(locations) do
    %{result | locations: locations ++ result.locations}
  end

  @doc """
  Adds fingerprints to a result.

  ## Examples

      iex> result = Metastatic.Analysis.Duplication.Result.exact_clone()
      iex> fingerprints = %{exact: "abc123", normalized: "def456"}
      iex> result = Metastatic.Analysis.Duplication.Result.with_fingerprints(result, fingerprints)
      iex> result.fingerprints.exact
      "abc123"
  """
  @spec with_fingerprints(t(), map()) :: t()
  def with_fingerprints(%__MODULE__{} = result, fingerprints) when is_map(fingerprints) do
    %{result | fingerprints: Map.merge(result.fingerprints, fingerprints)}
  end

  @doc """
  Adds metrics to a result.

  ## Examples

      iex> result = Metastatic.Analysis.Duplication.Result.exact_clone()
      iex> metrics = %{size: 100, complexity: 5, variables: 3}
      iex> result = Metastatic.Analysis.Duplication.Result.with_metrics(result, metrics)
      iex> result.metrics.size
      100
  """
  @spec with_metrics(t(), metrics()) :: t()
  def with_metrics(%__MODULE__{} = result, metrics) when is_map(metrics) do
    %{result | metrics: metrics}
  end

  @doc """
  Adds differences to a result (for Type III clones).

  ## Examples

      iex> result = Metastatic.Analysis.Duplication.Result.near_miss_clone(0.85)
      iex> diff = %{type: :statement_added, description: "Extra return statement"}
      iex> result = Metastatic.Analysis.Duplication.Result.with_difference(result, diff)
      iex> [d] = result.differences
      iex> d.type
      :statement_added
  """
  @spec with_difference(t(), difference()) :: t()
  def with_difference(%__MODULE__{} = result, difference) when is_map(difference) do
    %{result | differences: [difference | result.differences]}
  end

  @doc """
  Adds multiple differences to a result.

  ## Examples

      iex> result = Metastatic.Analysis.Duplication.Result.near_miss_clone(0.85)
      iex> diffs = [
      ...>   %{type: :statement_added, description: "Extra return"},
      ...>   %{type: :variable_renamed, description: "x renamed to y"}
      ...> ]
      iex> result = Metastatic.Analysis.Duplication.Result.with_differences(result, diffs)
      iex> length(result.differences)
      2
  """
  @spec with_differences(t(), [difference()]) :: t()
  def with_differences(%__MODULE__{} = result, differences) when is_list(differences) do
    %{result | differences: differences ++ result.differences}
  end

  @doc """
  Updates the summary of a result.

  ## Examples

      iex> result = Metastatic.Analysis.Duplication.Result.exact_clone()
      iex> result = Metastatic.Analysis.Duplication.Result.with_summary(result, "Custom summary")
      iex> result.summary
      "Custom summary"
  """
  @spec with_summary(t(), String.t()) :: t()
  def with_summary(%__MODULE__{} = result, summary) when is_binary(summary) do
    %{result | summary: summary}
  end
end
