defmodule Metastatic.Analysis.Complexity.CyclomaticTest do
  use ExUnit.Case, async: true

  alias Metastatic.Analysis.Complexity.Cyclomatic

  doctest Metastatic.Analysis.Complexity.Cyclomatic

  describe "calculate/1 - simple constructs" do
    test "literals have complexity 1" do
      ast = {:literal, :integer, 42}
      assert Cyclomatic.calculate(ast) == 1
    end

    test "variables have complexity 1" do
      ast = {:variable, "x"}
      assert Cyclomatic.calculate(ast) == 1
    end

    test "arithmetic operations have complexity 1" do
      ast = {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}}
      assert Cyclomatic.calculate(ast) == 1
    end

    test "comparison operations have complexity 1" do
      ast = {:binary_op, :comparison, :>, {:variable, "x"}, {:literal, :integer, 10}}
      assert Cyclomatic.calculate(ast) == 1
    end

    test "assignment has complexity 1" do
      ast = {:assignment, {:variable, "x"}, {:literal, :integer, 5}}
      assert Cyclomatic.calculate(ast) == 1
    end

    test "inline match has complexity 1" do
      ast = {:inline_match, {:variable, "x"}, {:literal, :integer, 5}}
      assert Cyclomatic.calculate(ast) == 1
    end
  end

  describe "calculate/1 - conditionals" do
    test "single conditional has complexity 2" do
      ast =
        {:conditional, {:variable, "condition"}, {:literal, :integer, 1}, {:literal, :integer, 2}}

      assert Cyclomatic.calculate(ast) == 2
    end

    test "conditional with complex condition has complexity 2" do
      ast =
        {:conditional, {:binary_op, :comparison, :>, {:variable, "x"}, {:literal, :integer, 0}},
         {:literal, :integer, 1}, {:literal, :integer, 2}}

      assert Cyclomatic.calculate(ast) == 2
    end

    test "conditional without else branch has complexity 2" do
      ast = {:conditional, {:variable, "x"}, {:literal, :integer, 1}, nil}
      assert Cyclomatic.calculate(ast) == 2
    end

    test "nested conditionals add complexity" do
      ast =
        {:conditional, {:variable, "x"},
         {:conditional, {:variable, "y"}, {:literal, :integer, 1}, {:literal, :integer, 2}},
         {:literal, :integer, 3}}

      assert Cyclomatic.calculate(ast) == 3
    end
  end

  describe "calculate/1 - loops" do
    test "while loop has complexity 2" do
      ast = {:loop, :while, {:variable, "condition"}, {:literal, :integer, 1}}
      assert Cyclomatic.calculate(ast) == 2
    end

    test "for loop has complexity 2" do
      ast =
        {:loop, :for, {:variable, "i"}, {:variable, "range"}, {:literal, :integer, 1}}

      assert Cyclomatic.calculate(ast) == 2
    end

    test "loop with conditional inside adds complexity" do
      ast =
        {:loop, :while, {:variable, "condition"},
         {:conditional, {:variable, "x"}, {:literal, :integer, 1}, {:literal, :integer, 2}}}

      assert Cyclomatic.calculate(ast) == 3
    end

    test "nested loops add complexity" do
      ast =
        {:loop, :while, {:variable, "outer"},
         {:loop, :while, {:variable, "inner"}, {:literal, :integer, 1}}}

      assert Cyclomatic.calculate(ast) == 3
    end
  end

  describe "calculate/1 - boolean operators" do
    test "and operator adds complexity" do
      ast =
        {:binary_op, :boolean, :and, {:variable, "x"}, {:variable, "y"}}

      assert Cyclomatic.calculate(ast) == 2
    end

    test "or operator adds complexity" do
      ast =
        {:binary_op, :boolean, :or, {:variable, "x"}, {:variable, "y"}}

      assert Cyclomatic.calculate(ast) == 2
    end

    test "multiple boolean operators add complexity each" do
      ast =
        {:binary_op, :boolean, :and,
         {:binary_op, :boolean, :or, {:variable, "x"}, {:variable, "y"}}, {:variable, "z"}}

      assert Cyclomatic.calculate(ast) == 3
    end

    test "boolean operators in conditional condition" do
      ast =
        {:conditional, {:binary_op, :boolean, :and, {:variable, "x"}, {:variable, "y"}},
         {:literal, :integer, 1}, {:literal, :integer, 2}}

      # 1 (base) + 1 (conditional) + 1 (and) = 3
      assert Cyclomatic.calculate(ast) == 3
    end
  end

  describe "calculate/1 - exception handling" do
    test "try with single catch has complexity 2" do
      ast =
        {:exception_handling, {:literal, :integer, 1},
         [{:catch, {:variable, "error"}, {:literal, :integer, 2}}], nil}

      assert Cyclomatic.calculate(ast) == 2
    end

    test "try with multiple catches adds complexity per catch" do
      ast =
        {:exception_handling, {:literal, :integer, 1},
         [
           {:catch, {:variable, "error1"}, {:literal, :integer, 2}},
           {:catch, {:variable, "error2"}, {:literal, :integer, 3}}
         ], nil}

      assert Cyclomatic.calculate(ast) == 3
    end
  end

  describe "calculate/1 - pattern matching" do
    test "pattern match with two branches has complexity 3" do
      ast =
        {:pattern_match, {:variable, "value"},
         [
           {{:literal, :integer, 1}, {:literal, :string, "one"}},
           {{:literal, :integer, 2}, {:literal, :string, "two"}}
         ]}

      assert Cyclomatic.calculate(ast) == 3
    end

    test "pattern match with three branches has complexity 4" do
      ast =
        {:pattern_match, {:variable, "value"},
         [
           {{:literal, :integer, 1}, {:literal, :string, "one"}},
           {{:literal, :integer, 2}, {:literal, :string, "two"}},
           {{:literal, :integer, 3}, {:literal, :string, "three"}}
         ]}

      assert Cyclomatic.calculate(ast) == 4
    end
  end

  describe "calculate/1 - blocks and sequences" do
    test "block with sequential statements has complexity 1" do
      ast =
        {:block,
         [
           {:variable, "x"},
           {:variable, "y"},
           {:variable, "z"}
         ]}

      assert Cyclomatic.calculate(ast) == 1
    end

    test "block with conditional has complexity 2" do
      ast =
        {:block,
         [
           {:variable, "x"},
           {:conditional, {:variable, "y"}, {:literal, :integer, 1}, {:literal, :integer, 2}}
         ]}

      assert Cyclomatic.calculate(ast) == 2
    end
  end

  describe "calculate/1 - collections and lambdas" do
    test "lambda body adds its complexity" do
      ast =
        {:lambda, [{:variable, "x"}],
         {:conditional, {:variable, "x"}, {:literal, :integer, 1}, {:literal, :integer, 2}}}

      assert Cyclomatic.calculate(ast) == 2
    end

    test "collection operation with conditional in function" do
      ast =
        {:collection_op, :map,
         {:lambda, [{:variable, "x"}],
          {:conditional, {:variable, "x"}, {:literal, :integer, 1}, {:literal, :integer, 2}}},
         {:variable, "list"}}

      assert Cyclomatic.calculate(ast) == 2
    end
  end

  describe "calculate/1 - complex real-world examples" do
    test "function with multiple conditionals and loop" do
      # if x > 0:
      #   while y < 10:
      #     if z:
      #       return 1
      #   return 2
      # else:
      #   return 3
      ast =
        {:conditional, {:binary_op, :comparison, :>, {:variable, "x"}, {:literal, :integer, 0}},
         {:block,
          [
            {:loop, :while,
             {:binary_op, :comparison, :<, {:variable, "y"}, {:literal, :integer, 10}},
             {:conditional, {:variable, "z"}, {:early_return, {:literal, :integer, 1}}, nil}},
            {:early_return, {:literal, :integer, 2}}
          ]}, {:early_return, {:literal, :integer, 3}}}

      # Base: 1
      # Conditional (if x > 0): +1 = 2
      # Loop (while y < 10): +1 = 3
      # Inner conditional (if z): +1 = 4
      assert Cyclomatic.calculate(ast) == 4
    end

    test "function with multiple boolean operators" do
      # if (x and y) or z:
      #   return 1
      # else:
      #   return 2
      ast =
        {:conditional,
         {:binary_op, :boolean, :or,
          {:binary_op, :boolean, :and, {:variable, "x"}, {:variable, "y"}}, {:variable, "z"}},
         {:early_return, {:literal, :integer, 1}}, {:early_return, {:literal, :integer, 2}}}

      # Base: 1
      # Conditional: +1 = 2
      # and: +1 = 3
      # or: +1 = 4
      assert Cyclomatic.calculate(ast) == 4
    end
  end

  describe "calculate/1 - language-specific constructs" do
    test "language-specific nodes don't add complexity" do
      ast = {:language_specific, :python, {:some, :native, :ast}}
      assert Cyclomatic.calculate(ast) == 1
    end

    test "language-specific with hint doesn't add complexity" do
      ast = {:language_specific, :elixir, {:pipe, :operator}, :pipe}
      assert Cyclomatic.calculate(ast) == 1
    end
  end
end
