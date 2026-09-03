defmodule Metastatic.Adapters.Cure.ToMeta do
  @moduledoc """
  Transform Cure source / Cure AST (M1) into MetaAST (M2).

  This is the abstraction function α_Cure that lifts a Cure program
  to the meta-level. Unlike the Python / Ruby / Haskell adapters --
  which marshal a foreign-language AST through a subprocess -- the
  Cure compiler already emits 3-tuples in the MetaAST shape because
  MetaAST was designed as Cure's primary AST. This module therefore
  does only two jobs:

    1. invoke the Cure compiler's lexer + parser (when it is linked in
       at runtime);
    2. normalise any lingering adapter-specific metadata so the result
       round-trips cleanly through `Metastatic.AST.conforms?/1`.

  When the `Cure.Compiler.Lexer` / `Cure.Compiler.Parser` modules are
  not available at runtime (e.g. Metastatic is used as a library in a
  host project that does not depend on Cure) the `from_source/2`
  entry point returns `{:error, :cure_not_available}`. The
  `normalize/1` entry point -- which accepts an already-parsed AST --
  works unconditionally.

  ## Entry Points

  - `from_source/2` -- parse Cure source into a canonical MetaAST.
  - `from_ast/1` -- normalise an already-parsed Cure AST.
  - `normalize/1` -- compact alias for `from_ast/1`.

  ## v0.20.0 Notes

  Cure v0.20.0 added `:bin_segment` and `:comment` node types plus the
  segment-list payload for `{:literal, [subtype: :bytes], ...}`. All
  three are part of the MetaAST M2.1 core layer, so this adapter does
  not need to rewrite them -- it only walks the tree to ensure every
  3-tuple has a keyword-list metadata in the second position (the
  Cure parser emits `[]` when no metadata applies, which is already
  canonical).
  """

  alias Metastatic.Adapters.Cure.Subprocess, as: CureSubProcess
  alias Metastatic.AST

  @typedoc "Opaque Cure source code."
  @type source :: String.t()

  @typedoc "The MetaAST produced by this adapter."
  @type meta_ast :: AST.meta_ast()

  @typedoc "M1 metadata preserved for round-tripping (currently empty)."
  @type metadata :: map()

  @doc """
  Return `true` if the Cure compiler is available at runtime.
  """
  @spec available?() :: boolean()
  def available? do
    ensure_cure_compiler() == :ok
  end

  @doc """
  Ensure Cure compiler modules are loaded into the VM.
  Attempts dynamic discovery of Cure ebin directories or escript/executable
  if Cure is not already loaded.
  """
  @spec ensure_cure_compiler() :: :ok | {:error, :cure_not_available}
  def ensure_cure_compiler do
    cond do
      cure_loaded?() ->
        :ok

      try_load_ebin_paths() ->
        :ok

      try_load_from_cure_executable() ->
        :ok

      true ->
        {:error, :cure_not_available}
    end
  end

  defp cure_loaded? do
    :code.is_loaded(Cure.Compiler.Lexer) != false or
      (match?({:module, _}, Code.ensure_compiled(Cure.Compiler.Lexer)) and
         match?({:module, _}, Code.ensure_compiled(Cure.Compiler.Parser)))
  end

  defp try_load_ebin_paths do
    possible_paths =
      [
        Path.join(File.cwd!(), "_build/#{Mix.env()}/lib/cure/ebin"),
        Path.join(File.cwd!(), "deps/cure/ebin"),
        Path.expand("../../Cure/cure/_build/#{Mix.env()}/lib/cure/ebin", File.cwd!()),
        Path.expand("../../Cure/cure/_build/dev/lib/cure/ebin", File.cwd!())
      ] ++
        Path.wildcard(Path.join(File.cwd!(), "_build/*/lib/cure/ebin")) ++
        Path.wildcard(Path.expand("../../Cure/cure/_build/*/lib/*/ebin", File.cwd!()))

    Enum.each(possible_paths, fn path ->
      if File.dir?(path) do
        Code.append_path(path)
      end
    end)

    cure_loaded?()
  end

  defp try_load_from_cure_executable do
    cure_bin = System.find_executable("cure") || "../../Cure/cure/cure"

    if File.exists?(cure_bin) do
      try do
        case :escript.extract(String.to_charlist(cure_bin), []) do
          {:ok, sections} ->
            case Keyword.get(sections, :archive) do
              nil ->
                false

              zip_bin ->
                {:ok, files} = :zip.extract(zip_bin, [:memory])

                for {filename, data} <- files do
                  fname = to_string(filename)

                  if String.ends_with?(fname, ".beam") and
                       (String.contains?(fname, "Cure") or String.contains?(fname, "cure")) do
                    mod_name = fname |> Path.basename(".beam") |> String.to_atom()
                    :code.load_binary(mod_name, String.to_charlist(fname), data)
                  end
                end

                cure_loaded?()
            end

          _ ->
            false
        end
      rescue
        _ -> false
      end
    else
      false
    end
  end

  # --- Source -> MetaAST -------------------------------------------------

  @doc """
  Parse a Cure source fragment into a canonical MetaAST.

  Returns `{:ok, meta_ast, metadata}` on success, `{:error, reason}`
  otherwise. `metadata` is a map reserved for future M1-specific
  round-trip hints; it is currently `%{language: :cure}`.

  When the Cure compiler's `Cure.Compiler.Lexer` /
  `Cure.Compiler.Parser` modules are not linked in at runtime the
  function returns `{:error, :cure_not_available}` instead of
  attempting to parse. Call `available?/0` to probe ahead of time.
  """
  @spec from_source(source(), keyword()) ::
          {:ok, meta_ast(), metadata()} | {:error, term()}
  def from_source(source, opts \\ []) when is_binary(source) and is_list(opts) do
    if available?() do
      preserve_comments? = Keyword.get(opts, :preserve_comments, false)

      # credo:disable-for-lines:13
      with {:ok, tokens} <-
             apply(Cure.Compiler.Lexer, :tokenize, [
               source,
               [emit_events: false, preserve_comments: preserve_comments?]
             ]),
           {:ok, ast} <-
             apply(Cure.Compiler.Parser, :parse, [
               tokens,
               [emit_events: false]
             ]) do
        {:ok, normalize(ast), %{language: :cure}}
      end
    else
      case CureSubProcess.parse(source) do
        {:ok, ast} ->
          {:ok, normalize(ast), %{language: :cure}}

        {:error, _reason} ->
          {:error, :cure_not_available}
      end
    end
  end

  # --- AST -> MetaAST ----------------------------------------------------

  @doc """
  Normalise an already-parsed Cure AST into canonical MetaAST.

  The Cure parser already emits 3-tuples with keyword metadata, so
  this is effectively a structure-preserving pass that ensures:

  - the metadata list is always a keyword list (even when empty);
  - `:literal` nodes with `subtype: :bytes` keep either their raw
    binary payload or their `:bin_segment` children (v0.20.0+);
  - `:comment` nodes carry a `:comment_kind` metadata key (defaults
    to `:line` when the parser did not set one);
  - `:param` lists stored in `:function_def` / `:lambda` metadata are
    recursively normalised.

  Nodes unknown to MetaAST are passed through unchanged so analyzers
  can use `Metastatic.AST.conforms?/1` to surface them.
  """
  @spec from_ast(meta_ast()) :: meta_ast()
  def from_ast(ast), do: normalize(ast)

  @spec normalize(meta_ast() | term()) :: meta_ast() | term()
  def normalize({:comment, meta, text}) when is_binary(text) do
    meta = meta |> to_keyword_list() |> Keyword.put_new(:comment_kind, :line)
    {:comment, meta, text}
  end

  def normalize({:literal, meta, value}) do
    meta = to_keyword_list(meta)

    case Keyword.get(meta, :subtype) do
      :bytes when is_list(value) ->
        {:literal, meta, Enum.map(value, &normalize/1)}

      _ ->
        {:literal, meta, value}
    end
  end

  def normalize({:bin_segment, meta, [value]}) do
    meta = normalize_bin_segment_meta(to_keyword_list(meta))
    {:bin_segment, meta, [normalize(value)]}
  end

  def normalize({:function_def, meta, body}) when is_list(body) do
    meta =
      meta
      |> to_keyword_list()
      |> normalize_params_meta()
      |> normalize_meta_value(:return_type, &normalize/1)
      |> normalize_meta_value(:for_type, &normalize/1)

    {:function_def, meta, Enum.map(body, &normalize/1)}
  end

  def normalize({:lambda, meta, body}) when is_list(body) do
    meta =
      meta
      |> to_keyword_list()
      |> normalize_params_meta()
      |> normalize_meta_value(:return_type, &normalize/1)

    {:lambda, meta, Enum.map(body, &normalize/1)}
  end

  def normalize({:match_arm, meta, body}) when is_list(body) do
    meta =
      meta
      |> to_keyword_list()
      |> normalize_meta_value(:pattern, &normalize/1)
      |> normalize_meta_value(:guard, &normalize/1)

    {:match_arm, meta, Enum.map(body, &normalize/1)}
  end

  def normalize({:variable, meta, name}) when is_binary(name) do
    {:variable, to_keyword_list(meta), name}
  end

  def normalize({type, meta, children}) when is_atom(type) and is_list(children) do
    meta =
      meta
      |> to_keyword_list()
      |> normalize_meta_value(:type, &normalize/1)
      |> normalize_meta_value(:return_type, &normalize/1)
      |> normalize_meta_value(:pattern, &normalize/1)
      |> normalize_meta_value(:guard, &normalize/1)
      |> normalize_meta_value(:for_type, &normalize/1)

    {type, meta, Enum.map(children, &normalize/1)}
  end

  def normalize({type, meta, value}) when is_atom(type) and is_list(meta) do
    meta =
      meta
      |> normalize_meta_value(:type, &normalize/1)
      |> normalize_meta_value(:return_type, &normalize/1)
      |> normalize_meta_value(:pattern, &normalize/1)
      |> normalize_meta_value(:guard, &normalize/1)
      |> normalize_meta_value(:for_type, &normalize/1)

    {type, meta, value}
  end

  def normalize(:_), do: :_
  def normalize(other), do: other

  # --- Internals ---------------------------------------------------------

  defp to_keyword_list(meta) when is_list(meta), do: meta
  defp to_keyword_list(nil), do: []
  defp to_keyword_list(_), do: []

  # The Cure parser always produces canonical atoms, but accept string
  # values as a defensive measure when the AST was round-tripped through
  # JSON / an external tool.
  defp normalize_bin_segment_meta(meta) do
    meta
    |> normalize_meta_value(:size, &normalize/1)
    |> coerce_atom_meta(:type)
    |> coerce_atom_meta(:signedness)
    |> coerce_atom_meta(:endianness)
  end

  defp coerce_atom_meta(meta, key) do
    case Keyword.get(meta, key) do
      nil -> meta
      value when is_atom(value) -> meta
      value when is_binary(value) -> Keyword.put(meta, key, String.to_atom(value))
      _ -> meta
    end
  end

  defp normalize_meta_value(meta, key, fun) do
    case Keyword.get(meta, key) do
      nil -> meta
      value -> Keyword.put(meta, key, fun.(value))
    end
  end

  defp normalize_params_meta(meta) do
    case Keyword.get(meta, :params) do
      nil ->
        meta

      params when is_list(params) ->
        Keyword.put(meta, :params, Enum.map(params, &normalize_param/1))

      _ ->
        meta
    end
  end

  defp normalize_param({:param, meta, name}) when is_binary(name) do
    meta =
      meta
      |> to_keyword_list()
      |> normalize_meta_value(:pattern, &normalize/1)
      |> normalize_meta_value(:default, &normalize/1)
      |> normalize_meta_value(:type, &normalize/1)

    {:param, meta, name}
  end

  defp normalize_param(name) when is_binary(name), do: {:param, [], name}
  defp normalize_param(other), do: other
end
