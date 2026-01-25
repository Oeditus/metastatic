defmodule Metastatic.Analysis.BusinessLogic.TelemetryInRecursiveFunction do
  @moduledoc """
  Detects telemetry/metrics emissions inside recursive functions.

  This analyzer identifies recursive functions that emit telemetry events or
  metrics on each iteration, causing metric spam and performance degradation.

  ## Cross-Language Applicability

  This is a **universal observability anti-pattern** across all languages:

  - **Python**: `metrics.emit()` in recursive function
  - **JavaScript**: `statsd.increment()` in recursive function
  - **Elixir**: `:telemetry.execute()` in recursive function
  - **Go**: `metrics.Inc()` in recursive function
  - **C#**: `meter.RecordValue()` in recursive function
  - **Java**: `meter.mark()` in recursive function
  - **Ruby**: `StatsD.increment` in recursive function

  ## Problem

  Emitting telemetry inside recursive functions causes:
  - **Metric spam**: N emissions for N iterations
  - **Performance degradation**: Telemetry overhead per recursion
  - **Misleading metrics**: Inflated counts
  - **Backend overload**: Too many metric events

  For recursive traversal of 10,000 nodes:
  - **Bad**: 10,000 telemetry events
  - **Good**: 1 telemetry event with aggregate data

  ## Examples

  ### Bad (Python)

      def process_tree(node):
          metrics.increment('tree.node')  # Emitted N times!
          if node.children:
              for child in node.children:
                  process_tree(child)

  ### Good (Python)

      def process_tree_wrapper(root):
          count = process_tree(root, 0)
          metrics.increment('tree.nodes', count)
          
      def process_tree(node, count):
          count += 1
          for child in node.children:
              count = process_tree(child, count)
          return count

  ### Bad (JavaScript)

      function fibonacci(n) {
          statsd.increment('fib.calls');  // Exponential spam!
          if (n <= 1) return n;
          return fibonacci(n-1) + fibonacci(n-2);
      }

  ### Good (JavaScript)

      function fibonacci(n) {
          const start = Date.now();
          const result = fib_internal(n);
          statsd.timing('fib.duration', Date.now() - start);
          return result;
      }
      
      function fib_internal(n) {
          if (n <= 1) return n;
          return fib_internal(n-1) + fib_internal(n-2);
      }

  ### Bad (Elixir)

      def traverse([head | tail]) do
        :telemetry.execute([:app, :item], %{})  # N times!
        process(head)
        traverse(tail)
      end
      def traverse([]), do: :ok

  ### Good (Elixir)

      def traverse(items) do
        :telemetry.span([:app, :traverse], %{count: length(items)}, fn ->
          {do_traverse(items), %{}}
        end)
      end
      
      defp do_traverse([head | tail]) do
        process(head)
        do_traverse(tail)
      end
      defp do_traverse([]), do: :ok

  ### Bad (Go)

      func process(node *Node) {
          metrics.Inc("nodes")  // Called N times
          if node.Left != nil {
              process(node.Left)
          }
          if node.Right != nil {
              process(node.Right)
          }
      }

  ### Good (Go)

      func processTree(root *Node) {
          count := processNode(root, 0)
          metrics.Add("nodes", float64(count))
      }
      
      func processNode(node *Node, count int) int {
          count++
          if node.Left != nil {
              count = processNode(node.Left, count)
          }
          if node.Right != nil {
              count = processNode(node.Right, count)
          }
          return count
      }

  ## Detection Strategy

  1. Identify recursive functions (functions that call themselves)
  2. Check if function body contains telemetry/metrics calls
  3. Flag if both conditions are met

  ### Telemetry Function Heuristics

  Function names suggesting telemetry/metrics:
  - `*telemetry*`, `*metric*`, `*statsd*`
  - `*emit*`, `*record*`, `*increment*`, `*gauge*`
  - `*.execute*`, `*.span*`, `*.timing*`

  ## Solution

  Wrap the recursive operation with telemetry at the top level:
  - Use telemetry spans for duration
  - Aggregate counts and emit once
  - Move instrumentation out of recursion

  ## Limitations

  - Requires structural recursion detection (function calling itself)
  - Cannot detect mutual recursion easily
  - May miss indirect telemetry calls
  """

  @behaviour Metastatic.Analysis.Analyzer

  alias Metastatic.Analysis.Analyzer

  # Common telemetry/metrics function keywords
  @telemetry_keywords [
    # Generic
    :telemetry,
    :metrics,
    :statsd,
    :emit,
    :record,
    :increment,
    :gauge,
    :timing,
    :histogram,
    :counter,
    # Elixir-specific
    :execute,
    :span,
    # Prometheus/OpenTelemetry
    :observe,
    :add,
    :inc,
    :mark
  ]

  @impl true
  def info do
    %{
      name: :telemetry_in_recursive_function,
      category: :performance,
      description: "Detects telemetry emissions inside recursive functions",
      severity: :warning,
      explanation: """
      Emitting telemetry or metrics inside recursive functions causes metric
      spam and performance issues. The telemetry overhead is multiplied by
      the recursion depth.

      Instead:
      - Wrap the entire recursive operation with telemetry at top level
      - Aggregate metrics and emit once
      - Use telemetry spans for duration measurement
      - Move instrumentation out of the recursive path

      This applies to all telemetry/metrics systems across all languages.
      """,
      configurable: false
    }
  end

  @impl true
  def run_before(context) do
    # Initialize tracking for functions we're analyzing
    {:ok, Map.put(context, :function_stack, [])}
  end

  @impl true
  def analyze({:function_def, name, _params, _return_type, _opts, body} = node, _context)
      when is_atom(name) do
    # Check if function is recursive and contains telemetry
    if recursive?(name, body) and contains_telemetry?(body) do
      [
        Analyzer.issue(
          analyzer: __MODULE__,
          category: :performance,
          severity: :warning,
          message:
            "Telemetry emitted in recursive function '#{name}' - wrap entire operation instead",
          node: node,
          metadata: %{
            function_name: name,
            suggestion:
              "Move telemetry outside recursion, use span at top level, or aggregate metrics"
          }
        )
      ]
    else
      []
    end
  end

  def analyze(_node, _context), do: []

  # ----- Private Helpers -----

  # Check if function calls itself (direct recursion)
  defp recursive?(func_name, body) do
    contains_call_to?(body, func_name)
  end

  # Check if AST contains call to specific function
  defp contains_call_to?({:block, statements}, target_name) when is_list(statements) do
    Enum.any?(statements, &contains_call_to?(&1, target_name))
  end

  defp contains_call_to?({:function_call, name, _args}, target_name)
       when is_atom(name) and is_atom(target_name) do
    name == target_name
  end

  defp contains_call_to?({:conditional, _cond, then_branch, else_branch}, target_name) do
    contains_call_to?(then_branch, target_name) or
      contains_call_to?(else_branch || {:block, []}, target_name)
  end

  defp contains_call_to?(tuple, target_name) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.any?(&contains_call_to?(&1, target_name))
  end

  defp contains_call_to?(list, target_name) when is_list(list) do
    Enum.any?(list, &contains_call_to?(&1, target_name))
  end

  defp contains_call_to?(_, _), do: false

  # Check if body contains telemetry calls
  defp contains_telemetry?({:block, statements}) when is_list(statements) do
    Enum.any?(statements, &contains_telemetry?/1)
  end

  defp contains_telemetry?({:function_call, func_name, _args}) when is_atom(func_name) do
    telemetry_function?(func_name)
  end

  defp contains_telemetry?({:attribute_access, _obj, method}) when is_atom(method) do
    telemetry_function?(method)
  end

  defp contains_telemetry?({:conditional, _cond, then_branch, else_branch}) do
    contains_telemetry?(then_branch) or contains_telemetry?(else_branch || {:block, []})
  end

  defp contains_telemetry?(tuple) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.any?(&contains_telemetry?/1)
  end

  defp contains_telemetry?(list) when is_list(list) do
    Enum.any?(list, &contains_telemetry?/1)
  end

  defp contains_telemetry?(_), do: false

  # Check if function name suggests telemetry/metrics
  defp telemetry_function?(func_name) when is_atom(func_name) do
    # Direct match
    if func_name in @telemetry_keywords do
      true
    else
      # Pattern match
      func_str = Atom.to_string(func_name) |> String.downcase()

      Enum.any?(
        [
          "telemetry",
          "metric",
          "statsd",
          "emit",
          "record",
          "increment",
          "gauge",
          "counter",
          "timing",
          "observe"
        ],
        &String.contains?(func_str, &1)
      )
    end
  end

  defp telemetry_function?(_), do: false
end
