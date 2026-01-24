defmodule Metastatic.Analysis.Cohesion do
  @moduledoc """
  Cohesion analysis for containers (modules/classes).

  Measures how well the members (methods/functions) of a container work together.
  High cohesion indicates that members are closely related and work toward a
  common purpose, which is a desirable property in object-oriented design.

  ## Supported Metrics

  ### LCOM (Lack of Cohesion of Methods)
  Measures the number of disjoint sets of methods. Lower is better.
  - LCOM = 0: Perfect cohesion (all methods share state)
  - LCOM > 0: Poor cohesion (methods form disconnected groups)

  ### TCC (Tight Class Cohesion)
  Ratio of directly connected method pairs. Range: 0.0-1.0, higher is better.
  - TCC = 1.0: All methods directly share state
  - TCC > 0.5: Good cohesion
  - TCC < 0.3: Poor cohesion

  ### LCC (Loose Class Cohesion)
  Ratio of directly or indirectly connected method pairs. Range: 0.0-1.0.
  - LCC >= TCC always
  - High LCC but low TCC: Methods connected through intermediaries

  ## Algorithm

  1. Extract all methods/functions from container
  2. For each method, identify which instance variables it accesses
  3. Build a connection graph between methods based on shared variables
  4. Calculate LCOM (number of disconnected components)
  5. Calculate TCC (direct connections / total possible pairs)
  6. Calculate LCC (transitive closure / total possible pairs)

  ## Examples

      # High cohesion - all methods use shared state
      ast = {:container, :class, \"BankAccount\", %{}, [
        {:function_def, :public, \"deposit\", [\"amount\"], %{},
         {:augmented_assignment, :+, {:attribute_access, {:variable, \"self\"}, \"balance\"}, {:variable, \"amount\"}}},
        {:function_def, :public, \"withdraw\", [\"amount\"], %{},
         {:augmented_assignment, :-, {:attribute_access, {:variable, \"self\"}, \"balance\"}, {:variable, \"amount\"}}},
        {:function_def, :public, \"get_balance\", [], %{},
         {:attribute_access, {:variable, \"self\"}, \"balance\"}}
      ]}

      doc = Document.new(ast, :python)
      {:ok, result} = Cohesion.analyze(doc)

      result.lcom           # => 0 (perfect cohesion)
      result.tcc            # => 1.0 (all methods connected)
      result.assessment     # => :excellent

      # Low cohesion - methods don't share state
      ast = {:container, :class, \"Utilities\", %{}, [
        {:function_def, :public, \"format_date\", [\"date\"], %{}, ...},
        {:function_def, :public, \"calculate_tax\", [\"amount\"], %{}, ...},
        {:function_def, :public, \"send_email\", [\"to\", \"msg\"], %{}, ...}
      ]}

      {:ok, result} = Cohesion.analyze(doc)
      result.lcom           # => 3 (three disjoint methods)
      result.tcc            # => 0.0 (no shared state)
      result.assessment     # => :very_poor
  """

  alias Metastatic.{Analysis.Cohesion.Result, Document}

  @doc """
  Analyze cohesion of a container (module/class/namespace).

  Returns `{:ok, result}` if the AST contains a container, or `{:error, reason}` otherwise.

  ## Examples

      iex> ast = {:container, :class, \"Calculator\", %{}, [
      ...>   {:function_def, :public, \"add\", [\"x\"], %{},
      ...>    {:augmented_assignment, :+, {:attribute_access, {:variable, \"self\"}, \"total\"}, {:variable, \"x\"}}},
      ...>   {:function_def, :public, \"get_total\", [], %{},
      ...>    {:attribute_access, {:variable, \"self\"}, \"total\"}}
      ...> ]}
      iex> doc = Metastatic.Document.new(ast, :python)
      iex> {:ok, result} = Metastatic.Analysis.Cohesion.analyze(doc)
      iex> result.lcom
      0
      iex> result.tcc
      1.0
  """
  @spec analyze(Document.t() | {atom(), term()}) :: {:ok, Result.t()} | {:error, term()}
  def analyze(input) when is_tuple(input) do
    case Document.normalize(input) do
      {:ok, doc} -> analyze(doc)
      {:error, reason} -> {:error, reason}
    end
  end

  def analyze(%Document{ast: ast}) do
    case extract_container(ast) do
      {:ok, container_type, container_name, members} ->
        result = analyze_container(container_type, container_name, members)
        {:ok, result}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private implementation

  defp extract_container({:container, type, name, _metadata, members}) do
    {:ok, type, name, members}
  end

  defp extract_container(_), do: {:error, "AST does not contain a container"}

  defp analyze_container(container_type, container_name, members) do
    # Extract only function definitions (not properties or other members)
    methods = Enum.filter(members, &match?({:function_def, _, _, _, _, _}, &1))

    # Extract state variables accessed by each method
    method_vars = Enum.map(methods, fn method -> {method, extract_accessed_state(method)} end)

    # Calculate metrics
    method_count = length(methods)
    method_pairs = calculate_method_pairs(method_count)

    # Build connection graph and calculate metrics
    {lcom, tcc, lcc, connected_pairs} = calculate_cohesion_metrics(method_vars, method_pairs)

    # Extract all unique shared state variables
    shared_state =
      method_vars
      |> Enum.flat_map(fn {_method, vars} -> vars end)
      |> Enum.uniq()
      |> Enum.sort()

    # Assess quality
    assessment = Result.assess(lcom, tcc)
    warnings = Result.generate_warnings(lcom, tcc, method_count)
    recommendations = Result.generate_recommendations(assessment, method_count, tcc)

    %Result{
      container_name: container_name,
      container_type: container_type,
      lcom: lcom,
      tcc: tcc,
      lcc: lcc,
      method_count: method_count,
      method_pairs: method_pairs,
      connected_pairs: connected_pairs,
      shared_state: shared_state,
      assessment: assessment,
      warnings: warnings,
      recommendations: recommendations
    }
  end

  # Calculate number of possible method pairs: n * (n - 1) / 2
  defp calculate_method_pairs(method_count) when method_count < 2, do: 0
  defp calculate_method_pairs(method_count), do: div(method_count * (method_count - 1), 2)

  # Extract state variables accessed by a method (attribute_access nodes)
  defp extract_accessed_state({:function_def, _vis, _name, _params, _meta, body}) do
    extract_state_accesses(body, MapSet.new())
    |> MapSet.to_list()
  end

  defp extract_state_accesses(ast, acc) do
    case ast do
      # Attribute access on self/this -> instance variable
      {:attribute_access, {:variable, var}, attr} when var in ["self", "this", "@"] ->
        MapSet.put(acc, attr)

      # Augmented assignment with attribute access
      {:augmented_assignment, _op, target, value} ->
        acc = extract_state_accesses(target, acc)
        extract_state_accesses(value, acc)

      # Property access
      {:property, _name, getter, setter, _metadata} ->
        acc = if getter, do: extract_state_accesses(getter, acc), else: acc
        if setter, do: extract_state_accesses(setter, acc), else: acc

      # Recurse into compound structures
      {:binary_op, _, _, left, right} ->
        acc = extract_state_accesses(left, acc)
        extract_state_accesses(right, acc)

      {:unary_op, _, _, operand} ->
        extract_state_accesses(operand, acc)

      {:conditional, cond, then_branch, else_branch} ->
        acc = extract_state_accesses(cond, acc)
        acc = extract_state_accesses(then_branch, acc)
        if else_branch, do: extract_state_accesses(else_branch, acc), else: acc

      {:assignment, target, value} ->
        acc = extract_state_accesses(target, acc)
        extract_state_accesses(value, acc)

      {:function_call, _name, args} ->
        Enum.reduce(args, acc, fn arg, a -> extract_state_accesses(arg, a) end)

      {:block, stmts} when is_list(stmts) ->
        Enum.reduce(stmts, acc, fn stmt, a -> extract_state_accesses(stmt, a) end)

      {:early_return, value} ->
        extract_state_accesses(value, acc)

      # Loops, lambdas, collections
      {:loop, :while, condition, body} ->
        acc = extract_state_accesses(condition, acc)
        extract_state_accesses(body, acc)

      {:loop, _, _iter, coll, body} ->
        acc = extract_state_accesses(coll, acc)
        extract_state_accesses(body, acc)

      {:lambda, _params, body} ->
        extract_state_accesses(body, acc)

      {:collection_op, _, func, coll} ->
        acc = extract_state_accesses(func, acc)
        extract_state_accesses(coll, acc)

      {:collection_op, _, func, coll, init} ->
        acc = extract_state_accesses(func, acc)
        acc = extract_state_accesses(coll, acc)
        extract_state_accesses(init, acc)

      # Containers and functions (nested)
      {:container, _type, _name, _metadata, members} when is_list(members) ->
        Enum.reduce(members, acc, fn member, a -> extract_state_accesses(member, a) end)

      {:function_def, _vis, _name, params, metadata, body} ->
        # Walk parameters
        acc =
          Enum.reduce(params, acc, fn
            {:pattern, pattern}, a -> extract_state_accesses(pattern, a)
            {:default, _name, default}, a -> extract_state_accesses(default, a)
            _simple_param, a -> a
          end)

        # Walk guards
        acc =
          case Map.get(metadata, :guards) do
            nil -> acc
            guard -> extract_state_accesses(guard, acc)
          end

        # Walk body
        extract_state_accesses(body, acc)

      # Literals, variables, etc. - no state access
      _ ->
        acc
    end
  end

  # Calculate LCOM, TCC, and LCC metrics
  defp calculate_cohesion_metrics(_method_vars, method_pairs) when method_pairs == 0 do
    # Less than 2 methods - no cohesion to measure
    {0, 0.0, 0.0, 0}
  end

  defp calculate_cohesion_metrics(method_vars, method_pairs) do
    # Build connection matrix: which methods share variables?
    connections = build_connection_matrix(method_vars)

    # Count directly connected pairs (TCC)
    connected_pairs = count_connected_pairs(connections)
    tcc = connected_pairs / method_pairs

    # Calculate LCOM using union-find algorithm
    lcom = calculate_lcom(connections, length(method_vars))

    # Calculate LCC (transitive closure)
    transitive_connections = calculate_transitive_closure(connections, length(method_vars))
    transitive_pairs = count_connected_pairs(transitive_connections)
    lcc = transitive_pairs / method_pairs

    {lcom, tcc, lcc, connected_pairs}
  end

  # Build connection matrix: true if methods i and j share at least one variable
  defp build_connection_matrix(method_vars) do
    indexed = Enum.with_index(method_vars)

    for {{_method1, vars1}, i} <- indexed,
        {{_method2, vars2}, j} <- indexed,
        i < j,
        into: %{} do
      # Check if methods share any variables
      shared = MapSet.new(vars1) |> MapSet.intersection(MapSet.new(vars2))
      {{i, j}, MapSet.size(shared) > 0}
    end
  end

  # Count how many method pairs are directly connected
  defp count_connected_pairs(connections) do
    Enum.count(connections, fn {_pair, connected} -> connected end)
  end

  # Calculate LCOM using union-find to count disconnected components
  defp calculate_lcom(connections, method_count) do
    # Initialize union-find with each method in its own set
    uf = Enum.reduce(0..(method_count - 1), %{}, fn i, acc -> Map.put(acc, i, i) end)

    # Union methods that are connected
    uf =
      Enum.reduce(connections, uf, fn {{i, j}, connected}, acc ->
        if connected do
          union(acc, i, j)
        else
          acc
        end
      end)

    # Count number of distinct roots (disconnected components)
    roots =
      Enum.map(0..(method_count - 1), fn i -> find(uf, i) end)
      |> Enum.uniq()
      |> length()

    # LCOM is number of components minus 1 (0 = fully connected)
    max(0, roots - 1)
  end

  # Union-find: find root of element
  defp find(uf, i) do
    parent = Map.get(uf, i, i)

    if parent == i do
      i
    else
      find(uf, parent)
    end
  end

  # Union-find: merge two sets
  defp union(uf, i, j) do
    root_i = find(uf, i)
    root_j = find(uf, j)

    if root_i != root_j do
      Map.put(uf, root_i, root_j)
    else
      uf
    end
  end

  # Calculate transitive closure using Floyd-Warshall
  defp calculate_transitive_closure(connections, method_count) do
    # Build adjacency matrix
    adj =
      for i <- 0..(method_count - 1),
          j <- 0..(method_count - 1),
          into: %{} do
        cond do
          i == j -> {{i, j}, true}
          i < j -> {{i, j}, Map.get(connections, {i, j}, false)}
          true -> {{i, j}, Map.get(connections, {j, i}, false)}
        end
      end

    # Floyd-Warshall: find transitive connections
    adj =
      for k <- 0..(method_count - 1), reduce: adj do
        acc ->
          for i <- 0..(method_count - 1),
              j <- 0..(method_count - 1),
              reduce: acc do
            inner_acc ->
              ik = Map.get(inner_acc, {i, k}, false)
              kj = Map.get(inner_acc, {k, j}, false)
              ij = Map.get(inner_acc, {i, j}, false)
              Map.put(inner_acc, {i, j}, ij or (ik and kj))
          end
      end

    # Extract upper triangle (i < j pairs)
    for {i, j} <- Map.keys(connections), into: %{} do
      {{i, j}, Map.get(adj, {i, j}, false)}
    end
  end
end
