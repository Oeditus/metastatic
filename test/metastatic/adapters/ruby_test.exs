defmodule Metastatic.Adapters.RubyTest do
  use ExUnit.Case, async: true

  alias Metastatic.Adapters.Ruby
  alias Metastatic.Adapters.Ruby.ToMeta

  describe "parse/1" do
    test "parses valid Ruby source code" do
      assert {:ok, ast} = Ruby.parse("x = 42")
      assert is_map(ast)
      assert ast["type"] == "lvasgn"
    end

    test "returns error for invalid syntax" do
      assert {:error, message} = Ruby.parse("x = ")
      assert message =~ "Parse error"
    end

    test "parses arithmetic expression" do
      assert {:ok, ast} = Ruby.parse("5 + 3")
      assert ast["type"] == "send"
    end

    test "parses method call" do
      assert {:ok, ast} = Ruby.parse("puts 'hello'")
      assert ast["type"] == "send"
    end
  end

  describe "ToMeta - literals" do
    test "transforms integer literals" do
      assert {:ok, {:literal, :integer, 42}, %{}} =
               ToMeta.transform(%{"type" => "int", "children" => [42]})
    end

    test "transforms float literals" do
      assert {:ok, {:literal, :float, 3.14}, %{}} =
               ToMeta.transform(%{"type" => "float", "children" => [3.14]})
    end

    test "transforms string literals" do
      assert {:ok, {:literal, :string, "hello"}, %{}} =
               ToMeta.transform(%{"type" => "str", "children" => ["hello"]})
    end

    test "transforms symbol literals" do
      assert {:ok, {:literal, :symbol, :foo}, %{}} =
               ToMeta.transform(%{"type" => "sym", "children" => [:foo]})
    end

    test "transforms true literal" do
      assert {:ok, {:literal, :boolean, true}, %{}} =
               ToMeta.transform(%{"type" => "true", "children" => []})
    end

    test "transforms false literal" do
      assert {:ok, {:literal, :boolean, false}, %{}} =
               ToMeta.transform(%{"type" => "false", "children" => []})
    end

    test "transforms nil literal" do
      assert {:ok, {:literal, :null, nil}, %{}} =
               ToMeta.transform(%{"type" => "nil", "children" => []})
    end

    test "transforms array literals" do
      ast = %{
        "type" => "array",
        "children" => [
          %{"type" => "int", "children" => [1]},
          %{"type" => "int", "children" => [2]},
          %{"type" => "int", "children" => [3]}
        ]
      }

      assert {:ok, {:literal, :collection, elements}, %{collection_type: :array}} =
               ToMeta.transform(ast)

      assert [_, _, _] = elements
    end

    test "transforms hash literals" do
      ast = %{
        "type" => "hash",
        "children" => [
          %{
            "type" => "pair",
            "children" => [
              %{"type" => "sym", "children" => [:name]},
              %{"type" => "str", "children" => ["John"]}
            ]
          }
        ]
      }

      assert {:ok, {:literal, :collection, pairs}, %{collection_type: :hash}} =
               ToMeta.transform(ast)

      assert [_] = pairs
    end
  end

  describe "ToMeta - variables" do
    test "transforms local variables" do
      assert {:ok, {:variable, "x"}, %{scope: :local}} =
               ToMeta.transform(%{"type" => "lvar", "children" => ["x"]})
    end

    test "transforms instance variables" do
      assert {:ok, {:variable, "@name"}, %{scope: :instance}} =
               ToMeta.transform(%{"type" => "ivar", "children" => ["@name"]})
    end

    test "transforms class variables" do
      assert {:ok, {:variable, "@@count"}, %{scope: :class}} =
               ToMeta.transform(%{"type" => "cvar", "children" => ["@@count"]})
    end

    test "transforms global variables" do
      assert {:ok, {:variable, "$debug"}, %{scope: :global}} =
               ToMeta.transform(%{"type" => "gvar", "children" => ["$debug"]})
    end

    test "handles atom variable names" do
      assert {:ok, {:variable, "x"}, %{scope: :local}} =
               ToMeta.transform(%{"type" => "lvar", "children" => [:x]})
    end
  end

  describe "ToMeta - binary operators" do
    test "transforms addition" do
      ast = %{
        "type" => "send",
        "children" => [
          %{"type" => "int", "children" => [5]},
          :+,
          %{"type" => "int", "children" => [3]}
        ]
      }

      assert {:ok, {:binary_op, :arithmetic, :+, left, right}, %{}} = ToMeta.transform(ast)
      assert {:literal, :integer, 5} = left
      assert {:literal, :integer, 3} = right
    end

    test "transforms multiplication" do
      ast = %{
        "type" => "send",
        "children" => [
          %{"type" => "int", "children" => [4]},
          :*,
          %{"type" => "int", "children" => [7]}
        ]
      }

      assert {:ok, {:binary_op, :arithmetic, :*, _left, _right}, %{}} = ToMeta.transform(ast)
    end

    test "transforms comparison operators" do
      ast = %{
        "type" => "send",
        "children" => [
          %{"type" => "lvar", "children" => [:x]},
          :>,
          %{"type" => "int", "children" => [10]}
        ]
      }

      assert {:ok, {:binary_op, :comparison, :>, _left, _right}, %{}} = ToMeta.transform(ast)
    end

    test "transforms equality" do
      ast = %{
        "type" => "send",
        "children" => [
          %{"type" => "lvar", "children" => [:a]},
          :==,
          %{"type" => "lvar", "children" => [:b]}
        ]
      }

      assert {:ok, {:binary_op, :comparison, :==, _left, _right}, %{}} = ToMeta.transform(ast)
    end

    test "transforms boolean and" do
      ast = %{
        "type" => "and",
        "children" => [
          %{"type" => "true", "children" => []},
          %{"type" => "false", "children" => []}
        ]
      }

      assert {:ok, {:binary_op, :boolean, :and, _left, _right}, %{}} = ToMeta.transform(ast)
    end

    test "transforms boolean or" do
      ast = %{
        "type" => "or",
        "children" => [
          %{"type" => "true", "children" => []},
          %{"type" => "false", "children" => []}
        ]
      }

      assert {:ok, {:binary_op, :boolean, :or, _left, _right}, %{}} = ToMeta.transform(ast)
    end
  end

  describe "ToMeta - unary operators" do
    test "transforms negation" do
      ast = %{
        "type" => "send",
        "children" => [
          %{"type" => "int", "children" => [42]},
          :-,
          nil
        ]
      }

      assert {:ok, {:unary_op, :arithmetic, :-, operand}, %{}} = ToMeta.transform(ast)
      assert {:literal, :integer, 42} = operand
    end

    test "transforms logical not" do
      ast = %{
        "type" => "send",
        "children" => [
          %{"type" => "true", "children" => []},
          :!,
          nil
        ]
      }

      assert {:ok, {:unary_op, :boolean, :not, _operand}, %{}} = ToMeta.transform(ast)
    end
  end

  describe "ToMeta - function calls" do
    test "transforms local method call without arguments" do
      ast = %{"type" => "send", "children" => [nil, :hello]}

      assert {:ok, {:function_call, "hello", []}, %{call_type: :local}} = ToMeta.transform(ast)
    end

    test "transforms local method call with arguments" do
      ast = %{
        "type" => "send",
        "children" => [
          nil,
          :add,
          %{"type" => "int", "children" => [1]},
          %{"type" => "int", "children" => [2]}
        ]
      }

      assert {:ok, {:function_call, "add", args}, %{call_type: :local}} = ToMeta.transform(ast)
      assert [_, _] = args
    end

    test "transforms method call with receiver" do
      ast = %{
        "type" => "send",
        "children" => [
          %{"type" => "lvar", "children" => [:obj]},
          :method,
          %{"type" => "int", "children" => [42]}
        ]
      }

      assert {:ok, {:function_call, method_name, args}, %{call_type: :instance}} =
               ToMeta.transform(ast)

      assert method_name =~ ".method"
      assert [_] = args
    end
  end

  describe "ToMeta - conditionals" do
    test "transforms if without else" do
      ast = %{
        "type" => "if",
        "children" => [
          %{"type" => "true", "children" => []},
          %{"type" => "int", "children" => [1]},
          nil
        ]
      }

      assert {:ok, {:conditional, condition, then_branch, nil}, %{}} = ToMeta.transform(ast)
      assert {:literal, :boolean, true} = condition
      assert {:literal, :integer, 1} = then_branch
    end

    test "transforms if with else" do
      ast = %{
        "type" => "if",
        "children" => [
          %{"type" => "lvar", "children" => [:x]},
          %{"type" => "int", "children" => [1]},
          %{"type" => "int", "children" => [2]}
        ]
      }

      assert {:ok, {:conditional, _condition, then_branch, else_branch}, %{}} =
               ToMeta.transform(ast)

      assert {:literal, :integer, 1} = then_branch
      assert {:literal, :integer, 2} = else_branch
    end
  end

  describe "ToMeta - assignment" do
    test "transforms local variable assignment" do
      ast = %{
        "type" => "lvasgn",
        "children" => [
          "x",
          %{"type" => "int", "children" => [42]}
        ]
      }

      assert {:ok, {:assignment, {:variable, "x"}, value}, %{scope: :local}} =
               ToMeta.transform(ast)

      assert {:literal, :integer, 42} = value
    end

    test "transforms instance variable assignment" do
      ast = %{
        "type" => "ivasgn",
        "children" => [
          "@name",
          %{"type" => "str", "children" => ["John"]}
        ]
      }

      assert {:ok, {:assignment, {:variable, "@name"}, value}, %{scope: :instance}} =
               ToMeta.transform(ast)

      assert {:literal, :string, "John"} = value
    end
  end

  describe "ToMeta - blocks" do
    test "transforms begin block with multiple statements" do
      ast = %{
        "type" => "begin",
        "children" => [
          %{"type" => "int", "children" => [1]},
          %{"type" => "int", "children" => [2]},
          %{"type" => "int", "children" => [3]}
        ]
      }

      assert {:ok, {:block, statements}, %{}} = ToMeta.transform(ast)
      assert [_, _, _] = statements
    end
  end

  describe "ToMeta - loops (M2.2 Extended Layer)" do
    test "transforms while loop" do
      ast = %{
        "type" => "while",
        "children" => [
          %{
            "type" => "send",
            "children" => [
              %{"type" => "lvar", "children" => ["x"]},
              :<,
              %{"type" => "int", "children" => [10]}
            ]
          },
          %{"type" => "int", "children" => [1]}
        ]
      }

      assert {:ok, {:loop, :while, condition, body}, %{}} = ToMeta.transform(ast)
      assert {:binary_op, :comparison, :<, _, _} = condition
      assert {:literal, :integer, 1} = body
    end

    test "transforms until loop" do
      ast = %{
        "type" => "until",
        "children" => [
          %{
            "type" => "send",
            "children" => [
              %{"type" => "lvar", "children" => ["x"]},
              :>=,
              %{"type" => "int", "children" => [10]}
            ]
          },
          %{"type" => "int", "children" => [1]}
        ]
      }

      assert {:ok, {:loop, :while, condition, body}, %{original_type: :until}} =
               ToMeta.transform(ast)

      # Until is negated condition
      assert {:unary_op, :boolean, :not, _} = condition
      assert {:literal, :integer, 1} = body
    end

    test "transforms for loop" do
      ast = %{
        "type" => "for",
        "children" => [
          %{"type" => "lvasgn", "children" => ["i"]},
          %{"type" => "array", "children" => []},
          %{"type" => "int", "children" => [1]}
        ]
      }

      assert {:ok, {:loop, :for_each, iterator, collection, body}, %{}} =
               ToMeta.transform(ast)

      assert iterator == "i"
      # Note: transform returns {:ok, meta_ast, metadata}, not metadata in tuple
      assert match?({:literal, :collection, []}, collection)
      assert {:literal, :integer, 1} = body
    end
  end

  describe "ToMeta - iterators (M2.2 Extended Layer)" do
    test "transforms .each iterator" do
      ast = %{
        "type" => "block",
        "children" => [
          %{
            "type" => "send",
            "children" => [
              %{"type" => "array", "children" => []},
              "each"
            ]
          },
          %{"type" => "args", "children" => [%{"type" => "arg", "children" => ["x"]}]},
          %{"type" => "int", "children" => [1]}
        ]
      }

      assert {:ok, {:collection_op, :each, lambda, collection}, %{}} = ToMeta.transform(ast)
      assert {:lambda, ["x"], {:literal, :integer, 1}} = lambda
      assert match?({:literal, :collection, []}, collection)
    end

    test "transforms .map iterator" do
      ast = %{
        "type" => "block",
        "children" => [
          %{
            "type" => "send",
            "children" => [
              %{"type" => "array", "children" => []},
              "map"
            ]
          },
          %{"type" => "args", "children" => [%{"type" => "arg", "children" => ["x"]}]},
          %{
            "type" => "send",
            "children" => [
              %{"type" => "lvar", "children" => ["x"]},
              :*,
              %{"type" => "int", "children" => [2]}
            ]
          }
        ]
      }

      assert {:ok, {:collection_op, :map, lambda, collection}, %{}} = ToMeta.transform(ast)
      assert {:lambda, ["x"], _body} = lambda
      assert match?({:literal, :collection, []}, collection)
    end

    test "transforms .select iterator" do
      ast = %{
        "type" => "block",
        "children" => [
          %{
            "type" => "send",
            "children" => [
              %{"type" => "array", "children" => []},
              "select"
            ]
          },
          %{"type" => "args", "children" => [%{"type" => "arg", "children" => ["x"]}]},
          %{"type" => "true", "children" => []}
        ]
      }

      assert {:ok, {:collection_op, :select, lambda, collection}, %{}} = ToMeta.transform(ast)
      assert {:lambda, ["x"], {:literal, :boolean, true}} = lambda
      assert match?({:literal, :collection, []}, collection)
    end

    test "transforms .reduce iterator with initial value" do
      ast = %{
        "type" => "block",
        "children" => [
          %{
            "type" => "send",
            "children" => [
              %{"type" => "array", "children" => []},
              "reduce",
              %{"type" => "int", "children" => [0]}
            ]
          },
          %{
            "type" => "args",
            "children" => [
              %{"type" => "arg", "children" => ["sum"]},
              %{"type" => "arg", "children" => ["x"]}
            ]
          },
          %{
            "type" => "send",
            "children" => [
              %{"type" => "lvar", "children" => ["sum"]},
              :+,
              %{"type" => "lvar", "children" => ["x"]}
            ]
          }
        ]
      }

      assert {:ok, {:collection_op, :reduce, lambda, collection, initial}, %{}} =
               ToMeta.transform(ast)

      assert {:lambda, ["sum", "x"], _body} = lambda
      assert match?({:literal, :collection, []}, collection)
      assert {:literal, :integer, 0} = initial
    end
  end

  describe "ToMeta - lambdas (M2.2 Extended Layer)" do
    test "transforms lambda with single parameter" do
      ast = %{
        "type" => "block",
        "children" => [
          %{"type" => "send", "children" => [nil, "lambda"]},
          %{"type" => "args", "children" => [%{"type" => "arg", "children" => ["x"]}]},
          %{
            "type" => "send",
            "children" => [
              %{"type" => "lvar", "children" => ["x"]},
              :+,
              %{"type" => "int", "children" => [1]}
            ]
          }
        ]
      }

      assert {:ok, {:lambda, ["x"], body}, %{}} = ToMeta.transform(ast)
      assert {:binary_op, :arithmetic, :+, _, _} = body
    end

    test "transforms lambda with multiple parameters" do
      ast = %{
        "type" => "block",
        "children" => [
          %{"type" => "send", "children" => [nil, "lambda"]},
          %{
            "type" => "args",
            "children" => [
              %{"type" => "arg", "children" => ["x"]},
              %{"type" => "arg", "children" => ["y"]}
            ]
          },
          %{
            "type" => "send",
            "children" => [
              %{"type" => "lvar", "children" => ["x"]},
              :+,
              %{"type" => "lvar", "children" => ["y"]}
            ]
          }
        ]
      }

      assert {:ok, {:lambda, ["x", "y"], body}, %{}} = ToMeta.transform(ast)
      assert {:binary_op, :arithmetic, :+, _, _} = body
    end
  end

  describe "ToMeta - pattern matching (M2.2 Extended Layer)" do
    test "transforms case/when statement" do
      ast = %{
        "type" => "case",
        "children" => [
          %{"type" => "lvar", "children" => ["x"]},
          %{
            "type" => "when",
            "children" => [
              %{"type" => "int", "children" => [1]},
              %{"type" => "sym", "children" => [:one]}
            ]
          },
          %{
            "type" => "when",
            "children" => [
              %{"type" => "int", "children" => [2]},
              %{"type" => "sym", "children" => [:two]}
            ]
          },
          %{"type" => "sym", "children" => [:other]}
        ]
      }

      assert {:ok, {:pattern_match, scrutinee, branches, else_branch}, %{}} =
               ToMeta.transform(ast)

      assert {:variable, "x"} = scrutinee
      assert [_, _] = branches
      assert {:literal, :symbol, :other} = else_branch
    end

    test "transforms case/when without else" do
      ast = %{
        "type" => "case",
        "children" => [
          %{"type" => "lvar", "children" => ["x"]},
          %{
            "type" => "when",
            "children" => [
              %{"type" => "int", "children" => [1]},
              %{"type" => "sym", "children" => [:one]}
            ]
          }
        ]
      }

      assert {:ok, {:pattern_match, _scrutinee, branches, nil}, %{}} = ToMeta.transform(ast)
      assert [_] = branches
    end
  end

  describe "ToMeta - exception handling (M2.2 Extended Layer)" do
    test "transforms begin/rescue block" do
      ast = %{
        "type" => "kwbegin",
        "children" => [
          %{
            "type" => "rescue",
            "children" => [
              %{"type" => "send", "children" => [nil, "risky_operation"]},
              %{
                "type" => "resbody",
                "children" => [
                  %{
                    "type" => "array",
                    "children" => [
                      %{"type" => "const", "children" => [nil, "StandardError"]}
                    ]
                  },
                  %{"type" => "lvasgn", "children" => ["e"]},
                  %{"type" => "send", "children" => [nil, "handle_error"]}
                ]
              }
            ]
          }
        ]
      }

      assert {:ok, {:exception_handling, try_body, handlers, nil}, %{}} =
               ToMeta.transform(ast)

      assert {:function_call, "risky_operation", []} = try_body
      assert [_] = handlers
    end

    test "transforms begin/rescue/ensure block" do
      ast = %{
        "type" => "kwbegin",
        "children" => [
          %{
            "type" => "ensure",
            "children" => [
              %{
                "type" => "rescue",
                "children" => [
                  %{"type" => "send", "children" => [nil, "risky_operation"]},
                  %{
                    "type" => "resbody",
                    "children" => [
                      %{"type" => "array", "children" => []},
                      nil,
                      %{"type" => "send", "children" => [nil, "handle_error"]}
                    ]
                  }
                ]
              },
              %{"type" => "send", "children" => [nil, "cleanup"]}
            ]
          }
        ]
      }

      assert {:ok, {:exception_handling, _try_body, _handlers, nil}, %{ensure: ensure_body}} =
               ToMeta.transform(ast)

      assert {:function_call, "cleanup", []} = ensure_body
    end

    test "transforms begin/ensure without rescue" do
      ast = %{
        "type" => "kwbegin",
        "children" => [
          %{
            "type" => "ensure",
            "children" => [
              %{"type" => "send", "children" => [nil, "operation"]},
              %{"type" => "send", "children" => [nil, "cleanup"]}
            ]
          }
        ]
      }

      assert {:ok, {:exception_handling, try_body, [], nil}, %{ensure: ensure_body}} =
               ToMeta.transform(ast)

      assert {:function_call, "operation", []} = try_body
      assert {:function_call, "cleanup", []} = ensure_body
    end
  end

  describe "ToMeta - Ruby-specific constructs (M2.3 Native Layer)" do
    test "transforms class definition" do
      ast = %{
        "type" => "class",
        "children" => [
          %{"type" => "const", "children" => [nil, "Foo"]},
          nil,
          %{"type" => "int", "children" => [42]}
        ]
      }

      assert {:ok, {:language_specific, :ruby, _ast, :class_definition}, metadata} =
               ToMeta.transform(ast)

      assert metadata.name == "Foo"
      assert metadata.superclass == nil
      assert metadata.body == {:literal, :integer, 42}
    end

    test "transforms class definition with superclass" do
      ast = %{
        "type" => "class",
        "children" => [
          %{"type" => "const", "children" => [nil, "Child"]},
          %{"type" => "const", "children" => [nil, "Parent"]},
          nil
        ]
      }

      assert {:ok, {:language_specific, :ruby, _ast, :class_definition}, metadata} =
               ToMeta.transform(ast)

      assert metadata.name == "Child"
      assert {:literal, :constant, "Parent"} = metadata.superclass
    end

    test "transforms module definition" do
      ast = %{
        "type" => "module",
        "children" => [
          %{"type" => "const", "children" => [nil, "Foo"]},
          %{"type" => "int", "children" => [42]}
        ]
      }

      assert {:ok, {:language_specific, :ruby, _ast, :module_definition}, metadata} =
               ToMeta.transform(ast)

      assert metadata.name == "Foo"
      assert metadata.body == {:literal, :integer, 42}
    end

    test "transforms method definition without params" do
      ast = %{
        "type" => "def",
        "children" => [
          "bar",
          %{"type" => "args", "children" => []},
          %{"type" => "int", "children" => [42]}
        ]
      }

      assert {:ok, {:language_specific, :ruby, _ast, :method_definition}, metadata} =
               ToMeta.transform(ast)

      assert metadata.name == "bar"
      assert metadata.params == []
      assert metadata.body == {:literal, :integer, 42}
    end

    test "transforms method definition with params" do
      ast = %{
        "type" => "def",
        "children" => [
          "add",
          %{
            "type" => "args",
            "children" => [
              %{"type" => "arg", "children" => ["x"]},
              %{"type" => "arg", "children" => ["y"]}
            ]
          },
          %{
            "type" => "send",
            "children" => [
              %{"type" => "lvar", "children" => ["x"]},
              :+,
              %{"type" => "lvar", "children" => ["y"]}
            ]
          }
        ]
      }

      assert {:ok, {:language_specific, :ruby, _ast, :method_definition}, metadata} =
               ToMeta.transform(ast)

      assert metadata.name == "add"
      assert metadata.params == ["x", "y"]
      assert {:binary_op, :arithmetic, :+, _, _} = metadata.body
    end

    test "transforms constant assignment" do
      ast = %{
        "type" => "casgn",
        "children" => [
          nil,
          "BAR",
          %{"type" => "int", "children" => [42]}
        ]
      }

      assert {:ok, {:language_specific, :ruby, _ast, :constant_assignment}, metadata} =
               ToMeta.transform(ast)

      assert metadata.name == "BAR"
      assert metadata.namespace == nil
      assert metadata.value == {:literal, :integer, 42}
    end
  end

  describe "integration - parse and transform" do
    test "parses and transforms simple assignment" do
      {:ok, ast} = Ruby.parse("x = 42")
      assert {:ok, meta_ast, _metadata} = ToMeta.transform(ast)
      assert {:assignment, {:variable, "x"}, {:literal, :integer, 42}} = meta_ast
    end

    test "parses and transforms arithmetic" do
      {:ok, ast} = Ruby.parse("5 + 3")
      assert {:ok, meta_ast, _metadata} = ToMeta.transform(ast)
      assert {:binary_op, :arithmetic, :+, _, _} = meta_ast
    end

    test "parses and transforms method call" do
      {:ok, ast} = Ruby.parse("hello")
      assert {:ok, meta_ast, _metadata} = ToMeta.transform(ast)
      assert {:function_call, "hello", []} = meta_ast
    end
  end

  describe "file_extensions/0" do
    test "returns Ruby file extensions" do
      assert [".rb"] = Ruby.file_extensions()
    end
  end
end
