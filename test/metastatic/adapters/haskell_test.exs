defmodule Metastatic.Adapters.HaskellTest do
  use ExUnit.Case, async: true

  alias Metastatic.Adapters.Haskell
  alias Metastatic.Adapters.Haskell.ToMeta

  describe "parse/1" do
    test "parses valid Haskell source code" do
      assert {:ok, ast} = Haskell.parse("42")
      assert is_map(ast)
      assert ast["type"] == "literal"
    end

    test "parses arithmetic expression" do
      assert {:ok, ast} = Haskell.parse("1 + 2")
      assert ast["type"] == "infix"
      assert ast["operator"] == "+"
    end

    test "parses function application" do
      assert {:ok, ast} = Haskell.parse("f x")
      assert ast["type"] == "app"
    end
  end

  describe "ToMeta - literals (M2.1 Core Layer)" do
    test "transforms integer literals" do
      ast = %{
        "type" => "literal",
        "value" => %{"literalType" => "int", "value" => 42}
      }

      assert {:ok, {:literal, :integer, 42}, %{}} = ToMeta.transform(ast)
    end

    test "transforms float literals" do
      ast = %{
        "type" => "literal",
        "value" => %{"literalType" => "float", "value" => 3.14}
      }

      assert {:ok, {:literal, :float, 3.14}, %{}} = ToMeta.transform(ast)
    end

    test "transforms string literals" do
      ast = %{
        "type" => "literal",
        "value" => %{"literalType" => "string", "value" => "hello"}
      }

      assert {:ok, {:literal, :string, "hello"}, %{}} = ToMeta.transform(ast)
    end

    test "transforms char literals" do
      ast = %{
        "type" => "literal",
        "value" => %{"literalType" => "char", "value" => "a"}
      }

      assert {:ok, {:literal, :char, "a"}, %{}} = ToMeta.transform(ast)
    end
  end

  describe "ToMeta - variables (M2.1 Core Layer)" do
    test "transforms variables" do
      ast = %{"type" => "var", "name" => "x"}
      assert {:ok, {:variable, "x"}, %{}} = ToMeta.transform(ast)
    end

    test "transforms constructors" do
      ast = %{"type" => "con", "name" => "Just"}
      assert {:ok, {:literal, :constructor, "Just"}, %{}} = ToMeta.transform(ast)
    end
  end

  describe "ToMeta - binary operators (M2.1 Core Layer)" do
    test "transforms addition" do
      ast = %{
        "type" => "infix",
        "left" => %{
          "type" => "literal",
          "value" => %{"literalType" => "int", "value" => 1}
        },
        "operator" => "+",
        "right" => %{
          "type" => "literal",
          "value" => %{"literalType" => "int", "value" => 2}
        }
      }

      assert {:ok, {:binary_op, :arithmetic, :+, left, right}, %{}} = ToMeta.transform(ast)
      assert {:literal, :integer, 1} = left
      assert {:literal, :integer, 2} = right
    end

    test "transforms multiplication" do
      ast = %{
        "type" => "infix",
        "left" => %{
          "type" => "literal",
          "value" => %{"literalType" => "int", "value" => 3}
        },
        "operator" => "*",
        "right" => %{
          "type" => "literal",
          "value" => %{"literalType" => "int", "value" => 4}
        }
      }

      assert {:ok, {:binary_op, :arithmetic, :*, _, _}, %{}} = ToMeta.transform(ast)
    end

    test "transforms comparison operators" do
      ast = %{
        "type" => "infix",
        "left" => %{"type" => "var", "name" => "x"},
        "operator" => "<",
        "right" => %{
          "type" => "literal",
          "value" => %{"literalType" => "int", "value" => 10}
        }
      }

      assert {:ok, {:binary_op, :comparison, :<, _, _}, %{}} = ToMeta.transform(ast)
    end

    test "transforms boolean operators" do
      ast = %{
        "type" => "infix",
        "left" => %{"type" => "var", "name" => "a"},
        "operator" => "&&",
        "right" => %{"type" => "var", "name" => "b"}
      }

      assert {:ok, {:binary_op, :boolean, :&&, _, _}, %{}} = ToMeta.transform(ast)
    end

    test "transforms custom operators as function calls" do
      ast = %{
        "type" => "infix",
        "left" => %{"type" => "var", "name" => "x"},
        "operator" => "<$>",
        "right" => %{"type" => "var", "name" => "y"}
      }

      assert {:ok, {:function_call, "<$>", [_, _]}, %{custom_op: true}} = ToMeta.transform(ast)
    end
  end

  describe "ToMeta - function application (M2.1 Core Layer)" do
    test "transforms simple function application" do
      ast = %{
        "type" => "app",
        "function" => %{"type" => "var", "name" => "f"},
        "argument" => %{"type" => "var", "name" => "x"}
      }

      assert {:ok, {:function_call, "f", [arg]}, %{}} = ToMeta.transform(ast)
      assert {:variable, "x"} = arg
    end

    test "transforms curried function application" do
      # f x y represented as App (App f x) y
      ast = %{
        "type" => "app",
        "function" => %{
          "type" => "app",
          "function" => %{"type" => "var", "name" => "f"},
          "argument" => %{"type" => "var", "name" => "x"}
        },
        "argument" => %{"type" => "var", "name" => "y"}
      }

      assert {:ok, {:function_call, "f", [arg1, arg2]}, %{}} = ToMeta.transform(ast)
      assert {:variable, "x"} = arg1
      assert {:variable, "y"} = arg2
    end
  end

  describe "ToMeta - lambdas (M2.1 Core Layer)" do
    test "transforms lambda with single parameter" do
      ast = %{
        "type" => "lambda",
        "patterns" => [%{"type" => "var_pat", "name" => "x"}],
        "body" => %{
          "type" => "infix",
          "left" => %{"type" => "var", "name" => "x"},
          "operator" => "+",
          "right" => %{
            "type" => "literal",
            "value" => %{"literalType" => "int", "value" => 1}
          }
        }
      }

      assert {:ok, {:lambda, ["x"], body}, %{}} = ToMeta.transform(ast)
      assert {:binary_op, :arithmetic, :+, _, _} = body
    end

    test "transforms lambda with multiple parameters" do
      ast = %{
        "type" => "lambda",
        "patterns" => [
          %{"type" => "var_pat", "name" => "x"},
          %{"type" => "var_pat", "name" => "y"}
        ],
        "body" => %{
          "type" => "infix",
          "left" => %{"type" => "var", "name" => "x"},
          "operator" => "+",
          "right" => %{"type" => "var", "name" => "y"}
        }
      }

      assert {:ok, {:lambda, ["x", "y"], body}, %{}} = ToMeta.transform(ast)
      assert {:binary_op, :arithmetic, :+, _, _} = body
    end
  end

  describe "ToMeta - conditionals (M2.1 Core Layer)" do
    test "transforms if-then-else" do
      ast = %{
        "type" => "if",
        "condition" => %{"type" => "var", "name" => "x"},
        "then" => %{
          "type" => "literal",
          "value" => %{"literalType" => "int", "value" => 1}
        },
        "else" => %{
          "type" => "literal",
          "value" => %{"literalType" => "int", "value" => 2}
        }
      }

      assert {:ok, {:conditional, condition, then_branch, else_branch}, %{}} =
               ToMeta.transform(ast)

      assert {:variable, "x"} = condition
      assert {:literal, :integer, 1} = then_branch
      assert {:literal, :integer, 2} = else_branch
    end
  end

  describe "ToMeta - let bindings (M2.1 Core Layer)" do
    test "transforms let binding" do
      ast = %{
        "type" => "let",
        "bindings" => [
          %{
            "type" => "pat_bind",
            "pattern" => %{"type" => "var_pat", "name" => "x"},
            "rhs" => %{
              "type" => "literal",
              "value" => %{"literalType" => "int", "value" => 42}
            }
          }
        ],
        "body" => %{"type" => "var", "name" => "x"}
      }

      assert {:ok, {:block, statements}, %{construct: :let}} = ToMeta.transform(ast)
      assert [assignment, body] = statements
      assert {:assignment, {:variable, "x"}, {:literal, :integer, 42}} = assignment
      assert {:variable, "x"} = body
    end
  end

  describe "ToMeta - collections (M2.1 Core Layer)" do
    test "transforms lists" do
      ast = %{
        "type" => "list",
        "elements" => [
          %{
            "type" => "literal",
            "value" => %{"literalType" => "int", "value" => 1}
          },
          %{
            "type" => "literal",
            "value" => %{"literalType" => "int", "value" => 2}
          }
        ]
      }

      assert {:ok, {:literal, :collection, elements}, %{collection_type: :list}} =
               ToMeta.transform(ast)

      assert [_, _] = elements
    end

    test "transforms tuples" do
      ast = %{
        "type" => "tuple",
        "elements" => [
          %{
            "type" => "literal",
            "value" => %{"literalType" => "int", "value" => 1}
          },
          %{
            "type" => "literal",
            "value" => %{"literalType" => "string", "value" => "hello"}
          }
        ]
      }

      assert {:ok, {:literal, :collection, elements}, %{collection_type: :tuple}} =
               ToMeta.transform(ast)

      assert [_, _] = elements
    end
  end

  describe "ToMeta - case expressions (M2.2 Extended Layer)" do
    test "transforms case expression" do
      ast = %{
        "type" => "case",
        "scrutinee" => %{"type" => "var", "name" => "x"},
        "alternatives" => [
          %{
            "pattern" => %{
              "type" => "lit_pat",
              "literal" => %{"literalType" => "int", "value" => 1}
            },
            "rhs" => %{
              "type" => "literal",
              "value" => %{"literalType" => "string", "value" => "one"}
            }
          },
          %{
            "pattern" => %{"type" => "wildcard"},
            "rhs" => %{
              "type" => "literal",
              "value" => %{"literalType" => "string", "value" => "other"}
            }
          }
        ]
      }

      assert {:ok, {:pattern_match, scrutinee, branches, nil}, %{}} = ToMeta.transform(ast)
      assert {:variable, "x"} = scrutinee
      assert [_, _] = branches
    end
  end

  describe "ToMeta - list comprehensions (M2.2 Extended Layer)" do
    test "transforms list comprehension" do
      ast = %{
        "type" => "list_comp",
        "expression" => %{"type" => "var", "name" => "x"},
        "qualifiers" => [
          %{
            "type" => "generator",
            "pattern" => %{"type" => "var_pat", "name" => "x"},
            "expression" => %{
              "type" => "list",
              "elements" => []
            }
          }
        ]
      }

      assert {:ok, {:language_specific, :haskell, data, :list_comp}, %{}} =
               ToMeta.transform(ast)

      assert is_map(data)
      assert Map.has_key?(data, "expr")
      assert Map.has_key?(data, "quals")
    end
  end

  describe "ToMeta - do notation (M2.2 Extended Layer)" do
    test "transforms do notation" do
      ast = %{
        "type" => "do",
        "statements" => [
          %{
            "type" => "generator",
            "pattern" => %{"type" => "var_pat", "name" => "x"},
            "expression" => %{"type" => "var", "name" => "getLine"}
          },
          %{
            "type" => "qualifier",
            "expression" => %{"type" => "var", "name" => "x"}
          }
        ]
      }

      assert {:ok, {:block, statements}, %{construct: :do_notation}} = ToMeta.transform(ast)
      assert [_, _] = statements
    end
  end

  describe "integration - parse and transform" do
    test "parses and transforms integer literal" do
      {:ok, ast} = Haskell.parse("42")
      assert {:ok, meta_ast, _metadata} = ToMeta.transform(ast)
      assert {:literal, :integer, 42} = meta_ast
    end

    test "parses and transforms arithmetic" do
      {:ok, ast} = Haskell.parse("5 + 3")
      assert {:ok, meta_ast, _metadata} = ToMeta.transform(ast)
      assert {:binary_op, :arithmetic, :+, _, _} = meta_ast
    end

    test "parses and transforms function application" do
      {:ok, ast} = Haskell.parse("f x")
      assert {:ok, meta_ast, _metadata} = ToMeta.transform(ast)
      assert {:function_call, "f", [_]} = meta_ast
    end

    test "parses and transforms lambda" do
      {:ok, ast} = Haskell.parse("\\x -> x + 1")
      assert {:ok, meta_ast, _metadata} = ToMeta.transform(ast)
      assert {:lambda, ["x"], _} = meta_ast
    end
  end

  describe "file_extensions/0" do
    test "returns Haskell file extensions" do
      assert [".hs", ".lhs"] = Haskell.file_extensions()
    end
  end
end
