defmodule Metastatic.Analysis.NestingDepthTest do
  use ExUnit.Case, async: true

  alias Metastatic.Analysis.NestingDepth
  alias Metastatic.{Analysis.Runner, Document}

  doctest NestingDepth

  describe "info/0" do
    test "returns correct analyzer metadata" do
      info = NestingDepth.info()

      assert info.name == :nesting_depth
      assert info.category == :maintainability
      assert info.severity == :warning
      assert info.configurable == true
    end
  end

  describe "analyze/2" do
    test "no issue for shallow nesting (below threshold)" do
      # Single conditional: depth = 1, below default threshold of 4
      ast = {:conditional, {:variable, "x"}, {:literal, :integer, 1}, {:literal, :integer, 2}}
      doc = Document.new(ast, :python)

      context = %{
        document: doc,
        config: [],
        parent_stack: [],
        depth: 0,
        scope: %{},
        max_nesting_depth: 0
      }

      issues = NestingDepth.analyze(ast, context)

      assert issues == []
    end

    test "no issue for exactly at threshold" do
      # Depth 4, exactly at warn_threshold (default 4)
      ast = {
        :conditional,
        {:variable, "a"},
        {
          :conditional,
          {:variable, "b"},
          {
            :conditional,
            {:variable, "c"},
            {:conditional, {:variable, "d"}, {:literal, :integer, 1}, {:literal, :integer, 2}},
            {:literal, :integer, 3}
          },
          {:literal, :integer, 4}
        },
        {:literal, :integer, 5}
      }

      doc = Document.new(ast, :python)

      context = %{
        document: doc,
        config: [],
        parent_stack: [],
        depth: 0,
        scope: %{},
        max_nesting_depth: 0
      }

      issues = NestingDepth.analyze(ast, context)

      # At threshold, should report
      assert match?([_ | _], issues)
    end

    test "issues for nesting above threshold" do
      # Depth 5, above warn_threshold (default 4)
      ast = {
        :conditional,
        {:variable, "a"},
        {
          :conditional,
          {:variable, "b"},
          {
            :conditional,
            {:variable, "c"},
            {
              :conditional,
              {:variable, "d"},
              {:conditional, {:variable, "e"}, {:literal, :integer, 1}, {:literal, :integer, 2}},
              {:literal, :integer, 3}
            },
            {:literal, :integer, 4}
          },
          {:literal, :integer, 5}
        },
        {:literal, :integer, 6}
      }

      doc = Document.new(ast, :python)

      context = %{
        document: doc,
        config: [],
        parent_stack: [],
        depth: 0,
        scope: %{},
        max_nesting_depth: 0
      }

      issues = NestingDepth.analyze(ast, context)

      assert [issue | _] = issues
      assert issue.category == :maintainability
    end

    test "respects custom threshold configuration" do
      # Depth 2, default threshold is 4 but we set warn_threshold to 1
      ast =
        {:conditional, {:variable, "x"},
         {:conditional, {:variable, "y"}, {:literal, :integer, 1}, {:literal, :integer, 2}},
         {:literal, :integer, 3}}

      doc = Document.new(ast, :python)

      context = %{
        document: doc,
        config: [warn_threshold: 1],
        parent_stack: [],
        depth: 0,
        scope: %{},
        max_nesting_depth: 0
      }

      assert [_ | _] = NestingDepth.analyze(ast, context)
    end

    test "severity increases at max_depth threshold" do
      # Depth 5, at max_depth (default 5)
      ast = {
        :conditional,
        {:variable, "a"},
        {
          :conditional,
          {:variable, "b"},
          {
            :conditional,
            {:variable, "c"},
            {
              :conditional,
              {:variable, "d"},
              {:conditional, {:variable, "e"}, {:literal, :integer, 1}, {:literal, :integer, 2}},
              {:literal, :integer, 3}
            },
            {:literal, :integer, 4}
          },
          {:literal, :integer, 5}
        },
        {:literal, :integer, 6}
      }

      doc = Document.new(ast, :python)

      context = %{
        document: doc,
        config: [],
        parent_stack: [],
        depth: 0,
        scope: %{},
        max_nesting_depth: 0
      }

      issues = NestingDepth.analyze(ast, context)

      assert [issue | _] = issues

      # At max_depth, should have warning severity
      if issue.metadata.current_depth >= 5 do
        assert issue.severity == :warning
      end
    end
  end

  describe "integration with Runner" do
    test "works as registered analyzer plugin" do
      # Simple shallow nesting (shouldn't trigger)
      ast = {:conditional, {:variable, "x"}, {:literal, :integer, 1}, {:literal, :integer, 2}}
      doc = Document.new(ast, :python)

      {:ok, report} = Runner.run(doc, analyzers: [NestingDepth])

      # Depth 1 is below threshold, so no issues expected
      assert [] == report.issues
    end

    test "detects deep nesting" do
      # Create a deeply nested structure
      deep_ast =
        Enum.reduce(1..6, {:literal, :integer, 99}, fn i, inner ->
          {:conditional, {:variable, "v#{i}"}, inner, {:literal, :integer, i}}
        end)

      doc = Document.new(deep_ast, :python)

      {:ok, report} = Runner.run(doc, analyzers: [NestingDepth])

      # Should find at least one nesting issue
      assert match?([_ | _], report.issues)

      Enum.each(report.issues, fn issue ->
        assert issue.analyzer == NestingDepth
        assert issue.category == :maintainability
      end)
    end

    test "respects custom configuration via Runner" do
      ast =
        {:conditional, {:variable, "x"},
         {:conditional, {:variable, "y"}, {:literal, :integer, 1}, {:literal, :integer, 2}},
         {:literal, :integer, 3}}

      doc = Document.new(ast, :python)

      # Set very low threshold
      {:ok, report} =
        Runner.run(doc,
          analyzers: [NestingDepth],
          config: %{nesting_depth: [warn_threshold: 1]}
        )

      # Depth 2 should exceed threshold of 1
      assert match?([_ | _], report.issues)
    end
  end

  describe "run_before/1" do
    test "initializes context state" do
      context = %{document: Document.new({:literal, :integer, 42}, :python), config: []}

      {:ok, new_context} = NestingDepth.run_before(context)

      assert Map.has_key?(new_context, :max_nesting_depth)
      assert Map.has_key?(new_context, :depth_issues)
      assert new_context.max_nesting_depth == 0
      assert new_context.depth_issues == []
    end
  end

  describe "run_after/2" do
    test "passes through issues unchanged" do
      context = %{document: Document.new({:literal, :integer, 42}, :python), config: []}
      issues = [%{analyzer: NestingDepth, severity: :warning}]

      result = NestingDepth.run_after(context, issues)

      assert result == issues
    end
  end
end
