defmodule Metastatic.NL.ASTTest do
  use ExUnit.Case, async: true
  alias Metastatic.NL.AST

  describe "node constructors" do
    test "constructs leaf token with metadata" do
      t = AST.token("analysis", pos: :noun, lemma: "analysis")
      assert {:token, [pos: :noun, lemma: "analysis"], "analysis"} = t
      assert AST.type(t) == :token
      assert AST.children(t) == "analysis"
      assert AST.get_meta(t, :pos) == :noun
      assert AST.get_meta(t, :lemma) == "analysis"
    end

    test "constructs punctuation node" do
      p = AST.punctuation(".")
      assert {:punctuation, [pos: :punctuation], "."} = p
      assert AST.type(p) == :punctuation
    end

    test "constructs phrase node" do
      child = AST.token("fast", pos: :adjective)
      p = AST.phrase(:adj_phrase, [child])
      assert {:phrase, meta, [^child]} = p
      assert Keyword.get(meta, :type) == :adj_phrase
    end

    test "constructs clause, sentence, paragraph, document" do
      subj = AST.phrase(:noun_phrase, [AST.token("Code", pos: :noun)])
      verb = AST.phrase(:verb_phrase, [AST.token("runs", pos: :verb)])
      clause = AST.clause([subj, verb], voice: :active, tense: :present)
      punct = AST.punctuation(".")
      sentence = AST.sentence([clause, punct], kind: :declarative)
      para = AST.paragraph([sentence])
      doc = AST.document([para], language: :en, format: :markdown)

      assert {:document, [language: :en, format: :markdown], [^para]} = doc
      assert AST.conforms?(doc)
    end
  end

  describe "conformance checking" do
    test "validates proper 3-tuple conforming structures" do
      t = AST.token("hello", pos: :interjection)
      assert AST.conforms?(t)

      # Elided token (e.g. pro-drop)
      assert AST.conforms?({:token, [implicit: true], nil})

      # Punctuation
      assert AST.conforms?({:punctuation, [pos: :punctuation], "!"})

      # Non-conforming: invalid type atom
      refute AST.conforms?({:invalid_random_type, [], []})

      # Non-conforming: non-keyword meta
      refute AST.conforms?({:token, "not-a-kw-list", "hello"})

      # Non-conforming: not a 3-tuple
      refute AST.conforms?({:token, []})
      refute AST.conforms?("just a string")
    end
  end

  describe "traversals and extraction" do
    setup do
      subj =
        AST.phrase(:noun_phrase, [
          AST.token("The", pos: :determiner),
          AST.token("system", pos: :noun, lemma: "system")
        ])

      verb =
        AST.phrase(:verb_phrase, [
          AST.token("processes", pos: :verb, lemma: "process")
        ])

      obj =
        AST.phrase(:noun_phrase, [
          AST.token("events", pos: :noun, lemma: "event")
        ])

      clause = AST.clause([subj, verb, obj], voice: :active)
      sent = AST.sentence([clause, AST.punctuation(".")])
      %{ast: sent}
    end

    test "tokens/1 extracts all token nodes", %{ast: ast} do
      toks = AST.tokens(ast)
      assert length(toks) == 4
      assert Enum.map(toks, &AST.children/1) == ["The", "system", "processes", "events"]
    end

    test "words/1 extracts all words", %{ast: ast} do
      assert AST.words(ast) == ["The", "system", "processes", "events"]
    end

    test "lemmas/1 extracts unique lemmas", %{ast: ast} do
      assert AST.lemmas(ast) == ["The", "system", "process", "event"]
    end

    test "sentences/1 and clauses/1 extract corresponding nodes", %{ast: ast} do
      assert length(AST.sentences(ast)) == 1
      assert length(AST.clauses(ast)) == 1
      assert length(AST.phrases(ast)) == 3
    end

    test "text/1 reconstructs surface text", %{ast: ast} do
      assert AST.text(ast) == "The system processes events."
    end

    test "prewalk/2 and postwalk/2 modify nodes", %{ast: ast} do
      upcased =
        AST.prewalk(ast, fn
          {:token, meta, val} -> {:token, meta, String.upcase(val)}
          other -> other
        end)

      assert AST.words(upcased) == ["THE", "SYSTEM", "PROCESSES", "EVENTS"]
    end
  end

  describe "layer categorization" do
    test "correctly categorizes core, extended, and native types" do
      assert AST.core_type?(:token)
      assert AST.core_type?(:clause)
      assert AST.core_type?(:sentence)

      assert AST.extended_type?(:named_entity)
      assert AST.extended_type?(:coreference)

      assert AST.native_type?(:native_nl_feature)
      refute AST.core_type?(:native_nl_feature)
    end
  end
end
