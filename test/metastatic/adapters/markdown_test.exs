defmodule Metastatic.Adapters.MarkdownTest do
  @moduledoc """
  Behavioural tests for the Markdown adapter: M1 → M2 abstraction, M2 → M1
  reification, prose integration and cross-language equivalence.
  """

  use ExUnit.Case, async: true

  alias Metastatic.Adapters.Markdown
  alias Metastatic.NL.Adapters.English
  alias Metastatic.NL.Adapters.Markdown, as: NLMarkdown
  alias Metastatic.NL.{AST, Lint, Validator}

  @document """
  # Project Title

  This guide explains **installation** and the *first* run.

  ## Install

  1. Add the dependency
  2. Run `mix deps.get`

  ```elixir
  def hello, do: :world
  ```

  - [x] done
  - [ ] pending

  > A quoted note.

  | Name | Type |
  | :--- | ---: |
  | id   | integer |

  See the [docs](https://hexdocs.pm) for details.
  """

  defp abstract!(source) do
    {:ok, cst} = Markdown.parse(source)
    {:ok, ast, metadata} = Markdown.to_meta(cst)
    {ast, metadata}
  end

  describe "parse/1" do
    test "produces a markdown CST document" do
      assert {:ok, %{"type" => "document", "language" => "markdown"}} = Markdown.parse("# Hi")
    end

    test "the NL facade and the top-level facade agree" do
      assert Markdown.parse("# Hi") == NLMarkdown.parse("# Hi")
    end
  end

  describe "to_meta/1 abstraction" do
    test "produces a conforming NL-MetaAST document" do
      {ast, metadata} = abstract!(@document)

      assert AST.conforms?(ast)
      assert AST.type(ast) == :document
      assert metadata.language == :markdown
      assert AST.get_meta(ast, :format) == :markdown
    end

    test "models headings with levels" do
      {ast, _} = abstract!(@document)

      levels = ast |> AST.headings() |> Enum.map(&AST.get_meta(&1, :level))
      assert levels == [1, 2]
    end

    test "keeps code blocks opaque" do
      {ast, _} = abstract!(@document)

      assert [code_block] = AST.code_blocks(ast)
      assert AST.children(code_block) == "def hello, do: :world"
      assert AST.get_meta(code_block, :language) == "elixir"
    end

    test "models lists, task items and tables" do
      {ast, _} = abstract!(@document)

      assert length(AST.all(ast, :list_block)) == 2
      assert length(AST.all(ast, :task_item)) == 2
      assert [table] = AST.tables(ast)
      # header row + one body row
      assert length(AST.all(table, :table_row)) == 2
    end

    test "models inline spans and links" do
      {ast, _} = abstract!(@document)

      assert [_strong] = AST.all(ast, :strong)
      assert [_emphasis] = AST.all(ast, :emphasis)
      assert [_inline_code] = AST.all(ast, :inline_code)
      assert [link] = AST.links(ast)
      assert AST.get_meta(link, :destination) == "https://hexdocs.pm"
    end

    test "chunks prose into sentences and clauses" do
      {ast, _} = abstract!(@document)

      assert length(AST.sentences(ast)) >= 2
      assert length(AST.clauses(ast)) >= 2
    end

    test "code is excluded from reconstructed text" do
      {ast, _} = abstract!(@document)

      text = AST.text(ast)
      refute text =~ "def hello"
      assert text =~ "Project Title"
      assert text =~ "installation"
    end

    test "enriches clauses with voice and readability metadata" do
      {ast, _} = abstract!("The migration was executed by the operator.")

      assert [clause] = AST.clauses(ast)
      assert AST.get_meta(clause, :voice) == :passive
      assert is_map(AST.get_meta(ast, :readability))
    end

    test "rejects non-CST input" do
      assert {:error, _} = Markdown.to_meta(%{"nope" => true})
    end
  end

  describe "from_meta/2 and unparse/1" do
    test "reifies a document back to markdown source" do
      {ast, metadata} = abstract!(@document)

      assert {:ok, cst} = Markdown.from_meta(ast, metadata)
      assert {:ok, source} = Markdown.unparse(cst)

      assert source =~ "# Project Title"
      assert source =~ "## Install"
      assert source =~ "```elixir"
      assert source =~ "| Name | Type |"
      assert source =~ "- [x] done"
      assert source =~ "> A quoted note."
    end

    test "preserves inline emphasis and links" do
      {ast, metadata} = abstract!("Use **bold** and [docs](https://x.dev).")
      {:ok, cst} = Markdown.from_meta(ast, metadata)
      {:ok, source} = Markdown.unparse(cst)

      assert source =~ "**bold**"
      assert source =~ "[docs](https://x.dev)"
    end

    test "unparses an M2 node directly" do
      doc = AST.document([AST.heading(1, [AST.token("Title")])])
      assert {:ok, "# Title"} = Markdown.unparse(doc)
    end

    test "rejects unparseable input" do
      assert {:error, _} = Markdown.unparse(42)
    end

    test "round-trips table alignment" do
      source = "| a | b |\n| :--- | ---: |\n| 1 | 2 |"
      {ast, metadata} = abstract!(source)
      {:ok, cst} = Markdown.from_meta(ast, metadata)
      {:ok, output} = Markdown.unparse(cst)

      assert output =~ "| :--- | ---: |"
    end
  end

  describe "integration with M2 facilities" do
    test "validates as an NL document with no native escapes" do
      {ast, _} = abstract!(@document)

      assert {:ok, metrics} = Validator.validate(ast)
      # Task items are M2.2 Extended markup, so the document is `:extended`.
      assert metrics.level == :extended
      assert metrics.native_nodes == 0
      assert metrics.sentences >= 2
    end

    test "prose linting runs on prose but not on code" do
      source = """
      The migration was executed by the operator.

      ```elixir
      # Clearly the whitelist is fine in code.
      ```
      """

      {ast, _} = abstract!(source)
      issues = Lint.Runner.lint(ast)
      rules = Enum.map(issues, & &1.rule)

      assert :avoid_passive_voice in rules
      refute Enum.any?(issues, &(&1.message =~ "whitelist"))
    end

    test "lint_source/2 accepts format: :markdown" do
      assert {:ok, issues} =
               Lint.Runner.lint_source("The task was completed by the bot.",
                 format: :markdown,
                 rules: [Lint.Rules.AvoidPassiveVoice]
               )

      assert [%{rule: :avoid_passive_voice}] = issues
    end

    test "readability metrics are attached to the document" do
      {ast, _} = abstract!("Short sentences read well. They stay focused.")

      assert %{words_count: count, sentences_count: 2} = AST.get_meta(ast, :readability)
      assert count > 5
    end

    test "semantic enrichment adds voice/roles but no programming-language op_kind" do
      {ast, _} = abstract!("Call the service. Then wait.")

      # The NL enricher runs (voice + semantic roles) …
      assert [clause | _] = AST.clauses(ast)
      assert AST.get_meta(clause, :voice) == :active

      # … but no programming-language OpKind metadata is attached anywhere.
      refute Enum.any?(AST.prewalker(ast), fn
               {_type, meta, _children} when is_list(meta) ->
                 Keyword.has_key?(meta, :op_kind) or Keyword.has_key?(meta, :callback_for)

               _ ->
                 false
             end)
    end
  end

  describe "cross-language equivalence" do
    test "markdown prose and plain prose canonicalise to the same NL-MetaAST" do
      {md_ast, _} = abstract!("The system processes events.")

      {:ok, cst} = English.parse("The system processes events.")
      {:ok, prose_ast, _} = English.to_meta(cst)

      strip = fn node ->
        AST.postwalk(node, fn
          {type, meta, children} when type in [:document, :heading] ->
            {type, Keyword.drop(meta, [:format, :level]), children}

          other ->
            other
        end)
      end

      assert AST.words(md_ast) == AST.words(prose_ast)
      assert AST.lemmas(strip.(md_ast)) == AST.lemmas(strip.(prose_ast))
    end
  end
end
