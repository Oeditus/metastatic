defmodule Metastatic do
  @moduledoc """
  Metastatic - Cross-language code analysis via unified MetaAST.

  ## Main API

  The primary entry points for working with Metastatic:

  - `quote/2` - Convert source code to MetaAST
  - `unquote/2` - Convert MetaAST back to source code

  ## Examples

      # Parse Python code to MetaAST
      iex> {:ok, ast} = Metastatic.quote("x + 5", :python)
      iex> match?({:binary_op, :arithmetic, :+, {:variable, "x", _}, {:literal, :integer, 5, _}, _}, ast)
      true

      # Convert MetaAST back to Python source
      iex> ast = {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}}
      iex> Metastatic.unquote(ast, :python)
      {:ok, "x + 5"}

      # Round-trip demonstration
      iex> {:ok, my_ast} = Metastatic.quote("x + 5", :python)
      iex> {:ok, source} = Metastatic.unquote(my_ast, :python)
      iex> source
      "x + 5"

  ## Cross-Language Translation

  Since MetaAST is language-independent, you can parse in one language
  and generate in another:

      # Parse from Python, generate Elixir code (same MetaAST!)
      iex> {:ok, py_ast} = Metastatic.quote("x + 5", :python)
      iex> {:ok, _source} = Metastatic.unquote(py_ast, :elixir)
      iex> true
      true
  """

  alias Metastatic.{Builder, Document}

  @type language :: :elixir | :erlang | :ruby | :haskell | :python
  @type meta_ast :: Metastatic.AST.meta_ast()

  @languages ~w|elixir erlang ruby haskell python|a

  @doc false
  def languages, do: @languages

  @doc false
  def supported?(lang) when lang in @languages, do: true
  def supported?(_), do: false

  @doc false
  def adapter_for_language(language)

  for lang <- @languages do
    mod = Module.concat([Metastatic.Adapters, lang |> Atom.to_string() |> Macro.camelize()])
    def adapter_for_language(unquote(lang)), do: {:ok, unquote(mod)}
  end

  def adapter_for_language(lang),
    do: {:error, {:unsupported_language, "No adapter found for language: #{inspect(lang)}"}}

  @doc """
  Convert source code to MetaAST.

  Performs Source → M1 → M2 transformation, returning just the MetaAST
  without the Document wrapper.

  ## Parameters

  - `code` - Source code string
  - `language` - Language atom (`:python`, `:elixir`, `:ruby`, `:erlang`, `:haskell`)

  ## Returns

  - `{:ok, meta_ast}` - Successfully parsed and abstracted to M2
  - `{:error, reason}` - Parsing or abstraction failed

  ## Examples

      iex> {:ok, ast} = Metastatic.quote("x + 5", :python)
      iex> match?({:binary_op, :arithmetic, :+, {:variable, "x", _}, {:literal, :integer, 5, _}, _}, ast)
      true

      iex> {:ok, ast} = Metastatic.quote("x + 5", :elixir)
      iex> match?({:binary_op, :arithmetic, :+, {:variable, "x", _}, {:literal, :integer, 5}, _}, ast)
      true

      iex> {:ok, ast} = Metastatic.quote("[1, 2, 3]", :python)
      iex> match?({:list, [{:literal, :integer, 1, _}, {:literal, :integer, 2, _}, {:literal, :integer, 3, _}], _}, ast)
      true
  """
  @spec quote(String.t(), language()) :: {:ok, meta_ast()} | {:error, term()}
  def quote(code, language) when is_binary(code) and is_atom(language) do
    with {:ok, %Document{ast: ast}} <- Builder.from_source(code, language) do
      {:ok, ast}
    end
  end

  @doc """
  Convert MetaAST to source code.

  Performs M2 → M1 → Source transformation, generating source code in the
  specified target language.

  ## Parameters

  - `ast` - MetaAST structure (M2 level)
  - `language` - Target language atom (`:python`, `:elixir`, `:ruby`, `:erlang`, `:haskell`)

  ## Returns

  - `{:ok, source}` - Successfully generated source code
  - `{:error, reason}` - Generation failed

  ## Examples

      iex> ast = {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}}
      iex> Metastatic.unquote(ast, :python)
      {:ok, "x + 5"}

      iex> ast = {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}}
      iex> Metastatic.unquote(ast, :elixir)
      {:ok, "x + 5"}

      iex> ast = {:literal, :integer, 42}
      iex> Metastatic.unquote(ast, :python)
      {:ok, "42"}

      iex> ast = {:list, [{:literal, :integer, 1}, {:literal, :integer, 2}]}
      iex> Metastatic.unquote(ast, :python)
      {:ok, "[1, 2]"}

  ## Cross-Language Translation

  Since MetaAST is language-independent, you can parse from one language
  and generate in another:

      iex> {:ok, ast} = Metastatic.quote("x + 5", :python)
      iex> {:ok, source} = Metastatic.unquote(ast, :elixir)
      iex> source
      "x + 5"

      iex> {:ok, ast} = Metastatic.quote("42", :ruby)
      iex> {:ok, source} = Metastatic.unquote(ast, :python)
      iex> source
      "42"
  """
  @spec unquote(meta_ast(), language()) :: {:ok, String.t()} | {:error, term()}
  def unquote(ast, language) when is_atom(language) do
    # Create minimal document wrapper (language will be used for target)
    doc = %Document{ast: ast, language: language, metadata: %{}, original_source: nil}
    Builder.to_source(doc)
  end
end
