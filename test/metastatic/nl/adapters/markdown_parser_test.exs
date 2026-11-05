defmodule Metastatic.NL.Adapters.Markdown.ParserTest do
  use ExUnit.Case, async: true

  alias Metastatic.NL.Adapters.Markdown.Parser

  doctest Metastatic.NL.Adapters.Markdown.Parser

  defp parse!(source) do
    {:ok, cst} = Parser.parse(source)
    cst
  end

  defp blocks(source), do: parse!(source)["children"]

  describe "document shape" do
    test "wraps blocks in a markdown document" do
      cst = parse!("# Title")
      assert %{"type" => "document", "language" => "markdown"} = cst
      assert [%{"type" => "heading"}] = cst["children"]
    end

    test "empty source yields an empty document" do
      assert %{"children" => []} = parse!("")
    end
  end

  describe "headings" do
    test "parses ATX headings with levels" do
      assert [%{"type" => "heading", "level" => 1, "text" => "One"}] = blocks("# One")

      assert [%{"level" => 3, "text" => "Three"}] = blocks("### Three")
    end

    test "parses setext headings" do
      assert [%{"type" => "heading", "level" => 1, "text" => "Title"}] = blocks("Title\n=====")
      assert [%{"level" => 2, "text" => "Sub"}] = blocks("Sub\n---")
    end

    test "records line numbers" do
      assert [%{"line" => 3}] = blocks("\n\n## Late")
    end
  end

  describe "paragraphs" do
    test "joins continuation lines" do
      assert [%{"type" => "paragraph", "text" => "one\ntwo"}] = blocks("one\ntwo")
    end

    test "separates paragraphs at blank lines" do
      assert [%{"text" => "a"}, %{"text" => "b"}] = blocks("a\n\nb")
    end

    test "a heading terminates a paragraph" do
      assert [%{"type" => "paragraph"}, %{"type" => "heading"}] = blocks("text\n# Heading")
    end
  end

  describe "code" do
    test "parses fenced code with info string" do
      source = "```elixir\ndef f, do: 1\n```"

      assert [%{"type" => "code_block", "value" => "def f, do: 1", "info" => "elixir"}] =
               blocks(source)
    end

    test "parses tilde fences" do
      assert [%{"type" => "code_block", "value" => "x"}] = blocks("~~~\nx\n~~~")
    end

    test "preserves markdown inside code fences verbatim" do
      source = "```\n# not a heading\n- not a list\n```"

      assert [%{"type" => "code_block", "value" => "# not a heading\n- not a list"}] =
               blocks(source)
    end

    test "parses indented code blocks" do
      assert [%{"type" => "code_block", "value" => "indented"}] = blocks("    indented")
    end
  end

  describe "block quotes" do
    test "collects quoted lines" do
      assert [%{"type" => "block_quote", "children" => [%{"text" => "quoted"}]}] =
               blocks("> quoted")
    end

    test "supports nested block content" do
      assert [%{"children" => [%{"type" => "heading"}]}] = blocks("> # Inside")
    end
  end

  describe "lists" do
    test "parses bullet lists in order" do
      assert [%{"type" => "list", "ordered" => false, "children" => items}] =
               blocks("- one\n- two\n- three")

      assert Enum.map(items, & &1["text"]) == ["one", "two", "three"]
    end

    test "parses ordered lists with start" do
      assert [%{"ordered" => true, "start" => 3, "children" => items}] =
               blocks("3. three\n4. four")

      assert Enum.map(items, & &1["text"]) == ["three", "four"]
    end

    test "parses GitHub task list items" do
      assert [%{"children" => [done, todo]}] = blocks("- [x] done\n- [ ] todo")
      assert done["task"] == true
      assert todo["task"] == false
    end

    test "collects continuation lines into the item as nested blocks" do
      assert [%{"children" => [%{"children" => [%{"text" => "continued"}]}]}] =
               blocks("- first\n  continued")
    end
  end

  describe "tables" do
    test "parses GFM tables with alignment" do
      source = """
      | Name | Age |
      | :--- | --: |
      | Ada  | 36  |
      """

      assert [%{"type" => "table", "align" => ["left", "right"], "children" => rows}] =
               blocks(source)

      assert [header, body] = rows
      assert header["header"] == true
      assert header["cells"] == ["Name", "Age"]
      assert body["header"] == false
      assert body["cells"] == ["Ada", "36"]
    end

    test "unescapes escaped pipes inside cells" do
      source = "| a \\| b |\n| --- |\n| c |"
      assert [%{"children" => [%{"cells" => ["a | b"]} | _]}] = blocks(source)
    end
  end

  describe "thematic breaks, references and footnotes" do
    test "parses thematic breaks" do
      assert [%{"type" => "thematic_break"}] = blocks("---")
      assert [%{"type" => "thematic_break"}] = blocks("***")
    end

    test "collects link reference definitions" do
      cst = parse!("[docs]: https://example.com \"Docs\"\n\nSee [docs].")

      assert %{"docs" => %{"url" => "https://example.com", "title" => "Docs"}} =
               cst["definitions"]
    end

    test "parses footnote definitions" do
      assert [%{"type" => "footnote", "label" => "1", "text" => "Note"}] = blocks("[^1]: Note")
    end
  end

  describe "inline parsing" do
    alias Metastatic.NL.Adapters.Markdown.Inline

    test "splits words and punctuation" do
      assert [
               %{"type" => "word", "value" => "Hello"},
               %{"type" => "punctuation", "value" => ","},
               %{"type" => "word", "value" => "world"},
               %{"type" => "punctuation", "value" => "."}
             ] = Inline.parse("Hello, world.", %{})
    end

    test "parses emphasis, strong and strikethrough" do
      assert [%{"type" => "emphasis"}] = Inline.parse("*x*", %{})
      assert [%{"type" => "strong"}] = Inline.parse("**x**", %{})
      assert [%{"type" => "strong"}] = Inline.parse("__x__", %{})
      assert [%{"type" => "strikethrough"}] = Inline.parse("~~x~~", %{})
    end

    test "parses inline code and leaves its content untouched" do
      assert [%{"type" => "code_span", "value" => "*not emphasis*"}] =
               Inline.parse("`*not emphasis*`", %{})
    end

    test "parses links with destinations and titles" do
      assert [%{"type" => "link", "destination" => "https://x.dev", "title" => "T"}] =
               Inline.parse("[text](https://x.dev \"T\")", %{})
    end

    test "parses images with alt text" do
      assert [%{"type" => "image", "destination" => "logo.png", "children" => [_ | _]}] =
               Inline.parse("![Logo](logo.png)", %{})
    end

    test "resolves reference links from definitions" do
      defs = %{"docs" => %{"url" => "https://x.dev", "title" => nil}}

      assert [%{"type" => "reference_link", "destination" => "https://x.dev"}] =
               Inline.parse("[Docs][docs]", defs)
    end

    test "parses autolinks" do
      assert [%{"type" => "link", "destination" => "https://x.dev"}] =
               Inline.parse("<https://x.dev>", %{})
    end

    test "marks hard line breaks" do
      nodes = Inline.parse("one  \ntwo", %{})
      assert Enum.any?(nodes, &(&1["type"] == "line_break"))
    end

    test "never fails on arbitrary input" do
      for input <- ["***", "[[[", "`unclosed", "![", "a * b", "\\", "~~~"] do
        assert is_list(Inline.parse(input, %{}))
      end
    end

    test "always makes progress on characters outside word/punctuation classes" do
      # Regression: `↔` is neither a word nor punctuation character; the
      # scanner must still consume it instead of recursing forever.
      assert [
               %{"type" => "word", "value" => "M1"},
               %{"type" => "word", "value" => "↔"},
               %{"type" => "word", "value" => "M2"}
             ] = Inline.parse("M1 ↔ M2", %{})

      for input <- ["↔", "→→→", "✓ done", "«quoted»", "emoji 🎉 here"] do
        assert is_list(Inline.parse(input, %{}))
      end
    end
  end

  describe "normalize_label/1" do
    test "lowercases and collapses whitespace" do
      assert Parser.normalize_label("  My   Label ") == "my label"
    end
  end
end
