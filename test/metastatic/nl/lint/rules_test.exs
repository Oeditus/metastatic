defmodule Metastatic.NL.Lint.RulesTest do
  use ExUnit.Case, async: true
  alias Metastatic.NL.Lint.Runner
  alias Metastatic.NL.Lint.Rules.{
    AvoidPassiveVoice,
    AvoidWeaselWords,
    SentenceLength,
    TerminologyConsistency
  }

  describe "AvoidPassiveVoice" do
    test "flags passive voice and suggests active rewrite" do
      text = "The database migration was executed by the operator."
      assert {:ok, issues} = Runner.lint_source(text, rules: [AvoidPassiveVoice])

      assert length(issues) == 1
      [issue] = issues
      assert issue.rule == :avoid_passive_voice
      assert issue.severity == :refactor
      assert issue.suggestion =~ "operator"
    end

    test "passes clean active voice" do
      text = "The operator executed the database migration."
      assert {:ok, []} = Runner.lint_source(text, rules: [AvoidPassiveVoice])
    end
  end

  describe "AvoidWeaselWords" do
    test "flags weasel words and hedging" do
      text = "Clearly, this optimization will probably improve latency."
      assert {:ok, issues} = Runner.lint_source(text, rules: [AvoidWeaselWords])

      assert length(issues) >= 2
      rules_flagged = Enum.map(issues, & &1.rule)
      assert Enum.all?(rules_flagged, &(&1 == :avoid_weasel_words))
    end
  end

  describe "SentenceLength" do
    test "flags sentences exceeding word threshold" do
      long_text =
        "This is an excessively long and verbose sentence that goes on and on without stopping, describing many multiple concepts simultaneously while dragging on and on, far beyond any reasonable readability limit."

      assert {:ok, issues} = Runner.lint_source(long_text, rules: [SentenceLength], max_words: 15)
      assert length(issues) == 1
      [issue] = issues
      assert issue.rule == :sentence_length
      assert issue.message =~ "exceeding maximum threshold of 15"
    end
  end

  describe "TerminologyConsistency" do
    test "flags deprecated terms" do
      text = "Add the IP address to the whitelist."
      assert {:ok, issues} = Runner.lint_source(text, rules: [TerminologyConsistency])

      assert length(issues) == 1
      [issue] = issues
      assert issue.rule == :terminology_consistency
      assert issue.suggestion =~ "allowlist"
    end
  end
end
