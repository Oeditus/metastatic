defmodule Metastatic.Adapter.Plugin do
  @moduledoc """
  `use` macro for third-party language adapters.

  A host application adds a language by writing one module and registering it.
  This macro removes the boilerplate from both halves:

      # my_app/lib/my_app/adapters/rust.ex
      defmodule MyApp.Adapters.Rust do
        use Metastatic.Adapter.Plugin,
          language: :rust,
          extensions: [".rs"]

        @impl true
        def parse(source), do: MyApp.Adapters.Rust.Bridge.parse(source)

        @impl true
        def to_meta(ast), do: MyApp.Adapters.Rust.ToMeta.transform(ast)

        @impl true
        def from_meta(meta_ast, metadata),
          do: MyApp.Adapters.Rust.FromMeta.transform(meta_ast, metadata)

        @impl true
        def unparse(ast), do: MyApp.Adapters.Rust.Bridge.unparse(ast)
      end

  Then register it at boot — no edit to Metastatic, no recompile:

      children = [
        {Metastatic.Adapter.Registry, plugins: [MyApp.Adapters.Rust]}
      ]

  ## What the macro injects

    * `@behaviour Metastatic.Adapter`, so `Metastatic.Adapter.valid_adapter?/1`
      and the structural contract test apply unchanged;
    * `file_extensions/0` from the `:extensions` option;
    * `__metastatic_language__/0`, `__metastatic_plugin_opts__/0` and
      `__metastatic_plugin__/0` so the registry can read the descriptor without
      guessing from the module name.

  ## Options

    * `:language` (required) — the language atom, e.g. `:rust`
    * `:extensions` (required) — dot-prefixed extensions, e.g. `[".rs"]`
    * `:experimental?` — flag the language as experimental (default `false`)
    * `:documentation?` — flag it as a document language (default `false`)

  ## Semantic enrichment

  The macro does **not** inject `to_meta/1`: that callback is where an adapter
  builds its MetaAST, and wrapping it would hide the transformation. Call
  `Metastatic.Semantic.Enricher.enrich_tree/2` at the end of your `to_meta`
  (as the built-in adapters do), or return the tree unenriched.

  The pattern tables for your language are registered through
  `Metastatic.Semantic.ensure_registered/0`; see
  `config :metastatic, :semantic, pattern_providers: [...]`.

  ## Why not register automatically?

  `@after_compile` registration was considered and rejected: it makes module
  load order significant, registers adapters from *any* loaded module
  (including test fixtures), and cannot report a failure anywhere useful.
  Explicit registration at boot is one line and is greppable.
  """

  @doc """
  Injects the adapter behaviour and the descriptor callbacks.

  See the module documentation for the options and an example.
  """
  @spec __using__(keyword()) :: Macro.t()
  defmacro __using__(opts) do
    language = Keyword.fetch!(opts, :language)
    extensions = Keyword.fetch!(opts, :extensions)
    experimental? = Keyword.get(opts, :experimental?, false)
    documentation? = Keyword.get(opts, :documentation?, false)

    validate_options!(language, extensions)

    quote do
      @behaviour Metastatic.Adapter

      @metastatic_language unquote(language)
      @metastatic_plugin_opts [
        extensions: unquote(extensions),
        experimental?: unquote(experimental?),
        documentation?: unquote(documentation?)
      ]

      @impl true
      def file_extensions, do: unquote(extensions)

      @doc false
      @spec __metastatic_language__() :: atom()
      def __metastatic_language__, do: @metastatic_language

      @doc false
      @spec __metastatic_plugin_opts__() :: keyword()
      def __metastatic_plugin_opts__, do: @metastatic_plugin_opts

      @doc false
      @spec __metastatic_plugin__() :: %{
              language: atom(),
              adapter: module(),
              extensions: [String.t()],
              experimental?: boolean(),
              documentation?: boolean()
            }
      def __metastatic_plugin__ do
        %{
          language: @metastatic_language,
          adapter: __MODULE__,
          extensions: unquote(extensions),
          experimental?: unquote(experimental?),
          documentation?: unquote(documentation?)
        }
      end
    end
  end

  # Fails at compile time of the *plug-in*, which is where the mistake is,
  # rather than at boot of the host application.
  defp validate_options!(language, extensions) do
    unless is_atom(language) do
      raise ArgumentError,
            "Metastatic.Adapter.Plugin expects :language to be an atom, got: #{inspect(language)}"
    end

    unless is_list(extensions) and extensions != [] do
      raise ArgumentError,
            "Metastatic.Adapter.Plugin expects :extensions to be a non-empty list, " <>
              "got: #{inspect(extensions)}"
    end

    Enum.each(extensions, fn ext ->
      unless is_binary(ext) and String.starts_with?(ext, ".") do
        raise ArgumentError,
              "Metastatic.Adapter.Plugin expects dot-prefixed extensions (e.g. \".rs\"), " <>
                "got: #{inspect(ext)}"
      end
    end)
  end
end
