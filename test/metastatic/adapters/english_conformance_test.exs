defmodule Metastatic.Adapters.EnglishConformanceTest do
  @moduledoc """
  Uniform conformance suite for the English NL adapter.

  Like `MarkdownConformanceTest`, this verifies the `Metastatic.Adapter`
  contract against NL-MetaAST.
  """
  use ExUnit.Case, async: true

  alias Metastatic.Adapter
  alias Metastatic.NL.Adapters.English
  alias Metastatic.NL.{AST, Validator}

  @adapter Metastatic.Adapters.English

  test "implements the Metastatic.Adapter behaviour" do
    assert Adapter.valid_adapter?(@adapter)
    assert Adapter.valid_adapter?(English)
    assert @adapter.available?() == true
  end

  test "file_extensions/0 returns dot-prefixed extensions" do
    extensions = @adapter.file_extensions()
    assert is_list(extensions) and extensions != []
    assert Enum.all?(extensions, &(is_binary(&1) and String.starts_with?(&1, ".")))
  end

  test "parse/1 accepts valid input and rejects non-binary input" do
    assert {:ok, %{"type" => "document"}} = @adapter.parse("Hello world.")
    assert {:error, _reason} = @adapter.parse(:not_a_binary)
  end

  test "to_meta/1 produces a conforming NL-MetaAST" do
    {:ok, cst} = @adapter.parse("The compiler builds the binary.")
    assert {:ok, meta_ast, metadata} = @adapter.to_meta(cst)
    assert AST.conforms?(meta_ast)
    assert is_map(metadata)
    assert {:ok, _} = Validator.validate(meta_ast)
  end

  test "from_meta/2 reifies a simple NL-MetaAST" do
    ast =
      AST.document([
        AST.paragraph([AST.sentence([AST.clause([AST.token("Hello"), AST.punctuation(".")])])])
      ])

    assert {:ok, cst} = @adapter.from_meta(ast, %{})
    assert {:ok, source} = @adapter.unparse(cst)
    assert source =~ "Hello."
  end

  test "a document round-trips to an equivalent NL-MetaAST" do
    source = "The system processes data. The output is valid."

    {:ok, cst} = @adapter.parse(source)
    {:ok, meta_ast, metadata} = @adapter.to_meta(cst)
    {:ok, cst2} = @adapter.from_meta(meta_ast, metadata)
    {:ok, source2} = @adapter.unparse(cst2)

    {:ok, cst3} = @adapter.parse(source2)
    {:ok, meta_ast2, _} = @adapter.to_meta(cst3)

    assert AST.text(meta_ast2) == AST.text(meta_ast)
  end
end
