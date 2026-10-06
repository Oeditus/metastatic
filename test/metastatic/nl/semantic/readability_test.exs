defmodule Metastatic.NL.Semantic.ReadabilityTest do
  use ExUnit.Case, async: true
  alias Metastatic.NL.Semantic.Readability
  alias Metastatic.NL.Adapters.English

  describe "syllable counting" do
    test "correctly estimates syllables for common words" do
      assert Readability.count_syllables("the") == 1
      assert Readability.count_syllables("system") == 2
      assert Readability.count_syllables("complex") == 2
      assert Readability.count_syllables("architecture") == 4
      assert Readability.count_syllables("implementation") == 5
    end
  end

  describe "readability metrics" do
    test "calculates Flesch scores on English prose" do
      text = "The system runs fast. It processes requests easily."
      {:ok, cst} = English.parse(text)
      {:ok, doc, _} = English.to_meta(cst)

      metrics = Readability.metrics(doc)
      assert metrics.words_count == 8
      assert metrics.sentences_count == 2
      assert is_float(metrics.flesch_reading_ease)
      assert is_float(metrics.flesch_kincaid_grade)
    end
  end
end
