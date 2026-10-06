defmodule Metastatic.NL.Semantic.EnricherTest do
  use ExUnit.Case, async: true
  alias Metastatic.NL.Adapters.English
  alias Metastatic.NL.AST

  describe "passive vs active voice detection" do
    test "detects passive voice and assigns semantic roles" do
      text = "The report was written by the committee."
      {:ok, cst} = English.parse(text)
      {:ok, doc, _} = English.to_meta(cst)

      [clause] = AST.clauses(doc)
      assert AST.get_meta(clause, :voice) == :passive

      phrases = AST.phrases(clause)
      # Patient role on the syntactic subject
      subject = Enum.find(phrases, &(AST.get_meta(&1, :role) == :subject))
      assert AST.get_meta(subject, :sem_role) == :patient

      # Agent role on the by-phrase
      by_phrase = Enum.find(phrases, &(AST.get_meta(&1, :type) == :prep_phrase))
      assert AST.get_meta(by_phrase, :sem_role) == :agent
    end

    test "detects active voice" do
      text = "The committee reviewed the code."
      {:ok, cst} = English.parse(text)
      {:ok, doc, _} = English.to_meta(cst)

      [clause] = AST.clauses(doc)
      assert AST.get_meta(clause, :voice) == :active

      phrases = AST.phrases(clause)
      subject = Enum.find(phrases, &(AST.get_meta(&1, :role) == :subject))
      assert AST.get_meta(subject, :sem_role) == :agent

      object = Enum.find(phrases, &(AST.get_meta(&1, :role) == :object))
      assert AST.get_meta(object, :sem_role) == :patient
    end
  end

  describe "hedging and weasel word detection" do
    test "flags weasel words in clauses" do
      text = "Clearly, this might improve performance."
      {:ok, cst} = English.parse(text)
      {:ok, doc, _} = English.to_meta(cst)

      [clause] = AST.clauses(doc)
      assert AST.get_meta(clause, :hedging) == :weasel
    end
  end

  describe "document-level readability" do
    test "attaches readability metadata to document and sentences" do
      text = "This document describes the design. Keep it simple."
      {:ok, cst} = English.parse(text)
      {:ok, doc, _} = English.to_meta(cst)

      assert %{words_count: 8, sentences_count: 2} = AST.get_meta(doc, :readability)

      [first_sent, _] = AST.sentences(doc)
      assert AST.get_meta(first_sent, :words_count) == 5
      assert is_integer(AST.get_meta(first_sent, :syllables_count))
    end
  end
end
