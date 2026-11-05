defmodule Metastatic.NL.Adapters.Markdown.ToMeta do
  @moduledoc """
  Transforms the Markdown CST (M1) into NL-MetaAST (M2).

  This is the abstraction step of the Markdown adapter:

      Markdown ──parse/1──> CST (M1) ──to_meta/1──> NL-MetaAST (M2)

  ## Mapping

  | Markdown CST | NL-MetaAST |
  |--------------|------------|
  | `document` | `:document` |
  | `heading` | `:heading` (`:level`) |
  | `paragraph` | `:paragraph` of sentences |
  | `code_block` | `:code_block` (raw, opaque) |
  | `block_quote` | `:block_quote` |
  | `list` / `list_item` | `:list_block` / `:list_item` (`:task_item` for task lists) |
  | `table` / `table_row` / cells | `:table` / `:table_row` / `:table_cell` |
  | `thematic_break` | `:thematic_break` |
  | `footnote` | `:footnote` |
  | `emphasis`, `strong`, `strikethrough` | same-named inline nodes |
  | `link`, `image`, `reference_link` | `:link`, `:image`, `:reference_link` |
  | `code_span` | `:inline_code` |
  | `word` / `punctuation` | `:token` / `:punctuation` (POS-tagged) |

  Prose-bearing inline runs are additionally chunked into sentences, clauses
  and phrases by the same English chunker used for plain prose, so prose
  linting rules (passive voice, weasel words, sentence length) work
  unchanged on Markdown documents.

  Code is never sent through the prose chunker: `:code_block` and
  `:inline_code` keep their raw text so that source code is not mistaken for
  prose.
  """

  alias Metastatic.NL.Adapters.English.Tokenizer
  alias Metastatic.NL.Adapters.Markdown.Inline
  alias Metastatic.NL.AST
  alias Metastatic.NL.Semantic.Enricher

  @doc """
  Transforms a Markdown CST document into an NL-MetaAST document.

  Returns `{:ok, nl_node, metadata}`.

  ## Examples

      iex> {:ok, cst} = Metastatic.NL.Adapters.Markdown.Parser.parse("# Title\\n\\nBody text.")
      iex> {:ok, ast, %{language: :markdown}} = Metastatic.NL.Adapters.Markdown.ToMeta.transform(cst)
      iex> Metastatic.NL.AST.type(ast)
      :document
  """
  @spec transform(map()) :: {:ok, AST.nl_node(), map()}
  def transform(%{"type" => "document", "children" => blocks} = cst) do
    definitions = Map.get(cst, "definitions", %{})
    nodes = Enum.map(blocks, &transform_block(&1, definitions))
    doc = AST.document(nodes, language: :markdown, format: :markdown)
    {:ok, Enricher.enrich(doc), %{language: :markdown}}
  end

  def transform(%{"type" => type} = block) do
    {:ok, Enricher.enrich(transform_block(block, %{})), %{language: :markdown, block: type}}
  end

  # ----- Block transformers -----

  defp transform_block(%{"type" => "heading", "level" => level, "text" => text} = block, defs) do
    AST.heading(level, inline_children(text, block, defs), line_meta(block))
  end

  defp transform_block(%{"type" => "paragraph", "text" => text} = block, defs) do
    AST.paragraph(prose_children(text, block, defs), line_meta(block))
  end

  defp transform_block(%{"type" => "code_block", "value" => code} = block, _defs) do
    info = Map.get(block, "info", "")
    language = info |> to_string() |> String.split(~r/\s+/, parts: 2) |> List.first()

    meta =
      line_meta(block) ++
        [info: info] ++ if(language in [nil, ""], do: [], else: [language: language])

    AST.code_block(code, meta)
  end

  defp transform_block(%{"type" => "block_quote", "children" => children} = block, defs) do
    AST.block_quote(Enum.map(children, &transform_block(&1, defs)), line_meta(block))
  end

  defp transform_block(%{"type" => "list", "children" => items} = block, defs) do
    ordered? = Map.get(block, "ordered", false)

    meta =
      line_meta(block) ++
        [ordered: ordered?] ++
        case Map.get(block, "start") do
          nil -> []
          start -> [start: start]
        end

    {:list_block, meta, Enum.map(items, &transform_list_item(&1, defs))}
  end

  defp transform_block(%{"type" => "table", "children" => rows} = block, defs) do
    align = Map.get(block, "align", [])

    table_rows =
      rows
      |> Enum.with_index()
      |> Enum.map(fn {row, index} -> transform_table_row(row, index == 0, align, defs) end)

    AST.table(table_rows, line_meta(block) ++ [align: align])
  end

  defp transform_block(%{"type" => "thematic_break"} = block, _defs) do
    AST.thematic_break(line_meta(block))
  end

  defp transform_block(%{"type" => "footnote", "label" => label, "text" => text} = block, defs) do
    AST.footnote(prose_children(text, block, defs), line_meta(block) ++ [label: label])
  end

  defp transform_block(%{"type" => "list_item"} = item, defs) do
    transform_list_item(item, defs)
  end

  defp transform_block(other, _defs) do
    {:language_specific, [language: :markdown, hint: :block], other}
  end

  defp transform_list_item(%{"type" => "list_item", "text" => text} = item, defs) do
    children = prose_children(text, item, defs)
    meta = line_meta(item)

    case Map.get(item, "task") do
      nil -> AST.list_item(children, meta)
      checked? -> AST.task_item(checked?, children, meta)
    end
  end

  defp transform_table_row(%{"cells" => cells}, header?, align, defs) do
    table_cells =
      cells
      |> Enum.with_index()
      |> Enum.map(fn {cell, index} ->
        alignment = Enum.at(align, index)

        meta =
          [header?: header?] ++ if(alignment, do: [align: alignment], else: [])

        AST.table_cell(inline_children(cell, %{}, defs), meta)
      end)

    AST.table_row(table_cells, header?: header?)
  end

  # ----- Inline transformers -----

  # Prose text: chunk into sentences → clauses → phrases, so prose rules apply.
  defp prose_children(text, block, defs) do
    text
    |> Inline.parse(defs)
    |> Enum.map(&transform_inline(&1, defs))
    |> chunk_into_sentences(block)
  end

  # Inline text (heading, list item, table cell): inline nodes only.
  defp inline_children(text, _block, defs) do
    text
    |> Inline.parse(defs)
    |> Enum.map(&transform_inline(&1, defs))
  end

  defp transform_inline(%{"type" => "word", "value" => value}, _defs) do
    pos = Tokenizer.tag_pos(value)
    lemma = Tokenizer.lemmatize(value, pos)
    AST.token(value, pos: pos, lemma: lemma)
  end

  defp transform_inline(%{"type" => "punctuation", "value" => value}, _defs) do
    AST.punctuation(value)
  end

  defp transform_inline(%{"type" => "code_span", "value" => value}, _defs) do
    AST.inline_code(value)
  end

  defp transform_inline(%{"type" => "line_break"}, _defs), do: AST.line_break()

  defp transform_inline(%{"type" => "emphasis", "children" => children}, defs) do
    AST.emphasis(Enum.map(children, &transform_inline(&1, defs)))
  end

  defp transform_inline(%{"type" => "strong", "children" => children}, defs) do
    AST.strong(Enum.map(children, &transform_inline(&1, defs)))
  end

  defp transform_inline(%{"type" => "strikethrough", "children" => children}, defs) do
    AST.strikethrough(Enum.map(children, &transform_inline(&1, defs)))
  end

  defp transform_inline(%{"type" => "link", "destination" => dest} = link, defs) do
    children = Enum.map(Map.get(link, "children", []), &transform_inline(&1, defs))
    title = Map.get(link, "title")

    meta = if title, do: [title: title], else: []
    AST.link(children, dest || "", meta)
  end

  defp transform_inline(%{"type" => "image", "destination" => dest} = image, defs) do
    children = Enum.map(Map.get(image, "children", []), &transform_inline(&1, defs))
    title = Map.get(image, "title")

    meta = if title, do: [title: title], else: []
    AST.image(children, dest || "", meta)
  end

  defp transform_inline(%{"type" => "reference_link", "label" => label} = ref, defs) do
    children = Enum.map(Map.get(ref, "children", []), &transform_inline(&1, defs))
    AST.reference_link(children, label)
  end

  defp transform_inline(other, _defs) do
    {:language_specific, [language: :markdown, hint: :inline], other}
  end

  # ----- Sentence chunking -----

  # Splits a flat inline node list into `:sentence` nodes at terminal
  # punctuation. Each sentence is wrapped in a single `:clause`, which is
  # what the prose lint rules traverse.
  defp chunk_into_sentences(nodes, block) do
    nodes
    |> split_sentences()
    |> Enum.map(fn sentence_nodes ->
      clause = AST.clause(build_phrases(sentence_nodes), type: :main)
      AST.sentence([clause], line_meta(block))
    end)
  end

  defp split_sentences(nodes) do
    {sentences, current} =
      Enum.reduce(nodes, {[], []}, fn
        {:punctuation, _meta, value} = node, {sentences, current}
        when value in [".", "!", "?"] ->
          sentence = Enum.reverse([node | current])
          {[sentence | sentences], []}

        node, {sentences, current} ->
          {sentences, [node | current]}
      end)

    finished = Enum.reverse(sentences)

    case Enum.reverse(current) do
      [] -> finished
      trailing -> finished ++ [trailing]
    end
  end

  # Groups consecutive tokens by POS into simple phrases, mirroring the
  # English chunker's contract without re-implementing its full grammar.
  # Inline markup nodes (emphasis, links, inline code, …) are preserved as
  # standalone children so no inline content is lost.
  defp build_phrases(nodes) do
    nodes
    |> Enum.chunk_by(&phrase_class/1)
    |> Enum.flat_map(fn group ->
      case phrase_class(hd(group)) do
        :np -> [AST.phrase(:noun_phrase, group)]
        :vp -> [AST.phrase(:verb_phrase, group)]
        :adv -> [AST.phrase(:adverb_phrase, group)]
        :pp -> [AST.phrase(:prep_phrase, group)]
        :other -> group
      end
    end)
  end

  defp phrase_class({:token, meta, _value}) do
    case Keyword.get(meta, :pos) do
      pos when pos in [:determiner, :adjective, :noun, :proper_noun, :pronoun, :numeral] -> :np
      pos when pos in [:auxiliary, :verb] -> :vp
      :adverb -> :adv
      :preposition -> :pp
      _ -> :other
    end
  end

  defp phrase_class(_node), do: :other

  defp line_meta(%{"line" => line}) when is_integer(line), do: [line: line]
  defp line_meta(_block), do: []
end
