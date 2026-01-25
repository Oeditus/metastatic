defmodule Metastatic.Analysis.BusinessLogic.SyncOverAsync do
  @moduledoc """
  Detects blocking synchronous operations used where async alternatives exist.

  Universal pattern: synchronous HTTP/network calls in contexts where async is available.

  ## Examples

  **Python (blocking httpx in async function):**
  ```python
  async def fetch_data():
      response = httpx.get("https://api.example.com")  # Should use await httpx.AsyncClient
      return response.json()
  ```

  **JavaScript (sync fs in async context):**
  ```javascript
  async function processFile() {
      const data = fs.readFileSync('file.txt');  // Should use fs.promises.readFile
      return data;
  }
  ```

  **Elixir (sync HTTP in async GenServer):**
  ```elixir
  def handle_cast(:fetch, state) do
      {:ok, response} = HTTPoison.get(url)  # Should use Task.async or async library
      {:noreply, response}
  end
  ```

  **C# (sync in async method):**
  ```csharp
  async Task<string> GetDataAsync() {
      var client = new WebClient();
      return client.DownloadString(url);  // Should use DownloadStringTaskAsync
  }
  ```

  **Go (blocking I/O in goroutine):**
  ```go
  go func() {
      resp, _ := http.Get(url)  // Consider using context.Context for cancellation
      processResponse(resp)
  }()
  ```

  **Ruby (sync in async Fiber):**
  ```ruby
  Fiber.new do
      response = Net::HTTP.get(uri)  # Should use async HTTP library
      process(response)
  end.resume
  ```
  """

  @behaviour Metastatic.Analysis.Analyzer
  alias Metastatic.Analysis.Analyzer

  @blocking_functions ~w[
    get post put delete patch request
    fetch download upload
    read write open close
    query execute transaction
    sleep wait block
  ]

  @impl true
  def info do
    %{
      name: :sync_over_async,
      category: :performance,
      description: "Detects blocking calls where async alternatives exist",
      severity: :warning,
      explanation: "Use async operations to avoid blocking event loops/processes",
      configurable: true
    }
  end

  @impl true
  def analyze({:function_call, fn_name, _args} = node, context)
      when is_binary(fn_name) do
    fn_lower = String.downcase(fn_name)

    if String.contains?(fn_lower, @blocking_functions) and in_async_context?(context) do
      [
        Analyzer.issue(
          analyzer: __MODULE__,
          category: :performance,
          severity: :warning,
          message:
            "Synchronous '#{fn_name}' call in async context - consider using async alternative",
          node: node,
          metadata: %{
            function: fn_name,
            context: "async",
            suggestion: "Use async/await or non-blocking alternative"
          }
        )
      ]
    else
      []
    end
  end

  def analyze(_node, _context), do: []

  # Check if we're in an async context (heuristic-based)
  defp in_async_context?(context) do
    context
    |> Map.get(:function_name, "")
    |> String.downcase()
    |> String.contains?(["async", "handle_", "cast", "call", "task", "fiber", "goroutine"])
  end
end
