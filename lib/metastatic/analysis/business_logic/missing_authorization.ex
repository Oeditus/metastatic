defmodule Metastatic.Analysis.BusinessLogic.MissingAuthorization do
  @moduledoc """
  Detects sensitive operations without authorization checks (CWE-862).

  This analyzer identifies code patterns where data modification or access
  operations are performed without apparent authorization verification.

  ## Cross-Language Applicability

  Missing authorization is a **universal access control vulnerability**:

  - **Elixir/Phoenix**: `def delete(conn, %{"id" => id}), do: Repo.delete!(id)`
  - **Python/Django**: `def delete(request, id): Model.objects.get(id=id).delete()`
  - **JavaScript/Express**: `app.delete('/item/:id', (req, res) => Item.delete(req.params.id))`
  - **Ruby/Rails**: `def destroy; @item.destroy; end`
  - **Java/Spring**: `@DeleteMapping public void delete(@PathVariable id) { repo.deleteById(id); }`
  - **C#/ASP.NET**: `public IActionResult Delete(int id) => _repo.Delete(id);`
  - **Go**: `func DeleteHandler(w http.ResponseWriter, r *http.Request) { db.Delete(id) }`

  ## Problem

  When sensitive operations lack authorization checks:
  - Any authenticated user can modify any data
  - Horizontal privilege escalation is possible
  - Data integrity is compromised
  - Compliance requirements may be violated

  ## Detection Strategy

  Detects patterns where:
  1. CRUD operations (create, update, delete) are performed
  2. The function context doesn't show authorization checks
  3. User-supplied IDs are used directly without ownership verification

  ## Examples

  ### Bad (Elixir)

      def delete(conn, %{"id" => id}) do
        post = Repo.get!(Post, id)
        Repo.delete!(post)
        json(conn, %{status: "deleted"})
      end

  ### Good (Elixir)

      def delete(conn, %{"id" => id}) do
        user = conn.assigns.current_user
        post = Repo.get!(Post, id)

        if post.user_id == user.id or user.admin? do
          Repo.delete!(post)
          json(conn, %{status: "deleted"})
        else
          conn |> put_status(403) |> json(%{error: "Forbidden"})
        end
      end
  """

  @behaviour Metastatic.Analysis.Analyzer

  alias Metastatic.Analysis.Analyzer

  @sensitive_operations ~w[
    delete delete! remove destroy
    update update! save put patch
    create insert insert! new
    Repo.delete Repo.update Repo.insert
    .delete .update .save .destroy
    deleteById updateById removeById
    delete_all update_all
  ]

  @authorization_indicators ~w[
    authorize authorized? can? permit? allowed?
    authorize! check_permission has_permission?
    current_user conn.assigns user_id owner
    policy policies ability abilities
    admin? is_admin role roles
    forbidden 403 unauthorized 401
    Bodyguard Canada CanCan Pundit
  ]

  @action_names ~w[
    delete destroy remove update edit
    create new index show
  ]

  @impl true
  def info do
    %{
      name: :missing_authorization,
      category: :security,
      description: "Detects sensitive operations without authorization checks (CWE-862)",
      severity: :error,
      explanation: """
      Missing authorization occurs when sensitive operations (create, update, delete)
      are performed without verifying the user has permission. This allows:
      - Any user to modify or delete any resource
      - Horizontal privilege escalation attacks
      - Data tampering and integrity violations

      Always verify authorization before sensitive operations:
      - Check resource ownership (resource.user_id == current_user.id)
      - Use authorization libraries (Bodyguard, CanCan, etc.)
      - Implement policy-based access control
      """,
      configurable: true
    }
  end

  @impl true
  # Detect function definitions that contain sensitive operations without auth
  def analyze({:function_def, meta, body} = node, context) when is_list(meta) do
    func_name = Keyword.get(meta, :name, "")

    if is_sensitive_action?(func_name) do
      body_list = if is_list(body), do: body, else: [body]

      has_auth? = has_authorization_check?(body_list, context)
      has_sensitive_op? = has_sensitive_operation?(body_list)

      if has_sensitive_op? and not has_auth? do
        [
          Analyzer.issue(
            analyzer: __MODULE__,
            category: :security,
            severity: :error,
            message:
              "Missing authorization: sensitive operation in '#{func_name}' without auth check",
            node: node,
            metadata: %{
              cwe: 862,
              function: func_name,
              suggestion: "Add authorization check before performing sensitive operations"
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

  # Detect direct sensitive operations with user-supplied IDs
  def analyze({:function_call, meta, args} = node, context) when is_list(meta) do
    func_name = Keyword.get(meta, :name, "")

    if is_sensitive_function?(func_name) and
         has_user_supplied_id?(args, context) and
         not in_authorization_context?(context) do
      [
        Analyzer.issue(
          analyzer: __MODULE__,
          category: :security,
          severity: :warning,
          message: "Potential missing authorization: '#{func_name}' with user-supplied ID",
          node: node,
          metadata: %{
            cwe: 862,
            function: func_name,
            suggestion: "Verify user has permission to access/modify this resource"
          }
        )
      ]
    else
      []
    end
  end

  def analyze(_node, _context), do: []

  # ----- Private Helpers -----

  defp is_sensitive_action?(func_name) when is_binary(func_name) do
    func_lower = String.downcase(func_name)
    Enum.any?(@action_names, &String.contains?(func_lower, &1))
  end

  defp is_sensitive_action?(_), do: false

  defp is_sensitive_function?(func_name) when is_binary(func_name) do
    func_lower = String.downcase(func_name)

    Enum.any?(@sensitive_operations, fn op ->
      String.contains?(func_lower, String.downcase(op))
    end)
  end

  defp is_sensitive_function?(_), do: false

  defp has_authorization_check?(body, _context) when is_list(body) do
    Enum.any?(body, &contains_authorization?/1)
  end

  defp has_authorization_check?(body, context), do: has_authorization_check?([body], context)

  defp contains_authorization?(node) do
    case node do
      {:function_call, meta, _args} when is_list(meta) ->
        func_name = Keyword.get(meta, :name, "")
        is_auth_function?(func_name)

      {:conditional, _meta, [condition | _branches]} ->
        contains_authorization?(condition)

      {:binary_op, meta, [left, right]} when is_list(meta) ->
        operator = Keyword.get(meta, :operator)
        # Check for equality comparisons that might be auth checks
        if operator in [:==, :===, :!=, :!==] do
          involves_auth_variable?(left) or involves_auth_variable?(right)
        else
          contains_authorization?(left) or contains_authorization?(right)
        end

      {:attribute_access, _meta, children} when is_list(children) ->
        Enum.any?(children, &involves_auth_variable?/1)

      {:block, _meta, statements} when is_list(statements) ->
        Enum.any?(statements, &contains_authorization?/1)

      {:case, _meta, [_expr | arms]} ->
        Enum.any?(arms, &contains_authorization?/1)

      {:pipe, _meta, stages} when is_list(stages) ->
        Enum.any?(stages, &contains_authorization?/1)

      tuple when is_tuple(tuple) ->
        tuple |> Tuple.to_list() |> Enum.any?(&contains_authorization?/1)

      list when is_list(list) ->
        Enum.any?(list, &contains_authorization?/1)

      _ ->
        false
    end
  end

  defp is_auth_function?(func_name) when is_binary(func_name) do
    func_lower = String.downcase(func_name)

    Enum.any?(@authorization_indicators, fn ind ->
      String.contains?(func_lower, String.downcase(ind))
    end)
  end

  defp is_auth_function?(_), do: false

  defp involves_auth_variable?({:variable, _meta, name}) when is_binary(name) do
    name_lower = String.downcase(name)
    Enum.any?(["user", "owner", "admin", "role", "permission"], &String.contains?(name_lower, &1))
  end

  defp involves_auth_variable?({:attribute_access, _meta, children}) when is_list(children) do
    Enum.any?(children, fn
      {:literal, _, attr} when is_binary(attr) ->
        attr_lower = String.downcase(attr)
        String.contains?(attr_lower, "user") or String.contains?(attr_lower, "id")

      other ->
        involves_auth_variable?(other)
    end)
  end

  defp involves_auth_variable?(_), do: false

  defp has_sensitive_operation?(body) when is_list(body) do
    Enum.any?(body, &contains_sensitive_operation?/1)
  end

  defp contains_sensitive_operation?(node) do
    case node do
      {:function_call, meta, _args} when is_list(meta) ->
        func_name = Keyword.get(meta, :name, "")
        is_sensitive_function?(func_name)

      {:pipe, _meta, stages} when is_list(stages) ->
        Enum.any?(stages, &contains_sensitive_operation?/1)

      {:block, _meta, statements} when is_list(statements) ->
        Enum.any?(statements, &contains_sensitive_operation?/1)

      tuple when is_tuple(tuple) ->
        tuple |> Tuple.to_list() |> Enum.any?(&contains_sensitive_operation?/1)

      list when is_list(list) ->
        Enum.any?(list, &contains_sensitive_operation?/1)

      _ ->
        false
    end
  end

  defp has_user_supplied_id?(args, _context) when is_list(args) do
    Enum.any?(args, fn arg ->
      case arg do
        {:variable, _meta, name} when is_binary(name) ->
          name_lower = String.downcase(name)
          String.contains?(name_lower, "id") or String.contains?(name_lower, "param")

        {:map_access, _meta, _} ->
          true

        {:attribute_access, _meta, _} ->
          true

        _ ->
          false
      end
    end)
  end

  defp has_user_supplied_id?(_, _), do: false

  defp in_authorization_context?(context) do
    parent_stack = Map.get(context, :parent_stack, [])
    Enum.any?(parent_stack, &contains_authorization?/1)
  end
end
