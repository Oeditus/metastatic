defmodule Metastatic.Analysis.BusinessLogic.BlockingInPlug do
  @moduledoc """
  Detects blocking operations in request handling middleware.

  Universal pattern: synchronous I/O in HTTP request middleware/interceptors.

  ## Examples

  **Python (Django middleware with sync DB):**
  ```python
  class AuthMiddleware:
      def process_request(self, request):
          user = User.objects.get(id=request.user_id)  # Blocking DB query in middleware
          request.user = user
  ```

  **JavaScript (Express middleware with sync file I/O):**
  ```javascript
  app.use((req, res, next) => {
      const config = fs.readFileSync('config.json');  # Blocking file read
      req.config = JSON.parse(config);
      next();
  });
  ```

  **Elixir (Plug with blocking HTTP):**
  ```elixir
  def call(conn, _opts) do
      {:ok, response} = HTTPoison.get(verification_url)  # Blocking in plug pipeline
      assign(conn, :verified, verified?(response))
  end
  ```

  **C# (ASP.NET middleware with sync DB):**
  ```csharp
  public class AuthMiddleware {
      public void OnActionExecuting(ActionExecutingContext context) {
          var user = db.Users.Find(userId);  # Blocking DB in middleware
          context.HttpContext.Items[\"user\"] = user;
      }
  }
  ```

  **Go (HTTP middleware with blocking call):**
  ```go
  func authMiddleware(next http.Handler) http.Handler {
      return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
          user := getUser(r.Header.Get(\"Authorization\"))  # Should use context for cancellation
          next.ServeHTTP(w, r)
      })
  }
  ```

  **Java (Spring interceptor with sync I/O):**
  ```java
  public class AuthInterceptor extends HandlerInterceptorAdapter {
      public boolean preHandle(HttpServletRequest request) {
          User user = userRepository.findById(userId).get();  # Blocking DB query
          request.setAttribute(\"user\", user);
      }
  }
  ```

  **Ruby (Rack middleware with blocking Redis):**
  ```ruby
  class CacheMiddleware
      def call(env)
          cached = Redis.current.get(cache_key)  # Synchronous Redis call in middleware
          @app.call(env)
      end
  end
  ```
  """

  @behaviour Metastatic.Analysis.Analyzer
  alias Metastatic.Analysis.Analyzer

  @middleware_indicators ~w[
    middleware plug handler interceptor
    filter guard decorator before_action
    process_request prehandle
  ]

  @blocking_operations ~w[
    get post query find read write
    sleep wait block fetch load
  ]

  @impl true
  def info do
    %{
      name: :blocking_in_plug,
      category: :performance,
      description: "Detects blocking operations in request middleware",
      severity: :warning,
      explanation: "Middleware should avoid blocking I/O to maintain request throughput",
      configurable: true
    }
  end

  @impl true
  def analyze({:function_call, fn_name, _args} = node, context)
      when is_binary(fn_name) do
    fn_lower = String.downcase(fn_name)

    if in_middleware_context?(context) and
         String.contains?(fn_lower, @blocking_operations) do
      [
        Analyzer.issue(
          analyzer: __MODULE__,
          category: :performance,
          severity: :warning,
          message:
            "Blocking operation '#{fn_name}' in middleware - consider async alternative or caching",
          node: node,
          metadata: %{
            function: fn_name,
            context: "middleware",
            suggestion: "Use async I/O, caching, or move to background task"
          }
        )
      ]
    else
      []
    end
  end

  def analyze(_node, _context), do: []

  defp in_middleware_context?(context) do
    fn_name = Map.get(context, :function_name, "")
    module_name = Map.get(context, :module_name, "")

    [fn_name, module_name]
    |> Enum.map(&String.downcase/1)
    |> Enum.any?(&String.contains?(&1, @middleware_indicators))
  end
end
