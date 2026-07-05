defmodule Metastatic.Adapters.Elixir.MacroExpander do
  @moduledoc """
  Full macro expansion for the Elixir adapter using ExPanda.

  This module takes a surface-level Elixir AST (from `Code.string_to_quoted/1`)
  and produces a fully expanded AST where every macro has been resolved, while
  annotating expansion boundaries with the original surface form so that the
  `FromMeta` transformer can reconstruct macros faithfully.

  ## How It Works

  1. Parse the surface AST via `Code.string_to_quoted/1` (done upstream)
  2. Expand the AST fully with `ExPanda.expand/1`
  3. Walk both ASTs in parallel (`annotate/2`):
     - **Structural match** (same form atom): recurse into children pairwise
     - **Macro boundary** (different form atoms): tag the expanded node with
       `__original_macro__: surface_node` in its Elixir AST metadata
     - **Leaf/literal match**: return expanded as-is
  4. Return the annotated expanded AST

  The `__original_macro__` annotation is later propagated by `ToMeta` into
  the MetaAST keyword metadata as `:original_macro`, and consumed by `FromMeta`
  to restore the original macro call during round-tripping.

  ## Examples

      iex> {:ok, surface} = Code.string_to_quoted("unless true, do: :never")
      iex> {:ok, annotated} = MacroExpander.expand_and_annotate(surface)
      iex> {form, meta, _args} = annotated
      iex> form
      :case
      iex> Keyword.has_key?(meta, :__original_macro__)
      true

  """

  @doc """
  Expand all macros in `surface_ast` via ExPanda and annotate expansion points.

  Returns `{:ok, annotated_ast}` where every node that resulted from a macro
  expansion carries `__original_macro__: original_surface_node` in its
  Elixir AST metadata keyword list.

  ## Options

  - `:env` - custom `Macro.Env` to pass to ExPanda (default: fresh env)
  - `:file` - file path for error messages (default: `"nofile"`)

  ## Examples

      iex> {:ok, surface} = Code.string_to_quoted("1 |> to_string()")
      iex> {:ok, annotated} = MacroExpander.expand_and_annotate(surface)
      iex> match?({{:., _, _}, _, _}, annotated)
      true
  """
  @spec expand_and_annotate(Macro.t(), keyword()) ::
          {:ok, Macro.t()} | {:error, term()}
  def expand_and_annotate(surface_ast, opts \\ []) do
    case ExPanda.expand(surface_ast, opts) do
      {:ok, expanded_ast} ->
        annotated = annotate(surface_ast, expanded_ast)
        {:ok, annotated}

      {:error, _reason} = error ->
        error
    end
  end

  @doc """
  Expand all macros in a source string and return the annotated AST.

  Convenience wrapper that parses + expands + annotates in one step.

  ## Examples

      iex> {:ok, annotated} = MacroExpander.expand_and_annotate_string("unless true, do: :never")
      iex> {form, meta, _} = annotated
      iex> form
      :case
      iex> is_list(Keyword.get(meta, :__original_macro__))
      false
  """
  @spec expand_and_annotate_string(String.t(), keyword()) ::
          {:ok, Macro.t()} | {:error, term()}
  def expand_and_annotate_string(source, opts \\ []) do
    case Code.string_to_quoted(source) do
      {:ok, surface_ast} ->
        expand_and_annotate(surface_ast, opts)

      {:error, _} = error ->
        error
    end
  end

  # -------------------------------------------------------------------
  # Parallel walk: annotate expansion boundaries
  # -------------------------------------------------------------------

  # Both are identical literals/atoms -- no expansion happened
  defp annotate(same, same), do: same

  # Both are 3-tuples with the SAME form atom -- structural match, recurse
  defp annotate(
         {form, _s_meta, s_args} = _surface,
         {form, e_meta, e_args} = _expanded
       )
       when is_atom(form) and is_list(e_args) do
    annotated_args = annotate_children(s_args, e_args)
    {form, e_meta, annotated_args}
  end

  # Structural forms with different metadata but same form -- handled above.
  # This clause catches structural forms where children diverged in shape
  # (e.g. defmodule body changed due to `use` expansion).
  # We still recurse pairwise into do/end blocks.

  # Remote call structural match: both are {{:., ...}, meta, args}
  # Recurse into the dot-tuple and the args pairwise.
  defp annotate(
         {{:., _s_dot_meta, s_dot_args}, _s_meta, s_args},
         {{:., e_dot_meta, e_dot_args}, e_meta, e_args}
       )
       when is_list(e_meta) and is_list(e_args) do
    annotated_dot_args = annotate_children(s_dot_args, e_dot_args)
    annotated_args = annotate_children(s_args, e_args)
    {{:., e_dot_meta, annotated_dot_args}, e_meta, annotated_args}
  end

  # Different form atoms -- MACRO BOUNDARY
  # Tag the expanded node with the original surface form.
  defp annotate(
         {_s_form, _s_meta, _s_args} = surface,
         {e_form, e_meta, e_args}
       )
       when is_atom(e_form) and is_list(e_meta) do
    tagged_meta = [{:__original_macro__, surface} | e_meta]
    {e_form, tagged_meta, e_args}
  end

  # Surface is an atom-form call, expanded is a remote call (e.g. pipe -> Module.func)
  # This is a macro boundary.
  defp annotate(
         {s_form, _s_meta, _s_args} = surface,
         {e_dot_tuple, e_meta, e_args}
       )
       when is_atom(s_form) and is_tuple(e_dot_tuple) and is_list(e_meta) do
    tagged_meta = [{:__original_macro__, surface} | e_meta]
    {e_dot_tuple, tagged_meta, e_args}
  end

  # Lists -- recurse element-wise when lengths match
  defp annotate(s_list, e_list) when is_list(s_list) and is_list(e_list) do
    annotate_children(s_list, e_list)
  end

  # 2-element tuples (keyword pairs, etc.)
  defp annotate({s_k, s_v}, {e_k, e_v}) do
    {annotate(s_k, e_k), annotate(s_v, e_v)}
  end

  # Fallback -- use expanded as-is (different shapes, can't correlate)
  defp annotate(_surface, expanded), do: expanded

  # -------------------------------------------------------------------
  # Children annotation helpers
  # -------------------------------------------------------------------

  # Same-length lists: pairwise annotate
  defp annotate_children(s_args, e_args)
       when is_list(s_args) and is_list(e_args) and length(s_args) == length(e_args) do
    Enum.zip_with(s_args, e_args, &annotate/2)
  end

  # When surface args is nil (e.g. variable node) but expanded has a list
  defp annotate_children(nil, e_args) when is_list(e_args), do: e_args

  # Different-length lists
  # Try to match by keyword keys for do/end blocks, otherwise use expanded.
  defp annotate_children(s_args, e_args)
       when is_list(s_args) and is_list(e_args) do
    if keyword_list?(s_args) and keyword_list?(e_args) do
      annotate_keyword_lists(s_args, e_args)
    else
      # Best effort: annotate the prefix that has matching length,
      # then append remaining expanded elements as-is
      annotate_partial(s_args, e_args)
    end
  end

  # Catch-all
  defp annotate_children(_s_args, e_args), do: e_args

  # Annotate keyword lists by matching keys (for do/end/rescue/after blocks)
  defp annotate_keyword_lists(s_kw, e_kw) do
    Enum.map(e_kw, fn {key, e_val} ->
      case List.keyfind(s_kw, key, 0) do
        {^key, s_val} -> {key, annotate(s_val, e_val)}
        nil -> {key, e_val}
      end
    end)
  end

  # Annotate as many elements as we can pair up, then append the rest
  defp annotate_partial(s_args, e_args) do
    min_len = min(length(s_args), length(e_args))
    {s_prefix, _s_rest} = Enum.split(s_args, min_len)
    {e_prefix, e_rest} = Enum.split(e_args, min_len)
    annotated_prefix = Enum.zip_with(s_prefix, e_prefix, &annotate/2)
    annotated_prefix ++ e_rest
  end

  # -------------------------------------------------------------------
  # Utilities
  # -------------------------------------------------------------------

  defp keyword_list?([{key, _val} | _rest]) when is_atom(key), do: true
  defp keyword_list?(_), do: false
end
