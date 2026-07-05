defmodule Metastatic.Languages do
  @moduledoc """
  Single source of truth for supported languages and their adapters.

  All language detection, validation, and adapter lookup throughout the
  codebase should go through this module. Adding support for a new language
  requires only adding a single entry to `@adapters` here (assuming the
  adapter module already exists and implements `Metastatic.Adapter`).

  ## Compile-Time Derivation

  Extension maps, supported language lists, and display strings are all
  derived at compile time from the `@adapters` map and each adapter's
  `file_extensions/0` callback, so they stay in sync automatically.

  ## Examples

      iex> Metastatic.Languages.supported?(:python)
      true

      iex> Metastatic.Languages.supported?(:brainfuck)
      false

      iex> {:ok, :ruby} = Metastatic.Languages.detect_language("app.rb")

      iex> {:ok, Metastatic.Adapters.Python} = Metastatic.Languages.get_adapter(:python)
  """

  # ── The single source of truth ──────────────────────────────────────
  @adapters %{
    python: Metastatic.Adapters.Python,
    elixir: Metastatic.Adapters.Elixir,
    erlang: Metastatic.Adapters.Erlang,
    ruby: Metastatic.Adapters.Ruby,
    haskell: Metastatic.Adapters.Haskell
  }

  # ── Derived at compile time ─────────────────────────────────────────

  @extension_map for {lang, adapter} <- @adapters,
                     ext <- adapter.file_extensions(),
                     into: %{},
                     do: {ext, lang}

  @primary_extensions for {lang, adapter} <- @adapters,
                          into: %{},
                          do: {lang, hd(adapter.file_extensions())}

  @supported_languages @adapters |> Map.keys() |> Enum.sort()

  @supported_languages_string @supported_languages |> Enum.map_join(", ", &Atom.to_string/1)

  @supported_extensions @extension_map |> Map.keys() |> Enum.sort()

  # ── Public API ──────────────────────────────────────────────────────

  @doc """
  Returns the list of supported language atoms, sorted alphabetically.

  ## Examples

      iex> Metastatic.Languages.supported_languages()
      [:elixir, :erlang, :haskell, :python, :ruby]
  """
  @spec supported_languages() :: [atom()]
  def supported_languages, do: @supported_languages

  @doc """
  Returns a comma-separated string of supported language names.

  Useful for error messages and help text.

  ## Examples

      iex> Metastatic.Languages.supported_languages_string()
      "elixir, erlang, haskell, python, ruby"
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
  def supported?(language), do: Map.has_key?(@adapters, language)

  @doc """
  Returns the adapter module for a supported language.

  ## Examples

      iex> Metastatic.Languages.get_adapter(:python)
      {:ok, Metastatic.Adapters.Python}

      iex> Metastatic.Languages.get_adapter(:unknown)
      {:error, "Unsupported language: unknown. Supported: elixir, erlang, haskell, python, ruby"}
  """
  @spec get_adapter(atom()) :: {:ok, module()} | {:error, String.t()}
  def get_adapter(language) do
    case Map.fetch(@adapters, language) do
      {:ok, adapter} ->
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

  Returns `nil` when given `nil` (language not specified, auto-detect).

  ## Examples

      iex> Metastatic.Languages.parse_language("python")
      {:ok, :python}

      iex> Metastatic.Languages.parse_language("Ruby")
      {:ok, :ruby}

      iex> Metastatic.Languages.parse_language(nil)
      nil

      iex> Metastatic.Languages.parse_language("brainfuck")
      {:error, "Invalid language: brainfuck. Supported: elixir, erlang, haskell, python, ruby"}
  """
  @spec parse_language(String.t() | nil) :: {:ok, atom()} | {:error, String.t()} | nil
  def parse_language(nil), do: nil

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
  def adapters, do: @adapters
end
