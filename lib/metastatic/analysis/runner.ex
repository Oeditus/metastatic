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

  alias Metastatic.{Adapter, Document}
  alias Metastatic.Analysis.{Analyzer, Registry}

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
        # Get analyzer-specific config
        analyzer_config = Map.get(base_context.config, analyzer.info().name, %{})
        context_with_config = Map.put(base_context, :config, analyzer_config)

        # Try to call run_before - it may or may not be defined
        try do
          case analyzer.run_before(context_with_config) do
            {:ok, ctx} ->
              {ready ++ [analyzer], Map.put(contexts, analyzer, ctx)}

            {:skip, reason} ->
              Logger.debug("Analyzer #{inspect(analyzer)} skipped: #{inspect(reason)}")
              {ready, contexts}
          end
        rescue
          UndefinedFunctionError ->
            # No run_before defined, use context as-is
            {ready ++ [analyzer], Map.put(contexts, analyzer, context_with_config)}
        end
      end)

    {ready, contexts}
  end

  defp traverse(ast, analyzers, contexts, opts) do
    # Get document language from context (use first analyzer's context)
    language =
      case Map.values(contexts) do
        [first_context | _] -> first_context.document.language
        # Default fallback when no analyzers
        [] -> :elixir
      end

    # Single-pass traversal calling all analyzers
    walk(ast, analyzers, contexts, [], opts, language)
  end

  defp walk(ast, analyzers, contexts, issues, opts, language) do
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
      walk_children(ast, analyzers, contexts, all_issues, opts, language)
    end
  end

  defp walk_children(ast, analyzers, contexts, issues, opts, language) do
    # Extract child nodes
    children = extract_children(ast, language)

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
      walk(child, analyzers, acc_contexts, acc_issues, opts, language)
    end)
  end

  # Extract children from AST nodes using the new 3-tuple format:
  # {type_atom, keyword_meta, children_or_value}
  #
  # For most composite nodes, children are in elem(ast, 2) as a list.
  # Leaf nodes (literal, variable) have values, not children.
  defp extract_children(ast, language) do
    case ast do
      # === NEW 3-TUPLE FORMAT ===

      # Leaf nodes - no children (value in third position)
      {:literal, _meta, _value} ->
        []

      {:variable, _meta, _name} ->
        []

      # Composite nodes - children are a list in third position
      {:binary_op, _meta, [left, right]} ->
        [left, right]

      {:unary_op, _meta, [operand]} ->
        [operand]

      {:conditional, _meta, children} when is_list(children) ->
        # [condition, then_branch, else_branch]
        Enum.filter(children, &(&1 != nil))

      {:block, _meta, stmts} when is_list(stmts) ->
        stmts

      {:early_return, _meta, value} ->
        if is_nil(value), do: [], else: [value]

      {:assignment, _meta, [target, value]} ->
        [target, value]

      {:inline_match, _meta, [pattern, value]} ->
        [pattern, value]

      {:function_call, _meta, args} when is_list(args) ->
        args

      {:list, _meta, elements} when is_list(elements) ->
        elements

      {:map, _meta, pairs} when is_list(pairs) ->
        pairs

      {:pair, _meta, [key, value]} ->
        [key, value]

      {:tuple, _meta, elements} when is_list(elements) ->
        elements

      {:attribute_access, _meta, [receiver]} ->
        [receiver]

      {:augmented_assignment, _meta, [target, value]} ->
        [target, value]

      # M2.2 Extended layer - 3-tuple format
      {:loop, _meta, children} when is_list(children) ->
        # :while has [condition, body], :for/:for_each has [iterator, collection, body]
        children

      {:lambda, _meta, body} when is_list(body) ->
        # Body statements as children
        body

      {:collection_op, _meta, children} when is_list(children) ->
        # [func, collection] or [func, collection, initial]
        children

      {:pattern_match, _meta, children} when is_list(children) ->
        # [scrutinee | match_arms]
        children

      {:match_arm, _meta, body} when is_list(body) ->
        # Body statements
        body

      {:exception_handling, _meta, children} when is_list(children) ->
        # [try_block | catch_blocks]
        children

      {:async_operation, _meta, [operation]} ->
        [operation]

      # M2.2s Structural layer - 3-tuple format
      {:container, _meta, body} when is_list(body) ->
        body

      {:function_def, _meta, body} when is_list(body) ->
        body

      {:property, _meta, children} when is_list(children) ->
        # [getter, setter] - filter out nils
        Enum.filter(children, &(&1 != nil))

      # M2.3 Native layer - 3-tuple format
      {:language_specific, meta, native_ast} ->
        # Check for body in metadata first
        case Keyword.get(meta, :body) do
          body when not is_nil(body) -> [body]
          nil -> extract_language_specific_children(native_ast, language)
        end

      # List of nodes (for traversing lists of statements)
      list when is_list(list) ->
        list

      # Unknown/unrecognized format - try generic extraction
      _ ->
        generic_extract_children(ast)
    end
  end

  # Note: extract_pattern_children and extract_catches removed -
  # no longer needed with 3-tuple format where children are always in elem(ast, 2)

  # Extract children from language-specific AST nodes
  # Delegates to the adapter for the specified language
  defp extract_language_specific_children(ast, language) do
    case Adapter.for_language(language) do
      {:ok, adapter} ->
        # Use adapter's extract_children if available
        if function_exported?(adapter, :extract_children, 1) do
          adapter.extract_children(ast)
        else
          # Fallback to generic extraction
          generic_extract_children(ast)
        end

      {:error, :no_adapter_found} ->
        # No adapter found, use generic extraction
        generic_extract_children(ast)
    end
  end

  # Generic fallback for extracting children from unknown AST structures
  defp generic_extract_children(ast) when is_list(ast), do: ast

  defp generic_extract_children(ast) when is_tuple(ast) do
    # Try to extract tuple elements, assuming common pattern {tag, meta, children}
    case tuple_size(ast) do
      3 ->
        case elem(ast, 2) do
          children when is_list(children) -> children
          _ -> []
        end

      _ ->
        []
    end
  end

  defp generic_extract_children(_), do: []

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

  # Update context based on current AST node using new 3-tuple format:
  # {type_atom, keyword_meta, children_or_value}
  #
  # Track function names, module names, etc. for analyzers that need them.
  # Container/function_def have name in keyword meta.
  defp update_contexts(contexts, ast) do
    case ast do
      # Container: {:container, [container_type: t, name: n, ...], body}
      {:container, meta, _body} when is_list(meta) ->
        name = Keyword.get(meta, :name)

        if name do
          Enum.reduce(contexts, %{}, fn {analyzer, ctx}, acc ->
            Map.put(acc, analyzer, Map.put(ctx, :module_name, name))
          end)
        else
          contexts
        end

      # Function definition: {:function_def, [name: n, params: [...], ...], body}
      {:function_def, meta, _body} when is_list(meta) ->
        name = Keyword.get(meta, :name)
        arity = length(Keyword.get(meta, :params, []))

        if name do
          Enum.reduce(contexts, %{}, fn {analyzer, ctx}, acc ->
            ctx =
              ctx
              |> Map.put(:function_name, name)
              |> Map.put(:function_arity, arity)

            Map.put(acc, analyzer, ctx)
          end)
        else
          contexts
        end

      _ ->
        # No context update for other nodes
        contexts
    end
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
