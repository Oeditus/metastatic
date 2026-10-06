defmodule Metastatic.NL.Adapters.English.ToMeta do
  @moduledoc """
  Transforms English CST (M1) to NL-MetaAST (M2).

  Performs lexical tagging, phrase chunking, and clause structuring.
  """

  alias Metastatic.NL.AST
  alias Metastatic.NL.Adapters.English.Tokenizer

  @doc """
  Transforms M1 CST map representation into M2 NL-MetaAST.
  """
  @spec transform(map()) :: {:ok, AST.nl_node(), map()}
  def transform(%{"type" => "document", "children" => paragraphs}) do
    para_nodes = Enum.map(paragraphs, &transform_paragraph/1)
    doc_node = AST.document(para_nodes, language: :en, format: :prose)
    {:ok, doc_node, %{language: :en}}
  end

  def transform(%{"type" => "paragraph"} = para) do
    {:ok, transform_paragraph(para), %{language: :en}}
  end

  def transform(%{"type" => "sentence"} = sent) do
    {:ok, transform_sentence(sent), %{language: :en}}
  end

  defp transform_paragraph(%{"children" => sentences}) do
    sent_nodes = Enum.map(sentences, &transform_sentence/1)
    AST.paragraph(sent_nodes)
  end

  defp transform_sentence(%{"children" => tokens} = sent) do
    # Separate terminal punctuation from words/internal punctuation
    {body_tokens, punct_tokens} = split_terminal_punct(tokens)

    # Convert tokens to leaf nodes with POS and lemma
    leaf_nodes =
      Enum.map(body_tokens, fn
        %{"type" => "punctuation", "value" => val} = m ->
          AST.punctuation(val, line: m["line"], col: m["col"])

        %{"type" => "word", "value" => val} = m ->
          pos = Tokenizer.tag_pos(val)
          lemma = Tokenizer.lemmatize(val, pos)
          AST.token(val, pos: pos, lemma: lemma, line: m["line"], col: m["col"])
      end)

    # Chunk tokens into syntactic phrases
    phrases = chunk_phrases(leaf_nodes)

    # Form a clause from the phrases
    clause = build_clause(phrases)

    terminal_nodes =
      Enum.map(punct_tokens, fn m ->
        AST.punctuation(m["value"], line: m["line"], col: m["col"])
      end)

    kind = detect_sentence_kind(sent["text"], terminal_nodes)
    AST.sentence([clause | terminal_nodes], kind: kind)
  end

  defp split_terminal_punct(tokens) do
    case Enum.reverse(tokens) do
      [%{"type" => "punctuation", "value" => p} = last | rest] when p in [".", "!", "?"] ->
        {Enum.reverse(rest), [last]}

      _ ->
        {tokens, []}
    end
  end

  defp detect_sentence_kind(text, terminal_punct) do
    last_symbol =
      case terminal_punct do
        [{:punctuation, _, sym} | _] -> sym
        _ -> ""
      end

    cond do
      last_symbol == "?" -> :interrogative
      last_symbol == "!" -> :exclamative
      String.ends_with?(text || "", "?") -> :interrogative
      String.ends_with?(text || "", "!") -> :exclamative
      true -> :declarative
    end
  end

  # Chunking engine: transforms a sequence of tokens into phrase nodes
  defp chunk_phrases(nodes) do
    chunk_phrases_loop(nodes, [])
  end

  defp chunk_phrases_loop([], acc), do: Enum.reverse(acc)

  # Prepositional phrase: PREP followed by NP
  defp chunk_phrases_loop([{:token, meta_p, _} = prep_node | rest], acc) do
    if Keyword.get(meta_p, :pos) == :preposition do
      {np_tokens, remaining} = extract_np_tokens(rest)

      if np_tokens != [] do
        np_phrase = AST.phrase(:noun_phrase, np_tokens)
        pp_node = AST.phrase(:prep_phrase, [prep_node, np_phrase])
        chunk_phrases_loop(remaining, [pp_node | acc])
      else
        chunk_phrases_loop(rest, [prep_node | acc])
      end
    else
      chunk_other([prep_node | rest], acc)
    end
  end

  defp chunk_phrases_loop(nodes, acc) do
    chunk_other(nodes, acc)
  end

  defp chunk_other([{:token, meta, _} = node | rest], acc) do
    pos = Keyword.get(meta, :pos)

    cond do
      pos in [:determiner, :adjective, :noun, :proper_noun, :pronoun] ->
        {np_tokens, remaining} = extract_np_tokens([node | rest])
        np_node = AST.phrase(:noun_phrase, np_tokens)
        chunk_phrases_loop(remaining, [np_node | acc])

      pos in [:auxiliary, :verb] ->
        {vp_tokens, remaining} = extract_vp_tokens([node | rest])
        vp_node = AST.phrase(:verb_phrase, vp_tokens)
        chunk_phrases_loop(remaining, [vp_node | acc])

      pos == :adverb ->
        adv_node = AST.phrase(:adverb_phrase, [node])
        chunk_phrases_loop(rest, [adv_node | acc])

      true ->
        chunk_phrases_loop(rest, [node | acc])
    end
  end

  defp chunk_other([punct_or_other | rest], acc) do
    chunk_phrases_loop(rest, [punct_or_other | acc])
  end

  defp extract_np_tokens(nodes) do
    {np_items, rest} =
      Enum.split_while(nodes, fn
        {:token, meta, _} ->
          Keyword.get(meta, :pos) in [:determiner, :adjective, :noun, :proper_noun, :pronoun, :numeral]

        _ ->
          false
      end)

    {np_items, rest}
  end

  defp extract_vp_tokens(nodes) do
    {vp_items, rest} =
      Enum.split_while(nodes, fn
        {:token, meta, _} ->
          Keyword.get(meta, :pos) in [:auxiliary, :verb, :adverb]

        _ ->
          false
      end)

    {vp_items, rest}
  end

  defp build_clause(phrases) do
    # Assign grammatical roles to noun phrases based on position relative to verb phrase
    {assigned, _} =
      Enum.map_reduce(phrases, :before_verb, fn phrase, state ->
        case phrase do
          {:phrase, meta, children} ->
            type = Keyword.get(meta, :type)

            cond do
              type == :verb_phrase ->
                {phrase, :after_verb}

              type == :noun_phrase and state == :before_verb ->
                {AST.phrase(:noun_phrase, children, Keyword.put(meta, :role, :subject)), state}

              type == :noun_phrase and state == :after_verb ->
                {AST.phrase(:noun_phrase, children, Keyword.put(meta, :role, :object)), state}

              true ->
                {phrase, state}
            end

          other ->
            {other, state}
        end
      end)

    AST.clause(assigned, type: :main)
  end
end
