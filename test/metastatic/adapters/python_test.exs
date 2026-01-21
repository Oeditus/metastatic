defmodule Metastatic.Adapters.PythonTest do
  use ExUnit.Case, async: true

  alias Metastatic.Adapters.Python
  alias Metastatic.Adapters.Python.{ToMeta, FromMeta}

  describe "parse/1" do
    test "parses simple expression" do
      assert {:ok, ast} = Python.parse("x + 5")
      assert %{"_type" => "Module", "body" => _} = ast
    end

    test "returns error for invalid syntax" do
      assert {:error, error} = Python.parse("x +")
      assert error =~ "SyntaxError"
    end

    test "parses function call" do
      assert {:ok, ast} = Python.parse("foo(1, 2)")
      assert %{"_type" => "Module"} = ast
    end
  end

  describe "ToMeta - literals" do
    test "transforms integer literals" do
      ast = %{"_type" => "Constant", "value" => 42}
      assert {:ok, {:literal, :integer, 42}, %{}} = ToMeta.transform(ast)
    end

    test "transforms float literals" do
      ast = %{"_type" => "Constant", "value" => 3.14}
      assert {:ok, {:literal, :float, 3.14}, %{}} = ToMeta.transform(ast)
    end

    test "transforms string literals" do
      ast = %{"_type" => "Constant", "value" => "hello"}
      assert {:ok, {:literal, :string, "hello"}, %{}} = ToMeta.transform(ast)
    end

    test "transforms boolean true" do
      ast = %{"_type" => "Constant", "value" => true}
      assert {:ok, {:literal, :boolean, true}, %{}} = ToMeta.transform(ast)
    end

    test "transforms boolean false" do
      ast = %{"_type" => "Constant", "value" => false}
      assert {:ok, {:literal, :boolean, false}, %{}} = ToMeta.transform(ast)
    end

    test "transforms None to null" do
      ast = %{"_type" => "Constant", "value" => nil}
      assert {:ok, {:literal, :null, nil}, %{}} = ToMeta.transform(ast)
    end

    test "transforms list literals" do
      ast = %{
        "_type" => "List",
        "elts" => [
          %{"_type" => "Constant", "value" => 1},
          %{"_type" => "Constant", "value" => 2}
        ]
      }

      assert {:ok, {:literal, :collection, elements}, _} = ToMeta.transform(ast)
      assert [{:literal, :integer, 1}, {:literal, :integer, 2}] = elements
    end
  end

  describe "ToMeta - variables" do
    test "transforms variable references" do
      ast = %{"_type" => "Name", "id" => "x"}
      assert {:ok, {:variable, "x"}, %{}} = ToMeta.transform(ast)
    end

    test "transforms different variable names" do
      ast = %{"_type" => "Name", "id" => "my_var"}
      assert {:ok, {:variable, "my_var"}, %{}} = ToMeta.transform(ast)
    end
  end

  describe "ToMeta - binary operators" do
    test "transforms addition" do
      ast = %{
        "_type" => "BinOp",
        "op" => %{"_type" => "Add"},
        "left" => %{"_type" => "Name", "id" => "x"},
        "right" => %{"_type" => "Constant", "value" => 5}
      }

      assert {:ok, {:binary_op, :arithmetic, :+, left, right}, %{}} = ToMeta.transform(ast)
      assert {:variable, "x"} = left
      assert {:literal, :integer, 5} = right
    end

    test "transforms subtraction" do
      ast = %{
        "_type" => "BinOp",
        "op" => %{"_type" => "Sub"},
        "left" => %{"_type" => "Constant", "value" => 10},
        "right" => %{"_type" => "Name", "id" => "y"}
      }

      assert {:ok, {:binary_op, :arithmetic, :-, left, right}, %{}} = ToMeta.transform(ast)
      assert {:literal, :integer, 10} = left
      assert {:variable, "y"} = right
    end

    test "transforms multiplication and division" do
      mult_ast = %{
        "_type" => "BinOp",
        "op" => %{"_type" => "Mult"},
        "left" => %{"_type" => "Constant", "value" => 2},
        "right" => %{"_type" => "Constant", "value" => 3}
      }

      assert {:ok, {:binary_op, :arithmetic, :*, _, _}, %{}} = ToMeta.transform(mult_ast)

      div_ast = %{
        "_type" => "BinOp",
        "op" => %{"_type" => "Div"},
        "left" => %{"_type" => "Constant", "value" => 10},
        "right" => %{"_type" => "Constant", "value" => 2}
      }

      assert {:ok, {:binary_op, :arithmetic, :/, _, _}, %{}} = ToMeta.transform(div_ast)
    end

    test "transforms modulo and floor division" do
      mod_ast = %{
        "_type" => "BinOp",
        "op" => %{"_type" => "Mod"},
        "left" => %{"_type" => "Constant", "value" => 10},
        "right" => %{"_type" => "Constant", "value" => 3}
      }

      assert {:ok, {:binary_op, :arithmetic, :rem, _, _}, %{}} = ToMeta.transform(mod_ast)

      floor_div_ast = %{
        "_type" => "BinOp",
        "op" => %{"_type" => "FloorDiv"},
        "left" => %{"_type" => "Constant", "value" => 10},
        "right" => %{"_type" => "Constant", "value" => 3}
      }

      assert {:ok, {:binary_op, :arithmetic, :div, _, _}, %{}} = ToMeta.transform(floor_div_ast)
    end
  end

  describe "ToMeta - comparison operators" do
    test "transforms equality comparison" do
      ast = %{
        "_type" => "Compare",
        "left" => %{"_type" => "Name", "id" => "x"},
        "ops" => [%{"_type" => "Eq"}],
        "comparators" => [%{"_type" => "Constant", "value" => 5}]
      }

      assert {:ok, {:binary_op, :comparison, :==, _, _}, %{}} = ToMeta.transform(ast)
    end

    test "transforms inequality comparison" do
      ast = %{
        "_type" => "Compare",
        "left" => %{"_type" => "Name", "id" => "x"},
        "ops" => [%{"_type" => "NotEq"}],
        "comparators" => [%{"_type" => "Constant", "value" => 5}]
      }

      assert {:ok, {:binary_op, :comparison, :!=, _, _}, %{}} = ToMeta.transform(ast)
    end

    test "transforms less than and greater than" do
      lt_ast = %{
        "_type" => "Compare",
        "left" => %{"_type" => "Name", "id" => "x"},
        "ops" => [%{"_type" => "Lt"}],
        "comparators" => [%{"_type" => "Constant", "value" => 5}]
      }

      assert {:ok, {:binary_op, :comparison, :<, _, _}, %{}} = ToMeta.transform(lt_ast)

      gt_ast = %{
        "_type" => "Compare",
        "left" => %{"_type" => "Name", "id" => "x"},
        "ops" => [%{"_type" => "Gt"}],
        "comparators" => [%{"_type" => "Constant", "value" => 5}]
      }

      assert {:ok, {:binary_op, :comparison, :>, _, _}, %{}} = ToMeta.transform(gt_ast)
    end
  end

  describe "ToMeta - boolean operators" do
    test "transforms and operator" do
      ast = %{
        "_type" => "BoolOp",
        "op" => %{"_type" => "And"},
        "values" => [
          %{"_type" => "Constant", "value" => true},
          %{"_type" => "Constant", "value" => false}
        ]
      }

      assert {:ok, {:binary_op, :boolean, :and, _, _}, %{}} = ToMeta.transform(ast)
    end

    test "transforms or operator" do
      ast = %{
        "_type" => "BoolOp",
        "op" => %{"_type" => "Or"},
        "values" => [
          %{"_type" => "Constant", "value" => true},
          %{"_type" => "Constant", "value" => false}
        ]
      }

      assert {:ok, {:binary_op, :boolean, :or, _, _}, %{}} = ToMeta.transform(ast)
    end

    test "chains multiple boolean operations" do
      ast = %{
        "_type" => "BoolOp",
        "op" => %{"_type" => "And"},
        "values" => [
          %{"_type" => "Name", "id" => "a"},
          %{"_type" => "Name", "id" => "b"},
          %{"_type" => "Name", "id" => "c"}
        ]
      }

      assert {:ok, {:binary_op, :boolean, :and, _, _}, %{}} = ToMeta.transform(ast)
    end
  end

  describe "ToMeta - unary operators" do
    test "transforms logical not" do
      ast = %{
        "_type" => "UnaryOp",
        "op" => %{"_type" => "Not"},
        "operand" => %{"_type" => "Constant", "value" => true}
      }

      assert {:ok, {:unary_op, :boolean, :not, operand}, %{}} = ToMeta.transform(ast)
      assert {:literal, :boolean, true} = operand
    end

    test "transforms unary minus" do
      ast = %{
        "_type" => "UnaryOp",
        "op" => %{"_type" => "USub"},
        "operand" => %{"_type" => "Constant", "value" => 42}
      }

      assert {:ok, {:unary_op, :arithmetic, :-, operand}, %{}} = ToMeta.transform(ast)
      assert {:literal, :integer, 42} = operand
    end

    test "transforms unary plus" do
      ast = %{
        "_type" => "UnaryOp",
        "op" => %{"_type" => "UAdd"},
        "operand" => %{"_type" => "Constant", "value" => 42}
      }

      assert {:ok, {:unary_op, :arithmetic, :+, operand}, %{}} = ToMeta.transform(ast)
      assert {:literal, :integer, 42} = operand
    end
  end

  describe "ToMeta - function calls" do
    test "transforms simple function call" do
      ast = %{
        "_type" => "Call",
        "func" => %{"_type" => "Name", "id" => "foo"},
        "args" => [
          %{"_type" => "Constant", "value" => 1},
          %{"_type" => "Constant", "value" => 2}
        ]
      }

      assert {:ok, {:function_call, "foo", args}, %{}} = ToMeta.transform(ast)
      assert [_, _] = args
    end

    test "transforms method call" do
      ast = %{
        "_type" => "Call",
        "func" => %{
          "_type" => "Attribute",
          "value" => %{"_type" => "Name", "id" => "obj"},
          "attr" => "method"
        },
        "args" => []
      }

      assert {:ok, {:function_call, "obj.method", []}, %{}} = ToMeta.transform(ast)
    end
  end

  describe "ToMeta - conditionals" do
    test "transforms if expression (ternary)" do
      ast = %{
        "_type" => "IfExp",
        "test" => %{"_type" => "Constant", "value" => true},
        "body" => %{"_type" => "Constant", "value" => 1},
        "orelse" => %{"_type" => "Constant", "value" => 2}
      }

      assert {:ok, {:conditional, condition, then_branch, else_branch}, %{}} =
               ToMeta.transform(ast)

      assert {:literal, :boolean, true} = condition
      assert {:literal, :integer, 1} = then_branch
      assert {:literal, :integer, 2} = else_branch
    end
  end

  describe "ToMeta - modules and blocks" do
    test "transforms module with single expression" do
      ast = %{
        "_type" => "Module",
        "body" => [
          %{"_type" => "Expr", "value" => %{"_type" => "Constant", "value" => 42}}
        ]
      }

      assert {:ok, {:literal, :integer, 42}, %{}} = ToMeta.transform(ast)
    end

    test "transforms module with multiple expressions" do
      ast = %{
        "_type" => "Module",
        "body" => [
          %{"_type" => "Expr", "value" => %{"_type" => "Constant", "value" => 1}},
          %{"_type" => "Expr", "value" => %{"_type" => "Constant", "value" => 2}}
        ]
      }

      assert {:ok, {:block, statements}, %{}} = ToMeta.transform(ast)
      assert [_, _] = statements
    end
  end

  describe "FromMeta - literals" do
    test "transforms integer literals back" do
      assert {:ok, %{"_type" => "Constant", "value" => 42}} =
               FromMeta.transform({:literal, :integer, 42}, %{})
    end

    test "transforms string literals back" do
      assert {:ok, %{"_type" => "Constant", "value" => "hello"}} =
               FromMeta.transform({:literal, :string, "hello"}, %{})
    end

    test "transforms boolean literals back" do
      assert {:ok, %{"_type" => "Constant", "value" => true}} =
               FromMeta.transform({:literal, :boolean, true}, %{})
    end

    test "transforms null back" do
      assert {:ok, %{"_type" => "Constant", "value" => nil}} =
               FromMeta.transform({:literal, :null, nil}, %{})
    end
  end

  describe "FromMeta - variables" do
    test "transforms variables back" do
      assert {:ok, %{"_type" => "Name", "id" => "x"}} =
               FromMeta.transform({:variable, "x"}, %{})
    end
  end

  describe "FromMeta - operators" do
    test "transforms arithmetic operators back" do
      meta_ast = {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}}

      assert {:ok, %{"_type" => "BinOp", "op" => %{"_type" => "Add"}}} =
               FromMeta.transform(meta_ast, %{})
    end

    test "transforms comparison operators back" do
      meta_ast = {:binary_op, :comparison, :==, {:variable, "x"}, {:literal, :integer, 5}}

      assert {:ok, %{"_type" => "Compare", "ops" => [%{"_type" => "Eq"}]}} =
               FromMeta.transform(meta_ast, %{})
    end

    test "transforms boolean operators back" do
      meta_ast =
        {:binary_op, :boolean, :and, {:literal, :boolean, true}, {:literal, :boolean, false}}

      assert {:ok, %{"_type" => "BoolOp", "op" => %{"_type" => "And"}}} =
               FromMeta.transform(meta_ast, %{})
    end
  end

  describe "FromMeta - function calls" do
    test "transforms simple function calls back" do
      meta_ast = {:function_call, "foo", [{:literal, :integer, 1}]}

      assert {:ok, %{"_type" => "Call", "func" => %{"_type" => "Name", "id" => "foo"}}} =
               FromMeta.transform(meta_ast, %{})
    end

    test "transforms method calls back" do
      meta_ast = {:function_call, "obj.method", []}

      assert {:ok, %{"_type" => "Call", "func" => %{"_type" => "Attribute"}}} =
               FromMeta.transform(meta_ast, %{})
    end
  end

  describe "round-trip transformations" do
    test "round-trips simple expression through subprocess" do
      source = "x + 5"
      assert {:ok, ast} = Python.parse(source)
      assert {:ok, meta_ast, metadata} = Python.to_meta(ast)
      assert {:ok, ast2} = Python.from_meta(meta_ast, metadata)
      assert {:ok, result} = Python.unparse(ast2)

      # May have whitespace differences
      assert String.trim(result) == String.trim(source)
    end

    test "round-trips function call" do
      source = "foo(1, 2)"
      assert {:ok, ast} = Python.parse(source)
      assert {:ok, meta_ast, _metadata} = Python.to_meta(ast)
      assert {:function_call, "foo", args} = meta_ast
      assert [_, _] = args
    end

    test "round-trips comparison" do
      source = "x == 5"
      assert {:ok, ast} = Python.parse(source)
      assert {:ok, meta_ast, _metadata} = Python.to_meta(ast)
      assert {:binary_op, :comparison, :==, {:variable, "x"}, {:literal, :integer, 5}} = meta_ast
    end

    test "round-trips boolean expression" do
      source = "True and False"
      assert {:ok, ast} = Python.parse(source)
      assert {:ok, meta_ast, _metadata} = Python.to_meta(ast)
      assert {:binary_op, :boolean, :and, _, _} = meta_ast
    end
  end

  describe "ToMeta - Extended Layer: Loops" do
    test "transforms while loop" do
      source = "while x > 0:\n    x"

      assert {:ok, ast} = Python.parse(source)
      assert {:ok, {:loop, :while, condition, body}, _metadata} = Python.to_meta(ast)
      assert {:binary_op, :comparison, :>, _, _} = condition
      assert {:variable, "x"} = body
    end

    test "transforms for loop" do
      source = "for i in items:\n    i"

      assert {:ok, ast} = Python.parse(source)

      assert {:ok, {:loop, :for_each, iterator, collection, body}, _metadata} =
               Python.to_meta(ast)

      assert {:variable, "i"} = iterator
      assert {:variable, "items"} = collection
      assert {:variable, "i"} = body
    end
  end

  describe "ToMeta - Extended Layer: Lambdas" do
    test "transforms lambda without parameters" do
      ast = %{
        "_type" => "Lambda",
        "args" => %{"args" => []},
        "body" => %{"_type" => "Constant", "value" => 42}
      }

      assert {:ok, {:lambda, [], [], body}, %{}} = ToMeta.transform(ast)
      assert {:literal, :integer, 42} = body
    end

    test "transforms lambda with single parameter" do
      ast = %{
        "_type" => "Lambda",
        "args" => %{"args" => [%{"arg" => "x"}]},
        "body" => %{
          "_type" => "BinOp",
          "op" => %{"_type" => "Mult"},
          "left" => %{"_type" => "Name", "id" => "x"},
          "right" => %{"_type" => "Constant", "value" => 2}
        }
      }

      assert {:ok, {:lambda, ["x"], [], body}, %{}} = ToMeta.transform(ast)
      assert {:binary_op, :arithmetic, :*, _, _} = body
    end

    test "transforms lambda with multiple parameters" do
      ast = %{
        "_type" => "Lambda",
        "args" => %{"args" => [%{"arg" => "x"}, %{"arg" => "y"}]},
        "body" => %{
          "_type" => "BinOp",
          "op" => %{"_type" => "Add"},
          "left" => %{"_type" => "Name", "id" => "x"},
          "right" => %{"_type" => "Name", "id" => "y"}
        }
      }

      assert {:ok, {:lambda, ["x", "y"], [], body}, %{}} = ToMeta.transform(ast)
      assert {:binary_op, :arithmetic, :+, _, _} = body
    end
  end

  describe "ToMeta - Extended Layer: Comprehensions" do
    test "transforms simple list comprehension to map operation" do
      ast = %{
        "_type" => "ListComp",
        "elt" => %{
          "_type" => "BinOp",
          "op" => %{"_type" => "Mult"},
          "left" => %{"_type" => "Name", "id" => "x"},
          "right" => %{"_type" => "Constant", "value" => 2}
        },
        "generators" => [
          %{
            "target" => %{"_type" => "Name", "id" => "x"},
            "iter" => %{"_type" => "Name", "id" => "numbers"},
            "ifs" => []
          }
        ]
      }

      assert {:ok, {:collection_op, :map, lambda, collection}, %{}} = ToMeta.transform(ast)
      assert {:lambda, ["x"], [], body} = lambda
      assert {:binary_op, :arithmetic, :*, _, _} = body
      assert {:variable, "numbers"} = collection
    end

    test "transforms complex comprehension with filter to language_specific" do
      ast = %{
        "_type" => "ListComp",
        "elt" => %{"_type" => "Name", "id" => "x"},
        "generators" => [
          %{
            "target" => %{"_type" => "Name", "id" => "x"},
            "iter" => %{"_type" => "Name", "id" => "numbers"},
            "ifs" => [
              %{
                "_type" => "Compare",
                "left" => %{"_type" => "Name", "id" => "x"},
                "ops" => [%{"_type" => "Gt"}],
                "comparators" => [%{"_type" => "Constant", "value" => 0}]
              }
            ]
          }
        ]
      }

      assert {:ok, {:language_specific, :python, _, :list_comprehension}, %{}} =
               ToMeta.transform(ast)
    end
  end

  describe "ToMeta - Extended Layer: Exception Handling" do
    test "transforms try-except block" do
      source = "try:\n    risky()\nexcept Exception as e:\n    handle(e)"

      assert {:ok, ast} = Python.parse(source)

      assert {:ok, {:exception_handling, try_block, rescue_clauses, finally_block}, _metadata} =
               Python.to_meta(ast)

      assert {:function_call, "risky", []} = try_block
      assert [{:error, {:variable, "e"}, _}] = rescue_clauses
      assert nil == finally_block
    end

    test "transforms try-finally block" do
      source = "try:\n    operation\nfinally:\n    cleanup()"

      assert {:ok, ast} = Python.parse(source)

      assert {:ok, {:exception_handling, _try_block, [], finally_block}, _metadata} =
               Python.to_meta(ast)

      assert {:function_call, "cleanup", []} = finally_block
    end
  end

  describe "FromMeta - Extended Layer: Loops" do
    test "transforms while loop back" do
      meta_ast =
        {:loop, :while, {:binary_op, :comparison, :>, {:variable, "x"}, {:literal, :integer, 0}},
         {:variable, "x"}}

      assert {:ok, %{"_type" => "While", "test" => _, "body" => [_]}} =
               FromMeta.transform(meta_ast, %{})
    end

    test "transforms for loop back" do
      meta_ast = {:loop, :for_each, {:variable, "i"}, {:variable, "items"}, {:variable, "i"}}

      assert {:ok, %{"_type" => "For", "target" => _, "iter" => _, "body" => [_]}} =
               FromMeta.transform(meta_ast, %{})
    end
  end

  describe "FromMeta - Extended Layer: Lambdas" do
    test "transforms lambda back" do
      meta_ast =
        {:lambda, ["x"], [],
         {:binary_op, :arithmetic, :*, {:variable, "x"}, {:literal, :integer, 2}}}

      assert {:ok, %{"_type" => "Lambda", "args" => %{"args" => [%{"arg" => "x"}]}}} =
               FromMeta.transform(meta_ast, %{})
    end

    test "transforms lambda with multiple parameters back" do
      meta_ast =
        {:lambda, ["x", "y"], [],
         {:binary_op, :arithmetic, :+, {:variable, "x"}, {:variable, "y"}}}

      assert {:ok,
              %{
                "_type" => "Lambda",
                "args" => %{"args" => [%{"arg" => "x"}, %{"arg" => "y"}]}
              }} = FromMeta.transform(meta_ast, %{})
    end
  end

  describe "FromMeta - Extended Layer: Collection Operations" do
    test "transforms map operation to list comprehension" do
      meta_ast =
        {:collection_op, :map,
         {:lambda, ["x"], [],
          {:binary_op, :arithmetic, :*, {:variable, "x"}, {:literal, :integer, 2}}},
         {:variable, "numbers"}}

      assert {:ok, %{"_type" => "ListComp", "elt" => _, "generators" => [_]}} =
               FromMeta.transform(meta_ast, %{})
    end

    test "transforms filter operation to function call" do
      meta_ast =
        {:collection_op, :filter, {:lambda, ["x"], [], {:variable, "x"}}, {:variable, "items"}}

      assert {:ok, %{"_type" => "Call", "func" => %{"_type" => "Name", "id" => "filter"}}} =
               FromMeta.transform(meta_ast, %{})
    end

    test "transforms reduce operation to functools.reduce call" do
      meta_ast =
        {:collection_op, :reduce,
         {:lambda, ["acc", "x"], [],
          {:binary_op, :arithmetic, :+, {:variable, "acc"}, {:variable, "x"}}},
         {:variable, "numbers"}, {:literal, :integer, 0}}

      assert {:ok,
              %{
                "_type" => "Call",
                "func" => %{"_type" => "Attribute", "attr" => "reduce"}
              }} = FromMeta.transform(meta_ast, %{})
    end
  end

  describe "FromMeta - Extended Layer: Exception Handling" do
    test "transforms exception handling back" do
      meta_ast =
        {:exception_handling, {:function_call, "risky", []},
         [{:error, {:variable, "e"}, {:function_call, "handle", [{:variable, "e"}]}}], nil}

      assert {:ok, %{"_type" => "Try", "body" => [_], "handlers" => [_]}} =
               FromMeta.transform(meta_ast, %{})
    end

    test "transforms exception handling with finally block" do
      meta_ast =
        {:exception_handling, {:function_call, "risky", []}, [], {:function_call, "cleanup", []}}

      assert {:ok, %{"_type" => "Try", "finalbody" => [_]}} =
               FromMeta.transform(meta_ast, %{})
    end
  end

  describe "round-trip transformations - Extended Layer" do
    test "round-trips while loop" do
      source = "while x > 0:\n    x"

      assert {:ok, ast} = Python.parse(source)
      assert {:ok, meta_ast, metadata} = Python.to_meta(ast)
      assert {:loop, :while, _, _} = meta_ast
      assert {:ok, _ast2} = Python.from_meta(meta_ast, metadata)
    end

    test "round-trips for loop" do
      source = "for i in items:\n    i"

      assert {:ok, ast} = Python.parse(source)
      assert {:ok, meta_ast, metadata} = Python.to_meta(ast)
      assert {:loop, :for_each, _, _, _} = meta_ast
      assert {:ok, _ast2} = Python.from_meta(meta_ast, metadata)
    end

    test "round-trips lambda" do
      source = "lambda x: x * 2"

      assert {:ok, ast} = Python.parse(source)
      assert {:ok, meta_ast, metadata} = Python.to_meta(ast)
      assert {:lambda, ["x"], [], _} = meta_ast
      assert {:ok, ast2} = Python.from_meta(meta_ast, metadata)
      assert {:ok, result} = Python.unparse(ast2)
      # Lambda may have parentheses added
      assert result =~ "lambda x"
      assert result =~ "x * 2"
    end

    test "round-trips simple list comprehension" do
      source = "[x * 2 for x in numbers]"

      assert {:ok, ast} = Python.parse(source)
      assert {:ok, meta_ast, metadata} = Python.to_meta(ast)
      assert {:collection_op, :map, {:lambda, _, _, _}, _} = meta_ast
      assert {:ok, ast2} = Python.from_meta(meta_ast, metadata)
      assert {:ok, result} = Python.unparse(ast2)
      # Should produce comprehension-like output
      assert result =~ "x"
      assert result =~ "numbers"
    end

    test "round-trips try-except block" do
      source = "try:\n    risky()\nexcept Exception as e:\n    handle(e)"

      assert {:ok, ast} = Python.parse(source)
      assert {:ok, meta_ast, metadata} = Python.to_meta(ast)
      assert {:exception_handling, _, _, _} = meta_ast
      assert {:ok, _ast2} = Python.from_meta(meta_ast, metadata)
    end
  end

  describe "cross-language validation" do
    test "Python and Elixir produce equivalent MetaAST" do
      python_source = "x + 5"
      elixir_source = "x + 5"

      # Python
      assert {:ok, py_ast} = Python.parse(python_source)
      assert {:ok, py_meta, _} = Python.to_meta(py_ast)

      # Elixir
      alias Metastatic.Adapters.Elixir, as: ElixirAdapter
      assert {:ok, ex_ast} = ElixirAdapter.parse(elixir_source)
      assert {:ok, ex_meta, _} = ElixirAdapter.to_meta(ex_ast)

      # Same structure (variables may differ in name)
      assert same_structure?(py_meta, ex_meta)
    end
  end

  # Helper function
  defp same_structure?({:binary_op, cat, op, l1, r1}, {:binary_op, cat, op, l2, r2}) do
    same_structure?(l1, l2) and same_structure?(r1, r2)
  end

  defp same_structure?({:variable, _}, {:variable, _}), do: true
  defp same_structure?({:literal, t, v}, {:literal, t, v}), do: true
  defp same_structure?(a, b), do: a == b
end
