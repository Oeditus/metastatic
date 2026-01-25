defmodule Metastatic.Analysis.BusinessLogic.MissingTelemetryInLiveviewMount do
  @moduledoc """
  Detects component initialization/mounting without telemetry.

  Universal pattern: component lifecycle hooks without performance monitoring.

  ## Examples

  **Python (React component mount without tracking):**
  ```python
  class UserDashboard(Component):
      def componentDidMount(self):  # Should track mount time
          self.load_user_data()
  ```

  **JavaScript (React mount without telemetry):**
  ```javascript
  useEffect(() => {
      loadUserData();  # Should track component mount performance
  }, []);
  ```

  **Elixir (LiveView mount without telemetry):**
  ```elixir
  def mount(_params, _session, socket) do
      user = load_user()  # Should emit mount telemetry
      {:ok, assign(socket, user: user)}
  end
  ```

  **C# (Blazor OnInitialized without tracking):**
  ```csharp
  protected override async Task OnInitializedAsync() {
      User = await LoadUserAsync();  # Should track initialization time
  }
  ```

  **JavaScript (Vue mounted without metrics):**
  ```javascript
  mounted() {
      this.loadUserData();  # Should emit mount event
  }
  ```

  **JavaScript (Angular ngOnInit without tracking):**
  ```javascript
  ngOnInit() {
      this.loadUserData();  # Should track initialization
  }
  ```

  **Python (Django view without metrics):**
  ```python
  def get(self, request):
      context = self.get_context_data()  # Should track view rendering time
      return render(request, template, context)
  ```
  """

  @behaviour Metastatic.Analysis.Analyzer
  alias Metastatic.Analysis.Analyzer

  @lifecycle_indicators ~w[
    mount componentdidmount oninit oninitialize
    mounted created setup ngOnInit
    get post render load initialize
  ]

  @telemetry_indicators ~w[
    telemetry emit log trace metric record measure
  ]

  @impl true
  def info do
    %{
      name: :missing_telemetry_in_liveview_mount,
      category: :observability,
      description: "Detects component mounting/initialization without telemetry",
      severity: :info,
      explanation: "Component lifecycle events should be tracked for performance monitoring",
      configurable: true
    }
  end

  @impl true
  def analyze(node, context) do
    if in_lifecycle_context?(context) and not has_telemetry?(node) do
      [
        Analyzer.issue(
          analyzer: __MODULE__,
          category: :observability,
          severity: :info,
          message: "Component lifecycle method without telemetry - add performance tracking",
          node: node,
          metadata: %{
            context: "component_lifecycle",
            suggestion: "Emit telemetry for mount/init time and data loading"
          }
        )
      ]
    else
      []
    end
  end

  defp in_lifecycle_context?(context) do
    fn_name = Map.get(context, :function_name, "")

    String.downcase(fn_name) |> String.contains?(@lifecycle_indicators)
  end

  defp has_telemetry?({:function_call, fn_name, _args}) when is_binary(fn_name) do
    String.downcase(fn_name) |> String.contains?(@telemetry_indicators)
  end

  defp has_telemetry?({:block, statements}) when is_list(statements) do
    Enum.any?(statements, &has_telemetry?/1)
  end

  defp has_telemetry?(_), do: false
end
