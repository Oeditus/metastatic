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
  defp filter_composite_children({:binary_op, category, op, left, right}, layer) do
    filtered_left = filter_by_layer(left, layer)
    filtered_right = filter_by_layer(right, layer)

    if filtered_left || filtered_right do
      {:binary_op, category, op, filtered_left || left, filtered_right || right}
    else
      nil
    end
  end

  defp filter_composite_children({:block, statements}, layer) do
    filtered_statements =
      statements
      |> Enum.map(&filter_by_layer(&1, layer))
      |> Enum.reject(&is_nil/1)

    if Enum.empty?(filtered_statements) do
      nil
    else
      {:block, filtered_statements}
    end
  end

  defp filter_composite_children(ast, _layer), do: ast

  @spec node_layer(AST.meta_ast()) :: layer()
  defp node_layer({:literal, _, _}), do: :core
  defp node_layer({:variable, _}), do: :core
  defp node_layer({:binary_op, _, _, _, _}), do: :core
  defp node_layer({:unary_op, _, _, _}), do: :core
  defp node_layer({:function_call, _, _}), do: :core
  defp node_layer({:conditional, _, _, _}), do: :core
  defp node_layer({:block, _}), do: :core
  defp node_layer({:early_return, _, _}), do: :core
  defp node_layer({:loop, _, _, _}), do: :extended
  defp node_layer({:loop, _, _, _, _}), do: :extended
  defp node_layer({:lambda, _, _, _}), do: :extended
  defp node_layer({:collection_op, _, _, _}), do: :extended
  defp node_layer({:collection_op, _, _, _, _}), do: :extended
  defp node_layer({:exception_handling, _, _, _}), do: :extended
  defp node_layer({:language_specific, _, _, _}), do: :native
  defp node_layer(_), do: :core

  @spec composite_node?(AST.meta_ast()) :: boolean()
  defp composite_node?({:binary_op, _, _, _, _}), do: true
  defp composite_node?({:unary_op, _, _, _}), do: true
  defp composite_node?({:function_call, _, _}), do: true
  defp composite_node?({:conditional, _, _, _}), do: true
  defp composite_node?({:block, _}), do: true
  defp composite_node?({:loop, _, _, _}), do: true
  defp composite_node?({:loop, _, _, _, _}), do: true
  defp composite_node?({:lambda, _, _, _}), do: true
  defp composite_node?({:collection_op, _, _, _}), do: true
  defp composite_node?({:collection_op, _, _, _, _}), do: true
  defp composite_node?({:exception_handling, _, _, _}), do: true
  defp composite_node?(_), do: false

  @spec calculate_depth(AST.meta_ast()) :: non_neg_integer()
  defp calculate_depth({:literal, _, _}), do: 1
  defp calculate_depth({:variable, _}), do: 1

  defp calculate_depth({:binary_op, _, _, left, right}) do
    1 + max(calculate_depth(left), calculate_depth(right))
  end

  defp calculate_depth({:unary_op, _, _, operand}) do
    1 + calculate_depth(operand)
  end

  defp calculate_depth({:function_call, _, args}) do
    if Enum.empty?(args) do
      1
    else
      1 + (Enum.map(args, &calculate_depth/1) |> Enum.max())
    end
  end

  defp calculate_depth({:conditional, condition, then_branch, else_branch}) do
    depths = [calculate_depth(condition), calculate_depth(then_branch)]

    depths =
      if else_branch do
        depths ++ [calculate_depth(else_branch)]
      else
        depths
      end

    1 + Enum.max(depths)
  end

  defp calculate_depth({:block, statements}) do
    if Enum.empty?(statements) do
      1
    else
      1 + (Enum.map(statements, &calculate_depth/1) |> Enum.max())
    end
  end

  defp calculate_depth({:loop, _, condition, body}) do
    1 + max(calculate_depth(condition), calculate_depth(body))
  end

  defp calculate_depth({:loop, _, iterator, collection, body}) do
    1 + Enum.max([calculate_depth(iterator), calculate_depth(collection), calculate_depth(body)])
  end

  defp calculate_depth({:lambda, _params, _captures, body}) do
    1 + calculate_depth(body)
  end

  defp calculate_depth({:collection_op, _, lambda, collection}) do
    1 + max(calculate_depth(lambda), calculate_depth(collection))
  end

  defp calculate_depth({:collection_op, _, lambda, collection, initial}) do
    1 + Enum.max([calculate_depth(lambda), calculate_depth(collection), calculate_depth(initial)])
  end

  defp calculate_depth({:language_specific, _, _, _}), do: 1
  defp calculate_depth(_), do: 1

  @spec count_nodes(AST.meta_ast()) :: non_neg_integer()
  defp count_nodes({:literal, _, _}), do: 1
  defp count_nodes({:variable, _}), do: 1

  defp count_nodes({:binary_op, _, _, left, right}) do
    1 + count_nodes(left) + count_nodes(right)
  end

  defp count_nodes({:unary_op, _, _, operand}) do
    1 + count_nodes(operand)
  end

  defp count_nodes({:function_call, _, args}) do
    1 + Enum.sum(Enum.map(args, &count_nodes/1))
  end

  defp count_nodes({:conditional, condition, then_branch, else_branch}) do
    base = 1 + count_nodes(condition) + count_nodes(then_branch)

    if else_branch do
      base + count_nodes(else_branch)
    else
      base
    end
  end

  defp count_nodes({:block, statements}) do
    1 + Enum.sum(Enum.map(statements, &count_nodes/1))
  end

  defp count_nodes({:loop, _, condition, body}) do
    1 + count_nodes(condition) + count_nodes(body)
  end

  defp count_nodes({:loop, _, iterator, collection, body}) do
    1 + count_nodes(iterator) + count_nodes(collection) + count_nodes(body)
  end

  defp count_nodes({:lambda, _params, _captures, body}) do
    1 + count_nodes(body)
  end

  defp count_nodes({:collection_op, _, lambda, collection}) do
    1 + count_nodes(lambda) + count_nodes(collection)
  end

  defp count_nodes({:collection_op, _, lambda, collection, initial}) do
    1 + count_nodes(lambda) + count_nodes(collection) + count_nodes(initial)
  end

  defp count_nodes({:language_specific, _, _, _}), do: 1
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
  defp contains_native?({:language_specific, _, _, _}), do: true

  defp contains_native?({:binary_op, _, _, left, right}) do
    contains_native?(left) || contains_native?(right)
  end

  defp contains_native?({:block, statements}) do
    Enum.any?(statements, &contains_native?/1)
  end

  defp contains_native?(_), do: false

  @spec contains_extended?(AST.meta_ast()) :: boolean()
  defp contains_extended?({:loop, _, _, _}), do: true
  defp contains_extended?({:loop, _, _, _, _}), do: true
  defp contains_extended?({:lambda, _, _, _}), do: true
  defp contains_extended?({:collection_op, _, _, _}), do: true
  defp contains_extended?({:collection_op, _, _, _, _}), do: true
  defp contains_extended?({:exception_handling, _, _, _}), do: true

  defp contains_extended?({:binary_op, _, _, left, right}) do
    contains_extended?(left) || contains_extended?(right)
  end

  defp contains_extended?({:block, statements}) do
    Enum.any?(statements, &contains_extended?/1)
  end

  defp contains_extended?(_), do: false
end
