defmodule Metastatic.Analysis.StateManagement do
  @moduledoc """
  State management analysis for containers (modules/classes).

  Analyzes how containers manage state, identifying patterns and potential issues.

  ## Patterns Detected

  - **Stateless**: No instance state (best for immutability)
  - **Immutable State**: State set once, never modified
  - **Controlled Mutation**: State modified through encapsulated methods
  - **Uncontrolled Mutation**: Direct state modification

  ## Examples

      # Stateless container
      ast = {:container, [container_type: :class, name: "Math"], [
        {:function_def, [name: "add", params: ["x", "y"], visibility: :public], [
         {:binary_op, [category: :arithmetic, operator: :+], [{:variable, [], "x"}, {:variable, [], "y"}]}]}
      ]}

      doc = Document.new(ast, :python)
      {:ok, result} = StateManagement.analyze(doc)
      result.pattern  # => :stateless

      # Controlled mutation
      ast = {:container, [container_type: :class, name: "Counter"], [
        {:function_def, [name: "increment", params: [], visibility: :public], [
         {:augmented_assignment, [operator: :+], [
          {:attribute_access, [], [{:variable, [], "self"}, "count"]}, {:literal, [subtype: :integer], 1}]}]}
      ]}

      {:ok, result} = StateManagement.analyze(doc)
      result.pattern  # => :controlled_mutation
  """

  alias Metastatic.{Analysis.StateManagement.Result, Document}

  use Metastatic.Document.Analyzer,
    doc: """
    Analyze state management of a container.

    ## Examples

        iex> ast = {:container, [container_type: :class, name: "Empty"], [[]]}
        iex> doc = Metastatic.Document.new(ast, :python)
        iex> {:ok, result} = Metastatic.Analysis.StateManagement.analyze(doc)
        iex> result.pattern
        :stateless
    """

  @impl Metastatic.Document.Analyzer
  def handle_analyze(%Document{ast: ast}, _opts \\ []) do
    with {:ok, container_type, container_name, members} <- extract_container(ast),
         do: {:ok, analyze_container(container_type, container_name, members)}
  end

  # Private implementation (3-tuple format)

  defp extract_container({:container, meta, [members]}) when is_list(meta) do
    type = Keyword.get(meta, :container_type, :class)
    name = Keyword.get(meta, :name, "anonymous")
    members_list = if is_list(members), do: members, else: [members]
    {:ok, type, name, members_list}
  end

  defp extract_container(_), do: {:error, "AST does not contain a container"}

  defp analyze_container(container_type, container_name, members) do
    methods = Enum.filter(members, &match?({:function_def, _, _}, &1))

    # Collect all state variables
    all_state = collect_all_state(members)
    state_count = length(all_state)

    # Identify initialized vs uninitialized
    {initialized, uninitialized} = categorize_initialization(members, all_state)

    # Track mutations
    mutations = collect_mutations(methods)
    mutation_count = length(mutations)
    mutable_state = mutations |> Enum.map(& &1.state_var) |> Enum.uniq()

    # Identify read-only state
    read_only_state = all_state -- mutable_state

    # Determine pattern
    pattern = Result.identify_pattern(state_count, mutation_count, read_only_state, mutable_state)

    # Generate assessment
    warnings = Result.generate_warnings(pattern, mutation_count, uninitialized)
    assessment = Result.assess(pattern, mutation_count, warnings)
    recommendations = Result.generate_recommendations(pattern, state_count)

    %Result{
      container_name: container_name,
      container_type: container_type,
      pattern: pattern,
      state_count: state_count,
      mutation_count: mutation_count,
      mutations: mutations,
      initialized_state: Enum.sort(initialized),
      uninitialized_state: Enum.sort(uninitialized),
      read_only_state: Enum.sort(read_only_state),
      mutable_state: Enum.sort(mutable_state),
      assessment: assessment,
      warnings: warnings,
      recommendations: recommendations
    }
  end

  # Collect all state variables accessed in the container
  defp collect_all_state(members) do
    members
    |> Enum.flat_map(&extract_state_vars/1)
    |> Enum.uniq()
  end

  # 3-tuple format
  defp extract_state_vars({:function_def, _meta, [body]}), do: extract_state_from_ast(body)

  defp extract_state_vars({:property, _meta, [getter, setter]}),
    do: extract_state_from_ast(getter) ++ extract_state_from_ast(setter)

  defp extract_state_vars(_), do: []

  defp extract_state_from_ast(nil), do: []

  defp extract_state_from_ast(ast) do
    case ast do
      # 3-tuple format
      {:attribute_access, _meta, [{:variable, _, var}, attr]} when var in ["self", "this", "@"] ->
        [attr]

      {:assignment, _meta, [target, value]} ->
        extract_state_from_ast(target) ++ extract_state_from_ast(value)

      {:augmented_assignment, _meta, [target, value]} ->
        extract_state_from_ast(target) ++ extract_state_from_ast(value)

      {:binary_op, _meta, [left, right]} ->
        extract_state_from_ast(left) ++ extract_state_from_ast(right)

      {:conditional, _meta, [cond_expr, then_br, else_br]} ->
        extract_state_from_ast(cond_expr) ++
          extract_state_from_ast(then_br) ++
          extract_state_from_ast(else_br)

      {:block, _meta, stmts} when is_list(stmts) ->
        Enum.flat_map(stmts, &extract_state_from_ast/1)

      {:function_call, _meta, args} when is_list(args) ->
        Enum.flat_map(args, &extract_state_from_ast/1)

      _ ->
        []
    end
  end

  # Categorize state as initialized or uninitialized (3-tuple format)
  defp categorize_initialization(members, all_state) do
    # Look for initialization methods (constructor, __init__, initialize, etc.)
    init_methods =
      members
      |> Enum.filter(fn
        {:function_def, meta, _} when is_list(meta) ->
          name = Keyword.get(meta, :name, "")
          name in ["__init__", "initialize", "constructor", "init"]

        _ ->
          false
      end)

    # Extract state initialized in these methods
    initialized =
      init_methods
      |> Enum.flat_map(fn {:function_def, _meta, [body]} ->
        find_initialized_state(body)
      end)
      |> Enum.uniq()

    uninitialized = all_state -- initialized

    {initialized, uninitialized}
  end

  defp find_initialized_state(ast) do
    case ast do
      {:assignment, _meta, [{:attribute_access, _, [{:variable, _, var}, attr]}, _value]}
      when var in ["self", "this", "@"] ->
        [attr]

      {:block, _meta, stmts} when is_list(stmts) ->
        Enum.flat_map(stmts, &find_initialized_state/1)

      _ ->
        []
    end
  end

  # Collect all mutations in methods (3-tuple format)
  defp collect_mutations(methods) do
    methods
    |> Enum.flat_map(fn {:function_def, meta, [body]} ->
      name = Keyword.get(meta, :name, "anonymous")
      find_mutations(body, name)
    end)
  end

  defp find_mutations(ast, location) do
    case ast do
      {:assignment, _meta, [{:attribute_access, _, [{:variable, _, var}, attr]}, _value]}
      when var in ["self", "this", "@"] ->
        [Result.mutation(location, attr, :assignment)]

      {:augmented_assignment, _ameta,
       [{:attribute_access, _, [{:variable, _, var}, attr]}, _value]}
      when var in ["self", "this", "@"] ->
        [Result.mutation(location, attr, :augmented_assignment)]

      {:block, _meta, stmts} when is_list(stmts) ->
        Enum.flat_map(stmts, &find_mutations(&1, location))

      {:conditional, _meta, [_cond, then_br, else_br]} ->
        find_mutations(then_br, location) ++ find_mutations(else_br, location)

      {:loop, meta, children} when is_list(meta) and is_list(children) ->
        Enum.flat_map(children, &find_mutations(&1, location))

      _ ->
        []
    end
  end
end
