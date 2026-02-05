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
      ast = {:conditional, [], [
        {:variable, [], "x"},
        {:literal, [subtype: :integer], 1},
        {:literal, [subtype: :integer], 2}]}
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
      iex> ast = {:binary_op, [category: :arithmetic, operator: :+], [{:literal, [subtype: :integer], 1}, {:literal, [subtype: :integer], 2}]}
      iex> doc = Metastatic.Document.new(ast, :python)
      iex> {:ok, result} = Metastatic.Analysis.Complexity.analyze(doc)
      iex> result.cyclomatic
      1

      # Conditional: complexity = 2
      iex> ast = {:conditional, [], [
      ...>   {:variable, [], "x"},
      ...>   {:literal, [subtype: :integer], 1},
      ...>   {:literal, [subtype: :integer], 2}]}
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
        iex> ast = {:literal, [subtype: :integer], 42}
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

  # 3-tuple format: {:language_specific, meta, native_ast}
  defp extract_analyzable_ast({:language_specific, meta, _native}, metadata)
       when is_list(meta) do
    hint = Keyword.get(meta, :hint)

    if hint in [:module_definition, :function_definition] do
      Map.get(metadata, :body, {:block, [], []})
    else
      Map.get(metadata, :body, {:block, [], []})
    end
  end

  # 3-tuple format: {:container, meta, [body]}
  defp extract_analyzable_ast({:container, meta, [body]}, _doc_metadata)
       when is_list(meta) do
    if is_list(body) do
      {:block, [], body}
    else
      body
    end
  end

  # 3-tuple format: {:function_def, meta, [body]}
  defp extract_analyzable_ast({:function_def, meta, [body]}, _doc_metadata)
       when is_list(meta) do
    body
  end

  defp extract_analyzable_ast(ast, _metadata), do: ast

  # Extract per-function complexity metrics from a module
  # 3-tuple format: {:language_specific, meta, native_ast}
  defp extract_per_function_metrics({:language_specific, meta, _native}, doc_metadata)
       when is_list(meta) do
    hint = Keyword.get(meta, :hint)

    if hint == :module_definition do
      body = Map.get(doc_metadata, :body)
      extract_functions_from_body(body)
    else
      []
    end
  end

  # 3-tuple format: {:container, meta, children}
  # Children can be a list of function definitions directly, or a single body element
  defp extract_per_function_metrics({:container, meta, children}, _doc_metadata)
       when is_list(meta) and is_list(children) do
    members =
      case children do
        # Single block element containing statements
        [{:block, _, statements}] when is_list(statements) ->
          statements

        # Direct list of function definitions or other nodes
        _ ->
          children
      end

    members
    |> Enum.filter(&match?(ast when is_tuple(ast) and elem(ast, 0) == :function_def, &1))
    |> Enum.map(&analyze_function_def/1)
    |> Enum.reject(&is_nil/1)
  end

  defp extract_per_function_metrics(_ast, _metadata) do
    []
  end

  # 3-tuple format: {:block, meta, statements}
  defp extract_functions_from_body({:block, _meta, statements}) when is_list(statements) do
    statements
    |> Enum.filter(
      &match?(
        ast when is_tuple(ast) and elem(ast, 0) in [:function_def, :language_specific],
        &1
      )
    )
    |> Enum.map(fn
      {:function_def, _, _} = node -> analyze_function_def(node)
      {:language_specific, _, _} = node -> analyze_function(node)
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp extract_functions_from_body(_), do: []

  # 3-tuple format: {:language_specific, meta, native_ast}
  defp analyze_function({:language_specific, meta, native_ast}) when is_list(meta) do
    hint = Keyword.get(meta, :hint)

    if hint == :function_definition do
      function_name =
        case native_ast do
          %{"function_name" => name} -> name
          _ -> "unknown"
        end

      body =
        case native_ast do
          %{"body" => b} -> b
          _ -> nil
        end

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
    else
      nil
    end
  end

  defp analyze_function(_), do: nil

  # 3-tuple format: {:function_def, meta, children}
  # Children can be a single body element or a list of statements
  defp analyze_function_def({:function_def, meta, children}) when is_list(meta) do
    name = Keyword.get(meta, :name, "unknown")

    # Wrap children in a block for consistent analysis
    body =
      case children do
        [single] -> single
        statements when is_list(statements) -> {:block, [], statements}
        other -> other
      end

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

  defp analyze_function_def(_), do: nil
end
