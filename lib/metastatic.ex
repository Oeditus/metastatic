defmodule Metastatic do
  @moduledoc """
  Metastatic - Cross-language code analysis via unified MetaAST.

  ## Main API

  The primary entry points for working with Metastatic:

  - `quote/2` - Convert source code to MetaAST
  - `unquote/2` - Convert MetaAST back to source code
  - `prewalk/2`, `prewalk/3` - Pre-order AST traversal
  - `postwalk/2`, `postwalk/3` - Post-order AST traversal
  - `traverse/4` - Full pre+post AST traversal with accumulator
  - `path/2` - Find path from root to matching node
  - `to_string/1` - Human-readable AST representation
  - `decompose_call/1` - Decompose function call nodes
  - `validate/1` - Validate AST structure with diagnostics
  - `unpipe/1` - Decompose pipe chains
  - `pipe_into/3` - Inject expression into function call
  - `literal?/1` - Check if AST is purely literal
  - `operator?/1` - Check if node is an operator
  - `prewalker/1`, `postwalker/1` - Lazy enumerable traversals
  - `unique_var/1` - Generate unique variable nodes

  ## Examples

      # Parse Python code to MetaAST
      iex> {:ok, {:binary_op, meta, _}} = Metastatic.quote("x + 5", :python)
      iex> Keyword.get(meta, :category) == :arithmetic and Keyword.get(meta, :operator) == :+
      true

      # Convert MetaAST back to Python source
      iex> ast = {:binary_op, [category: :arithmetic, operator: :+], [{:variable, [], "x"}, {:literal, [subtype: :integer], 5}]}
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

  alias Metastatic.{AST, Builder, Document}

  @type language :: :elixir | :erlang | :ruby | :haskell | :python
  @type meta_ast :: AST.meta_ast()

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

      iex> {:ok, {:binary_op, meta, _}} = Metastatic.quote("x + 5", :python)
      iex> Keyword.get(meta, :category) == :arithmetic and Keyword.get(meta, :operator) == :+
      true

      iex> {:ok, {:binary_op, meta, _}} = Metastatic.quote("x + 5", :elixir)
      iex> Keyword.get(meta, :category) == :arithmetic and Keyword.get(meta, :operator) == :+
      true

      iex> {:ok, {:list, _, items}} = Metastatic.quote("[1, 2, 3]", :python)
      iex> length(items) == 3
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

      iex> ast = {:binary_op, [category: :arithmetic, operator: :+], [{:variable, [], "x"}, {:literal, [subtype: :integer], 5}]}
      iex> Metastatic.unquote(ast, :python)
      {:ok, "x + 5"}

      iex> ast = {:binary_op, [category: :arithmetic, operator: :+], [{:variable, [], "x"}, {:literal, [subtype: :integer], 5}]}
      iex> Metastatic.unquote(ast, :elixir)
      {:ok, "x + 5"}

      iex> ast = {:literal, [subtype: :integer], 42}
      iex> Metastatic.unquote(ast, :python)
      {:ok, "42"}

      iex> ast = {:list, [], [{:literal, [subtype: :integer], 1}, {:literal, [subtype: :integer], 2}]}
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

  # ----- Traversal (mirrors Macro.traverse/4, Macro.prewalk, Macro.postwalk) -----

  @doc """
  Traverse a MetaAST, applying pre and post functions.

  Delegates to `Metastatic.AST.traverse/4`. See that module for full documentation.

  ## Examples

      iex> ast = {:binary_op, [category: :arithmetic, operator: :+],
      ...>   [{:literal, [subtype: :integer], 1}, {:literal, [subtype: :integer], 2}]}
      iex> {_ast, count} = Metastatic.traverse(ast, 0, fn node, acc -> {node, acc + 1} end, fn node, acc -> {node, acc} end)
      iex> count
      3
  """
  defdelegate traverse(ast, acc, pre, post), to: AST

  @doc """
  Performs a depth-first, pre-order traversal of the MetaAST (no accumulator).

  Delegates to `Metastatic.AST.prewalk/2`.

  ## Examples

      iex> ast = {:binary_op, [category: :arithmetic, operator: :+],
      ...>   [{:literal, [subtype: :integer], 1}, {:literal, [subtype: :integer], 2}]}
      iex> Metastatic.prewalk(ast, fn
      ...>   {:literal, meta, value} when is_integer(value) -> {:literal, meta, value * 10}
      ...>   node -> node
      ...> end)
      {:binary_op, [category: :arithmetic, operator: :+],
        [{:literal, [subtype: :integer], 10}, {:literal, [subtype: :integer], 20}]}
  """
  defdelegate prewalk(ast, fun), to: AST

  @doc """
  Performs a depth-first, pre-order traversal with accumulator.

  Delegates to `Metastatic.AST.prewalk/3`.
  """
  defdelegate prewalk(ast, acc, fun), to: AST

  @doc """
  Performs a depth-first, post-order traversal of the MetaAST (no accumulator).

  Delegates to `Metastatic.AST.postwalk/2`.

  ## Examples

      iex> ast = {:binary_op, [category: :arithmetic, operator: :+],
      ...>   [{:literal, [subtype: :integer], 1}, {:literal, [subtype: :integer], 2}]}
      iex> Metastatic.postwalk(ast, fn
      ...>   {:literal, meta, value} when is_integer(value) -> {:literal, meta, value * 10}
      ...>   node -> node
      ...> end)
      {:binary_op, [category: :arithmetic, operator: :+],
        [{:literal, [subtype: :integer], 10}, {:literal, [subtype: :integer], 20}]}
  """
  defdelegate postwalk(ast, fun), to: AST

  @doc """
  Performs a depth-first, post-order traversal with accumulator.

  Delegates to `Metastatic.AST.postwalk/3`.
  """
  defdelegate postwalk(ast, acc, fun), to: AST

  # ----- Enumerable Walkers (mirrors Macro.prewalker/1, Macro.postwalker/1) -----

  @doc """
  Returns an enumerable that lazily traverses the MetaAST in pre-order.

  Delegates to `Metastatic.AST.prewalker/1`.

  ## Examples

      iex> ast = {:binary_op, [category: :arithmetic, operator: :+],
      ...>   [{:literal, [subtype: :integer], 1}, {:literal, [subtype: :integer], 2}]}
      iex> ast |> Metastatic.prewalker() |> Enum.map(&Metastatic.AST.type/1)
      [:binary_op, :literal, :literal]
  """
  defdelegate prewalker(ast), to: AST

  @doc """
  Returns an enumerable that lazily traverses the MetaAST in post-order.

  Delegates to `Metastatic.AST.postwalker/1`.

  ## Examples

      iex> ast = {:binary_op, [category: :arithmetic, operator: :+],
      ...>   [{:literal, [subtype: :integer], 1}, {:literal, [subtype: :integer], 2}]}
      iex> ast |> Metastatic.postwalker() |> Enum.map(&Metastatic.AST.type/1)
      [:literal, :literal, :binary_op]
  """
  defdelegate postwalker(ast), to: AST

  # ----- Path (mirrors Macro.path/2) -----

  @doc """
  Returns the path to the node for which `fun` returns a truthy value.

  The path is a list starting with the matched node, followed by its
  parents up to the root. Returns `nil` if no match found.

  Delegates to `Metastatic.AST.path/2`.

  ## Examples

      iex> ast = {:binary_op, [category: :arithmetic, operator: :+],
      ...>   [{:variable, [], "x"}, {:literal, [subtype: :integer], 42}]}
      iex> path = Metastatic.path(ast, fn
      ...>   {:literal, _, 42} -> true
      ...>   _ -> false
      ...> end)
      iex> Enum.map(path, &Metastatic.AST.type/1)
      [:literal, :binary_op]
  """
  defdelegate path(ast, fun), to: AST

  # ----- Pipe Utilities (mirrors Macro.unpipe/1, Macro.pipe/3) -----

  @doc """
  Breaks a pipe chain into a flat list of `{ast, position}` tuples.

  Delegates to `Metastatic.AST.unpipe/1`.
  """
  defdelegate unpipe(ast), to: AST

  @doc """
  Pipes `expr` into a function call at the given position.

  Delegates to `Metastatic.AST.pipe_into/3`.

  ## Examples

      iex> expr = {:variable, [], "x"}
      iex> call = {:function_call, [name: "foo"], [{:literal, [subtype: :integer], 1}]}
      iex> Metastatic.pipe_into(expr, call, 0)
      {:function_call, [name: "foo"], [{:variable, [], "x"}, {:literal, [subtype: :integer], 1}]}
  """
  defdelegate pipe_into(expr, call, position), to: AST

  # ----- Call Decomposition (mirrors Macro.decompose_call/1) -----

  @doc """
  Decomposes a function call into `{name, args}` or `:error`.

  Delegates to `Metastatic.AST.decompose_call/1`.

  ## Examples

      iex> call = {:function_call, [name: "add"], [{:variable, [], "x"}, {:variable, [], "y"}]}
      iex> Metastatic.decompose_call(call)
      {"add", [{:variable, [], "x"}, {:variable, [], "y"}]}

      iex> Metastatic.decompose_call({:literal, [subtype: :integer], 42})
      :error
  """
  defdelegate decompose_call(ast), to: AST

  # ----- String Representation (mirrors Macro.to_string/1) -----

  @doc """
  Converts a MetaAST to a human-readable string.

  Delegates to `Metastatic.AST.to_string/1`.

  ## Examples

      iex> ast = {:binary_op, [category: :arithmetic, operator: :+],
      ...>   [{:variable, [], "x"}, {:literal, [subtype: :integer], 5}]}
      iex> Metastatic.to_string(ast)
      "x + 5"
  """
  defdelegate to_string(ast), to: AST

  # ----- Predicates (mirrors Macro.quoted_literal?/1, Macro.operator?/2) -----

  @doc """
  Returns `true` if the MetaAST represents a purely literal value.

  Delegates to `Metastatic.AST.literal?/1`.

  ## Examples

      iex> Metastatic.literal?({:literal, [subtype: :integer], 42})
      true

      iex> Metastatic.literal?({:variable, [], "x"})
      false
  """
  defdelegate literal?(ast), to: AST

  @doc """
  Returns `true` if the node is a binary or unary operator.

  Delegates to `Metastatic.AST.operator?/1`.

  ## Examples

      iex> Metastatic.operator?({:binary_op, [category: :arithmetic, operator: :+], [{:variable, [], "x"}, {:literal, [subtype: :integer], 1}]})
      true

      iex> Metastatic.operator?({:literal, [subtype: :integer], 42})
      false
  """
  defdelegate operator?(ast), to: AST

  # ----- Validation (mirrors Macro.validate/1) -----

  @doc """
  Validates AST structure, returning `:ok` or `{:error, reason}`.

  Delegates to `Metastatic.AST.validate/1`.

  ## Examples

      iex> Metastatic.validate({:literal, [subtype: :integer], 42})
      :ok

      iex> Metastatic.validate("not an ast")
      {:error, {:not_an_ast_node, "not an ast"}}
  """
  defdelegate validate(ast), to: AST

  # ----- Unique Variables (mirrors Macro.unique_var/2) -----

  @doc """
  Generates a unique variable MetaAST node.

  Delegates to `Metastatic.AST.unique_var/1`.

  ## Examples

      iex> {:variable, _, name} = Metastatic.unique_var("tmp")
      iex> String.starts_with?(name, "tmp_")
      true
  """
  defdelegate unique_var(prefix), to: AST
end
