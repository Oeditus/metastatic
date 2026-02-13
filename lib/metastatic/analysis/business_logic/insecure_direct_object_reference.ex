defmodule Metastatic.Analysis.BusinessLogic.InsecureDirectObjectReference do
  @moduledoc """
  Detects Insecure Direct Object Reference (IDOR) vulnerabilities (CWE-639).

  This analyzer identifies code patterns where user-supplied IDs are used to
  directly access resources without verifying ownership or authorization.

  ## Cross-Language Applicability

  IDOR is a **universal access control vulnerability**:

  - **Elixir**: `Repo.get!(Post, params["id"])` without ownership check
  - **Python**: `Post.objects.get(id=request.GET['id'])`
  - **JavaScript**: `Post.findById(req.params.id)`
  - **Ruby**: `Post.find(params[:id])`
  - **Java**: `postRepository.findById(request.getParameter("id"))`
  - **C#**: `_context.Posts.Find(id)`
  - **Go**: `db.First(&post, id)`

  ## Problem

  When resources are accessed directly by ID without authorization:
  - Users can access other users' data by guessing/incrementing IDs
  - Horizontal privilege escalation is trivial
  - Data theft and privacy violations

  ## Detection Strategy

  Detects patterns where:
  1. Resources are fetched by user-supplied ID
  2. No ownership check (resource.user_id == current_user.id) is apparent
  3. No authorization policy is applied
  """

  @behaviour Metastatic.Analysis.Analyzer

  alias Metastatic.Analysis.Analyzer

  @fetch_functions ~w[
    get get! get_by find find! find_by
    findById findByPk findOne first
    retrieve load fetch lookup
    Repo.get Repo.get! Repo.get_by
    objects.get objects.filter
  ]

  @ownership_indicators ~w[
    user_id owner_id created_by author_id
    belongs_to current_user owner
    where user: filter user
    scope user policy authorize
  ]

  @impl true
  def info do
    %{
      name: :insecure_direct_object_reference,
      category: :security,
      description:
        "Detects IDOR vulnerabilities - direct object access without ownership check (CWE-639)",
      severity: :warning,
      explanation: """
      Insecure Direct Object Reference (IDOR) occurs when user-supplied IDs are used
      to directly access resources without verifying the user owns or can access them.
      This allows attackers to:
      - Access other users' data by changing ID values
      - Modify or delete resources they don't own
      - Enumerate resources through sequential IDs

      Always verify authorization:
      - Check resource ownership (resource.user_id == current_user.id)
      - Use scoped queries (where(user_id: current_user.id))
      - Apply authorization policies before returning data
      """,
      configurable: true
    }
  end

  @impl true
  # Detect fetch operations with user-supplied IDs
  def analyze({:function_call, meta, args} = node, context) when is_list(meta) do
    func_name = Keyword.get(meta, :name, "")

    if is_fetch_function?(func_name) and has_user_supplied_id?(args) and
         not in_authorization_context?(context) do
      [
        Analyzer.issue(
          analyzer: __MODULE__,
          category: :security,
          severity: :warning,
          message: "Potential IDOR: '#{func_name}' with user-supplied ID without ownership check",
          node: node,
          metadata: %{
            cwe: 639,
            function: func_name,
            suggestion: "Add ownership check or use scoped query (where user_id: current_user.id)"
          }
        )
      ]
    else
      []
    end
  end

  def analyze(_node, _context), do: []

  # ----- Private Helpers -----

  defp is_fetch_function?(func_name) when is_binary(func_name) do
    func_lower = String.downcase(func_name)

    Enum.any?(@fetch_functions, fn pattern ->
      String.contains?(func_lower, String.downcase(pattern))
    end)
  end

  defp is_fetch_function?(_), do: false

  defp has_user_supplied_id?(args) when is_list(args) do
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

  defp has_user_supplied_id?(_), do: false

  defp in_authorization_context?(context) do
    parent_stack = Map.get(context, :parent_stack, [])
    Enum.any?(parent_stack, &has_ownership_check?/1)
  end

  defp has_ownership_check?(node) do
    case node do
      {:conditional, _meta, [condition | _]} ->
        involves_ownership?(condition)

      {:function_call, meta, _args} when is_list(meta) ->
        func_name = Keyword.get(meta, :name, "")
        func_lower = String.downcase(func_name)
        Enum.any?(@ownership_indicators, &String.contains?(func_lower, &1))

      {:binary_op, meta, [left, right]} when is_list(meta) ->
        operator = Keyword.get(meta, :operator)

        if operator in [:==, :===] do
          involves_ownership?(left) or involves_ownership?(right)
        else
          false
        end

      _ ->
        false
    end
  end

  defp involves_ownership?(node) do
    case node do
      {:attribute_access, _meta, children} when is_list(children) ->
        Enum.any?(children, fn
          {:literal, _, attr} when is_binary(attr) or is_atom(attr) ->
            attr_lower = to_string(attr) |> String.downcase()
            Enum.any?(@ownership_indicators, &String.contains?(attr_lower, &1))

          _ ->
            false
        end)

      {:variable, _meta, name} when is_binary(name) ->
        name_lower = String.downcase(name)
        Enum.any?(@ownership_indicators, &String.contains?(name_lower, &1))

      {:function_call, meta, _} when is_list(meta) ->
        func_name = Keyword.get(meta, :name, "")
        func_lower = String.downcase(func_name)
        Enum.any?(@ownership_indicators, &String.contains?(func_lower, &1))

      _ ->
        false
    end
  end
end
