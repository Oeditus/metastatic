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
