defmodule Metastatic.ASTTest do
  use ExUnit.Case, async: true

  alias Metastatic.AST

  doctest Metastatic.AST

  describe "M2.1 Core conformance/1" do
    test "literal integer" do
      ast = {:literal, [subtype: :integer], 42}
      assert AST.conforms?(ast)
    end

    test "literal string" do
      ast = {:literal, [subtype: :string], "hello"}
      assert AST.conforms?(ast)
    end

    test "literal float" do
      ast = {:literal, [subtype: :float], 3.14}
      assert AST.conforms?(ast)
    end

    test "literal boolean" do
      assert AST.conforms?({:literal, [subtype: :boolean], true})
      assert AST.conforms?({:literal, [subtype: :boolean], false})
    end

    test "literal null" do
      ast = {:literal, [subtype: :null], nil}
      assert AST.conforms?(ast)
    end

    test "variable" do
      ast = {:variable, [], "x"}
      assert AST.conforms?(ast)
    end

    test "binary_op arithmetic" do
      ast =
        {:binary_op, [category: :arithmetic, operator: :+],
         [{:variable, [], "x"}, {:literal, [subtype: :integer], 5}]}

      assert AST.conforms?(ast)
    end

    test "binary_op comparison" do
      ast =
        {:binary_op, [category: :comparison, operator: :>],
         [{:variable, [], "x"}, {:literal, [subtype: :integer], 0}]}

      assert AST.conforms?(ast)
    end

    test "binary_op boolean" do
      ast =
        {:binary_op, [category: :boolean, operator: :and],
         [{:variable, [], "a"}, {:variable, [], "b"}]}

      assert AST.conforms?(ast)
    end

    test "unary_op arithmetic" do
      ast = {:unary_op, [category: :arithmetic, operator: :-], [{:variable, [], "x"}]}
      assert AST.conforms?(ast)
    end

    test "unary_op boolean" do
      ast = {:unary_op, [category: :boolean, operator: :not], [{:variable, [], "flag"}]}
      assert AST.conforms?(ast)
    end

    test "function_call" do
      ast =
        {:function_call, [name: "add"],
         [
           {:variable, [], "x"},
           {:variable, [], "y"}
         ]}

      assert AST.conforms?(ast)
    end

    test "function_call with no arguments" do
      ast = {:function_call, [name: "get_value"], []}
      assert AST.conforms?(ast)
    end

    test "conditional" do
      ast =
        {:conditional, [],
         [
           {:binary_op, [category: :comparison, operator: :>],
            [{:variable, [], "x"}, {:literal, [subtype: :integer], 0}]},
           {:literal, [subtype: :integer], 1},
           {:literal, [subtype: :integer], -1}
         ]}

      assert AST.conforms?(ast)
    end

    test "early_return" do
      ast = {:early_return, [], [{:variable, [], "result"}]}
      assert AST.conforms?(ast)
    end

    test "block" do
      ast =
        {:block, [],
         [
           {:variable, [], "x"},
           {:variable, [], "y"},
           {:binary_op, [category: :arithmetic, operator: :+],
            [{:variable, [], "x"}, {:variable, [], "y"}]}
         ]}

      assert AST.conforms?(ast)
    end

    test "assignment simple" do
      ast = {:assignment, [], [{:variable, [], "x"}, {:literal, [subtype: :integer], 5}]}
      assert AST.conforms?(ast)
    end

    test "assignment tuple unpacking" do
      ast =
        {:assignment, [],
         [
           {:tuple, [], [{:variable, [], "x"}, {:variable, [], "y"}]},
           {:tuple, [], [{:literal, [subtype: :integer], 1}, {:literal, [subtype: :integer], 2}]}
         ]}

      assert AST.conforms?(ast)
    end

    test "assignment augmented (desugared)" do
      # x += 1 desugared to x = x + 1
      ast =
        {:assignment, [],
         [
           {:variable, [], "x"},
           {:binary_op, [category: :arithmetic, operator: :+],
            [{:variable, [], "x"}, {:literal, [subtype: :integer], 1}]}
         ]}

      assert AST.conforms?(ast)
    end

    test "inline_match simple" do
      ast = {:inline_match, [], [{:variable, [], "x"}, {:literal, [subtype: :integer], 5}]}
      assert AST.conforms?(ast)
    end

    test "inline_match tuple destructuring" do
      ast =
        {:inline_match, [],
         [
           {:tuple, [], [{:variable, [], "x"}, {:variable, [], "y"}]},
           {:tuple, [], [{:literal, [subtype: :integer], 1}, {:literal, [subtype: :integer], 2}]}
         ]}

      assert AST.conforms?(ast)
    end

    test "inline_match nested pattern" do
      # {:ok, value} = result
      ast =
        {:inline_match, [],
         [
           {:tuple, [], [{:literal, [subtype: :symbol], :ok}, {:variable, [], "value"}]},
           {:variable, [], "result"}
         ]}

      assert AST.conforms?(ast)
    end

    test "list empty" do
      ast = {:list, [], []}
      assert AST.conforms?(ast)
    end

    test "list with literals" do
      ast =
        {:list, [],
         [
           {:literal, [subtype: :integer], 1},
           {:literal, [subtype: :integer], 2},
           {:literal, [subtype: :integer], 3}
         ]}

      assert AST.conforms?(ast)
    end

    test "list with variables" do
      ast = {:list, [], [{:variable, [], "x"}, {:variable, [], "y"}]}
      assert AST.conforms?(ast)
    end

    test "list nested" do
      ast =
        {:list, [],
         [
           {:list, [], [{:literal, [subtype: :integer], 1}]},
           {:list, [], [{:literal, [subtype: :integer], 2}]}
         ]}

      assert AST.conforms?(ast)
    end

    test "map empty" do
      ast = {:map, [], []}
      assert AST.conforms?(ast)
    end

    test "map with literal keys and values" do
      ast =
        {:map, [],
         [
           {:pair, [],
            [{:literal, [subtype: :string], "name"}, {:literal, [subtype: :string], "Alice"}]},
           {:pair, [],
            [{:literal, [subtype: :string], "age"}, {:literal, [subtype: :integer], 30}]}
         ]}

      assert AST.conforms?(ast)
    end

    test "map with variable keys and values" do
      ast = {:map, [], [{:pair, [], [{:variable, [], "key"}, {:variable, [], "value"}]}]}
      assert AST.conforms?(ast)
    end

    test "map nested" do
      ast =
        {:map, [],
         [
           {:pair, [],
            [
              {:literal, [subtype: :string], "user"},
              {:map, [],
               [
                 {:pair, [],
                  [{:literal, [subtype: :string], "name"}, {:literal, [subtype: :string], "Bob"}]}
               ]}
            ]}
         ]}

      assert AST.conforms?(ast)
    end

    test "complex nested expression" do
      # ((x + 5) * y) > 10
      ast =
        {:binary_op, [category: :comparison, operator: :>],
         [
           {:binary_op, [category: :arithmetic, operator: :*],
            [
              {:binary_op, [category: :arithmetic, operator: :+],
               [{:variable, [], "x"}, {:literal, [subtype: :integer], 5}]},
              {:variable, [], "y"}
            ]},
           {:literal, [subtype: :integer], 10}
         ]}

      assert AST.conforms?(ast)
    end
  end

  describe "M2.2 Extended conformance/1" do
    test "loop while" do
      ast =
        {:loop, [loop_type: :while],
         [
           {:binary_op, [category: :comparison, operator: :>],
            [{:variable, [], "x"}, {:literal, [subtype: :integer], 0}]},
           {:block, [], [{:variable, [], "x"}]}
         ]}

      assert AST.conforms?(ast)
    end

    test "loop for" do
      ast =
        {:loop, [loop_type: :for],
         [
           {:variable, [], "item"},
           {:variable, [], "collection"},
           {:block, [], [{:variable, [], "item"}]}
         ]}

      assert AST.conforms?(ast)
    end

    test "lambda" do
      ast =
        {:lambda, [params: ["x", "y"], captures: []],
         [
           {:binary_op, [category: :arithmetic, operator: :+],
            [{:variable, [], "x"}, {:variable, [], "y"}]}
         ]}

      assert AST.conforms?(ast)
    end

    test "lambda with captures" do
      ast =
        {:lambda, [params: ["x"], captures: ["offset"]],
         [
           {:binary_op, [category: :arithmetic, operator: :+],
            [{:variable, [], "x"}, {:variable, [], "offset"}]}
         ]}

      assert AST.conforms?(ast)
    end

    test "collection_op map" do
      ast =
        {:collection_op, [op_type: :map],
         [
           {:lambda, [params: ["x"], captures: []],
            [
              {:binary_op, [category: :arithmetic, operator: :*],
               [{:variable, [], "x"}, {:literal, [subtype: :integer], 2}]}
            ]},
           {:variable, [], "list"}
         ]}

      assert AST.conforms?(ast)
    end

    test "collection_op filter" do
      ast =
        {:collection_op, [op_type: :filter],
         [
           {:lambda, [params: ["x"], captures: []],
            [
              {:binary_op, [category: :comparison, operator: :>],
               [{:variable, [], "x"}, {:literal, [subtype: :integer], 0}]}
            ]},
           {:variable, [], "list"}
         ]}

      assert AST.conforms?(ast)
    end

    test "collection_op reduce" do
      ast =
        {:collection_op, [op_type: :reduce],
         [
           {:lambda, [params: ["acc", "x"], captures: []],
            [
              {:binary_op, [category: :arithmetic, operator: :+],
               [{:variable, [], "acc"}, {:variable, [], "x"}]}
            ]},
           {:variable, [], "list"},
           {:literal, [subtype: :integer], 0}
         ]}

      assert AST.conforms?(ast)
    end

    test "pattern_match" do
      ast =
        {:pattern_match, [],
         [
           {:variable, [], "x"},
           [
             {{:literal, [subtype: :integer], 0}, {:literal, [subtype: :string], "zero"}},
             {{:literal, [subtype: :integer], 1}, {:literal, [subtype: :string], "one"}},
             {:_, {:literal, [subtype: :string], "other"}}
           ]
         ]}

      assert AST.conforms?(ast)
    end

    test "exception_handling" do
      ast =
        {:exception_handling, [],
         [
           {:block, [], [{:function_call, [name: "risky"], []}]},
           [
             {:error, {:variable, [], "e"},
              {:function_call, [name: "handle"], [{:variable, [], "e"}]}}
           ],
           {:function_call, [name: "cleanup"], []}
         ]}

      assert AST.conforms?(ast)
    end

    test "async_operation" do
      ast =
        {:async_operation, [op_type: :await],
         [{:function_call, [name: "fetch_data"], [{:literal, [subtype: :string], "url"}]}]}

      assert AST.conforms?(ast)
    end
  end

  describe "M2.3 Native conformance/1" do
    test "language_specific Python list comprehension" do
      ast =
        {:language_specific, [language: :python],
         %{
           construct: :list_comprehension,
           data: "[x * 2 for x in range(10)]"
         }}

      assert AST.conforms?(ast)
    end

    test "language_specific JavaScript spread" do
      ast =
        {:language_specific, [language: :javascript],
         %{
           construct: :spread_operator,
           data: "...args"
         }}

      assert AST.conforms?(ast)
    end
  end

  describe "non-conforming ASTs" do
    test "invalid meta-type" do
      ast = {:invalid_type, "data"}
      refute AST.conforms?(ast)
    end

    test "malformed literal" do
      ast = {:literal, 42}
      refute AST.conforms?(ast)
    end

    test "malformed variable" do
      ast = {:variable}
      refute AST.conforms?(ast)
    end

    test "malformed binary_op" do
      ast = {:binary_op, :+, {:variable, [], "x"}}
      refute AST.conforms?(ast)
    end

    test "atom instead of tuple" do
      refute AST.conforms?(:not_a_tuple)
    end

    test "string instead of AST" do
      refute AST.conforms?("not an ast")
    end
  end

  describe "variables/1" do
    test "single variable" do
      ast = {:variable, [], "x"}
      assert AST.variables(ast) == MapSet.new(["x"])
    end

    test "binary operation with variables" do
      ast =
        {:binary_op, [category: :arithmetic, operator: :+],
         [{:variable, [], "x"}, {:variable, [], "y"}]}

      assert AST.variables(ast) == MapSet.new(["x", "y"])
    end

    test "duplicate variables counted once" do
      ast =
        {:binary_op, [category: :arithmetic, operator: :+],
         [{:variable, [], "x"}, {:variable, [], "x"}]}

      assert AST.variables(ast) == MapSet.new(["x"])
    end

    test "nested expression with multiple variables" do
      # (x + y) * z
      ast =
        {:binary_op, [category: :arithmetic, operator: :*],
         [
           {:binary_op, [category: :arithmetic, operator: :+],
            [{:variable, [], "x"}, {:variable, [], "y"}]},
           {:variable, [], "z"}
         ]}

      assert AST.variables(ast) == MapSet.new(["x", "y", "z"])
    end

    test "function call with variables" do
      ast =
        {:function_call, [name: "add"],
         [
           {:variable, [], "a"},
           {:variable, [], "b"}
         ]}

      assert AST.variables(ast) == MapSet.new(["a", "b"])
    end

    test "block with variables" do
      ast =
        {:block, [],
         [
           {:variable, [], "x"},
           {:variable, [], "y"},
           {:binary_op, [category: :arithmetic, operator: :+],
            [{:variable, [], "x"}, {:variable, [], "y"}]}
         ]}

      assert AST.variables(ast) == MapSet.new(["x", "y"])
    end

    test "lambda with parameters and captures" do
      ast =
        {:lambda, [params: ["x"], captures: ["offset"]],
         [
           {:binary_op, [category: :arithmetic, operator: :+],
            [{:variable, [], "x"}, {:variable, [], "offset"}]}
         ]}

      # Lambda parameters and captures are included
      assert AST.variables(ast) == MapSet.new(["x", "offset"])
    end

    test "no variables in literal" do
      ast = {:literal, [subtype: :integer], 42}
      assert AST.variables(ast) == MapSet.new([])
    end

    test "assignment with variables" do
      # x = y + 5
      ast =
        {:assignment, [],
         [
           {:variable, [], "x"},
           {:binary_op, [category: :arithmetic, operator: :+],
            [{:variable, [], "y"}, {:literal, [subtype: :integer], 5}]}
         ]}

      assert AST.variables(ast) == MapSet.new(["x", "y"])
    end

    test "assignment with tuple unpacking" do
      # x, y = a, b
      ast =
        {:assignment, [],
         [
           {:tuple, [], [{:variable, [], "x"}, {:variable, [], "y"}]},
           {:tuple, [], [{:variable, [], "a"}, {:variable, [], "b"}]}
         ]}

      assert AST.variables(ast) == MapSet.new(["x", "y", "a", "b"])
    end

    test "inline_match with variables" do
      # x = y + 5
      ast =
        {:inline_match, [],
         [
           {:variable, [], "x"},
           {:binary_op, [category: :arithmetic, operator: :+],
            [{:variable, [], "y"}, {:literal, [subtype: :integer], 5}]}
         ]}

      assert AST.variables(ast) == MapSet.new(["x", "y"])
    end

    test "inline_match with pattern" do
      # {x, y} = result
      ast =
        {:inline_match, [],
         [
           {:tuple, [], [{:variable, [], "x"}, {:variable, [], "y"}]},
           {:variable, [], "result"}
         ]}

      assert AST.variables(ast) == MapSet.new(["x", "y", "result"])
    end

    test "list with variables" do
      ast = {:list, [], [{:variable, [], "x"}, {:variable, [], "y"}, {:variable, [], "z"}]}
      assert AST.variables(ast) == MapSet.new(["x", "y", "z"])
    end

    test "list with nested expressions" do
      # [x + 1, y * 2]
      ast =
        {:list, [],
         [
           {:binary_op, [category: :arithmetic, operator: :+],
            [{:variable, [], "x"}, {:literal, [subtype: :integer], 1}]},
           {:binary_op, [category: :arithmetic, operator: :*],
            [{:variable, [], "y"}, {:literal, [subtype: :integer], 2}]}
         ]}

      assert AST.variables(ast) == MapSet.new(["x", "y"])
    end

    test "map with variable keys and values" do
      ast =
        {:map, [],
         [
           {:pair, [], [{:variable, [], "key1"}, {:variable, [], "value1"}]},
           {:pair, [], [{:variable, [], "key2"}, {:variable, [], "value2"}]}
         ]}

      assert AST.variables(ast) == MapSet.new(["key1", "value1", "key2", "value2"])
    end

    test "map with literal keys and variable values" do
      # %{"name" => name, "age" => age}
      ast =
        {:map, [],
         [
           {:pair, [], [{:literal, [subtype: :string], "name"}, {:variable, [], "name"}]},
           {:pair, [], [{:literal, [subtype: :string], "age"}, {:variable, [], "age"}]}
         ]}

      assert AST.variables(ast) == MapSet.new(["name", "age"])
    end

    test "nested list and map" do
      # [%{"key" => x}]
      ast =
        {:list, [],
         [
           {:map, [],
            [{:pair, [], [{:literal, [subtype: :string], "key"}, {:variable, [], "x"}]}]}
         ]}

      assert AST.variables(ast) == MapSet.new(["x"])
    end
  end
end
