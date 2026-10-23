defmodule Metastatic.Test.AdapterConformance do
  @moduledoc """
  A reusable conformance suite for language adapters.

  Including this macro in an adapter test module generates a uniform set of
  assertions that every adapter must satisfy:

    * it implements the `Metastatic.Adapter` behaviour
    * `file_extensions/0` returns a non-empty list of `.`-prefixed strings
    * it is discoverable through `Metastatic.Languages`
    * `parse/1` returns `{:ok, _}` for valid input and `{:error, _}` for junk
    * `to_meta/1` produces a structurally conforming MetaAST
    * `from_meta/2` reifies a simple MetaAST back to a native AST
    * `unparse/1` produces a non-empty binary
    * a simple expression round-trips to a semantically equivalent AST

  This gives every adapter — including experimental ones — the same quality
  bar and makes a missing callback or a broken reification path fail loudly.

  ## Usage

      defmodule Metastatic.Adapters.PythonConformanceTest do
        use ExUnit.Case, async: true
        use Metastatic.Test.AdapterConformance,
          adapter: Metastatic.Adapters.Python,
          language: :python,
          # A snippet the adapter can parse and a MetaAST it can reify.
          sample: "1 + 2",
          sample_ast: {:binary_op, [category: :arithmetic, operator: :+],
                       [{:literal, [subtype: :integer], 1},
                        {:literal, [subtype: :integer], 2}]}
      end
  """

  defmacro __using__(opts) do
    adapter = Keyword.fetch!(opts, :adapter)
    language = Keyword.fetch!(opts, :language)
    sample = Keyword.fetch!(opts, :sample)
    sample_ast = Keyword.fetch!(opts, :sample_ast)

    quote do
      alias Metastatic.{Adapter, AST, Document, Languages, Validator}

      @conformance_adapter unquote(adapter)
      @conformance_language unquote(language)
      @conformance_sample unquote(sample)

      # The sample MetaAST arrives as quoted AST (keyword args to `use` are
      # macro-expanded), so splicing it directly evaluates to the tuple at
      # runtime. Escaping it again would double-quote it into `{:{}, ...}`.
      defp conformance_ast, do: unquote(sample_ast)

      test "implements the Metastatic.Adapter behaviour" do
        assert Adapter.valid_adapter?(@conformance_adapter)
      end

      test "file_extensions/0 returns dot-prefixed extensions" do
        extensions = @conformance_adapter.file_extensions()
        assert is_list(extensions)
        refute Enum.empty?(extensions)

        assert Enum.all?(extensions, fn ext ->
                 is_binary(ext) and String.starts_with?(ext, ".")
               end)
      end

      test "is discoverable through Metastatic.Languages" do
        assert Languages.supported?(@conformance_language)
        assert {:ok, @conformance_adapter} = Languages.get_adapter(@conformance_language)

        assert {:ok, @conformance_language} =
                 Languages.detect_language("sample" <> hd(@conformance_adapter.file_extensions()))
      end

      test "parse/1 accepts valid input and rejects junk" do
        assert {:ok, _native} = @conformance_adapter.parse(@conformance_sample)
        assert {:error, _reason} = @conformance_adapter.parse("this is not valid @@#$%")
      end

      test "to_meta/1 produces a conforming MetaAST" do
        {:ok, native} = @conformance_adapter.parse(@conformance_sample)
        assert {:ok, meta_ast, metadata} = @conformance_adapter.to_meta(native)
        assert AST.conforms?(meta_ast)
        assert is_map(metadata)

        doc = Document.new(meta_ast, @conformance_language, metadata, @conformance_sample)
        assert {:ok, _} = Validator.validate(doc)
      end

      test "from_meta/2 reifies a simple MetaAST" do
        assert {:ok, native} = @conformance_adapter.from_meta(conformance_ast(), %{})
        assert {:ok, source} = @conformance_adapter.unparse(native)
        assert is_binary(source)
        assert String.length(String.trim(source)) > 0
      end

      test "a simple expression round-trips to an equivalent AST" do
        {:ok, native} = @conformance_adapter.parse(@conformance_sample)
        {:ok, meta_ast, metadata} = @conformance_adapter.to_meta(native)
        {:ok, native2} = @conformance_adapter.from_meta(meta_ast, metadata)
        {:ok, source} = @conformance_adapter.unparse(native2)

        {:ok, native3} = @conformance_adapter.parse(source)
        {:ok, meta_ast2, _} = @conformance_adapter.to_meta(native3)

        assert AST.canonicalize(meta_ast2) == AST.canonicalize(meta_ast)
      end
    end
  end
end
