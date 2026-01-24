defmodule Metastatic.Analysis.StateManagement.Result do
  @moduledoc """
  Result structure for state management analysis.

  Analyzes how containers manage state, identifying patterns like:
  - Stateful vs stateless design
  - Mutation patterns
  - State initialization
  - State consistency

  ## State Patterns

  - **Stateless**: Container has no mutable state
  - **Immutable State**: State exists but is never modified after initialization
  - **Controlled Mutation**: State modified through well-defined methods
  - **Uncontrolled Mutation**: State modified directly without validation

  ## Examples

      iex> result = %Metastatic.Analysis.StateManagement.Result{
      ...>   container_name: "Calculator",
      ...>   pattern: :stateless,
      ...>   state_count: 0,
      ...>   mutation_count: 0
      ...> }
      iex> result.pattern
      :stateless
  """

  @type pattern ::
          :stateless
          | :immutable_state
          | :controlled_mutation
          | :uncontrolled_mutation
          | :mixed

  @type mutation :: %{
          location: String.t(),
          state_var: String.t(),
          operation: :assignment | :augmented_assignment | :increment | :decrement,
          severity: :low | :medium | :high
        }

  @type assessment :: :excellent | :good | :fair | :poor

  @type t :: %__MODULE__{
          container_name: String.t() | nil,
          container_type: :module | :class | :namespace | nil,
          pattern: pattern(),
          state_count: non_neg_integer(),
          mutation_count: non_neg_integer(),
          mutations: [mutation()],
          initialized_state: [String.t()],
          uninitialized_state: [String.t()],
          read_only_state: [String.t()],
          mutable_state: [String.t()],
          assessment: assessment(),
          warnings: [String.t()],
          recommendations: [String.t()]
        }

  defstruct container_name: nil,
            container_type: nil,
            pattern: :stateless,
            state_count: 0,
            mutation_count: 0,
            mutations: [],
            initialized_state: [],
            uninitialized_state: [],
            read_only_state: [],
            mutable_state: [],
            assessment: :excellent,
            warnings: [],
            recommendations: []

  @doc """
  Identify state management pattern based on metrics.

  ## Examples

      iex> Metastatic.Analysis.StateManagement.Result.identify_pattern(0, 0, [], [])
      :stateless

      iex> Metastatic.Analysis.StateManagement.Result.identify_pattern(2, 0, ["x", "y"], [])
      :immutable_state

      iex> Metastatic.Analysis.StateManagement.Result.identify_pattern(3, 5, ["x"], ["y", "z"])
      :controlled_mutation
  """
  @spec identify_pattern(non_neg_integer(), non_neg_integer(), [String.t()], [String.t()]) ::
          pattern()
  def identify_pattern(state_count, mutation_count, read_only, mutable) do
    cond do
      # No state at all
      state_count == 0 ->
        :stateless

      # Has state but never mutated
      mutation_count == 0 ->
        :immutable_state

      # All state is read-only except explicitly mutable
      match?([_ | _], read_only) and match?([_ | _], mutable) ->
        :controlled_mutation

      # Has mutations with mixed patterns
      mutation_count > 0 and match?([_ | _], mutable) ->
        :controlled_mutation

      # Mutations without clear pattern
      mutation_count > 0 ->
        :uncontrolled_mutation

      # Mixed or unclear
      true ->
        :mixed
    end
  end

  @doc """
  Assess state management quality.

  ## Examples

      iex> Metastatic.Analysis.StateManagement.Result.assess(:stateless, 0, [])
      :excellent

      iex> Metastatic.Analysis.StateManagement.Result.assess(:controlled_mutation, 5, [])
      :good

      iex> Metastatic.Analysis.StateManagement.Result.assess(:uncontrolled_mutation, 20, ["warning"])
      :poor
  """
  @spec assess(pattern(), non_neg_integer(), [String.t()]) :: assessment()
  def assess(pattern, mutation_count, warnings) do
    base_score =
      case pattern do
        :stateless -> 100
        :immutable_state -> 95
        :controlled_mutation -> 80
        :uncontrolled_mutation -> 50
        :mixed -> 60
      end

    # Reduce score based on mutations and warnings
    penalty = min(30, mutation_count * 2 + length(warnings) * 5)
    final_score = base_score - penalty

    cond do
      final_score >= 90 -> :excellent
      final_score >= 75 -> :good
      final_score >= 60 -> :fair
      true -> :poor
    end
  end

  @doc """
  Generate warnings based on state management issues.
  """
  @spec generate_warnings(pattern(), non_neg_integer(), [String.t()]) :: [String.t()]
  def generate_warnings(pattern, mutation_count, uninitialized) do
    warnings = []

    warnings =
      if pattern == :uncontrolled_mutation do
        [
          "State is mutated without clear encapsulation - consider using setter methods"
          | warnings
        ]
      else
        warnings
      end

    warnings =
      if mutation_count > 10 do
        ["High mutation count (#{mutation_count}) - consider reducing state changes" | warnings]
      else
        warnings
      end

    warnings =
      case uninitialized do
        [_ | _] ->
          [
            "State variables may be uninitialized: #{Enum.join(uninitialized, ", ")}"
            | warnings
          ]

        _ ->
          warnings
      end

    Enum.reverse(warnings)
  end

  @doc """
  Generate recommendations based on pattern.
  """
  @spec generate_recommendations(pattern(), non_neg_integer()) :: [String.t()]
  def generate_recommendations(pattern, state_count) do
    case pattern do
      :stateless ->
        ["Container is stateless - excellent for testability and concurrency"]

      :immutable_state ->
        [
          "State is immutable - good practice",
          "Consider making this explicit with final/const/readonly modifiers"
        ]

      :controlled_mutation ->
        [
          "State mutations are controlled through methods - good encapsulation",
          "Ensure all state modifications include proper validation"
        ]

      :uncontrolled_mutation ->
        [
          "Direct state mutation detected - refactor to use setter methods",
          "Add validation logic to state changes",
          "Consider making state private with controlled access"
        ]

      :mixed ->
        recs = ["Mixed state management pattern - consider standardizing approach"]

        if state_count > 5 do
          [
            "Large state footprint (#{state_count} variables) - consider splitting container"
            | recs
          ]
        else
          recs
        end
    end
  end

  @doc """
  Create a mutation record.
  """
  @spec mutation(String.t(), String.t(), atom(), atom()) :: mutation()
  def mutation(location, state_var, operation, severity \\ :medium) do
    %{
      location: location,
      state_var: state_var,
      operation: operation,
      severity: severity
    }
  end
end
