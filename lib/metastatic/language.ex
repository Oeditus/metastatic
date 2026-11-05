defmodule Metastatic.Language do
  @moduledoc """
  Value object describing a single supported language.

  A `Metastatic.Language` bundles everything the rest of the system needs to
  know about a language in one place:

    * the language atom (`:python`, `:elixir`, ...)
    * the adapter module implementing `Metastatic.Adapter`
    * the file extensions the adapter claims
    * whether the language is *experimental* (needs an external toolchain)
    * whether the language describes *documents* rather than executable code
      (e.g. Markdown), so code-only passes can skip it

  ## Why a struct?

  Historically the metadata was spread across several compile-time maps inside
  `Metastatic.Languages`. Collapsing it into a single struct makes the registry
  a plain list of values that can be built by discovery, filtered, merged with
  config overrides, and inspected as data -- no more parallel maps to keep in
  sync.

  ## Examples

      iex> lang = Metastatic.Language.new(:python, Metastatic.Adapters.Python)
      iex> lang.language
      :python
      iex> lang.extensions
      [".py", ".pyw"]
      iex> lang.experimental?
      false
      iex> lang.documentation?
      false
  """

  @enforce_keys [:language, :adapter]
  defstruct [
    :language,
    :adapter,
    extensions: [],
    experimental?: false,
    documentation?: false
  ]

  @type t :: %__MODULE__{
          language: atom(),
          adapter: module(),
          extensions: [String.t()],
          experimental?: boolean(),
          documentation?: boolean()
        }

  @doc """
  Builds a language descriptor from a language atom and its adapter module.

  Extensions are read from the adapter's `file_extensions/0` callback. The
  `:experimental?` and `:documentation?` flags default to `false` and can be
  overridden through `opts`.

  ## Options

    * `:experimental?` -- `true` when the adapter needs an external toolchain
      outside the default CI matrix (default: `false`)
    * `:documentation?` -- `true` for document languages such as Markdown
      (default: `false`)
    * `:extensions` -- override the adapter's declared extensions (default: read
      from the adapter)

  ## Examples

      iex> Metastatic.Language.new(:agda, Metastatic.Adapters.Agda, experimental?: true).experimental?
      true
  """
  @spec new(atom(), module(), keyword()) :: t()
  def new(language, adapter, opts \\ []) when is_atom(language) and is_atom(adapter) do
    %__MODULE__{
      language: language,
      adapter: adapter,
      extensions: Keyword.get_lazy(opts, :extensions, fn -> adapter.file_extensions() end),
      experimental?: Keyword.get(opts, :experimental?, false),
      documentation?: Keyword.get(opts, :documentation?, false)
    }
  end
end
