defmodule Metastatic.Analysis.Complexity.CyclomaticTest do
  use ExUnit.Case, async: true

  alias Metastatic.Analysis.Complexity.Cyclomatic

  doctest Metastatic.Analysis.Complexity.Cyclomatic

  describe "calculate/1 - simple constructs" do
    test "literals have complexity 1" do
      ast = {:literal, [subtype: :integer], 42}
      assert Cyclomatic.calculate(ast) == 1
    end

    test "variables have complexity 1" do
      ast = {:variable, [], "x"}
      assert Cyclomatic.calculate(ast) == 1
    end

    test "arithmetic operations have complexity 1" do
      ast =
        {:binary_op, [category: :arithmetic, operator: :+],
         [{:variable, [], "x"}, {:literal, [subtype: :integer], 5}]}

      assert Cyclomatic.calculate(ast) == 1
    end

    test "comparison operations have complexity 1" do
      ast =
        {:binary_op, [category: :comparison, operator: :>],
         [{:variable, [], "x"}, {:literal, [subtype: :integer], 10}]}

      assert Cyclomatic.calculate(ast) == 1
    end

    test "assignment has complexity 1" do
      ast = {:assignment, [], [{:variable, [], "x"}, {:literal, [subtype: :integer], 5}]}
      assert Cyclomatic.calculate(ast) == 1
    end

    test "inline match has complexity 1" do
      ast = {:inline_match, [], [{:variable, [], "x"}, {:literal, [subtype: :integer], 5}]}
      assert Cyclomatic.calculate(ast) == 1
    end
  end

  describe "calculate/1 - conditionals" do
    test "single conditional has complexity 2" do
      ast =
        {:conditional, [],
         [
           {:variable, [], "condition"},
           {:literal, [subtype: :integer], 1},
           {:literal, [subtype: :integer], 2}
         ]}

      assert Cyclomatic.calculate(ast) == 2
    end

    test "conditional with complex condition has complexity 2" do
      ast =
        {:conditional, [],
         [
           {:binary_op, [category: :comparison, operator: :>],
            [{:variable, [], "x"}, {:literal, [subtype: :integer], 0}]},
           {:literal, [subtype: :integer], 1},
           {:literal, [subtype: :integer], 2}
         ]}

      assert Cyclomatic.calculate(ast) == 2
    end

    test "conditional without else branch has complexity 2" do
      ast = {:conditional, [], [{:variable, [], "x"}, {:literal, [subtype: :integer], 1}, nil]}
      assert Cyclomatic.calculate(ast) == 2
    end

    test "nested conditionals add complexity" do
      ast =
        {:conditional, [],
         [
           {:variable, [], "x"},
           {:conditional, [],
            [
              {:variable, [], "y"},
              {:literal, [subtype: :integer], 1},
              {:literal, [subtype: :integer], 2}
            ]},
           {:literal, [subtype: :integer], 3}
         ]}

      assert Cyclomatic.calculate(ast) == 3
    end
  end

  describe "calculate/1 - loops" do
    test "while loop has complexity 2" do
      ast =
        {:loop, [loop_type: :while],
         [{:variable, [], "condition"}, {:literal, [subtype: :integer], 1}]}

      assert Cyclomatic.calculate(ast) == 2
    end

    test "for loop has complexity 2" do
      ast =
        {:loop, [loop_type: :for_each],
         [{:variable, [], "i"}, {:variable, [], "range"}, {:literal, [subtype: :integer], 1}]}

      assert Cyclomatic.calculate(ast) == 2
    end

    test "loop with conditional inside adds complexity" do
      ast =
        {:loop, [loop_type: :while],
         [
           {:variable, [], "condition"},
           {:conditional, [],
            [
              {:variable, [], "x"},
              {:literal, [subtype: :integer], 1},
              {:literal, [subtype: :integer], 2}
            ]}
         ]}

      assert Cyclomatic.calculate(ast) == 3
    end

    test "nested loops add complexity" do
      ast =
        {:loop, [loop_type: :while],
         [
           {:variable, [], "outer"},
           {:loop, [loop_type: :while],
            [{:variable, [], "inner"}, {:literal, [subtype: :integer], 1}]}
         ]}

      assert Cyclomatic.calculate(ast) == 3
    end
  end

  describe "calculate/1 - boolean operators" do
    test "and operator adds complexity" do
      ast =
        {:binary_op, [category: :boolean, operator: :and],
         [{:variable, [], "x"}, {:variable, [], "y"}]}

      assert Cyclomatic.calculate(ast) == 2
    end

    test "or operator adds complexity" do
      ast =
        {:binary_op, [category: :boolean, operator: :or],
         [{:variable, [], "x"}, {:variable, [], "y"}]}

      assert Cyclomatic.calculate(ast) == 2
    end

    test "multiple boolean operators add complexity each" do
      ast =
        {:binary_op, [category: :boolean, operator: :and],
         [
           {:binary_op, [category: :boolean, operator: :or],
            [{:variable, [], "x"}, {:variable, [], "y"}]},
           {:variable, [], "z"}
         ]}

      assert Cyclomatic.calculate(ast) == 3
    end

    test "boolean operators in conditional condition" do
      ast =
        {:conditional, [],
         [
           {:binary_op, [category: :boolean, operator: :and],
            [{:variable, [], "x"}, {:variable, [], "y"}]},
           {:literal, [subtype: :integer], 1},
           {:literal, [subtype: :integer], 2}
         ]}

      # 1 (base) + 1 (conditional) + 1 (and) = 3
      assert Cyclomatic.calculate(ast) == 3
    end
  end

  describe "calculate/1 - exception handling" do
    test "try with single catch has complexity 2" do
      ast =
        {:exception_handling, [],
         [
           {:literal, [subtype: :integer], 1},
           [{:catch, {:variable, [], "error"}, {:literal, [subtype: :integer], 2}}],
           nil
         ]}

      assert Cyclomatic.calculate(ast) == 2
    end

    test "try with multiple catches adds complexity per catch" do
      ast =
        {:exception_handling, [],
         [
           {:literal, [subtype: :integer], 1},
           [
             {:catch, {:variable, [], "error1"}, {:literal, [subtype: :integer], 2}},
             {:catch, {:variable, [], "error2"}, {:literal, [subtype: :integer], 3}}
           ],
           nil
         ]}

      assert Cyclomatic.calculate(ast) == 3
    end
  end

  describe "calculate/1 - pattern matching" do
    test "pattern match with two branches has complexity 3" do
      ast =
        {:pattern_match, [],
         [
           {:variable, [], "value"},
           [
             {:pair, [],
              [{:literal, [subtype: :integer], 1}, {:literal, [subtype: :string], "one"}]},
             {:pair, [],
              [{:literal, [subtype: :integer], 2}, {:literal, [subtype: :string], "two"}]}
           ]
         ]}

      assert Cyclomatic.calculate(ast) == 3
    end

    test "pattern match with three branches has complexity 4" do
      ast =
        {:pattern_match, [],
         [
           {:variable, [], "value"},
           [
             {:pair, [],
              [{:literal, [subtype: :integer], 1}, {:literal, [subtype: :string], "one"}]},
             {:pair, [],
              [{:literal, [subtype: :integer], 2}, {:literal, [subtype: :string], "two"}]},
             {:pair, [],
              [{:literal, [subtype: :integer], 3}, {:literal, [subtype: :string], "three"}]}
           ]
         ]}

      assert Cyclomatic.calculate(ast) == 4
    end
  end

  describe "calculate/1 - blocks and sequences" do
    test "block with sequential statements has complexity 1" do
      ast =
        {:block, [],
         [
           {:variable, [], "x"},
           {:variable, [], "y"},
           {:variable, [], "z"}
         ]}

      assert Cyclomatic.calculate(ast) == 1
    end

    test "block with conditional has complexity 2" do
      ast =
        {:block, [],
         [
           {:variable, [], "x"},
           {:conditional, [],
            [
              {:variable, [], "y"},
              {:literal, [subtype: :integer], 1},
              {:literal, [subtype: :integer], 2}
            ]}
         ]}

      assert Cyclomatic.calculate(ast) == 2
    end
  end

  describe "calculate/1 - collections and lambdas" do
    test "lambda body adds its complexity" do
      ast =
        {:lambda, [params: ["x"], captures: []],
         [
           {:conditional, [],
            [
              {:variable, [], "x"},
              {:literal, [subtype: :integer], 1},
              {:literal, [subtype: :integer], 2}
            ]}
         ]}

      assert Cyclomatic.calculate(ast) == 2
    end

    test "collection operation with conditional in function" do
      ast =
        {:collection_op, [op_type: :map],
         [
           {:lambda, [params: ["x"], captures: []],
            [
              {:conditional, [],
               [
                 {:variable, [], "x"},
                 {:literal, [subtype: :integer], 1},
                 {:literal, [subtype: :integer], 2}
               ]}
            ]},
           {:variable, [], "list"}
         ]}

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
        {:conditional, [],
         [
           {:binary_op, [category: :comparison, operator: :>],
            [{:variable, [], "x"}, {:literal, [subtype: :integer], 0}]},
           {:block, [],
            [
              {:loop, [loop_type: :while],
               [
                 {:binary_op, [category: :comparison, operator: :<],
                  [{:variable, [], "y"}, {:literal, [subtype: :integer], 10}]},
                 {:conditional, [],
                  [
                    {:variable, [], "z"},
                    {:early_return, [], [{:literal, [subtype: :integer], 1}]},
                    nil
                  ]}
               ]},
              {:early_return, [], [{:literal, [subtype: :integer], 2}]}
            ]},
           {:early_return, [], [{:literal, [subtype: :integer], 3}]}
         ]}

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
        {:conditional, [],
         [
           {:binary_op, [category: :boolean, operator: :or],
            [
              {:binary_op, [category: :boolean, operator: :and],
               [{:variable, [], "x"}, {:variable, [], "y"}]},
              {:variable, [], "z"}
            ]},
           {:early_return, [], [{:literal, [subtype: :integer], 1}]},
           {:early_return, [], [{:literal, [subtype: :integer], 2}]}
         ]}

      # Base: 1
      # Conditional: +1 = 2
      # and: +1 = 3
      # or: +1 = 4
      assert Cyclomatic.calculate(ast) == 4
    end
  end

  describe "calculate/1 - language-specific constructs" do
    test "language-specific nodes don't add complexity" do
      ast = {:language_specific, [language: :python], %{some: :native, ast: true}}
      assert Cyclomatic.calculate(ast) == 1
    end

    test "language-specific with hint doesn't add complexity" do
      ast = {:language_specific, [language: :elixir, hint: :pipe], %{pipe: :operator}}
      assert Cyclomatic.calculate(ast) == 1
    end
  end
end
