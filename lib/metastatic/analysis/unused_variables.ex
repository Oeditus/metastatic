defmodule Metastatic.Analysis.UnusedVariables do
  @moduledoc """
  Unused variable detection at the MetaAST level.

  Identifies variables that are assigned but never read, including
  function parameters, loop iterators, and pattern matches. Works across
  all supported languages by operating on the unified MetaAST representation.

  This module implements both:
  - **Standalone API** - Direct analysis via `analyze/2` returning structured results
  - **Analyzer behaviour** - Plugin integration for batch analysis via Runner

  ## Detection Categories

  - **Local variables** - Assigned but never referenced
  - **Function parameters** - Lambda parameters never used in body
  - **Loop iterators** - Loop variables never accessed
  - **Pattern matches** - Variables bound in patterns but not used

  ## Standalone Usage

      alias Metastatic.{Document, Analysis.UnusedVariables}

      # Analyze for unused variables
      ast = {:block, [], [
        {:assignment, [], [{:variable, [], "x"}, {:literal, [subtype: :integer], 42}]},
        {:literal, [subtype: :integer], 5}
      ]}
      doc = Document.new(ast, :python)
      {:ok, result} = UnusedVariables.analyze(doc)

      result.has_unused?       # => true
      result.total_unused      # => 1
      result.unused_variables  # => [%{name: "x", category: :local, ...}]

  ## Plugin Usage

      alias Metastatic.Analysis.{Registry, Runner}

      # Register as analyzer plugin
      Registry.register(UnusedVariables)

      # Run via Runner
      {:ok, report} = Runner.run(doc)

  ## Configuration (when used as plugin)

  - `:ignore_prefix` - Ignore variables starting with this prefix (default: `"_"`)
  - `:ignore_names` - List of variable names to ignore (default: `[]`)

  ## Examples

      # No unused variables
      iex> ast = {:assignment, [], [{:variable, [], "x"}, {:literal, [subtype: :integer], 5}]}
      iex> doc = Metastatic.Document.new(ast, :python)
      iex> {:ok, result} = Metastatic.Analysis.UnusedVariables.analyze(doc)
      iex> result.has_unused?
      false

      # Unused local variable
      iex> ast = {:block, [], [
      ...>   {:assignment, [], [{:variable, [], "x"}, {:literal, [subtype: :integer], 1}]},
      ...>   {:literal, [subtype: :integer], 2}
      ...> ]}
      iex> doc = Metastatic.Document.new(ast, :python)
      iex> {:ok, result} = Metastatic.Analysis.UnusedVariables.analyze(doc)
      iex> result.has_unused?
      true
      iex> [var | _] = result.unused_variables
      iex> var.name
      "x"
      iex> var.category
      :local
  """

  alias Metastatic.Analysis.UnusedVariables.Result
  alias Metastatic.Document

  use Metastatic.Document.Analyzer,
    doc: """
    Analyzes a document for unused variables.

    Returns `{:ok, result}` where result is a `Metastatic.Analysis.UnusedVariables.Result` struct.

    ## Options

    - `:ignore_underscore` - Ignore variables starting with underscore (default: true)
    - `:categories` - List of categories to check (default: all)

    ## Examples

        iex> ast = {:literal, [subtype: :integer], 42}
        iex> doc = Metastatic.Document.new(ast, :elixir)
        iex> {:ok, result} = Metastatic.Analysis.UnusedVariables.analyze(doc)
        iex> result.has_unused?
        false
    """

  def info do
    %{
      name: :unused_variables,
      category: :correctness,
      description: "Detects variables that are assigned but never used",
      severity: :warning,
      explanation: """
      Variables that are assigned but never referenced add noise to the code
      and may indicate bugs, incomplete code, or forgotten cleanup.

      Consider removing unused variables or prefixing them with underscore
      if they must exist for API compatibility.
      """,
      configurable: true
    }
  end

  @impl Metastatic.Document.Analyzer
  def handle_analyze(%Document{ast: ast} = _doc, opts) do
    ignore_underscore = Keyword.get(opts, :ignore_underscore, true)

    # Build symbol table: track writes and reads
    symbol_table = build_symbol_table(ast, %{scope_stack: [[]], category: :local})

    # Find variables that were written but never read
    unused =
      symbol_table.scope_stack
      |> List.flatten()
      |> Enum.uniq_by(& &1.name)
      |> Enum.filter(fn var ->
        not var.was_read and should_report?(var, ignore_underscore)
      end)
      |> Enum.map(&format_unused_variable/1)

    {:ok, Result.new(unused)}
  end

  # 3-tuple format
  defp build_symbol_table(ast, ctx) do
    case ast do
      {:block, _meta, statements} when is_list(statements) ->
        # New scope for block
        ctx = push_scope(ctx)
        ctx = Enum.reduce(statements, ctx, &build_symbol_table/2)
        pop_scope(ctx)

      {:assignment, _meta, [target, value]} ->
        ctx = track_writes(target, ctx.category, ctx)
        build_symbol_table(value, ctx)

      {:inline_match, _meta, [pattern, value]} ->
        ctx = track_writes(pattern, :pattern, ctx)
        build_symbol_table(value, ctx)

      {:variable, _meta, name} ->
        track_read(name, ctx)

      {:lambda, meta, [body]} when is_list(meta) ->
        params = Keyword.get(meta, :params, [])
        ctx = push_scope(ctx)
        # Track parameters as writes
        ctx = Enum.reduce(params, ctx, fn param, c -> track_writes(param, :parameter, c) end)
        ctx = build_symbol_table(body, ctx)
        pop_scope(ctx)

      {:loop, meta, children} when is_list(meta) and is_list(children) ->
        loop_type = Keyword.get(meta, :loop_type, :for)

        case {loop_type, children} do
          {:while, [cond_expr, body]} ->
            ctx = build_symbol_table(cond_expr, ctx)
            ctx = push_scope(ctx)
            ctx = build_symbol_table(body, ctx)
            pop_scope(ctx)

          {:for, [iterator, collection, body]} ->
            ctx = build_symbol_table(collection, ctx)
            ctx = push_scope(ctx)
            ctx = track_writes(iterator, :iterator, ctx)
            ctx = build_symbol_table(body, ctx)
            pop_scope(ctx)

          {_, [body]} ->
            ctx = push_scope(ctx)
            ctx = build_symbol_table(body, ctx)
            pop_scope(ctx)

          _ ->
            Enum.reduce(children, ctx, &build_symbol_table/2)
        end

      {:conditional, _meta, [cond_expr, then_branch, else_branch]} ->
        ctx = build_symbol_table(cond_expr, ctx)
        ctx = build_symbol_table(then_branch, ctx)
        if is_nil(else_branch), do: ctx, else: build_symbol_table(else_branch, ctx)

      {:binary_op, _meta, [left, right]} ->
        ctx = build_symbol_table(left, ctx)
        build_symbol_table(right, ctx)

      {:unary_op, _meta, [operand]} ->
        build_symbol_table(operand, ctx)

      {:function_call, _meta, args} when is_list(args) ->
        Enum.reduce(args, ctx, &build_symbol_table/2)

      {:collection_op, _meta, children} when is_list(children) ->
        Enum.reduce(children, ctx, &build_symbol_table/2)

      {:exception_handling, _meta, [try_block, catches, else_block]} ->
        ctx = build_symbol_table(try_block, ctx)

        ctx =
          if is_list(catches) do
            Enum.reduce(catches, ctx, &build_symbol_table/2)
          else
            ctx
          end

        if is_nil(else_block), do: ctx, else: build_symbol_table(else_block, ctx)

      {:early_return, _meta, [value]} ->
        build_symbol_table(value, ctx)

      {:list, _meta, elems} when is_list(elems) ->
        Enum.reduce(elems, ctx, &build_symbol_table/2)

      _ ->
        ctx
    end
  end

  # Track variable writes (assignments, patterns, parameters) - 3-tuple format
  defp track_writes({:variable, _meta, name}, category, ctx) do
    var = %{name: name, category: category, was_read: false}
    update_current_scope(ctx, fn scope -> [var | scope] end)
  end

  defp track_writes({:list, _meta, elems}, category, ctx) when is_list(elems) do
    Enum.reduce(elems, ctx, fn elem, c -> track_writes(elem, category, c) end)
  end

  defp track_writes(name, category, ctx) when is_binary(name) do
    var = %{name: name, category: category, was_read: false}
    update_current_scope(ctx, fn scope -> [var | scope] end)
  end

  defp track_writes(_, _category, ctx), do: ctx

  # Track variable reads
  defp track_read(name, ctx) do
    update_all_scopes(ctx, fn scope ->
      Enum.map(scope, fn var ->
        if var.name == name, do: %{var | was_read: true}, else: var
      end)
    end)
  end

  # Scope management
  defp push_scope(ctx) do
    %{ctx | scope_stack: [[] | ctx.scope_stack]}
  end

  defp pop_scope(ctx) do
    [_current | rest] = ctx.scope_stack
    %{ctx | scope_stack: rest}
  end

  defp update_current_scope(ctx, fun) do
    [current | rest] = ctx.scope_stack
    %{ctx | scope_stack: [fun.(current) | rest]}
  end

  defp update_all_scopes(ctx, fun) do
    %{ctx | scope_stack: Enum.map(ctx.scope_stack, fun)}
  end

  # Determine if variable should be reported as unused
  defp should_report?(%{name: "_" <> _}, true), do: false
  defp should_report?(_var, _ignore_underscore), do: true

  defp format_unused_variable(%{name: name, category: category}) do
    %{
      name: name,
      category: category,
      suggestion: build_suggestion(name, category),
      context: nil
    }
  end

  defp build_suggestion(name, :parameter) do
    "Remove unused parameter '#{name}' or prefix with underscore"
  end

  defp build_suggestion(name, :iterator) do
    "Remove unused iterator '#{name}' or prefix with underscore"
  end

  defp build_suggestion(name, :local) do
    "Remove unused variable '#{name}'"
  end

  defp build_suggestion(name, :pattern) do
    "Remove unused binding '#{name}' from pattern or prefix with underscore"
  end
end
