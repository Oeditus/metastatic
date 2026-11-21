defmodule Metastatic.Adapters.HaskellTest do
  use ExUnit.Case, async: true

  @moduletag :haskell

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

      assert {:ok, {:literal, [subtype: :integer], 42}, %{}} = ToMeta.transform(ast)
    end

    test "transforms float literals" do
      ast = %{
        "type" => "literal",
        "value" => %{"literalType" => "float", "value" => 3.14}
      }

      assert {:ok, {:literal, [subtype: :float], 3.14}, %{}} = ToMeta.transform(ast)
    end

    test "transforms string literals" do
      ast = %{
        "type" => "literal",
        "value" => %{"literalType" => "string", "value" => "hello"}
      }

      assert {:ok, {:literal, [subtype: :string], "hello"}, %{}} = ToMeta.transform(ast)
    end

    test "transforms char literals" do
      ast = %{
        "type" => "literal",
        "value" => %{"literalType" => "char", "value" => "a"}
      }

      assert {:ok, {:literal, [subtype: :char], "a"}, %{}} = ToMeta.transform(ast)
    end
  end

  describe "ToMeta - variables (M2.1 Core Layer)" do
    test "transforms variables" do
      ast = %{"type" => "var", "name" => "x"}
      assert {:ok, {:variable, [scope: :local], "x"}, %{}} = ToMeta.transform(ast)
    end

    test "transforms constructors" do
      ast = %{"type" => "con", "name" => "Just"}

      # Constructors are `:symbol` literals (the only conforming subtype for a
      # bare name); `:symbol` requires an atom payload.
      assert {:ok, {:literal, [subtype: :symbol], :Just}, %{}} = ToMeta.transform(ast)
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

      assert {:ok, {:binary_op, [category: :arithmetic, operator: :+], [left, right]}, %{}} =
               ToMeta.transform(ast)

      assert {:literal, [subtype: :integer], 1} = left
      assert {:literal, [subtype: :integer], 2} = right
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

      assert {:ok, {:binary_op, [category: :arithmetic, operator: :*], _children}, %{}} =
               ToMeta.transform(ast)
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

      assert {:ok, {:binary_op, [category: :comparison, operator: :<], _children}, %{}} =
               ToMeta.transform(ast)
    end

    test "transforms boolean operators" do
      ast = %{
        "type" => "infix",
        "left" => %{"type" => "var", "name" => "a"},
        "operator" => "&&",
        "right" => %{"type" => "var", "name" => "b"}
      }

      # && is normalized to :and at M2 level
      assert {:ok, {:binary_op, [category: :boolean, operator: :and], _children}, %{}} =
               ToMeta.transform(ast)
    end

    test "transforms custom operators as function calls" do
      ast = %{
        "type" => "infix",
        "left" => %{"type" => "var", "name" => "x"},
        "operator" => "<$>",
        "right" => %{"type" => "var", "name" => "y"}
      }

      assert {:ok, {:function_call, [name: "<$>"], _args}, %{custom_op: true}} =
               ToMeta.transform(ast)
    end
  end

  describe "ToMeta - function application (M2.1 Core Layer)" do
    test "transforms simple function application" do
      ast = %{
        "type" => "app",
        "function" => %{"type" => "var", "name" => "f"},
        "argument" => %{"type" => "var", "name" => "x"}
      }

      assert {:ok, {:function_call, [name: "f"], [arg]}, %{}} = ToMeta.transform(ast)
      assert {:variable, [scope: :local], "x"} = arg
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

      assert {:ok, {:function_call, [name: "f"], [arg1, arg2]}, %{}} = ToMeta.transform(ast)
      assert {:variable, [scope: :local], "x"} = arg1
      assert {:variable, [scope: :local], "y"} = arg2
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

      assert {:ok, {:lambda, [params: [{:param, [], "x"}], captures: []], [body]}, %{}} =
               ToMeta.transform(ast)

      assert {:binary_op, [category: :arithmetic, operator: :+], _children} = body
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

      assert {:ok,
              {:lambda, [params: [{:param, [], "x"}, {:param, [], "y"}], captures: []], [body]},
              %{}} =
               ToMeta.transform(ast)

      assert {:binary_op, [category: :arithmetic, operator: :+], _children} = body
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

      assert {:ok, {:conditional, [], [condition, then_branch, else_branch]}, %{}} =
               ToMeta.transform(ast)

      assert {:variable, [scope: :local], "x"} = condition
      assert {:literal, [subtype: :integer], 1} = then_branch
      assert {:literal, [subtype: :integer], 2} = else_branch
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

      assert {:ok, {:block, [construct: :let], statements}, %{construct: :let}} =
               ToMeta.transform(ast)

      assert [assignment, body] = statements

      assert {:assignment, [],
              [{:variable, [scope: :local], "x"}, {:literal, [subtype: :integer], 42}]} =
               assignment

      assert {:variable, [scope: :local], "x"} = body
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

      assert {:ok, {:list, [collection_type: :list], elements}, %{collection_type: :list}} =
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

      # Haskell tuples use the proper :tuple M2 type
      assert {:ok, {:tuple, [], elements}, %{}} = ToMeta.transform(ast)

      assert [{:literal, [subtype: :integer], 1}, {:literal, [subtype: :string], "hello"}] =
               elements
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

      # Haskell case produces [scrutinee | match_arm_nodes]
      assert {:ok, {:pattern_match, [], [scrutinee | arms]}, %{}} = ToMeta.transform(ast)
      assert {:variable, [scope: :local], "x"} = scrutinee
      assert [{:match_arm, _, _}, {:match_arm, _, _}] = arms
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

      # Now uses proper :comprehension M2 type
      assert {:ok, {:comprehension, meta, [body | gens]}, %{}} = ToMeta.transform(ast)
      assert Keyword.get(meta, :comp_type) == :list
      assert {:variable, _, "x"} = body
      assert [_] = gens
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

      assert {:ok, {:block, [construct: :do_notation], statements}, %{construct: :do_notation}} =
               ToMeta.transform(ast)

      assert [_, _] = statements
    end
  end

  describe "integration - parse and transform" do
    test "parses and transforms integer literal" do
      {:ok, ast} = Haskell.parse("42")
      assert {:ok, meta_ast, _metadata} = ToMeta.transform(ast)
      assert {:literal, meta, 42} = meta_ast
      assert Keyword.get(meta, :subtype) == :integer
    end

    test "parses and transforms arithmetic" do
      {:ok, ast} = Haskell.parse("5 + 3")
      assert {:ok, meta_ast, _metadata} = ToMeta.transform(ast)
      assert {:binary_op, meta, _children} = meta_ast
      assert Keyword.get(meta, :category) == :arithmetic
      assert Keyword.get(meta, :operator) == :+
    end

    test "parses and transforms function application" do
      {:ok, ast} = Haskell.parse("f x")
      assert {:ok, meta_ast, _metadata} = ToMeta.transform(ast)
      assert {:function_call, meta, _args} = meta_ast
      assert Keyword.get(meta, :name) == "f"
    end

    test "parses and transforms lambda" do
      {:ok, ast} = Haskell.parse("\\x -> x + 1")
      assert {:ok, meta_ast, _metadata} = ToMeta.transform(ast)
      assert {:lambda, meta, _body} = meta_ast
      assert Keyword.get(meta, :params) == [{:param, [], "x"}]
      assert Keyword.get(meta, :captures) == []
    end
  end

  describe "file_extensions/0" do
    test "returns Haskell file extensions" do
      assert [".hs", ".lhs"] = Haskell.file_extensions()
    end
  end

  describe "FromMeta - M2→M1 reification" do
    alias Metastatic.Adapters.Haskell.FromMeta

    test "transforms function calls with currying" do
      meta_ast =
        {:function_call, [name: "f"],
         [{:variable, [scope: :local], "x"}, {:variable, [scope: :local], "y"}]}

      assert {:ok, ast} = FromMeta.transform(meta_ast, %{})
      assert ast["type"] == "app"
      assert get_in(ast, ["function", "type"]) == "app"
    end

    test "transforms lists" do
      meta_ast =
        {:list, [collection_type: :list],
         [{:literal, [subtype: :integer], 1}, {:literal, [subtype: :integer], 2}]}

      assert {:ok, ast} = FromMeta.transform(meta_ast, %{collection_type: :list})
      assert ast["type"] == "list"
      assert length(ast["elements"]) == 2
    end

    test "transforms tuples" do
      # Tuples use the proper :tuple M2 type
      meta_ast =
        {:tuple, [],
         [{:literal, [subtype: :integer], 1}, {:literal, [subtype: :string], "hello"}]}

      assert {:ok, ast} = FromMeta.transform(meta_ast, %{})
      assert ast["type"] == "tuple"
      assert [_, _] = ast["elements"]
    end

    test "transforms tuples round-trip" do
      # Haskell AST -> MetaAST -> Haskell AST
      haskell_ast = %{
        "type" => "tuple",
        "elements" => [
          %{"type" => "literal", "value" => %{"literalType" => "int", "value" => 1}},
          %{"type" => "literal", "value" => %{"literalType" => "string", "value" => "hi"}}
        ]
      }

      {:ok, meta_ast, metadata} = ToMeta.transform(haskell_ast)
      assert {:tuple, [], [_, _]} = meta_ast

      {:ok, back} = FromMeta.transform(meta_ast, metadata)
      assert back["type"] == "tuple"
      assert [_, _] = back["elements"]
    end

    test "transforms let bindings" do
      meta_ast =
        {:block, [construct: :let],
         [
           {:assignment, [],
            [{:variable, [scope: :local], "x"}, {:literal, [subtype: :integer], 42}]},
           {:variable, [scope: :local], "x"}
         ]}

      assert {:ok, ast} = FromMeta.transform(meta_ast, %{construct: :let})
      assert ast["type"] == "let"
      assert is_list(ast["bindings"])
      assert ast["body"] != nil
    end

    test "transforms case expressions" do
      # Standard format: [scrutinee | match_arm_nodes]
      meta_ast =
        {:pattern_match, [],
         [
           {:variable, [scope: :local], "x"},
           {:match_arm, [pattern: {:literal, [subtype: :integer], 1}],
            [{:literal, [subtype: :string], "one"}]},
           {:match_arm, [pattern: :_], [{:literal, [subtype: :string], "other"}]}
         ]}

      assert {:ok, ast} = FromMeta.transform(meta_ast, %{})
      assert ast["type"] == "case"
      assert ast["scrutinee"]["type"] == "var"
      assert length(ast["alternatives"]) == 2
    end
  end

  describe "ToMeta - M2.3 Native Layer" do
    test "transforms type signature" do
      ast = %{
        "type" => "type_sig",
        "names" => ["factorial"],
        "signature" => %{
          "type" => "type_fun",
          "argument" => %{"type" => "type_con", "name" => "Int"},
          "result" => %{"type" => "type_con", "name" => "Int"}
        }
      }

      # Now uses proper :type_annotation M2 type
      assert {:ok, {:type_annotation, meta, [type_expr]}, %{}} = ToMeta.transform(ast)
      assert Keyword.get(meta, :annotation_type) == :spec
      assert Keyword.get(meta, :name) == "factorial"
      assert Keyword.get(meta, :names) == ["factorial"]
      assert {:language_specific, [language: :haskell, hint: :type_expr], _} = type_expr
    end

    test "transforms data type declaration" do
      ast = %{
        "type" => "data_decl",
        "data_or_new" => "data",
        "name" => "Maybe",
        "constructors" => [
          %{"name" => "Nothing", "types" => []},
          %{"name" => "Just", "types" => [%{"type" => "type_var", "name" => "a"}]}
        ]
      }

      assert {:ok, {:language_specific, [language: :haskell, hint: :data_decl], data}, %{}} =
               ToMeta.transform(ast)

      assert data["kind"] == "data"
      assert data["name"] == "Maybe"
      assert [_, _] = data["constructors"]
    end

    test "transforms newtype declaration" do
      ast = %{
        "type" => "data_decl",
        "data_or_new" => "newtype",
        "name" => "Identity",
        "constructors" => [%{"name" => "Identity", "types" => []}]
      }

      assert {:ok, {:language_specific, [language: :haskell, hint: :data_decl], data}, %{}} =
               ToMeta.transform(ast)

      assert data["kind"] == "newtype"
    end

    test "transforms type alias" do
      ast = %{
        "type" => "type_alias",
        "name" => "String",
        "definition" => %{
          "type" => "type_list",
          "element" => %{"type" => "type_con", "name" => "Char"}
        }
      }

      assert {:ok, {:language_specific, [language: :haskell, hint: :type_alias], data}, %{}} =
               ToMeta.transform(ast)

      assert data["name"] == "String"
      assert data["definition"]["type"] == "type_list"
    end

    test "transforms type class declaration to container interface" do
      ast = %{
        "type" => "class_decl",
        "name" => "Eq",
        "methods" => [
          %{
            "type" => "type_sig",
            "names" => ["=="],
            "signature" => %{"type" => "type_con", "name" => "Bool"}
          }
        ]
      }

      # Now uses :container with container_type: :interface
      assert {:ok, {:container, meta, methods}, %{}} = ToMeta.transform(ast)
      assert Keyword.get(meta, :container_type) == :interface
      assert Keyword.get(meta, :name) == "Eq"
      assert Keyword.get(meta, :language) == :haskell
      assert [_] = methods
    end

    test "transforms instance declaration" do
      ast = %{
        "type" => "instance_decl",
        "rule" => %{"class" => "Eq"},
        "methods" => []
      }

      assert {:ok, {:language_specific, [language: :haskell, hint: :instance_decl], data}, %{}} =
               ToMeta.transform(ast)

      assert data["rule"]["class"] == "Eq"
    end

    test "transforms function binding" do
      ast = %{
        "type" => "fun_bind",
        "matches" => [
          %{
            "name" => "factorial",
            "patterns" => [%{"type" => "var_pat", "name" => "n"}],
            "rhs" => %{"type" => "var", "name" => "n"}
          }
        ]
      }

      # Now uses proper :function_def M2 type
      assert {:ok, {:function_def, meta, [body]}, %{construct: :function_binding}} =
               ToMeta.transform(ast)

      assert Keyword.get(meta, :name) == "factorial"
      assert Keyword.get(meta, :params) == [{:param, [], "n"}]
      assert Keyword.get(meta, :visibility) == :public
      assert Keyword.get(meta, :arity) == 1
      assert {:variable, [scope: :local], "n"} = body
    end
  end

  describe "to_meta/1 enrichment" do
    test "enriches function calls through Enricher pipeline" do
      ast = %{
        "type" => "app",
        "function" => %{"type" => "var", "name" => "f"},
        "argument" => %{"type" => "var", "name" => "x"}
      }

      {:ok, meta_ast, _metadata} = Haskell.to_meta(ast)

      # Should produce a function_call (enricher traverses without error)
      assert {:function_call, meta, [_]} = meta_ast
      assert Keyword.get(meta, :name) == "f"
    end

    test "enrichment does not alter non-matching nodes" do
      ast = %{
        "type" => "literal",
        "value" => %{"literalType" => "int", "value" => 42}
      }

      {:ok, meta_ast, _metadata} = Haskell.to_meta(ast)

      # Literal should pass through enricher unchanged
      assert {:literal, [subtype: :integer], 42} = meta_ast
    end

    test "enriches nested structures" do
      # if cond then f(x) else g(y)
      ast = %{
        "type" => "if",
        "condition" => %{"type" => "var", "name" => "cond"},
        "then" => %{
          "type" => "app",
          "function" => %{"type" => "var", "name" => "f"},
          "argument" => %{"type" => "var", "name" => "x"}
        },
        "else" => %{
          "type" => "app",
          "function" => %{"type" => "var", "name" => "g"},
          "argument" => %{"type" => "var", "name" => "y"}
        }
      }

      {:ok, meta_ast, _metadata} = Haskell.to_meta(ast)

      assert {:conditional, [], [_cond, then_branch, else_branch]} = meta_ast
      assert {:function_call, _, _} = then_branch
      assert {:function_call, _, _} = else_branch
    end

    test "propagates errors from ToMeta through enrichment" do
      result = Haskell.to_meta(%{"type" => "unsupported_xyzzy"})
      assert {:error, _} = result
    end
  end

  describe "M2.3 Native Layer" do
    test "transforms module with declarations" do
      ast = %{
        "type" => "module",
        "declarations" => [
          %{"type" => "type_sig", "names" => ["f"], "signature" => %{}},
          %{
            "type" => "fun_bind",
            "matches" => [
              %{
                "name" => "f",
                "patterns" => [],
                "rhs" => %{
                  "type" => "literal",
                  "value" => %{"literalType" => "int", "value" => 42}
                }
              }
            ]
          }
        ]
      }

      # Now uses proper :container M2 type
      assert {:ok, {:container, meta, decls}, %{}} = ToMeta.transform(ast)
      assert Keyword.get(meta, :container_type) == :module
      assert Keyword.get(meta, :name) == "Main"
      assert Keyword.get(meta, :language) == :haskell
      assert [_, _] = decls
    end
  end

  describe "unparse/1 and round_trip" do
    test "unparses literals and binary operators" do
      ast = %{
        "type" => "infix",
        "left" => %{"type" => "literal", "value" => %{"literalType" => "int", "value" => 1}},
        "operator" => "+",
        "right" => %{"type" => "literal", "value" => %{"literalType" => "int", "value" => 2}}
      }

      assert {:ok, "1 + 2"} = Haskell.unparse(ast)
    end

    test "round-trips arithmetic expression via Metastatic.Adapter" do
      assert {:ok, code} = Metastatic.Adapter.round_trip(Haskell, "1 + 2")
      assert String.trim(code) == "1 + 2"
    end
  end

  describe "ToMeta - patterns (M1 pattern coverage)" do
    test "transforms constructor patterns to function_call" do
      ast = %{
        "type" => "con_pat",
        "name" => "Just",
        "patterns" => [%{"type" => "var_pat", "name" => "x"}]
      }

      assert {:ok, {:function_call, [name: "Just", pattern: true], [arg]}, %{}} =
               ToMeta.transform(ast)

      assert {:variable, [], "x"} = arg
    end

    test "transforms nullary constructor patterns" do
      ast = %{"type" => "con_pat", "name" => "Nothing", "patterns" => []}

      assert {:ok, {:function_call, [name: "Nothing", pattern: true], []}, %{}} =
               ToMeta.transform(ast)
    end

    test "transforms tuple patterns" do
      ast = %{
        "type" => "tuple_pat",
        "elements" => [
          %{"type" => "var_pat", "name" => "a"},
          %{"type" => "var_pat", "name" => "b"}
        ]
      }

      assert {:ok, {:tuple, [pattern: true], [_, _]}, %{}} = ToMeta.transform(ast)
    end

    test "transforms empty list patterns" do
      ast = %{"type" => "list_pat", "elements" => []}

      assert {:ok, {:list, [collection_type: :list, pattern: true], []}, %{}} =
               ToMeta.transform(ast)
    end

    test "transforms list patterns with elements" do
      ast = %{
        "type" => "list_pat",
        "elements" => [%{"type" => "var_pat", "name" => "x"}]
      }

      assert {:ok, {:list, [collection_type: :list, pattern: true], [_]}, %{}} =
               ToMeta.transform(ast)
    end

    test "transforms infix constructor patterns" do
      ast = %{
        "type" => "infix_pat",
        "left" => %{"type" => "var_pat", "name" => "x"},
        "operator" => ":",
        "right" => %{"type" => "var_pat", "name" => "xs"}
      }

      # An infix constructor is a *constructor* pattern, not an operator:
      # `:pattern` is not a valid `:binary_op` category, so encoding it as a
      # binary op produced a non-conforming node.
      assert {:ok, {:function_call, [name: ":", pattern: true], [_, _]}, %{}} =
               ToMeta.transform(ast)
    end

    test "transforms as-patterns" do
      ast = %{
        "type" => "as_pat",
        "name" => "all",
        "pattern" => %{"type" => "var_pat", "name" => "x"}
      }

      assert {:ok, {:language_specific, meta, data}, %{}} = ToMeta.transform(ast)
      assert Keyword.get(meta, :hint) == :as_pattern
      assert data["name"] == "all"
    end

    test "transforms record patterns" do
      ast = %{
        "type" => "record_pat",
        "name" => "Response",
        "fields" => [
          %{"name" => "status", "pattern" => %{"type" => "var_pat", "name" => "s"}}
        ]
      }

      assert {:ok, {:map, meta, [pair]}, %{}} = ToMeta.transform(ast)
      assert Keyword.get(meta, :record) == true
      assert Keyword.get(meta, :constructor) == "Response"
      assert {:pair, [], [{:literal, _, "status"}, {:variable, [], "s"}]} = pair
    end

    test "wildcard patterns conform to MetaAST" do
      # Regression: `:_` was emitted for a wildcard, but `AST.conforms?/1`
      # rejects the bare atom, so any `case` arm with `_` made the whole
      # module non-conforming.
      assert {:ok, {:wildcard, [], nil}, %{}} = ToMeta.transform(%{"type" => "wildcard"})
    end

    test "infix constructor patterns conform to MetaAST" do
      # Regression: `x : xs` was encoded as a `:binary_op` with
      # `category: :pattern`, which is not a valid operator category.
      ast = %{
        "type" => "infix_pat",
        "left" => %{"type" => "var_pat", "name" => "x"},
        "operator" => ":",
        "right" => %{"type" => "wildcard"}
      }

      assert {:ok, pattern, %{}} = ToMeta.transform(ast)
      assert Metastatic.AST.conforms?(pattern)
    end
  end

  describe "ToMeta - expression type signatures" do
    test "transforms (e :: T) to a type_annotation hint" do
      ast = %{
        "type" => "expr_type_sig",
        "expression" => %{
          "type" => "literal",
          "value" => %{"literalType" => "string", "value" => "literal"}
        },
        "signature" => %{"type" => "type_con", "name" => "String"}
      }

      assert {:ok, {:type_annotation, meta, [expr, type_expr]}, %{}} = ToMeta.transform(ast)
      assert Keyword.get(meta, :annotation_type) == :hint
      assert {:literal, [subtype: :string], "literal"} = expr
      assert {:language_specific, [language: :haskell, hint: :type_expr], _} = type_expr
    end
  end

  describe "ToMeta - record construction" do
    test "transforms record construction to a record map" do
      ast = %{
        "type" => "record_constr",
        "name" => "Response",
        "fields" => [
          %{
            "name" => "status",
            "value" => %{
              "type" => "literal",
              "value" => %{"literalType" => "string", "value" => "ok"}
            }
          },
          %{"name" => "ast", "value" => %{"type" => "con", "name" => "Nothing"}}
        ]
      }

      assert {:ok, {:map, meta, pairs}, %{record: true}} = ToMeta.transform(ast)
      assert Keyword.get(meta, :record) == true
      assert Keyword.get(meta, :constructor) == "Response"
      assert length(pairs) == 2
    end

    test "transforms record update to language_specific" do
      ast = %{
        "type" => "record_update",
        "expression" => %{"type" => "var", "name" => "r"},
        "fields" => [
          %{
            "name" => "status",
            "value" => %{
              "type" => "literal",
              "value" => %{"literalType" => "string", "value" => "error"}
            }
          }
        ]
      }

      assert {:ok, {:language_specific, meta, data}, %{}} = ToMeta.transform(ast)
      assert Keyword.get(meta, :hint) == :record_update
      assert data["target"] == {:variable, [scope: :local], "r"}
    end
  end

  describe "ToMeta - operator sections and negation" do
    test "transforms left sections" do
      ast = %{
        "type" => "left_section",
        "expression" => %{
          "type" => "literal",
          "value" => %{"literalType" => "string", "value" => "--"}
        },
        "operator" => "isPrefixOf"
      }

      assert {:ok, {:language_specific, meta, data}, %{}} = ToMeta.transform(ast)
      assert Keyword.get(meta, :hint) == :left_section
      assert data["operator"] == "isPrefixOf"
    end

    test "transforms right sections" do
      ast = %{
        "type" => "right_section",
        "operator" => "+",
        "expression" => %{"type" => "var", "name" => "x"}
      }

      assert {:ok, {:language_specific, meta, _data}, %{}} = ToMeta.transform(ast)
      assert Keyword.get(meta, :hint) == :right_section
    end

    test "transforms negation to unary_op" do
      ast = %{"type" => "negate", "expression" => %{"type" => "var", "name" => "x"}}

      assert {:ok, {:unary_op, [category: :arithmetic, operator: :-], [_]}, %{}} =
               ToMeta.transform(ast)
    end
  end

  describe "ToMeta - enum sequences" do
    test "transforms [a .. b] to a range" do
      ast = %{
        "type" => "enum_from_to",
        "from" => %{"type" => "literal", "value" => %{"literalType" => "int", "value" => 1}},
        "to" => %{"type" => "literal", "value" => %{"literalType" => "int", "value" => 10}}
      }

      assert {:ok, {:range, [range_type: :enum], [from, to]}, %{}} = ToMeta.transform(ast)
      assert {:literal, [subtype: :integer], 1} = from
      assert {:literal, [subtype: :integer], 10} = to
    end

    test "transforms [a ..] to language_specific" do
      ast = %{
        "type" => "enum_from",
        "from" => %{"type" => "literal", "value" => %{"literalType" => "int", "value" => 1}}
      }

      assert {:ok, {:language_specific, meta, _}, %{}} = ToMeta.transform(ast)
      assert Keyword.get(meta, :hint) == :enum_from
    end

    test "transforms [a, b ..] to language_specific" do
      ast = %{
        "type" => "enum_from_then",
        "from" => %{"type" => "literal", "value" => %{"literalType" => "int", "value" => 1}},
        "then" => %{"type" => "literal", "value" => %{"literalType" => "int", "value" => 3}}
      }

      assert {:ok, {:language_specific, meta, _}, %{}} = ToMeta.transform(ast)
      assert Keyword.get(meta, :hint) == :enum_from_then
    end
  end

  describe "FromMeta - new construct reification" do
    alias Metastatic.Adapters.Haskell.FromMeta

    test "reifies record construction" do
      meta_ast =
        {:map, [record: true, constructor: "Response"],
         [
           {:pair, [],
            [{:literal, [subtype: :string], "status"}, {:literal, [subtype: :string], "ok"}]}
         ]}

      assert {:ok, ast} = FromMeta.transform(meta_ast, %{})
      assert ast["type"] == "record_constr"
      assert ast["name"] == "Response"
      assert [%{"name" => "status"}] = ast["fields"]
    end

    test "reifies enum ranges" do
      meta_ast =
        {:range, [range_type: :enum],
         [{:literal, [subtype: :integer], 1}, {:literal, [subtype: :integer], 10}]}

      assert {:ok, ast} = FromMeta.transform(meta_ast, %{})
      assert ast["type"] == "enum_from_to"
    end

    test "reifies negation" do
      meta_ast = {:unary_op, [category: :arithmetic, operator: :-], [{:variable, [], "x"}]}

      assert {:ok, ast} = FromMeta.transform(meta_ast, %{})
      assert ast["type"] == "negate"
    end

    test "reifies constructor patterns" do
      meta_ast = {:function_call, [name: "Just", pattern: true], [{:variable, [], "x"}]}

      assert {:ok, ast} = FromMeta.transform(meta_ast, %{})
      assert ast["type"] == "con_pat"
      assert ast["name"] == "Just"
    end

    test "reifies tuple patterns" do
      meta_ast = {:tuple, [pattern: true], [{:variable, [], "a"}, {:variable, [], "b"}]}

      assert {:ok, ast} = FromMeta.transform(meta_ast, %{})
      assert ast["type"] == "tuple_pat"
    end

    test "reifies list patterns" do
      meta_ast = {:list, [pattern: true], [{:variable, [], "x"}]}

      assert {:ok, ast} = FromMeta.transform(meta_ast, %{})
      assert ast["type"] == "list_pat"
    end

    test "reifies infix constructor patterns" do
      meta_ast =
        {:binary_op, [category: :pattern, operator: ":"],
         [{:variable, [], "x"}, {:variable, [], "xs"}]}

      assert {:ok, ast} = FromMeta.transform(meta_ast, %{})
      assert ast["type"] == "infix_pat"
      assert ast["operator"] == ":"
    end

    test "rejects maps without :record metadata" do
      meta_ast = {:map, [], []}

      assert {:error, reason} = FromMeta.transform(meta_ast, %{})
      assert reason =~ "map without :record"
    end
  end

  describe "unparse/1 - new constructs" do
    test "unparses record construction" do
      ast = %{
        "type" => "record_constr",
        "name" => "Response",
        "fields" => [
          %{
            "name" => "status",
            "value" => %{
              "type" => "literal",
              "value" => %{"literalType" => "string", "value" => "ok"}
            }
          }
        ]
      }

      assert {:ok, source} = Haskell.unparse(ast)
      assert source =~ "Response { status ="
    end

    test "unparses enum ranges" do
      ast = %{
        "type" => "enum_from_to",
        "from" => %{"type" => "literal", "value" => %{"literalType" => "int", "value" => 1}},
        "to" => %{"type" => "literal", "value" => %{"literalType" => "int", "value" => 10}}
      }

      assert {:ok, "[1 .. 10]"} = Haskell.unparse(ast)
    end

    test "unparses function type signatures" do
      ast = %{
        "type" => "type_sig",
        "names" => ["f"],
        "signature" => %{
          "type" => "type_fun",
          "argument" => %{"type" => "type_con", "name" => "Int"},
          "result" => %{"type" => "type_con", "name" => "Int"}
        }
      }

      assert {:ok, "f :: Int -> Int"} = Haskell.unparse(ast)
    end
  end

  describe "dogfooding - own parser sources" do
    @parser_sources ["priv/parsers/haskell/Parser.hs", "priv/parsers/agda/Parser.hs"]

    for path <- @parser_sources do
      test "parses and abstracts #{path} without unsupported constructs" do
        source = File.read!(unquote(path))

        assert {:ok, ast} = Haskell.parse(source)

        # Stricter guard: the raw parser AST must contain zero `unsupported`
        # / `unsupported_pat` nodes anywhere. `ToMeta` errors on these, so
        # without this scan a construct could silently degrade to a partial
        # AST while the top-level transform still succeeds.
        assert %{"unsupported" => 0, "unsupported_pat" => 0} ==
                 count_unsupported_nodes(ast),
               "parser emitted unsupported AST nodes for #{unquote(path)}"

        assert {:ok, meta_ast, _metadata} = ToMeta.transform(ast)
        assert {:container, meta, decls} = meta_ast
        assert Keyword.get(meta, :container_type) == :module
        assert is_list(decls) and decls != []
      end
    end

    test "count_unsupported_nodes/1 detects nested regressions" do
      # A construct nested deep inside a type signature must still be caught.
      ast = %{
        "type" => "module",
        "declarations" => [
          %{
            "type" => "type_sig",
            "names" => ["f"],
            "signature" => %{"type" => "unsupported", "original" => "TyX"}
          },
          %{
            "type" => "fun_bind",
            "matches" => [%{"patterns" => [%{"type" => "unsupported_pat"}]}]
          }
        ]
      }

      assert %{"unsupported" => 1, "unsupported_pat" => 1} == count_unsupported_nodes(ast)
    end

    test "count_unsupported_nodes/1 returns zero for clean trees" do
      ast = %{
        "type" => "module",
        "declarations" => [
          %{"type" => "literal", "value" => %{"literalType" => "int", "value" => 1}}
        ]
      }

      assert %{"unsupported" => 0, "unsupported_pat" => 0} == count_unsupported_nodes(ast)
    end
  end

  # Recursively counts `unsupported` / `unsupported_pat` nodes in a raw
  # Haskell parser AST. Used by the dogfooding tests to fail loudly when a
  # construct degrades instead of being properly modelled.
  @doc false
  @spec count_unsupported_nodes(term()) :: %{String.t() => non_neg_integer()}
  defp count_unsupported_nodes(ast) do
    count_unsupported_nodes(ast, %{"unsupported" => 0, "unsupported_pat" => 0})
  end

  defp count_unsupported_nodes(node, acc) do
    case node do
      %{"type" => type} = map when type in ["unsupported", "unsupported_pat"] ->
        acc = Map.update!(acc, type, &(&1 + 1))
        Enum.reduce(map, acc, fn {_k, v}, a -> count_unsupported_nodes(v, a) end)

      map when is_map(map) ->
        Enum.reduce(map, acc, fn {_k, v}, a -> count_unsupported_nodes(v, a) end)

      list when is_list(list) ->
        Enum.reduce(list, acc, fn v, a -> count_unsupported_nodes(v, a) end)

      _ ->
        acc
    end
  end
end
