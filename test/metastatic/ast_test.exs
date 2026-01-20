defmodule Metastatic.ASTTest do
  use ExUnit.Case, async: true

  alias Metastatic.AST

  doctest Metastatic.AST

  describe "M2.1 Core conformance/1" do
    test "literal integer" do
      ast = {:literal, :integer, 42}
      assert AST.conforms?(ast)
    end

    test "literal string" do
      ast = {:literal, :string, "hello"}
      assert AST.conforms?(ast)
    end

    test "literal float" do
      ast = {:literal, :float, 3.14}
      assert AST.conforms?(ast)
    end

    test "literal boolean" do
      assert AST.conforms?({:literal, :boolean, true})
      assert AST.conforms?({:literal, :boolean, false})
    end

    test "literal null" do
      ast = {:literal, :null, nil}
      assert AST.conforms?(ast)
    end

    test "variable" do
      ast = {:variable, "x"}
      assert AST.conforms?(ast)
    end

    test "binary_op arithmetic" do
      ast =
        {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}}

      assert AST.conforms?(ast)
    end

    test "binary_op comparison" do
      ast =
        {:binary_op, :comparison, :>, {:variable, "x"}, {:literal, :integer, 0}}

      assert AST.conforms?(ast)
    end

    test "binary_op boolean" do
      ast =
        {:binary_op, :boolean, :and, {:variable, "a"}, {:variable, "b"}}

      assert AST.conforms?(ast)
    end

    test "unary_op arithmetic" do
      ast = {:unary_op, :arithmetic, :-, {:variable, "x"}}
      assert AST.conforms?(ast)
    end

    test "unary_op boolean" do
      ast = {:unary_op, :boolean, :not, {:variable, "flag"}}
      assert AST.conforms?(ast)
    end

    test "function_call" do
      ast =
        {:function_call, "add", [
          {:variable, "x"},
          {:variable, "y"}
        ]}

      assert AST.conforms?(ast)
    end

    test "function_call with no arguments" do
      ast = {:function_call, "get_value", []}
      assert AST.conforms?(ast)
    end

    test "conditional" do
      ast =
        {:conditional,
         {:binary_op, :comparison, :>, {:variable, "x"}, {:literal, :integer, 0}},
         {:literal, :integer, 1}, {:literal, :integer, -1}}

      assert AST.conforms?(ast)
    end

    test "early_return" do
      ast = {:early_return, {:variable, "result"}}
      assert AST.conforms?(ast)
    end

    test "block" do
      ast =
        {:block, [
          {:variable, "x"},
          {:variable, "y"},
          {:binary_op, :arithmetic, :+, {:variable, "x"}, {:variable, "y"}}
        ]}

      assert AST.conforms?(ast)
    end

    test "complex nested expression" do
      # ((x + 5) * y) > 10
      ast =
        {:binary_op, :comparison, :>,
         {:binary_op, :arithmetic, :*,
          {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}},
          {:variable, "y"}}, {:literal, :integer, 10}}

      assert AST.conforms?(ast)
    end
  end

  describe "M2.2 Extended conformance/1" do
    test "loop while" do
      ast =
        {:loop, :while,
         {:binary_op, :comparison, :>, {:variable, "x"}, {:literal, :integer, 0}},
         {:block, [{:variable, "x"}]}}

      assert AST.conforms?(ast)
    end

    test "loop for" do
      ast =
        {:loop, :for, {:variable, "item"}, {:variable, "collection"},
         {:block, [{:variable, "item"}]}}

      assert AST.conforms?(ast)
    end

    test "lambda" do
      ast =
        {:lambda, ["x", "y"], [], {:binary_op, :arithmetic, :+, {:variable, "x"}, {:variable, "y"}}}

      assert AST.conforms?(ast)
    end

    test "lambda with captures" do
      ast =
        {:lambda, ["x"], ["offset"],
         {:binary_op, :arithmetic, :+, {:variable, "x"}, {:variable, "offset"}}}

      assert AST.conforms?(ast)
    end

    test "collection_op map" do
      ast =
        {:collection_op, :map,
         {:lambda, ["x"], [], {:binary_op, :arithmetic, :*, {:variable, "x"}, {:literal, :integer, 2}}},
         {:variable, "list"}}

      assert AST.conforms?(ast)
    end

    test "collection_op filter" do
      ast =
        {:collection_op, :filter,
         {:lambda, ["x"], [],
          {:binary_op, :comparison, :>, {:variable, "x"}, {:literal, :integer, 0}}},
         {:variable, "list"}}

      assert AST.conforms?(ast)
    end

    test "collection_op reduce" do
      ast =
        {:collection_op, :reduce,
         {:lambda, ["acc", "x"], [],
          {:binary_op, :arithmetic, :+, {:variable, "acc"}, {:variable, "x"}}},
         {:variable, "list"}, {:literal, :integer, 0}}

      assert AST.conforms?(ast)
    end

    test "pattern_match" do
      ast =
        {:pattern_match, {:variable, "x"},
         [
           {{:literal, :integer, 0}, {:literal, :string, "zero"}},
           {{:literal, :integer, 1}, {:literal, :string, "one"}},
           {:_, {:literal, :string, "other"}}
         ]}

      assert AST.conforms?(ast)
    end

    test "exception_handling" do
      ast =
        {:exception_handling,
         {:block, [{:function_call, "risky", []}]},
         [{:error, {:variable, "e"}, {:function_call, "handle", [{:variable, "e"}]}}],
         {:function_call, "cleanup", []}}

      assert AST.conforms?(ast)
    end

    test "async_operation" do
      ast =
        {:async_operation, :await,
         {:function_call, "fetch_data", [{:literal, :string, "url"}]}}

      assert AST.conforms?(ast)
    end
  end

  describe "M2.3 Native conformance/1" do
    test "language_specific Python list comprehension" do
      ast =
        {:language_specific, :python,
         %{
           construct: :list_comprehension,
           data: "[x * 2 for x in range(10)]"
         }}

      assert AST.conforms?(ast)
    end

    test "language_specific JavaScript spread" do
      ast =
        {:language_specific, :javascript,
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
      ast = {:binary_op, :+, {:variable, "x"}}
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
      ast = {:variable, "x"}
      assert AST.variables(ast) == MapSet.new(["x"])
    end

    test "binary operation with variables" do
      ast = {:binary_op, :arithmetic, :+, {:variable, "x"}, {:variable, "y"}}
      assert AST.variables(ast) == MapSet.new(["x", "y"])
    end

    test "duplicate variables counted once" do
      ast =
        {:binary_op, :arithmetic, :+, {:variable, "x"}, {:variable, "x"}}

      assert AST.variables(ast) == MapSet.new(["x"])
    end

    test "nested expression with multiple variables" do
      # (x + y) * z
      ast =
        {:binary_op, :arithmetic, :*,
         {:binary_op, :arithmetic, :+, {:variable, "x"}, {:variable, "y"}},
         {:variable, "z"}}

      assert AST.variables(ast) == MapSet.new(["x", "y", "z"])
    end

    test "function call with variables" do
      ast =
        {:function_call, "add", [
          {:variable, "a"},
          {:variable, "b"}
        ]}

      assert AST.variables(ast) == MapSet.new(["a", "b"])
    end

    test "block with variables" do
      ast =
        {:block, [
          {:variable, "x"},
          {:variable, "y"},
          {:binary_op, :arithmetic, :+, {:variable, "x"}, {:variable, "y"}}
        ]}

      assert AST.variables(ast) == MapSet.new(["x", "y"])
    end

    test "lambda with parameters and captures" do
      ast =
        {:lambda, ["x"], ["offset"],
         {:binary_op, :arithmetic, :+, {:variable, "x"}, {:variable, "offset"}}}

      # Lambda parameters and captures are included
      assert AST.variables(ast) == MapSet.new(["x", "offset"])
    end

    test "no variables in literal" do
      ast = {:literal, :integer, 42}
      assert AST.variables(ast) == MapSet.new([])
    end
  end
end
