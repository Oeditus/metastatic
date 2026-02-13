defmodule Metastatic.Analysis.BusinessLogic.MissingCSRFProtection do
  @moduledoc """
  Detects state-changing endpoints without CSRF protection (CWE-352).

  This analyzer identifies code patterns where state-changing HTTP operations
  (POST, PUT, PATCH, DELETE) are handled without CSRF token validation.

  ## Cross-Language Applicability

  CSRF is a **universal web vulnerability**:

  - **Elixir/Phoenix**: Route without `:protect_from_forgery` plug
  - **Python/Django**: View without `@csrf_protect` or middleware
  - **JavaScript/Express**: Route without `csurf` middleware
  - **Ruby/Rails**: Controller without `protect_from_forgery`
  - **Java/Spring**: Without Spring Security CSRF protection
  - **C#/ASP.NET**: Without `[ValidateAntiForgeryToken]`

  ## Problem

  Without CSRF protection:
  - Attackers can trick users into performing unwanted actions
  - State changes can be initiated from malicious sites
  - User accounts can be compromised through social engineering

  ## Detection Strategy

  Detects patterns where:
  1. Functions handle state-changing HTTP methods (POST, PUT, PATCH, DELETE)
  2. No CSRF token validation is apparent
  3. The operation modifies state (database, session, etc.)
  """

  @behaviour Metastatic.Analysis.Analyzer

  alias Metastatic.Analysis.Analyzer

  @state_changing_methods ~w[post put patch delete]

  @csrf_indicators ~w[
    csrf token protect_from_forgery
    verify_authenticity_token antiforgery
    ValidateAntiForgeryToken csurf
    csrf_protect csrf_token csrf_exempt
    x-csrf-token _csrf
  ]

  @state_changing_actions ~w[
    create update delete destroy
    save insert remove edit
    post put patch
  ]

  @impl true
  def info do
    %{
      name: :missing_csrf_protection,
      category: :security,
      description: "Detects state-changing endpoints without CSRF protection (CWE-352)",
      severity: :warning,
      explanation: """
      Cross-Site Request Forgery (CSRF) occurs when malicious websites trick users
      into performing unwanted actions on sites where they're authenticated.
      Without CSRF protection:
      - Attackers can make users unknowingly submit forms
      - Bank transfers, password changes can be triggered
      - Account settings can be modified

      Always use CSRF protection for state-changing operations:
      - Use framework CSRF middleware/plugs
      - Validate CSRF tokens on POST/PUT/PATCH/DELETE
      - Use SameSite cookie attributes
      """,
      configurable: true
    }
  end

  @impl true
  # Detect function definitions for state-changing actions without CSRF check
  def analyze({:function_def, meta, body} = node, context) when is_list(meta) do
    func_name = Keyword.get(meta, :name, "")

    if is_state_changing_action?(func_name) and in_web_context?(context) do
      body_list = if is_list(body), do: body, else: [body]

      has_csrf? = has_csrf_check?(body_list) or module_has_csrf?(context)

      if not has_csrf? do
        [
          Analyzer.issue(
            analyzer: __MODULE__,
            category: :security,
            severity: :warning,
            message: "Potential missing CSRF protection: state-changing action '#{func_name}'",
            node: node,
            metadata: %{
              cwe: 352,
              function: func_name,
              suggestion: "Add CSRF token validation via plug/middleware"
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

  # Detect route definitions without CSRF protection
  def analyze({:function_call, meta, _args} = node, context) when is_list(meta) do
    func_name = Keyword.get(meta, :name, "")
    func_lower = String.downcase(func_name)

    if func_lower in @state_changing_methods and not in_csrf_context?(context) do
      [
        Analyzer.issue(
          analyzer: __MODULE__,
          category: :security,
          severity: :warning,
          message: "Potential missing CSRF protection: #{String.upcase(func_name)} route handler",
          node: node,
          metadata: %{
            cwe: 352,
            method: func_name,
            suggestion: "Ensure CSRF middleware is applied to this route"
          }
        )
      ]
    else
      []
    end
  end

  def analyze(_node, _context), do: []

  # ----- Private Helpers -----

  defp is_state_changing_action?(func_name) when is_binary(func_name) do
    func_lower = String.downcase(func_name)
    Enum.any?(@state_changing_actions, &String.contains?(func_lower, &1))
  end

  defp is_state_changing_action?(_), do: false

  defp in_web_context?(context) do
    module_name = Map.get(context, :module_name, "")
    module_lower = String.downcase(module_name)

    String.contains?(module_lower, "controller") or
      String.contains?(module_lower, "handler") or
      String.contains?(module_lower, "view") or
      String.contains?(module_lower, "api")
  end

  defp module_has_csrf?(context) do
    module_plugs = Map.get(context, :module_plugs, [])
    module_middleware = Map.get(context, :middleware, [])

    Enum.any?(module_plugs ++ module_middleware, &is_csrf_indicator?/1)
  end

  defp has_csrf_check?(body) when is_list(body) do
    Enum.any?(body, &contains_csrf_check?/1)
  end

  defp contains_csrf_check?(node) do
    case node do
      {:function_call, meta, _args} when is_list(meta) ->
        func_name = Keyword.get(meta, :name, "")
        is_csrf_indicator?(func_name)

      {:block, _meta, statements} when is_list(statements) ->
        Enum.any?(statements, &contains_csrf_check?/1)

      tuple when is_tuple(tuple) ->
        tuple |> Tuple.to_list() |> Enum.any?(&contains_csrf_check?/1)

      list when is_list(list) ->
        Enum.any?(list, &contains_csrf_check?/1)

      _ ->
        false
    end
  end

  defp is_csrf_indicator?(name) when is_binary(name) do
    name_lower = String.downcase(name)

    Enum.any?(@csrf_indicators, fn ind ->
      String.contains?(name_lower, String.downcase(ind))
    end)
  end

  defp is_csrf_indicator?(_), do: false

  defp in_csrf_context?(context) do
    parent_stack = Map.get(context, :parent_stack, [])
    Enum.any?(parent_stack, &contains_csrf_check?/1) or module_has_csrf?(context)
  end
end
