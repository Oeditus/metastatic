defmodule Metastatic.CLI.Inspector do
  @moduledoc """
  AST inspection and analysis logic for Metastatic CLI.

  Provides various inspection capabilities:
  - Layer filtering (core, extended, native)
  - Variable extraction
  - Node counting
  - Depth analysis
  """

  alias Metastatic.{AST, Document, Validator}

  @type layer :: :core | :extended | :native | :all
  @type inspection_result :: %{
          ast: AST.meta_ast(),
          variables: MapSet.t(String.t()),
          layer: layer(),
          depth: non_neg_integer(),
          node_count: non_neg_integer()
        }

  @doc """
  Inspect a MetaAST document.

  Returns detailed information about the AST structure.
  """
  @spec inspect_document(Document.t(), keyword()) ::
          {:ok, inspection_result()} | {:error, String.t()}
  def inspect_document(%Document{} = doc, opts \\ []) do
    layer_filter = Keyword.get(opts, :layer, :all)

    ast =
      if layer_filter == :all do
        doc.ast
      else
        filter_by_layer(doc.ast, layer_filter)
      end

    variables = AST.variables(doc.ast)
    depth = calculate_depth(doc.ast)
    node_count = count_nodes(doc.ast)
    layer = detect_layer(doc.ast)

    result = %{
      ast: ast,
      variables: variables,
      layer: layer,
      depth: depth,
      node_count: node_count
    }

    {:ok, result}
  end

  @doc """
  Extract only variables from a MetaAST.
  """
  @spec extract_variables(Document.t()) :: {:ok, MapSet.t(String.t())}
  def extract_variables(%Document{} = doc) do
    {:ok, AST.variables(doc.ast)}
  end

  @doc """
  Validate a document and return detailed validation metadata.
  """
  @spec validate_with_details(Document.t(), atom()) ::
          {:ok, Validator.validation_result()} | {:error, term()}
  def validate_with_details(%Document{} = doc, mode \\ :standard) do
    Validator.validate(doc, mode: mode)
  end

  # Private functions

  @spec filter_by_layer(AST.meta_ast(), layer()) :: AST.meta_ast() | nil
  defp filter_by_layer(ast, layer) do
    node_layer = node_layer(ast)

    cond do
      # If the node matches the requested layer, keep it
      node_layer == layer ->
        ast

      # If it's a composite node, filter its children
      composite_node?(ast) ->
        filter_composite_children(ast, layer)

      # Otherwise, exclude this node
      true ->
        nil
    end
  end

  @spec filter_composite_children(AST.meta_ast(), layer()) :: AST.meta_ast() | nil
  defp filter_composite_children({:binary_op, meta, [left, right]}, layer) do
    filtered_left = filter_by_layer(left, layer)
    filtered_right = filter_by_layer(right, layer)

    if filtered_left || filtered_right do
      {:binary_op, meta, [filtered_left || left, filtered_right || right]}
    else
      nil
    end
  end

  defp filter_composite_children({:block, meta, statements}, layer) do
    filtered_statements =
      statements
      |> Enum.map(&filter_by_layer(&1, layer))
      |> Enum.reject(&is_nil/1)

    if Enum.empty?(filtered_statements) do
      nil
    else
      {:block, meta, filtered_statements}
    end
  end

  defp filter_composite_children(ast, _layer), do: ast

  @node_layers %{
    core:
      ~w|literal variable list map binary_op unary_op function_call conditional block early_return|a,
    extended: ~w|loop lambda collection_op exception_handling|a,
    native: ~w|language_specific|a
  }
  @spec node_layer(AST.meta_ast()) :: layer()
  # Handle location-aware nodes
  for {layer, kinds} <- @node_layers do
    defp node_layer(ast) when is_tuple(ast) and elem(ast, 0) in unquote(kinds), do: unquote(layer)
  end

  defp node_layer(_), do: :core

  @composite_nodes ~w|binary_op unary_op list map function_call conditional block loop lambda collection_op exception_handling|a
  @spec composite_node?(AST.meta_ast()) :: boolean()
  # Handle location-aware nodes
  defp composite_node?(ast) when is_tuple(ast) and elem(ast, 0) in @composite_nodes, do: true
  defp composite_node?(_), do: false

  @spec calculate_depth(AST.meta_ast()) :: non_neg_integer()
  # 3-tuple format: {type, meta, children_or_value}
  defp calculate_depth({:literal, _meta, _value}), do: 1
  defp calculate_depth({:variable, _meta, _name}), do: 1

  defp calculate_depth({:binary_op, _meta, [left, right]}) do
    1 + max(calculate_depth(left), calculate_depth(right))
  end

  defp calculate_depth({:unary_op, _meta, [operand]}) do
    1 + calculate_depth(operand)
  end

  defp calculate_depth({:function_call, _meta, args}) when is_list(args) do
    if Enum.empty?(args) do
      1
    else
      1 + (Enum.map(args, &calculate_depth/1) |> Enum.max())
    end
  end

  defp calculate_depth({:conditional, _meta, children}) when is_list(children) do
    # children is [condition, then_branch] or [condition, then_branch, else_branch]
    depths = Enum.map(children, &calculate_depth/1)
    1 + Enum.max(depths)
  end

  defp calculate_depth({:block, _meta, statements}) when is_list(statements) do
    if Enum.empty?(statements) do
      1
    else
      1 + (Enum.map(statements, &calculate_depth/1) |> Enum.max())
    end
  end

  defp calculate_depth({:list, _meta, elements}) when is_list(elements) do
    if Enum.empty?(elements) do
      1
    else
      1 + (Enum.map(elements, &calculate_depth/1) |> Enum.max())
    end
  end

  defp calculate_depth({:map, _meta, pairs}) when is_list(pairs) do
    if Enum.empty?(pairs) do
      1
    else
      1 +
        (Enum.flat_map(pairs, fn {k, v} -> [calculate_depth(k), calculate_depth(v)] end)
         |> Enum.max())
    end
  end

  defp calculate_depth({:loop, meta, children}) when is_list(children) do
    subtype = Keyword.get(meta, :subtype)

    case {subtype, children} do
      {:while, [condition, body]} ->
        1 + max(calculate_depth(condition), calculate_depth(body))

      {:for, [iterator, collection, body]} ->
        1 +
          Enum.max([
            calculate_depth(iterator),
            calculate_depth(collection),
            calculate_depth(body)
          ])

      {:for_each, [iterator, collection, body]} ->
        1 +
          Enum.max([
            calculate_depth(iterator),
            calculate_depth(collection),
            calculate_depth(body)
          ])

      _ ->
        1 + (Enum.map(children, &calculate_depth/1) |> Enum.max(fn -> 0 end))
    end
  end

  defp calculate_depth({:lambda, _meta, children}) when is_list(children) do
    # Last child is body, rest are params/captures info
    body = List.last(children)
    1 + calculate_depth(body)
  end

  defp calculate_depth({:collection_op, _meta, children}) when is_list(children) do
    depths = Enum.map(children, &calculate_depth/1)
    1 + Enum.max(depths, fn -> 0 end)
  end

  defp calculate_depth({:language_specific, _meta, _content}), do: 1
  defp calculate_depth(_), do: 1

  @spec count_nodes(AST.meta_ast()) :: non_neg_integer()
  # 3-tuple format: {type, meta, children_or_value}
  defp count_nodes({:literal, _meta, _value}), do: 1
  defp count_nodes({:variable, _meta, _name}), do: 1

  defp count_nodes({:binary_op, _meta, [left, right]}) do
    1 + count_nodes(left) + count_nodes(right)
  end

  defp count_nodes({:unary_op, _meta, [operand]}) do
    1 + count_nodes(operand)
  end

  defp count_nodes({:function_call, _meta, args}) when is_list(args) do
    1 + Enum.sum(Enum.map(args, &count_nodes/1))
  end

  defp count_nodes({:conditional, _meta, children}) when is_list(children) do
    1 + Enum.sum(Enum.map(children, &count_nodes/1))
  end

  defp count_nodes({:block, _meta, statements}) when is_list(statements) do
    1 + Enum.sum(Enum.map(statements, &count_nodes/1))
  end

  defp count_nodes({:list, _meta, elements}) when is_list(elements) do
    1 + Enum.sum(Enum.map(elements, &count_nodes/1))
  end

  defp count_nodes({:map, _meta, pairs}) when is_list(pairs) do
    1 + Enum.sum(Enum.flat_map(pairs, fn {k, v} -> [count_nodes(k), count_nodes(v)] end))
  end

  defp count_nodes({:loop, _meta, children}) when is_list(children) do
    1 + Enum.sum(Enum.map(children, &count_nodes/1))
  end

  defp count_nodes({:lambda, _meta, children}) when is_list(children) do
    1 + Enum.sum(Enum.map(children, &count_nodes/1))
  end

  defp count_nodes({:collection_op, _meta, children}) when is_list(children) do
    1 + Enum.sum(Enum.map(children, &count_nodes/1))
  end

  defp count_nodes({:language_specific, _meta, _content}), do: 1
  defp count_nodes(_), do: 1

  @spec detect_layer(AST.meta_ast()) :: layer()
  defp detect_layer(ast) do
    if contains_native?(ast) do
      :native
    else
      if contains_extended?(ast) do
        :extended
      else
        :core
      end
    end
  end

  @spec contains_native?(AST.meta_ast()) :: boolean()
  defp contains_native?({:language_specific, _meta, _content}), do: true

  defp contains_native?({:binary_op, _meta, [left, right]}) do
    contains_native?(left) || contains_native?(right)
  end

  defp contains_native?({:block, _meta, statements}) when is_list(statements) do
    Enum.any?(statements, &contains_native?/1)
  end

  defp contains_native?({_type, _meta, children}) when is_list(children) do
    Enum.any?(children, &contains_native?/1)
  end

  defp contains_native?(_), do: false

  @spec contains_extended?(AST.meta_ast()) :: boolean()
  defp contains_extended?({:loop, _meta, _children}), do: true
  defp contains_extended?({:lambda, _meta, _children}), do: true
  defp contains_extended?({:collection_op, _meta, _children}), do: true
  defp contains_extended?({:exception_handling, _meta, _children}), do: true

  defp contains_extended?({:binary_op, _meta, [left, right]}) do
    contains_extended?(left) || contains_extended?(right)
  end

  defp contains_extended?({:block, _meta, statements}) when is_list(statements) do
    Enum.any?(statements, &contains_extended?/1)
  end

  defp contains_extended?({_type, _meta, children}) when is_list(children) do
    Enum.any?(children, &contains_extended?/1)
  end

  defp contains_extended?(_), do: false
end
