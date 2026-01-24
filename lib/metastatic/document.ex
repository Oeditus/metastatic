defmodule Metastatic.Document do
  @moduledoc """
  A MetaAST Document wraps an M2 AST with metadata and language information.

  This structure represents the result of abstraction (M1 → M2) and serves
  as input for reification (M2 → M1).

  ## Fields

  - `ast` - The M2 MetaAST representation
  - `metadata` - Language-specific information preserved from M1
  - `language` - Source language (:python, :javascript, :elixir, etc.)
  - `original_source` - Optional: original source code (for debugging/comparison)

  ## Metadata

  Metadata contains M1-specific information that cannot be represented at M2 level:

  - Formatting preferences (indentation, spacing)
  - Comments and documentation
  - Type annotations (TypeScript, Python type hints)
  - Language-specific hints (async models, iterator styles, etc.)

  This enables high-fidelity M2 → M1 round-trips while maintaining semantic equivalence.

  ## Examples

      # After abstraction from Python
      %Metastatic.Document{
        language: :python,
        ast: {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}},
        metadata: %{
          native_lang: :python,
          type_hints: %{"x" => "int"},
          formatting: %{indent: 4}
        },
        original_source: "x + 5"
      }
  """

  alias Metastatic.AST

  @enforce_keys [:ast, :language]
  defstruct [:ast, :metadata, :language, :original_source]

  @typedoc """
  A Document containing M2 AST with associated metadata.
  """
  @type t :: %__MODULE__{
          ast: AST.meta_ast(),
          metadata: map(),
          language: atom(),
          original_source: String.t() | nil
        }

  @doc """
  Create a new MetaAST document.

  ## Examples

      iex> ast = {:literal, :integer, 42}
      iex> Metastatic.Document.new(ast, :python)
      %Metastatic.Document{
        ast: {:literal, :integer, 42},
        language: :python,
        metadata: %{},
        original_source: nil
      }

      iex> ast = {:variable, "x"}
      iex> metadata = %{type_hint: "str"}
      iex> Metastatic.Document.new(ast, :python, metadata, "x")
      %Metastatic.Document{
        ast: {:variable, "x"},
        language: :python,
        metadata: %{type_hint: "str"},
        original_source: "x"
      }
  """
  @spec new(AST.meta_ast(), atom(), map(), String.t() | nil) :: t()
  def new(ast, language, metadata \\ %{}, original_source \\ nil) do
    %__MODULE__{
      ast: ast,
      language: language,
      metadata: metadata,
      original_source: original_source
    }
  end

  @doc """
  Validate that a document's AST conforms to M2 meta-model.

  ## Examples

      iex> doc = Metastatic.Document.new({:literal, :integer, 42}, :python)
      iex> Metastatic.Document.valid?(doc)
      true

      iex> doc = %Metastatic.Document{
      ...>   ast: {:invalid_node, "data"},
      ...>   language: :python,
      ...>   metadata: %{}
      ...> }
      iex> Metastatic.Document.valid?(doc)
      false
  """
  @spec valid?(t()) :: boolean()
  def valid?(%__MODULE__{ast: ast}) do
    AST.conforms?(ast)
  end

  @doc """
  Update the AST in a document while preserving metadata and language.

  Useful for transformations that operate on the M2 level.

  ## Examples

      iex> doc = Metastatic.Document.new({:literal, :integer, 42}, :python)
      iex> new_ast = {:literal, :integer, 100}
      iex> updated = Metastatic.Document.update_ast(doc, new_ast)
      iex> updated.ast
      {:literal, :integer, 100}
      iex> updated.language
      :python
  """
  @spec update_ast(t(), AST.meta_ast()) :: t()
  def update_ast(%__MODULE__{} = doc, new_ast) do
    %{doc | ast: new_ast}
  end

  @doc """
  Update document metadata (merges with existing metadata).

  ## Examples

      iex> doc = Metastatic.Document.new({:variable, "x"}, :python, %{type: "int"})
      iex> updated = Metastatic.Document.update_metadata(doc, %{mutable: false})
      iex> updated.metadata
      %{type: "int", mutable: false}
  """
  @spec update_metadata(t(), map()) :: t()
  def update_metadata(%__MODULE__{metadata: metadata} = doc, new_metadata) do
    %{doc | metadata: Map.merge(metadata, new_metadata)}
  end

  @doc """
  Get the language of a document.

  ## Examples

      iex> doc = Metastatic.Document.new({:literal, :integer, 42}, :python)
      iex> Metastatic.Document.language(doc)
      :python
  """
  @spec language(t()) :: atom()
  def language(%__MODULE__{language: lang}), do: lang

  @doc """
  Check if two documents have semantically equivalent ASTs.

  This compares the M2 AST structures, ignoring metadata and original source.

  ## Examples

      iex> doc1 = Metastatic.Document.new({:literal, :integer, 42}, :python)
      iex> doc2 = Metastatic.Document.new({:literal, :integer, 42}, :javascript)
      iex> Metastatic.Document.equivalent?(doc1, doc2)
      true

      iex> doc1 = Metastatic.Document.new({:literal, :integer, 42}, :python)
      iex> doc2 = Metastatic.Document.new({:literal, :string, "42"}, :python)
      iex> Metastatic.Document.equivalent?(doc1, doc2)
      false
  """
  @spec equivalent?(t(), t()) :: boolean()
  def equivalent?(%__MODULE__{ast: ast1}, %__MODULE__{ast: ast2}) do
    ast1 == ast2
  end

  @doc """
  Extract all variables referenced in the document's AST.

  Delegates to `Metastatic.AST.variables/1`.

  ## Examples

      iex> ast = {:binary_op, :arithmetic, :+, {:variable, "x"}, {:variable, "y"}}
      iex> doc = Metastatic.Document.new(ast, :python)
      iex> Metastatic.Document.variables(doc)
      MapSet.new(["x", "y"])
  """
  @spec variables(t()) :: MapSet.t(String.t())
  def variables(%__MODULE__{ast: ast}) do
    AST.variables(ast)
  end

  @doc """
  Normalize input to a Document.

  Accepts either:
  - A `Metastatic.Document` struct (returned as-is)
  - A `{language, native_ast}` tuple (converted to Document using the appropriate adapter)

  This enables analyzers to accept both formats for convenience.

  ## Examples

      # Already a Document - returns as-is
      iex> doc = Metastatic.Document.new({:literal, :integer, 42}, :python)
      iex> Metastatic.Document.normalize(doc)
      {:ok, doc}

      # {lang, native_ast} tuple - converts using adapter
      iex> python_ast = %{"_type" => "Constant", "value" => 42}
      iex> {:ok, doc} = Metastatic.Document.normalize({:python, python_ast})
      iex> doc.ast
      {:literal, :integer, 42}
      iex> doc.language
      :python
  """
  @spec normalize(t() | {atom(), term()}) :: {:ok, t()} | {:error, term()}
  def normalize(%__MODULE__{} = doc), do: {:ok, doc}

  def normalize({language, native_ast}) when is_atom(language) do
    case adapter_for_language(language) do
      {:ok, adapter} ->
        case adapter.to_meta(native_ast) do
          {:ok, meta_ast, metadata} ->
            doc = new(meta_ast, language, metadata)
            {:ok, doc}

          {:error, reason} ->
            {:error, {:transformation_failed, reason}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def normalize(other) do
    {:error,
     {:invalid_input, "Expected Document.t() or {language, native_ast}, got: #{inspect(other)}"}}
  end

  @doc """
  Normalize input to a Document, raising on error.

  ## Examples

      iex> doc = Metastatic.Document.new({:literal, :integer, 42}, :python)
      iex> Metastatic.Document.normalize!(doc)
      doc
  """
  @spec normalize!(t() | {atom(), term()}) :: t()
  def normalize!(input) do
    case normalize(input) do
      {:ok, doc} -> doc
      {:error, reason} -> raise "Failed to normalize input: #{inspect(reason)}"
    end
  end

  # Private helper to get adapter module for a language
  defp adapter_for_language(:python), do: {:ok, Metastatic.Adapters.Python}
  defp adapter_for_language(:elixir), do: {:ok, Metastatic.Adapters.Elixir}
  defp adapter_for_language(:erlang), do: {:ok, Metastatic.Adapters.Erlang}
  defp adapter_for_language(:ruby), do: {:ok, Metastatic.Adapters.Ruby}
  defp adapter_for_language(:haskell), do: {:ok, Metastatic.Adapters.Haskell}

  defp adapter_for_language(lang),
    do: {:error, {:unsupported_language, "No adapter found for language: #{inspect(lang)}"}}
end
