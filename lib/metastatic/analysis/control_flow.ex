defmodule Metastatic.Analysis.ControlFlow do
  @moduledoc """
  Control flow graph construction at the MetaAST level.

  Builds a control flow graph (CFG) from MetaAST, identifying control flow
  paths, entry/exit points, and providing graph analysis capabilities.
  Works across all supported languages.

  ## CFG Components

  - **Nodes** - Entry, exit, statements, conditionals, loops
  - **Edges** - Control flow connections (conditional/unconditional)
  - **Entry point** - Where execution begins
  - **Exit points** - Where execution ends

  ## Usage

      alias Metastatic.{Document, Analysis.ControlFlow}

      # Build CFG
      ast = {:conditional, {:variable, "x"},
        {:literal, :integer, 1},
        {:literal, :integer, 2}}
      doc = Document.new(ast, :python)
      {:ok, result} = ControlFlow.analyze(doc)

      result.node_count    # Number of nodes
      result.edge_count    # Number of edges
      result.has_cycles?   # Contains cycles?

  ## Examples

      # Simple literal creates minimal CFG
      iex> ast = {:literal, :integer, 42}
      iex> doc = Metastatic.Document.new(ast, :python)
      iex> {:ok, result} = Metastatic.Analysis.ControlFlow.analyze(doc)
      iex> result.node_count >= 1
      true
  """

  alias Metastatic.Analysis.ControlFlow.Result
  alias Metastatic.Document

  @doc """
  Analyzes a document to build its control flow graph.

  Returns `{:ok, result}` where result contains the CFG and analysis.

  ## Examples

      iex> ast = {:literal, :integer, 42}
      iex> doc = Metastatic.Document.new(ast, :elixir)
      iex> {:ok, result} = Metastatic.Analysis.ControlFlow.analyze(doc)
      iex> is_integer(result.node_count)
      true
  """
  @spec analyze(Document.t(), keyword()) :: {:ok, Result.t()}
  def analyze(%Document{ast: ast} = _doc, _opts \\ []) do
    cfg = build_cfg(ast)
    {:ok, Result.new(cfg)}
  end

  @doc """
  Analyzes a document to build its CFG, raising on error.

  ## Examples

      iex> ast = {:literal, :integer, 42}
      iex> doc = Metastatic.Document.new(ast, :elixir)
      iex> result = Metastatic.Analysis.ControlFlow.analyze!(doc)
      iex> is_integer(result.node_count)
      true
  """
  @spec analyze!(Document.t(), keyword()) :: Result.t()
  def analyze!(doc, opts \\ []) do
    {:ok, result} = analyze(doc, opts)
    result
  end

  # Private implementation

  defp build_cfg(ast) do
    # Create entry node
    entry_node = %{
      id: 0,
      type: :entry,
      ast: nil,
      predecessors: [],
      successors: []
    }

    ctx = %{
      nodes: %{0 => entry_node},
      edges: [],
      next_id: 1,
      entry: 0,
      exits: []
    }

    # Build CFG from AST
    {ctx, last_node_id} = build_cfg_node(ast, ctx, 0)

    # Create exit node
    exit_id = ctx.next_id

    exit_node = %{
      id: exit_id,
      type: :exit,
      ast: nil,
      predecessors: [last_node_id],
      successors: []
    }

    # Connect last node to exit
    ctx = %{ctx | nodes: Map.put(ctx.nodes, exit_id, exit_node)}
    ctx = add_edge(ctx, last_node_id, exit_id, nil)
    ctx = %{ctx | exits: [exit_id]}

    %{
      nodes: ctx.nodes,
      edges: ctx.edges,
      entry: ctx.entry,
      exits: ctx.exits
    }
  end

  defp build_cfg_node(ast, ctx, pred_id) do
    case ast do
      {:block, statements} when is_list(statements) ->
        build_sequential_nodes(statements, ctx, pred_id)

      {:conditional, cond, then_br, else_br} ->
        build_conditional_node(cond, then_br, else_br, ctx, pred_id)

      {:loop, :while, cond, body} ->
        build_while_loop_node(cond, body, ctx, pred_id)

      {:loop, _, _iter, _coll, body} ->
        build_for_loop_node(body, ctx, pred_id)

      {:early_return, value} ->
        build_return_node(value, ctx, pred_id)

      _ ->
        build_simple_node(ast, ctx, pred_id)
    end
  end

  defp build_simple_node(ast, ctx, pred_id) do
    node_id = ctx.next_id

    node = %{
      id: node_id,
      type: :statement,
      ast: ast,
      predecessors: [pred_id],
      successors: []
    }

    ctx = %{ctx | nodes: Map.put(ctx.nodes, node_id, node), next_id: node_id + 1}
    ctx = add_edge(ctx, pred_id, node_id, nil)

    {ctx, node_id}
  end

  defp build_sequential_nodes([], ctx, pred_id), do: {ctx, pred_id}

  defp build_sequential_nodes([stmt | rest], ctx, pred_id) do
    {ctx, node_id} = build_cfg_node(stmt, ctx, pred_id)
    build_sequential_nodes(rest, ctx, node_id)
  end

  defp build_conditional_node(cond, then_br, else_br, ctx, pred_id) do
    # Create conditional node
    cond_id = ctx.next_id

    cond_node = %{
      id: cond_id,
      type: :conditional,
      ast: cond,
      predecessors: [pred_id],
      successors: []
    }

    ctx = %{ctx | nodes: Map.put(ctx.nodes, cond_id, cond_node), next_id: cond_id + 1}
    ctx = add_edge(ctx, pred_id, cond_id, nil)

    # Build then branch
    {ctx, then_end} = build_cfg_node(then_br, ctx, cond_id)
    ctx = add_edge(ctx, cond_id, then_end, :then)

    # Build else branch if present
    {ctx, else_end} =
      if else_br do
        {ctx, else_id} = build_cfg_node(else_br, ctx, cond_id)
        ctx = add_edge(ctx, cond_id, else_id, :else)
        {ctx, else_id}
      else
        # No else branch, conditional can flow directly to merge
        {ctx, cond_id}
      end

    # Create merge node
    merge_id = ctx.next_id

    merge_node = %{
      id: merge_id,
      type: :statement,
      ast: nil,
      predecessors: [then_end, else_end],
      successors: []
    }

    ctx = %{ctx | nodes: Map.put(ctx.nodes, merge_id, merge_node), next_id: merge_id + 1}
    ctx = add_edge(ctx, then_end, merge_id, nil)
    ctx = add_edge(ctx, else_end, merge_id, nil)

    {ctx, merge_id}
  end

  defp build_while_loop_node(cond, body, ctx, pred_id) do
    # Create loop header node
    loop_id = ctx.next_id

    loop_node = %{
      id: loop_id,
      type: :loop,
      ast: cond,
      predecessors: [pred_id],
      successors: []
    }

    ctx = %{ctx | nodes: Map.put(ctx.nodes, loop_id, loop_node), next_id: loop_id + 1}
    ctx = add_edge(ctx, pred_id, loop_id, nil)

    # Build loop body
    {ctx, body_end} = build_cfg_node(body, ctx, loop_id)

    # Back edge from body to loop header
    ctx = add_edge(ctx, body_end, loop_id, :loop_back)

    # Exit edge from loop
    exit_id = ctx.next_id

    exit_node = %{
      id: exit_id,
      type: :statement,
      ast: nil,
      predecessors: [loop_id],
      successors: []
    }

    ctx = %{ctx | nodes: Map.put(ctx.nodes, exit_id, exit_node), next_id: exit_id + 1}
    ctx = add_edge(ctx, loop_id, exit_id, :exit)

    {ctx, exit_id}
  end

  defp build_for_loop_node(body, ctx, pred_id) do
    # Simplified for-loop (similar to while)
    loop_id = ctx.next_id

    loop_node = %{
      id: loop_id,
      type: :loop,
      ast: nil,
      predecessors: [pred_id],
      successors: []
    }

    ctx = %{ctx | nodes: Map.put(ctx.nodes, loop_id, loop_node), next_id: loop_id + 1}
    ctx = add_edge(ctx, pred_id, loop_id, nil)

    {ctx, body_end} = build_cfg_node(body, ctx, loop_id)
    ctx = add_edge(ctx, body_end, loop_id, :loop_back)

    {ctx, loop_id}
  end

  defp build_return_node(_value, ctx, pred_id) do
    # Return creates exit point
    return_id = ctx.next_id

    return_node = %{
      id: return_id,
      type: :statement,
      ast: :return,
      predecessors: [pred_id],
      successors: []
    }

    ctx = %{ctx | nodes: Map.put(ctx.nodes, return_id, return_node), next_id: return_id + 1}
    ctx = add_edge(ctx, pred_id, return_id, nil)
    ctx = %{ctx | exits: [return_id | ctx.exits]}

    {ctx, return_id}
  end

  defp add_edge(ctx, from, to, condition) do
    # Update successor of from node
    from_node = Map.get(ctx.nodes, from)

    if from_node do
      updated_from = %{from_node | successors: [to | from_node.successors]}
      ctx = %{ctx | nodes: Map.put(ctx.nodes, from, updated_from)}

      # Update predecessor of to node
      to_node = Map.get(ctx.nodes, to)

      ctx =
        if to_node do
          updated_to = %{to_node | predecessors: [from | to_node.predecessors]}
          %{ctx | nodes: Map.put(ctx.nodes, to, updated_to)}
        else
          ctx
        end

      # Add edge
      %{ctx | edges: [{from, to, condition} | ctx.edges]}
    else
      ctx
    end
  end
end
