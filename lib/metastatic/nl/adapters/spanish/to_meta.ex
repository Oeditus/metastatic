defmodule Metastatic.NL.Adapters.Spanish.ToMeta do
  @moduledoc """
  Transforms Spanish CST / tokens to NL-MetaAST (M2).
  """

  alias Metastatic.NL.Adapters.Spanish.Tokenizer
  alias Metastatic.NL.AST

  @ser_forms ~w(es son fue fueron era eran sido sea)

  @doc """
  Transforms text or tokens into NL-MetaAST document.
  """
  @spec transform(map() | String.t()) :: {:ok, AST.nl_node(), map()}
  def transform(source) when is_binary(source) do
    paragraphs =
      source
      |> String.split(~r/\n\s*\n/)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    para_nodes =
      Enum.map(paragraphs, fn para ->
        sentences =
          para
          |> String.split(~r/(?<=[.!?¡¿])\s+/)
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))

        sent_nodes = Enum.map(sentences, &transform_sentence/1)
        AST.paragraph(sent_nodes)
      end)

    doc_node = AST.document(para_nodes, language: :es, format: :prose)
    {:ok, doc_node, %{language: :es}}
  end

  def transform(%{"children" => _} = map) do
    # When given CST map
    transform(to_string(map))
  end

  defp transform_sentence(sentence) do
    tokens = tokenize_sentence(sentence)
    {body_tokens, punct_tokens} = split_punct(tokens)

    leaf_nodes =
      Enum.map(body_tokens, fn {raw, col} ->
        pos = Tokenizer.tag_pos(raw)
        lemma = Tokenizer.lemmatize(raw, pos)
        AST.token(raw, pos: pos, lemma: lemma, col: col)
      end)

    phrases = chunk_phrases(leaf_nodes)
    clause = build_clause(phrases)

    terminal_nodes =
      Enum.map(punct_tokens, fn {val, col} ->
        AST.punctuation(val, col: col)
      end)

    kind =
      cond do
        String.ends_with?(sentence, "?") or String.starts_with?(sentence, "¿") -> :interrogative
        String.ends_with?(sentence, "!") or String.starts_with?(sentence, "¡") -> :exclamative
        true -> :declarative
      end

    AST.sentence([clause | terminal_nodes], kind: kind)
  end

  defp tokenize_sentence(sentence) do
    regex = ~r/([A-Za-zÁÉÍÓÚáéíóúñÑ0-9]+(?:'[A-Za-z]+)?|[-–—]|[:;,.!?¡¿(){}[\]"“”'’])/u

    Regex.scan(regex, sentence, return: :index)
    |> Enum.map(fn [{start, len} | _] ->
      raw = binary_part(sentence, start, len)
      {raw, start + 1}
    end)
  end

  defp split_punct(tokens) do
    case Enum.reverse(tokens) do
      [{p, _} = last | rest] when p in [".", "!", "?", "¡", "¿"] ->
        {Enum.reverse(rest), [last]}

      _ ->
        {tokens, []}
    end
  end

  defp chunk_phrases(nodes) do
    chunk_loop(nodes, [])
  end

  defp chunk_loop([], acc), do: Enum.reverse(acc)

  defp chunk_loop([{:token, meta_p, val_p} = prep_node | rest], acc) do
    if Keyword.get(meta_p, :pos) == :preposition do
      {np_tokens, remaining} = extract_np(rest)

      if np_tokens != [] do
        np_phrase = AST.phrase(:noun_phrase, np_tokens)
        role = if String.downcase(val_p) == "por", do: :agent_by_phrase, else: :adverbial
        pp_node = AST.phrase(:prep_phrase, [prep_node, np_phrase], role: role)
        chunk_loop(remaining, [pp_node | acc])
      else
        chunk_loop(rest, [prep_node | acc])
      end
    else
      chunk_other([prep_node | rest], acc)
    end
  end

  defp chunk_loop(nodes, acc) do
    chunk_other(nodes, acc)
  end

  defp chunk_other([{:token, meta, _} = node | rest], acc) do
    pos = Keyword.get(meta, :pos)

    cond do
      pos in [:determiner, :noun, :proper_noun, :pronoun] ->
        {np_tokens, remaining} = extract_np([node | rest])
        np_node = AST.phrase(:noun_phrase, np_tokens)
        chunk_loop(remaining, [np_node | acc])

      pos in [:auxiliary, :verb] ->
        {vp_tokens, remaining} = extract_vp([node | rest])
        vp_node = AST.phrase(:verb_phrase, vp_tokens)
        chunk_loop(remaining, [vp_node | acc])

      pos == :adverb ->
        adv_node = AST.phrase(:adverb_phrase, [node])
        chunk_loop(rest, [adv_node | acc])

      true ->
        chunk_loop(rest, [node | acc])
    end
  end

  defp chunk_other([other | rest], acc) do
    chunk_loop(rest, [other | acc])
  end

  defp extract_np(nodes) do
    {np_items, rest} =
      Enum.split_while(nodes, fn
        {:token, meta, _} ->
          Keyword.get(meta, :pos) in [:determiner, :noun, :proper_noun, :adjective, :pronoun]

        _ ->
          false
      end)

    {np_items, rest}
  end

  defp extract_vp(nodes) do
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
    is_passive = detect_spanish_passive(phrases)

    {assigned, _} =
      Enum.map_reduce(phrases, :before_verb, fn phrase, state ->
        case phrase do
          {:phrase, meta, children} ->
            type = Keyword.get(meta, :type)

            cond do
              type == :verb_phrase ->
                {phrase, :after_verb}

              type == :noun_phrase and state == :before_verb ->
                sem_role = if is_passive, do: :patient, else: :agent

                {AST.phrase(
                   :noun_phrase,
                   children,
                   Keyword.merge(meta, role: :subject, sem_role: sem_role)
                 ), state}

              type == :noun_phrase and state == :after_verb ->
                {AST.phrase(
                   :noun_phrase,
                   children,
                   Keyword.merge(meta, role: :object, sem_role: :patient)
                 ), state}

              type == :prep_phrase and Keyword.get(meta, :role) == :agent_by_phrase and is_passive ->
                {AST.phrase(:prep_phrase, children, Keyword.put(meta, :sem_role, :agent)), state}

              true ->
                {phrase, state}
            end

          other ->
            {other, state}
        end
      end)

    voice = if is_passive, do: :passive, else: :active
    AST.clause(assigned, type: :main, voice: voice)
  end

  defp detect_spanish_passive(phrases) do
    vp =
      Enum.find(phrases, fn
        {:phrase, meta, _} -> Keyword.get(meta, :type) == :verb_phrase
        _ -> false
      end)

    case vp do
      {:phrase, _, children} ->
        words =
          children
          |> Enum.filter(&match?({:token, _, _}, &1))
          |> Enum.map(fn {:token, _, val} -> String.downcase(val || "") end)

        # Check for pair of: ser + participles
        words
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.any?(fn [w1, w2] ->
          w1 in @ser_forms and
            (Tokenizer.regular_participle?(w2) or w2 in ["escrito", "hecho", "dicho", "visto"])
        end)

      _ ->
        false
    end
  end
end
