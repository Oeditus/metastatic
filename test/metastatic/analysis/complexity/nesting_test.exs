defmodule Metastatic.Analysis.Complexity.NestingTest do
  use ExUnit.Case, async: true

  alias Metastatic.Analysis.Complexity.Nesting

  doctest Metastatic.Analysis.Complexity.Nesting

  describe "calculate/1 - no nesting" do
    test "literals have depth 0" do
      ast = {:literal, :integer, 42}
      assert Nesting.calculate(ast) == 0
    end

    test "variables have depth 0" do
      ast = {:variable, "x"}
      assert Nesting.calculate(ast) == 0
    end

    test "arithmetic operations have depth 0" do
      ast = {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}}
      assert Nesting.calculate(ast) == 0
    end

    test "sequential statements have depth 0" do
      ast =
        {:block,
         [
           {:variable, "x"},
           {:variable, "y"},
           {:variable, "z"}
         ]}

      assert Nesting.calculate(ast) == 0
    end
  end

  describe "calculate/1 - single level nesting" do
    test "conditional has depth 1" do
      ast = {:conditional, {:variable, "x"}, {:literal, :integer, 1}, {:literal, :integer, 2}}
      assert Nesting.calculate(ast) == 1
    end

    test "while loop has depth 1" do
      ast = {:loop, :while, {:variable, "condition"}, {:literal, :integer, 1}}
      assert Nesting.calculate(ast) == 1
    end

    test "for loop has depth 1" do
      ast = {:loop, :for, {:variable, "i"}, {:variable, "range"}, {:literal, :integer, 1}}
      assert Nesting.calculate(ast) == 1
    end

    test "lambda has depth 1" do
      ast = {:lambda, [{:variable, "x"}], {:literal, :integer, 1}}
      assert Nesting.calculate(ast) == 1
    end

    test "exception handling has depth 1" do
      ast =
        {:exception_handling, {:literal, :integer, 1},
         [{:catch, {:variable, "error"}, {:literal, :integer, 2}}], nil}

      assert Nesting.calculate(ast) == 1
    end

    test "pattern match has depth 1" do
      ast =
        {:pattern_match, {:variable, "value"},
         [
           {{:literal, :integer, 1}, {:literal, :string, "one"}},
           {{:literal, :integer, 2}, {:literal, :string, "two"}}
         ]}

      assert Nesting.calculate(ast) == 1
    end
  end

  describe "calculate/1 - nested structures" do
    test "nested conditionals have depth 2" do
      ast =
        {:conditional, {:variable, "x"},
         {:conditional, {:variable, "y"}, {:literal, :integer, 1}, {:literal, :integer, 2}},
         {:literal, :integer, 3}}

      assert Nesting.calculate(ast) == 2
    end

    test "triple nested conditionals have depth 3" do
      ast =
        {:conditional, {:variable, "x"},
         {:conditional, {:variable, "y"},
          {:conditional, {:variable, "z"}, {:literal, :integer, 1}, {:literal, :integer, 2}},
          {:literal, :integer, 3}}, {:literal, :integer, 4}}

      assert Nesting.calculate(ast) == 3
    end

    test "loop with conditional inside has depth 2" do
      ast =
        {:loop, :while, {:variable, "condition"},
         {:conditional, {:variable, "x"}, {:literal, :integer, 1}, {:literal, :integer, 2}}}

      assert Nesting.calculate(ast) == 2
    end

    test "nested loops have depth 2" do
      ast =
        {:loop, :while, {:variable, "outer"},
         {:loop, :while, {:variable, "inner"}, {:literal, :integer, 1}}}

      assert Nesting.calculate(ast) == 2
    end

    test "lambda with conditional inside has depth 2" do
      ast =
        {:lambda, [{:variable, "x"}],
         {:conditional, {:variable, "x"}, {:literal, :integer, 1}, {:literal, :integer, 2}}}

      assert Nesting.calculate(ast) == 2
    end
  end

  describe "calculate/1 - complex nesting scenarios" do
    test "conditional in loop in conditional has depth 3" do
      # if a:
      #   while b:
      #     if c:
      ast =
        {:conditional, {:variable, "a"},
         {:loop, :while, {:variable, "b"},
          {:conditional, {:variable, "c"}, {:literal, :integer, 1}, {:literal, :integer, 2}}},
         {:literal, :integer, 3}}

      assert Nesting.calculate(ast) == 3
    end

    test "multiple branches use max depth" do
      # if x:
      #   if y:
      #     if z:  <- depth 3
      # else:
      #   if a:  <- depth 2
      ast =
        {:conditional, {:variable, "x"},
         {:conditional, {:variable, "y"},
          {:conditional, {:variable, "z"}, {:literal, :integer, 1}, {:literal, :integer, 2}},
          {:literal, :integer, 3}},
         {:conditional, {:variable, "a"}, {:literal, :integer, 4}, {:literal, :integer, 5}}}

      # Max of then_branch (3) and else_branch (2)
      assert Nesting.calculate(ast) == 3
    end

    test "sequential statements at different depths use max" do
      # block:
      #   if x:
      #     statement  <- depth 1
      #   if y:
      #     if z:
      #       statement  <- depth 2
      ast =
        {:block,
         [
           {:conditional, {:variable, "x"}, {:literal, :integer, 1}, {:literal, :integer, 2}},
           {:conditional, {:variable, "y"},
            {:conditional, {:variable, "z"}, {:literal, :integer, 3}, {:literal, :integer, 4}},
            {:literal, :integer, 5}}
         ]}

      # First conditional: depth 1, Second nested conditional: depth 2 -> max = 2
      assert Nesting.calculate(ast) == 2
    end
  end

  describe "calculate/1 - exception handling and pattern matching" do
    test "nested exception handling" do
      ast =
        {:exception_handling, {:literal, :integer, 1},
         [
           {:catch, {:variable, "error"},
            {:exception_handling, {:literal, :integer, 2},
             [{:catch, {:variable, "inner_error"}, {:literal, :integer, 3}}], nil}}
         ], nil}

      assert Nesting.calculate(ast) == 2
    end

    test "pattern match with nested conditional" do
      ast =
        {:pattern_match, {:variable, "value"},
         [
           {{:literal, :integer, 1},
            {:conditional, {:variable, "x"}, {:literal, :integer, 10}, {:literal, :integer, 20}}}
         ]}

      assert Nesting.calculate(ast) == 2
    end
  end

  describe "calculate/1 - real-world complexity" do
    test "deeply nested realistic example" do
      # if authenticated:
      #   while processing:
      #     for item in items:
      #       if item.valid:
      #         if item.active:
      #           process(item)
      ast =
        {:conditional, {:variable, "authenticated"},
         {:loop, :while, {:variable, "processing"},
          {:loop, :for, {:variable, "item"}, {:variable, "items"},
           {:conditional, {:variable, "item_valid"},
            {:conditional, {:variable, "item_active"},
             {:function_call, "process", [{:variable, "item"}]}, nil}, nil}}}, nil}

      # Levels: conditional(1) -> while(2) -> for(3) -> if(4) -> if(5)
      assert Nesting.calculate(ast) == 5
    end
  end
end
