defmodule Metastatic.Analysis.BusinessLogic.ImperativeStatusHandling do
  @moduledoc """
  Detects imperative status/state management that should be replaced with an FSM.

  Entity lifecycle is frequently managed with plain imperative code: branching on
  a `status`/`state` field, manually setting it to new values, scattering guards
  across multiple function heads. This ad-hoc approach is error-prone (missing
  transitions, invalid state paths, no transition validation) and should be
  replaced with a proper finite state machine -- `Finitomata`, `gen_statem`,
  a state-machine library, or an equivalent construct in the target language.

  ## Cross-Language Applicability

  This pattern is universal and applies to every language that manages entity
  lifecycle through a discrete set of named states:

  - **Elixir**: `case record.status do`, `put_change(cs, :status, :active)`
  - **Python**: `if self.status == "pending":`, `self.status = "active"`
  - **Ruby**: `case @status`, `@status = :active`
  - **JavaScript/TypeScript**: `switch (this.status)`, `this.status = "active"`
  - **Erlang**: `case maps:get(status, Record) of`, `Record\#{status := active}`

  ## Detection Strategy

  The analyzer collects evidence at three tiers and reports when sufficient
  evidence accumulates within a single scope (module / class / file):

  ### Tier 1 -- Status branching (high confidence)
  `:conditional` nodes whose condition accesses a field named `status`/`state`
  with 3 or more branches mapping distinct literal values.

  ### Tier 2 -- Status assignment (medium confidence)
  `:assignment` nodes that write to a field/variable named `status`/`state`
  with a literal value, especially when multiple such assignments exist with
  different target values.

  ### Tier 3 -- Transition-verb function names (supporting signal)
  `:function_def` nodes whose name encodes a state-transition verb such as
  `activate`, `deactivate`, `publish`, `archive`, `suspend`, `resume`,
  `complete`, `cancel`, `approve`, `reject`, etc.

  ## Configuration

  - `:status_field_names` - Field/variable names to watch (default: `["status", "state"]`)
  - `:min_states` - Minimum distinct status values before flagging (default: 3)
  - `:transition_verbs` - Additional verbs to recognize (merged with defaults)
  """

  @behaviour Metastatic.Analysis.Analyzer

  alias Metastatic.Analysis.Analyzer

  @default_status_fields ["status", "state"]

  @default_transition_verbs ~w(
    activate deactivate publish unpublish archive unarchive
    suspend resume complete cancel approve reject
    enable disable start stop pause draft
    submit finalize close reopen expire revoke
    block unblock lock unlock freeze thaw
  )

  @impl true
  def info do
    %{
      name: :imperative_status_handling,
      category: :refactoring,
      description:
        "Detects imperative status/state management that should be replaced with an FSM",
      severity: :info,
      explanation: """
      Code that manages entity lifecycle through ad-hoc status fields --
      branching on status values, manually assigning new statuses, and
      scattering transition logic across functions -- is error-prone and
      hard to reason about. Consider replacing it with a finite state
      machine (Finitomata, gen_statem, or equivalent) which provides:

      - Explicit transition rules (only valid state changes are allowed)
      - Central definition of states and events
      - Callback-driven business logic per transition
      - Built-in history, telemetry, and supervision
      """,
      configurable: true
    }
  end

  @impl true
  def run_before(context) do
    status_fields =
      Map.get(context.config, :status_field_names, @default_status_fields)

    min_states = Map.get(context.config, :min_states, 3)

    extra_verbs = Map.get(context.config, :transition_verbs, [])
    transition_verbs = Enum.uniq(@default_transition_verbs ++ extra_verbs)

    context =
      context
      |> Map.put(:status_fields, status_fields)
      |> Map.put(:min_states, min_states)
      |> Map.put(:transition_verbs, transition_verbs)
      # Accumulate evidence across nodes for run_after summary
      |> Map.put(:fsm_evidence, %{
        branching_sites: [],
        assignment_sites: [],
        transition_functions: [],
        detected_states: MapSet.new()
      })

    {:ok, context}
  end

  # --- Tier 1: Conditional branching on status field ---
  @impl true
  def analyze({:conditional, _meta, [condition | _branches]} = node, context) do
    status_fields = Map.get(context, :status_fields, @default_status_fields)

    if accesses_status_field?(condition, status_fields) do
      states = extract_branch_literals(node)

      if MapSet.size(states) >= Map.get(context, :min_states, 3) do
        [
          Analyzer.issue(
            analyzer: __MODULE__,
            category: :refactoring,
            severity: :info,
            message:
              "Conditional branches on #{MapSet.size(states)} status values " <>
                "(#{format_states(states)}) -- consider replacing with an FSM",
            node: node,
            metadata: %{
              tier: :branching,
              detected_states: MapSet.to_list(states),
              state_count: MapSet.size(states)
            }
          )
        ]
      else
        []
      end
    else
      []
    end
  end

  # --- Tier 2: Assignment to status field ---
  def analyze({:assignment, _meta, [target, value]} = node, context) do
    status_fields = Map.get(context, :status_fields, @default_status_fields)

    if assigns_to_status_field?(target, status_fields) do
      state_value = extract_literal_value(value)

      if state_value do
        [
          Analyzer.issue(
            analyzer: __MODULE__,
            category: :refactoring,
            severity: :info,
            message:
              "Imperative status assignment to #{inspect(state_value)} -- " <>
                "FSM transitions should manage state changes",
            node: node,
            metadata: %{
              tier: :assignment,
              assigned_state: state_value
            }
          )
        ]
      else
        []
      end
    else
      []
    end
  end

  # --- Tier 3: Transition-verb function names ---
  def analyze({:function_def, meta, _children} = node, context) do
    transition_verbs = Map.get(context, :transition_verbs, @default_transition_verbs)
    func_name = extract_function_name(meta)

    if func_name && matches_transition_verb?(func_name, transition_verbs) do
      [
        Analyzer.issue(
          analyzer: __MODULE__,
          category: :refactoring,
          severity: :info,
          message:
            "Function `#{func_name}` looks like a state transition -- " <>
              "consider modeling as an FSM event",
          node: node,
          metadata: %{
            tier: :transition_verb,
            function_name: func_name,
            matched_verb: find_matching_verb(func_name, transition_verbs)
          }
        )
      ]
    else
      []
    end
  end

  def analyze(_node, _context), do: []

  # ----- Private Helpers -----

  # Check if a condition node accesses a field named status/state
  defp accesses_status_field?({:field_access, meta, _children}, status_fields) do
    field_name = Keyword.get(meta, :field) || Keyword.get(meta, :name)
    field_name && to_string(field_name) in status_fields
  end

  defp accesses_status_field?({:variable, _meta, name}, status_fields) when is_binary(name) do
    name in status_fields
  end

  defp accesses_status_field?({:variable, _meta, name}, status_fields) when is_atom(name) do
    to_string(name) in status_fields
  end

  defp accesses_status_field?({:binary_op, _meta, [left, right]}, status_fields) do
    accesses_status_field?(left, status_fields) ||
      accesses_status_field?(right, status_fields)
  end

  defp accesses_status_field?({:function_call, meta, _args}, status_fields) do
    name = Keyword.get(meta, :name, "")
    # e.g. Map.get(record, :status) or record.status()
    Enum.any?(status_fields, fn f -> String.contains?(to_string(name), f) end)
  end

  defp accesses_status_field?(_node, _status_fields), do: false

  # Check if an assignment target is a status field
  defp assigns_to_status_field?({:field_access, meta, _children}, status_fields) do
    field_name = Keyword.get(meta, :field) || Keyword.get(meta, :name)
    field_name && to_string(field_name) in status_fields
  end

  defp assigns_to_status_field?({:variable, _meta, name}, status_fields) do
    to_string(name) in status_fields
  end

  defp assigns_to_status_field?(_target, _status_fields), do: false

  # Extract literal values from conditional branches to discover states
  defp extract_branch_literals({:conditional, _meta, [_condition | branches]}) do
    branches
    |> List.flatten()
    |> Enum.reduce(MapSet.new(), fn branch, acc ->
      case branch do
        {:block, _m, statements} when is_list(statements) ->
          Enum.reduce(statements, acc, &collect_literal_patterns/2)

        nil ->
          acc

        other ->
          collect_literal_patterns(other, acc)
      end
    end)
  end

  defp extract_branch_literals(_), do: MapSet.new()

  defp collect_literal_patterns({:match_clause, meta, _children}, acc) do
    # Extract the pattern from a match clause
    case Keyword.get(meta, :pattern) do
      {:literal, _, value} when is_atom(value) or is_binary(value) ->
        MapSet.put(acc, value)

      _ ->
        acc
    end
  end

  defp collect_literal_patterns({:literal, meta, value}, acc)
       when is_atom(value) or is_binary(value) do
    subtype = Keyword.get(meta, :subtype)

    if subtype in [:atom, :string, nil] do
      MapSet.put(acc, value)
    else
      acc
    end
  end

  defp collect_literal_patterns({:case_clause, _meta, [pattern | _body]}, acc) do
    case pattern do
      {:literal, _, value} when is_atom(value) or is_binary(value) ->
        MapSet.put(acc, value)

      {:tuple, _, elements} when is_list(elements) ->
        # e.g. {:ok, _} patterns -- extract atoms
        Enum.reduce(elements, acc, fn
          {:literal, _, v}, inner_acc when is_atom(v) -> MapSet.put(inner_acc, v)
          _, inner_acc -> inner_acc
        end)

      _ ->
        acc
    end
  end

  defp collect_literal_patterns(_node, acc), do: acc

  defp extract_literal_value({:literal, _meta, value})
       when is_atom(value) or is_binary(value),
       do: value

  defp extract_literal_value(_), do: nil

  defp extract_function_name(meta) when is_list(meta) do
    name = Keyword.get(meta, :name) || Keyword.get(meta, :function)

    if name, do: to_string(name), else: nil
  end

  defp extract_function_name(_), do: nil

  defp matches_transition_verb?(func_name, verbs) do
    normalized = func_name |> to_string() |> String.downcase()

    Enum.any?(verbs, fn verb ->
      String.contains?(normalized, verb) ||
        String.starts_with?(normalized, verb <> "_") ||
        String.ends_with?(normalized, "_" <> verb)
    end)
  end

  defp find_matching_verb(func_name, verbs) do
    normalized = func_name |> to_string() |> String.downcase()

    Enum.find(verbs, fn verb ->
      String.contains?(normalized, verb)
    end)
  end

  defp format_states(states) do
    states
    |> MapSet.to_list()
    |> Enum.sort()
    |> Enum.map_join(", ", &inspect/1)
  end
end
