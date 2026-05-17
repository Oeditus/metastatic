defmodule Metastatic.Semantic.Enricher do
  @moduledoc """
  AST enricher for semantic metadata injection.

  This module provides functions to enrich MetaAST nodes with semantic
  metadata. Two kinds of enrichment are performed:

  1. **`op_kind`** on `:function_call` nodes -- classifies calls by
     semantic domain (database, HTTP, queue, ...) using registered patterns.
  2. **`callback_for`** on `:function_def` nodes -- tags functions that
     implement a known behaviour/base-class callback (e.g., `Oban.Worker`
     `perform/1`, `ActiveJob::Base` `perform`).

  ## Usage

  ### Single Node Enrichment

      alias Metastatic.Semantic.Enricher

      # Enrich a single function_call node
      enriched = Enricher.enrich(node, :elixir)

  ### Full Tree Enrichment

      # Enrich all nodes in an AST tree (including callback_for)
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

  Enrichment is **eager** -- all applicable nodes are enriched in a single
  pass. This ensures semantic information is available immediately for
  analyzers.

  The tree traversal is context-aware: when entering a `:container` node,
  the enricher collects behaviours declared via `:import` children (e.g.,
  `use Oban.Worker`) and `:parent` metadata (e.g., Ruby class inheritance).
  These behaviours are then matched against the `Semantic.Callbacks`
  registry to annotate enclosed `:function_def` nodes.
  """

  alias Metastatic.AST
  alias Metastatic.Semantic.{Callbacks, Patterns}

  @typedoc "Language identifier for pattern matching"
  @type language :: Patterns.language()

  @typedoc "Traversal accumulator carrying container context"
  @type enricher_acc :: %{
          language: language(),
          behaviours: [String.t()]
        }

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
  Enriches a `:function_def` node with `callback_for` metadata.

  When the function matches a known callback for one of the given
  behaviours, the node's metadata is annotated with
  `callback_for: "BehaviourModule"`.

  This is called internally by `enrich_tree/2` with the behaviours
  collected from the enclosing `:container`. Can also be called
  directly when the set of behaviours is known.

  ## Parameters

  - `node` - A `:function_def` MetaAST node
  - `language` - Source language atom
  - `behaviours` - List of behaviour/base-class module name strings

  ## Examples

      iex> node = {:function_def, [name: "perform", params: [{:param, [], "job"}], visibility: :public, arity: 1], []}
      iex> enriched = Enricher.enrich_callback(node, :elixir, ["Oban.Worker"])
      iex> Keyword.get(elem(enriched, 1), :callback_for)
      "Oban.Worker"
  """
  @spec enrich_callback(AST.meta_ast(), language(), [String.t()]) :: AST.meta_ast()
  def enrich_callback({:function_def, meta, _children} = node, language, behaviours)
      when is_list(meta) and is_list(behaviours) do
    func_name = Keyword.get(meta, :name, "")
    arity = Keyword.get(meta, :arity)

    case find_matching_behaviour(language, behaviours, func_name, arity) do
      nil -> node
      behaviour -> AST.put_meta(node, :callback_for, behaviour)
    end
  end

  def enrich_callback(node, _language, _behaviours), do: node

  @doc """
  Enriches an entire AST tree with semantic metadata.

  Traverses the AST and enriches all applicable nodes. This is the
  recommended way to enrich AST during adapter transformations.

  The traversal is context-aware:
  - On entering a `:container` node, collects behaviours from its
    `:import` children and `:parent` metadata.
  - On leaving a `:function_def` inside such a container, checks
    `Callbacks.lookup/4` and adds `callback_for:` if matched.
  - On leaving a `:function_call`, adds `op_kind:` if matched.

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
    initial_acc = %{language: language, behaviours: []}

    {enriched, _acc} =
      AST.traverse(
        ast,
        initial_acc,
        # Pre: collect behaviours when entering containers
        &pre_enrich/2,
        # Post: enrich function_call (op_kind) and function_def (callback_for)
        &post_enrich/2
      )

    enriched
  end

  @doc """
  Checks if a node has been enriched with semantic metadata.

  Returns `true` if the node carries `op_kind` or `callback_for`.

  ## Examples

      iex> node = {:function_call, [name: "Repo.get", op_kind: [domain: :db, operation: :retrieve]], []}
      iex> Enricher.enriched?(node)
      true

      iex> node = {:function_def, [name: "perform", callback_for: "Oban.Worker"], []}
      iex> Enricher.enriched?(node)
      true

      iex> node = {:function_call, [name: "unknown"], []}
      iex> Enricher.enriched?(node)
      false
  """
  @spec enriched?(AST.meta_ast()) :: boolean()
  def enriched?({_type, meta, _children}) when is_list(meta) do
    Keyword.has_key?(meta, :op_kind) or Keyword.has_key?(meta, :callback_for)
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

  @doc """
  Gets the callback_for value from a node, if present.

  ## Examples

      iex> node = {:function_def, [name: "perform", callback_for: "Oban.Worker"], []}
      iex> Enricher.get_callback_for(node)
      "Oban.Worker"

      iex> node = {:function_def, [name: "run"], []}
      iex> Enricher.get_callback_for(node)
      nil
  """
  @spec get_callback_for(AST.meta_ast()) :: String.t() | nil
  def get_callback_for({_type, meta, _children}) when is_list(meta) do
    Keyword.get(meta, :callback_for)
  end

  def get_callback_for(_), do: nil

  # ----- Private Helpers -----

  # -- Traversal callbacks for enrich_tree --

  # Pre-pass: when entering a :container, extract behaviours from its
  # children (import nodes) and metadata (parent class).
  defp pre_enrich({:container, meta, children} = node, acc) when is_list(meta) do
    behaviours = extract_behaviours_from_container(meta, children)
    {node, %{acc | behaviours: behaviours}}
  end

  defp pre_enrich(node, acc), do: {node, acc}

  # Post-pass: enrich function_call (op_kind), function_def (callback_for),
  # and reset behaviours when leaving a container.
  defp post_enrich({:function_def, _meta, _children} = node, acc) do
    enriched = enrich_callback(node, acc.language, acc.behaviours)
    {enrich(enriched, acc.language), acc}
  end

  defp post_enrich({:container, _meta, _children} = node, acc) do
    # Reset behaviours when leaving the container scope
    {enrich(node, acc.language), %{acc | behaviours: []}}
  end

  defp post_enrich(node, acc) do
    {enrich(node, acc.language), acc}
  end

  # Extract behaviour module names from a container's children and metadata.
  # Sources:
  #   1. :import children with import_type :use or :import whose source
  #      is a known behaviour in the Callbacks registry
  #   2. :parent metadata on the container itself (Ruby/Python inheritance)
  defp extract_behaviours_from_container(meta, children) when is_list(children) do
    language = Keyword.get(meta, :language)
    known = if language, do: Callbacks.behaviours_for_language(language), else: []

    import_behaviours =
      children
      |> Enum.flat_map(fn
        {:import, import_meta, _} when is_list(import_meta) ->
          source = Keyword.get(import_meta, :source, "")
          import_type = Keyword.get(import_meta, :import_type)

          if import_type in [:use, :import, :require, :include] and source in known do
            [source]
          else
            []
          end

        _ ->
          []
      end)

    # Ruby/Python: parent class is also a potential behaviour source
    parent = Keyword.get(meta, :parent)
    parent_behaviours = if is_binary(parent) and parent in known, do: [parent], else: []

    Enum.uniq(import_behaviours ++ parent_behaviours)
  end

  defp extract_behaviours_from_container(_meta, _children), do: []

  # Find the first behaviour in the list that declares a callback matching
  # the given function name and arity.
  defp find_matching_behaviour(language, behaviours, func_name, arity) do
    Enum.find(behaviours, fn behaviour ->
      Callbacks.callback?(language, behaviour, func_name, arity)
    end)
  end

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
