defmodule Metastatic.MetaAST do
  @moduledoc """
  Shared, language-agnostic core for MetaAST-shaped trees.

  Both `Metastatic.AST` (programming-language MetaAST) and
  `Metastatic.NL.AST` (natural-language MetaAST) model their trees as the same
  uniform 3-tuple:

      {type_atom, keyword_meta, children_or_value}

  This module owns the operations that are *identical* for both:

  - node accessors (`type/1`, `meta/1`, `children/1`)
  - metadata access (`get_meta/3`, `put_meta/3`, `update_meta/2`)
  - generic depth-first traversal (`traverse/4`, `prewalk/2`, `postwalk/2`)

  `Metastatic.AST` and `Metastatic.NL.AST` delegate here, so the two meta-ASTs
  can no longer drift apart in their shared surface. Domain-specific behaviour
  (conformance rules, type registries, builders, `to_string/1`, …) stays in the
  respective modules.

  ## Traversal contract

  `traverse/4` visits a node's metadata values as well as its children: any
  metadata value that is itself a node (or a list/keyword containing one) is
  traversed. This keeps subterms embedded in metadata — e.g. a `:coreference`
  target or a `:pattern` — visible to walkers. See `Metastatic.AST.traverse/4`
  for the precise invariant used by the programming-language side.
  """

  @typedoc "A uniform MetaAST node: `{type, metadata, children_or_value}`."
  @type t :: {atom(), keyword(), term()}

  # ----- Node accessors -----

  @doc "Returns the node type atom."
  @spec type(t()) :: atom()
  def type({type, _meta, _children}) when is_atom(type), do: type

  @doc "Returns the node's metadata keyword list."
  @spec meta(t()) :: keyword()
  def meta({_type, meta, _children}) when is_list(meta), do: meta

  @doc "Returns the node's children list or leaf value."
  @spec children(t()) :: term()
  def children({_type, _meta, children}), do: children

  # ----- Metadata access -----

  @doc "Gets a metadata value by key, with an optional default."
  @spec get_meta(t(), atom(), term()) :: term()
  def get_meta({_type, meta, _children}, key, default \\ nil) when is_atom(key) do
    Keyword.get(meta, key, default)
  end

  @doc "Puts a metadata value by key."
  @spec put_meta(t(), atom(), term()) :: t()
  def put_meta({type, meta, children}, key, value) when is_atom(key) do
    {type, Keyword.put(meta, key, value), children}
  end

  @doc "Merges a keyword list of metadata updates into the node."
  @spec update_meta(t(), keyword()) :: t()
  def update_meta({type, meta, children}, updates) when is_list(updates) do
    {type, Keyword.merge(meta, updates), children}
  end

  @doc """
  Updates a single metadata value with a function.

  The function receives the current value (or `default` when absent) and
  returns the new value.
  """
  @spec update_meta(t(), atom(), term(), (term() -> term())) :: t()
  def update_meta({type, meta, children}, key, default, fun)
      when is_atom(key) and is_function(fun, 1) do
    current = Keyword.get(meta, key, default)
    {type, Keyword.put(meta, key, fun.(current)), children}
  end

  @doc "Replaces a node's children/value."
  @spec update_children(t(), term()) :: t()
  def update_children({type, meta, _children}, new_children) do
    {type, meta, new_children}
  end

  # ----- Generic traversal -----

  @doc """
  Depth-first traversal with pre- and post-visit callbacks.

  `pre` runs before a node's descendants, `post` after. Both receive
  `{node, acc}` and must return `{node, acc}`. Metadata values that contain
  nodes are traversed too.
  """
  @spec traverse(t() | term(), acc, pre_fun, post_fun) :: {t() | term(), acc}
        when acc: term(),
             pre_fun: (t() | term(), acc -> {t() | term(), acc}),
             post_fun: (t() | term(), acc -> {t() | term(), acc})
  def traverse(ast, acc, pre, post) when is_function(pre, 2) and is_function(post, 2) do
    {ast, acc} = pre.(ast, acc)

    case ast do
      {type, meta, children} when is_atom(type) and is_list(meta) ->
        {meta, acc} = traverse_meta(meta, acc, pre, post)

        {children, acc} =
          if is_list(children) do
            Enum.map_reduce(children, acc, fn child, acc_in ->
              traverse(child, acc_in, pre, post)
            end)
          else
            {children, acc}
          end

        post.({type, meta, children}, acc)

      leaf ->
        post.(leaf, acc)
    end
  end

  @doc "Pre-order traversal (no accumulator)."
  @spec prewalk(t(), (t() -> t())) :: t()
  def prewalk(node, fun) when is_function(fun, 1) do
    {new_node, _} =
      traverse(node, nil, fn n, acc -> {fun.(n), acc} end, fn n, acc -> {n, acc} end)

    new_node
  end

  @doc "Post-order traversal (no accumulator)."
  @spec postwalk(t(), (t() -> t())) :: t()
  def postwalk(node, fun) when is_function(fun, 1) do
    {new_node, _} =
      traverse(node, nil, fn n, acc -> {n, acc} end, fn n, acc -> {fun.(n), acc} end)

    new_node
  end

  # ----- Lazy walkers & path -----

  @doc """
  Returns a lazy enumerable that walks the tree in depth-first pre-order.

  Mirrors `Macro.prewalker/1`: each node is yielded before its children.
  """
  @spec prewalker(t()) :: Enumerable.t()
  def prewalker(ast) do
    Stream.unfold([ast], fn
      [] -> nil
      [node | rest] -> {node, child_nodes(node) ++ rest}
    end)
  end

  @doc """
  Returns a lazy pre-order enumerable that threads an accumulator.

  Mirrors the `Macro.prewalker/2` shape: the caller supplies
  `fun.(node, acc) -> {yielded, acc}` which runs for each node in pre-order
  and returns the value to yield together with the next accumulator.

  ## Examples

      iex> ast = {:binary_op, [operator: :+],
      ...>   [{:literal, [subtype: :integer], 1}, {:literal, [subtype: :integer], 2}]}
      iex> ast |> Metastatic.MetaAST.prewalker(0, fn _n, acc -> {acc, acc + 1} end) |> Enum.to_list()
      [0, 1, 2]
  """
  @spec prewalker(t(), acc, (t(), acc -> {term(), acc})) :: Enumerable.t() when acc: term()
  def prewalker(ast, acc, fun) when is_function(fun, 2) do
    Stream.unfold({[ast], acc}, fn
      {[], _acc} ->
        nil

      {[node | rest], acc_in} ->
        {yielded, acc_out} = fun.(node, acc_in)
        {yielded, {child_nodes(node) ++ rest, acc_out}}
    end)
  end

  @doc """
  Returns the path from a matching node up to the root, or `nil`.

  The path starts with the matched node, followed by its parents up to the
  root. Mirrors `Macro.path/2`.

  ## Examples

      iex> ast = {:binary_op, [operator: :+],
      ...>   [{:variable, [], "x"}, {:literal, [subtype: :integer], 42}]}
      iex> path = Metastatic.MetaAST.path(ast, fn {:literal, _, 42} -> true; _ -> false end)
      iex> Enum.map(path, &Metastatic.MetaAST.type/1)
      [:literal, :binary_op]
  """
  @spec path(t(), (t() -> as_boolean(term()))) :: [t()] | nil
  def path(ast, fun) when is_function(fun, 1) do
    do_path(ast, fun)
  end

  defp do_path({type, meta, _children} = node, fun) when is_atom(type) and is_list(meta) do
    if fun.(node) do
      [node]
    else
      Enum.find_value(child_nodes(node), fn child ->
        case do_path(child, fun) do
          nil -> nil
          found -> found ++ [node]
        end
      end)
    end
  end

  defp do_path(_other, _fun), do: nil

  # Extracts child nodes from a node (skips leaf values).
  defp child_nodes({type, _meta, children})
       when is_atom(type) and type in [:literal, :variable, :comment, :token, :punctuation] do
    _ = children
    []
  end

  defp child_nodes({type, _meta, children}) when is_atom(type) and is_list(children) do
    Enum.filter(children, &node?/1)
  end

  defp child_nodes(_), do: []

  # ----- Private -----

  defp traverse_meta(meta, acc, pre, post) do
    if Keyword.keyword?(meta) do
      Enum.map_reduce(meta, acc, fn {key, val}, acc_in ->
        {new_val, acc_out} = traverse_meta_val(val, acc_in, pre, post)
        {{key, new_val}, acc_out}
      end)
    else
      {meta, acc}
    end
  end

  defp traverse_meta_val({type, meta, _} = node, acc, pre, post)
       when is_atom(type) and is_list(meta) do
    traverse(node, acc, pre, post)
  end

  defp traverse_meta_val(list, acc, pre, post) when is_list(list) do
    if Keyword.keyword?(list) or contains_node?(list) do
      Enum.map_reduce(list, acc, fn item, acc_in ->
        traverse_meta_val(item, acc_in, pre, post)
      end)
    else
      {list, acc}
    end
  end

  defp traverse_meta_val(other, acc, _pre, _post), do: {other, acc}

  defp contains_node?(list) when is_list(list), do: Enum.any?(list, &node?/1)

  defp node?({type, meta, _}) when is_atom(type) and is_list(meta), do: true
  defp node?(list) when is_list(list), do: contains_node?(list)
  defp node?(_), do: false
end
