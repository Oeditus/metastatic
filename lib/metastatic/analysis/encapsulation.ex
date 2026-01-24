defmodule Metastatic.Analysis.Encapsulation do
  @moduledoc """
  Encapsulation analysis for containers (modules/classes).

  Detects violations of encapsulation principles - the practice of hiding internal
  state and requiring all interaction to go through well-defined interfaces.

  ## Principles Checked

  1. **Information Hiding**: Internal state should be private
  2. **Controlled Access**: State access should go through methods
  3. **Interface Segregation**: Public interface should be minimal and focused
  4. **Implementation Hiding**: Internal details should not leak

  ## Detected Violations

  ### Public State (Critical)
  Instance variables that are publicly accessible without getters/setters.
  Breaks encapsulation by allowing uncontrolled state modification.

  ### Missing Accessors (High)
  Direct state access/modification without using accessor methods.
  Bypasses potential validation and business logic.

  ### Excessive Accessors (Medium)
  Too many getter/setter pairs relative to behavior methods.
  May indicate a "data class" that lacks encapsulation of behavior.

  ### Leaky Abstraction (Medium)
  Methods that expose internal implementation details.
  Makes refactoring difficult and couples clients to implementation.

  ## Examples

      # Good encapsulation
      ast = {:container, :class, "BankAccount", %{}, [
        {:function_def, :public, "deposit", ["amount"], %{},
         {:augmented_assignment, :+,
          {:attribute_access, {:variable, "self"}, "balance"}, {:variable, "amount"}}},
        {:function_def, :public, "get_balance", [], %{},
         {:attribute_access, {:variable, "self"}, "balance"}}
      ]}

      doc = Document.new(ast, :python)
      {:ok, result} = Encapsulation.analyze(doc)

      result.violations  # => []
      result.score       # => 100
      result.assessment  # => :excellent

      # Poor encapsulation - direct state access
      ast = {:container, :class, "User", %{}, [
        {:function_def, :public, "process", [], %{},
         {:assignment, {:attribute_access, {:variable, "self"}, "status"}, {:literal, :string, "done"}}}
      ]}

      {:ok, result} = Encapsulation.analyze(doc)
      result.violations  # => [%{type: :missing_accessor, ...}]
      result.assessment  # => :poor
  """

  alias Metastatic.{Analysis.Encapsulation.Result, Document}

  @doc """
  Analyze encapsulation of a container (module/class/namespace).

  Returns `{:ok, result}` if the AST contains a container, or `{:error, reason}` otherwise.

  ## Examples

      iex> ast = {:container, :class, "Example", %{}, [
      ...>   {:function_def, :public, "get_value", [], %{},
      ...>    {:attribute_access, {:variable, "self"}, "value"}}
      ...> ]}
      iex> doc = Metastatic.Document.new(ast, :python)
      iex> {:ok, result} = Metastatic.Analysis.Encapsulation.analyze(doc)
      iex> result.score
      100
      iex> result.assessment
      :excellent
  """
  @spec analyze(Document.t()) :: {:ok, Result.t()} | {:error, String.t()}
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
    # Extract methods and properties
    methods = Enum.filter(members, &match?({:function_def, _, _, _, _, _}, &1))
    properties = Enum.filter(members, &match?({:property, _, _, _, _}, &1))

    # Count visibility
    public_methods =
      Enum.count(methods, fn {:function_def, vis, _, _, _, _} -> vis == :public end)

    private_methods =
      Enum.count(methods, fn {:function_def, vis, _, _, _, _} -> vis == :private end)

    # Identify accessors (getters/setters)
    accessor_count = count_accessors(methods)

    # Extract all state variables accessed in the container
    state_variables = extract_state_variables(members)

    # Detect violations
    violations = detect_violations(members, methods, properties)

    # Calculate metrics
    score = Result.calculate_score(violations)
    assessment = Result.assess(score)
    recommendations = Result.generate_recommendations(violations, public_methods, accessor_count)

    %Result{
      container_name: container_name,
      container_type: container_type,
      violations: violations,
      score: score,
      assessment: assessment,
      public_methods: public_methods,
      private_methods: private_methods,
      accessor_count: accessor_count,
      state_variables: Enum.sort(state_variables),
      recommendations: recommendations
    }
  end

  # Count methods that are simple accessors (getters/setters)
  defp count_accessors(methods) do
    Enum.count(methods, &accessor?/1)
  end

  # Check if a function is a simple accessor
  defp accessor?({:function_def, :public, name, params, _meta, body}) do
    # Getter: no params, returns attribute access
    getter? = params == [] and getter_body?(body)

    # Setter: one param, assigns to attribute
    setter? = match?([_], params) and setter_body?(body)

    # Check if name suggests accessor (get_*, set_*, or property-style)
    name_suggests_accessor =
      String.starts_with?(name, ["get_", "set_"]) or
        not String.contains?(name, "_")

    (getter? or setter?) and name_suggests_accessor
  end

  defp accessor?(_), do: false

  # Check if body is a getter (returns attribute access)
  defp getter_body?({:attribute_access, _, _}), do: true
  defp getter_body?(_), do: false

  # Check if body is a setter (assigns to attribute)
  defp setter_body?({:assignment, {:attribute_access, _, _}, _}), do: true
  defp setter_body?(_), do: false

  # Extract all state variables accessed in members
  defp extract_state_variables(members) do
    members
    |> Enum.flat_map(&extract_state_from_member/1)
    |> Enum.uniq()
  end

  defp extract_state_from_member({:function_def, _, _, _, _, body}) do
    extract_state_accesses(body, [])
  end

  defp extract_state_from_member({:property, _name, getter, setter, _metadata}) do
    getter_vars = if getter, do: extract_state_from_member(getter), else: []
    setter_vars = if setter, do: extract_state_from_member(setter), else: []
    getter_vars ++ setter_vars
  end

  defp extract_state_from_member(_), do: []

  defp extract_state_accesses(ast, acc) do
    case ast do
      {:attribute_access, {:variable, var}, attr} when var in ["self", "this", "@"] ->
        [attr | acc]

      {:augmented_assignment, _op, target, value} ->
        acc = extract_state_accesses(target, acc)
        extract_state_accesses(value, acc)

      {:assignment, target, value} ->
        acc = extract_state_accesses(target, acc)
        extract_state_accesses(value, acc)

      {:binary_op, _, _, left, right} ->
        acc = extract_state_accesses(left, acc)
        extract_state_accesses(right, acc)

      {:conditional, cond, then_br, else_br} ->
        acc = extract_state_accesses(cond, acc)
        acc = extract_state_accesses(then_br, acc)
        if else_br, do: extract_state_accesses(else_br, acc), else: acc

      {:block, stmts} when is_list(stmts) ->
        Enum.reduce(stmts, acc, fn stmt, a -> extract_state_accesses(stmt, a) end)

      {:function_call, _name, args} ->
        Enum.reduce(args, acc, fn arg, a -> extract_state_accesses(arg, a) end)

      {:loop, :while, condition, body} ->
        acc = extract_state_accesses(condition, acc)
        extract_state_accesses(body, acc)

      {:loop, _, _iter, coll, body} ->
        acc = extract_state_accesses(coll, acc)
        extract_state_accesses(body, acc)

      _ ->
        acc
    end
  end

  # Detect encapsulation violations
  defp detect_violations(_members, methods, _properties) do
    violations = []

    # Check for direct state assignments without accessors
    violations = violations ++ detect_missing_accessors(methods)

    # Check for excessive accessors (data class smell)
    violations = violations ++ detect_excessive_accessors(methods)

    # Check for public methods accessing too much state
    violations = violations ++ detect_leaky_abstractions(methods)

    violations
  end

  # Detect methods that directly modify state without proper encapsulation
  defp detect_missing_accessors(methods) do
    methods
    |> Enum.flat_map(fn {:function_def, visibility, name, _params, _meta, body} = method ->
      # Skip if it's already an accessor
      if accessor?(method) do
        []
      else
        # Check if method directly assigns to state
        if visibility == :public and has_direct_state_assignment?(body) do
          [
            Result.violation(
              :missing_accessor,
              :high,
              "Method '#{name}' directly modifies state - consider using setter methods",
              name,
              "Extract state modification into private methods or setters"
            )
          ]
        else
          []
        end
      end
    end)
  end

  # Check if AST contains direct state assignments
  defp has_direct_state_assignment?(ast) do
    case ast do
      {:assignment, {:attribute_access, {:variable, var}, _attr}, _value}
      when var in ["self", "this", "@"] ->
        true

      {:augmented_assignment, _op, {:attribute_access, {:variable, var}, _attr}, _value}
      when var in ["self", "this", "@"] ->
        true

      {:block, stmts} when is_list(stmts) ->
        Enum.any?(stmts, &has_direct_state_assignment?/1)

      {:conditional, _cond, then_br, else_br} ->
        has_direct_state_assignment?(then_br) or
          (else_br != nil and has_direct_state_assignment?(else_br))

      {:loop, :while, _condition, body} ->
        has_direct_state_assignment?(body)

      {:loop, _, _iter, _coll, body} ->
        has_direct_state_assignment?(body)

      _ ->
        false
    end
  end

  # Detect excessive accessors (data class smell)
  defp detect_excessive_accessors(methods) do
    accessor_count = count_accessors(methods)
    total_public = Enum.count(methods, fn {:function_def, vis, _, _, _, _} -> vis == :public end)

    # If more than 70% of public methods are accessors, it's a data class smell
    if total_public > 0 and accessor_count / total_public > 0.7 and accessor_count > 5 do
      [
        Result.violation(
          :excessive_accessors,
          :medium,
          "Container has #{accessor_count} accessors out of #{total_public} public methods - may be a data class",
          nil,
          "Add behavior methods that encapsulate business logic, not just state access"
        )
      ]
    else
      []
    end
  end

  # Detect methods that expose too much internal state (leaky abstraction)
  defp detect_leaky_abstractions(methods) do
    # Check for public methods that return internal collections or complex state
    methods
    |> Enum.flat_map(fn {:function_def, visibility, name, _params, _meta, body} ->
      if visibility == :public and returns_internal_structure?(body) do
        [
          Result.violation(
            :leaky_abstraction,
            :medium,
            "Method '#{name}' may expose internal implementation details",
            name,
            "Consider returning copies or immutable views of internal state"
          )
        ]
      else
        []
      end
    end)
  end

  # Check if method returns internal collections or complex structures
  defp returns_internal_structure?(ast) do
    case ast do
      # Returning a list/tuple of internal state
      {:list, elems} when is_list(elems) ->
        Enum.any?(elems, fn elem ->
          case elem do
            {:attribute_access, {:variable, var}, _} when var in ["self", "this", "@"] -> true
            _ -> false
          end
        end)

      {:tuple, elems} when is_list(elems) ->
        Enum.any?(elems, fn elem ->
          case elem do
            {:attribute_access, {:variable, var}, _} when var in ["self", "this", "@"] -> true
            _ -> false
          end
        end)

      # Early return
      {:early_return, value} ->
        returns_internal_structure?(value)

      # Conditional
      {:conditional, _cond, then_br, _else_br} ->
        returns_internal_structure?(then_br)

      # Block - check last statement
      {:block, [_ | _] = stmts} ->
        returns_internal_structure?(List.last(stmts))

      _ ->
        false
    end
  end
end
