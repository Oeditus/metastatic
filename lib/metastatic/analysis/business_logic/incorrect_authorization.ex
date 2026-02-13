defmodule Metastatic.Analysis.BusinessLogic.IncorrectAuthorization do
  @moduledoc """
  Detects incorrect authorization patterns (CWE-863).

  This analyzer identifies weak or flawed authorization logic patterns that
  could allow unauthorized access even when some authorization exists.

  ## Common Incorrect Authorization Patterns

  1. **Authorization after action** - Performing the operation before checking permissions
  2. **Client-side only authorization** - Relying on UI to hide options
  3. **Role check without resource check** - Checking role but not resource ownership
  4. **Negated logic flaws** - Using complex negation that can be bypassed
  5. **Default allow** - Allowing access unless explicitly denied

  ## Cross-Language Applicability

  Incorrect authorization affects all languages and frameworks.

  ## Detection Strategy

  Detects patterns where:
  1. Authorization check appears after sensitive operation
  2. Authorization uses only role check without resource verification
  3. Complex boolean logic that might have flaws
  4. Default-allow patterns instead of default-deny
  """

  @behaviour Metastatic.Analysis.Analyzer

  alias Metastatic.Analysis.Analyzer

  @sensitive_operations ~w[
    delete update insert create
    destroy save remove modify
    write transfer send execute
  ]

  @authorization_functions ~w[
    authorize can? permit? allowed?
    has_permission check_access verify_access
    authorize! policy
  ]

  @impl true
  def info do
    %{
      name: :incorrect_authorization,
      category: :security,
      description: "Detects incorrect authorization patterns (CWE-863)",
      severity: :warning,
      explanation: """
      Incorrect authorization occurs when authorization logic is flawed, even if present.
      Common issues include:
      - Checking authorization after performing the action
      - Using only role checks without resource ownership verification
      - Complex boolean logic with flaws
      - Default-allow instead of default-deny patterns

      Best practices:
      - Always authorize BEFORE performing operations
      - Check both role AND resource ownership
      - Use simple, clear authorization logic
      - Default to deny, explicitly allow
      """,
      configurable: true
    }
  end

  @impl true
  # Detect authorization after sensitive operation (wrong order)
  def analyze({:block, _meta, statements} = _node, context) when is_list(statements) do
    issues = check_authorization_order(statements, context)

    if Enum.any?(issues) do
      issues
    else
      []
    end
  end

  # Detect role-only checks without resource verification
  def analyze({:conditional, _meta, [condition | _branches]} = node, context) do
    if is_role_only_check?(condition) and in_sensitive_context?(context) do
      [
        Analyzer.issue(
          analyzer: __MODULE__,
          category: :security,
          severity: :warning,
          message:
            "Potential incorrect authorization: role-only check without resource ownership verification",
          node: node,
          metadata: %{
            cwe: 863,
            suggestion: "Add resource ownership check in addition to role check"
          }
        )
      ]
    else
      []
    end
  end

  def analyze(_node, _context), do: []

  # ----- Private Helpers -----

  defp check_authorization_order(statements, _context) do
    {issues, _state} =
      Enum.reduce(statements, {[], %{auth_seen: false, op_seen: false}}, fn stmt,
                                                                            {issues, state} ->
        cond do
          # Sensitive operation seen
          is_sensitive_operation?(stmt) and not state.auth_seen ->
            # Operation before auth - might be a problem
            {issues, %{state | op_seen: true}}

          # Authorization check seen
          is_authorization_check?(stmt) ->
            if state.op_seen do
              # Auth after operation - this is wrong!
              issue =
                Analyzer.issue(
                  analyzer: __MODULE__,
                  category: :security,
                  severity: :warning,
                  message:
                    "Incorrect authorization: authorization check appears AFTER sensitive operation",
                  node: stmt,
                  metadata: %{
                    cwe: 863,
                    suggestion: "Move authorization check BEFORE the sensitive operation"
                  }
                )

              {[issue | issues], %{state | auth_seen: true}}
            else
              {issues, %{state | auth_seen: true}}
            end

          true ->
            {issues, state}
        end
      end)

    issues
  end

  defp is_sensitive_operation?(node) do
    case node do
      {:function_call, meta, _args} when is_list(meta) ->
        func_name = Keyword.get(meta, :name, "")
        func_lower = String.downcase(func_name)
        Enum.any?(@sensitive_operations, &String.contains?(func_lower, &1))

      {:pipe, _meta, stages} when is_list(stages) ->
        Enum.any?(stages, &is_sensitive_operation?/1)

      _ ->
        false
    end
  end

  defp is_authorization_check?(node) do
    case node do
      {:function_call, meta, _args} when is_list(meta) ->
        func_name = Keyword.get(meta, :name, "")
        func_lower = String.downcase(func_name)
        Enum.any?(@authorization_functions, &String.contains?(func_lower, &1))

      {:conditional, _meta, [condition | _]} ->
        involves_authorization?(condition)

      _ ->
        false
    end
  end

  defp involves_authorization?(node) do
    case node do
      {:function_call, meta, _args} when is_list(meta) ->
        func_name = Keyword.get(meta, :name, "")
        func_lower = String.downcase(func_name)
        Enum.any?(@authorization_functions, &String.contains?(func_lower, &1))

      {:binary_op, _meta, [left, right]} ->
        involves_authorization?(left) or involves_authorization?(right)

      {:variable, _meta, name} when is_binary(name) ->
        name_lower = String.downcase(name)
        String.contains?(name_lower, "auth") or String.contains?(name_lower, "permission")

      _ ->
        false
    end
  end

  defp is_role_only_check?(condition) do
    has_role_check?(condition) and not has_resource_check?(condition)
  end

  defp has_role_check?(node) do
    case node do
      {:function_call, meta, _args} when is_list(meta) ->
        func_name = Keyword.get(meta, :name, "")
        func_lower = String.downcase(func_name)

        String.contains?(func_lower, "role") or
          String.contains?(func_lower, "admin") or
          String.contains?(func_lower, "is_")

      {:binary_op, _meta, [left, right]} ->
        has_role_check?(left) or has_role_check?(right)

      {:attribute_access, _meta, children} when is_list(children) ->
        Enum.any?(children, fn
          {:literal, _, attr} when is_binary(attr) or is_atom(attr) ->
            attr_lower = to_string(attr) |> String.downcase()
            String.contains?(attr_lower, "role") or String.contains?(attr_lower, "admin")

          _ ->
            false
        end)

      _ ->
        false
    end
  end

  defp has_resource_check?(node) do
    case node do
      {:binary_op, meta, [left, right]} when is_list(meta) ->
        operator = Keyword.get(meta, :operator)

        if operator in [:==, :===] do
          involves_resource_ownership?(left) or involves_resource_ownership?(right)
        else
          has_resource_check?(left) or has_resource_check?(right)
        end

      {:function_call, meta, _args} when is_list(meta) ->
        func_name = Keyword.get(meta, :name, "")
        func_lower = String.downcase(func_name)

        String.contains?(func_lower, "owner") or
          String.contains?(func_lower, "belongs") or
          String.contains?(func_lower, "policy")

      _ ->
        false
    end
  end

  defp involves_resource_ownership?(node) do
    case node do
      {:attribute_access, _meta, children} when is_list(children) ->
        Enum.any?(children, fn
          {:literal, _, attr} when is_binary(attr) or is_atom(attr) ->
            attr_lower = to_string(attr) |> String.downcase()
            String.contains?(attr_lower, "user_id") or String.contains?(attr_lower, "owner")

          _ ->
            false
        end)

      _ ->
        false
    end
  end

  defp in_sensitive_context?(context) do
    func_name = Map.get(context, :function_name, "")
    func_lower = String.downcase(func_name)
    Enum.any?(@sensitive_operations, &String.contains?(func_lower, &1))
  end
end
