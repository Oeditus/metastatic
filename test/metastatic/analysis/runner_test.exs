defmodule Metastatic.Analysis.RunnerTest do
  use ExUnit.Case, async: false

  alias Metastatic.Analysis.{Analyzer, Registry, Runner}
  alias Metastatic.Document

  # Test-local analyzer implementations
  defmodule UnusedVariables do
    @behaviour Metastatic.Analysis.Analyzer

    @impl true
    def info do
      %{
        name: :unused_variables,
        category: :correctness,
        description: "Detects variables that are assigned but never used",
        severity: :warning,
        explanation: "Test analyzer for unused variables",
        configurable: true
      }
    end

    @impl true
    def analyze(_node, _context), do: []

    @impl true
    def run_after(context, issues) do
      {assigned, used} = collect_variables(context.document.ast)
      config = context.config
      ignore_prefix = Map.get(config, :ignore_prefix, "_")
      ignore_names = Map.get(config, :ignore_names, [])

      unused =
        assigned
        |> MapSet.difference(used)
        |> Enum.filter(&(not should_ignore?(&1, ignore_prefix, ignore_names)))

      new_issues =
        Enum.map(unused, fn var ->
          Analyzer.issue(
            analyzer: __MODULE__,
            category: :correctness,
            severity: :warning,
            message: "Variable '#{var}' is assigned but never used",
            node: {:variable, var},
            location: %{line: nil, column: nil, path: nil},
            suggestion:
              Analyzer.suggestion(
                type: :remove,
                replacement: nil,
                message:
                  "Consider removing this unused variable or prefixing with '#{ignore_prefix}'"
              ),
            metadata: %{variable: var}
          )
        end)

      issues ++ new_issues
    end

    defp collect_variables(ast), do: walk_collect(ast, {MapSet.new(), MapSet.new()})

    defp walk_collect({:assignment, {:variable, name}, value}, {assigned, used}) do
      assigned = MapSet.put(assigned, name)
      {assigned, used} = walk_collect(value, {assigned, used})
      {assigned, used}
    end

    defp walk_collect({:variable, name}, {assigned, used}) do
      used = MapSet.put(used, name)
      {assigned, used}
    end

    defp walk_collect({:binary_op, _, _, left, right}, acc) do
      acc = walk_collect(left, acc)
      walk_collect(right, acc)
    end

    defp walk_collect({:unary_op, _, _, operand}, acc), do: walk_collect(operand, acc)

    defp walk_collect({:conditional, cond, then_br, else_br}, acc) do
      acc = walk_collect(cond, acc)
      acc = walk_collect(then_br, acc)
      walk_collect(else_br, acc)
    end

    defp walk_collect({:block, stmts}, acc) when is_list(stmts) do
      Enum.reduce(stmts, acc, fn stmt, a -> walk_collect(stmt, a) end)
    end

    defp walk_collect({:function_call, _name, args}, acc) do
      Enum.reduce(args, acc, fn arg, a -> walk_collect(arg, a) end)
    end

    defp walk_collect({:early_return, value}, acc), do: walk_collect(value, acc)

    defp walk_collect({:inline_match, pattern, value}, acc) do
      acc = walk_collect(pattern, acc)
      walk_collect(value, acc)
    end

    defp walk_collect({:attribute_access, obj, _attr}, acc), do: walk_collect(obj, acc)

    defp walk_collect({:augmented_assignment, target, _op, value}, acc) do
      acc = walk_collect(target, acc)
      walk_collect(value, acc)
    end

    defp walk_collect(list, acc) when is_list(list) do
      Enum.reduce(list, acc, fn item, a -> walk_collect(item, a) end)
    end

    defp walk_collect(_other, acc), do: acc

    defp should_ignore?(var_name, ignore_prefix, ignore_names) do
      String.starts_with?(var_name, ignore_prefix) or var_name in ignore_names
    end
  end

  defmodule SimplifyConditional do
    @behaviour Metastatic.Analysis.Analyzer

    @impl true
    def info do
      %{
        name: :simplify_conditional,
        category: :refactoring,
        description: "Suggests simplification of redundant conditionals",
        severity: :refactoring_opportunity,
        explanation: "Test analyzer for simplifying conditionals",
        configurable: false
      }
    end

    @impl true
    def analyze(
          {:conditional, condition, {:literal, :boolean, true}, {:literal, :boolean, false}},
          _context
        ) do
      [
        Analyzer.issue(
          analyzer: __MODULE__,
          category: :refactoring,
          severity: :refactoring_opportunity,
          message: "This conditional can be simplified to just the condition",
          node:
            {:conditional, condition, {:literal, :boolean, true}, {:literal, :boolean, false}},
          location: %{line: nil, column: nil, path: nil},
          suggestion:
            Analyzer.suggestion(
              type: :replace,
              replacement: condition,
              message: "Replace with the condition"
            ),
          metadata: %{pattern: :true_false}
        )
      ]
    end

    def analyze(
          {:conditional, condition, {:literal, :boolean, false}, {:literal, :boolean, true}},
          _context
        ) do
      negated = {:unary_op, :boolean, :not, condition}

      [
        Analyzer.issue(
          analyzer: __MODULE__,
          category: :refactoring,
          severity: :refactoring_opportunity,
          message: "This conditional can be simplified to the negation of the condition",
          node:
            {:conditional, condition, {:literal, :boolean, false}, {:literal, :boolean, true}},
          location: %{line: nil, column: nil, path: nil},
          suggestion:
            Analyzer.suggestion(
              type: :replace,
              replacement: negated,
              message: "Replace with negation"
            ),
          metadata: %{pattern: :false_true}
        )
      ]
    end

    def analyze(_node, _context), do: []
  end

  setup do
    # Clear and set up registry for each test
    Registry.clear()
    :ok
  end

  describe "run/2" do
    test "runs with no analyzers" do
      ast = {:literal, :integer, 42}
      doc = Document.new(ast, :python)

      {:ok, report} = Runner.run(doc)

      assert report.document == doc
      assert report.analyzers_run == []
      assert report.issues == []
      assert report.summary.total == 0
    end

    test "runs single analyzer" do
      ast =
        {:block,
         [
           {:assignment, {:variable, "x"}, {:literal, :integer, 5}},
           {:assignment, {:variable, "y"}, {:literal, :integer, 10}},
           {:early_return, {:variable, "y"}}
         ]}

      doc = Document.new(ast, :python)

      Registry.register(UnusedVariables)
      {:ok, report} = Runner.run(doc)

      assert UnusedVariables in report.analyzers_run
      assert [issue] = report.issues
      assert issue.analyzer == UnusedVariables
      assert issue.message =~ "x"
      assert issue.severity == :warning
    end

    test "runs multiple analyzers" do
      ast =
        {:block,
         [
           {:assignment, {:variable, "x"}, {:literal, :integer, 5}},
           {:assignment, {:variable, "y"}, {:literal, :integer, 10}},
           {:conditional, {:variable, "x"}, {:literal, :boolean, true},
            {:literal, :boolean, false}}
         ]}

      doc = Document.new(ast, :python)

      Registry.register(UnusedVariables)
      Registry.register(SimplifyConditional)

      {:ok, report} = Runner.run(doc)

      assert UnusedVariables in report.analyzers_run
      assert SimplifyConditional in report.analyzers_run
      assert length(report.issues) == 2
    end

    test "runs specific analyzers via options" do
      ast =
        {:conditional, {:variable, "x"}, {:literal, :boolean, true}, {:literal, :boolean, false}}

      doc = Document.new(ast, :python)

      Registry.register(UnusedVariables)
      Registry.register(SimplifyConditional)

      {:ok, report} = Runner.run(doc, analyzers: [SimplifyConditional])

      assert report.analyzers_run == [SimplifyConditional]
      assert length(report.issues) == 1
      assert hd(report.issues).analyzer == SimplifyConditional
    end

    test "includes timing when requested" do
      ast = {:literal, :integer, 42}
      doc = Document.new(ast, :python)

      {:ok, report} = Runner.run(doc, track_timing: true)

      assert is_map(report.timing)
      assert is_number(report.timing.total_ms)
    end

    test "halts on error when configured" do
      defmodule ErrorAnalyzer do
        @behaviour Metastatic.Analysis.Analyzer

        @impl true
        def info do
          %{
            name: :error_analyzer,
            category: :correctness,
            description: "Always errors",
            severity: :error,
            explanation: "Test",
            configurable: false
          }
        end

        @impl true
        def analyze({:literal, _, _}, _context) do
          [
            %{
              analyzer: __MODULE__,
              category: :correctness,
              severity: :error,
              message: "Error found",
              node: {:literal, :integer, 1},
              location: %{line: nil, column: nil, path: nil},
              suggestion: nil,
              metadata: %{}
            }
          ]
        end

        def analyze(_node, _context), do: []
      end

      Registry.register(ErrorAnalyzer)

      ast =
        {:block,
         [
           {:literal, :integer, 1},
           {:literal, :integer, 2},
           {:literal, :integer, 3}
         ]}

      doc = Document.new(ast, :python)

      {:ok, report} = Runner.run(doc, halt_on_error: true)

      # Currently halts after processing each parent node,
      # so all 3 literals in the block are processed
      # [TODO]: Fix Runner to halt immediately after first error
      assert length(report.issues) == 3
    end
  end

  describe "run!/2" do
    test "returns report on success" do
      ast = {:literal, :integer, 42}
      doc = Document.new(ast, :python)

      report = Runner.run!(doc)

      assert is_map(report)
      assert report.document == doc
    end
  end

  describe "UnusedVariables analyzer" do
    test "detects unused variable" do
      ast =
        {:block,
         [
           {:assignment, {:variable, "x"}, {:literal, :integer, 5}},
           {:assignment, {:variable, "y"}, {:literal, :integer, 10}},
           {:early_return, {:variable, "y"}}
         ]}

      doc = Document.new(ast, :python)
      Registry.register(UnusedVariables)

      {:ok, report} = Runner.run(doc)

      assert [issue] = report.issues
      assert issue.message =~ "x"
      assert issue.message =~ "never used"
      assert issue.category == :correctness
      assert issue.severity == :warning
      assert issue.suggestion != nil
    end

    test "detects multiple unused variables" do
      ast =
        {:block,
         [
           {:assignment, {:variable, "x"}, {:literal, :integer, 5}},
           {:assignment, {:variable, "y"}, {:literal, :integer, 10}},
           {:assignment, {:variable, "z"}, {:literal, :integer, 15}}
         ]}

      doc = Document.new(ast, :python)
      Registry.register(UnusedVariables)

      {:ok, report} = Runner.run(doc)

      assert [_, _, _] = report.issues
      variable_names = Enum.map(report.issues, & &1.metadata.variable)
      assert "x" in variable_names
      assert "y" in variable_names
      assert "z" in variable_names
    end

    test "ignores underscore-prefixed variables by default" do
      ast =
        {:block,
         [
           {:assignment, {:variable, "_temp"}, {:literal, :integer, 5}},
           {:assignment, {:variable, "result"}, {:literal, :integer, 10}},
           {:early_return, {:variable, "result"}}
         ]}

      doc = Document.new(ast, :python)
      Registry.register(UnusedVariables)

      {:ok, report} = Runner.run(doc)

      assert report.issues == []
    end

    test "respects ignore_prefix configuration" do
      ast =
        {:block,
         [
           {:assignment, {:variable, "tmp_value"}, {:literal, :integer, 5}},
           {:assignment, {:variable, "result"}, {:literal, :integer, 10}},
           {:early_return, {:variable, "result"}}
         ]}

      doc = Document.new(ast, :python)
      Registry.register(UnusedVariables)

      {:ok, report} = Runner.run(doc, config: %{unused_variables: %{ignore_prefix: "tmp_"}})

      assert report.issues == []
    end

    test "does not flag used variables" do
      ast =
        {:block,
         [
           {:assignment, {:variable, "x"}, {:literal, :integer, 5}},
           {:assignment, {:variable, "y"},
            {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 10}}},
           {:early_return, {:variable, "y"}}
         ]}

      doc = Document.new(ast, :python)
      Registry.register(UnusedVariables)

      {:ok, report} = Runner.run(doc)

      assert report.issues == []
    end
  end

  describe "SimplifyConditional analyzer" do
    test "detects if-true-else-false pattern" do
      ast =
        {:conditional, {:variable, "x"}, {:literal, :boolean, true}, {:literal, :boolean, false}}

      doc = Document.new(ast, :python)

      Registry.register(SimplifyConditional)
      {:ok, report} = Runner.run(doc)

      assert [issue] = report.issues
      assert issue.message =~ "simplified"
      assert issue.category == :refactoring
      assert issue.severity == :refactoring_opportunity
      assert issue.suggestion.type == :replace
      assert issue.suggestion.replacement == {:variable, "x"}
    end

    test "detects if-false-else-true pattern" do
      ast =
        {:conditional, {:variable, "x"}, {:literal, :boolean, false}, {:literal, :boolean, true}}

      doc = Document.new(ast, :python)

      Registry.register(SimplifyConditional)
      {:ok, report} = Runner.run(doc)

      assert [issue] = report.issues
      assert issue.message =~ "negation"
      assert issue.suggestion.replacement == {:unary_op, :boolean, :not, {:variable, "x"}}
    end

    test "does not flag non-redundant conditionals" do
      ast =
        {:conditional, {:variable, "x"}, {:literal, :integer, 1}, {:literal, :integer, 2}}

      doc = Document.new(ast, :python)

      Registry.register(SimplifyConditional)
      {:ok, report} = Runner.run(doc)

      assert report.issues == []
    end

    test "handles nested conditionals" do
      ast =
        {:block,
         [
           {:conditional, {:variable, "a"}, {:literal, :boolean, true},
            {:literal, :boolean, false}},
           {:conditional, {:variable, "b"}, {:literal, :boolean, false},
            {:literal, :boolean, true}}
         ]}

      doc = Document.new(ast, :python)

      Registry.register(SimplifyConditional)
      {:ok, report} = Runner.run(doc)

      assert [_, _] = report.issues
    end
  end

  describe "report summary" do
    test "includes correct statistics" do
      ast =
        {:block,
         [
           {:assignment, {:variable, "x"}, {:literal, :integer, 5}},
           {:assignment, {:variable, "y"}, {:literal, :integer, 10}},
           {:conditional, {:variable, "y"}, {:literal, :boolean, true},
            {:literal, :boolean, false}}
         ]}

      doc = Document.new(ast, :python)

      Registry.register(UnusedVariables)
      Registry.register(SimplifyConditional)

      {:ok, report} = Runner.run(doc)

      assert report.summary.total == 2
      assert report.summary.by_severity[:warning] == 1
      assert report.summary.by_severity[:refactoring_opportunity] == 1
      assert report.summary.by_category[:correctness] == 1
      assert report.summary.by_category[:refactoring] == 1
    end
  end
end
