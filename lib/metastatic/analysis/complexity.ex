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

  use Metastatic.Document.Analyzer,
    doc: """
    Analyzes a document for complexity.

    Accepts either:
    - A `Metastatic.Document` struct
    - A `{language, native_ast}` tuple

    Returns `{:ok, result}` where result is a `Metastatic.Analysis.Complexity.Result` struct.

    ## Options

    - `:thresholds` - Threshold map for warnings (default thresholds used if not provided)
    - `:metrics` - List of metrics to calculate (default: `:all`)

    ## Examples

        # Using Document
        iex> ast = {:literal, :integer, 42}
        iex> doc = Metastatic.Document.new(ast, :python)
        iex> {:ok, result} = Metastatic.Analysis.Complexity.analyze(doc)
        iex> result.cyclomatic
        1
        iex> result.cognitive
        0

        # Using {language, native_ast} tuple
        iex> python_ast = %{"_type" => "Constant", "value" => 42}
        iex> {:ok, result} = Metastatic.Analysis.Complexity.analyze(:python, python_ast, [])
        iex> result.cyclomatic
        1
    """

  @impl Metastatic.Document.Analyzer
  def handle_analyze(%Document{ast: ast, metadata: metadata} = doc, opts \\ []) do
    thresholds = Keyword.get(opts, :thresholds, %{})
    metrics = Keyword.get(opts, :metrics, :all)

    # If the top-level AST is a language-specific module/function definition,
    # extract the body from metadata for analysis
    analysis_ast = extract_analyzable_ast(ast, metadata)

    # Extract per-function metrics if analyzing a module
    per_function = extract_per_function_metrics(ast, metadata)

    result =
      %{}
      |> calculate_cyclomatic(analysis_ast, metrics)
      |> calculate_cognitive(analysis_ast, metrics)
      |> calculate_nesting(analysis_ast, metrics)
      |> calculate_halstead(analysis_ast, metrics)
      |> calculate_loc(analysis_ast, doc, metrics)
      |> calculate_function_metrics(analysis_ast, metrics)
      |> Map.put(:per_function, per_function)
      |> Result.new()
      |> Result.apply_thresholds(thresholds)

    {:ok, result}
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

  # M2.2s: Structural types - extract members/body for analysis
  # NEW format: {:container, type, name, parent, type_params, implements, body}
  defp extract_analyzable_ast(
         {:container, _type, _name, _parent, _type_params, _implements, body},
         _doc_metadata
       ) do
    # For containers, analyze the aggregate complexity of all members
    if is_list(body) do
      {:block, body}
    else
      body
    end
  end

  # NEW format: {:function_def, name, params, ret_type, opts, body}
  defp extract_analyzable_ast(
         {:function_def, _name, _params, _ret_type, _opts, body},
         _doc_metadata
       ) do
    # For function definitions, analyze the body
    body
  end

  defp extract_analyzable_ast(ast, _metadata), do: ast

  # Extract per-function complexity metrics from a module
  defp extract_per_function_metrics({:language_specific, _, _, hint, metadata}, doc_metadata)
       when hint == :module_definition and is_map(metadata) do
    body = Map.get(metadata, :body) || Map.get(doc_metadata, :body)
    extract_functions_from_body(body)
  end

  defp extract_per_function_metrics({:language_specific, _, _, hint}, metadata)
       when hint == :module_definition do
    metadata
    |> Map.get(:body)
    |> extract_functions_from_body()
  end

  # M2.2s: Extract functions from container members
  # NEW format: {:container, type, name, parent, type_params, implements, body}
  defp extract_per_function_metrics(
         {:container, _type, name, _parent, _type_params, _implements, body},
         _doc_metadata
       ) do
    # Handle different body formats:
    # - {:block, [function_def, ...]} for multiple functions
    # - function_def for single function
    # - [function_def, ...] for list of functions (edge case)
    members =
      case body do
        {:block, statements} when is_list(statements) ->
          statements

        list when is_list(list) ->
          list

        single_item ->
          [single_item]
      end

    members
    |> Enum.filter(&match?(ast when is_tuple(ast) and elem(ast, 1) == :function_def, &1))
    |> Enum.map(&analyze_function_def/1)
  end

  defp extract_per_function_metrics(_ast, _metadata) do
    []
  end

  defp extract_functions_from_body({:block, statements}) when is_list(statements) do
    statements
    |> Enum.filter(fn
      {:language_specific, _, _, :function_definition, _} -> true
      {:language_specific, _, _, :function_definition} -> true
      {:function_def, _, _, _, _, _} -> true
      _ -> false
    end)
    |> Enum.map(fn
      {:function_def, _, _, _, _, _} = node -> analyze_function_def(node)
      node -> analyze_function(node)
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp extract_functions_from_body(_), do: []

  defp analyze_function({:language_specific, _, _, :function_definition, metadata})
       when is_map(metadata) do
    function_name = Map.get(metadata, :function_name, "unknown")
    body = Map.get(metadata, :body)

    if body do
      variables = Metastatic.AST.variables(body)

      %{
        name: function_name,
        cyclomatic: Cyclomatic.calculate(body),
        cognitive: Cognitive.calculate(body),
        max_nesting: Nesting.calculate(body),
        statements: FunctionMetrics.calculate(body).statement_count,
        variables: MapSet.size(variables)
      }
    else
      nil
    end
  end

  defp analyze_function(_), do: nil

  # M2.2s: Analyze function_def structural type
  # NEW format: {:function_def, name, params, ret_type, opts, body}
  defp analyze_function_def({:function_def, name, _params, _ret_type, _opts, body}) do
    variables = Metastatic.AST.variables(body)

    %{
      name: name,
      cyclomatic: Cyclomatic.calculate(body),
      cognitive: Cognitive.calculate(body),
      max_nesting: Nesting.calculate(body),
      statements: FunctionMetrics.calculate(body).statement_count,
      variables: MapSet.size(variables)
    }
  end
end
