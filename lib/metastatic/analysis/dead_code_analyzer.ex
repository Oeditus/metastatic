defmodule Metastatic.Analysis.DeadCodeAnalyzer do
  @moduledoc """
  Plugin analyzer wrapper for dead code detection.

  This module wraps the existing `Metastatic.Analysis.DeadCode` module as an
  `Analyzer` behaviour plugin for use with the Runner system. It detects:

  - **Unreachable code after returns** - Code following early_return nodes
  - **Constant conditionals** - Branches that can never execute (if true/false)
  - **Other dead patterns** - Unused assignments, etc.

  ## Usage

      alias Metastatic.{Document, Analysis.Runner}

      # Register as plugin
      Registry.register(DeadCodeAnalyzer)

      # Run via Runner
      {:ok, report} = Runner.run(doc)

  ## Configuration

  - `:min_confidence` - Minimum confidence to report (default: :low)
    - `:low` - Report all dead code
    - `:medium` - Report high-confidence issues only
    - `:high` - Report only definite dead code

  ## Examples

      # Unreachable after return
      iex> ast = {:block, [
      ...>   {:early_return, {:literal, :integer, 1}},
      ...>   {:literal, :integer, 2}
      ...> ]}
      iex> doc = Metastatic.Document.new(ast, :python)
      iex> {:ok, report} = Metastatic.Analysis.Runner.run(doc,
      ...>   analyzers: [Metastatic.Analysis.DeadCodeAnalyzer])
      iex> length(report.issues)
      1
      iex> [issue | _] = report.issues
      iex> issue.category
      :correctness
  """

  @behaviour Metastatic.Analysis.Analyzer

  alias Metastatic.Analysis.{Analyzer, DeadCode}

  # ----- Behaviour Callbacks -----

  @impl true
  def info do
    %{
      name: :dead_code,
      category: :correctness,
      description: "Detects unreachable and dead code patterns",
      severity: :warning,
      explanation: """
      Dead code is code that can never be executed. This includes:
      - Code after return statements
      - Branches in constant conditionals
      - Unreachable paths

      Dead code should be removed to keep the codebase clean and maintainable.
      """,
      configurable: true
    }
  end

  @impl true
  def run_before(context) do
    # Convert config from map to keyword list if needed
    opts =
      case context.config do
        config when is_list(config) -> config
        config when is_map(config) -> Map.to_list(config)
        _other -> []
      end

    # Run the standalone DeadCode analyzer on the full document
    case DeadCode.analyze(context.document, opts) do
      {:ok, result} ->
        # Store result for later use
        context = Map.put(context, :dead_code_result, result)
        {:ok, context}

      {:error, reason} ->
        {:skip, reason}
    end
  end

  @impl true
  def analyze(_node, _context) do
    # Individual node analysis not needed; all analysis done in run_before
    []
  end

  @impl true
  def run_after(context, issues) do
    # Convert dead code results to analyzer issues
    case Map.get(context, :dead_code_result) do
      nil ->
        issues

      result ->
        new_issues = convert_dead_code_results(result, context)
        issues ++ new_issues
    end
  end

  # ----- Private Helpers -----

  defp convert_dead_code_results(result, context) do
    dead_locations = Map.get(result, :dead_locations, [])

    Enum.map(dead_locations, fn location ->
      severity =
        case Map.get(location, :confidence, :low) do
          :high -> :warning
          :medium -> :info
          :low -> :info
        end

      node = Map.get(location, :context, %{}) |> Map.get(:ast)

      Analyzer.issue(
        analyzer: __MODULE__,
        category: :correctness,
        severity: severity,
        message: Map.get(location, :reason, "Dead code detected"),
        node: node || context.document.ast,
        location: %{line: nil, column: nil, path: nil},
        suggestion:
          Analyzer.suggestion(
            type: :remove,
            replacement: nil,
            message: Map.get(location, :suggestion, "Remove dead code")
          ),
        metadata: Map.put(location, :type, Map.get(location, :type))
      )
    end)
  end
end
