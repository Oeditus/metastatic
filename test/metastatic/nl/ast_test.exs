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

    test "markup blocks and inline spans live in the core layer" do
      for type <- [
            :heading,
            :block_quote,
            :code_block,
            :table,
            :table_row,
            :table_cell,
            :thematic_break,
            :emphasis,
            :strong,
            :strikethrough,
            :link,
            :image,
            :inline_code,
            :line_break
          ] do
        assert AST.core_type?(type), "expected #{type} to be a core type"
      end
    end

    test "markup extensions live in the extended layer" do
      for type <- [:code_fence, :task_item, :reference_link, :footnote] do
        assert AST.extended_type?(type), "expected #{type} to be an extended type"
      end
    end
  end

  describe "markup constructors" do
    test "heading/3 stores the level" do
      heading = AST.heading(3, [AST.token("Title")])
      assert {:heading, meta, [_]} = heading
      assert Keyword.get(meta, :level) == 3
      assert AST.conforms?(heading)
    end

    test "code_block/2 keeps raw code as its value" do
      block = AST.code_block("IO.puts(1)", language: "elixir")
      assert AST.children(block) == "IO.puts(1)"
      assert AST.get_meta(block, :language) == "elixir"
      assert AST.conforms?(block)
    end

    test "inline_code/2 and link/3" do
      assert AST.children(AST.inline_code("x = 1")) == "x = 1"

      link = AST.link([AST.token("docs")], "https://x.dev", title: "Docs")
      assert AST.get_meta(link, :destination) == "https://x.dev"
      assert AST.get_meta(link, :title) == "Docs"
      assert AST.conforms?(link)
    end

    test "table/1, table_row/1 and table_cell/1 compose" do
      cell = AST.table_cell([AST.token("id")])
      row = AST.table_row([cell], header?: true)
      table = AST.table([row], align: ["left"])

      assert AST.conforms?(table)
      assert [^row] = AST.children(table)
      assert [^cell] = AST.children(row)
    end

    test "task_item/3 records the checkbox state" do
      done = AST.task_item(true, [AST.token("done")])
      todo = AST.task_item(false, [AST.token("todo")])

      assert AST.get_meta(done, :checked) == true
      assert AST.get_meta(todo, :checked) == false
      assert AST.conforms?(done)
    end

    test "list_block/2 and list_item/2" do
      block = AST.list_block([AST.list_item([AST.token("one")])], ordered: true)
      assert AST.get_meta(block, :ordered) == true
      assert AST.conforms?(block)
    end

    test "thematic_break/1 and line_break/1" do
      assert AST.conforms?(AST.thematic_break())
      assert AST.conforms?(AST.line_break())
    end
  end

  describe "markup conformance" do
    test "rejects headings without an integer level" do
      refute AST.conforms?({:heading, [], [AST.token("x")]})
    end

    test "rejects non-binary code values" do
      refute AST.conforms?({:code_block, [], 42})
      refute AST.conforms?({:inline_code, [], [:not_a_binary]})
    end

    test "rejects composite markup with non-conforming children" do
      refute AST.conforms?({:strong, [], [{:bogus, [], []}]})
    end
  end

  describe "markup text rendering" do
    test "renders inline spans as plain text" do
      doc =
        AST.document([
          AST.paragraph([
            AST.sentence([
              AST.clause([
                AST.strong([AST.token("Bold")]),
                AST.token("and"),
                AST.emphasis([AST.token("italic")])
              ])
            ])
          ])
        ])

      assert AST.text(doc) == "Bold and italic"
    end

    test "omits code from rendered text" do
      doc =
        AST.document([
          AST.code_block("def secret, do: 1"),
          AST.paragraph([
            AST.sentence([
              AST.clause([AST.token("Run"), AST.inline_code("mix test"), AST.punctuation(".")])
            ])
          ])
        ])

      text = AST.text(doc)
      refute text =~ "secret"
      refute text =~ "mix test"
      assert text =~ "Run"
    end

    test "separates block-level markup" do
      doc =
        AST.document([
          AST.heading(1, [AST.token("Title")]),
          AST.paragraph([AST.sentence([AST.clause([AST.token("Body")])])]),
          AST.list_block([AST.list_item([AST.token("Item")])])
        ])

      assert AST.text(doc) == "Title\n\nBody\nItem"
    end
  end
end
