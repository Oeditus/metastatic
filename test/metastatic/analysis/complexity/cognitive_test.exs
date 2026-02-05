defmodule Metastatic.Analysis.Complexity.CognitiveTest do
  use ExUnit.Case, async: true

  alias Metastatic.Analysis.Complexity.Cognitive

  doctest Metastatic.Analysis.Complexity.Cognitive

  describe "calculate/1 - simple constructs" do
    test "literals have no cognitive complexity" do
      ast = {:literal, [subtype: :integer], 42}
      assert Cognitive.calculate(ast) == 0
    end

    test "variables have no cognitive complexity" do
      ast = {:variable, [], "x"}
      assert Cognitive.calculate(ast) == 0
    end

    test "arithmetic operations have no cognitive complexity" do
      ast =
        {:binary_op, [category: :arithmetic, operator: :+],
         [{:variable, [], "x"}, {:literal, [subtype: :integer], 5}]}

      assert Cognitive.calculate(ast) == 0
    end
  end

  describe "calculate/1 - conditionals with nesting" do
    test "single conditional has complexity 1" do
      ast =
        {:conditional, [],
         [
           {:variable, [], "x"},
           {:literal, [subtype: :integer], 1},
           {:literal, [subtype: :integer], 2}
         ]}

      assert Cognitive.calculate(ast) == 1
    end

    test "nested conditional adds nesting penalty" do
      # if x:
      #   if y:  <- +2 (1 base + 1 nesting)
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

      # Outer: +1, Inner: +2 (base 1 + nesting 1) = 3
      assert Cognitive.calculate(ast) == 3
    end

    test "deeply nested conditional increases penalty" do
      # if x:
      #   if y:
      #     if z:
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

      # Level 0: +1, Level 1: +2, Level 2: +3 = 6
      assert Cognitive.calculate(ast) == 6
    end
  end

  describe "calculate/1 - loops with nesting" do
    test "single loop has complexity 1" do
      ast =
        {:loop, [loop_type: :while],
         [{:variable, [], "condition"}, {:literal, [subtype: :integer], 1}]}

      assert Cognitive.calculate(ast) == 1
    end

    test "loop with conditional inside adds nesting penalty" do
      # while condition:
      #   if x:
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

      # Loop: +1, Conditional (nested): +2 = 3
      assert Cognitive.calculate(ast) == 3
    end

    test "nested loops add nesting penalties" do
      # while outer:
      #   while inner:
      ast =
        {:loop, [loop_type: :while],
         [
           {:variable, [], "outer"},
           {:loop, [loop_type: :while],
            [{:variable, [], "inner"}, {:literal, [subtype: :integer], 1}]}
         ]}

      # Outer: +1, Inner: +2 = 3
      assert Cognitive.calculate(ast) == 3
    end
  end

  describe "calculate/1 - boolean operators" do
    test "and operator adds complexity without nesting penalty" do
      ast =
        {:binary_op, [category: :boolean, operator: :and],
         [{:variable, [], "x"}, {:variable, [], "y"}]}

      assert Cognitive.calculate(ast) == 1
    end

    test "or operator adds complexity without nesting penalty" do
      ast =
        {:binary_op, [category: :boolean, operator: :or],
         [{:variable, [], "x"}, {:variable, [], "y"}]}

      assert Cognitive.calculate(ast) == 1
    end

    test "multiple boolean operators add complexity each" do
      ast =
        {:binary_op, [category: :boolean, operator: :and],
         [
           {:binary_op, [category: :boolean, operator: :or],
            [{:variable, [], "x"}, {:variable, [], "y"}]},
           {:variable, [], "z"}
         ]}

      # or: +1, and: +1 = 2
      assert Cognitive.calculate(ast) == 2
    end

    test "boolean operators in nested conditional don't get nesting penalty" do
      ast =
        {:conditional, [],
         [
           {:variable, [], "a"},
           {:conditional, [],
            [
              {:binary_op, [category: :boolean, operator: :and],
               [{:variable, [], "x"}, {:variable, [], "y"}]},
              {:literal, [subtype: :integer], 1},
              {:literal, [subtype: :integer], 2}
            ]},
           {:literal, [subtype: :integer], 3}
         ]}

      # Outer conditional: +1
      # Inner conditional: +2 (1 + 1 nesting)
      # Boolean and: +1 (no nesting penalty)
      # Total: 4
      assert Cognitive.calculate(ast) == 4
    end
  end

  describe "calculate/1 - exception handling" do
    test "try/catch has complexity 1" do
      ast =
        {:exception_handling, [],
         [
           {:literal, [subtype: :integer], 1},
           [{:catch, {:variable, [], "error"}, {:literal, [subtype: :integer], 2}}],
           nil
         ]}

      assert Cognitive.calculate(ast) == 1
    end

    test "nested exception handling adds penalty" do
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

      # Outer: +1, Inner: +2 = 3
      assert Cognitive.calculate(ast) == 3
    end
  end

  describe "calculate/1 - pattern matching" do
    test "pattern match branches each add complexity with nesting" do
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

      # Two branches, each +1 = 2
      assert Cognitive.calculate(ast) == 2
    end

    test "nested pattern match adds nesting penalties" do
      ast =
        {:pattern_match, [],
         [
           {:variable, [], "outer"},
           [
             {:pair, [],
              [
                {:literal, [subtype: :integer], 1},
                {:pattern_match, [],
                 [
                   {:variable, [], "inner"},
                   [
                     {:pair, [],
                      [{:literal, [subtype: :integer], 10}, {:literal, [subtype: :string], "ten"}]},
                     {:pair, [],
                      [
                        {:literal, [subtype: :integer], 20},
                        {:literal, [subtype: :string], "twenty"}
                      ]}
                   ]
                 ]}
              ]}
           ]
         ]}

      # Outer branch: +1
      # Inner branch 1: +2 (1 + 1 nesting)
      # Inner branch 2: +2 (1 + 1 nesting)
      # Total: 5
      assert Cognitive.calculate(ast) == 5
    end
  end

  describe "calculate/1 - comparison with cyclomatic" do
    test "simple code has similar cognitive and cyclomatic complexity" do
      alias Metastatic.Analysis.Complexity.Cyclomatic

      ast =
        {:conditional, [],
         [
           {:variable, [], "x"},
           {:literal, [subtype: :integer], 1},
           {:literal, [subtype: :integer], 2}
         ]}

      cognitive = Cognitive.calculate(ast)
      cyclomatic = Cyclomatic.calculate(ast)

      # Cognitive: 1, Cyclomatic: 2 (base + decision)
      assert cognitive == 1
      assert cyclomatic == 2
    end

    test "nested code has higher cognitive than cyclomatic difference" do
      alias Metastatic.Analysis.Complexity.Cyclomatic

      # Deeply nested: if x: if y: if z:
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

      cognitive = Cognitive.calculate(ast)
      cyclomatic = Cyclomatic.calculate(ast)

      # Cognitive: 1 + 2 + 3 = 6 (nesting penalties)
      # Cyclomatic: 1 + 3 = 4 (just decision points)
      assert cognitive == 6
      assert cyclomatic == 4
      assert cognitive > cyclomatic
    end
  end

  describe "calculate/1 - lambdas and collections" do
    test "lambda increases nesting for body" do
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

      # Conditional inside lambda: +2 (1 + 1 nesting from lambda)
      assert Cognitive.calculate(ast) == 2
    end

    test "collection operation with nested conditional" do
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

      # Lambda adds nesting, conditional: +2
      assert Cognitive.calculate(ast) == 2
    end
  end
end
