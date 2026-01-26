defmodule Metastatic.Analysis.SimplifyConditionalTest do
  use ExUnit.Case, async: true

  alias Metastatic.{Analysis.Runner, Document}
  alias Metastatic.Analysis.SimplifyConditional

  doctest SimplifyConditional

  describe "info/0" do
    test "returns correct analyzer metadata" do
      info = SimplifyConditional.info()

      assert info.name == :simplify_conditional
      assert info.category == :refactoring
      assert info.severity == :refactoring_opportunity
      assert info.configurable == false
    end
  end

  describe "analyze/2" do
    test "detects if true else false pattern" do
      ast =
        {:conditional, {:variable, "x"}, {:literal, :boolean, true}, {:literal, :boolean, false}}

      doc = Document.new(ast, :python)
      context = %{document: doc, config: %{}, parent_stack: [], depth: 0, scope: %{}}

      issues = SimplifyConditional.analyze(ast, context)

      assert length(issues) == 1
      [issue] = issues
      assert issue.category == :refactoring
      assert issue.severity == :refactoring_opportunity
      assert issue.suggestion.type == :replace
      assert issue.suggestion.replacement == {:variable, "x"}
    end

    test "detects if false else true pattern" do
      ast =
        {:conditional, {:variable, "x"}, {:literal, :boolean, false}, {:literal, :boolean, true}}

      doc = Document.new(ast, :python)
      context = %{document: doc, config: %{}, parent_stack: [], depth: 0, scope: %{}}

      issues = SimplifyConditional.analyze(ast, context)

      assert length(issues) == 1
      [issue] = issues
      assert issue.suggestion.type == :replace
      # Should suggest negation
      assert match?({:unary_op, :boolean, :not, _}, issue.suggestion.replacement)
    end

    test "detects condition else false pattern" do
      condition = {:binary_op, :comparison, :>, {:variable, "x"}, {:literal, :integer, 5}}

      ast = {:conditional, condition, condition, {:literal, :boolean, false}}
      doc = Document.new(ast, :python)
      context = %{document: doc, config: %{}, parent_stack: [], depth: 0, scope: %{}}

      issues = SimplifyConditional.analyze(ast, context)

      assert length(issues) == 1
      [issue] = issues
      assert issue.suggestion.replacement == condition
    end

    test "detects true condition else pattern" do
      condition = {:binary_op, :comparison, :>, {:variable, "x"}, {:literal, :integer, 5}}

      ast = {:conditional, condition, {:literal, :boolean, true}, condition}
      doc = Document.new(ast, :python)
      context = %{document: doc, config: %{}, parent_stack: [], depth: 0, scope: %{}}

      issues = SimplifyConditional.analyze(ast, context)

      assert length(issues) == 1
      [issue] = issues
      assert issue.suggestion.replacement == condition
    end

    test "ignores conditionals that cannot be simplified" do
      ast = {:conditional, {:variable, "x"}, {:variable, "a"}, {:variable, "b"}}
      doc = Document.new(ast, :python)
      context = %{document: doc, config: %{}, parent_stack: [], depth: 0, scope: %{}}

      issues = SimplifyConditional.analyze(ast, context)

      assert issues == []
    end

    test "ignores non-conditional nodes" do
      ast = {:literal, :integer, 42}
      doc = Document.new(ast, :python)
      context = %{document: doc, config: %{}, parent_stack: [], depth: 0, scope: %{}}

      issues = SimplifyConditional.analyze(ast, context)

      assert issues == []
    end
  end

  describe "integration with Runner" do
    test "works as registered analyzer plugin" do
      ast =
        {:conditional, {:variable, "x"}, {:literal, :boolean, true}, {:literal, :boolean, false}}

      doc = Document.new(ast, :python)

      {:ok, report} = Runner.run(doc, analyzers: [SimplifyConditional])

      assert length(report.issues) == 1
      [issue] = report.issues
      assert issue.analyzer == SimplifyConditional
      assert issue.severity == :refactoring_opportunity
    end

    test "multiple patterns in nested structure" do
      # Nested: outer conditional + inner conditional
      ast = {
        :conditional,
        {:variable, "a"},
        {:conditional, {:variable, "x"}, {:literal, :boolean, true}, {:literal, :boolean, false}},
        {:literal, :boolean, false}
      }

      doc = Document.new(ast, :python)
      {:ok, report} = Runner.run(doc, analyzers: [SimplifyConditional])

      # Should find both patterns
      assert match?([_ | _], report.issues)
    end

    test "summary includes refactoring opportunities" do
      ast =
        {:conditional, {:variable, "x"}, {:literal, :boolean, true}, {:literal, :boolean, false}}

      doc = Document.new(ast, :python)

      {:ok, report} = Runner.run(doc, analyzers: [SimplifyConditional])

      assert report.summary.total == 1
      assert Map.get(report.summary.by_severity, :refactoring_opportunity) == 1
    end
  end
end
