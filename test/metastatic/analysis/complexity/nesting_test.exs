defmodule Metastatic.Analysis.Complexity.NestingTest do
  use ExUnit.Case, async: true

  alias Metastatic.Analysis.Complexity.Nesting

  doctest Metastatic.Analysis.Complexity.Nesting

  describe "calculate/1 - no nesting" do
    test "literals have depth 0" do
      ast = {:literal, [subtype: :integer], 42}
      assert Nesting.calculate(ast) == 0
    end

    test "variables have depth 0" do
      ast = {:variable, [], "x"}
      assert Nesting.calculate(ast) == 0
    end

    test "arithmetic operations have depth 0" do
      ast =
        {:binary_op, [category: :arithmetic, operator: :+],
         [{:variable, [], "x"}, {:literal, [subtype: :integer], 5}]}

      assert Nesting.calculate(ast) == 0
    end

    test "sequential statements have depth 0" do
      ast =
        {:block, [],
         [
           {:variable, [], "x"},
           {:variable, [], "y"},
           {:variable, [], "z"}
         ]}

      assert Nesting.calculate(ast) == 0
    end
  end

  describe "calculate/1 - single level nesting" do
    test "conditional has depth 1" do
      ast =
        {:conditional, [],
         [
           {:variable, [], "x"},
           {:literal, [subtype: :integer], 1},
           {:literal, [subtype: :integer], 2}
         ]}

      assert Nesting.calculate(ast) == 1
    end

    test "while loop has depth 1" do
      ast =
        {:loop, [loop_type: :while],
         [{:variable, [], "condition"}, {:literal, [subtype: :integer], 1}]}

      assert Nesting.calculate(ast) == 1
    end

    test "for loop has depth 1" do
      ast =
        {:loop, [loop_type: :for_each],
         [{:variable, [], "i"}, {:variable, [], "range"}, {:literal, [subtype: :integer], 1}]}

      assert Nesting.calculate(ast) == 1
    end

    test "lambda has depth 1" do
      ast = {:lambda, [params: ["x"], captures: []], [{:literal, [subtype: :integer], 1}]}
      assert Nesting.calculate(ast) == 1
    end

    test "exception handling has depth 1" do
      ast =
        {:exception_handling, [],
         [
           {:literal, [subtype: :integer], 1},
           [{:catch, {:variable, [], "error"}, {:literal, [subtype: :integer], 2}}],
           nil
         ]}

      assert Nesting.calculate(ast) == 1
    end

    test "pattern match has depth 1" do
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

      assert Nesting.calculate(ast) == 1
    end
  end

  describe "calculate/1 - nested structures" do
    test "nested conditionals have depth 2" do
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

      assert Nesting.calculate(ast) == 2
    end

    test "triple nested conditionals have depth 3" do
      ast =
        {:conditional, [],
         [
           {:variable, [], "x"},
           {:conditional, [],
            [
              {:variable, [], "y"},
              {:conditional, [],
               [
                 {:variable, [], "z"},
                 {:literal, [subtype: :integer], 1},
                 {:literal, [subtype: :integer], 2}
               ]},
              {:literal, [subtype: :integer], 3}
            ]},
           {:literal, [subtype: :integer], 4}
         ]}

      assert Nesting.calculate(ast) == 3
    end

    test "loop with conditional inside has depth 2" do
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

      assert Nesting.calculate(ast) == 2
    end

    test "nested loops have depth 2" do
      ast =
        {:loop, [loop_type: :while],
         [
           {:variable, [], "outer"},
           {:loop, [loop_type: :while],
            [{:variable, [], "inner"}, {:literal, [subtype: :integer], 1}]}
         ]}

      assert Nesting.calculate(ast) == 2
    end

    test "lambda with conditional inside has depth 2" do
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

      assert Nesting.calculate(ast) == 2
    end
  end

  describe "calculate/1 - complex nesting scenarios" do
    test "conditional in loop in conditional has depth 3" do
      # if a:
      #   while b:
      #     if c:
      ast =
        {:conditional, [],
         [
           {:variable, [], "a"},
           {:loop, [loop_type: :while],
            [
              {:variable, [], "b"},
              {:conditional, [],
               [
                 {:variable, [], "c"},
                 {:literal, [subtype: :integer], 1},
                 {:literal, [subtype: :integer], 2}
               ]}
            ]},
           {:literal, [subtype: :integer], 3}
         ]}

      assert Nesting.calculate(ast) == 3
    end

    test "multiple branches use max depth" do
      # if x:
      #   if y:
      #     if z:  <- depth 3
      # else:
      #   if a:  <- depth 2
      ast =
        {:conditional, [],
         [
           {:variable, [], "x"},
           {:conditional, [],
            [
              {:variable, [], "y"},
              {:conditional, [],
               [
                 {:variable, [], "z"},
                 {:literal, [subtype: :integer], 1},
                 {:literal, [subtype: :integer], 2}
               ]},
              {:literal, [subtype: :integer], 3}
            ]},
           {:conditional, [],
            [
              {:variable, [], "a"},
              {:literal, [subtype: :integer], 4},
              {:literal, [subtype: :integer], 5}
            ]}
         ]}

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
        {:block, [],
         [
           {:conditional, [],
            [
              {:variable, [], "x"},
              {:literal, [subtype: :integer], 1},
              {:literal, [subtype: :integer], 2}
            ]},
           {:conditional, [],
            [
              {:variable, [], "y"},
              {:conditional, [],
               [
                 {:variable, [], "z"},
                 {:literal, [subtype: :integer], 3},
                 {:literal, [subtype: :integer], 4}
               ]},
              {:literal, [subtype: :integer], 5}
            ]}
         ]}

      # First conditional: depth 1, Second nested conditional: depth 2 -> max = 2
      assert Nesting.calculate(ast) == 2
    end
  end

  describe "calculate/1 - exception handling and pattern matching" do
    test "nested exception handling" do
      ast =
        {:exception_handling, [],
         [
           {:literal, [subtype: :integer], 1},
           [
             {:catch, {:variable, [], "error"},
              {:exception_handling, [],
               [
                 {:literal, [subtype: :integer], 2},
                 [{:catch, {:variable, [], "inner_error"}, {:literal, [subtype: :integer], 3}}],
                 nil
               ]}}
           ],
           nil
         ]}

      assert Nesting.calculate(ast) == 2
    end

    test "pattern match with nested conditional" do
      ast =
        {:pattern_match, [],
         [
           {:variable, [], "value"},
           [
             {:pair, [],
              [
                {:literal, [subtype: :integer], 1},
                {:conditional, [],
                 [
                   {:variable, [], "x"},
                   {:literal, [subtype: :integer], 10},
                   {:literal, [subtype: :integer], 20}
                 ]}
              ]}
           ]
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
        {:conditional, [],
         [
           {:variable, [], "authenticated"},
           {:loop, [loop_type: :while],
            [
              {:variable, [], "processing"},
              {:loop, [loop_type: :for_each],
               [
                 {:variable, [], "item"},
                 {:variable, [], "items"},
                 {:conditional, [],
                  [
                    {:variable, [], "item_valid"},
                    {:conditional, [],
                     [
                       {:variable, [], "item_active"},
                       {:function_call, [name: "process"], [{:variable, [], "item"}]},
                       nil
                     ]},
                    nil
                  ]}
               ]}
            ]},
           nil
         ]}

      # Levels: conditional(1) -> while(2) -> for(3) -> if(4) -> if(5)
      assert Nesting.calculate(ast) == 5
    end
  end
end
