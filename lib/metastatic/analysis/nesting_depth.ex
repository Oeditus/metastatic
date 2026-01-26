defmodule Metastatic.Analysis.NestingDepth do
  @moduledoc """
  Detects excessive nesting depth in code.

  High nesting depth makes code harder to understand and maintain. This analyzer
  identifies nodes that exceed a configurable nesting threshold and suggests
  refactoring to reduce complexity.

  Works across all supported languages by operating on the unified MetaAST.

  ## Configuration

  - `:max_depth` - Maximum allowed nesting depth (default: 5)
  - `:warn_threshold` - Depth at which warnings are issued (default: 4)

  ## Examples

      alias Metastatic.{Document, Analysis.Runner}

      # As plugin
      Registry.register(NestingDepth)
      {:ok, report} = Runner.run(doc,
        config: %{nesting_depth: %{max_depth: 4}}
      )

  ## Nesting Examples

      # Depth 0: No nesting
      x = 5

      # Depth 1: One conditional
      if x > 0 then y = 1 end

      # Depth 2: Nested conditionals
      if x > 0 then
        if y > 0 then z = 1 end
      end

      # Depth 3+: Excessive nesting
      if a then
        if b then
          if c then
            result = 1
          end
        end
      end
  """

  @behaviour Metastatic.Analysis.Analyzer

  alias Metastatic.Analysis.Analyzer
  alias Metastatic.Analysis.Complexity.Nesting

  # ----- Behaviour Callbacks -----

  @impl true
  def info do
    %{
      name: :nesting_depth,
      category: :maintainability,
      description: "Detects functions with excessive nesting depth",
      severity: :warning,
      explanation: """
      Deeply nested code is harder to understand, test, and maintain. Each level
      of nesting increases cognitive load for readers. Consider refactoring deeply
      nested code into separate functions or methods.

      Default threshold: 5 levels
      Adjust via configuration.
      """,
      configurable: true
    }
  end

  @impl true
  def run_before(context) do
    # Initialize state for tracking max depth across document
    context = Map.put(context, :max_nesting_depth, 0)
    context = Map.put(context, :depth_issues, [])
    {:ok, context}
  end

  @impl true
  def analyze(node, context) do
    config = context.config

    max_depth =
      cond do
        is_list(config) -> Keyword.get(config, :max_depth, 5)
        is_map(config) -> Map.get(config, :max_depth, 5)
        true -> 5
      end

    warn_threshold =
      cond do
        is_list(config) -> Keyword.get(config, :warn_threshold, 4)
        is_map(config) -> Map.get(config, :warn_threshold, 4)
        true -> 4
      end

    # Calculate nesting depth for this node
    current_depth = Nesting.calculate(node)

    # Track maximum depth (for future use)
    _updated_context =
      update_in(context, [:max_nesting_depth], fn d ->
        max(d, current_depth)
      end)

    # Generate issue if exceeds threshold
    if current_depth >= warn_threshold do
      severity = if current_depth >= max_depth, do: :warning, else: :info

      issue =
        Analyzer.issue(
          analyzer: __MODULE__,
          category: :maintainability,
          severity: severity,
          message: "Nesting depth #{current_depth} exceeds threshold #{warn_threshold}",
          node: node,
          suggestion:
            if current_depth >= max_depth do
              Analyzer.suggestion(
                type: :replace,
                replacement: nil,
                message: "Refactor to reduce nesting depth"
              )
            else
              nil
            end,
          metadata: %{
            current_depth: current_depth,
            max_depth: max_depth,
            warn_threshold: warn_threshold
          }
        )

      [issue]
    else
      []
    end
  end

  @impl true
  def run_after(_context, issues) do
    # Could optionally add summary issues here if needed
    issues
  end
end
