defmodule Metastatic.Analysis.BusinessLogic.CallbackHellTest do
  use ExUnit.Case, async: true

  alias Metastatic.Analysis.BusinessLogic.CallbackHell
  alias Metastatic.Document

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
        document: Document.new({:literal, :integer, 1}, :elixir),
        config: %{},
        parent_stack: [],
        depth: 0,
        scope: %{}
      }

      {:ok, context} = CallbackHell.run_before(context)
      %{context: context}
    end

    test "accepts single conditional", %{context: context} do
      ast = {:conditional, {:variable, "x"}, {:literal, :integer, 1}, nil}

      assert [] = CallbackHell.analyze(ast, context)
    end

    test "accepts 2-level nesting (at threshold)", %{context: context} do
      # Nested 2 deep - should be OK
      inner = {:conditional, {:variable, "y"}, {:literal, :integer, 2}, nil}

      outer =
        {:conditional, {:variable, "x"}, {:block, [inner]}, nil}

      assert [] = CallbackHell.analyze(outer, context)
    end

    test "detects 3-level nesting (exceeds threshold)", %{context: context} do
      # Nested 3 deep - should trigger warning
      deepest = {:conditional, {:variable, "z"}, {:literal, :integer, 3}, nil}
      middle = {:conditional, {:variable, "y"}, {:block, [deepest]}, nil}
      outer = {:conditional, {:variable, "x"}, {:block, [middle]}, nil}

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
      deepest = {:conditional, {:variable, "w"}, {:literal, :integer, 4}, nil}
      third = {:conditional, {:variable, "z"}, {:block, [deepest]}, nil}
      second = {:conditional, {:variable, "y"}, {:block, [third]}, nil}
      first = {:conditional, {:variable, "x"}, {:block, [second]}, nil}

      [issue] = CallbackHell.analyze(first, context)

      assert issue.metadata.nesting_level == 4
      assert issue.message =~ "4 levels"
    end

    test "handles else branch nesting", %{context: context} do
      # Nesting in else branch
      inner = {:conditional, {:variable, "y"}, {:literal, :integer, 2}, nil}

      outer =
        {:conditional, {:variable, "x"}, {:literal, :integer, 1}, {:block, [inner]}}

      assert [] = CallbackHell.analyze(outer, context)
    end

    test "finds max nesting across both branches", %{context: context} do
      # Then branch: 2 levels
      then_inner = {:conditional, {:variable, "y"}, {:literal, :integer, 2}, nil}

      # Else branch: 3 levels (deeper)
      else_deepest = {:conditional, {:variable, "w"}, {:literal, :integer, 3}, nil}
      else_middle = {:conditional, {:variable, "z"}, {:block, [else_deepest]}, nil}

      outer =
        {:conditional, {:variable, "x"}, {:block, [then_inner]}, {:block, [else_middle]}}

      [issue] = CallbackHell.analyze(outer, context)
      assert issue.metadata.nesting_level == 3
    end

    test "ignores non-conditional nodes", %{context: context} do
      ast = {:literal, :string, "hello"}
      assert [] = CallbackHell.analyze(ast, context)

      ast = {:variable, "x"}
      assert [] = CallbackHell.analyze(ast, context)

      ast = {:binary_op, :arithmetic, :+, {:variable, "a"}, {:variable, "b"}}
      assert [] = CallbackHell.analyze(ast, context)
    end
  end

  describe "analyze/2 with custom max_nesting" do
    test "respects custom threshold of 1" do
      context = %{
        document: Document.new({:literal, :integer, 1}, :elixir),
        config: %{max_nesting: 1},
        parent_stack: [],
        depth: 0,
        scope: %{}
      }

      {:ok, context} = CallbackHell.run_before(context)

      # 2 levels should now trigger (threshold is 1)
      inner = {:conditional, {:variable, "y"}, {:literal, :integer, 2}, nil}
      outer = {:conditional, {:variable, "x"}, {:block, [inner]}, nil}

      [issue] = CallbackHell.analyze(outer, context)
      assert issue.metadata.nesting_level == 2
      assert issue.metadata.max_allowed == 1
    end

    test "respects custom threshold of 5" do
      context = %{
        document: Document.new({:literal, :integer, 1}, :elixir),
        config: %{max_nesting: 5},
        parent_stack: [],
        depth: 0,
        scope: %{}
      }

      {:ok, context} = CallbackHell.run_before(context)

      # 3 levels should be fine (threshold is 5)
      deepest = {:conditional, {:variable, "z"}, {:literal, :integer, 3}, nil}
      middle = {:conditional, {:variable, "y"}, {:block, [deepest]}, nil}
      outer = {:conditional, {:variable, "x"}, {:block, [middle]}, nil}

      assert [] = CallbackHell.analyze(outer, context)

      # But 6 levels should trigger
      level6 = {:conditional, {:variable, "f"}, {:literal, :integer, 6}, nil}
      level5 = {:conditional, {:variable, "e"}, {:block, [level6]}, nil}
      level4 = {:conditional, {:variable, "d"}, {:block, [level5]}, nil}
      level3 = {:conditional, {:variable, "c"}, {:block, [level4]}, nil}
      level2 = {:conditional, {:variable, "b"}, {:block, [level3]}, nil}
      level1 = {:conditional, {:variable, "a"}, {:block, [level2]}, nil}

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
        document: Document.new({:literal, :integer, 1}, :python),
        config: %{max_nesting: 2},
        parent_stack: [],
        depth: 0,
        scope: %{}
      }

      {:ok, context} = CallbackHell.run_before(context)

      permission_check =
        {:conditional, {:function_call, :has_permission, []},
         {:early_return, {:literal, :boolean, true}}, nil}

      active_check =
        {:conditional, {:variable, "user_active"}, {:block, [permission_check]}, nil}

      none_check =
        {:conditional,
         {:binary_op, :comparison, :!=, {:variable, "user"}, {:literal, :atom, nil}},
         {:block, [active_check]}, nil}

      [issue] = CallbackHell.analyze(none_check, context)
      assert issue.metadata.nesting_level == 3
      assert issue.node == none_check
    end

    test "represents JavaScript nested ternary pattern" do
      # JavaScript: cond1 ? (cond2 ? (cond3 ? val1 : val2) : val3) : val4
      # While ternaries are different, they map to conditionals in MetaAST

      context = %{
        document: Document.new({:literal, :integer, 1}, :javascript),
        config: %{max_nesting: 2},
        parent_stack: [],
        depth: 0,
        scope: %{}
      }

      {:ok, context} = CallbackHell.run_before(context)

      inner =
        {:conditional, {:variable, "cond3"}, {:variable, "val1"}, {:variable, "val2"}}

      middle = {:conditional, {:variable, "cond2"}, inner, {:variable, "val3"}}
      outer = {:conditional, {:variable, "cond1"}, middle, {:variable, "val4"}}

      [issue] = CallbackHell.analyze(outer, context)
      assert issue.metadata.nesting_level == 3
    end

    test "represents Rust nested match pattern" do
      # Rust:
      # match result1 {
      #     Ok(v1) => match result2 {
      #         Ok(v2) => match result3 {
      #             Ok(v3) => v3
      #         }
      #     }
      # }

      context = %{
        document: Document.new({:literal, :integer, 1}, :rust),
        config: %{max_nesting: 2},
        parent_stack: [],
        depth: 0,
        scope: %{}
      }

      {:ok, context} = CallbackHell.run_before(context)

      # Using conditional as simplified match representation
      inner = {:conditional, {:variable, "result3"}, {:variable, "v3"}, nil}
      middle = {:conditional, {:variable, "result2"}, {:block, [inner]}, nil}
      outer = {:conditional, {:variable, "result1"}, {:block, [middle]}, nil}

      [issue] = CallbackHell.analyze(outer, context)
      assert issue.metadata.nesting_level == 3
    end
  end
end
