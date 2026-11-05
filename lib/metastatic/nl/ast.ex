defmodule Metastatic.NL.AST do
  @moduledoc """
  M2: Meta-Model for Natural Language Abstract Syntax (NL-MetaAST).

  Provides a universal, language-neutral abstract representation for natural
  language text, sentences, clauses, phrases, and tokens.

  ## Meta-Modeling Hierarchy

  - **M3:** Elixir type system (`@type`, `@spec`)
  - **M2:** NL-MetaAST (this module) - defines what natural language AST nodes can be
  - **M1:** Language-specific concrete syntax trees (Tree-sitter English CST, Universal Dependencies, etc.)
  - **M0:** Concrete text utterances and written documents

  ## Uniform 3-Tuple Representation

  All NL-MetaAST nodes are uniform 3-element tuples:

      {type_atom, keyword_meta, children_or_value}

  Where:
  - `type_atom` - Node kind (e.g., `:document`, `:sentence`, `:clause`, `:phrase`, `:token`)
  - `keyword_meta` - Keyword list containing metadata (POS, lemma, voice, aspect, line, col, etc.)
  - `children_or_value` - Either a string/nil (for leaf nodes) or a list of child nodes

  ## Stratification

  - **M2.1 Core:** Universal linguistic units present in all human languages:
    `:document`, `:section`, `:paragraph`, `:sentence`, `:clause`, `:phrase`,
    `:token`, `:punctuation`, `:coordination`, `:subordination`.
    The Core layer also carries the universal **markup** blocks and inline
    spans shared by Markdown, RDoc, reStructuredText, AsciiDoc and HTML:
    `:heading`, `:block_quote`, `:code_block`, `:table`, `:table_row`,
    `:table_cell`, `:thematic_break`, `:emphasis`, `:strong`,
    `:strikethrough`, `:link`, `:image`, `:inline_code`, `:line_break`.
  - **M2.2 Extended:** Typological variations and semantic enrichment:
    Tense, Aspect, Mood, Voice (TAM), grammatical gender/number/case,
    hedging/weasel tags, semantic frames, and coreference indices.
    Markup-specific extensions live here too: `:code_fence` (info string /
    language routing), `:task_item` (GitHub task lists), `:reference_link`
    and `:footnote`.
  - **M2.3 Native:** Language-specific escape hatches via `:native_nl_feature`.

  ## Markup Nodes at a Glance

  | Node | Value / children | Notable metadata |
  |------|------------------|------------------|
  | `:heading` | inline children | `:level` (1-6) |
  | `:block_quote` | block children | — |
  | `:code_block` | raw code string | `:language`, `:info` |
  | `:code_fence` | `[]` | `:info`, `:language` |
  | `:table` / `:table_row` | rows / cells | `:align` |
  | `:table_cell` | inline children | `:header?` |
  | `:thematic_break` | `[]` | — |
  | `:emphasis` / `:strong` | inline children | — |
  | `:strikethrough` | inline children | — |
  | `:link` / `:image` | inline children (text/alt) | `:destination`, `:title` |
  | `:reference_link` | inline children | `:label` |
  | `:inline_code` | raw code string | — |
  | `:line_break` | `[]` | — |
  | `:task_item` | inline children | `:checked` |
  | `:footnote` | block children | `:label` |

  Code (`:code_block`, `:inline_code`) is deliberately opaque: `text/1`
  skips it so that prose linting and readability metrics never treat
  source code as prose.
  """

  # ----- Type Definitions -----

  @typedoc "An NL-MetaAST node 3-tuple"
  @type nl_node :: {atom(), keyword(), term()}

  @typedoc "Universal POS (Part-of-Speech) tags"
  @type pos_tag ::
          :noun
          | :proper_noun
          | :verb
          | :adjective
          | :adverb
          | :pronoun
          | :determiner
          | :preposition
          | :postposition
          | :conjunction
          | :auxiliary
          | :numeral
          | :particle
          | :symbol
          | :punctuation
          | :interjection
          | :other

  @typedoc "Phrase syntactic types"
  @type phrase_type ::
          :noun_phrase
          | :verb_phrase
          | :prep_phrase
          | :adj_phrase
          | :adverb_phrase
          | :conjunction_phrase
          | :interjection_phrase

  @typedoc "Clause classification"
  @type clause_type ::
          :main
          | :subordinate
          | :relative
          | :conditional
          | :coordinate
          | :adverbial

  @typedoc "Grammatical voice"
  @type voice :: :active | :passive | :middle

  @typedoc "Grammatical tense"
  @type tense :: :present | :past | :future

  @typedoc "Grammatical aspect"
  @type aspect :: :simple | :progressive | :perfect | :perfect_progressive

  @typedoc "Sentence modality / kind"
  @type sentence_kind :: :declarative | :interrogative | :imperative | :exclamative

  @typedoc "Hedging / weasel classification"
  @type hedging :: :none | :weasel | :tentative | :certain

  @core_types [
    :document,
    :section,
    :paragraph,
    :sentence,
    :clause,
    :phrase,
    :token,
    :punctuation,
    :coordination,
    :subordination,
    :list_block,
    :list_item,
    # Markdown block structure (headings, code fences, block quotes,
    # tables, rules) and inline structure (emphasis, links, images,
    # inline code). These are universal across markup languages, so they
    # live in the Core layer rather than behind a native escape hatch.
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
  ]

  @extended_types [
    :named_entity,
    :coreference,
    # Markdown extended structure: fenced-code language + attributes,
    # task-list checkboxes, reference-style links, footnotes.
    :code_fence,
    :task_item,
    :reference_link,
    :footnote
  ]

  @native_types [
    :native_nl_feature
  ]

  @all_types @core_types ++ @extended_types ++ @native_types

  # ----- Constructors -----

  @doc """
  Constructs a `:token` leaf node.
  """
  @spec token(String.t() | nil, keyword()) :: nl_node()
  def token(text, meta \\ []) do
    {:token, meta, text}
  end

  @doc """
  Constructs a `:punctuation` leaf node.
  """
  @spec punctuation(String.t(), keyword()) :: nl_node()
  def punctuation(symbol, meta \\ []) when is_binary(symbol) do
    {:punctuation, Keyword.put_new(meta, :pos, :punctuation), symbol}
  end

  @doc """
  Constructs a `:phrase` composite node.
  """
  @spec phrase(phrase_type(), list(nl_node()), keyword()) :: nl_node()
  def phrase(type, children, meta \\ []) when is_list(children) do
    {:phrase, Keyword.put(meta, :type, type), children}
  end

  @doc """
  Constructs a `:clause` node.
  """
  @spec clause(list(nl_node()), keyword()) :: nl_node()
  def clause(children, meta \\ []) when is_list(children) do
    {:clause, meta, children}
  end

  @doc """
  Constructs a `:sentence` node.
  """
  @spec sentence(list(nl_node()), keyword()) :: nl_node()
  def sentence(children, meta \\ []) when is_list(children) do
    {:sentence, meta, children}
  end

  @doc """
  Constructs a `:paragraph` node.
  """
  @spec paragraph(list(nl_node()), keyword()) :: nl_node()
  def paragraph(children, meta \\ []) when is_list(children) do
    {:paragraph, meta, children}
  end

  @doc """
  Constructs a `:section` node.
  """
  @spec section(list(nl_node()), keyword()) :: nl_node()
  def section(children, meta \\ []) when is_list(children) do
    {:section, meta, children}
  end

  @doc """
  Constructs a `:document` node.
  """
  @spec document(list(nl_node()), keyword()) :: nl_node()
  def document(children, meta \\ []) when is_list(children) do
    {:document, meta, children}
  end

  # ----- Markdown / Markup Constructors -----

  @doc """
  Constructs a `:heading` node.

  The level (1-6) is stored in metadata under `:level`; the heading's
  inline content (tokens, emphasis, links, ...) is the children list.

  ## Examples

      iex> heading = Metastatic.NL.AST.heading(2, [Metastatic.NL.AST.token("Usage")])
      iex> Metastatic.NL.AST.get_meta(heading, :level)
      2
  """
  @spec heading(pos_integer(), list(nl_node()), keyword()) :: nl_node()
  def heading(level, children, meta \\ []) when is_integer(level) and is_list(children) do
    {:heading, Keyword.put(meta, :level, level), children}
  end

  @doc """
  Constructs a `:block_quote` node wrapping the quoted blocks.
  """
  @spec block_quote(list(nl_node()), keyword()) :: nl_node()
  def block_quote(children, meta \\ []) when is_list(children) do
    {:block_quote, meta, children}
  end

  @doc """
  Constructs a `:code_block` node.

  The raw code text is the leaf value (children), so code blocks are
  opaque to prose linting while remaining traversable as nodes.

  ## Examples

      iex> block = Metastatic.NL.AST.code_block("IO.puts(1)", language: "elixir")
      iex> Metastatic.NL.AST.children(block)
      "IO.puts(1)"
  """
  @spec code_block(String.t() | nil, keyword()) :: nl_node()
  def code_block(code, meta \\ []) when is_binary(code) or is_nil(code) do
    {:code_block, meta, code}
  end

  @doc """
  Constructs a `:list_item` node.

  The item body is the children list; the parent `:list_block` carries the
  `:ordered` flag.

  ## Examples

      iex> item = Metastatic.NL.AST.list_item([Metastatic.NL.AST.token("First")])
      iex> Metastatic.NL.AST.type(item)
      :list_item
  """
  @spec list_item(list(nl_node()), keyword()) :: nl_node()
  def list_item(children, meta \\ []) when is_list(children) do
    {:list_item, meta, children}
  end

  @doc """
  Constructs a `:list_block` node from a list of `:list_item` nodes.
  """
  @spec list_block(list(nl_node()), keyword()) :: nl_node()
  def list_block(items, meta \\ []) when is_list(items) do
    {:list_block, Keyword.put_new(meta, :ordered, false), items}
  end

  @doc """
  Constructs a `:table` node from a list of `:table_row` nodes.
  """
  @spec table(list(nl_node()), keyword()) :: nl_node()
  def table(rows, meta \\ []) when is_list(rows) do
    {:table, meta, rows}
  end

  @doc """
  Constructs a `:table_row` node from a list of `:table_cell` nodes.
  """
  @spec table_row(list(nl_node()), keyword()) :: nl_node()
  def table_row(cells, meta \\ []) when is_list(cells) do
    {:table_row, meta, cells}
  end

  @doc """
  Constructs a `:table_cell` node holding inline content.
  """
  @spec table_cell(list(nl_node()), keyword()) :: nl_node()
  def table_cell(children, meta \\ []) when is_list(children) do
    {:table_cell, meta, children}
  end

  @doc """
  Constructs a `:thematic_break` node (horizontal rule).
  """
  @spec thematic_break(keyword()) :: nl_node()
  def thematic_break(meta \\ []), do: {:thematic_break, meta, []}

  @doc """
  Constructs an `:emphasis` (or `:strong`) inline node.
  """
  @spec emphasis(list(nl_node()), keyword()) :: nl_node()
  def emphasis(children, meta \\ []) when is_list(children) do
    {:emphasis, meta, children}
  end

  @doc """
  Constructs a `:strong` inline node.
  """
  @spec strong(list(nl_node()), keyword()) :: nl_node()
  def strong(children, meta \\ []) when is_list(children) do
    {:strong, meta, children}
  end

  @doc """
  Constructs a `:strikethrough` inline node.
  """
  @spec strikethrough(list(nl_node()), keyword()) :: nl_node()
  def strikethrough(children, meta \\ []) when is_list(children) do
    {:strikethrough, meta, children}
  end

  @doc """
  Constructs a `:link` inline node.

  The link destination is stored in metadata under `:destination` (and an
  optional `:title`); the children are the link text.
  """
  @spec link(list(nl_node()), String.t(), keyword()) :: nl_node()
  def link(children, destination, meta \\ []) when is_list(children) and is_binary(destination) do
    {:link, Keyword.put(meta, :destination, destination), children}
  end

  @doc """
  Constructs an `:image` inline node.

  The image source is stored in metadata under `:destination`; the children
  are the alt text.
  """
  @spec image(list(nl_node()), String.t(), keyword()) :: nl_node()
  def image(children, destination, meta \\ [])
      when is_list(children) and is_binary(destination) do
    {:image, Keyword.put(meta, :destination, destination), children}
  end

  @doc """
  Constructs an `:inline_code` leaf node.
  """
  @spec inline_code(String.t(), keyword()) :: nl_node()
  def inline_code(code, meta \\ []) when is_binary(code) do
    {:inline_code, meta, code}
  end

  @doc """
  Constructs a `:line_break` node (hard break, two trailing spaces or `\\`).
  """
  @spec line_break(keyword()) :: nl_node()
  def line_break(meta \\ []), do: {:line_break, meta, []}

  @doc """
  Constructs a `:code_fence` node.

  Captures the info string (language + attributes) of a fenced code block
  so the code can be routed to the matching programming-language adapter.
  """
  @spec code_fence(String.t() | nil, keyword()) :: nl_node()
  def code_fence(info, meta \\ []) when is_binary(info) or is_nil(info) do
    {:code_fence, Keyword.put(meta, :info, info), []}
  end

  @doc """
  Constructs a `:task_item` node for a GitHub-style task list entry.

  `checked` is `true`/`false` for `[x]` / `[ ]`; children hold the item body.
  """
  @spec task_item(boolean(), list(nl_node()), keyword()) :: nl_node()
  def task_item(checked, children, meta \\ []) when is_boolean(checked) and is_list(children) do
    {:task_item, Keyword.put(meta, :checked, checked), children}
  end

  @doc """
  Constructs a `:reference_link` node (link defined by a reference label).
  """
  @spec reference_link(list(nl_node()), String.t(), keyword()) :: nl_node()
  def reference_link(children, label, meta \\ []) when is_list(children) and is_binary(label) do
    {:reference_link, Keyword.put(meta, :label, label), children}
  end

  @doc """
  Constructs a `:footnote` node.
  """
  @spec footnote(list(nl_node()), keyword()) :: nl_node()
  def footnote(children, meta \\ []) when is_list(children) do
    {:footnote, meta, children}
  end

  # ----- Node Accessors -----
  #
  # These are identical to the programming-language MetaAST and are delegated
  # to the shared `Metastatic.MetaAST` core so the two meta-ASTs cannot drift.

  @doc "Returns the type atom of an NL node."
  @spec type(nl_node()) :: atom()
  defdelegate type(node), to: Metastatic.MetaAST

  @doc "Returns the metadata keyword list of an NL node."
  @spec meta(nl_node()) :: keyword()
  defdelegate meta(node), to: Metastatic.MetaAST

  @doc "Returns the children list or leaf value of an NL node."
  @spec children(nl_node()) :: term()
  defdelegate children(node), to: Metastatic.MetaAST

  @doc "Gets a metadata value by key, returning default if absent."
  @spec get_meta(nl_node(), atom(), term()) :: term()
  defdelegate get_meta(node, key, default \\ nil), to: Metastatic.MetaAST

  @doc "Sets or updates a metadata key."
  @spec put_meta(nl_node(), atom(), term()) :: nl_node()
  defdelegate put_meta(node, key, value), to: Metastatic.MetaAST

  @doc "Merges a keyword list of metadata updates into the node."
  @spec update_meta(nl_node(), keyword()) :: nl_node()
  defdelegate update_meta(node, updates), to: Metastatic.MetaAST

  @doc "Updates a metadata value with a function."
  @spec update_meta(nl_node(), atom(), term(), (term() -> term())) :: nl_node()
  defdelegate update_meta(node, key, default, fun), to: Metastatic.MetaAST

  # ----- Traversal -----

  @doc """
  Traverses an NL-MetaAST depth-first with pre-visit and post-visit functions.

  Delegates to `Metastatic.MetaAST.traverse/4`, which also visits metadata
  values that contain nodes (e.g. a `:coreference` target).
  """
  @spec traverse(nl_node(), acc, (nl_node(), acc -> {nl_node(), acc}), (nl_node(), acc ->
                                                                          {nl_node(), acc})) ::
          {nl_node(), acc}
        when acc: term()
  defdelegate traverse(node, acc, pre, post), to: Metastatic.MetaAST

  @doc "Pre-walk traversal over an NL-MetaAST."
  @spec prewalk(nl_node(), (nl_node() -> nl_node())) :: nl_node()
  defdelegate prewalk(node, fun), to: Metastatic.MetaAST

  @doc "Post-walk traversal over an NL-MetaAST."
  @spec postwalk(nl_node(), (nl_node() -> nl_node())) :: nl_node()
  defdelegate postwalk(node, fun), to: Metastatic.MetaAST

  @doc "Lazy depth-first pre-order enumerable over an NL-MetaAST."
  @spec prewalker(nl_node()) :: Enumerable.t()
  defdelegate prewalker(node), to: Metastatic.MetaAST

  @doc "Lazy pre-order enumerable that threads an accumulator."
  @spec prewalker(nl_node(), acc, (nl_node(), acc -> {term(), acc})) :: Enumerable.t()
        when acc: term()
  defdelegate prewalker(node, acc, fun), to: Metastatic.MetaAST

  @doc "Path from a matching NL node up to the root, or `nil`."
  @spec path(nl_node(), (nl_node() -> as_boolean(term()))) :: [nl_node()] | nil
  defdelegate path(node, fun), to: Metastatic.MetaAST

  # ----- Extraction Utilities -----

  @doc """
  Extracts all `:token` nodes from the tree.
  """
  @spec tokens(nl_node()) :: [nl_node()]
  def tokens(node) do
    {_, collected} =
      traverse(
        node,
        [],
        fn
          {:token, _, _} = t, acc -> {t, [t | acc]}
          n, acc -> {n, acc}
        end,
        fn n, acc -> {n, acc} end
      )

    Enum.reverse(collected)
  end

  @doc """
  Extracts all string words from word-like tokens (excluding punctuation).
  """
  @spec words(nl_node()) :: [String.t()]
  def words(node) do
    tokens(node)
    |> Enum.map(fn {:token, _meta, val} -> val end)
    |> Enum.reject(&(&1 == nil or String.trim(&1) == ""))
  end

  @doc """
  Extracts all distinct lemmas from the tokens.
  """
  @spec lemmas(nl_node()) :: [String.t()]
  def lemmas(node) do
    tokens(node)
    |> Enum.map(fn {:token, meta, val} -> Keyword.get(meta, :lemma, val) end)
    |> Enum.reject(&(&1 == nil or String.trim(&1) == ""))
    |> Enum.uniq()
  end

  @doc """
  Extracts all `:sentence` nodes from the tree.
  """
  @spec sentences(nl_node()) :: [nl_node()]
  def sentences(node) do
    {_, collected} =
      traverse(
        node,
        [],
        fn
          {:sentence, _, _} = s, acc -> {s, [s | acc]}
          n, acc -> {n, acc}
        end,
        fn n, acc -> {n, acc} end
      )

    Enum.reverse(collected)
  end

  @doc """
  Extracts all `:clause` nodes from the tree.
  """
  @spec clauses(nl_node()) :: [nl_node()]
  def clauses(node) do
    {_, collected} =
      traverse(
        node,
        [],
        fn
          {:clause, _, _} = c, acc -> {c, [c | acc]}
          n, acc -> {n, acc}
        end,
        fn n, acc -> {n, acc} end
      )

    Enum.reverse(collected)
  end

  @doc """
  Extracts all `:phrase` nodes from the tree.
  """
  @spec phrases(nl_node()) :: [nl_node()]
  def phrases(node) do
    {_, collected} =
      traverse(
        node,
        [],
        fn
          {:phrase, _, _} = p, acc -> {p, [p | acc]}
          n, acc -> {n, acc}
        end,
        fn n, acc -> {n, acc} end
      )

    Enum.reverse(collected)
  end

  @doc """
  Extracts all nodes of a given type from the tree, in document order.

  ## Examples

      iex> doc = Metastatic.NL.AST.document([
      ...>   Metastatic.NL.AST.heading(1, [Metastatic.NL.AST.token("Title")]),
      ...>   Metastatic.NL.AST.heading(2, [Metastatic.NL.AST.token("Section")])
      ...> ])
      iex> doc |> Metastatic.NL.AST.all(:heading) |> Enum.map(&Metastatic.NL.AST.get_meta(&1, :level))
      [1, 2]
  """
  @spec all(nl_node(), atom()) :: [nl_node()]
  def all(node, type) when is_atom(type) do
    {_, collected} =
      traverse(
        node,
        [],
        fn
          {^type, _, _} = n, acc -> {n, [n | acc]}
          n, acc -> {n, acc}
        end,
        fn n, acc -> {n, acc} end
      )

    Enum.reverse(collected)
  end

  @doc """
  Extracts all `:heading` nodes from the tree.
  """
  @spec headings(nl_node()) :: [nl_node()]
  def headings(node), do: all(node, :heading)

  @doc """
  Extracts all `:code_block` nodes from the tree.
  """
  @spec code_blocks(nl_node()) :: [nl_node()]
  def code_blocks(node), do: all(node, :code_block)

  @doc """
  Extracts all `:link` nodes from the tree.
  """
  @spec links(nl_node()) :: [nl_node()]
  def links(node), do: all(node, :link)

  @doc """
  Extracts all `:list_item` and `:task_item` nodes from the tree.
  """
  @spec list_items(nl_node()) :: [nl_node()]
  def list_items(node), do: all(node, :list_item) ++ all(node, :task_item)

  @doc """
  Extracts all `:table` nodes from the tree.
  """
  @spec tables(nl_node()) :: [nl_node()]
  def tables(node), do: all(node, :table)

  @doc """
  Reconstructs readable text from the leaf tokens and punctuation.

  Markup structure is rendered structurally: headings become their inline
  text, list items and table cells are separated, block quotes are kept,
  and code blocks / inline code are **omitted** so that prose linting and
  readability metrics never see source code as prose.
  """
  @spec text(nl_node()) :: String.t()
  def text(node) do
    node
    |> render_text_nodes()
    |> join_surface_tokens()
  end

  # Renders a subtree into a flat list of surface strings. Block-level
  # markup contributes separators; code is skipped entirely.
  defp render_text_nodes({type, _meta, children}) when type in [:code_block, :inline_code] do
    _ = children
    []
  end

  defp render_text_nodes({:token, _meta, val}) when is_binary(val), do: [val]
  defp render_text_nodes({:punctuation, _meta, val}) when is_binary(val), do: [val]

  # Inline containers contribute no separator of their own: their surface
  # text flows into the surrounding run (`**bold** text` → `bold text`).
  defp render_text_nodes({type, _meta, children})
       when type in [:emphasis, :strong, :strikethrough, :link, :image, :reference_link] do
    render_children(children)
  end

  defp render_text_nodes({:line_break, _meta, _children}), do: ["\n"]
  defp render_text_nodes({:thematic_break, _meta, _children}), do: ["\n"]

  defp render_text_nodes({:heading, _meta, children}),
    do: ["\n"] ++ render_children(children) ++ ["\n"]

  defp render_text_nodes({:block_quote, _meta, children}),
    do: ["\n"] ++ render_children(children) ++ ["\n"]

  defp render_text_nodes({:list_item, _meta, children}), do: ["\n"] ++ render_children(children)
  defp render_text_nodes({:task_item, _meta, children}), do: ["\n"] ++ render_children(children)
  defp render_text_nodes({:table_row, _meta, children}), do: ["\n"] ++ render_children(children)
  defp render_text_nodes({:table_cell, _meta, children}), do: [" "] ++ render_children(children)
  defp render_text_nodes({:paragraph, _meta, children}), do: ["\n"] ++ render_children(children)

  defp render_text_nodes({_type, _meta, children}) when is_list(children),
    do: render_children(children)

  defp render_text_nodes(_other), do: []

  defp render_children(children) when is_list(children),
    do: Enum.flat_map(children, &render_text_nodes/1)

  defp join_surface_tokens(tokens) do
    tokens
    |> Enum.reduce("", fn token, acc ->
      cond do
        acc == "" ->
          token

        String.ends_with?(acc, "\n") ->
          acc <> token

        token in [".", ",", ";", ":", "!", "?", "'", "’", ")", "]", "}"] ->
          acc <> token

        String.ends_with?(acc, "(") or String.ends_with?(acc, "[") or
            String.ends_with?(acc, "{") ->
          acc <> token

        true ->
          acc <> " " <> token
      end
    end)
    |> String.replace(~r/[ \t]+/, " ")
    |> String.replace(~r/ *\n */, "\n")
    |> String.trim()
  end

  # ----- Conformance Checking -----

  @doc """
  Determines whether an arbitrary term conforms to the NL-MetaAST specification.

  Markup nodes are validated structurally: leaf nodes (`:code_block`,
  `:inline_code`) carry a binary (or `nil`) value, while every other
  composite node must hold a list of conforming children.
  """
  @spec conforms?(term()) :: boolean()
  def conforms?({type, meta, children})
      when type in @all_types and is_list(meta) do
    if Keyword.keyword?(meta) do
      case type do
        :token ->
          is_binary(children) or is_nil(children)

        :punctuation ->
          is_binary(children)

        :code_block ->
          is_binary(children) or is_nil(children)

        :inline_code ->
          is_binary(children)

        :heading ->
          is_integer(Keyword.get(meta, :level)) and valid_children?(children)

        :native_nl_feature when is_list(children) ->
          Enum.all?(children, &conforms?/1)

        :native_nl_feature ->
          true

        _composite when is_list(children) ->
          Enum.all?(children, &conforms?/1)

        _ ->
          false
      end
    else
      false
    end
  end

  def conforms?(_), do: false

  defp valid_children?(children), do: is_list(children) and Enum.all?(children, &conforms?/1)

  @doc """
  Returns the list of all supported NL-MetaAST node types.
  """
  @spec supported_types() :: [atom()]
  def supported_types, do: @all_types

  @doc """
  Returns whether a node type belongs to the Core (M2.1) layer.
  """
  @spec core_type?(atom()) :: boolean()
  def core_type?(type), do: type in @core_types

  @doc """
  Returns whether a node type belongs to the Extended (M2.2) layer.
  """
  @spec extended_type?(atom()) :: boolean()
  def extended_type?(type), do: type in @extended_types

  @doc """
  Returns whether a node type belongs to the Native (M2.3) layer.
  """
  @spec native_type?(atom()) :: boolean()
  def native_type?(type), do: type in @native_types
end
