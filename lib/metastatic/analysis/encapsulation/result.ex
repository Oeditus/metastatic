defmodule Metastatic.Analysis.Encapsulation.Result do
  @moduledoc """
  Result structure for encapsulation analysis.

  Encapsulation is the principle of hiding internal state and requiring all
  interaction to go through well-defined interfaces (methods). This analyzer
  detects violations of encapsulation principles.

  ## Violation Types

  - **Public State** - Instance variables accessible without getters/setters
  - **Missing Accessors** - State modified directly instead of through methods
  - **Excessive Accessors** - Too many getters/setters (data class smell)
  - **Leaky Abstraction** - Internal implementation details exposed
  - **Visibility Violations** - Private methods called externally

  ## Severity Levels

  - `:critical` - Severe encapsulation breach
  - `:high` - Significant encapsulation issue
  - `:medium` - Moderate concern
  - `:low` - Minor issue or code smell

  ## Examples

      iex> result = %Metastatic.Analysis.Encapsulation.Result{
      ...>   container_name: "User",
      ...>   violations: [],
      ...>   score: 100,
      ...>   assessment: :excellent
      ...> }
      iex> result.assessment
      :excellent
  """

  @type severity :: :critical | :high | :medium | :low
  @type violation_type ::
          :public_state
          | :missing_accessor
          | :excessive_accessors
          | :leaky_abstraction
          | :visibility_violation
          | :direct_state_access

  @type violation :: %{
          type: violation_type(),
          severity: severity(),
          message: String.t(),
          location: String.t() | nil,
          suggestion: String.t() | nil
        }

  @type assessment :: :excellent | :good | :fair | :poor | :very_poor

  @type t :: %__MODULE__{
          container_name: String.t() | nil,
          container_type: :module | :class | :namespace | nil,
          violations: [violation()],
          score: non_neg_integer(),
          assessment: assessment(),
          public_methods: non_neg_integer(),
          private_methods: non_neg_integer(),
          accessor_count: non_neg_integer(),
          state_variables: [String.t()],
          recommendations: [String.t()]
        }

  defstruct container_name: nil,
            container_type: nil,
            violations: [],
            score: 100,
            assessment: :excellent,
            public_methods: 0,
            private_methods: 0,
            accessor_count: 0,
            state_variables: [],
            recommendations: []

  @doc """
  Calculate encapsulation score based on violations.

  Score starts at 100 and is reduced based on violation severity:
  - Critical: -20 points
  - High: -10 points
  - Medium: -5 points
  - Low: -2 points

  ## Examples

      iex> violations = [
      ...>   %{type: :public_state, severity: :critical, message: "Public var", location: nil, suggestion: nil},
      ...>   %{type: :missing_accessor, severity: :high, message: "Direct access", location: nil, suggestion: nil}
      ...> ]
      iex> Metastatic.Analysis.Encapsulation.Result.calculate_score(violations)
      70
  """
  @spec calculate_score([violation()]) :: non_neg_integer()
  def calculate_score(violations) do
    penalty =
      Enum.reduce(violations, 0, fn violation, acc ->
        case violation.severity do
          :critical -> acc + 20
          :high -> acc + 10
          :medium -> acc + 5
          :low -> acc + 2
        end
      end)

    max(0, 100 - penalty)
  end

  @doc """
  Assess encapsulation quality based on score.

  ## Examples

      iex> Metastatic.Analysis.Encapsulation.Result.assess(95)
      :excellent

      iex> Metastatic.Analysis.Encapsulation.Result.assess(65)
      :fair

      iex> Metastatic.Analysis.Encapsulation.Result.assess(35)
      :very_poor
  """
  @spec assess(non_neg_integer()) :: assessment()
  def assess(score) do
    cond do
      score >= 90 -> :excellent
      score >= 75 -> :good
      score >= 60 -> :fair
      score >= 40 -> :poor
      true -> :very_poor
    end
  end

  @doc """
  Generate recommendations based on violations.

  ## Examples

      iex> violations = [%{type: :public_state, severity: :critical, message: "x", location: nil, suggestion: nil}]
      iex> recs = Metastatic.Analysis.Encapsulation.Result.generate_recommendations(violations, 5, 0)
      iex> Enum.any?(recs, &String.contains?(&1, "private"))
      true
  """
  @spec generate_recommendations([violation()], non_neg_integer(), non_neg_integer()) :: [
          String.t()
        ]
  def generate_recommendations(violations, _public_count, accessor_count) do
    recs = []

    # Check for public state violations
    recs =
      if Enum.any?(violations, &(&1.type == :public_state)) do
        ["Make instance variables private and provide controlled access through methods" | recs]
      else
        recs
      end

    # Check for missing accessors
    recs =
      if Enum.any?(violations, &(&1.type == :missing_accessor)) do
        ["Add getter/setter methods instead of accessing state directly" | recs]
      else
        recs
      end

    # Check for excessive accessors (data class smell)
    recs =
      if accessor_count > 10 do
        [
          "Consider if this is a data class - encapsulation may require behavior, not just accessors"
          | recs
        ]
      else
        recs
      end

    # Check for leaky abstractions
    recs =
      if Enum.any?(violations, &(&1.type == :leaky_abstraction)) do
        [
          "Hide implementation details - provide higher-level methods that encapsulate behavior"
          | recs
        ]
      else
        recs
      end

    # Default recommendation if no specific issues
    recs =
      if Enum.empty?(recs) do
        [
          "Encapsulation is good - continue maintaining clear boundaries between interface and implementation"
        ]
      else
        recs
      end

    Enum.reverse(recs)
  end

  @doc """
  Create a violation record.

  ## Examples

      iex> Metastatic.Analysis.Encapsulation.Result.violation(:public_state, :critical, "Variable 'x' is public", "x", "Make 'x' private")
      %{type: :public_state, severity: :critical, message: "Variable 'x' is public", location: "x", suggestion: "Make 'x' private"}
  """
  @spec violation(violation_type(), severity(), String.t(), String.t() | nil, String.t() | nil) ::
          violation()
  def violation(type, severity, message, location \\ nil, suggestion \\ nil) do
    %{
      type: type,
      severity: severity,
      message: message,
      location: location,
      suggestion: suggestion
    }
  end
end
