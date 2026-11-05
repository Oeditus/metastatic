defmodule Metastatic.NL.Adapters.Markdown.Parser do
  @moduledoc """
  Pure-Elixir block/inline parser for Markdown (M0) into an M1 CST map.

  This is the M0 -> M1 step of the Markdown adapter pipeline:

      Markdown text ──parse/1──> CST map ──to_meta/1──> NL-MetaAST

  The CST is a plain map tree (`%{"type" => ..., "children" => [...]}`)
  mirroring the shape produced by the English prose parser, so both adapters
  share the same downstream contract.

  ## Supported Syntax

  **Blocks**

  - ATX headings `#` … `######`
  - Setext headings (`===` / `---` underlines)
  - Paragraphs
  - Fenced code blocks (```` ``` ```` and `~~~`, with info strings)
  - Indented code blocks (4 spaces / tab)
  - Block quotes (`>`), including nested quotes
  - Bullet and ordered lists, including nested lists and GitHub task lists
  - GFM tables with alignment row
  - Thematic breaks (`---`, `***`, `___`)
  - Link reference definitions (`[label]: url "title"`)
  - Footnote definitions (`[^label]: text`)

  **Inline**

  - Emphasis (`*x*`, `_x_`), strong (`**x**`, `__x__`), strikethrough (`~~x~~`)
  - Inline code spans (`` `x` ``, ``` ``x`` ```)
  - Links `[text](url "title")` and images `![alt](src)`
  - Reference links `[text][label]`, `[label][]`, `[label]`
  - Autolinks `<https://example.com>`
  - Hard line breaks (two trailing spaces or trailing `\\`)
  - HTML entities are left verbatim

  ## Design Notes

  The parser is intentionally dependency-free and line-oriented: Markdown is
  a line-based format, and a two-phase (block then inline) parser is both
  simpler to audit and fast enough for documentation trees. Every node
  carries `line` metadata so prose linter issues point at real lines.
  """

  @heading_re ~r/^(\#{1,6})(?:\s+(.*?))?\s*#*\s*$/
  @thematic_break_re ~r/^(?:\*\s*){3,}$|^(?:-\s*){3,}$|^(?:_\s*){3,}$/
  @ul_item_re ~r/^(\s*)([-*+])\s+(.*)$/
  @ol_item_re ~r/^(\s*)(\d{1,9})[.)]\s+(.*)$/
  @fence_re ~r/^(\s*)(`{3,}|~{3,})\s*(.*)$/
  @blockquote_re ~r/^\s*>\s?(.*)$/
  @setext_h1_re ~r/^\s*=+\s*$/
  @setext_h2_re ~r/^\s*-{2,}\s*$/
  @table_delimiter_re ~r/^\s*\|?\s*:?-{1,}:?\s*(\|\s*:?-{1,}:?\s*)*\|?\s*$/
  @ref_def_re ~r/^\s{0,3}\[([^\]]+)\]:\s*(\S+)(?:\s+"([^"]*)")?\s*$/
  @footnote_def_re ~r/^\s{0,3}\[\^([^\]]+)\]:\s*(.*)$/
  @task_re ~r/^\[([ xX])\]\s+(.*)$/

  @doc """
  Parses Markdown source into an M1 CST document map.

  Returns `{:ok, cst}` where `cst` is
  `%{"type" => "document", "language" => "markdown", "children" => blocks}`.

  ## Examples

      iex> {:ok, cst} = Metastatic.NL.Adapters.Markdown.Parser.parse("# Title")
      iex> [%{"type" => "heading", "level" => 1}] = cst["children"]
      iex> cst["language"]
      "markdown"
  """
  @spec parse(String.t()) :: {:ok, map()}
  def parse(source) when is_binary(source) do
    source
    |> String.replace("\r\n", "\n")
    |> String.replace("\r", "\n")
    |> String.split("\n")
    |> parse_lines(1, %{})
    |> then(fn {blocks, defs} ->
      {:ok,
       %{
         "type" => "document",
         "language" => "markdown",
         "children" => blocks,
         "definitions" => defs
       }}
    end)
  end

  # ----- Block-level parsing -----

  # Returns {blocks, reference_definitions}
  defp parse_lines(lines, start_line, defs) do
    do_parse(lines, start_line, [], defs)
  end

  defp do_parse([], _line, acc, defs), do: {Enum.reverse(acc), defs}

  defp do_parse([line | rest], line_no, acc, defs) do
    cond do
      blank?(line) ->
        do_parse(rest, line_no + 1, acc, defs)

      match = Regex.run(@fence_re, line) ->
        [_, _indent, fence, info] = match
        {block, remaining, consumed} = parse_fence(rest, fence, info, line_no)
        do_parse(remaining, line_no + consumed + 1, [block | acc], defs)

      match = Regex.run(@heading_re, line, capture: :all_but_first) ->
        {hashes, text} =
          case match do
            [hashes, text] -> {hashes, text}
            [hashes] -> {hashes, nil}
          end

        block = %{
          "type" => "heading",
          "level" => String.length(hashes),
          "text" => heading_text(text),
          "line" => line_no
        }

        do_parse(rest, line_no + 1, [block | acc], defs)

      match = Regex.run(@thematic_break_re, line) ->
        _ = match
        block = %{"type" => "thematic_break", "line" => line_no}
        do_parse(rest, line_no + 1, [block | acc], defs)

      Regex.match?(@blockquote_re, line) ->
        {block, remaining, consumed} = parse_blockquote([line | rest], line_no)
        do_parse(remaining, line_no + consumed, [block | acc], defs)

      list_start?(line) ->
        {block, remaining, consumed} = parse_list([line | rest], line_no)
        do_parse(remaining, line_no + consumed, [block | acc], defs)

      match = Regex.run(@footnote_def_re, line) ->
        [_, label, text] = match

        block = %{
          "type" => "footnote",
          "label" => label,
          "text" => text,
          "line" => line_no
        }

        do_parse(rest, line_no + 1, [block | acc], defs)

      match = Regex.run(@ref_def_re, line) ->
        [_, label, url | title] = match
        key = normalize_label(label)
        new_defs = Map.put(defs, key, %{"url" => url, "title" => List.first(title)})
        do_parse(rest, line_no + 1, acc, new_defs)

      indented_code?(line) ->
        {block, remaining, consumed} = parse_indented_code([line | rest], line_no)
        do_parse(remaining, line_no + consumed, [block | acc], defs)

      table_start?([line | rest]) ->
        {block, remaining, consumed} = parse_table([line | rest], line_no)
        do_parse(remaining, line_no + consumed, [block | acc], defs)

      setext_heading?(rest) ->
        {block, remaining, consumed} = parse_setext(line, rest, line_no)
        do_parse(remaining, line_no + consumed, [block | acc], defs)

      true ->
        {block, remaining, consumed} = parse_paragraph([line | rest], line_no)
        do_parse(remaining, line_no + consumed, [block | acc], defs)
    end
  end

  defp blank?(line), do: String.trim(line) == ""

  # An ATX heading may have no text (`#`), in which case the optional capture
  # group yields `nil` (or is absent entirely).
  defp heading_text(nil), do: ""
  defp heading_text(text) when is_binary(text), do: text

  # ----- Fenced code -----

  defp parse_fence(lines, fence, info, line_no) do
    close_re = ~r/^\s*#{Regex.escape(fence)}+\s*$/

    {code_lines, remaining, consumed} = take_until(lines, close_re, 0, [])

    block = %{
      "type" => "code_block",
      "value" => Enum.join(code_lines, "\n"),
      "info" => String.trim(info),
      "line" => line_no
    }

    {block, remaining, consumed}
  end

  defp take_until([], _re, consumed, acc), do: {Enum.reverse(acc), [], consumed}

  defp take_until([line | rest], re, consumed, acc) do
    if Regex.match?(re, line) do
      {Enum.reverse(acc), rest, consumed + 1}
    else
      take_until(rest, re, consumed + 1, [line | acc])
    end
  end

  # ----- Indented code -----

  defp indented_code?(line), do: Regex.match?(~r/^(?: {4}|\t)/, line)

  defp parse_indented_code(lines, line_no) do
    {code_lines, _remaining, consumed} =
      Enum.reduce_while(lines, {[], [], 0}, fn line, {acc, _rest, count} ->
        if indented_code?(line) or blank?(line) do
          {:cont, {[strip_indent(line) | acc], [], count + 1}}
        else
          {:halt, {acc, [], count}}
        end
      end)

    remaining = Enum.drop(lines, consumed)

    block = %{
      "type" => "code_block",
      "value" => code_lines |> Enum.reverse() |> trim_trailing_blanks() |> Enum.join("\n"),
      "info" => "",
      "line" => line_no
    }

    {block, remaining, consumed}
  end

  defp strip_indent(line) do
    cond do
      String.starts_with?(line, "\t") -> String.replace_prefix(line, "\t", "")
      String.starts_with?(line, "    ") -> String.replace_prefix(line, "    ", "")
      true -> line
    end
  end

  defp trim_trailing_blanks(lines) do
    lines |> Enum.reverse() |> Enum.drop_while(&blank?/1) |> Enum.reverse()
  end

  # ----- Block quotes -----

  defp parse_blockquote(lines, line_no) do
    {quoted, _remaining, consumed} =
      Enum.reduce_while(lines, {[], [], 0}, fn line, {acc, _rest, count} ->
        cond do
          match = Regex.run(@blockquote_re, line) ->
            [_, inner] = match
            {:cont, {[inner | acc], [], count + 1}}

          blank?(line) ->
            {:cont, {["" | acc], [], count + 1}}

          true ->
            {:halt, {acc, [], count}}
        end
      end)

    remaining = Enum.drop(lines, consumed)
    {inner_blocks, _defs} = do_parse(Enum.reverse(quoted), line_no, [], %{})

    block = %{"type" => "block_quote", "children" => inner_blocks, "line" => line_no}
    {block, remaining, consumed}
  end

  # ----- Lists -----

  defp list_start?(line),
    do: Regex.match?(@ul_item_re, line) or Regex.match?(@ol_item_re, line)

  defp parse_list(lines, line_no) do
    {first_line, _rest} = List.pop_at(lines, 0)

    {ordered?, start} =
      case Regex.run(@ol_item_re, first_line) do
        [_, _indent, num, _text] -> {true, String.to_integer(num)}
        nil -> {false, nil}
      end

    {items, remaining, consumed} = collect_items(lines, ordered?, line_no, [])

    block =
      %{
        "type" => "list",
        "ordered" => ordered?,
        "children" => items,
        "line" => line_no
      }
      |> maybe_put("start", start)

    {block, remaining, consumed}
  end

  defp collect_items(lines, ordered?, line_no, acc) do
    case lines do
      [] ->
        {Enum.reverse(acc), [], 0}

      [line | _] = remaining ->
        cond do
          blank?(line) ->
            # A blank line ends the list unless another item follows.
            case Enum.drop(remaining, 1) do
              [next | _] when is_binary(next) ->
                if item_line?(next, ordered?) do
                  {items, rest, consumed} =
                    collect_items(Enum.drop(remaining, 1), ordered?, line_no + 1, acc)

                  {items, rest, consumed + 1}
                else
                  {Enum.reverse(acc), remaining, 0}
                end

              _ ->
                {Enum.reverse(acc), remaining, 0}
            end

          item_line?(line, ordered?) ->
            {item, rest, consumed} = parse_item(remaining, ordered?, line_no)

            {items, rest2, consumed2} =
              collect_items(rest, ordered?, line_no + consumed, [item | acc])

            {items, rest2, consumed + consumed2}

          true ->
            {Enum.reverse(acc), remaining, 0}
        end
    end
  end

  defp item_line?(line, ordered?) do
    if ordered?,
      do: Regex.match?(@ol_item_re, line),
      else: Regex.match?(@ul_item_re, line)
  end

  defp parse_item([line | rest], ordered?, line_no) do
    {indent, text} = split_item(line, ordered?)
    indent_size = String.length(indent)

    {continuation_lines, remaining, consumed} = collect_continuation(rest, indent_size, [])

    # Continuation lines form the item's nested blocks (usually a paragraph).
    {continuation, _defs} = do_parse(continuation_lines, line_no + 1, [], %{})

    {task, body} =
      case Regex.run(@task_re, text) do
        [_, mark, rest_text] -> {String.downcase(mark) == "x", rest_text}
        nil -> {nil, text}
      end

    item =
      %{
        "type" => "list_item",
        "text" => body,
        "children" => continuation,
        "line" => line_no
      }
      |> maybe_put("task", task)

    {item, remaining, consumed + 1}
  end

  defp split_item(line, ordered?) do
    re = if ordered?, do: @ol_item_re, else: @ul_item_re
    [_, indent, _marker, text] = Regex.run(re, line)
    {indent, text}
  end

  defp collect_continuation(lines, indent_size, acc) do
    case lines do
      [] ->
        {Enum.reverse(acc), [], 0}

      [line | rest] ->
        cond do
          blank?(line) ->
            {Enum.reverse(acc), lines, 0}

          leading_spaces(line) > indent_size ->
            {Enum.reverse(acc) ++ [String.trim_leading(line)], [], 0}
            |> then(fn {_acc, _rest, _n} ->
              collect_continuation(rest, indent_size, [String.trim_leading(line) | acc])
            end)

          true ->
            {Enum.reverse(acc), lines, 0}
        end
    end
  end

  defp leading_spaces(line) do
    line
    |> String.graphemes()
    |> Enum.take_while(&(&1 == " "))
    |> length()
  end

  # ----- Tables -----

  defp table_start?([header, delimiter | _]) do
    String.contains?(header, "|") and Regex.match?(@table_delimiter_re, delimiter) and
      String.contains?(delimiter, "-")
  end

  defp table_start?(_), do: false

  defp parse_table([header_line, delimiter_line | rest], line_no) do
    alignments = parse_alignments(delimiter_line)
    header_cells = split_row(header_line)

    header = %{
      "type" => "table_row",
      "header" => true,
      "cells" => header_cells,
      "line" => line_no
    }

    {body_rows, remaining, consumed} =
      take_table_rows(rest, line_no + 2, [])

    rows = [header | body_rows]

    block = %{
      "type" => "table",
      "align" => alignments,
      "children" => rows,
      "line" => line_no
    }

    {block, remaining, consumed + 2}
  end

  defp take_table_rows([line | rest] = lines, line_no, acc) do
    if blank?(line) or not String.contains?(line, "|") do
      {Enum.reverse(acc), lines, 0}
    else
      row = %{
        "type" => "table_row",
        "header" => false,
        "cells" => split_row(line),
        "line" => line_no
      }

      {rows, remaining, consumed} = take_table_rows(rest, line_no + 1, [row | acc])
      {rows, remaining, consumed + 1}
    end
  end

  defp take_table_rows([], _line_no, acc), do: {Enum.reverse(acc), [], 0}

  defp split_row(line) do
    line
    |> String.trim()
    |> String.trim("|")
    |> split_unescaped_pipes()
    |> Enum.map(&String.trim/1)
  end

  defp split_unescaped_pipes(text) do
    # Split on `|` that is not escaped as `\|`.
    Regex.split(~r/(?<!\\)\|/, text)
    |> Enum.map(&String.replace(&1, "\\|", "|"))
  end

  defp parse_alignments(delimiter_line) do
    delimiter_line
    |> split_row()
    |> Enum.map(fn cell ->
      left? = String.starts_with?(cell, ":")
      right? = String.ends_with?(cell, ":")

      cond do
        left? and right? -> "center"
        left? -> "left"
        right? -> "right"
        true -> nil
      end
    end)
  end

  # ----- Setext headings -----

  defp setext_heading?([underline | _]) do
    Regex.match?(@setext_h1_re, underline) or Regex.match?(@setext_h2_re, underline)
  end

  defp setext_heading?([]), do: false

  defp parse_setext(text, [underline | rest], line_no) do
    level = if Regex.match?(@setext_h1_re, underline), do: 1, else: 2

    block = %{
      "type" => "heading",
      "level" => level,
      "text" => String.trim(text),
      "line" => line_no
    }

    {block, rest, 2}
  end

  # ----- Paragraphs -----

  defp parse_paragraph(lines, line_no) do
    {para_lines, _remaining, consumed} =
      Enum.reduce_while(lines, {[], [], 0}, fn line, {acc, _rest, count} ->
        if blank?(line) or block_start?(line) do
          {:halt, {acc, [], count}}
        else
          {:cont, {[line | acc], [], count + 1}}
        end
      end)

    remaining = Enum.drop(lines, consumed)

    text =
      para_lines
      |> Enum.reverse()
      |> Enum.join("\n")
      |> String.trim()

    block = %{"type" => "paragraph", "text" => text, "line" => line_no}
    {block, remaining, consumed}
  end

  # A line starts a new block (and therefore terminates a paragraph).
  defp block_start?(line) do
    Regex.match?(@heading_re, line) or
      Regex.match?(@thematic_break_re, line) or
      Regex.match?(@blockquote_re, line) or
      Regex.match?(@fence_re, line) or
      Regex.match?(@footnote_def_re, line) or
      list_start?(line)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  @doc """
  Normalises a link reference label (case-insensitive, whitespace-collapsed).
  """
  @spec normalize_label(String.t()) :: String.t()
  def normalize_label(label) do
    label
    |> String.trim()
    |> String.downcase()
    |> String.replace(~r/\s+/, " ")
  end
end
