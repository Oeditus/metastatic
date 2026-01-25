defmodule Metastatic.Analysis.BusinessLogic.MissingHandleAsync do
  @moduledoc """
  Detects missing async error handling (fire-and-forget without supervision).

  Universal pattern: spawning async tasks without monitoring results or errors.

  ## Examples

  **Python (asyncio without await):**
  ```python
  async def process():
      asyncio.create_task(heavy_work())  # Task created but never awaited - errors lost
      return "done"
  ```

  **JavaScript (Promise without catch):**
  ```javascript
  function processData() {
      fetchData();  // Returns Promise but not awaited/caught - errors swallowed
      return success;
  }
  ```

  **Elixir (Task.start without monitoring):**
  ```elixir
  def handle_cast(:process, state) do
      Task.start(fn -> heavy_work() end)  # Should use Task.Supervisor or Task.async + await
      {:noreply, state}
  end
  ```

  **C# (Task.Run fire-and-forget):**
  ```csharp
  void ProcessData() {
      Task.Run(() => HeavyWork());  // Should await or use ContinueWith
      return;
  }
  ```

  **Go (goroutine without sync):**
  ```go
  func process() {
      go heavyWork()  // No WaitGroup or channel - completion/errors unknown
      return
  }
  ```

  **Java (CompletableFuture without handling):**
  ```java
  void processData() {
      CompletableFuture.runAsync(() -> heavyWork());  // Should use get() or exceptionally()
      return;
  }
  ```

  **Ruby (Thread without join):**
  ```ruby
  def process
      Thread.new { heavy_work }  # Should join or use thread pool
      return
  end
  ```
  """

  @behaviour Metastatic.Analysis.Analyzer
  alias Metastatic.Analysis.Analyzer

  @async_spawn_functions ~w[
    create_task run_async start spawn
    task async future thread goroutine
    parallel background detached
  ]

  @impl true
  def info do
    %{
      name: :missing_handle_async,
      category: :reliability,
      description: "Detects unmonitored async operations",
      severity: :warning,
      explanation: "Async tasks should be supervised, awaited, or have error handlers",
      configurable: true
    }
  end

  @impl true
  def analyze({:function_call, fn_name, args} = node, context)
      when is_binary(fn_name) do
    fn_lower = String.downcase(fn_name)

    if String.contains?(fn_lower, @async_spawn_functions) and
         not has_error_handling?(args, context) do
      [
        Analyzer.issue(
          analyzer: __MODULE__,
          category: :reliability,
          severity: :warning,
          message:
            "Async operation '#{fn_name}' started without supervision/error handling - errors may be lost",
          node: node,
          metadata: %{
            function: fn_name,
            suggestion: "Use supervision, await result, or add error handling"
          }
        )
      ]
    else
      []
    end
  end

  def analyze(_node, _context), do: []

  # Heuristic: check if there's error handling nearby (simplified)
  defp has_error_handling?(_args, context) do
    # Check if we're in a try/catch block or have supervision
    Map.get(context, :in_exception_handling, false) or
      Map.get(context, :supervised, false)
  end
end
