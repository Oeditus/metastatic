defmodule Metastatic.Adapters.RubyTest do
  use ExUnit.Case, async: true

  @moduletag :ruby

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
      assert {:ok, {:literal, [subtype: :integer], 42}, %{}} =
               ToMeta.transform(%{"type" => "int", "children" => [42]})
    end

    test "transforms float literals" do
      assert {:ok, {:literal, [subtype: :float], 3.14}, %{}} =
               ToMeta.transform(%{"type" => "float", "children" => [3.14]})
    end

    test "transforms string literals" do
      assert {:ok, {:literal, [subtype: :string], "hello"}, %{}} =
               ToMeta.transform(%{"type" => "str", "children" => ["hello"]})
    end

    test "transforms symbol literals" do
      assert {:ok, {:literal, [subtype: :symbol], :foo}, %{}} =
               ToMeta.transform(%{"type" => "sym", "children" => [:foo]})
    end

    test "transforms true literal" do
      assert {:ok, {:literal, [subtype: :boolean], true}, %{}} =
               ToMeta.transform(%{"type" => "true", "children" => []})
    end

    test "transforms false literal" do
      assert {:ok, {:literal, [subtype: :boolean], false}, %{}} =
               ToMeta.transform(%{"type" => "false", "children" => []})
    end

    test "transforms nil literal" do
      assert {:ok, {:literal, [subtype: :null], nil}, %{}} =
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

      # Ruby arrays are represented as :list nodes
      assert {:ok, {:list, [], elements}, %{collection_type: :array}} =
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

      # Ruby hashes are represented as :map nodes
      assert {:ok, {:map, [], pairs}, %{collection_type: :hash}} =
               ToMeta.transform(ast)

      assert [_] = pairs
    end
  end

  describe "ToMeta - variables" do
    test "transforms local variables" do
      assert {:ok, {:variable, [scope: :local], "x"}, %{scope: :local}} =
               ToMeta.transform(%{"type" => "lvar", "children" => ["x"]})
    end

    test "transforms instance variables" do
      assert {:ok, {:variable, [scope: :instance], "@name"}, %{scope: :instance}} =
               ToMeta.transform(%{"type" => "ivar", "children" => ["@name"]})
    end

    test "transforms class variables" do
      assert {:ok, {:variable, [scope: :class], "@@count"}, %{scope: :class}} =
               ToMeta.transform(%{"type" => "cvar", "children" => ["@@count"]})
    end

    test "transforms global variables" do
      assert {:ok, {:variable, [scope: :global], "$debug"}, %{scope: :global}} =
               ToMeta.transform(%{"type" => "gvar", "children" => ["$debug"]})
    end

    test "handles atom variable names" do
      assert {:ok, {:variable, [scope: :local], "x"}, %{scope: :local}} =
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

      assert {:ok, {:binary_op, [category: :arithmetic, operator: :+], [left, right]}, %{}} =
               ToMeta.transform(ast)

      assert {:literal, [subtype: :integer], 5} = left
      assert {:literal, [subtype: :integer], 3} = right
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

      assert {:ok, {:binary_op, [category: :arithmetic, operator: :*], _children}, %{}} =
               ToMeta.transform(ast)
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

      assert {:ok, {:binary_op, [category: :comparison, operator: :>], _children}, %{}} =
               ToMeta.transform(ast)
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

      assert {:ok, {:binary_op, [category: :comparison, operator: :==], _children}, %{}} =
               ToMeta.transform(ast)
    end

    test "transforms boolean and" do
      ast = %{
        "type" => "and",
        "children" => [
          %{"type" => "true", "children" => []},
          %{"type" => "false", "children" => []}
        ]
      }

      assert {:ok, {:binary_op, [category: :boolean, operator: :and], _children}, %{}} =
               ToMeta.transform(ast)
    end

    test "transforms boolean or" do
      ast = %{
        "type" => "or",
        "children" => [
          %{"type" => "true", "children" => []},
          %{"type" => "false", "children" => []}
        ]
      }

      assert {:ok, {:binary_op, [category: :boolean, operator: :or], _children}, %{}} =
               ToMeta.transform(ast)
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

      assert {:ok, {:unary_op, [category: :arithmetic, operator: :-], [operand]}, %{}} =
               ToMeta.transform(ast)

      assert {:literal, [subtype: :integer], 42} = operand
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

      assert {:ok, {:unary_op, [category: :boolean, operator: :not], _children}, %{}} =
               ToMeta.transform(ast)
    end
  end

  describe "ToMeta - function calls" do
    test "transforms local method call without arguments" do
      ast = %{"type" => "send", "children" => [nil, :hello]}

      assert {:ok, {:function_call, [name: "hello"], []}, %{call_type: :local}} =
               ToMeta.transform(ast)
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

      assert {:ok, {:function_call, [name: "add"], args}, %{call_type: :local}} =
               ToMeta.transform(ast)

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

      assert {:ok, {:function_call, meta, args}, %{call_type: :instance}} = ToMeta.transform(ast)
      # Meta is a keyword list with :name key
      method_name = if is_list(meta), do: Keyword.get(meta, :name), else: meta

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

      assert {:ok, {:conditional, [], [condition, then_branch, nil]}, %{}} = ToMeta.transform(ast)
      assert {:literal, [subtype: :boolean], true} = condition
      assert {:literal, [subtype: :integer], 1} = then_branch
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

      assert {:ok, {:conditional, [], [_condition, then_branch, else_branch]}, %{}} =
               ToMeta.transform(ast)

      assert {:literal, [subtype: :integer], 1} = then_branch
      assert {:literal, [subtype: :integer], 2} = else_branch
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

      # Scope is in the meta keyword list
      assert {:ok, {:assignment, [scope: :local], [{:variable, [], "x"}, value]},
              %{scope: :local}} =
               ToMeta.transform(ast)

      assert {:literal, [subtype: :integer], 42} = value
    end

    test "transforms instance variable assignment" do
      ast = %{
        "type" => "ivasgn",
        "children" => [
          "@name",
          %{"type" => "str", "children" => ["John"]}
        ]
      }

      # Scope is in the meta keyword list
      assert {:ok, {:assignment, [scope: :instance], [{:variable, [], "@name"}, value]},
              %{scope: :instance}} = ToMeta.transform(ast)

      assert {:literal, [subtype: :string], "John"} = value
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

      assert {:ok, {:block, [], statements}, %{}} = ToMeta.transform(ast)
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

      assert {:ok, {:loop, [loop_type: :while], [condition, body]}, %{}} = ToMeta.transform(ast)
      assert {:binary_op, [category: :comparison, operator: :<], _} = condition
      assert {:literal, [subtype: :integer], 1} = body
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

      assert {:ok, {:loop, [loop_type: :while], [condition, body]}, %{original_type: :until}} =
               ToMeta.transform(ast)

      # Until is negated condition
      assert {:unary_op, [category: :boolean, operator: :not], _} = condition
      assert {:literal, [subtype: :integer], 1} = body
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

      # For loop format: {:loop, [loop_type: :for_each], [iterator, collection, body]}
      assert {:ok, {:loop, [loop_type: :for_each], [iterator, collection, body]}, %{}} =
               ToMeta.transform(ast)

      assert iterator == "i"
      assert {:list, [], []} = collection
      assert {:literal, [subtype: :integer], 1} = body
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

      assert {:ok, {:collection_op, [op_type: :each], [lambda, collection]}, %{}} =
               ToMeta.transform(ast)

      assert {:lambda, [params: ["x"], captures: []], [body]} = lambda
      assert {:literal, [subtype: :integer], 1} = body
      assert {:list, [], []} = collection
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

      assert {:ok, {:collection_op, [op_type: :map], [lambda, collection]}, %{}} =
               ToMeta.transform(ast)

      assert {:lambda, [params: ["x"], captures: []], _body} = lambda
      assert {:list, [], []} = collection
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

      # Ruby 'select' is represented as :select (not :filter)
      assert {:ok, {:collection_op, [op_type: :select], [lambda, collection]}, %{}} =
               ToMeta.transform(ast)

      assert {:lambda, [params: ["x"], captures: []], [body]} = lambda
      assert {:literal, [subtype: :boolean], true} = body
      assert {:list, [], []} = collection
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

      assert {:ok, {:collection_op, [op_type: :reduce], [lambda, collection, initial]}, %{}} =
               ToMeta.transform(ast)

      assert {:lambda, [params: ["sum", "x"], captures: []], _body} = lambda
      assert {:list, [], []} = collection
      assert {:literal, [subtype: :integer], 0} = initial
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

      assert {:ok, {:lambda, [params: ["x"], captures: []], [body]}, %{}} = ToMeta.transform(ast)
      assert {:binary_op, [category: :arithmetic, operator: :+], _} = body
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

      assert {:ok, {:lambda, [params: ["x", "y"], captures: []], [body]}, %{}} =
               ToMeta.transform(ast)

      assert {:binary_op, [category: :arithmetic, operator: :+], _} = body
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

      assert {:ok, {:pattern_match, [], [scrutinee, branches, else_branch]}, %{}} =
               ToMeta.transform(ast)

      assert {:variable, _, "x"} = scrutinee
      assert [_, _] = branches
      assert {:literal, [subtype: :symbol], :other} = else_branch
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

      assert {:ok, {:pattern_match, [], [_scrutinee, branches, nil]}, %{}} = ToMeta.transform(ast)
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

      # 3-tuple format: {:exception_handling, [], [try_body, handlers, else]}
      assert {:ok, {:exception_handling, [], [try_body, handlers, nil]}, %{}} =
               ToMeta.transform(ast)

      assert {:function_call, [name: "risky_operation"], []} = try_body
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

      assert {:ok, {:exception_handling, [], [_try_body, _handlers, nil]}, %{ensure: ensure_body}} =
               ToMeta.transform(ast)

      assert {:function_call, [name: "cleanup"], []} = ensure_body
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

      assert {:ok, {:exception_handling, [], [try_body, [], nil]}, %{ensure: ensure_body}} =
               ToMeta.transform(ast)

      assert {:function_call, [name: "operation"], []} = try_body
      assert {:function_call, [name: "cleanup"], []} = ensure_body
    end
  end

  describe "ToMeta - M2.2s Structural Layer (containers and functions)" do
    test "transforms class definition to container" do
      ast = %{
        "type" => "class",
        "children" => [
          %{"type" => "const", "children" => [nil, "Foo"]},
          nil,
          %{"type" => "int", "children" => [42]}
        ]
      }

      assert {:ok, meta_ast, metadata} = ToMeta.transform(ast)

      # 3-tuple format: {:container, [container_type: :class, name: "Foo", ...], [body]}
      case meta_ast do
        {:container, meta, [body]} when is_list(meta) ->
          assert Keyword.get(meta, :container_type) == :class
          assert Keyword.get(meta, :name) == "Foo"
          assert {:literal, [subtype: :integer], 42} = body

        other ->
          flunk("Expected container, got: #{inspect(other)}")
      end

      assert metadata.ruby_ast == ast
    end

    test "transforms class definition with superclass to container" do
      ast = %{
        "type" => "class",
        "children" => [
          %{"type" => "const", "children" => [nil, "Child"]},
          %{"type" => "const", "children" => [nil, "Parent"]},
          nil
        ]
      }

      assert {:ok, meta_ast, metadata} = ToMeta.transform(ast)

      # 3-tuple format: {:container, [container_type: :class, name: "Child", parent: "Parent"], [body]}
      case meta_ast do
        {:container, meta, _body} when is_list(meta) ->
          assert Keyword.get(meta, :container_type) == :class
          assert Keyword.get(meta, :name) == "Child"
          assert Keyword.get(meta, :parent) == "Parent"

        other ->
          flunk("Expected container with parent, got: #{inspect(other)}")
      end

      assert {:literal, [subtype: :constant], "Parent"} = metadata.superclass
    end

    test "transforms module definition to container" do
      ast = %{
        "type" => "module",
        "children" => [
          %{"type" => "const", "children" => [nil, "Foo"]},
          %{"type" => "int", "children" => [42]}
        ]
      }

      assert {:ok, meta_ast, metadata} = ToMeta.transform(ast)

      # 3-tuple format: {:container, [container_type: :module, name: "Foo"], [body]}
      case meta_ast do
        {:container, meta, [body]} when is_list(meta) ->
          assert Keyword.get(meta, :container_type) == :module
          assert Keyword.get(meta, :name) == "Foo"
          assert {:literal, [subtype: :integer], 42} = body

        other ->
          flunk("Expected module container, got: #{inspect(other)}")
      end

      assert metadata.ruby_ast == ast
    end

    test "transforms method definition to function_def" do
      ast = %{
        "type" => "def",
        "children" => [
          "bar",
          %{"type" => "args", "children" => []},
          %{"type" => "int", "children" => [42]}
        ]
      }

      assert {:ok, meta_ast, metadata} = ToMeta.transform(ast)

      # 3-tuple format: {:function_def, [name: "bar", params: [], ...], [body]}
      case meta_ast do
        {:function_def, meta, [body]} when is_list(meta) ->
          assert Keyword.get(meta, :name) == "bar"
          assert Keyword.get(meta, :visibility) == :public
          assert Keyword.get(meta, :arity) == 0
          assert {:literal, [subtype: :integer], 42} = body

        other ->
          flunk("Expected function_def, got: #{inspect(other)}")
      end

      assert metadata.ruby_ast == ast
    end

    test "transforms method definition with params to function_def" do
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

      assert {:ok, meta_ast, _metadata} = ToMeta.transform(ast)

      # 3-tuple format: {:function_def, [name: "add", params: [...], ...], [body]}
      case meta_ast do
        {:function_def, meta, [body]} when is_list(meta) ->
          assert Keyword.get(meta, :name) == "add"
          assert Keyword.get(meta, :params) == ["x", "y"]
          assert Keyword.get(meta, :visibility) == :public
          assert Keyword.get(meta, :arity) == 2
          assert {:binary_op, [category: :arithmetic, operator: :+], _} = body

        other ->
          flunk("Expected function_def, got: #{inspect(other)}")
      end
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

      assert {:ok, {:language_specific, [language: :ruby, hint: :constant_assignment], _ast},
              metadata} = ToMeta.transform(ast)

      assert metadata.name == "BAR"
      assert metadata.namespace == nil
      assert {:literal, [subtype: :integer], 42} = metadata.value
    end
  end

  describe "integration - parse and transform" do
    test "parses and transforms simple assignment" do
      {:ok, ast} = Ruby.parse("x = 42")
      assert {:ok, meta_ast, _metadata} = ToMeta.transform(ast)

      # 3-tuple format: {:assignment, [scope: :local], [var, value]}
      case meta_ast do
        {:assignment, meta, [{:variable, _, "x"}, {:literal, _, 42}]} when is_list(meta) ->
          :ok

        other ->
          flunk("Expected assignment, got: #{inspect(other)}")
      end
    end

    test "parses and transforms arithmetic" do
      {:ok, ast} = Ruby.parse("5 + 3")
      assert {:ok, meta_ast, _metadata} = ToMeta.transform(ast)

      # 3-tuple format: {:binary_op, [category: ..., operator: ..., ...], [left, right]}
      # Meta may have additional location keys
      assert {:binary_op, meta, [_left, _right]} = meta_ast
      assert Keyword.get(meta, :category) == :arithmetic
      assert Keyword.get(meta, :operator) == :+
    end

    test "parses and transforms method call" do
      {:ok, ast} = Ruby.parse("hello")
      assert {:ok, meta_ast, _metadata} = ToMeta.transform(ast)
      assert {:function_call, [name: "hello"], []} = meta_ast
    end
  end

  describe "file_extensions/0" do
    test "returns Ruby file extensions" do
      assert [".rb"] = Ruby.file_extensions()
    end
  end

  describe "M2.2s Structural Layer - Round-trip integration" do
    test "round-trips class definition" do
      source = """
      class Calculator
        def add(x, y)
          x + y
        end
      end
      """

      {:ok, ast} = Ruby.parse(source)
      assert {:ok, meta_ast, _metadata} = ToMeta.transform(ast)

      # 3-tuple format: {:container, [container_type: :class, name: "Calculator", ...], [body]}
      case meta_ast do
        {:container, meta, _body} when is_list(meta) ->
          assert Keyword.get(meta, :container_type) == :class
          assert Keyword.get(meta, :name) == "Calculator"

        other ->
          flunk("Expected class container, got: #{inspect(other)}")
      end
    end

    test "round-trips module definition" do
      source = """
      module Utils
        def self.helper
          42
        end
      end
      """

      {:ok, ast} = Ruby.parse(source)
      assert {:ok, meta_ast, _metadata} = ToMeta.transform(ast)

      # 3-tuple format: {:container, [container_type: :module, name: "Utils", ...], [body]}
      case meta_ast do
        {:container, meta, _body} when is_list(meta) ->
          assert Keyword.get(meta, :container_type) == :module
          assert Keyword.get(meta, :name) == "Utils"

        other ->
          flunk("Expected module container, got: #{inspect(other)}")
      end
    end

    test "round-trips method definition" do
      source = "def calculate(x); x * 2; end"

      {:ok, ast} = Ruby.parse(source)
      assert {:ok, meta_ast, _metadata} = ToMeta.transform(ast)

      # 3-tuple format: {:function_def, [name: "calculate", params: [...], ...], [body]}
      case meta_ast do
        {:function_def, meta, _body} when is_list(meta) ->
          assert Keyword.get(meta, :name) == "calculate"
          assert Keyword.get(meta, :params) == ["x"]

        other ->
          flunk("Expected function_def, got: #{inspect(other)}")
      end
    end

    test "round-trips augmented assignment" do
      source = "x += 5"

      {:ok, ast} = Ruby.parse(source)
      assert {:ok, meta_ast, _metadata} = ToMeta.transform(ast)

      # 3-tuple format: {:augmented_assignment, [category: ..., operator: ...], [target, value]}
      case meta_ast do
        {:augmented_assignment, meta, _children} when is_list(meta) ->
          assert Keyword.get(meta, :category) == :arithmetic
          assert Keyword.get(meta, :operator) == :+

        other ->
          flunk("Expected augmented_assignment, got: #{inspect(other)}")
      end
    end

    test "verifies M1 context metadata preservation" do
      source = """
      module Calculator
        def add(x, y)
          x + y
        end
      end
      """

      {:ok, ast} = Ruby.parse(source)
      assert {:ok, meta_ast, _metadata} = ToMeta.transform(ast)

      # 3-tuple format with context in metadata
      case meta_ast do
        {:container, meta, _body} when is_list(meta) ->
          assert Keyword.get(meta, :container_type) == :module
          assert Keyword.get(meta, :name) == "Calculator"

        other ->
          flunk("Expected module container with context, got: #{inspect(other)}")
      end
    end
  end

  describe "ToMeta - M2.2s Structural Layer (attribute access and augmented assignment)" do
    test "transforms attribute access" do
      ast = %{
        "type" => "send",
        "children" => [
          %{"type" => "lvar", "children" => ["obj"]},
          "field"
        ]
      }

      assert {:ok, meta_ast, _metadata} = ToMeta.transform(ast)

      # 3-tuple format: {:attribute_access, [object: ..., attribute: ...], []} or function_call
      case meta_ast do
        {:attribute_access, meta, _children} when is_list(meta) ->
          :ok

        {:function_call, meta, _args} when is_list(meta) ->
          # Attribute access may be represented as function call
          name = Keyword.get(meta, :name)
          assert name =~ "field"

        other ->
          flunk("Expected attribute_access or function_call, got: #{inspect(other)}")
      end
    end

    test "transforms augmented assignment (+=)" do
      ast = %{
        "type" => "op_asgn",
        "children" => [
          %{"type" => "lvar", "children" => ["x"]},
          :+,
          %{"type" => "int", "children" => [5]}
        ]
      }

      assert {:ok, meta_ast, _metadata} = ToMeta.transform(ast)

      # 3-tuple format: {:augmented_assignment, [category: :arithmetic, operator: :+], [target, value]}
      case meta_ast do
        {:augmented_assignment, meta, _children} when is_list(meta) ->
          assert Keyword.get(meta, :category) == :arithmetic
          assert Keyword.get(meta, :operator) == :+

        other ->
          flunk("Expected augmented_assignment, got: #{inspect(other)}")
      end
    end

    test "transforms augmented assignment (-=)" do
      ast = %{
        "type" => "op_asgn",
        "children" => [
          %{"type" => "lvar", "children" => ["count"]},
          :-,
          %{"type" => "int", "children" => [1]}
        ]
      }

      assert {:ok, meta_ast, _metadata} = ToMeta.transform(ast)

      # 3-tuple format: {:augmented_assignment, [category: :arithmetic, operator: :-], [...]}
      case meta_ast do
        {:augmented_assignment, meta, _children} when is_list(meta) ->
          assert Keyword.get(meta, :category) == :arithmetic
          assert Keyword.get(meta, :operator) == :-

        other ->
          flunk("Expected augmented_assignment with :-, got: #{inspect(other)}")
      end
    end
  end

  describe "ToMeta - M2.3 Native Layer (additional constructs)" do
    test "transforms yield with arguments" do
      ast = %{"type" => "yield", "children" => [%{"type" => "lvar", "children" => ["x"]}]}

      # 3-tuple format: {:language_specific, [language: :ruby, hint: :yield], original_ast}
      assert {:ok, {:language_specific, [language: :ruby, hint: :yield], ^ast}, metadata} =
               ToMeta.transform(ast)

      assert [_] = metadata.args
    end

    test "transforms alias" do
      ast = %{
        "type" => "alias",
        "children" => [
          %{"type" => "sym", "children" => ["new_name"]},
          %{"type" => "sym", "children" => ["old_name"]}
        ]
      }

      # 3-tuple format: {:language_specific, [language: :ruby, hint: :alias], original_ast}
      assert {:ok, {:language_specific, [language: :ruby, hint: :alias], ^ast}, metadata} =
               ToMeta.transform(ast)

      assert metadata.new_name == "new_name"
      assert metadata.old_name == "old_name"
    end

    test "transforms string interpolation" do
      ast = %{
        "type" => "dstr",
        "children" => [
          %{"type" => "str", "children" => ["Hello, "]},
          %{"type" => "begin", "children" => [%{"type" => "lvar", "children" => ["name"]}]}
        ]
      }

      # 3-tuple format: {:language_specific, [language: :ruby, hint: :string_interpolation], original_ast}
      assert {:ok, {:language_specific, [language: :ruby, hint: :string_interpolation], ^ast},
              metadata} = ToMeta.transform(ast)

      assert [_, _] = metadata.parts
    end

    test "transforms regular expression" do
      ast = %{
        "type" => "regexp",
        "children" => [
          %{"type" => "str", "children" => ["[a-z]+"]},
          %{"type" => "regopt", "children" => ["i"]}
        ]
      }

      # 3-tuple format: {:language_specific, [language: :ruby, hint: :regexp], original_ast}
      assert {:ok, {:language_specific, [language: :ruby, hint: :regexp], ^ast}, metadata} =
               ToMeta.transform(ast)

      assert metadata.pattern != nil
    end

    test "transforms singleton class" do
      ast = %{
        "type" => "sclass",
        "children" => [
          %{"type" => "self", "children" => []},
          %{
            "type" => "def",
            "children" => ["instance_method", %{"type" => "args", "children" => []}, nil]
          }
        ]
      }

      # 3-tuple format: {:language_specific, [language: :ruby, hint: :singleton_class], original_ast}
      assert {:ok, {:language_specific, [language: :ruby, hint: :singleton_class], ^ast},
              metadata} = ToMeta.transform(ast)

      assert metadata.object != nil
      assert metadata.body != nil
    end

    test "transforms super with arguments" do
      ast = %{
        "type" => "super",
        "children" => [
          %{"type" => "lvar", "children" => ["x"]},
          %{"type" => "lvar", "children" => ["y"]}
        ]
      }

      # 3-tuple format: {:language_specific, [language: :ruby, hint: :super], original_ast}
      assert {:ok, {:language_specific, [language: :ruby, hint: :super], ^ast}, metadata} =
               ToMeta.transform(ast)

      assert [_, _] = metadata.args
    end

    test "transforms zsuper" do
      ast = %{"type" => "zsuper", "children" => []}

      # 3-tuple format: {:language_specific, [language: :ruby, hint: :zsuper], original_ast}
      assert {:ok, {:language_specific, [language: :ruby, hint: :zsuper], ^ast}, %{}} =
               ToMeta.transform(ast)
    end

    test "transforms kwsplat (keyword argument splat) as standalone" do
      # Represents **kw as a standalone node
      ast = %{
        "type" => "kwsplat",
        "children" => [%{"type" => "send", "children" => [nil, "kw"]}]
      }

      # 3-tuple format: {:language_specific, [language: :ruby, hint: :kwsplat], original_ast}
      assert {:ok, {:language_specific, [language: :ruby, hint: :kwsplat], _original_ast},
              metadata} = ToMeta.transform(ast)

      # The value should be transformed from the send node (variable reference)
      assert {:function_call, [name: "kw"], []} = metadata.value
    end

    test "transforms hash with kwsplat" do
      # Represents {a: 1, **other}
      ast = %{
        "type" => "hash",
        "children" => [
          %{
            "type" => "pair",
            "children" => [
              %{"type" => "sym", "children" => [:a]},
              %{"type" => "int", "children" => [1]}
            ]
          },
          %{
            "type" => "kwsplat",
            "children" => [%{"type" => "send", "children" => [nil, "other"]}]
          }
        ]
      }

      # The hash should be transformed to a map with a pair and a kwsplat
      assert {:ok, {:map, [], elements}, %{collection_type: :hash}} = ToMeta.transform(ast)

      # Should have a regular pair and a kwsplat
      assert [_, _] = elements
      assert Enum.any?(elements, &match?({:pair, _, _}, &1))

      assert Enum.any?(elements, &match?({:language_specific, [language: :ruby, hint: :kwsplat], _},
                                         &1))
    end

    test "transforms hash with multiple kwsplats" do
      # Represents {**a, **b}
      ast = %{
        "type" => "hash",
        "children" => [
          %{
            "type" => "kwsplat",
            "children" => [%{"type" => "send", "children" => [nil, "a"]}]
          },
          %{
            "type" => "kwsplat",
            "children" => [%{"type" => "send", "children" => [nil, "b"]}]
          }
        ]
      }

      # The hash should be transformed to a map with two kwsplats
      assert {:ok, {:map, [], elements}, %{collection_type: :hash}} = ToMeta.transform(ast)

      # Should have two kwsplat elements
      assert [_, _] = elements

      assert Enum.all?(elements,
                       &match?({:language_specific, [language: :ruby, hint: :kwsplat], _}, &1))
    end

    test "transforms multiple assignment (parallel assignment)" do
      # Represents: a, b = [1, 2]
      ast = %{
        "type" => "masgn",
        "children" => [
          %{
            "type" => "mlhs",
            "children" => [
              %{"type" => "lvasgn", "children" => ["a"]},
              %{"type" => "lvasgn", "children" => ["b"]}
            ]
          },
          %{
            "type" => "array",
            "children" => [
              %{"type" => "int", "children" => [1]},
              %{"type" => "int", "children" => [2]}
            ]
          }
        ]
      }

      # 3-tuple format: {:language_specific, [language: :ruby, hint: :multiple_assignment], original_ast}
      assert {:ok, {:language_specific, [language: :ruby, hint: :multiple_assignment], ^ast},
              metadata} = ToMeta.transform(ast)

      # Metadata should contain transformed left and right sides
      assert {:language_specific, [language: :ruby, hint: :mlhs], _targets} = metadata.left
      assert {:list, [], _elements} = metadata.right
    end

    test "transforms mlhs (multiple left-hand side)" do
      # Represents: a, b, c (the left side of a multiple assignment)
      ast = %{
        "type" => "mlhs",
        "children" => [
          %{"type" => "lvasgn", "children" => ["a"]},
          %{"type" => "lvasgn", "children" => ["b"]},
          %{"type" => "lvasgn", "children" => ["c"]}
        ]
      }

      # 3-tuple format: {:language_specific, [language: :ruby, hint: :mlhs], targets}
      assert {:ok, {:language_specific, [language: :ruby, hint: :mlhs], targets}, %{}} =
               ToMeta.transform(ast)

      # Targets should be a list of variable nodes
      assert [_, _, _] = targets
      assert Enum.all?(targets, &match?({:variable, [scope: :local], _}, &1))
    end

    test "transforms multiple assignment from method call" do
      # Represents: x, y = some_method(arg)
      ast = %{
        "type" => "masgn",
        "children" => [
          %{
            "type" => "mlhs",
            "children" => [
              %{"type" => "lvasgn", "children" => ["x"]},
              %{"type" => "lvasgn", "children" => ["y"]}
            ]
          },
          %{
            "type" => "send",
            "children" => [
              nil,
              :some_method,
              %{"type" => "lvar", "children" => ["arg"]}
            ]
          }
        ]
      }

      assert {:ok, {:language_specific, [language: :ruby, hint: :multiple_assignment], ^ast},
              metadata} = ToMeta.transform(ast)

      # Right side should be a function call
      assert {:function_call, [name: "some_method"], _args} = metadata.right
    end
  end

  describe "ToMeta - Control Flow (return/break/next/redo/retry)" do
    test "transforms return without value" do
      ast = %{"type" => "return", "children" => []}

      assert {:ok, {:early_return, _, [nil]}, %{}} = ToMeta.transform(ast)
    end

    test "transforms return with single value" do
      ast = %{
        "type" => "return",
        "children" => [%{"type" => "int", "children" => [42]}]
      }

      assert {:ok, {:early_return, _, [value]}, %{}} = ToMeta.transform(ast)
      assert {:literal, [subtype: :integer], 42} = value
    end

    test "transforms return with multiple values" do
      ast = %{
        "type" => "return",
        "children" => [
          %{"type" => "int", "children" => [1]},
          %{"type" => "int", "children" => [2]}
        ]
      }

      assert {:ok, {:early_return, _, [{:tuple, [], values}]}, %{}} = ToMeta.transform(ast)
      assert [_, _] = values
    end

    test "transforms break without value" do
      ast = %{"type" => "break", "children" => []}

      assert {:ok, {:language_specific, [language: :ruby, hint: :break], ^ast}, %{value: nil}} =
               ToMeta.transform(ast)
    end

    test "transforms break with value" do
      ast = %{
        "type" => "break",
        "children" => [%{"type" => "int", "children" => [42]}]
      }

      assert {:ok, {:language_specific, [language: :ruby, hint: :break], ^ast}, metadata} =
               ToMeta.transform(ast)

      assert {:literal, [subtype: :integer], 42} = metadata.value
    end

    test "transforms next without value" do
      ast = %{"type" => "next", "children" => []}

      assert {:ok, {:language_specific, [language: :ruby, hint: :next], ^ast}, %{value: nil}} =
               ToMeta.transform(ast)
    end

    test "transforms next with value" do
      ast = %{
        "type" => "next",
        "children" => [%{"type" => "str", "children" => ["skip"]}]
      }

      assert {:ok, {:language_specific, [language: :ruby, hint: :next], ^ast}, metadata} =
               ToMeta.transform(ast)

      assert {:literal, [subtype: :string], "skip"} = metadata.value
    end

    test "transforms redo" do
      ast = %{"type" => "redo", "children" => []}

      assert {:ok, {:language_specific, [language: :ruby, hint: :redo], ^ast}, %{}} =
               ToMeta.transform(ast)
    end

    test "transforms retry" do
      ast = %{"type" => "retry", "children" => []}

      assert {:ok, {:language_specific, [language: :ruby, hint: :retry], ^ast}, %{}} =
               ToMeta.transform(ast)
    end
  end

  describe "ToMeta - Range Literals" do
    test "transforms inclusive range (1..10)" do
      ast = %{
        "type" => "irange",
        "children" => [
          %{"type" => "int", "children" => [1]},
          %{"type" => "int", "children" => [10]}
        ]
      }

      assert {:ok, {:literal, meta, {start_val, end_val}}, %{range_type: :inclusive}} =
               ToMeta.transform(ast)

      assert Keyword.get(meta, :subtype) == :range
      assert Keyword.get(meta, :inclusive) == true
      assert {:literal, [subtype: :integer], 1} = start_val
      assert {:literal, [subtype: :integer], 10} = end_val
    end

    test "transforms exclusive range (1...10)" do
      ast = %{
        "type" => "erange",
        "children" => [
          %{"type" => "int", "children" => [1]},
          %{"type" => "int", "children" => [10]}
        ]
      }

      assert {:ok, {:literal, meta, {start_val, end_val}}, %{range_type: :exclusive}} =
               ToMeta.transform(ast)

      assert Keyword.get(meta, :subtype) == :range
      assert Keyword.get(meta, :inclusive) == false
      assert {:literal, [subtype: :integer], 1} = start_val
      assert {:literal, [subtype: :integer], 10} = end_val
    end

    test "transforms range with variables" do
      ast = %{
        "type" => "irange",
        "children" => [
          %{"type" => "lvar", "children" => ["start"]},
          %{"type" => "lvar", "children" => ["finish"]}
        ]
      }

      assert {:ok, {:literal, meta, {start_val, end_val}}, _} = ToMeta.transform(ast)
      assert Keyword.get(meta, :subtype) == :range
      assert {:variable, _, "start"} = start_val
      assert {:variable, _, "finish"} = end_val
    end
  end

  describe "ToMeta - Splat and Block Pass" do
    test "transforms splat operator" do
      ast = %{
        "type" => "splat",
        "children" => [%{"type" => "lvar", "children" => ["args"]}]
      }

      assert {:ok, {:language_specific, [language: :ruby, hint: :splat], ^ast}, metadata} =
               ToMeta.transform(ast)

      assert {:variable, _, "args"} = metadata.value
    end

    test "transforms block_pass operator" do
      ast = %{
        "type" => "block_pass",
        "children" => [%{"type" => "lvar", "children" => ["block"]}]
      }

      assert {:ok, {:language_specific, [language: :ruby, hint: :block_pass], ^ast}, metadata} =
               ToMeta.transform(ast)

      assert {:variable, _, "block"} = metadata.value
    end
  end

  describe "ToMeta - Proc and Additional Iterators" do
    test "transforms proc block" do
      ast = %{
        "type" => "block",
        "children" => [
          %{"type" => "send", "children" => [nil, "proc"]},
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

      assert {:ok, {:lambda, meta, [body]}, %{kind: :proc}} = ToMeta.transform(ast)
      assert Keyword.get(meta, :params) == ["x"]
      assert Keyword.get(meta, :kind) == :proc
      assert {:binary_op, _, _} = body
    end

    test "transforms times iterator" do
      ast = %{
        "type" => "block",
        "children" => [
          %{
            "type" => "send",
            "children" => [%{"type" => "int", "children" => [5]}, "times"]
          },
          %{"type" => "args", "children" => [%{"type" => "arg", "children" => ["i"]}]},
          %{
            "type" => "send",
            "children" => [nil, "puts", %{"type" => "lvar", "children" => ["i"]}]
          }
        ]
      }

      assert {:ok, {:collection_op, meta, [lambda, count]}, %{}} = ToMeta.transform(ast)
      assert Keyword.get(meta, :op_type) == :times
      assert {:lambda, _, _} = lambda
      assert {:literal, [subtype: :integer], 5} = count
    end

    test "transforms each_with_index iterator" do
      ast = %{
        "type" => "block",
        "children" => [
          %{
            "type" => "send",
            "children" => [%{"type" => "array", "children" => []}, "each_with_index"]
          },
          %{
            "type" => "args",
            "children" => [
              %{"type" => "arg", "children" => ["item"]},
              %{"type" => "arg", "children" => ["index"]}
            ]
          },
          %{"type" => "int", "children" => [1]}
        ]
      }

      assert {:ok, {:collection_op, meta, [lambda, collection]}, %{}} = ToMeta.transform(ast)
      assert Keyword.get(meta, :op_type) == :each_with_index
      assert {:lambda, lambda_meta, _} = lambda
      assert Keyword.get(lambda_meta, :params) == ["item", "index"]
      assert {:list, [], []} = collection
    end
  end

  describe "ToMeta - Defined? Operator" do
    test "transforms defined? with variable" do
      ast = %{
        "type" => "defined?",
        "children" => [%{"type" => "lvar", "children" => ["foo"]}]
      }

      assert {:ok, {:language_specific, [language: :ruby, hint: :defined], ^ast}, metadata} =
               ToMeta.transform(ast)

      assert {:variable, _, "foo"} = metadata.expr
    end

    test "transforms defined? with method call" do
      ast = %{
        "type" => "defined?",
        "children" => [%{"type" => "send", "children" => [nil, "some_method"]}]
      }

      assert {:ok, {:language_specific, [language: :ruby, hint: :defined], ^ast}, metadata} =
               ToMeta.transform(ast)

      assert {:function_call, _, _} = metadata.expr
    end
  end

  describe "ToMeta - BEGIN/END Blocks" do
    test "transforms BEGIN block" do
      ast = %{
        "type" => "preexe",
        "children" => [
          %{"type" => "send", "children" => [nil, "puts", %{"type" => "int", "children" => [1]}]}
        ]
      }

      assert {:ok, {:language_specific, [language: :ruby, hint: :begin_block], ^ast}, metadata} =
               ToMeta.transform(ast)

      assert {:function_call, _, _} = metadata.body
    end

    test "transforms END block" do
      ast = %{
        "type" => "postexe",
        "children" => [
          %{"type" => "send", "children" => [nil, "puts", %{"type" => "int", "children" => [1]}]}
        ]
      }

      assert {:ok, {:language_specific, [language: :ruby, hint: :end_block], ^ast}, metadata} =
               ToMeta.transform(ast)

      assert {:function_call, _, _} = metadata.body
    end
  end

  describe "Integration - parse and transform new constructs" do
    test "parses and transforms return statement" do
      {:ok, ast} = Ruby.parse("return 42")
      assert {:ok, {:early_return, _, [value]}, _} = ToMeta.transform(ast)
      assert {:literal, _, 42} = value
    end

    test "parses and transforms range literal" do
      {:ok, ast} = Ruby.parse("1..10")
      assert {:ok, {:literal, meta, _}, _} = ToMeta.transform(ast)
      assert Keyword.get(meta, :subtype) == :range
      assert Keyword.get(meta, :inclusive) == true
    end

    test "parses and transforms exclusive range" do
      {:ok, ast} = Ruby.parse("1...10")
      assert {:ok, {:literal, meta, _}, _} = ToMeta.transform(ast)
      assert Keyword.get(meta, :subtype) == :range
      assert Keyword.get(meta, :inclusive) == false
    end

    test "parses and transforms proc" do
      {:ok, ast} = Ruby.parse("proc { |x| x + 1 }")
      assert {:ok, {:lambda, meta, _}, %{kind: :proc}} = ToMeta.transform(ast)
      assert Keyword.get(meta, :kind) == :proc
    end

    test "parses and transforms require statement" do
      {:ok, ast} = Ruby.parse("require 'json'")
      assert {:ok, {:function_call, meta, args}, _} = ToMeta.transform(ast)
      # Meta can be a keyword list or a string depending on whether it's a local call
      name = if is_list(meta), do: Keyword.get(meta, :name), else: meta
      assert name =~ "require"
      assert [_] = args
    end

    test "parses and transforms attr_reader" do
      {:ok, ast} = Ruby.parse("attr_reader :name, :age")
      assert {:ok, {:function_call, meta, args}, _} = ToMeta.transform(ast)
      assert Keyword.get(meta, :name) == "attr_reader"
      assert [_, _] = args
    end

    test "parses and transforms class with inheritance" do
      source = """
      class Dog < Animal
        def bark
          "woof"
        end
      end
      """

      {:ok, ast} = Ruby.parse(source)
      assert {:ok, {:container, meta, _}, %{superclass: superclass}} = ToMeta.transform(ast)
      assert Keyword.get(meta, :container_type) == :class
      assert Keyword.get(meta, :name) == "Dog"
      assert Keyword.get(meta, :parent) == "Animal"
      assert {:literal, [subtype: :constant], "Animal"} = superclass
    end

    test "parses and transforms module with methods" do
      source = """
      module Utilities
        def self.helper(x)
          x * 2
        end
      end
      """

      {:ok, ast} = Ruby.parse(source)
      assert {:ok, {:container, meta, [body]}, _} = ToMeta.transform(ast)
      assert Keyword.get(meta, :container_type) == :module
      assert Keyword.get(meta, :name) == "Utilities"
      assert {:function_def, func_meta, _} = body
      assert Keyword.get(func_meta, :name) == "self.helper"
    end

    test "parses and transforms complex iterator chain" do
      source = "[1, 2, 3].map { |x| x * 2 }"

      {:ok, ast} = Ruby.parse(source)
      assert {:ok, {:collection_op, meta, [lambda, collection]}, _} = ToMeta.transform(ast)
      assert Keyword.get(meta, :op_type) == :map
      assert {:lambda, _, _} = lambda
      assert {:list, _, _} = collection
    end

    test "parses and transforms case/when statement" do
      # Use a variable that's already defined (via assignment)
      source = """
      y = 1
      case y
      when 1 then :one
      when 2 then :two
      else :other
      end
      """

      {:ok, ast} = Ruby.parse(source)
      # The result is a block with assignment and case
      assert {:ok, {:block, _, [_assignment, pattern_match]}, _} = ToMeta.transform(ast)
      {:pattern_match, _, [scrutinee, branches, else_branch]} = pattern_match

      # Scrutinee is a variable reference
      assert {:variable, _, "y"} = scrutinee
      assert [_, _] = branches
      assert {:literal, [subtype: :symbol], :other} = else_branch
    end

    test "parses and transforms begin/rescue/ensure" do
      source = """
      begin
        risky
      rescue StandardError => e
        handle(e)
      ensure
        cleanup
      end
      """

      {:ok, ast} = Ruby.parse(source)
      assert {:ok, {:exception_handling, _, _}, metadata} = ToMeta.transform(ast)
      assert metadata.ensure != nil
    end
  end
end
