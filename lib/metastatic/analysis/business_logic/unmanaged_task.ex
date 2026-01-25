defmodule Metastatic.Analysis.BusinessLogic.UnmanagedTask do
  @moduledoc """
  Detects unsupervised async operations that can cause memory leaks.

  This analyzer identifies spawning of async tasks/threads without proper
  supervision or error handling - a common concurrency anti-pattern.

  ## Cross-Language Applicability

  This is a **universal concurrency anti-pattern** across all async/concurrent systems:

  - **Python/asyncio**: `asyncio.create_task()` without task group
  - **Python/threading**: `Thread(target=fn).start()` without join
  - **JavaScript**: `new Promise()` without `.catch()`
  - **JavaScript/Node**: Promise without rejection handler
  - **Elixir**: `Task.async()` without `Task.Supervisor`
  - **Go**: `go func()` without wait group or context
  - **C#**: `Task.Run()` without continuation or error handling
  - **Java**: `CompletableFuture.runAsync()` without exception handling
  - **Rust**: `tokio::spawn()` without join handle management

  ## Problem

  Unmanaged async operations can:
  - **Leak memory** if tasks never complete
  - **Silently fail** without error propagation
  - **Cause race conditions** without synchronization
  - **Leave orphaned processes** after parent exits
  - **Exhaust resources** (threads, file handles, connections)

  ## Examples

  ### Bad (Python)

      async def handler():
          asyncio.create_task(background_work())  # Fire and forget!
          # Task may fail silently, no cleanup

  ### Good (Python)

      async def handler():
          async with asyncio.TaskGroup() as tg:
              tg.create_task(background_work())
          # Tasks are supervised, errors propagate

  ### Bad (JavaScript)

      function handler() {
          new Promise(async (resolve) => {
              await riskyWork();  // No error handling!
          });
      }

  ### Good (JavaScript)

      function handler() {
          Promise.resolve()
              .then(() => riskyWork())
              .catch(handleError);
      }

  ### Bad (Elixir)

      def handle_event(event) do
        Task.async(fn -> process(event) end)  # Unmanaged!
      end

  ### Good (Elixir)

      def handle_event(event) do
        Task.Supervisor.async_nolink(MySupervisor, fn ->
          process(event)
        end)
      end

  ### Bad (Go)

      func handler() {
          go riskyWork()  // No wait, no error handling
      }

  ### Good (Go)

      func handler(ctx context.Context) {
          var wg sync.WaitGroup
          wg.Add(1)
          go func() {
              defer wg.Done()
              riskyWork(ctx)
          }()
          wg.Wait()
      }

  ### Bad (C#)

      void Handler() {
          Task.Run(() => RiskyWork());  // Fire and forget
      }

  ### Good (C#)

      async Task Handler() {
          await Task.Run(() => RiskyWork())
              .ContinueWith(t => HandleError(t.Exception));
      }

  ## Detection Strategy

  Detects MetaAST pattern:

      {:async_operation, :spawn, lambda}

  Or function calls matching async spawn patterns:
  - `Task.async`, `asyncio.create_task`, `Promise.resolve`
  - `go func()`, `Task.Run`, `spawn`

  Without subsequent supervision/await/join in same scope.

  ## Limitations

  - Cannot detect if supervision exists in parent scope
  - Heuristic-based: may have false positives
  - Difficult to detect await in different block
  """

  @behaviour Metastatic.Analysis.Analyzer

  alias Metastatic.Analysis.Analyzer

  # Common async spawn function names across languages
  @async_spawn_keywords [
    # Elixir
    :async,
    :start,
    :start_link,
    # Python
    :create_task,
    :run_in_executor,
    # JavaScript
    :Promise,
    # Go (would be in function name)
    :go,
    # C#/.NET
    :Run,
    :Start,
    # Rust
    :spawn,
    # Java
    :runAsync,
    :supplyAsync
  ]

  @impl true
  def info do
    %{
      name: :unmanaged_task,
      category: :correctness,
      description: "Detects unsupervised async operations that can leak resources",
      severity: :warning,
      explanation: """
      Spawning async operations without supervision can lead to memory leaks,
      silent failures, and resource exhaustion. Always use:

      - Supervised task spawning (task groups, supervisors)
      - Proper error handling (try/catch, error callbacks)
      - Resource cleanup (join, await, cancel)
      - Structured concurrency patterns

      This applies to all concurrent/async programming across languages.
      """,
      configurable: false
    }
  end

  @impl true
  def analyze({:async_operation, :spawn, _lambda} = node, _context) do
    # Direct async operation in MetaAST
    [
      Analyzer.issue(
        analyzer: __MODULE__,
        category: :correctness,
        severity: :warning,
        message: "Unsupervised async operation - use supervised spawning to prevent leaks",
        node: node,
        metadata: %{
          suggestion: "Use task supervisor/group (TaskSupervisor, TaskGroup, Promise.all, etc.)"
        }
      )
    ]
  end

  def analyze({:function_call, func_name, _args} = node, _context) when is_atom(func_name) do
    if is_async_spawn?(func_name) do
      [
        Analyzer.issue(
          analyzer: __MODULE__,
          category: :correctness,
          severity: :warning,
          message:
            "Unsupervised async operation '#{func_name}' - use supervised spawning to prevent leaks",
          node: node,
          metadata: %{
            function: func_name,
            suggestion: "Use supervised task spawning (TaskSupervisor, asyncio.TaskGroup, etc.)"
          }
        )
      ]
    else
      []
    end
  end

  def analyze(_node, _context), do: []

  # ----- Private Helpers -----

  # Check if function name suggests async spawning
  defp is_async_spawn?(func_name) when is_atom(func_name) do
    # Direct match
    if func_name in @async_spawn_keywords do
      true
    else
      # Pattern match
      func_str = Atom.to_string(func_name) |> String.downcase()

      # Check for common async spawn patterns
      (String.contains?(func_str, "task") and
         (String.contains?(func_str, "async") or String.contains?(func_str, "start"))) or
        String.contains?(func_str, "spawn") or
        String.contains?(func_str, "create_task") or
        String.contains?(func_str, "promise")
    end
  end

  defp is_async_spawn?(_), do: false
end
