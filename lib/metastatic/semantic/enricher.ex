defmodule Metastatic.Semantic.Enricher do
  @moduledoc """
  AST enricher for semantic metadata injection.

  This module provides functions to enrich MetaAST nodes with semantic
  operation metadata (`op_kind`). It is designed to be called during
  adapter transformations (in `to_meta`) to eagerly annotate function
  calls with their semantic meaning.

  ## Usage

  ### Single Node Enrichment

      alias Metastatic.Semantic.Enricher

      # Enrich a single function_call node
      enriched = Enricher.enrich(node, :elixir)

  ### Full Tree Enrichment

      # Enrich all nodes in an AST tree
      enriched_ast = Enricher.enrich_tree(ast, :python)

  ## Integration with Adapters

  The enricher should be called at the end of the `to_meta` transformation:

      def transform(native_ast) do
        with {:ok, meta_ast, metadata} <- do_transform(native_ast) do
          enriched = Enricher.enrich_tree(meta_ast, :python)
          {:ok, enriched, metadata}
        end
      end

  ## Enrichment Strategy

  Enrichment is **eager** - all applicable nodes are enriched in a single pass.
  This ensures semantic information is available immediately for analyzers.

  Only `:function_call` nodes are currently enriched. The enricher:
  1. Extracts the function name from metadata
  2. Matches against registered patterns for the source language
  3. If matched, adds `op_kind` to the node's metadata
  4. Extracts target entity from arguments when possible
  """

  alias Metastatic.AST
  alias Metastatic.Semantic.Patterns

  @typedoc "Language identifier for pattern matching"
  @type language :: Patterns.language()

  # ----- Public API -----

  @doc """
  Enriches a single MetaAST node with semantic metadata.

  If the node is a `:function_call` and matches a known pattern for the
  given language, adds `op_kind` metadata. Otherwise returns the node unchanged.

  ## Parameters

  - `node` - The MetaAST node to enrich
  - `language` - The source language for pattern matching

  ## Examples

      iex> node = {:function_call, [name: "Repo.get"], [{:variable, [], "User"}, {:literal, [subtype: :integer], 1}]}
      iex> enriched = Enricher.enrich(node, :elixir)
      iex> Keyword.get(elem(enriched, 1), :op_kind)
      [domain: :db, operation: :retrieve, target: "User", async: false, framework: :ecto]
  """
  @spec enrich(AST.meta_ast(), language()) :: AST.meta_ast()
  def enrich({:function_call, meta, args} = node, language) when is_list(meta) do
    name = Keyword.get(meta, :name, "")

    case Patterns.match(name, language, args) do
      {:ok, op_kind} ->
        AST.put_meta(node, :op_kind, op_kind)

      :no_match ->
        node
    end
  end

  # Handle attribute access with method call (e.g., user.save(), Model.objects.get())
  def enrich(
        {:attribute_access, meta, [receiver, {:function_call, call_meta, args}]} = node,
        language
      )
      when is_list(meta) and is_list(call_meta) do
    # Build full method name: receiver.method
    method_name = Keyword.get(call_meta, :name, "")
    receiver_name = extract_receiver_name(receiver)
    full_name = build_full_name(receiver_name, method_name)

    case Patterns.match(full_name, language, args, receiver) do
      {:ok, op_kind} ->
        # Add op_kind to the outer attribute_access node
        AST.put_meta(node, :op_kind, op_kind)

      :no_match ->
        node
    end
  end

  def enrich(node, _language), do: node

  @doc """
  Enriches an entire AST tree with semantic metadata.

  Traverses the AST and enriches all applicable nodes. This is the
  recommended way to enrich AST during adapter transformations.

  ## Parameters

  - `ast` - The root MetaAST node
  - `language` - The source language for pattern matching

  ## Examples

      iex> ast = {:block, [], [
      ...>   {:function_call, [name: "Repo.get"], [{:variable, [], "User"}, {:literal, [subtype: :integer], 1}]},
      ...>   {:function_call, [name: "Repo.all"], [{:variable, [], "Post"}]}
      ...> ]}
      iex> enriched = Enricher.enrich_tree(ast, :elixir)
      iex> {:block, [], [call1, call2]} = enriched
      iex> Keyword.get(elem(call1, 1), :op_kind) |> Keyword.get(:operation)
      :retrieve
      iex> Keyword.get(elem(call2, 1), :op_kind) |> Keyword.get(:operation)
      :retrieve_all
  """
  @spec enrich_tree(AST.meta_ast(), language()) :: AST.meta_ast()
  def enrich_tree(ast, language) do
    {enriched, _acc} =
      AST.traverse(
        ast,
        nil,
        # Pre: no-op
        fn node, acc -> {node, acc} end,
        # Post: enrich after children are processed
        fn node, acc -> {enrich(node, language), acc} end
      )

    enriched
  end

  @doc """
  Checks if a node has been enriched with semantic metadata.

  ## Examples

      iex> node = {:function_call, [name: "Repo.get", op_kind: [domain: :db, operation: :retrieve]], []}
      iex> Enricher.enriched?(node)
      true

      iex> node = {:function_call, [name: "unknown"], []}
      iex> Enricher.enriched?(node)
      false
  """
  @spec enriched?(AST.meta_ast()) :: boolean()
  def enriched?({_type, meta, _children}) when is_list(meta) do
    Keyword.has_key?(meta, :op_kind)
  end

  def enriched?(_), do: false

  @doc """
  Gets the op_kind from a node, if present.

  ## Examples

      iex> node = {:function_call, [name: "Repo.get", op_kind: [domain: :db, operation: :retrieve]], []}
      iex> Enricher.get_op_kind(node)
      [domain: :db, operation: :retrieve]

      iex> node = {:function_call, [name: "unknown"], []}
      iex> Enricher.get_op_kind(node)
      nil
  """
  @spec get_op_kind(AST.meta_ast()) :: Metastatic.Semantic.OpKind.t() | nil
  def get_op_kind({_type, meta, _children}) when is_list(meta) do
    Keyword.get(meta, :op_kind)
  end

  def get_op_kind(_), do: nil

  # ----- Private Helpers -----

  # Extract receiver name from an AST node
  defp extract_receiver_name({:variable, _meta, name}) when is_binary(name), do: name

  defp extract_receiver_name({:literal, _meta, value}) when is_atom(value),
    do: Atom.to_string(value)

  defp extract_receiver_name({:literal, _meta, value}) when is_binary(value), do: value

  defp extract_receiver_name({:attribute_access, _meta, children}) when is_list(children) do
    # Recursive extraction for chained access: a.b.c
    children
    |> Enum.map(&extract_receiver_name/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.join(".")
  end

  defp extract_receiver_name({:function_call, meta, _args}) when is_list(meta) do
    # For method chains like Model.objects.get()
    Keyword.get(meta, :name)
  end

  defp extract_receiver_name(_), do: nil

  # Build full method name from receiver and method
  defp build_full_name(nil, method), do: method
  defp build_full_name("", method), do: method
  defp build_full_name(receiver, method), do: "#{receiver}.#{method}"
end
