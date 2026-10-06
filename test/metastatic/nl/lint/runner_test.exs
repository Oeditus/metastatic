defmodule Metastatic.NL.Lint.RunnerTest do
  use ExUnit.Case, async: true
  alias Metastatic.NL.Lint.Runner

  describe "Runner.lint_source/2" do
    test "runs full default suite against multi-issue text" do
      prose = """
      The system configuration was changed by an unknown script.
      Clearly, this was done without a sanity check.
      """

      assert {:ok, issues} = Runner.lint_source(prose)
      assert length(issues) >= 2

      rule_names = Enum.map(issues, & &1.rule)
      assert :avoid_passive_voice in rule_names
      assert :avoid_weasel_words in rule_names
    end

    test "returns empty issues for clean, active prose" do
      prose = "The operator restarted the service. The service is running."
      assert {:ok, []} = Runner.lint_source(prose)
    end
  end
end
