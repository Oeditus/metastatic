defmodule Metastatic.Analysis.ControlFlow.Result do
  @moduledoc """
  Result structure for control flow graph analysis.

  Contains the control flow graph with nodes, edges, entry/exit points,
  and analysis results like reachability and cycles.

  ## Fields

  - `:cfg` - The control flow graph structure
  - `:entry_node` - ID of the entry node
  - `:exit_nodes` - List of exit node IDs
  - `:reachable_nodes` - Set of reachable node IDs
  - `:has_cycles?` - Boolean indicating if graph contains cycles
  - `:node_count` - Total number of nodes
  - `:edge_count` - Total number of edges

  ## Examples

      iex> cfg = %{nodes: %{0 => %{type: :entry}}, edges: [], entry: 0, exits: [0]}
      iex> result = Metastatic.Analysis.ControlFlow.Result.new(cfg)
      iex> result.node_count
      1
  """

  @type node_id :: non_neg_integer()

  @type cfg_node :: %{
          id: node_id(),
          type: :entry | :exit | :statement | :conditional | :loop,
          ast: term(),
          predecessors: [node_id()],
          successors: [node_id()]
        }

  @type cfg_edge :: {from :: node_id(), to :: node_id(), condition :: atom() | nil}

  @type cfg :: %{
          nodes: %{node_id() => cfg_node()},
          edges: [cfg_edge()],
          entry: node_id(),
          exits: [node_id()]
        }

  @type t :: %__MODULE__{
          cfg: cfg(),
          entry_node: node_id(),
          exit_nodes: [node_id()],
          reachable_nodes: MapSet.t(node_id()),
          has_cycles?: boolean(),
          node_count: non_neg_integer(),
          edge_count: non_neg_integer()
        }

  defstruct cfg: %{nodes: %{}, edges: [], entry: 0, exits: []},
            entry_node: 0,
            exit_nodes: [],
            reachable_nodes: MapSet.new(),
            has_cycles?: false,
            node_count: 0,
            edge_count: 0

  @doc """
  Creates a new result from a CFG.

  ## Examples

      iex> cfg = %{nodes: %{0 => %{id: 0, type: :entry, ast: nil, predecessors: [], successors: []}}, edges: [], entry: 0, exits: [0]}
      iex> result = Metastatic.Analysis.ControlFlow.Result.new(cfg)
      iex> result.entry_node
      0
  """
  @spec new(cfg()) :: t()
  def new(cfg) do
    reachable = compute_reachable_nodes(cfg)
    has_cycles = detect_cycles(cfg)

    %__MODULE__{
      cfg: cfg,
      entry_node: cfg.entry,
      exit_nodes: cfg.exits,
      reachable_nodes: reachable,
      has_cycles?: has_cycles,
      node_count: map_size(cfg.nodes),
      edge_count: length(cfg.edges)
    }
  end

  @doc """
  Converts result to JSON-compatible map.

  ## Examples

      iex> cfg = %{nodes: %{}, edges: [], entry: 0, exits: []}
      iex> result = Metastatic.Analysis.ControlFlow.Result.new(cfg)
      iex> map = Metastatic.Analysis.ControlFlow.Result.to_map(result)
      iex> is_map(map)
      true
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = result) do
    %{
      entry_node: result.entry_node,
      exit_nodes: result.exit_nodes,
      reachable_nodes: MapSet.to_list(result.reachable_nodes),
      has_cycles: result.has_cycles?,
      node_count: result.node_count,
      edge_count: result.edge_count,
      nodes: result.cfg.nodes,
      edges: result.cfg.edges
    }
  end

  @doc """
  Exports CFG to DOT format for visualization.

  ## Examples

      iex> cfg = %{nodes: %{0 => %{id: 0, type: :entry, ast: nil, predecessors: [], successors: [1]}, 1 => %{id: 1, type: :exit, ast: nil, predecessors: [0], successors: []}}, edges: [{0, 1, nil}], entry: 0, exits: [1]}
      iex> result = Metastatic.Analysis.ControlFlow.Result.new(cfg)
      iex> dot = Metastatic.Analysis.ControlFlow.Result.to_dot(result)
      iex> String.contains?(dot, "digraph")
      true
  """
  @spec to_dot(t()) :: String.t()
  def to_dot(%__MODULE__{cfg: cfg}) do
    header = "digraph CFG {\n"
    footer = "}\n"

    nodes =
      cfg.nodes
      |> Enum.map(fn {id, node} ->
        label = format_node_label(node)
        shape = node_shape(node.type)
        ~s(  #{id} [label="#{label}", shape=#{shape}];)
      end)
      |> Enum.join("\n")

    edges =
      cfg.edges
      |> Enum.map(fn {from, to, condition} ->
        label = if condition, do: ~s([label="#{condition}"]), else: ""
        ~s(  #{from} -> #{to}#{label};)
      end)
      |> Enum.join("\n")

    header <> nodes <> "\n" <> edges <> "\n" <> footer
  end

  # Private helpers

  defp compute_reachable_nodes(cfg) do
    visit_reachable(cfg, cfg.entry, MapSet.new())
  end

  defp visit_reachable(cfg, node_id, visited) do
    if MapSet.member?(visited, node_id) do
      visited
    else
      visited = MapSet.put(visited, node_id)
      node = Map.get(cfg.nodes, node_id)

      if node do
        Enum.reduce(node.successors, visited, fn succ, acc ->
          visit_reachable(cfg, succ, acc)
        end)
      else
        visited
      end
    end
  end

  defp detect_cycles(cfg) do
    # Simple cycle detection using DFS
    detect_cycle_dfs(cfg, cfg.entry, MapSet.new(), MapSet.new())
  end

  defp detect_cycle_dfs(_cfg, node_id, visited, _rec_stack) when node_id == nil, do: false

  defp detect_cycle_dfs(cfg, node_id, visited, rec_stack) do
    if MapSet.member?(rec_stack, node_id) do
      true
    else
      if MapSet.member?(visited, node_id) do
        false
      else
        visited = MapSet.put(visited, node_id)
        rec_stack = MapSet.put(rec_stack, node_id)
        node = Map.get(cfg.nodes, node_id)

        if node do
          Enum.any?(node.successors, fn succ ->
            detect_cycle_dfs(cfg, succ, visited, rec_stack)
          end)
        else
          false
        end
      end
    end
  end

  defp format_node_label(%{type: :entry}), do: "ENTRY"
  defp format_node_label(%{type: :exit}), do: "EXIT"
  defp format_node_label(%{type: type, id: id}), do: "#{type}_#{id}"

  defp node_shape(:entry), do: "ellipse"
  defp node_shape(:exit), do: "ellipse"
  defp node_shape(:conditional), do: "diamond"
  defp node_shape(:loop), do: "box"
  defp node_shape(_), do: "rectangle"
end
