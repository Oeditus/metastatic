defmodule Metastatic.NL.Lint.Rules.SentenceLength do
  @moduledoc """
  Flags overly long and convoluted sentences.
  """

  @behaviour Metastatic.NL.Lint.Rule

  alias Metastatic.NL.AST
  alias Metastatic.NL.Lint.Issue

  @default_max_words 25

  @impl true
  def name, do: :sentence_length

  @impl true
  def category, do: :readability

  @impl true
  def explanation do
    "Sentences exceeding 25 words are harder to read and comprehend. Split complex compound ideas into separate sentences."
  end

  @impl true
  def run(ast, opts) do
    max_words = Keyword.get(opts, :max_words, @default_max_words)

    {_, issues} =
      AST.traverse(
        ast,
        [],
        fn
          {:sentence, meta, children} = sent, acc ->
            word_count = Keyword.get(meta, :words_count) || length(AST.words(sent))

            if word_count > max_words do
              line = Keyword.get(meta, :line) || find_line(children)
              col = Keyword.get(meta, :col) || find_col(children)

              issue =
                Issue.new(
                  :sentence_length,
                  "Sentence contains #{word_count} words, exceeding maximum threshold of #{max_words}.",
                  line: line,
                  col: col,
                  severity: :refactor,
                  suggestion: "Split this sentence into shorter, focused sentences."
                )

              {sent, [issue | acc]}
            else
              {sent, acc}
            end

          node, acc ->
            {node, acc}
        end,
        fn node, acc -> {node, acc} end
      )

    Enum.reverse(issues)
  end

  defp find_line(children) do
    Enum.find_value(children, fn
      {:token, meta, _} -> Keyword.get(meta, :line)
      {:phrase, meta, _} -> Keyword.get(meta, :line)
      {:clause, meta, _} -> Keyword.get(meta, :line)
      _ -> nil
    end)
  end

  defp find_col(children) do
    Enum.find_value(children, fn
      {:token, meta, _} -> Keyword.get(meta, :col)
      {:phrase, meta, _} -> Keyword.get(meta, :col)
      {:clause, meta, _} -> Keyword.get(meta, :col)
      _ -> nil
    end)
  end
end
