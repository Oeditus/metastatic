defmodule Metastatic.Languages do
  @moduledoc """
  Single source of truth for supported languages and their adapters.

  All language detection, validation, and adapter lookup throughout the
  codebase goes through this module.

  ## Plug-in discovery

  The registry is **discovered at compile time** rather than hand-maintained.
  Every module under `lib/metastatic/adapters/` that declares
  `@behaviour Metastatic.Adapter` is picked up automatically and registered
  under the language atom derived from its name (`Metastatic.Adapters.Python`
  becomes `:python`, `Metastatic.Adapters.TypeScript` becomes `:typescript`).

  Adding a language therefore requires **only** dropping a new adapter module
  into `lib/metastatic/adapters/` -- no edit to this file is needed.

  ### Exclusions

  Some adapter modules are language adapters only in the structural sense but
  are not *source languages* for the code pipeline. These are listed in
  `@excluded` and skipped by discovery:

    * `english`, `spanish` -- NL adapters (natural-language prose), reachable
      through `Metastatic.NL.Adapters.*` instead.

  ### Config overrides

  Discovery can be adjusted at compile time through application config:

      config :metastatic, :languages,
        exclude: [:spanish],
        include: [%{language: :mylang, adapter: MyApp.Adapters.MyLang}],
        experimental: [:mylang],
        documentation: [:markdown]

  * `:exclude` -- language atoms to drop from the discovered set
  * `:include` -- extra `%{language: atom, adapter: module}` entries to add
    (useful for adapters living outside this library)
  * `:experimental` -- language atoms to flag as experimental
  * `:documentation` -- language atoms to flag as document languages

  ## Compile-Time Derivation

  Extension maps, supported language lists, and display strings are all
  derived at compile time from the discovered descriptors, so they stay in sync
  automatically.

  ## Examples

      iex> Metastatic.Languages.supported?(:python)
      true

      iex> Metastatic.Languages.supported?(:brainfuck)
      false

      iex> {:ok, :ruby} = Metastatic.Languages.detect_language("app.rb")

      iex> {:ok, Metastatic.Adapters.Python} = Metastatic.Languages.get_adapter(:python)
  """

  alias Metastatic.Language

  # Adapters that are structurally `Metastatic.Adapter` implementations but are
  # not source languages for the code pipeline. Kept here (not in the adapter
  # modules) so that discovery stays purely name-driven.
  @excluded [:english, :spanish]

  # Languages whose adapters are not exercised by the default CI matrix
  # (they require an external toolchain: GHC/Agda). They remain usable but
  # are advertised as experimental so the support matrix stays honest.
  @default_experimental [:agda, :haskell]

  # Languages that describe documents rather than executable code. They are
  # fully parseable and analyzable, but carry no callable entities.
  @default_documentation [:markdown]

  # ── Discovery ───────────────────────────────────────────────────────

  # Discover `{language_atom, adapter_module}` pairs at compile time. See
  # `Metastatic.Languages.Discovery` for the scanning logic.
  @discovered_modules Metastatic.Languages.Discovery.discover()

  # Config-driven overrides. `Application.compile_env/3` is evaluated at compile
  # time so the registry stays a compile-time constant.
  @config_overrides Application.compile_env(:metastatic, :languages, [])
  @config_exclude Keyword.get(@config_overrides, :exclude, [])
  @config_include Keyword.get(@config_overrides, :include, [])
  @config_experimental Keyword.get(@config_overrides, :experimental, [])
  @config_documentation Keyword.get(@config_overrides, :documentation, [])

  @experimental Enum.uniq(@default_experimental ++ @config_experimental)
  @documentation Enum.uniq(@default_documentation ++ @config_documentation)

  # Build the final list of `%Metastatic.Language{}` descriptors.
  @languages (
               discovered =
                 @discovered_modules
                 |> Enum.reject(fn {lang, _mod} ->
                   lang in @excluded or lang in @config_exclude
                 end)

               included =
                 Enum.map(@config_include, fn
                   %{language: lang, adapter: mod} -> {lang, mod}
                   {lang, mod} -> {lang, mod}
                 end)

               (discovered ++ included)
               |> Enum.uniq_by(fn {lang, _mod} -> lang end)
               |> Enum.sort_by(fn {lang, _mod} -> lang end)
               |> Enum.map(fn {lang, mod} ->
                 Language.new(lang, mod,
                   experimental?: lang in @experimental,
                   documentation?: lang in @documentation
                 )
               end)
             )

  # ── Derived at compile time ─────────────────────────────────────────

  @by_language Map.new(@languages, fn %Language{language: lang} = l -> {lang, l} end)

  @extension_map for %Language{language: lang, extensions: exts} <- @languages,
                     ext <- exts,
                     into: %{},
                     do: {ext, lang}

  @primary_extensions for %Language{language: lang, extensions: [first | _]} <- @languages,
                          into: %{},
                          do: {lang, first}

  @supported_languages @languages |> Enum.map(& &1.language) |> Enum.sort()

  @supported_languages_string @supported_languages |> Enum.map_join(", ", &Atom.to_string/1)

  @supported_extensions @extension_map |> Map.keys() |> Enum.sort()

  # ── Public API ──────────────────────────────────────────────────────

  @doc """
  Returns the list of supported language atoms, sorted alphabetically.

  ## Examples

      iex> :python in Metastatic.Languages.supported_languages()
      true
  """
  @spec supported_languages() :: [atom()]
  def supported_languages, do: @supported_languages

  @doc """
  Returns a comma-separated string of supported language names.

  Useful for error messages and help text.

  ## Examples

      iex> Metastatic.Languages.supported_languages_string() |> String.contains?("python")
      true
  """
  @spec supported_languages_string() :: String.t()
  def supported_languages_string, do: @supported_languages_string

  @doc """
  Returns all supported file extensions.

  ## Examples

      iex> ".py" in Metastatic.Languages.supported_extensions()
      true
  """
  @spec supported_extensions() :: [String.t()]
  def supported_extensions, do: @supported_extensions

  @doc """
  Checks whether a language atom is supported.

  ## Examples

      iex> Metastatic.Languages.supported?(:python)
      true

      iex> Metastatic.Languages.supported?(:brainfuck)
      false
  """
  @spec supported?(atom()) :: boolean()
  def supported?(language), do: Map.has_key?(@by_language, language)

  @doc """
  Returns the list of languages whose adapters are considered experimental.

  ## Examples

      iex> :agda in Metastatic.Languages.experimental_languages()
      true

      iex> :python in Metastatic.Languages.experimental_languages()
      false
  """
  @spec experimental_languages() :: [atom()]
  def experimental_languages, do: @experimental

  @doc """
  Checks whether a language is experimental.

  ## Examples

      iex> Metastatic.Languages.experimental?(:haskell)
      true

      iex> Metastatic.Languages.experimental?(:elixir)
      false
  """
  @spec experimental?(atom()) :: boolean()
  def experimental?(language), do: language in @experimental

  @doc """
  Returns the list of documentation languages.

  ## Examples

      iex> :markdown in Metastatic.Languages.documentation_languages()
      true
  """
  @spec documentation_languages() :: [atom()]
  def documentation_languages, do: @documentation

  @doc """
  Checks whether a language describes documents rather than executable code.

  ## Examples

      iex> Metastatic.Languages.documentation?(:markdown)
      true

      iex> Metastatic.Languages.documentation?(:elixir)
      false
  """
  @spec documentation?(atom()) :: boolean()
  def documentation?(language), do: language in @documentation

  @doc """
  Returns the `%Metastatic.Language{}` descriptor for a language, or `nil`.

  ## Examples

      iex> %Metastatic.Language{language: :python} = Metastatic.Languages.get(:python)
      iex> Metastatic.Languages.get(:brainfuck)
      nil
  """
  @spec get(atom()) :: Language.t() | nil
  def get(language), do: Map.get(@by_language, language)

  @doc """
  Returns all language descriptors.

  ## Examples

      iex> is_list(Metastatic.Languages.all())
      true
  """
  @spec all() :: [Language.t()]
  def all, do: @languages

  @doc """
  Returns the adapter module for a supported language.

  ## Examples

      iex> Metastatic.Languages.get_adapter(:python)
      {:ok, Metastatic.Adapters.Python}

      iex> Metastatic.Languages.get_adapter(:unknown)
      {:error, "Unsupported language: unknown. Supported: " <> _}
  """
  @spec get_adapter(atom()) :: {:ok, module()} | {:error, String.t()}
  def get_adapter(language) do
    case Map.fetch(@by_language, language) do
      {:ok, %Language{adapter: adapter}} ->
        {:ok, adapter}

      :error ->
        {:error, "Unsupported language: #{language}. Supported: #{@supported_languages_string}"}
    end
  end

  @doc """
  Detects language from a file path based on its extension.

  ## Examples

      iex> Metastatic.Languages.detect_language("script.py")
      {:ok, :python}

      iex> Metastatic.Languages.detect_language("app.rb")
      {:ok, :ruby}

      iex> Metastatic.Languages.detect_language("unknown.xyz")
      {:error, "Cannot detect language from extension: .xyz"}
  """
  @spec detect_language(String.t()) :: {:ok, atom()} | {:error, String.t()}
  def detect_language(path) do
    ext = Path.extname(path)

    case Map.fetch(@extension_map, ext) do
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
    lang = lang_str |> String.downcase() |> String.to_existing_atom()

    if supported?(lang) do
      {:ok, lang}
    else
      {:error, "Invalid language: #{lang_str}. Supported: #{@supported_languages_string}"}
    end
  rescue
    ArgumentError ->
      {:error, "Invalid language: #{lang_str}. Supported: #{@supported_languages_string}"}
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
  def extension_for_language(language) do
    case Map.fetch(@primary_extensions, language) do
      {:ok, ext} -> {:ok, ext}
      :error -> {:error, "No extension known for language: #{language}"}
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
    Map.new(@languages, fn %Language{language: lang, adapter: adapter} -> {lang, adapter} end)
  end
end
