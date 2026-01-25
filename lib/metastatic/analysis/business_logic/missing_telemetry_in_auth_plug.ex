defmodule Metastatic.Analysis.BusinessLogic.MissingTelemetryInAuthPlug do
  @moduledoc """
  Detects authentication/authorization code without telemetry.

  Universal pattern: auth checks without audit logging or metrics.

  ## Examples

  **Python (Django auth without logging):**
  ```python
  def check_permission(request, required_role):
      if request.user.role != required_role:  # Should log auth failures
          raise PermissionDenied()
  ```

  **JavaScript (Express auth without metrics):**
  ```javascript
  function authMiddleware(req, res, next) {
      if (!req.headers.authorization) {  # Should emit auth failure metric
          return res.status(401).send('Unauthorized');
      }
      next();
  }
  ```

  **Elixir (Plug auth without telemetry):**
  ```elixir
  def authenticate(conn, _opts) do
      case verify_token(conn) do
          {:error, _} -> send_resp(conn, 401, "Unauthorized")  # Should emit telemetry
          {:ok, user} -> assign(conn, :user, user)
      end
  end
  ```

  **C# (ASP.NET auth without logging):**
  ```csharp
  public override void OnAuthorization(AuthorizationContext context) {
      if (!context.HttpContext.User.Identity.IsAuthenticated) {  # Should log
          context.Result = new UnauthorizedResult();
      }
  }
  ```

  **Go (auth check without tracing):**
  ```go
  func requireAuth(next http.Handler) http.Handler {
      return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
          if !isAuthenticated(r) {  # Should emit auth failure event
              http.Error(w, "Unauthorized", 401)
              return
          }
          next.ServeHTTP(w, r)
      })
  }
  ```

  **Java (Spring Security without audit):**
  ```java
  public class CustomAuthFilter extends OncePerRequestFilter {
      protected void doFilterInternal(HttpServletRequest request) {
          if (!hasValidToken(request)) {  # Should audit auth failures
              response.sendError(HttpServletResponse.SC_UNAUTHORIZED);
          }
      }
  }
  ```

  **Ruby (devise auth without logging):**
  ```ruby
  before_action :authenticate_user!

  def authenticate_user!
      unless signed_in?  # Should log authentication attempts
          redirect_to login_path
      end
  end
  ```
  """

  @behaviour Metastatic.Analysis.Analyzer
  alias Metastatic.Analysis.Analyzer

  @auth_indicators ~w[
    auth authenticate authorize permission
    verify check validate token session
    login logout sign_in sign_out
    require_auth require_permission
  ]

  @telemetry_indicators ~w[
    telemetry emit log audit trace metric record
  ]

  @impl true
  def info do
    %{
      name: :missing_telemetry_in_auth_plug,
      category: :security,
      description: "Detects authentication code without telemetry/audit logging",
      severity: :warning,
      explanation: "Auth operations should be logged for security auditing and compliance",
      configurable: true
    }
  end

  @impl true
  def analyze({:conditional, _condition, then_branch, else_branch} = node, context) do
    if in_auth_context?(context) and not has_telemetry_in_branches?(then_branch, else_branch) do
      [
        Analyzer.issue(
          analyzer: __MODULE__,
          category: :security,
          severity: :warning,
          message: "Authentication check without telemetry - add audit logging for security",
          node: node,
          metadata: %{
            context: "authentication",
            suggestion: "Emit telemetry/audit events for auth successes and failures"
          }
        )
      ]
    else
      []
    end
  end

  def analyze(_node, _context), do: []

  defp in_auth_context?(context) do
    fn_name = Map.get(context, :function_name, "")
    module_name = Map.get(context, :module_name, "")

    [fn_name, module_name]
    |> Enum.map(&String.downcase/1)
    |> Enum.any?(&String.contains?(&1, @auth_indicators))
  end

  defp has_telemetry_in_branches?(then_branch, else_branch) do
    has_telemetry_call?(then_branch) or has_telemetry_call?(else_branch)
  end

  defp has_telemetry_call?({:function_call, fn_name, _args}) when is_binary(fn_name) do
    String.downcase(fn_name) |> String.contains?(@telemetry_indicators)
  end

  defp has_telemetry_call?({:block, statements}) when is_list(statements) do
    Enum.any?(statements, &has_telemetry_call?/1)
  end

  defp has_telemetry_call?(_), do: false
end
