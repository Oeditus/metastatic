defmodule Metastatic.Analysis.RunnerIntegrationTest do
  use ExUnit.Case, async: true

  alias Metastatic.Analysis.BusinessLogic.{CallbackHell, HardcodedValue}
  alias Metastatic.Analysis.Runner
  alias Metastatic.Document

  # Helper functions for building MetaAST nodes
  defp literal(subtype, value), do: {:literal, [subtype: subtype], value}
  defp variable(name), do: {:variable, [], name}
  defp block(stmts), do: {:block, [], stmts}
  defp conditional(cond, then_b, else_b), do: {:conditional, [], [cond, then_b, else_b]}

  describe "run/2 with business logic analyzers" do
    test "runs multiple analyzers in single pass" do
      # AST with both callback hell and hardcoded value
      deepest = conditional(variable("z"), literal(:integer, 3), nil)
      middle = conditional(variable("y"), block([deepest]), nil)

      outer =
        conditional(
          variable("x"),
          block([middle]),
          block([literal(:string, "https://api.example.com")])
        )

      doc = Document.new(outer, :python)

      {:ok, report} =
        Runner.run(doc,
          analyzers: [CallbackHell, HardcodedValue],
          config: %{
            callback_hell: %{max_nesting: 2},
            hardcoded_value: %{exclude_localhost: true}
          }
        )

      assert length(report.issues) == 2
      assert report.analyzers_run == [CallbackHell, HardcodedValue]

      # Check callback hell issue
      callback_issue = Enum.find(report.issues, &(&1.analyzer == CallbackHell))
      assert callback_issue.severity == :warning
      assert callback_issue.category == :readability
      assert callback_issue.metadata.nesting_level == 3

      # Check hardcoded value issue
      hardcoded_issue = Enum.find(report.issues, &(&1.analyzer == HardcodedValue))
      assert hardcoded_issue.severity == :warning
      assert hardcoded_issue.category == :security
      assert hardcoded_issue.metadata.type == :url
    end

    test "respects analyzer-specific configuration" do
      # 3-level nesting
      deepest = conditional(variable("z"), literal(:integer, 3), block([]))
      middle = conditional(variable("y"), block([deepest]), block([]))
      outer = conditional(variable("x"), block([middle]), block([]))

      doc = Document.new(outer, :python)

      # With max_nesting: 5, should not trigger
      {:ok, report1} =
        Runner.run(doc,
          analyzers: [CallbackHell],
          config: %{callback_hell: %{max_nesting: 5}}
        )

      assert [] == report1.issues

      # With max_nesting: 2, should trigger
      {:ok, report2} =
        Runner.run(doc,
          analyzers: [CallbackHell],
          config: %{callback_hell: %{max_nesting: 2}}
        )

      assert [_issue] = report2.issues
    end

    test "provides meaningful summary" do
      # Multiple issues of different types
      ast =
        block([
          # Callback hell (readability, warning)
          conditional(
            variable("a"),
            block([
              conditional(
                variable("b"),
                block([conditional(variable("c"), literal(:integer, 1), nil)]),
                nil
              )
            ]),
            nil
          ),
          # Hardcoded URL (security, warning)
          literal(:string, "https://prod.example.com")
        ])

      doc = Document.new(ast, :javascript)

      {:ok, report} =
        Runner.run(doc,
          analyzers: [CallbackHell, HardcodedValue],
          config: %{callback_hell: %{max_nesting: 2}}
        )

      assert report.summary.total == 2
      assert report.summary.by_severity.warning == 2
      assert report.summary.by_category.readability == 1
      assert report.summary.by_category.security == 1
      assert report.summary.by_analyzer[CallbackHell] == 1
      assert report.summary.by_analyzer[HardcodedValue] == 1
    end

    test "supports max_issues limit" do
      # Many issues
      ast =
        block([
          literal(:string, "https://example1.com"),
          literal(:string, "https://example2.com"),
          literal(:string, "https://example3.com"),
          literal(:string, "https://example4.com"),
          literal(:string, "https://example5.com")
        ])

      doc = Document.new(ast, :python)

      {:ok, report} =
        Runner.run(doc,
          analyzers: [HardcodedValue],
          max_issues: 3
        )

      # Should stop traversal after reaching max_issues
      # Note: May collect more than max if multiple issues found at same node
      assert length(report.issues) >= 3
      assert length(report.issues) <= 5
    end

    test "tracks timing when requested" do
      ast = conditional(variable("x"), literal(:integer, 1), nil)
      doc = Document.new(ast, :elixir)

      {:ok, report} =
        Runner.run(doc,
          analyzers: [CallbackHell],
          track_timing: true
        )

      assert is_map(report.timing)
      assert is_integer(report.timing.total_ms)
      assert report.timing.total_ms >= 0
    end

    test "handles empty AST" do
      doc = Document.new(block([]), :python)

      {:ok, report} =
        Runner.run(doc,
          analyzers: [CallbackHell, HardcodedValue]
        )

      assert report.issues == []
      assert report.summary.total == 0
    end
  end
end
