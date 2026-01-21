defmodule Metastatic.Builder do
  @moduledoc """
  High-level API for building MetaAST documents from source code.

  This module provides the primary interface for users to work with Metastatic:

  - `from_source/2` - Parse source code to MetaAST (Source → M1 → M2)
  - `to_source/1` - Convert MetaAST back to source (M2 → M1 → Source)

  ## Usage

      # Parse Python code to MetaAST
      {:ok, doc} = Metastatic.Builder.from_source("x + 5", :python)

      # Doc now contains M2 representation:
      doc.ast
      # => {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}}

      # Convert back to source
      {:ok, source} = Metastatic.Builder.to_source(doc)
      # => "x + 5"

  ## Round-Trip Example

      source = "x + 5"
      {:ok, doc} = Metastatic.Builder.from_source(source, :python)
      {:ok, result} = Metastatic.Builder.to_source(doc)

      # Should be semantically equivalent (may have normalized formatting)
      assert normalize(result) == normalize(source)

  ## Cross-Language Transformation

      # Parse from Python
      {:ok, doc} = Metastatic.Builder.from_source("x + 5", :python)

      # The M2 AST is language-independent!
      # Could theoretically transform to JavaScript, Elixir, etc.
      # (Once those adapters are implemented)
  """

  alias Metastatic.{Adapter, Document}

  @doc """
  Build a MetaAST document from source code.

  Performs the full Source → M1 → M2 pipeline:
  1. Detects or uses specified language
  2. Parses source to M1 (native AST)
  3. Abstracts M1 to M2 (MetaAST)
  4. Returns Document with M2 AST and metadata

  ## Parameters

  - `source` - Source code string
  - `language` - Language atom (`:python`, `:javascript`, `:elixir`, etc.)
    If not provided, attempts to detect from source (not yet implemented)

  ## Returns

  - `{:ok, document}` - Successfully parsed and abstracted
  - `{:error, reason}` - Parsing or abstraction failed

  ## Examples

      iex> Metastatic.Builder.from_source("x + 5", :python)
      {:ok, %Metastatic.Document{
        ast: {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}},
        language: :python,
        metadata: %{...},
        original_source: "x + 5"
      }}

      iex> Metastatic.Builder.from_source("invalid syntax!", :python)
      {:error, "SyntaxError: ..."}

      iex> Metastatic.Builder.from_source("code", :unknown_language)
      {:error, :no_adapter_found}
  """
  @spec from_source(String.t(), atom()) :: {:ok, Document.t()} | {:error, term()}
  def from_source(source, language) when is_binary(source) and is_atom(language) do
    with {:ok, adapter} <- get_adapter(language) do
      Adapter.abstract(adapter, source, language)
    end
  end

  @doc """
  Build a MetaAST document from a file.

  Reads the file, detects language from extension, and parses to MetaAST.

  ## Parameters

  - `file_path` - Path to source file
  - `language` - Optional language override (auto-detected if not provided)

  ## Examples

      iex> Metastatic.Builder.from_file("script.py")
      {:ok, %Metastatic.Document{...}}

      iex> Metastatic.Builder.from_file("module.js")
      {:ok, %Metastatic.Document{language: :javascript, ...}}

      iex> Metastatic.Builder.from_file("nonexistent.py")
      {:error, :enoent}
  """
  @spec from_file(Path.t(), atom() | nil) :: {:ok, Document.t()} | {:error, term()}
  def from_file(file_path, language \\ nil) do
    with {:ok, source} <- File.read(file_path),
         {:ok, lang} <- detect_or_use_language(file_path, language) do
      from_source(source, lang)
    end
  end

  @doc """
  Convert a MetaAST document back to source code.

  Performs the full M2 → M1 → Source pipeline:
  1. Gets adapter for document's language
  2. Reifies M2 to M1 (native AST)
  3. Unparses M1 to source
  4. Returns source string

  ## Parameters

  - `document` - MetaAST document
  - `target_language` - Optional target language (defaults to document's language)

  ## Returns

  - `{:ok, source}` - Successfully unparsed
  - `{:error, reason}` - Unparsing failed

  ## Examples

      iex> doc = %Metastatic.Document{
      ...>   ast: {:literal, :integer, 42},
      ...>   language: :python,
      ...>   metadata: %{}
      ...> }
      iex> Metastatic.Builder.to_source(doc)
      {:ok, "42"}

  ## Cross-Language Translation (Future)

      # This will be possible once multiple adapters are implemented
      iex> doc = %Metastatic.Document{ast: ..., language: :python, ...}
      iex> Metastatic.Builder.to_source(doc, :javascript)
      {:ok, "// JavaScript equivalent"}
  """
  @spec to_source(Document.t(), atom() | nil) :: {:ok, String.t()} | {:error, term()}
  def to_source(%Document{} = document, target_language \\ nil) do
    language = target_language || document.language

    with {:ok, adapter} <- get_adapter(language) do
      Adapter.reify(adapter, document)
    end
  end

  @doc """
  Write a MetaAST document to a file.

  Converts to source and writes to the specified path.

  ## Examples

      iex> doc = %Metastatic.Document{...}
      iex> Metastatic.Builder.to_file(doc, "output.py")
      :ok

      iex> Metastatic.Builder.to_file(doc, "/invalid/path/file.py")
      {:error, :enoent}
  """
  @spec to_file(Document.t(), Path.t(), atom() | nil) :: :ok | {:error, term()}
  def to_file(%Document{} = document, file_path, target_language \\ nil) do
    with {:ok, source} <- to_source(document, target_language) do
      File.write(file_path, source)
    end
  end

  @doc """
  Round-trip test: Source → M1 → M2 → M1 → Source.

  Useful for validating adapter fidelity. The result may have normalized
  formatting but should be semantically equivalent to the input.

  ## Examples

      iex> Metastatic.Builder.round_trip("x + 5", :python)
      {:ok, "x + 5"}

      iex> Metastatic.Builder.round_trip("x  +  5", :python)
      {:ok, "x + 5"}  # Normalized spacing

      iex> Metastatic.Builder.round_trip("invalid!", :python)
      {:error, "SyntaxError: ..."}
  """
  @spec round_trip(String.t(), atom()) :: {:ok, String.t()} | {:error, term()}
  def round_trip(source, language) do
    with {:ok, document} <- from_source(source, language) do
      to_source(document)
    end
  end

  @doc """
  Validate that source code can be parsed and abstracted.

  Returns `true` if the source is valid, `false` otherwise.

  ## Examples

      iex> Metastatic.Builder.valid_source?("x + 5", :python)
      true

      iex> Metastatic.Builder.valid_source?("x +", :python)
      false

      iex> Metastatic.Builder.valid_source?("code", :unknown)
      false
  """
  @spec valid_source?(String.t(), atom()) :: boolean()
  def valid_source?(source, language) do
    case from_source(source, language) do
      {:ok, document} -> Document.valid?(document)
      {:error, _} -> false
    end
  end

  @doc """
  Get information about available language adapters.

  Returns a list of supported languages with their adapters.

  ## Examples

      iex> Metastatic.Builder.supported_languages()
      [
        %{language: :python, adapter: Metastatic.Adapters.Python, extensions: [".py"]},
        %{language: :javascript, adapter: Metastatic.Adapters.JavaScript, extensions: [".js", ".jsx"]}
      ]
  """
  @spec supported_languages() :: [map()]
  def supported_languages do
    # Get all registered adapters from the registry
    Adapter.Registry.list()
    |> Enum.map(fn {lang, adapter} ->
      %{
        language: lang,
        adapter: adapter,
        extensions: adapter.file_extensions(),
        loaded: true
      }
    end)
  end

  # Private helpers

  defp get_adapter(language) do
    # Try registry first, then fallback to hard-coded module lookup
    case Adapter.Registry.get(language) do
      {:ok, adapter} -> {:ok, adapter}
      {:error, :not_found} -> Adapter.for_language(language)
    end
  end

  defp detect_or_use_language(file_path, nil) do
    # Try registry first for file extension detection
    case Adapter.Registry.detect_language(file_path) do
      {:ok, language} -> {:ok, language}
      {:error, :unknown_extension} -> Adapter.detect_language(file_path)
    end
  end

  defp detect_or_use_language(_file_path, language) when is_atom(language) do
    {:ok, language}
  end
end
