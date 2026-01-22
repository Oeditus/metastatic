defmodule Metastatic.Analysis.Complexity do
  @moduledoc """
  Code complexity analysis at the MetaAST level.

  Analyzes code to compute comprehensive complexity metrics that work
  uniformly across all supported languages by operating on the unified
  MetaAST representation.

  ## Metrics

  - **Cyclomatic Complexity** - McCabe metric, decision points + 1
  - **Cognitive Complexity** - Structural complexity with nesting penalties
  - **Nesting Depth** - Maximum nesting level
  - **Halstead Metrics** - Volume, difficulty, effort
  - **Lines of Code** - Physical, logical, comments
  - **Function Metrics** - Statements, returns, variables

  ## Usage

      alias Metastatic.{Document, Analysis.Complexity}

      # Analyze a document
      ast = {:conditional, {:variable, "x"},
        {:literal, :integer, 1},
        {:literal, :integer, 2}}
      doc = Document.new(ast, :python)
      {:ok, result} = Complexity.analyze(doc)

      result.cyclomatic       # => 2
      result.cognitive        # => 1
      result.max_nesting      # => 1
      result.warnings         # => []
      result.summary          # => "Code has low complexity"

  ## Options

  - `:thresholds` - Configurable threshold map (see `Metastatic.Analysis.Complexity.Result`)
  - `:metrics` - List of metrics to calculate (default: all)

  ## Examples

      # Simple arithmetic: complexity = 1
      iex> ast = {:binary_op, :arithmetic, :+, {:literal, :integer, 1}, {:literal, :integer, 2}}
      iex> doc = Metastatic.Document.new(ast, :python)
      iex> {:ok, result} = Metastatic.Analysis.Complexity.analyze(doc)
      iex> result.cyclomatic
      1

      # Conditional: complexity = 2
      iex> ast = {:conditional, {:variable, "x"},
      ...>   {:literal, :integer, 1},
      ...>   {:literal, :integer, 2}}
      iex> doc = Metastatic.Document.new(ast, :elixir)
      iex> {:ok, result} = Metastatic.Analysis.Complexity.analyze(doc)
      iex> result.cyclomatic
      2
  """

  alias Metastatic.Analysis.Complexity.{
    Cognitive,
    Cyclomatic,
    FunctionMetrics,
    Halstead,
    LoC,
    Nesting,
    Result
  }

  alias Metastatic.Document

  @doc """
  Analyzes a document for complexity.

  Returns `{:ok, result}` where result is a `Metastatic.Analysis.Complexity.Result` struct.

  ## Options

  - `:thresholds` - Threshold map for warnings (default thresholds used if not provided)
  - `:metrics` - List of metrics to calculate (default: `:all`)

  ## Examples

      iex> ast = {:literal, :integer, 42}
      iex> doc = Metastatic.Document.new(ast, :python)
      iex> {:ok, result} = Metastatic.Analysis.Complexity.analyze(doc)
      iex> result.cyclomatic
      1
      iex> result.cognitive
      0
  """
  @spec analyze(Document.t(), keyword()) :: {:ok, Result.t()}
  def analyze(%Document{ast: ast, metadata: metadata} = doc, opts \\ []) do
    thresholds = Keyword.get(opts, :thresholds, %{})
    metrics = Keyword.get(opts, :metrics, :all)

    # If the top-level AST is a language-specific module/function definition,
    # extract the body from metadata for analysis
    analysis_ast = extract_analyzable_ast(ast, metadata)

    result =
      %{}
      |> calculate_cyclomatic(analysis_ast, metrics)
      |> calculate_cognitive(analysis_ast, metrics)
      |> calculate_nesting(analysis_ast, metrics)
      |> calculate_halstead(analysis_ast, metrics)
      |> calculate_loc(analysis_ast, doc, metrics)
      |> calculate_function_metrics(analysis_ast, metrics)
      |> Result.new()
      |> Result.apply_thresholds(thresholds)

    {:ok, result}
  end

  @doc """
  Analyzes a document for complexity, raising on error.

  ## Examples

      iex> ast = {:literal, :integer, 42}
      iex> doc = Metastatic.Document.new(ast, :elixir)
      iex> result = Metastatic.Analysis.Complexity.analyze!(doc)
      iex> result.cyclomatic
      1
  """
  @spec analyze!(Document.t(), keyword()) :: Result.t()
  def analyze!(doc, opts \\ []) do
    {:ok, result} = analyze(doc, opts)
    result
  end

  # Private implementation

  defp calculate_cyclomatic(metrics, ast, metric_list) do
    if metric_list == :all or :cyclomatic in metric_list do
      Map.put(metrics, :cyclomatic, Cyclomatic.calculate(ast))
    else
      Map.put(metrics, :cyclomatic, 0)
    end
  end

  defp calculate_cognitive(metrics, ast, metric_list) do
    if metric_list == :all or :cognitive in metric_list do
      Map.put(metrics, :cognitive, Cognitive.calculate(ast))
    else
      Map.put(metrics, :cognitive, 0)
    end
  end

  defp calculate_nesting(metrics, ast, metric_list) do
    if metric_list == :all or :nesting in metric_list do
      Map.put(metrics, :max_nesting, Nesting.calculate(ast))
    else
      Map.put(metrics, :max_nesting, 0)
    end
  end

  defp calculate_halstead(metrics, ast, metric_list) do
    if metric_list == :all or :halstead in metric_list do
      Map.put(metrics, :halstead, Halstead.calculate(ast))
    else
      Map.put(metrics, :halstead, %{})
    end
  end

  defp calculate_loc(metrics, ast, doc, metric_list) do
    if metric_list == :all or :loc in metric_list do
      metadata = Map.get(doc, :metadata, %{})
      Map.put(metrics, :loc, LoC.calculate(ast, metadata))
    else
      Map.put(metrics, :loc, %{})
    end
  end

  defp calculate_function_metrics(metrics, ast, metric_list) do
    if metric_list == :all or :function_metrics in metric_list do
      Map.put(metrics, :function_metrics, FunctionMetrics.calculate(ast))
    else
      Map.put(metrics, :function_metrics, %{})
    end
  end

  # Extract the actual code body from language-specific wrappers
  # For module definitions, extract the module body from metadata
  #
  # NOTE: This currently extracts the top-level module body, which contains
  # language_specific function definition nodes. The bodies of individual
  # functions are lost during transformation (stored in transform/1 return
  # metadata but not preserved in the final Document).
  #
  # For accurate per-function complexity analysis, analyze individual functions
  # directly rather than entire modules.
  defp extract_analyzable_ast({:language_specific, _lang, _native, hint}, metadata)
       when hint in [:module_definition, :function_definition] do
    Map.get(metadata, :body, {:block, []})
  end

  defp extract_analyzable_ast(ast, _metadata), do: ast
end
