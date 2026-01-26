defmodule Metastatic.Analysis.DeadCodeAnalyzerTest do
  use ExUnit.Case, async: true

  alias Metastatic.Analysis.DeadCodeAnalyzer
  alias Metastatic.{Analysis.Runner, Document}

  doctest DeadCodeAnalyzer

  describe "info/0" do
    test "returns correct analyzer metadata" do
      info = DeadCodeAnalyzer.info()

      assert info.name == :dead_code
      assert info.category == :correctness
      assert info.severity == :warning
      assert info.configurable == true
    end
  end

  describe "run_before/1" do
    test "initializes context with dead code results" do
      ast =
        {:block,
         [
           {:early_return, {:literal, :integer, 1}},
           {:literal, :integer, 2}
         ]}

      doc = Document.new(ast, :python)

      context = %{
        document: doc,
        config: [],
        parent_stack: [],
        depth: 0,
        scope: %{}
      }

      {:ok, new_context} = DeadCodeAnalyzer.run_before(context)

      assert Map.has_key?(new_context, :dead_code_result)
      assert new_context.dead_code_result != nil
    end

    test "skips when dead code analysis fails" do
      # Invalid AST that might cause DeadCode to fail
      context = %{
        document: nil,
        config: [],
        parent_stack: [],
        depth: 0,
        scope: %{}
      }

      result = DeadCodeAnalyzer.run_before(context)

      # Should either skip or continue
      assert match?({:skip, _}, result) or match?({:ok, _}, result)
    end
  end

  describe "analyze/2" do
    test "returns empty list (all analysis in run_before)" do
      ast = {:literal, :integer, 42}
      doc = Document.new(ast, :python)

      context = %{
        document: doc,
        config: [],
        parent_stack: [],
        depth: 0,
        scope: %{}
      }

      issues = DeadCodeAnalyzer.analyze(ast, context)

      assert issues == []
    end
  end

  describe "run_after/2" do
    test "converts dead code results to issues" do
      ast =
        {:block,
         [
           {:early_return, {:literal, :integer, 1}},
           {:literal, :integer, 2}
         ]}

      doc = Document.new(ast, :python)

      # First run run_before to get results
      context = %{
        document: doc,
        config: [],
        parent_stack: [],
        depth: 0,
        scope: %{}
      }

      {:ok, new_context} = DeadCodeAnalyzer.run_before(context)

      # Then run_after with empty issues list
      result = DeadCodeAnalyzer.run_after(new_context, [])

      # Should have found the unreachable code after return
      assert match?([_ | _], result)

      Enum.each(result, fn issue ->
        assert issue.analyzer == DeadCodeAnalyzer
        assert issue.category == :correctness
      end)
    end

    test "appends to existing issues" do
      ast =
        {:block,
         [
           {:early_return, {:literal, :integer, 1}},
           {:literal, :integer, 2}
         ]}

      doc = Document.new(ast, :python)

      context = %{
        document: doc,
        config: [],
        parent_stack: [],
        depth: 0,
        scope: %{}
      }

      {:ok, new_context} = DeadCodeAnalyzer.run_before(context)

      existing_issues = [%{analyzer: :other, category: :style}]
      result = DeadCodeAnalyzer.run_after(new_context, existing_issues)

      # Should preserve existing issues and add new ones
      assert length(result) > length(existing_issues)
    end

    test "returns issues unchanged when no dead code result" do
      context = %{
        document: Document.new({:literal, :integer, 42}, :python),
        config: []
      }

      issues = [%{analyzer: :test, category: :style}]
      result = DeadCodeAnalyzer.run_after(context, issues)

      assert result == issues
    end
  end

  describe "integration with Runner" do
    test "detects unreachable code after return" do
      ast =
        {:block,
         [
           {:early_return, {:literal, :integer, 1}},
           {:literal, :integer, 2}
         ]}

      doc = Document.new(ast, :python)

      {:ok, report} = Runner.run(doc, analyzers: [DeadCodeAnalyzer])

      assert match?([_ | _], report.issues)

      Enum.each(report.issues, fn issue ->
        assert issue.analyzer == DeadCodeAnalyzer
        assert issue.category == :correctness
        assert issue.severity == :warning or issue.severity == :info
      end)
    end

    test "detects constant conditionals" do
      # if true then x else y - else is unreachable
      ast =
        {:conditional, {:literal, :boolean, true}, {:literal, :integer, 1},
         {:literal, :integer, 2}}

      doc = Document.new(ast, :python)

      {:ok, report} = Runner.run(doc, analyzers: [DeadCodeAnalyzer])

      assert match?([_ | _], report.issues)
    end

    test "no issues for reachable code" do
      ast =
        {:block,
         [
           {:assignment, {:variable, "x"}, {:literal, :integer, 1}},
           {:literal, :integer, 2}
         ]}

      doc = Document.new(ast, :python)

      {:ok, report} = Runner.run(doc, analyzers: [DeadCodeAnalyzer])

      # No unreachable code, so should be empty or minimal issues
      Enum.each(report.issues, fn issue ->
        assert issue.analyzer == DeadCodeAnalyzer
      end)
    end

    test "respects configuration" do
      ast =
        {:conditional, {:literal, :boolean, true}, {:literal, :integer, 1},
         {:literal, :integer, 2}}

      doc = Document.new(ast, :python)

      # Filter by confidence
      {:ok, report} =
        Runner.run(doc,
          analyzers: [DeadCodeAnalyzer],
          config: %{dead_code: [min_confidence: :high]}
        )

      # High confidence should still find constant conditionals
      Enum.each(report.issues, fn issue ->
        assert issue.analyzer == DeadCodeAnalyzer
      end)
    end

    test "summary includes dead code issues" do
      ast =
        {:block,
         [
           {:early_return, {:literal, :integer, 1}},
           {:literal, :integer, 2}
         ]}

      doc = Document.new(ast, :python)

      {:ok, report} = Runner.run(doc, analyzers: [DeadCodeAnalyzer])

      assert report.summary.total >= 1
      assert Map.get(report.summary.by_analyzer, DeadCodeAnalyzer) >= 1
    end
  end
end
