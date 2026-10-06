defmodule Metastatic.NL.Semantic.Enricher do
  @moduledoc """
  Semantic and pragmatic enricher for NL-MetaAST trees.

  Enriches syntactic nodes with:
  - Grammatical voice (`voice: :active` or `voice: :passive`)
  - Semantic roles (`sem_role: :agent` and `sem_role: :patient`)
  - Hedging and weasel word detection (`hedging: :weasel`)
  - Readability and complexity metrics
  """

  alias Metastatic.NL.AST
  alias Metastatic.NL.Semantic.Readability

  @be_verbs ~w(be is am are was were been being)
  @common_irregular_past_participles ~w(
    written done built taken read sent given found run made known seen gone broken
    chosen driven fallen forgotten frozen grown hidden ridden risen shaken spoken
    stolen thrown worn begun drank drunk sung swam won lost understood held brought
    caught taught thought fought bought felt kept left met meant paid said sold told
    sent spent built lent lost
  )

  @weasel_words ~w(
    probably possibly perhaps maybe seemingly reportedly arguably clearly obviously
    basically essentially fairly somewhat relatively quite virtually largely
  )

  @hedging_modals ~w(might could may)

  @doc """
  Recursively enriches an NL-MetaAST tree.
  """
  @spec enrich(AST.nl_node()) :: AST.nl_node()
  def enrich(node) do
    # Pass 1: enrich clauses, phrases, and tokens
    enriched_tree =
      AST.postwalk(node, fn
        {:token, meta, val} ->
          enrich_token({:token, meta, val})

        {:phrase, meta, children} ->
          enrich_phrase({:phrase, meta, children})

        {:clause, meta, children} ->
          enrich_clause({:clause, meta, children})

        {:sentence, _meta, _children} = sent ->
          metrics = Readability.metrics(sent)

          sent
          |> AST.put_meta(:words_count, metrics.words_count)
          |> AST.put_meta(:syllables_count, metrics.syllables_count)
          |> AST.put_meta(:flesch_reading_ease, metrics.flesch_reading_ease)
          |> AST.put_meta(:flesch_kincaid_grade, metrics.flesch_kincaid_grade)

        other ->
          other
      end)

    # Pass 2: attach document-level readability if root is document
    case enriched_tree do
      {:document, _meta, _children} = doc ->
        doc_metrics = Readability.metrics(doc)
        AST.put_meta(doc, :readability, doc_metrics)

      other ->
        other
    end
  end

  defp enrich_token({:token, _meta, val} = token) when is_binary(val) do
    down = String.downcase(val)

    cond do
      down in @weasel_words ->
        AST.put_meta(token, :hedging, :weasel)

      down in @hedging_modals ->
        AST.put_meta(token, :hedging, :tentative)

      true ->
        token
    end
  end

  defp enrich_token(token), do: token

  defp enrich_phrase({:phrase, _meta, children} = phrase) do
    has_weasel =
      Enum.any?(children, fn
        {:token, m, _} -> Keyword.get(m, :hedging) in [:weasel, :tentative]
        _ -> false
      end)

    if has_weasel do
      AST.put_meta(phrase, :hedging, :weasel)
    else
      phrase
    end
  end

  defp enrich_clause({:clause, _meta, children} = clause) do
    voice = detect_clause_voice(children)
    hedging = detect_clause_hedging(children)

    updated_children = assign_semantic_roles(children, voice)

    clause
    |> AST.put_meta(:voice, voice)
    |> AST.put_meta(:hedging, hedging)
    |> struct_children(updated_children)
  end

  defp struct_children({type, meta, _}, new_children) do
    {type, meta, new_children}
  end

  defp detect_clause_voice(children) do
    # Search for verb phrase with auxiliary 'be' + past participle
    vp =
      Enum.find(children, fn
        {:phrase, meta, _} -> Keyword.get(meta, :type) == :verb_phrase
        _ -> false
      end)

    case vp do
      {:phrase, _, vp_children} ->
        words =
          vp_children
          |> Enum.filter(&match?({:token, _, _}, &1))
          |> Enum.map(fn {:token, m, val} -> {String.downcase(val || ""), Keyword.get(m, :pos)} end)

        if has_passive_construction?(words) do
          :passive
        else
          :active
        end

      _ ->
        :active
    end
  end

  defp has_passive_construction?(words) do
    # Look for pair of: (be-auxiliary, past_participle)
    words
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.any?(fn [{w1, _pos1}, {w2, _pos2}] ->
      is_be_aux = w1 in @be_verbs

      is_past_participle =
        String.ends_with?(w2, "ed") or
          String.ends_with?(w2, "en") or
          w2 in @common_irregular_past_participles

      is_be_aux and is_past_participle
    end)
  end

  defp detect_clause_hedging(children) do
    has_weasel =
      Enum.any?(children, fn
        {:phrase, m, _} -> Keyword.get(m, :hedging) == :weasel
        {:token, m, _} -> Keyword.get(m, :hedging) == :weasel
        _ -> false
      end)

    if has_weasel, do: :weasel, else: :none
  end

  defp assign_semantic_roles(children, :passive) do
    Enum.map(children, fn
      {:phrase, meta, c} ->
        role = Keyword.get(meta, :role)
        type = Keyword.get(meta, :type)

        cond do
          role == :subject ->
            AST.phrase(type, c, Keyword.put(meta, :sem_role, :patient))

          type == :prep_phrase and starts_with_by?(c) ->
            AST.phrase(type, c, Keyword.put(meta, :sem_role, :agent))

          true ->
            {:phrase, meta, c}
        end

      other ->
        other
    end)
  end

  defp assign_semantic_roles(children, :active) do
    Enum.map(children, fn
      {:phrase, meta, c} ->
        role = Keyword.get(meta, :role)
        type = Keyword.get(meta, :type)

        cond do
          role == :subject ->
            AST.phrase(type, c, Keyword.put(meta, :sem_role, :agent))

          role == :object ->
            AST.phrase(type, c, Keyword.put(meta, :sem_role, :patient))

          true ->
            {:phrase, meta, c}
        end

      other ->
        other
    end)
  end

  defp starts_with_by?([{:token, _, val} | _]) when is_binary(val) do
    String.downcase(val) == "by"
  end

  defp starts_with_by?(_), do: false
end
