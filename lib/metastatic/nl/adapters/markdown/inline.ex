defmodule Metastatic.NL.Adapters.Markdown.Inline do
  @moduledoc """
  Inline parser for Markdown spans (M1 CST fragments).

  Splits a single inline text run into a list of inline CST nodes:
  words, punctuation, emphasis, strong, strikethrough, inline code, links,
  images, reference links and hard line breaks.

  The parser is a small recursive-descent scanner. It deliberately favours
  predictable output over full CommonMark edge-case coverage: every
  construct it does not recognise degrades to plain words and punctuation,
  so no input can fail to parse.

  ## Output node shapes

      %{"type" => "word", "value" => "Hello"}
      %{"type" => "punctuation", "value" => ","}
      %{"type" => "code_span", "value" => "IO.puts(1)"}
      %{"type" => "emphasis", "children" => [...]}
      %{"type" => "strong", "children" => [...]}
      %{"type" => "strikethrough", "children" => [...]}
      %{"type" => "link", "destination" => "https://…", "title" => nil, "children" => [...]}
      %{"type" => "image", "destination" => "logo.png", "title" => nil, "children" => [...]}
      %{"type" => "reference_link", "label" => "docs", "children" => [...]}
      %{"type" => "line_break"}
  """

  alias Metastatic.NL.Adapters.Markdown.Parser

  @word_re ~r/^[[:alnum:]_'’\-]+/u
  @punct_re ~r/^[[:punct:]]/u
  @autolink_re ~r/^<((?:https?|ftp|mailto):[^>\s]+)>/u

  @doc """
  Parses inline text into a list of inline CST nodes.

  `definitions` maps normalised reference labels to
  `%{"url" => url, "title" => title}` (from link reference definitions).

  ## Examples

      iex> [%{"type" => "word", "value" => "Hello"}] =
      ...>   Metastatic.NL.Adapters.Markdown.Inline.parse("Hello", %{})
  """
  @spec parse(String.t() | nil, map()) :: [map()]
  def parse(nil, _definitions), do: []
  def parse("", _definitions), do: []

  def parse(text, definitions) when is_binary(text) do
    text
    |> String.split("\n")
    |> join_with_breaks()
    |> scan(definitions)
  end

  # ----- Line handling -----

  # A line ending in two spaces or a backslash is a hard break; any other
  # newline behaves as a soft space.
  defp join_with_breaks([single]), do: single

  defp join_with_breaks([line | rest]) do
    cond do
      String.ends_with?(line, "  ") ->
        String.trim_trailing(line) <> <<0>> <> join_with_breaks(rest)

      String.ends_with?(line, "\\") ->
        String.slice(line, 0, String.length(line) - 1) <> <<0>> <> join_with_breaks(rest)

      true ->
        line <> " " <> join_with_breaks(rest)
    end
  end

  defp join_with_breaks([]), do: ""

  # ----- Scanner -----

  defp scan("", _definitions), do: []

  defp scan(<<0, rest::binary>>, definitions) do
    [%{"type" => "line_break"} | scan(rest, definitions)]
  end

  defp scan(text, definitions) do
    cond do
      match = Regex.run(@autolink_re, text) ->
        [_, url] = match
        consumed = byte_size(url) + 2
        rest = binary_part(text, consumed, byte_size(text) - consumed)

        link = %{
          "type" => "link",
          "destination" => url,
          "title" => nil,
          "children" => [word(url)]
        }

        [link | scan(rest, definitions)]

      match = Regex.run(~r/^(`+)(.+?)\1/s, text) ->
        [whole, _ticks, code] = match
        rest = binary_part(text, byte_size(whole), byte_size(text) - byte_size(whole))
        [%{"type" => "code_span", "value" => String.trim(code)} | scan(rest, definitions)]

      match = Regex.run(~r/^!\[([^\]]*)\]\(([^)\s]*)(?:\s+"([^"]*)")?\)/, text) ->
        [whole, alt, dest | title] = match
        rest = binary_part(text, byte_size(whole), byte_size(text) - byte_size(whole))

        node = %{
          "type" => "image",
          "destination" => dest,
          "title" => List.first(title),
          "children" => scan(alt, definitions)
        }

        [node | scan(rest, definitions)]

      match = Regex.run(~r/^\[([^\]]*)\]\(([^)\s]*)(?:\s+"([^"]*)")?\)/, text) ->
        [whole, label, dest | title] = match
        rest = binary_part(text, byte_size(whole), byte_size(text) - byte_size(whole))

        node = %{
          "type" => "link",
          "destination" => dest,
          "title" => List.first(title),
          "children" => scan(label, definitions)
        }

        [node | scan(rest, definitions)]

      match = Regex.run(~r/^\[([^\]]*)\]\[([^\]]*)\]/, text) ->
        [whole, label, ref] = match
        rest = binary_part(text, byte_size(whole), byte_size(text) - byte_size(whole))
        ref_label = if ref == "", do: label, else: ref
        [reference_node(label, ref_label, definitions) | scan(rest, definitions)]

      match = Regex.run(~r/^\*\*\*(.+?)\*\*\*/s, text) ->
        [whole, inner] = match
        rest = binary_part(text, byte_size(whole), byte_size(text) - byte_size(whole))

        [
          %{
            "type" => "strong",
            "children" => [%{"type" => "emphasis", "children" => scan(inner, definitions)}]
          }
          | scan(rest, definitions)
        ]

      match = Regex.run(~r/^\*\*(.+?)\*\*/s, text) ->
        [whole, inner] = match
        rest = binary_part(text, byte_size(whole), byte_size(text) - byte_size(whole))
        [%{"type" => "strong", "children" => scan(inner, definitions)} | scan(rest, definitions)]

      match = Regex.run(~r/^__(.+?)__/s, text) ->
        [whole, inner] = match
        rest = binary_part(text, byte_size(whole), byte_size(text) - byte_size(whole))
        [%{"type" => "strong", "children" => scan(inner, definitions)} | scan(rest, definitions)]

      match = Regex.run(~r/^\*(.+?)\*/s, text) ->
        [whole, inner] = match
        rest = binary_part(text, byte_size(whole), byte_size(text) - byte_size(whole))

        [
          %{"type" => "emphasis", "children" => scan(inner, definitions)}
          | scan(rest, definitions)
        ]

      match = Regex.run(~r/^_(.+?)_/s, text) ->
        [whole, inner] = match
        rest = binary_part(text, byte_size(whole), byte_size(text) - byte_size(whole))

        [
          %{"type" => "emphasis", "children" => scan(inner, definitions)}
          | scan(rest, definitions)
        ]

      match = Regex.run(~r/^~~(.+?)~~/s, text) ->
        [whole, inner] = match
        rest = binary_part(text, byte_size(whole), byte_size(text) - byte_size(whole))

        [
          %{"type" => "strikethrough", "children" => scan(inner, definitions)}
          | scan(rest, definitions)
        ]

      match = Regex.run(@word_re, text) ->
        [word] = match
        rest = binary_part(text, byte_size(word), byte_size(text) - byte_size(word))
        [%{"type" => "word", "value" => word} | scan(rest, definitions)]

      # Whitespace is a separator, not punctuation: consume it silently.
      match = Regex.run(~r/^\s+/u, text) ->
        [space] = match
        rest = binary_part(text, byte_size(space), byte_size(text) - byte_size(space))
        scan(rest, definitions)

      match = Regex.run(@punct_re, text) ->
        [punct] = match
        rest = binary_part(text, byte_size(punct), byte_size(text) - byte_size(punct))
        [%{"type" => "punctuation", "value" => punct} | scan(rest, definitions)]

      true ->
        # Any other character (e.g. `↔`, emoji): consume exactly one grapheme
        # so the scanner always makes progress.
        <<grapheme::utf8, rest::binary>> = text
        [%{"type" => "word", "value" => <<grapheme::utf8>>} | scan(rest, definitions)]
    end
  end

  defp reference_node(label, ref_label, definitions) do
    normalised = Parser.normalize_label(ref_label)

    case Map.fetch(definitions, normalised) do
      {:ok, %{"url" => url, "title" => title}} ->
        %{
          "type" => "reference_link",
          "label" => ref_label,
          "destination" => url,
          "title" => title,
          "children" => scan(label, definitions)
        }

      :error ->
        # Unresolved reference: keep the literal text so nothing is lost.
        %{
          "type" => "reference_link",
          "label" => ref_label,
          "children" => scan(label, definitions)
        }
    end
  end

  defp word(value), do: %{"type" => "word", "value" => value}
end
