defmodule Metastatic.Analysis.Cohesion.Result do
  @moduledoc """
  Result structure for cohesion analysis.

  Cohesion measures how well the members (methods/functions) of a container
  (class/module) work together. High cohesion indicates members are closely
  related and work toward a common purpose.

  ## Metrics

  - **LCOM (Lack of Cohesion of Methods)** - Lower is better (0 = perfect cohesion)
  - **TCC (Tight Class Cohesion)** - Higher is better (0.0-1.0, 1.0 = perfect)
  - **LCC (Loose Class Cohesion)** - Higher is better (0.0-1.0, 1.0 = perfect)
  - **Method Pairs** - Total possible method pairs in container
  - **Connected Pairs** - Pairs that share at least one instance variable

  ## Interpretation

  - LCOM = 0: Perfect cohesion (all methods use shared state)
  - LCOM > 0: Poor cohesion (methods don't interact)
  - TCC > 0.5: Good tight cohesion
  - TCC < 0.3: Poor cohesion, consider splitting

  ## Examples

      iex> result = %Metastatic.Analysis.Cohesion.Result{
      ...>   container_name: "Calculator",
      ...>   lcom: 0,
      ...>   tcc: 1.0,
      ...>   lcc: 1.0,
      ...>   method_count: 3,
      ...>   method_pairs: 3,
      ...>   connected_pairs: 3,
      ...>   assessment: :excellent
      ...> }
      iex> result.assessment
      :excellent
  """

  @type assessment :: :excellent | :good | :fair | :poor | :very_poor

  @type t :: %__MODULE__{
          container_name: String.t() | nil,
          container_type: :module | :class | :namespace | nil,
          lcom: non_neg_integer(),
          tcc: float(),
          lcc: float(),
          method_count: non_neg_integer(),
          method_pairs: non_neg_integer(),
          connected_pairs: non_neg_integer(),
          shared_state: [String.t()],
          assessment: assessment(),
          warnings: [String.t()],
          recommendations: [String.t()]
        }

  defstruct container_name: nil,
            container_type: nil,
            lcom: 0,
            tcc: 0.0,
            lcc: 0.0,
            method_count: 0,
            method_pairs: 0,
            connected_pairs: 0,
            shared_state: [],
            assessment: :excellent,
            warnings: [],
            recommendations: []

  @doc """
  Assess cohesion level based on metrics.

  Returns `:excellent`, `:good`, `:fair`, `:poor`, or `:very_poor`.

  ## Examples

      iex> Metastatic.Analysis.Cohesion.Result.assess(0, 0.9)
      :excellent

      iex> Metastatic.Analysis.Cohesion.Result.assess(2, 0.4)
      :fair

      iex> Metastatic.Analysis.Cohesion.Result.assess(10, 0.1)
      :very_poor
  """
  @spec assess(non_neg_integer(), float()) :: assessment()
  def assess(lcom, tcc) do
    cond do
      lcom == 0 and tcc >= 0.8 -> :excellent
      lcom <= 1 and tcc >= 0.6 -> :good
      lcom <= 3 and tcc >= 0.4 -> :fair
      lcom <= 5 and tcc >= 0.2 -> :poor
      true -> :very_poor
    end
  end

  @doc """
  Generate warnings based on cohesion metrics.

  ## Examples

      iex> Metastatic.Analysis.Cohesion.Result.generate_warnings(8, 0.15, 2)
      ["Very high LCOM (8) indicates poor cohesion", "Low TCC (0.15) suggests methods don't share state", "Only 2 methods - too small to measure cohesion accurately"]
  """
  @spec generate_warnings(non_neg_integer(), float(), non_neg_integer()) :: [String.t()]
  def generate_warnings(lcom, tcc, method_count) do
    warnings = []

    warnings =
      if lcom > 5 do
        ["Very high LCOM (#{lcom}) indicates poor cohesion" | warnings]
      else
        warnings
      end

    warnings =
      if tcc < 0.3 do
        ["Low TCC (#{Float.round(tcc, 2)}) suggests methods don't share state" | warnings]
      else
        warnings
      end

    warnings =
      if method_count < 3 do
        ["Only #{method_count} methods - too small to measure cohesion accurately" | warnings]
      else
        warnings
      end

    Enum.reverse(warnings)
  end

  @doc """
  Generate recommendations based on assessment.

  ## Examples

      iex> Metastatic.Analysis.Cohesion.Result.generate_recommendations(:poor, 15, 0.2)
      ["Consider splitting this container into multiple focused units", "High method count (15) with low cohesion suggests multiple responsibilities", "Group methods that share state into separate classes"]
  """
  @spec generate_recommendations(assessment(), non_neg_integer(), float()) :: [String.t()]
  def generate_recommendations(assessment, method_count, tcc) do
    case assessment do
      :excellent ->
        ["Cohesion is excellent - no changes needed"]

      :good ->
        ["Cohesion is good - minor improvements possible"]

      :fair ->
        [
          "Consider reviewing method responsibilities",
          "Look for opportunities to extract helper classes"
        ]

      :poor ->
        recs = []

        recs =
          if tcc < 0.3 do
            ["Group methods that share state into separate classes" | recs]
          else
            recs
          end

        recs =
          if method_count > 10 do
            [
              "High method count (#{method_count}) with low cohesion suggests multiple responsibilities"
              | recs
            ]
          else
            recs
          end

        ["Consider splitting this container into multiple focused units" | recs]

      :very_poor ->
        [
          "This container has very poor cohesion - refactoring strongly recommended",
          "Extract methods into separate, focused classes",
          "Each class should have a single, well-defined responsibility"
        ]
    end
  end
end
