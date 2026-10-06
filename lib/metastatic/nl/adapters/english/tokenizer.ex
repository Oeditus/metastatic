defmodule Metastatic.NL.Adapters.English.Tokenizer do
  @moduledoc """
  Linguistic tokenizer, part-of-speech tagger, and lemmatizer for English.

  Maps surface English words and punctuation to universal POS tags and lemmas.
  """

  @determiners ~w(the a an this that these those every each all some any no both either neither my your his her its our their)
  @pronouns ~w(i you he she it we they me him her us them who whom whose which what myself yourself himself herself itself ourselves yourselves themselves)
  @prepositions ~w(in on at by for with from to into about between through over under after before during without against among upon toward towards)
  @conjunctions ~w(and or but because although though if while unless since so yet whereas whereafter)
  @auxiliaries ~w(be am is are was were been being have has had having do does did can could may might must shall should will would)
  @common_adverbs ~w(not very always never often usually sometimes already still also just only perhaps probably possibly clearly obviously actually certainly definitely really quite rather)

  @doc """
  Determines the Universal POS tag for an English word token.
  """
  @spec tag_pos(String.t()) :: atom()
  def tag_pos(word) when is_binary(word) do
    downcased = String.downcase(word)

    cond do
      downcased in @determiners ->
        :determiner

      downcased in @pronouns ->
        :pronoun

      downcased in @prepositions ->
        :preposition

      downcased in @conjunctions ->
        :conjunction

      downcased in @auxiliaries ->
        :auxiliary

      downcased in @common_adverbs or (String.ends_with?(downcased, "ly") and String.length(downcased) > 3) ->
        :adverb

      Regex.match?(~r/^\d+(\.\d+)?$/, downcased) ->
        :numeral

      # Capitalized mid-sentence or known proper nouns
      Regex.match?(~r/^[A-Z][a-z]+$/, word) and not (downcased in @determiners or downcased in @pronouns) ->
        :proper_noun

      # Morphological verb heuristics
      String.ends_with?(downcased, "ing") and String.length(downcased) > 4 ->
        :verb

      String.ends_with?(downcased, "ed") and String.length(downcased) > 3 ->
        :verb

      String.ends_with?(downcased, "ize") or String.ends_with?(downcased, "ise") ->
        :verb

      # Morphological adjective heuristics
      String.ends_with?(downcased, "able") or String.ends_with?(downcased, "ible") or
        String.ends_with?(downcased, "ous") or String.ends_with?(downcased, "ful") or
          String.ends_with?(downcased, "less") or String.ends_with?(downcased, "ive") ->
        :adjective

      # Morphological noun heuristics
      String.ends_with?(downcased, "tion") or String.ends_with?(downcased, "sion") or
        String.ends_with?(downcased, "ment") or String.ends_with?(downcased, "ness") or
          String.ends_with?(downcased, "ity") or String.ends_with?(downcased, "er") or
          String.ends_with?(downcased, "or") ->
        :noun

      true ->
        :noun
    end
  end

  @doc """
  Derives the canonical base lemma for a given word and POS tag.
  """
  @spec lemmatize(String.t(), atom()) :: String.t()
  def lemmatize(word, pos) when is_binary(word) do
    down = String.downcase(word)

    case pos do
      :verb ->
        cond do
          down in ["is", "am", "are", "was", "were", "been", "being"] -> "be"
          down in ["has", "had", "having"] -> "have"
          down in ["does", "did", "doing"] -> "do"
          String.ends_with?(down, "ies") -> String.slice(down, 0, String.length(down) - 3) <> "y"
          String.ends_with?(down, "es") and String.ends_with?(String.slice(down, 0, String.length(down) - 2), ["s", "sh", "ch", "x", "z"]) -> String.slice(down, 0, String.length(down) - 2)
          String.ends_with?(down, "s") and not String.ends_with?(down, "ss") -> String.slice(down, 0, String.length(down) - 1)
          String.ends_with?(down, "ing") -> lemmatize_ing(down)
          String.ends_with?(down, "ed") -> lemmatize_ed(down)
          true -> down
        end

      :noun ->
        cond do
          down in ["children"] -> "child"
          down in ["people"] -> "person"
          down in ["data"] -> "datum"
          down in ["criteria"] -> "criterion"
          String.ends_with?(down, "ies") -> String.slice(down, 0, String.length(down) - 3) <> "y"
          String.ends_with?(down, "ves") -> String.slice(down, 0, String.length(down) - 3) <> "f"
          String.ends_with?(down, "es") and String.ends_with?(String.slice(down, 0, String.length(down) - 2), ["s", "sh", "ch", "x", "z"]) -> String.slice(down, 0, String.length(down) - 2)
          String.ends_with?(down, "s") and not String.ends_with?(down, "ss") -> String.slice(down, 0, String.length(down) - 1)
          true -> down
        end

      _ ->
        down
    end
  end

  defp lemmatize_ing(word) do
    len = String.length(word)
    base = String.slice(word, 0, len - 3)
    cond do
      String.ends_with?(base, ["bb", "dd", "gg", "mm", "nn", "pp", "rr", "tt"]) ->
        String.slice(base, 0, String.length(base) - 1)
      true ->
        base
    end
  end

  defp lemmatize_ed(word) do
    len = String.length(word)
    base = String.slice(word, 0, len - 2)
    cond do
      String.ends_with?(base, ["bb", "dd", "gg", "mm", "nn", "pp", "rr", "tt"]) ->
        String.slice(base, 0, String.length(base) - 1)
      String.ends_with?(base, "i") ->
        String.slice(base, 0, String.length(base) - 1) <> "y"
      true ->
        base
    end
  end
end
