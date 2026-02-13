defmodule Metastatic.Analysis.BusinessLogic.MissingThrottle do
  @moduledoc """
  Detects expensive operations without rate limiting or throttling.

  Universal pattern: resource-intensive endpoints without rate limits.

  ## Examples

  **Python (Flask API without rate limiting):**
  ```python
  @app.route('/api/search', methods=['POST'])
  def search():  # Should add rate limiter decorator
      results = expensive_search(request.json['query'])
      return jsonify(results)
  ```

  **JavaScript (Express API without rate limit):**
  ```javascript
  app.post('/api/search', async (req, res) => {  # Should use express-rate-limit
      const results = await expensiveSearch(req.body.query);
      res.json(results);
  });
  ```

  **Elixir (Phoenix action without rate limiting):**
  ```elixir
  def create(conn, params) do  # Should add Plug.RateLimit or similar
      result = expensive_operation(params)
      json(conn, result)
  end
  ```

  **C# (ASP.NET endpoint without throttling):**
  ```csharp
  [HttpPost(\"api/search\")]
  public IActionResult Search([FromBody] SearchRequest req) {  # Should add [RateLimit] attribute
      var results = ExpensiveSearch(req.Query);
      return Ok(results);
  }
  ```

  **Go (HTTP handler without rate limiting):**
  ```go
  func searchHandler(w http.ResponseWriter, r *http.Request) {  # Should use rate.Limiter
      results := expensiveSearch(r.Body)
      json.NewEncoder(w).Encode(results)
  }
  ```

  **Java (Spring endpoint without rate limit):**
  ```java
  @PostMapping(\"/api/search\")
  public ResponseEntity search(@RequestBody SearchRequest req) {  # Should add Bucket4j or similar
      List results = expensiveSearch(req.getQuery());
      return ResponseEntity.ok(results);
  }
  ```

  **Ruby (Rails action without throttling):**
  ```ruby
  def create  # Should use rack-attack or similar
      results = expensive_search(params[:query])
      render json: results
  end
  ```

  **Python (FastAPI without rate limit):**
  ```python
  @app.post(\"/api/search\")
  async def search(request: SearchRequest):  # Should use slowapi
      results = await expensive_search(request.query)
      return results
  ```
  """

  @behaviour Metastatic.Analysis.Analyzer
  alias Metastatic.Analysis.Analyzer

  # Expanded expensive operations for better CWE-770 coverage
  @expensive_operations ~w[
    search query aggregate calculate compute
    export import generate process batch
    upload download convert transform transcode
    analyze scan crawl index reindex
    report render pdf email send
    sync synchronize migrate backup
    encrypt decrypt hash compress decompress
    resize thumbnail watermark
    train predict inference model
    bulk mass all fetch_all
  ]

  # Rate limiting indicators across frameworks
  @rate_limit_indicators ~w[
    ratelimit rate_limit throttle limiter bucket
    quota limit_rate slowapi rate_limiter
    Hammer ExRated PlugAttack Rihanna
    express-rate-limit ratelimiter redis-rate-limiter
    Bucket4j RateLimiter Guava
    leaky_bucket token_bucket sliding_window
    max_requests per_second per_minute
  ]

  # API endpoint patterns
  @api_endpoints ~w[
    post put patch delete create update
    route endpoint handler action
    api controller resource
    webhook callback trigger
    graphql mutation
  ]

  # Resource-intensive patterns that should always have limits
  # @high_risk_operations ~w[
  #   send_email send_sms notify broadcast
  #   external_api third_party payment
  #   file_upload video_upload media
  #   database_dump full_export
  #   password_reset login register signup
  # ]

  @impl true
  def info do
    %{
      name: :missing_throttle,
      category: :security,
      description: "Detects expensive operations without rate limiting",
      severity: :warning,
      explanation: "Resource-intensive endpoints should have rate limiting to prevent abuse/DoS",
      configurable: true
    }
  end

  @impl true
  def analyze({:function_call, fn_name, _args} = node, context)
      when is_binary(fn_name) do
    fn_lower = String.downcase(fn_name)

    if in_api_endpoint_context?(context) and
         String.contains?(fn_lower, @expensive_operations) and
         not has_rate_limiting?(context) do
      [
        Analyzer.issue(
          analyzer: __MODULE__,
          category: :security,
          severity: :warning,
          message:
            "Expensive operation '#{fn_name}' in API endpoint without rate limiting - DoS risk",
          node: node,
          metadata: %{
            operation: fn_name,
            context: "api_endpoint",
            suggestion: "Add rate limiting middleware/decorator to prevent abuse"
          }
        )
      ]
    else
      []
    end
  end

  def analyze(_node, _context), do: []

  defp in_api_endpoint_context?(context) do
    fn_name = Map.get(context, :function_name, "")
    module_name = Map.get(context, :module_name, "")

    [fn_name, module_name]
    |> Enum.map(&String.downcase/1)
    |> Enum.any?(&String.contains?(&1, @api_endpoints))
  end

  defp has_rate_limiting?(context) do
    decorators = Map.get(context, :decorators, [])
    middleware = Map.get(context, :middleware, [])

    [decorators, middleware]
    |> List.flatten()
    |> Enum.map(&String.downcase/1)
    |> Enum.any?(&String.contains?(&1, @rate_limit_indicators))
  end
end
