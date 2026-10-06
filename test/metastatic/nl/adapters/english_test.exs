defmodule Metastatic.NL.Adapters.EnglishTest do
  use ExUnit.Case, async: true
  alias Metastatic.NL.Adapters.English
  alias Metastatic.NL.AST
  alias Metastatic.Adapter

  describe "adapter behaviour conformance" do
    test "implements Metastatic.Adapter behaviour" do
      assert Adapter.valid_adapter?(English)
      assert Adapter.valid_adapter?(Metastatic.Adapters.English)
      assert ".md" in English.file_extensions()
    end
  end

  describe "parsing and transformation pipeline" do
    test "parses simple English prose into NL-MetaAST" do
      text = "The quick brown fox jumps over the lazy dog."
      assert {:ok, cst} = English.parse(text)
      assert {:ok, meta_ast, meta} = English.to_meta(cst)

      assert meta.language == :en
      assert AST.conforms?(meta_ast)
      assert AST.type(meta_ast) == :document

      # Verify sentences and phrases
      [sentence] = AST.sentences(meta_ast)
      assert AST.get_meta(sentence, :kind) == :declarative

      words = AST.words(meta_ast)
      assert "quick" in words
      assert "fox" in words
      assert "jumps" in words

      # Verify round trip text
      assert AST.text(sentence) =~ "The quick brown fox jumps over the lazy dog."
    end

    test "handles multiple paragraphs and questions" do
      text = """
      Is the database connection alive?

      The system processes user requests.
      """

      assert {:ok, cst} = English.parse(text)
      assert {:ok, meta_ast, _} = English.to_meta(cst)

      sentences = AST.sentences(meta_ast)
      assert length(sentences) == 2

      [first_sent, second_sent] = sentences
      assert AST.get_meta(first_sent, :kind) == :interrogative
      assert AST.get_meta(second_sent, :kind) == :declarative
    end

    test "round-trip unparsing" do
      text = "Documentation must be clear."
      assert {:ok, cst} = English.parse(text)
      assert {:ok, meta_ast, metadata} = English.to_meta(cst)
      assert {:ok, cst2} = English.from_meta(meta_ast, metadata)
      assert {:ok, unparsed} = English.unparse(cst2)
      assert unparsed =~ "Documentation must be clear."
    end
  end
end
