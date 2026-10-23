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
  - **M2.2 Extended:** Typological variations and semantic enrichment:
    Tense, Aspect, Mood, Voice (TAM), grammatical gender/number/case,
    hedging/weasel tags, semantic frames, and coreference indices.
  - **M2.3 Native:** Language-specific escape hatches via `:native_nl_feature`.
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
    :list_item
  ]

  @extended_types [
    :named_entity,
    :coreference
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
  Reconstructs readable text from the leaf tokens and punctuation.
  """
  @spec text(nl_node()) :: String.t()
  def text(node) do
    {_, parts} =
      traverse(
        node,
        [],
        fn
          {:token, _, val}, acc when is_binary(val) ->
            {{:token, [], val}, [val | acc]}

          {:punctuation, _, val}, acc when is_binary(val) ->
            {{:punctuation, [], val}, [val | acc]}

          n, acc ->
            {n, acc}
        end,
        fn n, acc -> {n, acc} end
      )

    parts
    |> Enum.reverse()
    |> join_surface_tokens()
  end

  defp join_surface_tokens(tokens) do
    Enum.reduce(tokens, "", fn token, acc ->
      cond do
        acc == "" ->
          token

        token in [".", ",", ";", ":", "!", "?", "'", "’", ")", "]", "}"] ->
          acc <> token

        String.ends_with?(acc, "(") or String.ends_with?(acc, "[") or
            String.ends_with?(acc, "{") ->
          acc <> token

        true ->
          acc <> " " <> token
      end
    end)
  end

  # ----- Conformance Checking -----

  @doc """
  Determines whether an arbitrary term conforms to the NL-MetaAST specification.
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
