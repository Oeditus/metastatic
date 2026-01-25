defmodule Metastatic.Analysis.BusinessLogic.MissingTelemetryForExternalHttp do
  @moduledoc """
  Detects external HTTP requests without telemetry instrumentation.

  This analyzer identifies HTTP client calls that lack telemetry/monitoring,
  making it difficult to track API latency, failure rates, and external
  service health.

  ## Cross-Language Applicability

  Universal pattern across all HTTP clients:

  - **Python**: `requests.get()`, `httpx.get()`, `urllib.request()`
  - **JavaScript**: `fetch()`, `axios.get()`, `http.request()`
  - **Elixir**: `HTTPoison.get()`, `Req.get()`, `Finch.request()`
  - **Go**: `http.Get()`, `client.Do()`
  - **C#**: `HttpClient.GetAsync()`, `WebRequest.Create()`
  - **Java**: `HttpClient.send()`, `RestTemplate.get()`
  - **Ruby**: `Net::HTTP.get()`, `RestClient.get()`
  - **Rust**: `reqwest::get()`, `hyper::Client`

  ## Examples

  ### Bad (Python)
      response = requests.get(api_url)  # No monitoring

  ### Good (Python)
      start = time.time()
      response = requests.get(api_url)
      metrics.timing('api.request', time.time() - start)

  ### Bad (JavaScript)
      const data = await fetch(apiUrl);  # No telemetry

  ### Good (JavaScript)
      const start = Date.now();
      const data = await fetch(apiUrl);
      metrics.timing('api.request', Date.now() - start);
  """

  @behaviour Metastatic.Analysis.Analyzer
  alias Metastatic.Analysis.Analyzer

  @http_keywords [:get, :post, :put, :patch, :delete, :request, :fetch, :send]

  @impl true
  def info do
    %{
      name: :missing_telemetry_for_external_http,
      category: :maintainability,
      description: "Detects HTTP requests without telemetry instrumentation",
      severity: :info,
      explanation: """
      External HTTP requests should be instrumented with telemetry to track:
      - API latency and performance
      - Failure rates and error patterns
      - External service health
      - Request volumes
      """,
      configurable: false
    }
  end

  @impl true
  def analyze({:function_call, func_name, _args} = node, _context) when is_atom(func_name) do
    if http_function?(func_name) do
      [
        Analyzer.issue(
          analyzer: __MODULE__,
          category: :maintainability,
          severity: :info,
          message: "HTTP request '#{func_name}' should be wrapped with telemetry",
          node: node,
          metadata: %{function: func_name}
        )
      ]
    else
      []
    end
  end

  def analyze(_node, _context), do: []

  defp http_function?(func_name) do
    func_name in @http_keywords or
      String.contains?(Atom.to_string(func_name), ["http", "fetch", "request"])
  end
end
