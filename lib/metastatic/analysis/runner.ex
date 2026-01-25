defmodule Metastatic.Analysis.Runner do
  @moduledoc """
  Executes multiple analyzers on a Document in a single pass.

  Handles AST traversal, context management, and issue collection.

  ## Usage

      alias Metastatic.{Document, Analysis.Runner}

      doc = Document.new(ast, :python)

      # Run all registered analyzers
      {:ok, report} = Runner.run(doc)

      # Run specific analyzers
      {:ok, report} = Runner.run(doc,
        analyzers: [MyAnalyzer, AnotherAnalyzer]
      )

      # With configuration
      {:ok, report} = Runner.run(doc,
        analyzers: :all,
        config: %{my_analyzer: %{threshold: 10}}
      )

  ## Report Structure

  The report contains:
  - `:document` - The analyzed document
  - `:analyzers_run` - List of analyzers that were executed
  - `:issues` - All issues found
  - `:summary` - Aggregated statistics
  - `:timing` - Performance metrics (if enabled)
  """

  alias Metastatic.Analysis.{Analyzer, Registry}
  alias Metastatic.Document

  require Logger

  @type run_options :: [
          analyzers: :all | [module()],
          config: map(),
          halt_on_error: boolean(),
          max_issues: non_neg_integer() | :infinity,
          track_timing: boolean()
        ]

  @type report :: %{
          document: Document.t(),
          analyzers_run: [module()],
          issues: [Analyzer.issue()],
          summary: map(),
          timing: map() | nil
        }

  # ----- Public API -----

  @doc """
  Runs configured analyzers on a document.

  ## Options

  - `:analyzers` - Which analyzers to run (default: `:all` registered)
  - `:config` - Configuration map for analyzers
  - `:halt_on_error` - Stop on first error severity issue (default: `false`)
  - `:max_issues` - Maximum issues to collect (default: `:infinity`)
  - `:track_timing` - Include timing information (default: `false`)

  ## Examples

      iex> doc = Document.new(ast, :python)
      iex> {:ok, report} = Runner.run(doc)
      iex> report.summary.total
      3

      iex> {:ok, report} = Runner.run(doc, analyzers: [UnusedVariables])
      iex> report.analyzers_run
      [Metastatic.Analysis.UnusedVariables]
  """
  @spec run(Document.t(), run_options()) :: {:ok, report()} | {:error, term()}
  def run(%Document{} = doc, opts \\ []) do
    start_time = if Keyword.get(opts, :track_timing, false), do: System.monotonic_time()

    # Get analyzers to run
    analyzers = get_analyzers(opts)
    config = Keyword.get(opts, :config, %{})

    # Initialize base context
    base_context = %{
      document: doc,
      config: config,
      parent_stack: [],
      depth: 0,
      scope: %{}
    }

    # Run before hooks
    {ready_analyzers, contexts} = run_before_hooks(analyzers, base_context)

    # Traverse AST and collect issues
    {issues, final_contexts} = traverse(doc.ast, ready_analyzers, contexts, opts)

    # Run after hooks
    final_issues = run_after_hooks(ready_analyzers, final_contexts, issues)

    # Calculate timing if requested
    timing =
      if start_time do
        %{
          total_ms:
            System.convert_time_unit(System.monotonic_time() - start_time, :native, :millisecond)
        }
      end

    # Build report
    report = %{
      document: doc,
      analyzers_run: ready_analyzers,
      issues: final_issues,
      summary: summarize(final_issues),
      timing: timing
    }

    {:ok, report}
  rescue
    e ->
      {:error, {:analysis_failed, e, __STACKTRACE__}}
  end

  @doc """
  Runs analyzers, raising on error.

  ## Examples

      iex> report = Runner.run!(doc)
      iex> length(report.issues)
      3
  """
  @spec run!(Document.t(), run_options()) :: report()
  def run!(doc, opts \\ []) do
    case run(doc, opts) do
      {:ok, report} -> report
      {:error, reason} -> raise "Analysis failed: #{inspect(reason)}"
    end
  end

  # ----- Private Implementation -----

  defp get_analyzers(opts) do
    case Keyword.get(opts, :analyzers, :all) do
      :all -> Registry.list_all()
      list when is_list(list) -> list
    end
  end

  defp run_before_hooks(analyzers, base_context) do
    {ready, contexts} =
      Enum.reduce(analyzers, {[], %{}}, fn analyzer, {ready, contexts} ->
        if function_exported?(analyzer, :run_before, 1) do
          # Get analyzer-specific config
          analyzer_config = Map.get(base_context.config, analyzer.info().name, %{})
          context_with_config = Map.put(base_context, :config, analyzer_config)

          case analyzer.run_before(context_with_config) do
            {:ok, ctx} ->
              {ready ++ [analyzer], Map.put(contexts, analyzer, ctx)}

            {:skip, reason} ->
              Logger.debug("Analyzer #{inspect(analyzer)} skipped: #{inspect(reason)}")
              {ready, contexts}
          end
        else
          # No run_before, use base context with analyzer-specific config
          analyzer_config = Map.get(base_context.config, analyzer.info().name, %{})
          context_with_config = Map.put(base_context, :config, analyzer_config)
          {ready ++ [analyzer], Map.put(contexts, analyzer, context_with_config)}
        end
      end)

    {ready, contexts}
  end

  defp traverse(ast, analyzers, contexts, opts) do
    # Single-pass traversal calling all analyzers
    walk(ast, analyzers, contexts, [], opts)
  end

  defp walk(ast, analyzers, contexts, issues, opts) do
    # Update contexts with current node info
    contexts = update_contexts(contexts, ast)

    # Call each analyzer on this node
    node_issues =
      Enum.flat_map(analyzers, fn analyzer ->
        context = Map.get(contexts, analyzer)
        apply_analyzer(analyzer, ast, context)
      end)

    all_issues = issues ++ node_issues

    # Check halt conditions
    if should_halt?(all_issues, opts) do
      {all_issues, contexts}
    else
      # Recurse into children
      walk_children(ast, analyzers, contexts, all_issues, opts)
    end
  end

  defp walk_children(ast, analyzers, contexts, issues, opts) do
    # Extract child nodes
    children = extract_children(ast)

    # Update context depth and parent stack
    contexts =
      Enum.reduce(contexts, %{}, fn {analyzer, ctx}, acc ->
        Map.put(acc, analyzer, %{
          ctx
          | depth: ctx.depth + 1,
            parent_stack: [ast | ctx.parent_stack]
        })
      end)

    # Traverse each child
    Enum.reduce(children, {issues, contexts}, fn child, {acc_issues, acc_contexts} ->
      walk(child, analyzers, acc_contexts, acc_issues, opts)
    end)
  end

  defp extract_children(ast) do
    case ast do
      # M2.1 Core layer
      {:binary_op, _, _, left, right} ->
        [left, right]

      {:unary_op, _, _, operand} ->
        [operand]

      {:conditional, cond, then_br, else_br} ->
        [cond, then_br, else_br]

      {:block, stmts} when is_list(stmts) ->
        stmts

      {:early_return, value} ->
        [value]

      {:assignment, target, value} ->
        [target, value]

      {:inline_match, pattern, value} ->
        [pattern, value]

      {:function_call, _name, args} ->
        args

      {:attribute_access, obj, _attr} ->
        [obj]

      {:augmented_assignment, target, _op, value} ->
        [target, value]

      # M2.2 Extended layer
      {:loop, :while, cond, body} ->
        [cond, body]

      {:loop, _, iter, coll, body} ->
        [iter, coll, body]

      {:lambda, _params, body} ->
        [body]

      {:collection_op, _, func, coll} ->
        [func, coll]

      {:collection_op, _, func, coll, init} ->
        [func, coll, init]

      {:pattern_match, patterns, _opts} when is_list(patterns) ->
        Enum.flat_map(patterns, &extract_pattern_children/1)

      {:exception_handling, try_block, catches, else_block} ->
        [try_block] ++ extract_catches(catches) ++ [else_block]

      {:async_operation, _type, expr} ->
        [expr]

      # M2.2s Structural layer
      {:container, _type, _name, _opts, body} when is_list(body) ->
        body

      {:function_def, _name, _params, _ret_type, _opts, body} ->
        [body]

      {:property, _name, getter, setter, _opts} ->
        [getter, setter]

      # Literals and variables have no children
      {:literal, _, _} ->
        []

      {:variable, _} ->
        []

      # Language-specific nodes - use transformed body from metadata if available
      {:language_specific, _, _original_ast, _tag, metadata} when is_map(metadata) ->
        # Try to get transformed body from metadata first
        case Map.get(metadata, :body) do
          body when not is_nil(body) -> [body]
          nil -> []
        end

      {:language_specific, _, original_ast, _} ->
        # Fallback: extract children from the original language-specific AST
        extract_language_specific_children(original_ast)

      # List of nodes
      list when is_list(list) ->
        list

      # Unknown - no children
      _ ->
        []
    end
  end

  defp extract_pattern_children({_pattern, body}), do: [body]
  defp extract_pattern_children(_), do: []

  # Extract children from language-specific AST nodes
  # These are Elixir/Erlang AST structures that need to be traversed
  defp extract_language_specific_children(ast) when is_tuple(ast) do
    case ast do
      # Module definition: {:defmodule, meta, [name, [do: body]]}
      {:defmodule, _meta, [_name, [do: body]]} ->
        [body]

      # Function definition: {:def/:defp, meta, [signature, [do: body]]}
      {func_type, _meta, [_signature, [do: body]]}
      when func_type in [:def, :defp, :defmacro, :defmacrop] ->
        [body]

      # Block: {:__block__, [], statements}
      {:__block__, _, statements} when is_list(statements) ->
        statements

      # Pipe operator: {:|>, meta, [left, right]}
      {:|>, _meta, [left, right]} ->
        [left, right]

      # Function call: {:function, meta, args}
      {func, _meta, args} when is_atom(func) and is_list(args) ->
        args

      # Remote call: {{:., meta1, [module, func]}, meta2, args}
      {{:., _meta1, [_module, _func]}, _meta2, args} when is_list(args) ->
        args

      # Match operator: {:=, meta, [left, right]}
      {:=, _meta, [left, right]} ->
        [left, right]

      # Try/rescue: {:try, meta, [[do: body, rescue: handlers]]}
      {:try, _meta, [[do: body, rescue: handlers]]} when is_list(handlers) ->
        [body | Enum.map(handlers, fn {:->, _, [_pattern, handler_body]} -> handler_body end)]

      # Module attribute: {:@, meta, [{name, meta2, [value]}]}
      {:@, _meta, [{_name, _meta2, [value]}]} ->
        [value]

      # List
      list when is_list(list) ->
        list

      # Literal or unknown - no children
      _ when is_atom(ast) or is_number(ast) or is_binary(ast) ->
        []

      # Other tuples - try to extract all elements except metadata
      {_tag, _meta, elements} when is_list(elements) ->
        elements

      _ ->
        []
    end
  end

  defp extract_language_specific_children(list) when is_list(list), do: list
  defp extract_language_specific_children(_), do: []

  defp extract_catches(catches) when is_list(catches) do
    Enum.flat_map(catches, fn
      {_exc_type, body} -> [body]
      _ -> []
    end)
  end

  defp extract_catches(_), do: []

  defp apply_analyzer(analyzer, ast, context) do
    analyzer.analyze(ast, context)
  rescue
    e ->
      # Log error but don't fail entire analysis
      Logger.error(
        "Analyzer #{inspect(analyzer)} failed on node #{inspect(elem(ast, 0))}: #{inspect(e)}"
      )

      []
  end

  defp run_after_hooks(analyzers, contexts, issues) do
    Enum.reduce(analyzers, issues, fn analyzer, acc ->
      if function_exported?(analyzer, :run_after, 2) do
        context = Map.get(contexts, analyzer)
        analyzer.run_after(context, acc)
      else
        acc
      end
    end)
  end

  defp update_contexts(contexts, _ast) do
    # Context updates happen in walk_children for depth/parent_stack
    # This is a hook for future extensions
    contexts
  end

  defp should_halt?(issues, opts) do
    halt_on_error = Keyword.get(opts, :halt_on_error, false)
    max_issues = Keyword.get(opts, :max_issues, :infinity)

    has_error = halt_on_error and Enum.any?(issues, fn i -> i.severity == :error end)
    over_max = max_issues != :infinity and length(issues) >= max_issues

    has_error or over_max
  end

  defp summarize(issues) do
    %{
      total: length(issues),
      by_severity: Enum.frequencies_by(issues, & &1.severity),
      by_category: Enum.frequencies_by(issues, & &1.category),
      by_analyzer: Enum.frequencies_by(issues, & &1.analyzer)
    }
  end
end
