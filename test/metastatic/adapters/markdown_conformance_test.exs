defmodule Metastatic.Adapters.MarkdownConformanceTest do
  @moduledoc """
  Uniform conformance suite for the Markdown adapter (see
  `Metastatic.Test.AdapterConformance`).

  Unlike the programming-language adapters, the Markdown adapter's `to_meta/1`
  produces NL-MetaAST, so this module overrides the generic MetaAST
  conformance assertions with NL-MetaAST ones.
  """
  use ExUnit.Case, async: true

  alias Metastatic.{Adapter, Document, Languages}
  alias Metastatic.NL.Adapters.Markdown
  alias Metastatic.NL.AST
  alias Metastatic.NL.Validator

  @adapter Metastatic.Adapters.Markdown

  test "implements the Metastatic.Adapter behaviour" do
    assert Adapter.valid_adapter?(@adapter)
    assert Adapter.valid_adapter?(Markdown)
  end

  test "file_extensions/0 returns dot-prefixed extensions" do
    assert @adapter.file_extensions() == [".md", ".markdown"]
  end

  test "is discoverable through Metastatic.Languages" do
    assert Languages.supported?(:markdown)
    assert {:ok, @adapter} = Languages.get_adapter(:markdown)
    assert {:ok, :markdown} = Languages.detect_language("README.md")
    assert {:ok, :markdown} = Languages.detect_language("GUIDE.markdown")
  end

  test "parse/1 accepts valid input and rejects non-binary input" do
    assert {:ok, %{"type" => "document"}} = @adapter.parse("# Title")
    assert {:error, _reason} = @adapter.parse(:not_a_binary)
  end

  test "to_meta/1 produces a conforming NL-MetaAST" do
    {:ok, cst} = @adapter.parse("# Title\n\nSome prose.")
    assert {:ok, meta_ast, metadata} = @adapter.to_meta(cst)
    assert AST.conforms?(meta_ast)
    assert metadata.language == :markdown

    doc = Document.new(meta_ast, :markdown, metadata, "# Title")
    assert {:ok, _} = Validator.validate(doc.ast)
  end

  test "from_meta/2 reifies a simple NL-MetaAST" do
    ast =
      AST.document([
        AST.heading(2, [AST.token("Usage")]),
        AST.paragraph([AST.sentence([AST.clause([AST.token("Hello"), AST.punctuation(".")])])])
      ])

    assert {:ok, cst} = @adapter.from_meta(ast, %{})
    assert {:ok, source} = @adapter.unparse(cst)
    assert source =~ "## Usage"
    assert source =~ "Hello."
  end

  test "a document round-trips to an equivalent NL-MetaAST" do
    source = "# Title\n\nA sentence here. Another one.\n\n- item one\n- item two"

    {:ok, cst} = @adapter.parse(source)
    {:ok, meta_ast, metadata} = @adapter.to_meta(cst)
    {:ok, cst2} = @adapter.from_meta(meta_ast, metadata)
    {:ok, source2} = @adapter.unparse(cst2)

    {:ok, cst3} = @adapter.parse(source2)
    {:ok, meta_ast2, _} = @adapter.to_meta(cst3)

    assert AST.text(meta_ast2) == AST.text(meta_ast)
  end
end
