defmodule Metastatic.Adapter do
  @moduledoc """
  Behaviour for language adapters (M1 ↔ M2 transformations).

  Language adapters bridge between:
  - **M1:** Language-specific ASTs (Python, JavaScript, Elixir, etc.)
  - **M2:** MetaAST meta-model

  ## Meta-Modeling Operations

  - `parse/1`: Source → M1 (language-specific parsing)
  - `to_meta/1`: M1 → M2 (abstraction to meta-level)
  - `from_meta/2`: M2 → M1 (reification from meta-level)
  - `unparse/1`: M1 → Source (language-specific unparsing)

  ## Conformance

  Adapters must ensure:
  1. M1 instances conform to M2 meta-model
  2. M2 → M1 → M2 round-trips preserve semantics
  3. Invalid M2 transformations are rejected at M1 level

  ## Theory

  In formal terms, a language adapter is a pair of functions:

      Adapter_L = ⟨α_L, ρ_L⟩

      where:
        α_L: AS_L → MetaAST × Metadata    (abstraction)
        ρ_L: MetaAST × Metadata → AS_L    (reification)

  These functions form a Galois connection between M1 and M2 levels.

  ## Example Implementation

      defmodule Metastatic.Adapters.Python do
        @behaviour Metastatic.Adapter

        @impl true
        def parse(source) do
          # Call Python AST parser (via port or NIF)
          {:ok, python_ast}
        end

        @impl true
        def to_meta(python_ast) do
          # Transform Python AST (M1) to MetaAST (M2)
          # Example: BinOp(op=Add()) → {:binary_op, :arithmetic, :+, ...}
          {:ok, meta_ast, metadata}
        end

        @impl true
        def from_meta(meta_ast, metadata) do
          # Transform MetaAST (M2) back to Python AST (M1)
          {:ok, python_ast}
        end

        @impl true
        def unparse(python_ast) do
          # Convert Python AST back to source code
          {:ok, source}
        end

        @impl true
        def file_extensions, do: [".py"]
      end

  ## Semantic Equivalence

  Different M1 models may map to the same M2 instance:

      # Python (M1)
      BinOp(op=Add(), left=Name('x'), right=Num(5))

      # JavaScript (M1)
      BinaryExpression(operator: '+', left: Identifier('x'), right: Literal(5))

      # Both abstract to the SAME M2 instance:
      {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}}

  This is the foundation of universal transformations.
  """

  alias Metastatic.{AST, Document}

  @typedoc """
  Native AST in the language-specific format (M1 level).

  This is an opaque term - the structure varies by language.
  """
  @type native_ast :: term()

  @typedoc """
  MetaAST representation (M2 level).
  """
  @type meta_ast :: AST.node()

  @typedoc """
  Metadata preserving M1-specific information.

  Contains details that cannot be represented at M2 level but are
  necessary for high-fidelity round-trips.
  """
  @type metadata :: map()

  @typedoc """
  Source code as a string.
  """
  @type source :: String.t()

  # ----- Required Callbacks -----

  @doc """
  Parse source code to native AST (Source → M1).

  This is a language-specific operation that produces the M1 representation.

  ## Implementation Notes

  - May spawn external processes (Python, Node.js, etc.)
  - May use native Elixir parsing (for Elixir adapter)
  - Should validate syntax and return clear error messages

  ## Examples

      # Python adapter
      parse("x + 5")
      # => {:ok, %{"_type" => "BinOp", "op" => %{"_type" => "Add"}, ...}}

      # JavaScript adapter
      parse("x + 5")
      # => {:ok, %{"type" => "BinaryExpression", "operator" => "+", ...}}
  """
  @callback parse(source) :: {:ok, native_ast} | {:error, reason :: term()}

  @doc """
  Transform native AST to MetaAST (M1 → M2 abstraction).

  This is the **abstraction operation** that lifts language-specific
  AST (M1) to the meta-level (M2).

  ## Semantic Equivalence

  Different M1 models may map to the same M2 instance:
  - Python: `BinOp(op=Add)` → `{:binary_op, :arithmetic, :+, ...}`
  - JavaScript: `BinaryExpression(operator: '+')` → same M2 instance
  - Elixir: `{:+, [], [...]}` → same M2 instance

  ## Return Value

  Returns a tuple of `{meta_ast, metadata}` where:
  - `meta_ast` is the M2 representation
  - `metadata` preserves M1-specific information for round-tripping

  ## Examples

      # Python BinOp to MetaAST
      to_meta(%{"_type" => "BinOp", "op" => %{"_type" => "Add"}, ...})
      # => {:ok,
      #     {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}},
      #     %{native_lang: :python, ...}}
  """
  @callback to_meta(native_ast) :: {:ok, meta_ast, metadata} | {:error, reason :: term()}

  @doc """
  Transform MetaAST back to native AST (M2 → M1 reification).

  This is the **reification operation** that instantiates the meta-model (M2)
  into a concrete language AST (M1).

  Uses metadata to restore M1-specific information that was preserved
  during abstraction (e.g., formatting, type annotations, etc.).

  ## Conformance Validation

  Implementation must ensure the resulting M1 AST:
  1. Is valid for the target language
  2. Preserves the semantics of the M2 instance
  3. Can be round-tripped (M1 → M2 → M1 ≈ M1)

  ## Examples

      # MetaAST to Python BinOp
      from_meta(
        {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}},
        %{native_lang: :python}
      )
      # => {:ok, %{"_type" => "BinOp", "op" => %{"_type" => "Add"}, ...}}
  """
  @callback from_meta(meta_ast, metadata) :: {:ok, native_ast} | {:error, reason :: term()}

  @doc """
  Convert native AST back to source code (M1 → Source).

  This is the final step in the M2 → M1 → Source pipeline.

  ## Implementation Notes

  - May use language-specific unparsers/pretty-printers
  - Should attempt to preserve formatting where possible
  - May normalize formatting to language conventions

  ## Examples

      # Python AST to source
      unparse(%{"_type" => "BinOp", ...})
      # => {:ok, "x + 5"}
  """
  @callback unparse(native_ast) :: {:ok, source} | {:error, reason :: term()}

  @doc """
  Return the file extensions this adapter handles.

  Used for automatic language detection.

  ## Examples

      # Python adapter
      file_extensions()
      # => [".py"]

      # JavaScript/TypeScript adapter
      file_extensions()
      # => [".js", ".jsx", ".ts", ".tsx"]
  """
  @callback file_extensions() :: [String.t()]

  # ----- Optional Callbacks -----

  @doc """
  Validate that an M2 transformation produces valid M1.

  After a mutation at M2 level, validate that the result:
  1. Conforms to M2 meta-model structurally
  2. Can be instantiated in this language (M1 conformance)
  3. Satisfies language-specific constraints

  ## Examples

  - **Rust:** Reject mutations that violate ownership/borrowing
  - **TypeScript:** Reject mutations that violate type constraints
  - **Python:** Most mutations valid (dynamic typing)

  This is M2 → M1 **semantic conformance validation**.

  ## Default Implementation

  If not implemented, assumes all M2-valid transformations are M1-valid.
  """
  @callback validate_mutation(meta_ast, metadata) ::
              :ok | {:error, validation_error :: String.t()}

  @optional_callbacks validate_mutation: 2

  # ----- Helper Functions -----

  @doc """
  Full round-trip: Source → M1 → M2 → M1 → Source.

  Useful for testing adapter fidelity.

  ## Examples

      iex> source = "x + 5"
      iex> Metastatic.Adapter.round_trip(MyAdapter, source)
      {:ok, "x + 5"}  # May have normalized formatting
  """
  @spec round_trip(module(), source) :: {:ok, source} | {:error, term()}
  def round_trip(adapter, source) do
    with {:ok, native_ast} <- adapter.parse(source),
         {:ok, meta_ast, metadata} <- adapter.to_meta(native_ast),
         {:ok, native_ast2} <- adapter.from_meta(meta_ast, metadata) do
      adapter.unparse(native_ast2)
    end
  end

  @doc """
  Abstraction pipeline: Source → M1 → M2 (Document).

  Convenience function that combines parse and to_meta.

  ## Examples

      iex> Metastatic.Adapter.abstract(MyAdapter, "x + 5")
      {:ok, %Metastatic.Document{
        ast: {:binary_op, :arithmetic, :+, ...},
        language: :python,
        metadata: %{...},
        original_source: "x + 5"
      }}
  """
  @spec abstract(module(), source, atom()) :: {:ok, Document.t()} | {:error, term()}
  def abstract(adapter, source, language) do
    with {:ok, native_ast} <- adapter.parse(source),
         {:ok, meta_ast, metadata} <- adapter.to_meta(native_ast) do
      doc = Document.new(meta_ast, language, metadata, source)
      {:ok, doc}
    end
  end

  @doc """
  Reification pipeline: M2 (Document) → M1 → Source.

  Convenience function that combines from_meta and unparse.

  ## Examples

      iex> doc = %Metastatic.Document{
      ...>   ast: {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}},
      ...>   language: :python,
      ...>   metadata: %{}
      ...> }
      iex> Metastatic.Adapter.reify(MyAdapter, doc)
      {:ok, "x + 5"}
  """
  @spec reify(module(), Document.t()) :: {:ok, source} | {:error, term()}
  def reify(adapter, %Document{ast: meta_ast, metadata: metadata}) do
    with {:ok, native_ast} <- adapter.from_meta(meta_ast, metadata) do
      adapter.unparse(native_ast)
    end
  end

  @doc """
  Validate that an adapter correctly implements the behaviour.

  Checks that all required callbacks are defined.

  ## Examples

      iex> Metastatic.Adapter.valid_adapter?(MyPythonAdapter)
      true

      iex> Metastatic.Adapter.valid_adapter?(InvalidModule)
      false
  """
  @spec valid_adapter?(module()) :: boolean()
  def valid_adapter?(adapter) do
    required_callbacks = [
      {:parse, 1},
      {:to_meta, 1},
      {:from_meta, 2},
      {:unparse, 1},
      {:file_extensions, 0}
    ]

    Enum.all?(required_callbacks, fn {fun, arity} ->
      function_exported?(adapter, fun, arity)
    end)
  end

  @doc """
  Get adapter module for a language.

  Returns the appropriate adapter module for a given language atom.

  ## Examples

      iex> Metastatic.Adapter.for_language(:python)
      {:ok, Metastatic.Adapters.Python}

      iex> Metastatic.Adapter.for_language(:unknown)
      {:error, :no_adapter_found}
  """
  @spec for_language(atom()) :: {:ok, module()} | {:error, :no_adapter_found}
  def for_language(language) do
    adapter_module = Module.concat([Metastatic.Adapters, camelize(language)])

    if Code.ensure_loaded?(adapter_module) and valid_adapter?(adapter_module) do
      {:ok, adapter_module}
    else
      {:error, :no_adapter_found}
    end
  end

  @doc """
  Detect language from file extension.

  ## Examples

      iex> Metastatic.Adapter.detect_language("script.py")
      {:ok, :python}

      iex> Metastatic.Adapter.detect_language("app.js")
      {:ok, :javascript}

      iex> Metastatic.Adapter.detect_language("unknown.xyz")
      {:error, :unknown_extension}
  """
  @spec detect_language(String.t()) :: {:ok, atom()} | {:error, :unknown_extension}
  def detect_language(filename) do
    extension = Path.extname(filename)

    # This would be populated by registered adapters
    # For now, basic mapping
    case extension do
      ".py" -> {:ok, :python}
      ".js" -> {:ok, :javascript}
      ".jsx" -> {:ok, :javascript}
      ".ts" -> {:ok, :typescript}
      ".tsx" -> {:ok, :typescript}
      ".ex" -> {:ok, :elixir}
      ".exs" -> {:ok, :elixir}
      ".rb" -> {:ok, :ruby}
      ".go" -> {:ok, :go}
      ".rs" -> {:ok, :rust}
      _ -> {:error, :unknown_extension}
    end
  end

  # Private helpers

  defp camelize(atom) do
    atom
    |> Atom.to_string()
    |> String.split("_")
    |> Enum.map_join(&String.capitalize/1)
  end
end
