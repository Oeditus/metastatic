defmodule Metastatic.Analysis.BusinessLogic.MissingAuthentication do
  @moduledoc """
  Detects critical functions without authentication checks (CWE-306).

  This analyzer identifies endpoints or functions that perform sensitive
  operations but lack apparent authentication verification.

  ## Cross-Language Applicability

  Missing authentication is a **universal access control vulnerability**:

  - **Elixir/Phoenix**: Controller action without `plug :authenticate`
  - **Python/Django**: View without `@login_required` decorator
  - **JavaScript/Express**: Route without auth middleware
  - **Ruby/Rails**: Controller without `before_action :authenticate_user!`
  - **Java/Spring**: Endpoint without `@PreAuthorize` or security config
  - **C#/ASP.NET**: Action without `[Authorize]` attribute
  - **Go**: Handler without auth middleware in chain

  ## Problem

  When critical functions lack authentication:
  - Anonymous users can access protected resources
  - Sensitive operations can be performed without identity verification
  - Data exposure to unauthorized parties
  - System integrity compromised

  ## Detection Strategy

  Detects patterns where:
  1. Functions named as critical actions (admin, delete, update, etc.)
  2. Functions in controller/handler modules
  3. No authentication check is apparent in the function or module context
  """

  @behaviour Metastatic.Analysis.Analyzer

  alias Metastatic.Analysis.Analyzer

  @critical_action_names ~w[
    admin dashboard settings config configuration
    delete destroy remove purge
    update modify edit patch
    create new insert
    export import backup restore
    password reset token api_key
    payment checkout billing subscription
    user users account accounts
  ]

  @authentication_indicators ~w[
    authenticate authenticated? ensure_authenticated
    login logged_in? current_user
    require_login require_auth session
    token bearer jwt oauth
    api_key authorized verify_token
    before_action plug guardian
    @login_required @authenticated @authorize
    PreAuthorize Secured RolesAllowed
  ]

  @impl true
  def info do
    %{
      name: :missing_authentication,
      category: :security,
      description: "Detects critical functions without authentication checks (CWE-306)",
      severity: :error,
      explanation: """
      Missing authentication occurs when sensitive operations can be performed
      without verifying the user's identity. This allows:
      - Anonymous access to protected functionality
      - Data exposure to unauthenticated users
      - Unauthorized operations

      Always require authentication for:
      - Admin/dashboard pages
      - Data modification operations
      - User account management
      - Payment/billing operations
      - Export/import functionality
      """,
      configurable: true
    }
  end

  @impl true
  # Detect function definitions for critical actions without auth
  def analyze({:function_def, meta, body} = node, context) when is_list(meta) do
    func_name = Keyword.get(meta, :name, "")

    if is_critical_action?(func_name) and in_handler_context?(context) do
      body_list = if is_list(body), do: body, else: [body]

      has_auth? = has_authentication_check?(body_list) or module_has_auth?(context)

      if not has_auth? do
        [
          Analyzer.issue(
            analyzer: __MODULE__,
            category: :security,
            severity: :error,
            message:
              "Missing authentication: critical function '#{func_name}' without auth check",
            node: node,
            metadata: %{
              cwe: 306,
              function: func_name,
              suggestion: "Add authentication plug/middleware/decorator to protect this endpoint"
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

  # Detect container (module/class) definitions for controllers without auth
  def analyze({:container, meta, body} = node, _context) when is_list(meta) do
    container_name = Keyword.get(meta, :name, "")

    if is_controller_module?(container_name) do
      body_list = if is_list(body), do: body, else: [body]

      has_module_auth? = has_module_level_auth?(body_list)
      has_critical_actions? = has_critical_action_functions?(body_list)

      if has_critical_actions? and not has_module_auth? do
        [
          Analyzer.issue(
            analyzer: __MODULE__,
            category: :security,
            severity: :warning,
            message:
              "Potential missing authentication: controller '#{container_name}' without module-level auth",
            node: node,
            metadata: %{
              cwe: 306,
              module: container_name,
              suggestion: "Add authentication plug/before_action at module level"
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

  def analyze(_node, _context), do: []

  # ----- Private Helpers -----

  defp is_critical_action?(func_name) when is_binary(func_name) do
    func_lower = String.downcase(func_name)
    Enum.any?(@critical_action_names, &String.contains?(func_lower, &1))
  end

  defp is_critical_action?(_), do: false

  defp is_controller_module?(name) when is_binary(name) do
    name_lower = String.downcase(name)

    String.contains?(name_lower, "controller") or
      String.contains?(name_lower, "handler") or
      String.contains?(name_lower, "api") or
      String.contains?(name_lower, "endpoint") or
      String.contains?(name_lower, "view")
  end

  defp is_controller_module?(_), do: false

  defp in_handler_context?(context) do
    module_name = Map.get(context, :module_name, "")
    is_controller_module?(module_name)
  end

  defp module_has_auth?(context) do
    module_plugs = Map.get(context, :module_plugs, [])
    module_decorators = Map.get(context, :decorators, [])

    Enum.any?(module_plugs ++ module_decorators, &is_auth_indicator?/1)
  end

  defp has_authentication_check?(body) when is_list(body) do
    Enum.any?(body, &contains_auth_check?/1)
  end

  defp contains_auth_check?(node) do
    case node do
      {:function_call, meta, _args} when is_list(meta) ->
        func_name = Keyword.get(meta, :name, "")
        is_auth_indicator?(func_name)

      {:conditional, _meta, [condition | _branches]} ->
        involves_auth?(condition)

      {:block, _meta, statements} when is_list(statements) ->
        Enum.any?(statements, &contains_auth_check?/1)

      {:pipe, _meta, stages} when is_list(stages) ->
        Enum.any?(stages, &contains_auth_check?/1)

      tuple when is_tuple(tuple) ->
        tuple |> Tuple.to_list() |> Enum.any?(&contains_auth_check?/1)

      list when is_list(list) ->
        Enum.any?(list, &contains_auth_check?/1)

      _ ->
        false
    end
  end

  defp is_auth_indicator?(name) when is_binary(name) do
    name_lower = String.downcase(name)

    Enum.any?(@authentication_indicators, fn ind ->
      String.contains?(name_lower, String.downcase(ind))
    end)
  end

  defp is_auth_indicator?(_), do: false

  defp involves_auth?(node) do
    case node do
      {:variable, _meta, name} when is_binary(name) ->
        name_lower = String.downcase(name)
        String.contains?(name_lower, "user") or String.contains?(name_lower, "auth")

      {:function_call, meta, _} when is_list(meta) ->
        func_name = Keyword.get(meta, :name, "")
        is_auth_indicator?(func_name)

      {:attribute_access, _meta, children} when is_list(children) ->
        Enum.any?(children, &involves_auth?/1)

      _ ->
        false
    end
  end

  defp has_module_level_auth?(body) when is_list(body) do
    Enum.any?(body, fn node ->
      case node do
        {:function_call, meta, _args} when is_list(meta) ->
          func_name = Keyword.get(meta, :name, "")
          # Check for plug :authenticate, before_action patterns
          func_lower = String.downcase(func_name)

          String.contains?(func_lower, "plug") or
            String.contains?(func_lower, "before_action") or
            String.contains?(func_lower, "use") or
            is_auth_indicator?(func_name)

        _ ->
          false
      end
    end)
  end

  defp has_critical_action_functions?(body) when is_list(body) do
    Enum.any?(body, fn node ->
      case node do
        {:function_def, meta, _} when is_list(meta) ->
          func_name = Keyword.get(meta, :name, "")
          is_critical_action?(func_name)

        _ ->
          false
      end
    end)
  end
end
