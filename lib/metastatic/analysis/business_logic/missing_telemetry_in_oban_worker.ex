defmodule Metastatic.Analysis.BusinessLogic.MissingTelemetryInObanWorker do
  @moduledoc """
  Detects background job processing without telemetry.

  Universal pattern: async job workers without metrics/monitoring.

  ## Examples

  **Python (Celery task without metrics):**
  ```python
  @celery.task
  def process_upload(file_id):  # Should emit task metrics
      file = File.objects.get(id=file_id)
      process_file(file)
  ```

  **JavaScript (Bull queue without telemetry):**
  ```javascript
  queue.process(async (job) => {  # Should track job processing time
      await processData(job.data);
  });
  ```

  **Elixir (Oban worker without telemetry):**
  ```elixir
  def perform(%Oban.Job{args: args}) do
      process_data(args)  # Should emit telemetry for job execution
      :ok
  end
  ```

  **C# (Hangfire job without logging):**
  ```csharp
  public void ProcessUpload(int fileId) {  # Should track job metrics
      var file = db.Files.Find(fileId);
      ProcessFile(file);
  }
  ```

  **Go (worker goroutine without metrics):**
  ```go
  func processJob(job Job) error {  # Should emit job metrics
      return processData(job.Data)
  }
  ```

  **Java (Quartz job without monitoring):**
  ```java
  public void execute(JobExecutionContext context) {  # Should track execution time
      processData(context.getMergedJobDataMap());
  }
  ```

  **Ruby (Sidekiq worker without telemetry):**
  ```ruby
  def perform(file_id)  # Should emit job metrics
      file = File.find(file_id)
      process_file(file)
  end
  ```

  **Python (RQ worker without tracking):**
  ```python
  @job
  def process_data(data_id):  # Should track job execution
      data = Data.objects.get(id=data_id)
      process(data)
  ```
  """

  @behaviour Metastatic.Analysis.Analyzer
  alias Metastatic.Analysis.Analyzer

  @job_indicators ~w[
    perform execute process run
    worker job task handler
    enqueue background async
  ]

  @telemetry_indicators ~w[
    telemetry emit log trace metric record measure monitor
  ]

  @impl true
  def info do
    %{
      name: :missing_telemetry_in_oban_worker,
      category: :observability,
      description: "Detects background job processing without telemetry",
      severity: :info,
      explanation: "Background jobs should emit metrics for monitoring and debugging",
      configurable: true
    }
  end

  @impl true
  def analyze(node, context) do
    if in_job_context?(context) and not has_telemetry?(node) do
      [
        Analyzer.issue(
          analyzer: __MODULE__,
          category: :observability,
          severity: :info,
          message: "Background job without telemetry - add metrics for job execution",
          node: node,
          metadata: %{
            context: "background_job",
            suggestion: "Emit telemetry for job start, completion, duration, and failures"
          }
        )
      ]
    else
      []
    end
  end

  defp in_job_context?(context) do
    fn_name = Map.get(context, :function_name, "")
    module_name = Map.get(context, :module_name, "")

    [fn_name, module_name]
    |> Enum.map(&String.downcase/1)
    |> Enum.any?(&String.contains?(&1, @job_indicators))
  end

  defp has_telemetry?({:function_call, fn_name, _args}) when is_binary(fn_name) do
    String.downcase(fn_name) |> String.contains?(@telemetry_indicators)
  end

  defp has_telemetry?({:block, statements}) when is_list(statements) do
    Enum.any?(statements, &has_telemetry?/1)
  end

  defp has_telemetry?(_), do: false
end
