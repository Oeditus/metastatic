defmodule Metastatic.NL.Semantic.Readability do
  @moduledoc """
  Readability metrics calculation for Natural Language MetaAST.

  Computes syllable counts, word lengths, Flesch Reading Ease,
  and Flesch-Kincaid Grade Level.
  """

  alias Metastatic.NL.AST

  @doc """
  Estimates the number of syllables in an English word.
  """
  @spec count_syllables(String.t()) :: pos_integer()
  def count_syllables(word) when is_binary(word) do
    clean =
      word
      |> String.downcase()
      |> String.replace(~r/[^a-z]/, "")

    cond do
      clean == "" ->
        1

      String.length(clean) <= 3 ->
        1

      true ->
        # Remove silent 'e' at the end (unless ending in 'le' after consonant)
        without_silent_e =
          if String.ends_with?(clean, "e") and not String.ends_with?(clean, ["le", "ee"]) do
            String.slice(clean, 0, String.length(clean) - 1)
          else
            clean
          end

        # Count vowel groups (aeiouy)
        matches = Regex.scan(~r/[aeiouy]+/, without_silent_e)
        count = length(matches)
        max(count, 1)
    end
  end

  @doc """
  Calculates readability metrics for an NL-MetaAST node (sentence, paragraph, or document).
  """
  @spec metrics(AST.nl_node()) :: map()
  def metrics(node) do
    words = AST.words(node)
    sentences = AST.sentences(node)

    word_count = max(length(words), 1)
    sentence_count = max(length(sentences), 1)

    syllable_counts = Enum.map(words, &count_syllables/1)
    total_syllables = Enum.sum(syllable_counts)
    complex_words = Enum.count(syllable_counts, &(&1 >= 3))

    avg_sentence_len = word_count / sentence_count
    avg_syllables_per_word = total_syllables / word_count

    # Flesch Reading Ease (higher = easier to read; 60-70 is standard)
    flesch_ease =
      206.835 - 1.015 * avg_sentence_len - 84.6 * avg_syllables_per_word

    # Flesch-Kincaid Grade Level (corresponds to US school grade level)
    grade_level =
      0.39 * avg_sentence_len + 11.8 * avg_syllables_per_word - 15.59

    %{
      words_count: word_count,
      sentences_count: sentence_count,
      syllables_count: total_syllables,
      complex_words_count: complex_words,
      avg_sentence_length: Float.round(avg_sentence_len, 2),
      avg_syllables_per_word: Float.round(avg_syllables_per_word, 2),
      flesch_reading_ease: Float.round(flesch_ease, 2),
      flesch_kincaid_grade: Float.round(grade_level, 2)
    }
  end
end
