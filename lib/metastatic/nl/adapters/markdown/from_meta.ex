defmodule Metastatic.NL.Adapters.Markdown.FromMeta do
  @moduledoc """
  Reifies NL-MetaAST (M2) back into Markdown (M1 CST and source text).

  Two entry points:

  - `transform/2` — M2 → M1 CST map, mirroring the shape produced by
    `Metastatic.NL.Adapters.Markdown.Parser`
  - `to_source/1` — M2 (or M1 CST) → Markdown source string

  The reification is structural rather than byte-exact: it preserves the
  document's semantics (headings, lists, code, tables, inline spans) but
  normalises whitespace and marker choices. Use `original_source` on the
  `Document` when byte-exact round-trips are required.
  """

  alias Metastatic.NL.AST

  @doc """
  Transforms NL-MetaAST into a Markdown CST map.

  ## Examples

      iex> doc = Metastatic.NL.AST.document([Metastatic.NL.AST.heading(1, [Metastatic.NL.AST.token("Hi")])])
      iex> {:ok, %{"type" => "document", "children" => [%{"type" => "heading"}]}} =
      ...>   Metastatic.NL.Adapters.Markdown.FromMeta.transform(doc, %{})
  """
  @spec transform(AST.nl_node(), map()) :: {:ok, map()}
  def transform({:document, _meta, children}, _metadata) do
    blocks = Enum.map(children, &transform_block/1)
    {:ok, %{"type" => "document", "language" => "markdown", "children" => blocks}}
  end

  def transform(node, _metadata) do
    {:ok, transform_block(node)}
  end

  # ----- Block reification -----

  defp transform_block({:heading, meta, children}) do
    %{
      "type" => "heading",
      "level" => Keyword.get(meta, :level, 1),
      "text" => inline_text(children),
      "line" => Keyword.get(meta, :line)
    }
  end

  defp transform_block({:paragraph, meta, children}) do
    %{
      "type" => "paragraph",
      "text" => inline_source(children),
      "line" => Keyword.get(meta, :line)
    }
  end

  defp transform_block({:code_block, meta, code}) do
    %{
      "type" => "code_block",
      "value" => code || "",
      "info" => Keyword.get(meta, :info) || Keyword.get(meta, :language) || "",
      "line" => Keyword.get(meta, :line)
    }
  end

  defp transform_block({:block_quote, meta, children}) do
    %{
      "type" => "block_quote",
      "children" => Enum.map(children, &transform_block/1),
      "line" => Keyword.get(meta, :line)
    }
  end

  defp transform_block({:list_block, meta, items}) do
    %{
      "type" => "list",
      "ordered" => Keyword.get(meta, :ordered, false),
      "children" => Enum.map(items, &transform_block/1),
      "line" => Keyword.get(meta, :line)
    }
  end

  defp transform_block({:list_item, meta, children}) do
    %{
      "type" => "list_item",
      "text" => inline_text(children),
      "children" => [],
      "line" => Keyword.get(meta, :line)
    }
  end

  defp transform_block({:task_item, meta, children}) do
    %{
      "type" => "list_item",
      "text" => inline_text(children),
      "task" => Keyword.get(meta, :checked, false),
      "children" => [],
      "line" => Keyword.get(meta, :line)
    }
  end

  defp transform_block({:table, meta, rows}) do
    %{
      "type" => "table",
      "align" => Keyword.get(meta, :align, []),
      "children" => Enum.map(rows, &transform_block/1),
      "line" => Keyword.get(meta, :line)
    }
  end

  defp transform_block({:table_row, meta, cells}) do
    %{
      "type" => "table_row",
      "header" => Keyword.get(meta, :header?, false),
      "cells" => Enum.map(cells, &inline_text(elem(&1, 2))),
      "line" => Keyword.get(meta, :line)
    }
  end

  defp transform_block({:thematic_break, meta, _}) do
    %{"type" => "thematic_break", "line" => Keyword.get(meta, :line)}
  end

  defp transform_block({:footnote, meta, children}) do
    %{
      "type" => "footnote",
      "label" => Keyword.get(meta, :label, ""),
      "text" => inline_text(children),
      "line" => Keyword.get(meta, :line)
    }
  end

  defp transform_block(node) do
    %{"type" => "paragraph", "text" => AST.text(node), "line" => nil}
  end

  # ----- Source generation -----

  @doc """
  Reifies NL-MetaAST (or a Markdown CST map) into Markdown source text.

  ## Examples

      iex> doc = Metastatic.NL.AST.document([
      ...>   Metastatic.NL.AST.heading(2, [Metastatic.NL.AST.token("Usage")]),
      ...>   Metastatic.NL.AST.paragraph([Metastatic.NL.AST.sentence([Metastatic.NL.AST.clause([
      ...>     Metastatic.NL.AST.token("Call"), Metastatic.NL.AST.token("it"), Metastatic.NL.AST.punctuation(".")
      ...>   ])])])
      ...> ])
      iex> Metastatic.NL.Adapters.Markdown.FromMeta.to_source(doc)
      "## Usage\\n\\nCall it."
  """
  @spec to_source(AST.nl_node() | map()) :: String.t()
  def to_source(%{"type" => "document", "children" => blocks}) do
    blocks
    |> Enum.map(&block_source/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
  end

  def to_source({:document, _meta, children}) do
    children
    |> Enum.map(&block_source/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
  end

  def to_source(blocks) when is_list(blocks) do
    blocks
    |> Enum.map(&block_source/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
  end

  def to_source({type, _meta, _children} = node) when is_atom(type) do
    block_source(node)
  end

  def to_source(other), do: AST.text(other)

  defp block_source(%{"type" => "heading", "level" => level, "text" => text}) do
    String.duplicate("#", level || 1) <> " " <> to_string(text)
  end

  defp block_source(%{"type" => "paragraph", "text" => text}), do: to_string(text)

  defp block_source(%{"type" => "code_block"} = block) do
    info = Map.get(block, "info", "") || ""
    "```" <> to_string(info) <> "\n" <> to_string(Map.get(block, "value", "")) <> "\n```"
  end

  defp block_source(%{"type" => "block_quote", "children" => children}) do
    children
    |> Enum.map_join("\n\n", &block_source/1)
    |> String.split("\n")
    |> Enum.map_join("\n", &("> " <> &1))
  end

  defp block_source(%{"type" => "list", "children" => items} = block) do
    ordered? = Map.get(block, "ordered", false)

    items
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn {item, index} ->
      marker = if ordered?, do: "#{index}.", else: "-"
      marker <> " " <> cst_item_source(item)
    end)
  end

  defp block_source(%{"type" => "table", "children" => rows} = block) do
    rows
    |> Enum.map(&row_source/1)
    |> insert_delimiter(Map.get(block, "align", []))
    |> Enum.join("\n")
  end

  defp block_source(%{"type" => "thematic_break"}), do: "---"

  defp block_source(%{"type" => "footnote"} = block) do
    "[^" <>
      to_string(Map.get(block, "label", "")) <> "]: " <> to_string(Map.get(block, "text", ""))
  end

  defp block_source(%{"type" => "list_item"} = item), do: cst_item_source(item)

  defp block_source({:heading, meta, children}) do
    String.duplicate("#", Keyword.get(meta, :level, 1)) <> " " <> inline_source(children)
  end

  defp block_source({:paragraph, _meta, children}) do
    inline_source(children)
  end

  defp block_source({:code_block, meta, code}) do
    info = Keyword.get(meta, :info) || Keyword.get(meta, :language) || ""
    "```" <> to_string(info) <> "\n" <> (code || "") <> "\n```"
  end

  defp block_source({:block_quote, _meta, children}) do
    children
    |> Enum.map_join("\n\n", &block_source/1)
    |> String.split("\n")
    |> Enum.map_join("\n", &("> " <> &1))
  end

  defp block_source({:list_block, meta, items}) do
    ordered? = Keyword.get(meta, :ordered, false)

    items
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn {item, index} ->
      marker = if ordered?, do: "#{index}.", else: "-"
      marker <> " " <> item_source(item)
    end)
  end

  defp block_source({:list_item, _meta, children}), do: inline_source(children)

  defp block_source({:task_item, meta, children}) do
    box = if Keyword.get(meta, :checked, false), do: "[x]", else: "[ ]"
    box <> " " <> inline_source(children)
  end

  defp block_source({:table, meta, rows}) do
    align = Keyword.get(meta, :align, [])

    rows
    |> Enum.map(&row_source/1)
    |> insert_delimiter(align)
    |> Enum.join("\n")
  end

  defp block_source({:thematic_break, _meta, _}), do: "---"

  defp block_source({:footnote, meta, children}) do
    "[^" <> to_string(Keyword.get(meta, :label, "")) <> "]: " <> inline_source(children)
  end

  defp block_source(node), do: AST.text(node)

  defp cst_item_source(%{"task" => task} = item) when is_boolean(task) do
    box = if task, do: "[x]", else: "[ ]"
    box <> " " <> to_string(Map.get(item, "text", ""))
  end

  defp cst_item_source(item), do: to_string(Map.get(item, "text", ""))

  defp item_source({:list_item, _meta, children}), do: inline_source(children)

  defp item_source({:task_item, meta, children}) do
    box = if Keyword.get(meta, :checked, false), do: "[x]", else: "[ ]"
    box <> " " <> inline_source(children)
  end

  defp item_source(node), do: AST.text(node)

  defp row_source({:table_row, _meta, cells}) do
    "| " <> Enum.map_join(cells, " | ", &inline_source(elem(&1, 2))) <> " |"
  end

  defp row_source(%{"cells" => cells}) do
    "| " <> Enum.map_join(cells, " | ", &to_string/1) <> " |"
  end

  defp insert_delimiter([], _align), do: []

  defp insert_delimiter([header | rest], align) do
    column_count = header |> String.split("|") |> length() |> Kernel.-(2)
    columns = max(column_count, 1)

    delimiter =
      "| " <>
        Enum.map_join(0..(columns - 1), " | ", fn index ->
          case Enum.at(align, index) do
            "center" -> ":---:"
            "right" -> "---:"
            "left" -> ":---"
            _ -> "---"
          end
        end) <> " |"

    [header, delimiter | rest]
  end

  # ----- Inline rendering -----

  # Renders inline children as plain text (used for CST cells/heading text).
  defp inline_text(children) when is_list(children) do
    Enum.map_join(children, " ", &AST.text/1)
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp inline_text(other), do: AST.text(other)

  # Renders inline children back to Markdown source, preserving markers.
  # Inline nodes are separated by a single space unless the boundary is
  # punctuation, so `**bold** text` does not collapse to `**bold**text`.
  defp inline_source(children) when is_list(children) do
    children
    |> Enum.map(&inline_node_source/1)
    |> Enum.reduce("", fn part, acc -> join_inline(acc, part) end)
    |> String.replace(~r/[ \t]+/, " ")
    |> String.trim()
  end

  defp inline_source({_type, _meta, _children} = node), do: inline_node_source(node)

  defp inline_source(other), do: AST.text(other)

  defp join_inline("", part), do: part

  defp join_inline(acc, ""), do: acc

  defp join_inline(acc, part) do
    cond do
      String.ends_with?(acc, "\n") -> acc <> part
      String.starts_with?(part, ".") -> acc <> part
      part in [",", ";", ":", "!", "?", ")", "]", "}"] -> acc <> part
      String.ends_with?(acc, "(") or String.ends_with?(acc, "[") -> acc <> part
      true -> acc <> " " <> part
    end
  end

  defp inline_node_source({:emphasis, _meta, children}), do: "*" <> inline_source(children) <> "*"
  defp inline_node_source({:strong, _meta, children}), do: "**" <> inline_source(children) <> "**"

  defp inline_node_source({:strikethrough, _meta, children}),
    do: "~~" <> inline_source(children) <> "~~"

  defp inline_node_source({:inline_code, _meta, code}), do: "`" <> to_string(code) <> "`"

  defp inline_node_source({:link, meta, children}) do
    destination = Keyword.get(meta, :destination, "")
    title = Keyword.get(meta, :title)

    title_part = if title, do: " \"#{title}\"", else: ""
    "[" <> inline_source(children) <> "](" <> destination <> title_part <> ")"
  end

  defp inline_node_source({:image, meta, children}) do
    destination = Keyword.get(meta, :destination, "")
    "![" <> inline_source(children) <> "](" <> destination <> ")"
  end

  defp inline_node_source({:reference_link, meta, children}) do
    "[" <> inline_source(children) <> "][" <> to_string(Keyword.get(meta, :label, "")) <> "]"
  end

  defp inline_node_source({:line_break, _meta, _}), do: "  \n"

  defp inline_node_source({:punctuation, _meta, value}), do: to_string(value)

  defp inline_node_source({:token, _meta, value}), do: to_string(value)

  # Structural prose wrappers contribute their children only.
  defp inline_node_source({type, _meta, children})
       when type in [:sentence, :clause, :phrase] and is_list(children) do
    inline_source(children)
  end

  defp inline_node_source(node), do: AST.text(node)
end
