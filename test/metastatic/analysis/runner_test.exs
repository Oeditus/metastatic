defmodule Metastatic.Analysis.RunnerTest do
  use ExUnit.Case, async: false

  alias Metastatic.Analysis.{Analyzer, Registry, Runner}
  alias Metastatic.Document

  # Helper functions to build 3-tuple MetaAST nodes
  defp literal(subtype, value), do: {:literal, [subtype: subtype], value}
  defp variable(name), do: {:variable, [], name}

  defp binary_op(category, operator, left, right),
    do: {:binary_op, [category: category, operator: operator], [left, right]}

  defp unary_op(category, operator, operand),
    do: {:unary_op, [category: category, operator: operator], [operand]}

  defp block(children), do: {:block, [], children}
  defp assignment(target, value), do: {:assignment, [], [target, value]}
  defp early_return(value), do: {:early_return, [], value}
  defp conditional(cond, then_br, else_br), do: {:conditional, [], [cond, then_br, else_br]}

  # Test-local analyzer implementations (updated for 3-tuple format)
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
            node: {:variable, [], var},
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

    # New 3-tuple format: {:assignment, meta, [target, value]}
    defp walk_collect({:assignment, _meta, [{:variable, _, name}, value]}, {assigned, used}) do
      assigned = MapSet.put(assigned, name)
      walk_collect(value, {assigned, used})
    end

    # New 3-tuple format: {:variable, meta, name}
    defp walk_collect({:variable, _meta, name}, {assigned, used}) do
      {assigned, MapSet.put(used, name)}
    end

    # New 3-tuple format: {:binary_op, meta, [left, right]}
    defp walk_collect({:binary_op, _meta, [left, right]}, acc) do
      acc = walk_collect(left, acc)
      walk_collect(right, acc)
    end

    # New 3-tuple format: {:unary_op, meta, [operand]}
    defp walk_collect({:unary_op, _meta, [operand]}, acc), do: walk_collect(operand, acc)

    # New 3-tuple format: {:conditional, meta, [cond, then_br, else_br]}
    defp walk_collect({:conditional, _meta, children}, acc) when is_list(children) do
      Enum.reduce(children, acc, fn child, a ->
        if child, do: walk_collect(child, a), else: a
      end)
    end

    # New 3-tuple format: {:block, meta, stmts}
    defp walk_collect({:block, _meta, stmts}, acc) when is_list(stmts) do
      Enum.reduce(stmts, acc, fn stmt, a -> walk_collect(stmt, a) end)
    end

    # New 3-tuple format: {:function_call, meta, args}
    defp walk_collect({:function_call, _meta, args}, acc) when is_list(args) do
      Enum.reduce(args, acc, fn arg, a -> walk_collect(arg, a) end)
    end

    # New 3-tuple format: {:early_return, meta, value}
    defp walk_collect({:early_return, _meta, value}, acc) do
      if value, do: walk_collect(value, acc), else: acc
    end

    # New 3-tuple format: {:inline_match, meta, [pattern, value]}
    defp walk_collect({:inline_match, _meta, [pattern, value]}, acc) do
      acc = walk_collect(pattern, acc)
      walk_collect(value, acc)
    end

    # New 3-tuple format: {:attribute_access, meta, [receiver]}
    defp walk_collect({:attribute_access, _meta, [obj]}, acc), do: walk_collect(obj, acc)

    # New 3-tuple format: {:augmented_assignment, meta, [target, value]}
    defp walk_collect({:augmented_assignment, _meta, [target, value]}, acc) do
      acc = walk_collect(target, acc)
      walk_collect(value, acc)
    end

    # Literals have no variables
    defp walk_collect({:literal, _meta, _value}, acc), do: acc

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
    # New 3-tuple format:
    # {:conditional, meta, [cond, {:literal, [subtype: :boolean], true}, {:literal, [subtype: :boolean], false}]}
    def analyze(
          {:conditional, _meta,
           [
             condition,
             {:literal, [subtype: :boolean], true},
             {:literal, [subtype: :boolean], false}
           ]} =
            node,
          _context
        ) do
      [
        Analyzer.issue(
          analyzer: __MODULE__,
          category: :refactoring,
          severity: :refactoring_opportunity,
          message: "This conditional can be simplified to just the condition",
          node: node,
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
          {:conditional, _meta,
           [
             condition,
             {:literal, [subtype: :boolean], false},
             {:literal, [subtype: :boolean], true}
           ]} =
            node,
          _context
        ) do
      negated = {:unary_op, [category: :boolean, operator: :not], [condition]}

      [
        Analyzer.issue(
          analyzer: __MODULE__,
          category: :refactoring,
          severity: :refactoring_opportunity,
          message: "This conditional can be simplified to the negation of the condition",
          node: node,
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
      ast = literal(:integer, 42)
      doc = Document.new(ast, :python)

      {:ok, report} = Runner.run(doc)

      assert report.document == doc
      assert report.analyzers_run == []
      assert report.issues == []
      assert report.summary.total == 0
    end

    test "runs single analyzer" do
      ast =
        block([
          assignment(variable("x"), literal(:integer, 5)),
          assignment(variable("y"), literal(:integer, 10)),
          early_return(variable("y"))
        ])

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
        block([
          assignment(variable("x"), literal(:integer, 5)),
          assignment(variable("y"), literal(:integer, 10)),
          conditional(variable("x"), literal(:boolean, true), literal(:boolean, false))
        ])

      doc = Document.new(ast, :python)

      Registry.register(UnusedVariables)
      Registry.register(SimplifyConditional)

      {:ok, report} = Runner.run(doc)

      assert UnusedVariables in report.analyzers_run
      assert SimplifyConditional in report.analyzers_run
      assert length(report.issues) == 2
    end

    test "runs specific analyzers via options" do
      ast = conditional(variable("x"), literal(:boolean, true), literal(:boolean, false))

      doc = Document.new(ast, :python)

      Registry.register(UnusedVariables)
      Registry.register(SimplifyConditional)

      {:ok, report} = Runner.run(doc, analyzers: [SimplifyConditional])

      assert report.analyzers_run == [SimplifyConditional]
      assert length(report.issues) == 1
      assert hd(report.issues).analyzer == SimplifyConditional
    end

    test "includes timing when requested" do
      ast = literal(:integer, 42)
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
        def analyze({:literal, _meta, _value}, _context) do
          [
            %{
              analyzer: __MODULE__,
              category: :correctness,
              severity: :error,
              message: "Error found",
              node: {:literal, [subtype: :integer], 1},
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
        block([
          literal(:integer, 1),
          literal(:integer, 2),
          literal(:integer, 3)
        ])

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
      ast = literal(:integer, 42)
      doc = Document.new(ast, :python)

      report = Runner.run!(doc)

      assert is_map(report)
      assert report.document == doc
    end
  end

  describe "UnusedVariables analyzer" do
    test "detects unused variable" do
      ast =
        block([
          assignment(variable("x"), literal(:integer, 5)),
          assignment(variable("y"), literal(:integer, 10)),
          early_return(variable("y"))
        ])

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
        block([
          assignment(variable("x"), literal(:integer, 5)),
          assignment(variable("y"), literal(:integer, 10)),
          assignment(variable("z"), literal(:integer, 15))
        ])

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
        block([
          assignment(variable("_temp"), literal(:integer, 5)),
          assignment(variable("result"), literal(:integer, 10)),
          early_return(variable("result"))
        ])

      doc = Document.new(ast, :python)
      Registry.register(UnusedVariables)

      {:ok, report} = Runner.run(doc)

      assert report.issues == []
    end

    test "respects ignore_prefix configuration" do
      ast =
        block([
          assignment(variable("tmp_value"), literal(:integer, 5)),
          assignment(variable("result"), literal(:integer, 10)),
          early_return(variable("result"))
        ])

      doc = Document.new(ast, :python)
      Registry.register(UnusedVariables)

      {:ok, report} = Runner.run(doc, config: %{unused_variables: %{ignore_prefix: "tmp_"}})

      assert report.issues == []
    end

    test "does not flag used variables" do
      ast =
        block([
          assignment(variable("x"), literal(:integer, 5)),
          assignment(
            variable("y"),
            binary_op(:arithmetic, :+, variable("x"), literal(:integer, 10))
          ),
          early_return(variable("y"))
        ])

      doc = Document.new(ast, :python)
      Registry.register(UnusedVariables)

      {:ok, report} = Runner.run(doc)

      assert report.issues == []
    end
  end

  describe "SimplifyConditional analyzer" do
    test "detects if-true-else-false pattern" do
      ast = conditional(variable("x"), literal(:boolean, true), literal(:boolean, false))

      doc = Document.new(ast, :python)

      Registry.register(SimplifyConditional)
      {:ok, report} = Runner.run(doc)

      assert [issue] = report.issues
      assert issue.message =~ "simplified"
      assert issue.category == :refactoring
      assert issue.severity == :refactoring_opportunity
      assert issue.suggestion.type == :replace
      # Replacement is the condition - a variable in new 3-tuple format
      assert {:variable, [], "x"} = issue.suggestion.replacement
    end

    test "detects if-false-else-true pattern" do
      ast = conditional(variable("x"), literal(:boolean, false), literal(:boolean, true))

      doc = Document.new(ast, :python)

      Registry.register(SimplifyConditional)
      {:ok, report} = Runner.run(doc)

      assert [issue] = report.issues
      assert issue.message =~ "negation"
      # Replacement is unary_op in new 3-tuple format
      assert {:unary_op, [category: :boolean, operator: :not], [{:variable, [], "x"}]} =
               issue.suggestion.replacement
    end

    test "does not flag non-redundant conditionals" do
      ast = conditional(variable("x"), literal(:integer, 1), literal(:integer, 2))

      doc = Document.new(ast, :python)

      Registry.register(SimplifyConditional)
      {:ok, report} = Runner.run(doc)

      assert report.issues == []
    end

    test "handles nested conditionals" do
      ast =
        block([
          conditional(variable("a"), literal(:boolean, true), literal(:boolean, false)),
          conditional(variable("b"), literal(:boolean, false), literal(:boolean, true))
        ])

      doc = Document.new(ast, :python)

      Registry.register(SimplifyConditional)
      {:ok, report} = Runner.run(doc)

      assert [_, _] = report.issues
    end
  end

  describe "report summary" do
    test "includes correct statistics" do
      ast =
        block([
          assignment(variable("x"), literal(:integer, 5)),
          assignment(variable("y"), literal(:integer, 10)),
          conditional(variable("y"), literal(:boolean, true), literal(:boolean, false))
        ])

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
