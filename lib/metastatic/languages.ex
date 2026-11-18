defmodule Metastatic.Languages do
  @moduledoc """
  Single source of truth for supported languages and their adapters.

  All language detection, validation, and adapter lookup throughout the
  codebase goes through this module.

  ## Hybrid registry

  The set of languages is the union of two sources:

    1. **Built-ins** — the adapters compiled into Metastatic, discovered at
       compile time by `Metastatic.Languages.Builtin`.
    2. **Plug-ins** — adapters registered at runtime by the host application,
       through `Metastatic.Adapter.Registry.register/2`, the registry's
       `:plugins` child-spec option, or `register/2` below.

  Both are stored in `Metastatic.Languages.Store` (ETS). This module is a
  façade over that store: every function here is a lookup, not a compile-time
  constant, so a language registered at boot is visible to
  `supported_languages/0`, `detect_language/1` and `get_adapter/1` immediately.

  ### Adding a language

  Inside Metastatic, drop a module into `lib/metastatic/adapters/` that
  declares `@behaviour Metastatic.Adapter`; `Languages.Builtin` picks it up on
  the next compile.

  From a host application, register it at boot — no edit to Metastatic and no
  recompile:

      # my_app/lib/my_app/application.ex
      children = [
        {Metastatic.Adapter.Registry, plugins: [MyApp.Adapters.Rust]}
      ]

  or, if the registry is already running:

      Metastatic.Languages.register(:rust, MyApp.Adapters.Rust)

  ### Exclusions and config

  Some adapter modules are language adapters only in the structural sense but
  are not *source languages* for the code pipeline (`english`, `spanish`, the
  NL adapters). `Metastatic.Languages.Builtin` excludes them.

  Compile-time config still works for the built-ins:

      config :metastatic, :languages,
        exclude: [:spanish],
        include: [%{language: :mylang, adapter: MyApp.Adapters.MyLang}],
        experimental: [:mylang],
        documentation: [:markdown]

  Prefer runtime registration for host adapters: `:include` requires
  recompiling Metastatic, while `register/2` does not.

  ## Examples

      iex> Metastatic.Languages.supported?(:python)
      true

      iex> Metastatic.Languages.supported?(:brainfuck)
      false

      iex> {:ok, :ruby} = Metastatic.Languages.detect_language("app.rb")

      iex> {:ok, Metastatic.Adapters.Python} = Metastatic.Languages.get_adapter(:python)
  """

  alias Metastatic.{Language, Languages.Builtin, Languages.Store}

  # ── Registration ────────────────────────────────────────────────────

  @doc """
  Registers a language adapter at runtime.

  The adapter must implement `Metastatic.Adapter` (see
  `Metastatic.Adapter.valid_adapter?/1`). Extensions are read from its
  `file_extensions/0`.

  Refuses to replace a language that is already registered with a *different*
  adapter — silently shadowing `:python` would make the whole pipeline depend
  on boot order. Re-registering the same adapter is idempotent.

  ## Options

    * `:experimental?` — flag the language as experimental (default `false`)
    * `:documentation?` — flag it as a document language (default `false`)
    * `:extensions` — override the adapter's declared extensions

  When `adapter` was built with `Metastatic.Adapter.Plugin`, its declared
  descriptor (extensions and flags) is used automatically; explicit options
  still win.

  ## Examples

      iex> Metastatic.Languages.register(:demo_lang, Metastatic.Adapters.Elixir, extensions: [".demo"])
      :ok
      iex> Metastatic.Languages.supported?(:demo_lang)
      true
      iex> Metastatic.Languages.unregister(:demo_lang)
      :ok

      iex> Metastatic.Languages.register(:invalid, String)
      {:error, :invalid_adapter}
  """
  @spec register(atom(), module(), keyword()) ::
          :ok | {:error, :invalid_adapter} | {:error, {:already_registered, atom(), module()}}
  def register(language, adapter, opts \\ []) when is_atom(language) and is_atom(adapter) do
    Metastatic.Adapter.Registry.register(language, adapter, opts)
  end

  @doc """
  Removes a runtime-registered language.

  Built-in languages cannot be unregistered: they are re-seeded at boot, so
  removing one would only desynchronise the store from the library's own
  contract. Returns `{:error, :builtin}` for those.

  ## Examples

      iex> Metastatic.Languages.register(:demo_lang, Metastatic.Adapters.Elixir, extensions: [".demo"])
      iex> Metastatic.Languages.unregister(:demo_lang)
      :ok

      iex> Metastatic.Languages.unregister(:python)
      {:error, :builtin}
  """
  @spec unregister(atom()) :: :ok | {:error, :builtin}
  def unregister(language) when is_atom(language) do
    Metastatic.Adapter.Registry.unregister(language)
  end

  # ── Queries ─────────────────────────────────────────────────────────

  @doc """
  Returns the list of supported language atoms, sorted alphabetically.

  ## Examples

      iex> :python in Metastatic.Languages.supported_languages()
      true
  """
  @spec supported_languages() :: [atom()]
  def supported_languages do
    Store.all() |> Enum.map(& &1.language)
  end

  @doc """
  Returns a comma-separated string of supported language names.

  Useful for error messages and help text. Computed on demand (it is only
  reached on an error path), so runtime-registered languages appear in it.

  ## Examples

      iex> Metastatic.Languages.supported_languages_string() |> String.contains?("python")
      true
  """
  @spec supported_languages_string() :: String.t()
  def supported_languages_string do
    supported_languages() |> Enum.map_join(", ", &Atom.to_string/1)
  end

  @doc """
  Returns all supported file extensions.

  ## Examples

      iex> ".py" in Metastatic.Languages.supported_extensions()
      true
  """
  @spec supported_extensions() :: [String.t()]
  def supported_extensions, do: Store.extensions()

  @doc """
  Checks whether a language atom is supported.

  ## Examples

      iex> Metastatic.Languages.supported?(:python)
      true

      iex> Metastatic.Languages.supported?(:brainfuck)
      false
  """
  @spec supported?(atom()) :: boolean()
  def supported?(language) when is_atom(language) do
    Store.get(language) != nil
  end

  @doc """
  Returns the list of languages whose adapters are considered experimental.

  ## Examples

      iex> :agda in Metastatic.Languages.experimental_languages()
      true

      iex> :python in Metastatic.Languages.experimental_languages()
      false
  """
  @spec experimental_languages() :: [atom()]
  def experimental_languages do
    Store.all() |> Enum.filter(& &1.experimental?) |> Enum.map(& &1.language)
  end

  @doc """
  Checks whether a language is experimental.

  ## Examples

      iex> Metastatic.Languages.experimental?(:haskell)
      true

      iex> Metastatic.Languages.experimental?(:elixir)
      false
  """
  @spec experimental?(atom()) :: boolean()
  def experimental?(language) when is_atom(language) do
    case Store.get(language) do
      nil -> false
      descriptor -> descriptor.experimental?
    end
  end

  @doc """
  Returns the list of documentation languages.

  ## Examples

      iex> :markdown in Metastatic.Languages.documentation_languages()
      true
  """
  @spec documentation_languages() :: [atom()]
  def documentation_languages do
    Store.all() |> Enum.filter(& &1.documentation?) |> Enum.map(& &1.language)
  end

  @doc """
  Checks whether a language describes documents rather than executable code.

  ## Examples

      iex> Metastatic.Languages.documentation?(:markdown)
      true

      iex> Metastatic.Languages.documentation?(:elixir)
      false
  """
  @spec documentation?(atom()) :: boolean()
  def documentation?(language) when is_atom(language) do
    case Store.get(language) do
      nil -> false
      descriptor -> descriptor.documentation?
    end
  end

  @doc """
  Returns the `%Metastatic.Language{}` descriptor for a language, or `nil`.

  ## Examples

      iex> %Metastatic.Language{language: :python} = Metastatic.Languages.get(:python)
      iex> Metastatic.Languages.get(:brainfuck)
      nil
  """
  @spec get(atom()) :: Language.t() | nil
  def get(language) when is_atom(language), do: Store.get(language)

  @doc """
  Returns all language descriptors, sorted by language atom.

  ## Examples

      iex> is_list(Metastatic.Languages.all())
      true
  """
  @spec all() :: [Language.t()]
  def all, do: Store.all()

  @doc """
  Returns the adapter module for a supported language.

  ## Examples

      iex> Metastatic.Languages.get_adapter(:python)
      {:ok, Metastatic.Adapters.Python}

      iex> Metastatic.Languages.get_adapter(:unknown)
      {:error, "Unsupported language: unknown. Supported: " <> _}
  """
  @spec get_adapter(atom()) :: {:ok, module()} | {:error, String.t()}
  def get_adapter(language) when is_atom(language) do
    case Store.get(language) do
      %Language{adapter: adapter} ->
        {:ok, adapter}

      nil ->
        {:error, "Unsupported language: #{language}. Supported: #{supported_languages_string()}"}
    end
  end

  @doc """
  Detects language from a file path based on its extension.

  A single ETS lookup — this is called once per file during directory
  translation, so it must not go through a `GenServer`.

  ## Examples

      iex> Metastatic.Languages.detect_language("script.py")
      {:ok, :python}

      iex> Metastatic.Languages.detect_language("app.rb")
      {:ok, :ruby}

      iex> Metastatic.Languages.detect_language("unknown.xyz")
      {:error, "Cannot detect language from extension: .xyz"}
  """
  @spec detect_language(String.t()) :: {:ok, atom()} | {:error, String.t()}
  def detect_language(path) when is_binary(path) do
    ext = Path.extname(path)

    case Store.detect(ext) do
      {:ok, lang} -> {:ok, lang}
      :error -> {:error, "Cannot detect language from extension: #{ext}"}
    end
  end

  @doc """
  Parses a language string (e.g. from CLI `--language` option) into an atom.

  ## Return contract

  This function has three outcomes, each documented explicitly:

  - `{:ok, atom}` — a supported language
  - `{:error, message}` — an unknown/unsupported language
  - `:none` — the input was `nil` (no language specified; caller should
    auto-detect).

  ## Examples

      iex> Metastatic.Languages.parse_language("python")
      {:ok, :python}

      iex> Metastatic.Languages.parse_language("Ruby")
      {:ok, :ruby}

      iex> Metastatic.Languages.parse_language(nil)
      :none

      iex> Metastatic.Languages.parse_language("brainfuck")
      {:error, "Invalid language: brainfuck. Supported: " <> _}
  """
  @spec parse_language(String.t() | nil) :: {:ok, atom()} | {:error, String.t()} | :none
  def parse_language(nil), do: :none

  def parse_language(lang_str) when is_binary(lang_str) do
    # `String.to_existing_atom/1` would reject a runtime-registered language
    # whose atom was created after this module was loaded, so the lookup is by
    # name against the registry instead.
    normalised = String.downcase(lang_str)

    Enum.find_value(supported_languages(), :error, fn language ->
      if Atom.to_string(language) == normalised, do: {:ok, language}
    end)
    |> case do
      {:ok, language} ->
        {:ok, language}

      :error ->
        {:error, "Invalid language: #{lang_str}. Supported: #{supported_languages_string()}"}
    end
  end

  @doc """
  Returns the primary file extension for a language.

  ## Examples

      iex> Metastatic.Languages.extension_for_language(:python)
      {:ok, ".py"}

      iex> Metastatic.Languages.extension_for_language(:unknown)
      {:error, "No extension known for language: unknown"}
  """
  @spec extension_for_language(atom()) :: {:ok, String.t()} | {:error, String.t()}
  def extension_for_language(language) when is_atom(language) do
    case Store.get(language) do
      %Language{extensions: [first | _]} -> {:ok, first}
      _ -> {:error, "No extension known for language: #{language}"}
    end
  end

  @doc """
  Returns the map of all adapters (language atom => module).

  ## Examples

      iex> adapters = Metastatic.Languages.adapters()
      iex> Map.has_key?(adapters, :python)
      true
  """
  @spec adapters() :: %{atom() => module()}
  def adapters do
    Map.new(Store.all(), fn %Language{language: lang, adapter: adapter} -> {lang, adapter} end)
  end

  @doc """
  Returns the built-in language descriptors, ignoring runtime registrations.

  Useful for diagnostics and for code that must reason about what the library
  itself ships.

  ## Examples

      iex> is_list(Metastatic.Languages.builtin())
      true
  """
  @spec builtin() :: [Language.t()]
  def builtin, do: Builtin.all()
end
