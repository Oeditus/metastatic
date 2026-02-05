defmodule Metastatic.Analysis.BusinessLogic.CallbackHellTest do
  use ExUnit.Case, async: true

  alias Metastatic.Analysis.BusinessLogic.CallbackHell
  alias Metastatic.Document

  # Helper to create 3-tuple nodes
  defp conditional(condition, then_branch, else_branch \\ nil) do
    {:conditional, [], [condition, then_branch, else_branch]}
  end

  defp variable(name), do: {:variable, [], name}
  defp literal(subtype, value), do: {:literal, [subtype: subtype], value}
  defp block(statements), do: {:block, [], statements}

  defp binary_op(category, operator, left, right) do
    {:binary_op, [category: category, operator: operator], [left, right]}
  end

  defp function_call(name, args), do: {:function_call, [name: name], args}
  defp early_return(value), do: {:early_return, [], [value]}

  describe "info/0" do
    test "returns analyzer metadata" do
      info = CallbackHell.info()

      assert info.name == :callback_hell
      assert info.category == :readability
      assert info.severity == :warning
      assert info.configurable == true
      assert is_binary(info.description)
      assert is_binary(info.explanation)
    end
  end

  describe "analyze/2 with default config (max_nesting: 2)" do
    setup do
      context = %{
        document: Document.new(literal(:integer, 1), :elixir),
        config: %{},
        parent_stack: [],
        depth: 0,
        scope: %{}
      }

      {:ok, context} = CallbackHell.run_before(context)
      %{context: context}
    end

    test "accepts single conditional", %{context: context} do
      ast = conditional(variable("x"), literal(:integer, 1))

      assert [] = CallbackHell.analyze(ast, context)
    end

    test "accepts 2-level nesting (at threshold)", %{context: context} do
      # Nested 2 deep - should be OK
      inner = conditional(variable("y"), literal(:integer, 2))
      outer = conditional(variable("x"), block([inner]))

      assert [] = CallbackHell.analyze(outer, context)
    end

    test "detects 3-level nesting (exceeds threshold)", %{context: context} do
      # Nested 3 deep - should trigger warning
      deepest = conditional(variable("z"), literal(:integer, 3))
      middle = conditional(variable("y"), block([deepest]))
      outer = conditional(variable("x"), block([middle]))

      [issue] = CallbackHell.analyze(outer, context)

      assert issue.analyzer == CallbackHell
      assert issue.category == :readability
      assert issue.severity == :warning
      assert issue.message =~ "3 levels"
      assert issue.metadata.nesting_level == 3
      assert issue.metadata.max_allowed == 2
    end

    test "detects 4-level deep nesting", %{context: context} do
      # Even deeper nesting
      deepest = conditional(variable("w"), literal(:integer, 4))
      third = conditional(variable("z"), block([deepest]))
      second = conditional(variable("y"), block([third]))
      first = conditional(variable("x"), block([second]))

      [issue] = CallbackHell.analyze(first, context)

      assert issue.metadata.nesting_level == 4
      assert issue.message =~ "4 levels"
    end

    test "handles else branch nesting", %{context: context} do
      # Nesting in else branch
      inner = conditional(variable("y"), literal(:integer, 2))
      outer = conditional(variable("x"), literal(:integer, 1), block([inner]))

      assert [] = CallbackHell.analyze(outer, context)
    end

    test "finds max nesting across both branches", %{context: context} do
      # Then branch: 2 levels
      then_inner = conditional(variable("y"), literal(:integer, 2))

      # Else branch: 3 levels (deeper)
      else_deepest = conditional(variable("w"), literal(:integer, 3))
      else_middle = conditional(variable("z"), block([else_deepest]))

      outer = conditional(variable("x"), block([then_inner]), block([else_middle]))

      [issue] = CallbackHell.analyze(outer, context)
      assert issue.metadata.nesting_level == 3
    end

    test "ignores non-conditional nodes", %{context: context} do
      ast = literal(:string, "hello")
      assert [] = CallbackHell.analyze(ast, context)

      ast = variable("x")
      assert [] = CallbackHell.analyze(ast, context)

      ast = binary_op(:arithmetic, :+, variable("a"), variable("b"))
      assert [] = CallbackHell.analyze(ast, context)
    end
  end

  describe "analyze/2 with custom max_nesting" do
    test "respects custom threshold of 1" do
      context = %{
        document: Document.new(literal(:integer, 1), :elixir),
        config: %{max_nesting: 1},
        parent_stack: [],
        depth: 0,
        scope: %{}
      }

      {:ok, context} = CallbackHell.run_before(context)

      # 2 levels should now trigger (threshold is 1)
      inner = conditional(variable("y"), literal(:integer, 2))
      outer = conditional(variable("x"), block([inner]))

      [issue] = CallbackHell.analyze(outer, context)
      assert issue.metadata.nesting_level == 2
      assert issue.metadata.max_allowed == 1
    end

    test "respects custom threshold of 5" do
      context = %{
        document: Document.new(literal(:integer, 1), :elixir),
        config: %{max_nesting: 5},
        parent_stack: [],
        depth: 0,
        scope: %{}
      }

      {:ok, context} = CallbackHell.run_before(context)

      # 3 levels should be fine (threshold is 5)
      deepest = conditional(variable("z"), literal(:integer, 3))
      middle = conditional(variable("y"), block([deepest]))
      outer = conditional(variable("x"), block([middle]))

      assert [] = CallbackHell.analyze(outer, context)

      # But 6 levels should trigger
      level6 = conditional(variable("f"), literal(:integer, 6))
      level5 = conditional(variable("e"), block([level6]))
      level4 = conditional(variable("d"), block([level5]))
      level3 = conditional(variable("c"), block([level4]))
      level2 = conditional(variable("b"), block([level3]))
      level1 = conditional(variable("a"), block([level2]))

      [issue] = CallbackHell.analyze(level1, context)
      assert issue.metadata.nesting_level == 6
      assert issue.metadata.max_allowed == 5
    end
  end

  describe "cross-language patterns" do
    test "represents Python nested if/else pattern" do
      # Python:
      # if user is not None:
      #     if user.active:
      #         if user.has_permission():
      #             return True

      context = %{
        document: Document.new(literal(:integer, 1), :python),
        config: %{max_nesting: 2},
        parent_stack: [],
        depth: 0,
        scope: %{}
      }

      {:ok, context} = CallbackHell.run_before(context)

      permission_check =
        conditional(
          function_call("has_permission", []),
          early_return(literal(:boolean, true))
        )

      active_check = conditional(variable("user_active"), block([permission_check]))

      none_check =
        conditional(
          binary_op(:comparison, :!=, variable("user"), literal(:null, nil)),
          block([active_check])
        )

      [issue] = CallbackHell.analyze(none_check, context)
      assert issue.metadata.nesting_level == 3
    end

    test "represents JavaScript nested ternary pattern" do
      # JavaScript:
      # x ? (y ? a : b) : (z ? c : d)
      # Represented as nested conditionals

      context = %{
        document: Document.new(literal(:integer, 1), :javascript),
        config: %{max_nesting: 2},
        parent_stack: [],
        depth: 0,
        scope: %{}
      }

      {:ok, context} = CallbackHell.run_before(context)

      inner_then = conditional(variable("y"), variable("a"), variable("b"))
      inner_else = conditional(variable("z"), variable("c"), variable("d"))
      outer = conditional(variable("x"), inner_then, inner_else)

      # Nested ternaries have 2 levels (x -> y OR x -> z)
      assert [] = CallbackHell.analyze(outer, context)

      # But adding another level should trigger
      deepest = conditional(variable("w"), variable("deep"), nil)
      inner_then_deep = conditional(variable("y"), block([deepest]), variable("b"))
      outer_deep = conditional(variable("x"), inner_then_deep, variable("c"))

      [issue] = CallbackHell.analyze(outer_deep, context)
      assert issue.metadata.nesting_level == 3
    end

    test "represents Rust nested match pattern" do
      # Rust:
      # match a {
      #     Some(x) => match x {
      #         Ok(y) => match y {
      #             Value::Int(n) => n
      #         }
      #     }
      # }

      context = %{
        document: Document.new(literal(:integer, 1), :rust),
        config: %{max_nesting: 2},
        parent_stack: [],
        depth: 0,
        scope: %{}
      }

      {:ok, context} = CallbackHell.run_before(context)

      deepest_match = conditional(variable("y"), variable("n"))
      middle_match = conditional(variable("x"), block([deepest_match]))
      outer_match = conditional(variable("a"), block([middle_match]))

      [issue] = CallbackHell.analyze(outer_match, context)
      assert issue.metadata.nesting_level == 3
    end
  end
end
