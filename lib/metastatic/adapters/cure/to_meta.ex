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

  ## Cure v0.36.0 alignment

  The adapter tracks the current Cure grammar (v0.36.0). The
  normaliser is deliberately *structure-preserving*: every node type
  the Cure parser can emit is walked, its metadata coerced to a
  keyword list, and its children normalised recursively. Nothing is
  dropped, so `Metastatic.Adapters.Cure.FromMeta` can re-emit the
  original shape.

  The following Cure-specific concerns are handled explicitly:

    * **`:source_info` spans.** Cure v0.36.0 attaches a
      `%Cure.MetaAST.SourceInfo{}` struct to nearly every node. It is
      preserved under the namespaced key `:cure_source_info` (see
      `preserve_source_info?/1`) so tooling keeps byte-accurate spans
      without leaking a foreign struct into portable MetaAST.
    * **`:comment`.** Plain `#` comments and `##` doc comments are
      first-party nodes; `:comment_kind` defaults to `:line`.
    * **`:literal` `subtype: :bytes`.** Carries either a raw binary or
      a list of `:bin_segment` children (Cure v0.20.0+).
    * **`:bin_segment`.** Specifier keys (`:type`, `:signedness`,
      `:endianness`) are coerced to atoms when they arrive as strings.
    * **`:macro_def` rules.** Rule maps keep their `:template` /
      `:expander` ASTs normalised; opaque compiler bookkeeping keys
      (`:source_span`, `:body_span`, `:head_span`, `:field_spans`,
      `:segments`, `:obligations`, `:examples`) are stripped. The
      surviving `:segments` are distilled into a portable
      `{:lit, text}` / `{:hole, name}` / `{:repeat, seg}` /
      `{:optional, segs}` shape (see `distill_rule_segments/1`), so a
      printer can reconstruct the surface rule without the compiler's
      hole records.
    * **`:computed_use`.** The macro-expansion record for `fsm`, `sup`,
      `app` and other computed macros. Its very large `:syntax_segments`
      / `:syntax_field_types` bookkeeping is dropped, keeping the
      surface keyword, the distilled family grammar and the argument
      ASTs.
    * **`:with` / convoy pattern.** `with_abs` carries a scrutinee plus
      `:match_arm` children; the optional `proof` binder stays on
      metadata.
    * **`:with_rematch_arm`.** A `with` arm that restates its parent
      patterns (`Parent | WithPat -> …`). The restated patterns live in
      metadata and are normalised like any other subterm, so the
      printer can re-emit them.
    * **`:indexed_type` parameters.** `:params` / `:indices` hold
      `:param` nodes (or bare names); both are normalised.
    * **`:implementation` `for_type`.** The implemented type is a real
      AST node and is normalised.
    * **`:function_call` `:arg_labels`.** Cure records call-site labels
      (`g(a: 1)`) as a list of names/nils parallel to the arguments;
      the list is preserved verbatim.
    * **`:tactic_script` / `:tactic_computed_use`.** Raw invocation
      `%Cure.Compiler.Token{}` structs are flattened to portable
      `%{type:, value:, line:, col:}` maps so the printer can re-emit
      the author's own spelling without a foreign struct.
  """

  alias Metastatic.Adapters.Cure.Subprocess, as: CureSubProcess
  alias Metastatic.AST

  @typedoc "Opaque Cure source code."
  @type source :: String.t()

  @typedoc "The MetaAST produced by this adapter."
  @type meta_ast :: AST.meta_ast()

  @typedoc "M1 metadata preserved for round-tripping."
  @type metadata :: map()

  # Metadata keys that hold a `%Cure.MetaAST.SourceInfo{}` span struct.
  @source_info_key :source_info

  # Metadata keys whose values are already-normalised AST nodes. Every
  # other metadata value is passed through untouched (it is scalar or
  # opaque compiler bookkeeping).
  @ast_meta_keys [
    :type,
    :return_type,
    :for_type,
    :for,
    :pattern,
    :guard,
    :init,
    :payload,
    :params,
    :indices,
    :decorator,
    :template,
    :expander,
    :elab,
    # `with` rematch arms keep the restated parent patterns in meta
    # (`Parent | WithPat -> …`); they are ordinary subterms.
    :parent_patterns,
    # `assignment` carries an optional `:type_annotation` subterm.
    :type_annotation,
    # `receive … after <timeout>` stores `{timeout_expr, timeout_body}`.
    :timeout,
    # `:param` defaults are full expressions (`x: Int = f(y)`).
    :default
  ]

  # Opaque compiler bookkeeping carried on `:macro_def` rule maps. The
  # `:segments` list is *not* dropped: it is distilled into a portable
  # shape that the printer needs to re-emit the rule's surface form.
  @macro_rule_opaque_keys [
    :source_span,
    :body_span,
    :head_span,
    :field_spans,
    :obligations,
    :examples,
    :module_rule,
    :progress,
    :category,
    :line
  ]

  # Opaque expansion bookkeeping carried on `:computed_use` nodes.
  @computed_use_opaque_keys [
    :syntax_segments,
    :syntax_field_types,
    :syntax_fields,
    :syntax_repeated_fields,
    :syntax_type,
    :productions,
    :name_span,
    :home_source,
    :file
  ]

  # Keys on a rule map whose values are raw token lists (a `tactic` rule's
  # captured body). They are flattened into portable maps, never walked as
  # AST.
  @macro_rule_token_keys [:tactic_body_tokens]

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
        Path.expand("../../cure-lang/_build/#{Mix.env()}/lib/cure/ebin", File.cwd!()),
        Path.expand("../../cure-lang/_build/dev/lib/cure/ebin", File.cwd!()),
        Path.expand("../../Cure/cure/_build/#{Mix.env()}/lib/cure/ebin", File.cwd!()),
        Path.expand("../../Cure/cure/_build/dev/lib/cure/ebin", File.cwd!())
      ] ++
        Path.wildcard(Path.join(File.cwd!(), "_build/*/lib/cure/ebin")) ++
        Path.wildcard(Path.expand("../../cure-lang/_build/*/lib/*/ebin", File.cwd!())) ++
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
                load_beams(files)
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

  @doc """
  Load Cure's own beams from `{filename, binary}` entries, in the shape
  returned by `:zip.extract/2` with `:memory` (typically the archive of the
  `cure` escript).

  Only modules named `Cure.*` / `Elixir.Cure.*` are considered, and a module
  is loaded only when none of that name is already loaded or reachable on the
  code path.

  The escript embeds Cure's dependencies as well, including a possibly older
  copy of Metastatic. Loading those over the host's modules (for example
  `Metastatic.Adapters.Cure`) would silently downgrade this library at
  runtime, so they are never loaded.

  Returns the list of modules that were actually loaded.

  ## Examples

      iex> Metastatic.Adapters.Cure.ToMeta.load_beams([
      ...>   {~c"cure/ebin/Elixir.Metastatic.Adapters.Cure.beam", "not a beam"},
      ...>   {~c"cure/priv/std/option.cure", "mod Option"}
      ...> ])
      []
  """
  @spec load_beams([{charlist() | String.t(), binary()}]) :: [module()]
  def load_beams(files) when is_list(files) do
    Enum.flat_map(files, fn {filename, data} ->
      fname = to_string(filename)
      mod_str = Path.basename(fname, ".beam")

      if cure_beam?(fname, mod_str), do: load_beam(mod_str, fname, data), else: []
    end)
  end

  defp cure_beam?(fname, mod_str) do
    String.ends_with?(fname, ".beam") and
      (String.starts_with?(mod_str, "Elixir.Cure") or String.starts_with?(mod_str, "Cure")) and
      not (String.starts_with?(mod_str, "Elixir.Metastatic") or
             String.starts_with?(mod_str, "Metastatic"))
  end

  defp load_beam(mod_str, fname, data) do
    mod_name = String.to_atom(mod_str)

    if module_available?(mod_name) do
      []
    else
      case :code.load_binary(mod_name, String.to_charlist(fname), data) do
        {:module, ^mod_name} -> [mod_name]
        _ -> []
      end
    end
  end

  defp module_available?(module) do
    :code.is_loaded(module) != false or :code.which(module) != :non_existing
  end

  # --- Source -> MetaAST -------------------------------------------------

  @doc """
  Parse a Cure source fragment into a canonical MetaAST.

  Returns `{:ok, meta_ast, metadata}` on success, `{:error, reason}`
  otherwise. `metadata` is a map reserved for M1-specific
  round-trip hints; it is currently `%{language: :cure}`.

  When the Cure compiler's `Cure.Compiler.Lexer` /
  `Cure.Compiler.Parser` modules are not linked in at runtime the
  function returns `{:error, :cure_not_available}` instead of
  attempting to parse. Call `available?/0` to probe ahead of time.

  ## Options

    * `:preserve_comments` -- when `true` (the default here) plain `#`
      comments are kept as `:comment` nodes. Pass `false` to drop them.
    * `:preserve_source_info` -- when `true`, the full
      `%Cure.MetaAST.SourceInfo{}` span is retained under
      `:cure_source_info`. Defaults to `true`.
  """
  @spec from_source(source(), keyword()) ::
          {:ok, meta_ast(), metadata()} | {:error, term()}
  def from_source(source, opts \\ []) when is_binary(source) and is_list(opts) do
    if available?() do
      preserve_comments? = Keyword.get(opts, :preserve_comments, true)

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
        {:ok, normalize(ast, opts), %{language: :cure}}
      end
    else
      case CureSubProcess.parse(source, opts) do
        {:ok, ast} ->
          {:ok, normalize(ast, opts), %{language: :cure}}

        {:error, _reason} ->
          {:error, :cure_not_available}
      end
    end
  end

  # --- AST -> MetaAST ----------------------------------------------------

  @doc """
  Normalise an already-parsed Cure AST into canonical MetaAST.

  This is a structure-preserving pass that guarantees:

  - every node's metadata is a keyword list (even when empty);
  - `%Cure.MetaAST.SourceInfo{}` spans are moved to `:cure_source_info`
    (or dropped when `preserve_source_info: false`);
  - `:comment` nodes carry a `:comment_kind` metadata key (defaults to
    `:line`);
  - `:literal` nodes with `subtype: :bytes` keep either their raw
    binary payload or their `:bin_segment` children;
  - `:bin_segment` specifier atoms are coerced from strings;
  - `:macro_def` rule maps are normalised and stripped of opaque
    compiler bookkeeping;
  - `:computed_use` nodes drop their large expansion tables;
  - `:param` lists stored in `:function_def` / `:lambda` metadata are
    recursively normalised.

  Nodes unknown to MetaAST are passed through unchanged so analyzers
  can use `Metastatic.AST.conforms?/1` to surface them.
  """
  @spec from_ast(meta_ast(), keyword()) :: meta_ast()
  def from_ast(ast, opts \\ []), do: normalize(ast, opts)

  @doc """
  Compact alias for `from_ast/2`.
  """
  @spec normalize(meta_ast() | term(), keyword()) :: meta_ast() | term()
  def normalize(ast, opts \\ [])

  def normalize({:comment, meta, text}, opts) when is_binary(text) do
    meta =
      meta
      |> clean_meta(opts)
      |> Keyword.put_new(:comment_kind, :line)

    {:comment, meta, text}
  end

  def normalize({:literal, meta, value}, opts) do
    meta = clean_meta(meta, opts)

    case Keyword.get(meta, :subtype) do
      :bytes when is_list(value) ->
        {:literal, meta, Enum.map(value, &normalize(&1, opts))}

      _ ->
        {:literal, meta, value}
    end
  end

  def normalize({:bin_segment, meta, [value]}, opts) do
    meta =
      meta
      |> clean_meta(opts)
      |> normalize_bin_segment_meta(&normalize(&1, opts))

    {:bin_segment, meta, [normalize(value, opts)]}
  end

  def normalize({:function_def, meta, body}, opts) when is_list(body) do
    meta =
      meta
      |> clean_meta(opts)
      |> normalize_params_meta(opts)
      |> normalize_ast_meta_keys(opts)

    {:function_def, meta, Enum.map(body, &normalize(&1, opts))}
  end

  def normalize({:lambda, meta, body}, opts) when is_list(body) do
    meta =
      meta
      |> clean_meta(opts)
      |> normalize_params_meta(opts)
      |> normalize_ast_meta_keys(opts)

    {:lambda, meta, Enum.map(body, &normalize(&1, opts))}
  end

  def normalize({:match_arm, meta, body}, opts) when is_list(body) do
    meta =
      meta
      |> clean_meta(opts)
      |> normalize_ast_meta_keys(opts)

    {:match_arm, meta, Enum.map(body, &normalize(&1, opts))}
  end

  # A `with`-abstraction arm that restates its parent patterns
  # (`Parent | WithPat -> body`). Both the restated patterns and the
  # with-pattern live in metadata; the children are the arm body.
  def normalize({:with_rematch_arm, meta, body}, opts) when is_list(body) do
    meta =
      meta
      |> clean_meta(opts)
      |> normalize_ast_meta_keys(opts)

    {:with_rematch_arm, meta, Enum.map(body, &normalize(&1, opts))}
  end

  # `with <scrut> [proof <name>]` — the convoy pattern. The `:proof`
  # binder name is a plain string; children are the scrutinee and arms.
  def normalize({:with_abs, meta, children}, opts) when is_list(children) do
    meta =
      meta
      |> clean_meta(opts)
      |> normalize_ast_meta_keys(opts)

    {:with_abs, meta, Enum.map(children, &normalize(&1, opts))}
  end

  # `receive … after <timeout>` keeps `{timeout_expr, timeout_body}` in
  # metadata; both halves are subterms.
  def normalize({:async_operation, meta, children}, opts) when is_list(meta) do
    meta =
      meta
      |> clean_meta(opts)
      |> normalize_timeout(opts)
      |> normalize_ast_meta_keys(opts)

    {:async_operation, meta, normalize_children(children, opts)}
  end

  # `type Name(params) indices (…)` — `:params` / `:indices` are `:param`
  # nodes (or bare names) and `:decorator` is a `:decorator` node.
  def normalize({:indexed_type, meta, body}, opts) when is_list(meta) do
    meta =
      meta
      |> clean_meta(opts)
      |> normalize_params_meta(opts)
      |> normalize_indices_meta(opts)
      |> normalize_ast_meta_keys(opts)

    {:indexed_type, meta, normalize_children(body, opts)}
  end

  # `implementation Interface for Type [as Alias]` — `:for_type` is a real
  # AST node; `:interface` / `:for` / `:as` are names.
  def normalize({:implementation, meta, body}, opts) when is_list(meta) do
    meta =
      meta
      |> clean_meta(opts)
      |> normalize_ast_meta_keys(opts)

    {:implementation, meta, normalize_children(body, opts)}
  end

  # `interface Name(params) requires A, B` — `:params` / `:requires` hold
  # names or type expressions; `:defaults` is a name-keyed map of ASTs.
  def normalize({:interface, meta, body}, opts) when is_list(meta) do
    meta =
      meta
      |> clean_meta(opts)
      |> normalize_ast_meta_keys(opts)
      |> normalize_defaults_meta(opts)

    {:interface, meta, normalize_children(body, opts)}
  end

  # A tactic invocation (`by close`, `because finish h`). The captured
  # invocation tokens are compiler structs; flatten them so the printer can
  # re-emit the author's spelling without a foreign struct leaking through.
  def normalize({type, meta, children}, opts)
      when type in [:tactic_script, :tactic_computed_use] and is_list(meta) do
    meta =
      meta
      |> clean_meta(opts)
      |> normalize_token_meta(:tactic_use_tokens)
      |> normalize_ast_meta_keys(opts)

    {type, meta, normalize_children(children, opts)}
  end

  def normalize({:variable, meta, name}, opts) when is_binary(name) or is_atom(name) do
    {:variable, clean_meta(meta, opts), name}
  end

  def normalize({:param, meta, name}, opts) when is_binary(name) or is_atom(name) do
    normalize_param({:param, meta, name}, opts)
  end

  def normalize({:macro_def, meta, rules}, opts) when is_list(rules) do
    meta = clean_meta(meta, opts)

    normalized_rules =
      Enum.map(rules, fn
        rule when is_map(rule) -> normalize_macro_rule(rule, opts)
        other -> normalize(other, opts)
      end)

    {:macro_def, meta, normalized_rules}
  end

  def normalize({:computed_use, meta, children}, opts) when is_list(meta) do
    grammar = extract_family_grammar(meta)
    header = extract_header_segments(meta)

    meta =
      meta
      |> clean_meta(opts)
      |> Keyword.drop(@computed_use_opaque_keys)
      |> maybe_put_grammar(grammar)
      |> maybe_put_header(header)

    {:computed_use, meta, normalize_children(children, opts)}
  end

  def normalize({type, meta, children}, opts) when is_atom(type) and is_list(children) do
    meta =
      meta
      |> clean_meta(opts)
      |> normalize_ast_meta_keys(opts)

    {type, meta, Enum.map(children, &normalize(&1, opts))}
  end

  def normalize({type, meta, value}, opts) when is_atom(type) and is_list(meta) do
    meta =
      meta
      |> clean_meta(opts)
      |> normalize_ast_meta_keys(opts)

    {type, meta, value}
  end

  def normalize(:_, _opts), do: :_
  def normalize(other, _opts), do: other

  # --- Internals ---------------------------------------------------------

  defp normalize_children(children, opts) when is_list(children) do
    Enum.map(children, &normalize(&1, opts))
  end

  defp normalize_children(other, _opts), do: other

  # Move `%Cure.MetaAST.SourceInfo{}` under `:cure_source_info` (or drop
  # it), and guarantee a keyword list.
  defp clean_meta(meta, opts) when is_list(meta) do
    preserve? = Keyword.get(opts, :preserve_source_info, true)

    meta
    |> Enum.reject(fn
      {@source_info_key, _} -> true
      _ -> false
    end)
    |> maybe_put_source_info(meta, preserve?)
  end

  defp clean_meta(nil, _opts), do: []
  defp clean_meta(_other, _opts), do: []

  defp maybe_put_source_info(cleaned, original, true) do
    case Keyword.get(original, @source_info_key) do
      nil -> cleaned
      info -> Keyword.put(cleaned, :cure_source_info, info)
    end
  end

  defp maybe_put_source_info(cleaned, _original, false), do: cleaned

  # The Cure parser always produces canonical atoms, but accept string
  # values as a defensive measure when the AST was round-tripped through
  # JSON / an external tool.
  defp normalize_bin_segment_meta(meta, normalize_fun) do
    meta
    |> normalize_meta_value(:size, normalize_fun)
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

  # Normalise only the metadata keys that are known to hold AST nodes.
  defp normalize_ast_meta_keys(meta, opts) do
    Enum.reduce(@ast_meta_keys, meta, fn key, acc ->
      case Keyword.get(acc, key) do
        nil -> acc
        value -> Keyword.put(acc, key, normalize(value, opts))
      end
    end)
  end

  defp normalize_params_meta(meta, opts) do
    case Keyword.get(meta, :params) do
      nil ->
        meta

      params when is_list(params) ->
        Keyword.put(meta, :params, Enum.map(params, &normalize_param(&1, opts)))

      _ ->
        meta
    end
  end

  defp normalize_param({:param, meta, name}, opts) when is_binary(name) or is_atom(name) do
    meta =
      meta
      |> clean_meta(opts)
      |> normalize_ast_meta_keys(opts)

    {:param, meta, name}
  end

  defp normalize_param(name, _opts) when is_binary(name) or is_atom(name),
    do: {:param, [], name}

  defp normalize_param(other, opts), do: normalize(other, opts)

  # `indexed_type` indices are `:param` nodes exactly like `function_def`
  # parameters (a bare name when the index is untyped).
  defp normalize_indices_meta(meta, opts) do
    case Keyword.get(meta, :indices) do
      nil ->
        meta

      indices when is_list(indices) ->
        Keyword.put(meta, :indices, Enum.map(indices, &normalize_param(&1, opts)))

      _ ->
        meta
    end
  end

  # `receive … after <timeout>` stores `{timeout_expr, timeout_body}`.
  defp normalize_timeout(meta, opts) do
    case Keyword.get(meta, :timeout) do
      {timeout_expr, timeout_body} ->
        Keyword.put(
          meta,
          :timeout,
          {normalize(timeout_expr, opts), normalize(timeout_body, opts)}
        )

      _ ->
        meta
    end
  end

  # `interface` default method bodies are a name-keyed map of ASTs.
  defp normalize_defaults_meta(meta, opts) do
    case Keyword.get(meta, :defaults) do
      defaults when is_map(defaults) and map_size(defaults) > 0 ->
        normalized = Map.new(defaults, fn {k, v} -> {k, normalize(v, opts)} end)
        Keyword.put(meta, :defaults, normalized)

      _ ->
        meta
    end
  end

  # Raw `%Cure.Compiler.Token{}` lists (a tactic rule's captured body, a
  # tactic use-site's invocation) are flattened to portable maps. Nothing
  # else in MetaAST is allowed to carry a foreign struct.
  defp normalize_token_meta(meta, key) do
    case Keyword.get(meta, key) do
      tokens when is_list(tokens) ->
        Keyword.put(meta, key, Enum.map(tokens, &flatten_token/1))

      _ ->
        meta
    end
  end

  defp flatten_token(%{__struct__: _} = token) do
    %{
      type: Map.get(token, :type),
      value: Map.get(token, :value),
      line: Map.get(token, :line),
      col: Map.get(token, :col)
    }
  end

  defp flatten_token(other), do: other

  # `:macro_def` rules are plain maps carrying AST templates plus opaque
  # compiler bookkeeping. Keep the former, drop the latter, and distill the
  # rule's `:segments` into a portable shape the printer can re-emit.
  defp normalize_macro_rule(rule, opts) do
    rule
    |> Map.drop(@macro_rule_opaque_keys)
    |> normalize_map_key(:template, opts)
    |> normalize_map_key(:expander, opts)
    |> normalize_map_key(:elab, opts)
    |> normalize_map_key(:source_span, opts)
    |> distill_rule_segments_key()
    |> normalize_rule_token_keys()
  end

  defp distill_rule_segments_key(rule) do
    case Map.get(rule, :segments) do
      segments when is_list(segments) -> Map.put(rule, :segments, distill_rule_segments(segments))
      _ -> rule
    end
  end

  defp normalize_rule_token_keys(rule) do
    Enum.reduce(@macro_rule_token_keys, rule, fn key, acc ->
      case Map.get(acc, key) do
        tokens when is_list(tokens) -> Map.put(acc, key, Enum.map(tokens, &flatten_token/1))
        _ -> acc
      end
    end)
  end

  # A rule's matched segments are compiler hole records. Distill them to the
  # portable vocabulary the printer understands:
  #
  #     {:lit, text} | {:hole, name} | {:repeat, seg} | {:optional, [seg]}
  #
  # which is exactly what `FromMeta` needs to rebuild the surface rule.
  defp distill_rule_segments(segments) when is_list(segments) do
    Enum.map(segments, &distill_rule_segment/1)
  end

  defp distill_rule_segment({:lit, text}) when is_binary(text), do: {:lit, text}
  defp distill_rule_segment({:hole, %{name: name}}), do: {:hole, name}
  defp distill_rule_segment({:code_hole, %{name: name}}), do: {:hole, name}
  defp distill_rule_segment({:raw_hole, %{name: name}}), do: {:hole, name}
  defp distill_rule_segment({:declarations_hole, %{name: name}}), do: {:hole, name}
  defp distill_rule_segment({:family, %{name: name}}), do: {:hole, name}
  defp distill_rule_segment({:repeat, segment}), do: {:repeat, distill_rule_segment(segment)}

  defp distill_rule_segment({:optional, segments}) when is_list(segments),
    do: {:optional, Enum.map(segments, &distill_rule_segment/1)}

  defp distill_rule_segment(other), do: other

  defp normalize_map_key(map, key, opts) do
    case Map.get(map, key) do
      nil -> map
      val -> Map.put(map, key, normalize(val, opts))
    end
  end

  # --- Family grammar distillation --------------------------------------

  # A `:computed_use` node carries the whole macro-expansion record. Its
  # `:syntax_segments` holds the family grammar that produced the surface
  # form; the grammar's `:productions` are the only place the literal
  # separators (`--`, `-->`, `as`, ...) survive, so they must be preserved
  # for the printer to reconstruct the original rows.
  #
  # We distill it to a compact shape:
  #
  #     %{family => %{field => [%{fields: [name], segments: [...]}]}}
  #
  # where each segment is `{:lit, binary}` or `{:hole, name}`.
  defp extract_family_grammar(meta) do
    case Keyword.get(meta, :syntax_segments) do
      segments when is_list(segments) ->
        segments
        |> Enum.filter(&match?({:family, _}, &1))
        |> Enum.reduce(%{}, fn {:family, family}, acc ->
          Map.merge(acc, distill_family(family))
        end)

      _ ->
        %{}
    end
  end

  defp distill_family(family) when is_map(family) do
    name = Map.get(family, :name)

    fields =
      family
      |> Map.get(:fields, [])
      |> Enum.reduce(%{}, fn field, acc ->
        case distill_field(field) do
          nil -> acc
          {field_name, productions} -> Map.put(acc, field_name, productions)
        end
      end)

    case {name, fields} do
      {nil, _} -> %{}
      {_, empty} when map_size(empty) == 0 -> %{}
      {_, _} -> %{name => fields}
    end
  end

  defp distill_family(_), do: %{}

  defp distill_field(field) when is_map(field) do
    grammar = Map.get(field, :grammar)
    name = Map.get(field, :name)

    case grammar do
      %{} ->
        productions =
          grammar
          |> Map.get(:productions, [])
          |> Enum.map(&distill_production/1)
          |> Enum.reject(&is_nil/1)

        field_names = grammar |> Map.get(:fields, []) |> Enum.map(&Map.get(&1, :name))
        field_records = grammar |> Map.get(:fields, []) |> Enum.map(&distill_field_record/1)

        case {productions, field_names} do
          {[], []} ->
            nil

          _ ->
            {name, %{productions: productions, fields: field_names, field_records: field_records}}
        end

      _ ->
        nil
    end
  end

  defp distill_field(_), do: nil

  # The declared shape / cardinality of one family field. The printer needs
  # them to tell a `repeated` row (`repeated terminal Red`) from a header
  # value, and an `optional when Expression` continuation clause from a
  # production field.
  defp distill_field_record(field) when is_map(field) do
    %{
      name: Map.get(field, :name),
      shape: Map.get(field, :shape),
      cardinality: Map.get(field, :cardinality, :required)
    }
  end

  defp distill_field_record(other), do: other

  defp distill_production(production) when is_map(production) do
    segments =
      production
      |> Map.get(:segments, [])
      |> Enum.map(&distill_segment/1)
      |> Enum.reject(&is_nil/1)

    %{
      fields: Map.get(production, :fields, []),
      segments: segments
    }
  end

  defp distill_production(_), do: nil

  defp distill_segment({:lit, lit}) when is_binary(lit), do: {:lit, lit}
  defp distill_segment({:hole, %{name: name}}), do: {:hole, name}
  defp distill_segment(_), do: nil

  defp maybe_put_grammar(meta, grammar) when map_size(grammar) == 0, do: meta
  defp maybe_put_grammar(meta, grammar), do: Keyword.put(meta, :family_grammar, grammar)

  # The macro *header* grammar (`fsm <name> with <data>`) lives in the
  # `:syntax_segments` list alongside the family record. Preserve its
  # `{:lit, _}` / `{:hole, _}` / `{:family, _}` shape so the printer can
  # re-emit keywords such as `with` that the argument AST does not carry.
  defp extract_header_segments(meta) do
    case Keyword.get(meta, :syntax_segments) do
      segments when is_list(segments) ->
        Enum.map(segments, fn
          {:lit, lit} when is_binary(lit) -> {:lit, lit}
          {:hole, %{name: name}} -> {:hole, name}
          {:family, %{name: name}} -> {:family, name}
          _ -> nil
        end)
        |> Enum.reject(&is_nil/1)

      _ ->
        []
    end
  end

  defp maybe_put_header(meta, []), do: meta
  defp maybe_put_header(meta, header), do: Keyword.put(meta, :header_segments, header)
end
