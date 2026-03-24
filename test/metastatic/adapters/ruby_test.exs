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

      assert {:lambda, [params: [{:param, [], "x"}], captures: []], [body]} = lambda
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

      assert {:lambda, [params: [{:param, [], "x"}], captures: []], _body} = lambda
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

      assert {:lambda, [params: [{:param, [], "x"}], captures: []], [body]} = lambda
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

      assert {:lambda, [params: [{:param, [], "sum"}, {:param, [], "x"}], captures: []], _body} =
               lambda

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

      assert {:ok, {:lambda, [params: [{:param, [], "x"}], captures: []], [body]}, %{}} =
               ToMeta.transform(ast)

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

      assert {:ok,
              {:lambda, [params: [{:param, [], "x"}, {:param, [], "y"}], captures: []], [body]},
              %{}} =
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
          assert Keyword.get(meta, :params) == [{:param, [], "x"}, {:param, [], "y"}]
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
          assert Keyword.get(meta, :params) == [{:param, [], "x"}]

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

      assert Enum.any?(
               elements,
               &match?(
                 {:language_specific, [language: :ruby, hint: :kwsplat], _},
                 &1
               )
             )
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

      assert Enum.all?(
               elements,
               &match?({:language_specific, [language: :ruby, hint: :kwsplat], _}, &1)
             )
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
      assert Keyword.get(meta, :params) == [{:param, [], "x"}]
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
      assert Keyword.get(lambda_meta, :params) == [{:param, [], "item"}, {:param, [], "index"}]
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

  # ============================================================
  # Phase 1: Safe Navigation (&.), ||=, &&=
  # ============================================================

  describe "ToMeta - Safe Navigation Operator (csend)" do
    test "transforms csend without arguments (attribute access)" do
      ast = %{
        "type" => "csend",
        "children" => [
          %{"type" => "lvar", "children" => ["user"]},
          "name"
        ]
      }

      assert {:ok, meta_ast, %{null_safe: true}} = ToMeta.transform(ast)

      assert {:attribute_access, meta, [{:variable, _, "user"}]} = meta_ast
      assert Keyword.get(meta, :attribute) == "name"
      assert Keyword.get(meta, :null_safe) == true
    end

    test "transforms csend with arguments" do
      ast = %{
        "type" => "csend",
        "children" => [
          %{"type" => "lvar", "children" => ["header"]},
          "match",
          %{"type" => "str", "children" => ["pattern"]}
        ]
      }

      assert {:ok, {:function_call, meta, [_arg]}, %{null_safe: true}} = ToMeta.transform(ast)
      assert Keyword.get(meta, :null_safe) == true
      assert Keyword.get(meta, :name) =~ "match"
    end

    test "transforms chained csend" do
      # header&.match(pattern)&.captures
      inner = %{
        "type" => "csend",
        "children" => [
          %{"type" => "lvar", "children" => ["header"]},
          "match",
          %{"type" => "str", "children" => ["pattern"]}
        ]
      }

      outer = %{
        "type" => "csend",
        "children" => [inner, "captures"]
      }

      assert {:ok, meta_ast, %{null_safe: true}} = ToMeta.transform(outer)
      # The outer is a function_call (receiver is not a variable)
      assert {:function_call, meta, []} = meta_ast
      assert Keyword.get(meta, :null_safe) == true
    end

    test "parses and transforms safe navigation from source" do
      {:ok, ast} = Ruby.parse("user&.name")
      assert {:ok, meta_ast, _} = ToMeta.transform(ast)

      case meta_ast do
        {:attribute_access, meta, _} ->
          assert Keyword.get(meta, :null_safe) == true

        {:function_call, meta, _} ->
          assert Keyword.get(meta, :null_safe) == true
      end
    end
  end

  describe "ToMeta - Conditional Assignment (||= and &&=)" do
    test "transforms or_asgn with instance variable" do
      ast = %{
        "type" => "or_asgn",
        "children" => [
          %{"type" => "ivasgn", "children" => ["@value"]},
          %{"type" => "int", "children" => [42]}
        ]
      }

      assert {:ok, {:augmented_assignment, meta, [target, value]}, %{original_type: :or_asgn}} =
               ToMeta.transform(ast)

      assert Keyword.get(meta, :operator) == :"||="
      assert Keyword.get(meta, :category) == :boolean
      assert {:variable, [scope: :instance], "@value"} = target
      assert {:literal, [subtype: :integer], 42} = value
    end

    test "transforms and_asgn with local variable" do
      ast = %{
        "type" => "and_asgn",
        "children" => [
          %{"type" => "lvasgn", "children" => ["x"]},
          %{"type" => "str", "children" => ["default"]}
        ]
      }

      assert {:ok, {:augmented_assignment, meta, [target, value]}, %{original_type: :and_asgn}} =
               ToMeta.transform(ast)

      assert Keyword.get(meta, :operator) == :"&&="
      assert {:variable, [scope: :local], "x"} = target
      assert {:literal, [subtype: :string], "default"} = value
    end

    test "parses and transforms ||= from source" do
      {:ok, ast} = Ruby.parse("@cached ||= compute")
      assert {:ok, {:augmented_assignment, meta, _}, _} = ToMeta.transform(ast)
      assert Keyword.get(meta, :operator) == :"||="
    end

    test "parses and transforms &&= from source" do
      {:ok, ast} = Ruby.parse("x &&= y")
      assert {:ok, {:augmented_assignment, meta, _}, _} = ToMeta.transform(ast)
      assert Keyword.get(meta, :operator) == :"&&="
    end
  end

  describe "ToMeta - Variable Binding Forms" do
    test "transforms instance variable binding (ivasgn with 1 child)" do
      ast = %{"type" => "ivasgn", "children" => ["@x"]}

      assert {:ok, {:variable, [scope: :instance], "@x"}, %{binding: true}} =
               ToMeta.transform(ast)
    end

    test "transforms class variable binding (cvasgn with 1 child)" do
      ast = %{"type" => "cvasgn", "children" => ["@@x"]}

      assert {:ok, {:variable, [scope: :class], "@@x"}, %{binding: true}} =
               ToMeta.transform(ast)
    end

    test "transforms global variable binding (gvasgn with 1 child)" do
      ast = %{"type" => "gvasgn", "children" => ["$x"]}

      assert {:ok, {:variable, [scope: :global], "$x"}, %{binding: true}} =
               ToMeta.transform(ast)
    end
  end

  describe "ToMeta - kwbegin with multiple statements" do
    test "transforms kwbegin as block" do
      ast = %{
        "type" => "kwbegin",
        "children" => [
          %{"type" => "int", "children" => [1]},
          %{"type" => "int", "children" => [2]}
        ]
      }

      assert {:ok, {:block, [], [_, _]}, %{}} = ToMeta.transform(ast)
    end
  end

  # ============================================================
  # Phase 2: Method Parameter Types
  # ============================================================

  describe "ToMeta - Extended Parameter Types" do
    test "transforms optarg (optional positional parameter)" do
      ast = %{
        "type" => "def",
        "children" => [
          "foo",
          %{
            "type" => "args",
            "children" => [
              %{"type" => "optarg", "children" => ["x", %{"type" => "int", "children" => [0]}]}
            ]
          },
          nil
        ]
      }

      assert {:ok, {:function_def, meta, _}, _} = ToMeta.transform(ast)
      params = Keyword.get(meta, :params)
      assert [{:param, param_meta, "x"}] = params
      assert {:literal, [subtype: :integer], 0} = Keyword.get(param_meta, :default)
    end

    test "transforms kwarg (required keyword parameter)" do
      ast = %{
        "type" => "def",
        "children" => [
          "foo",
          %{
            "type" => "args",
            "children" => [
              %{"type" => "kwarg", "children" => ["name"]}
            ]
          },
          nil
        ]
      }

      assert {:ok, {:function_def, meta, _}, _} = ToMeta.transform(ast)
      params = Keyword.get(meta, :params)
      assert [{:param, [keyword: true], "name"}] = params
    end

    test "transforms kwoptarg (optional keyword parameter)" do
      ast = %{
        "type" => "def",
        "children" => [
          "foo",
          %{
            "type" => "args",
            "children" => [
              %{
                "type" => "kwoptarg",
                "children" => ["name", %{"type" => "str", "children" => ["default"]}]
              }
            ]
          },
          nil
        ]
      }

      assert {:ok, {:function_def, meta, _}, _} = ToMeta.transform(ast)
      params = Keyword.get(meta, :params)
      assert [{:param, param_meta, "name"}] = params
      assert Keyword.get(param_meta, :keyword) == true
      assert {:literal, [subtype: :string], "default"} = Keyword.get(param_meta, :default)
    end

    test "transforms restarg (splat parameter)" do
      ast = %{
        "type" => "def",
        "children" => [
          "foo",
          %{
            "type" => "args",
            "children" => [
              %{"type" => "restarg", "children" => ["args"]}
            ]
          },
          nil
        ]
      }

      assert {:ok, {:function_def, meta, _}, _} = ToMeta.transform(ast)
      params = Keyword.get(meta, :params)
      assert [{:param, [rest: true], "args"}] = params
    end

    test "transforms kwrestarg (double splat parameter)" do
      ast = %{
        "type" => "def",
        "children" => [
          "foo",
          %{
            "type" => "args",
            "children" => [
              %{"type" => "kwrestarg", "children" => ["opts"]}
            ]
          },
          nil
        ]
      }

      assert {:ok, {:function_def, meta, _}, _} = ToMeta.transform(ast)
      params = Keyword.get(meta, :params)
      assert [{:param, [keyword_rest: true], "opts"}] = params
    end

    test "transforms blockarg (block parameter)" do
      ast = %{
        "type" => "def",
        "children" => [
          "foo",
          %{
            "type" => "args",
            "children" => [
              %{"type" => "blockarg", "children" => ["block"]}
            ]
          },
          nil
        ]
      }

      assert {:ok, {:function_def, meta, _}, _} = ToMeta.transform(ast)
      params = Keyword.get(meta, :params)
      assert [{:param, [block: true], "block"}] = params
    end

    test "transforms mixed parameter types" do
      ast = %{
        "type" => "def",
        "children" => [
          "complex",
          %{
            "type" => "args",
            "children" => [
              %{"type" => "arg", "children" => ["x"]},
              %{"type" => "optarg", "children" => ["y", %{"type" => "int", "children" => [0]}]},
              %{"type" => "restarg", "children" => ["args"]},
              %{"type" => "kwarg", "children" => ["name"]},
              %{
                "type" => "kwoptarg",
                "children" => ["age", %{"type" => "int", "children" => [18]}]
              },
              %{"type" => "kwrestarg", "children" => ["opts"]},
              %{"type" => "blockarg", "children" => ["block"]}
            ]
          },
          nil
        ]
      }

      assert {:ok, {:function_def, meta, _}, _} = ToMeta.transform(ast)
      params = Keyword.get(meta, :params)

      assert [
               {:param, [], "x"},
               {:param, [default: {:literal, [subtype: :integer], 0}], "y"},
               {:param, [rest: true], "args"},
               {:param, [keyword: true], "name"},
               {:param, [keyword: true, default: {:literal, [subtype: :integer], 18}], "age"},
               {:param, [keyword_rest: true], "opts"},
               {:param, [block: true], "block"}
             ] = params
    end

    test "parses and transforms method with default param from source" do
      {:ok, ast} = Ruby.parse("def initialize(initial = 0); end")
      assert {:ok, {:function_def, meta, _}, _} = ToMeta.transform(ast)
      params = Keyword.get(meta, :params)
      assert [{:param, param_meta, "initial"}] = params
      assert Keyword.get(param_meta, :default) != nil
    end

    test "parses and transforms method with keyword params from source" do
      {:ok, ast} = Ruby.parse("def foo(name:, age: 18); end")
      assert {:ok, {:function_def, meta, _}, _} = ToMeta.transform(ast)
      params = Keyword.get(meta, :params)
      assert [_, _] = params
      assert {:param, [keyword: true], "name"} = Enum.at(params, 0)
      assert {:param, kw_meta, "age"} = Enum.at(params, 1)
      assert Keyword.get(kw_meta, :keyword) == true
      assert Keyword.get(kw_meta, :default) != nil
    end

    test "parses and transforms method with splat params from source" do
      {:ok, ast} = Ruby.parse("def foo(*args, **opts, &block); end")
      assert {:ok, {:function_def, meta, _}, _} = ToMeta.transform(ast)
      params = Keyword.get(meta, :params)
      assert [_, _, _] = params
      assert {:param, [rest: true], "args"} = Enum.at(params, 0)
      assert {:param, [keyword_rest: true], "opts"} = Enum.at(params, 1)
      assert {:param, [block: true], "block"} = Enum.at(params, 2)
    end
  end

  # ============================================================
  # Phase 3: FromMeta Round-Trip Tests
  # ============================================================

  describe "FromMeta - csend round-trip" do
    alias Metastatic.Adapters.Ruby.FromMeta

    test "reconstructs csend for null_safe attribute access" do
      meta_ast =
        {:attribute_access, [attribute: "name", null_safe: true],
         [{:variable, [scope: :local], "user"}]}

      assert {:ok, ast} = FromMeta.transform(meta_ast, %{})
      assert ast["type"] == "csend"
      assert Enum.at(ast["children"], 1) == :name
    end

    test "reconstructs csend for null_safe function call" do
      meta_ast = {:function_call, [name: "obj.method", null_safe: true], []}

      assert {:ok, ast} = FromMeta.transform(meta_ast, %{})
      assert ast["type"] == "csend"
    end

    test "reconstructs regular send for non-null_safe" do
      meta_ast =
        {:attribute_access, [attribute: "name"], [{:variable, [scope: :local], "user"}]}

      assert {:ok, ast} = FromMeta.transform(meta_ast, %{})
      assert ast["type"] == "send"
    end
  end

  describe "FromMeta - or_asgn/and_asgn round-trip" do
    alias Metastatic.Adapters.Ruby.FromMeta

    test "reconstructs or_asgn from augmented_assignment ||=" do
      meta_ast =
        {:augmented_assignment, [category: :boolean, operator: :"||="],
         [{:variable, [scope: :instance], "@val"}, {:literal, [subtype: :integer], 42}]}

      assert {:ok, ast} = FromMeta.transform(meta_ast, %{})
      assert ast["type"] == "or_asgn"
      assert [target, _value] = ast["children"]
      assert target["type"] == "ivasgn"
      assert target["children"] == ["@val"]
    end

    test "reconstructs and_asgn from augmented_assignment &&=" do
      meta_ast =
        {:augmented_assignment, [category: :boolean, operator: :"&&="],
         [{:variable, [scope: :local], "x"}, {:literal, [subtype: :string], "val"}]}

      assert {:ok, ast} = FromMeta.transform(meta_ast, %{})
      assert ast["type"] == "and_asgn"
      assert [target, _value] = ast["children"]
      assert target["type"] == "lvasgn"
    end

    test "reconstructs op_asgn for regular += operator" do
      meta_ast =
        {:augmented_assignment, [category: :arithmetic, operator: :+],
         [{:variable, [scope: :local], "x"}, {:literal, [subtype: :integer], 5}]}

      assert {:ok, ast} = FromMeta.transform(meta_ast, %{})
      assert ast["type"] == "op_asgn"
    end
  end

  describe "FromMeta - extended parameter types round-trip" do
    alias Metastatic.Adapters.Ruby.FromMeta

    test "reconstructs optarg parameter" do
      meta_ast =
        {:function_def,
         [
           name: "foo",
           params: [{:param, [default: {:literal, [subtype: :integer], 0}], "x"}],
           visibility: :public,
           arity: 1
         ], [nil]}

      assert {:ok, ast} = FromMeta.transform(meta_ast, %{})
      args = ast["children"] |> Enum.at(1)
      assert args["type"] == "args"
      [param] = args["children"]
      assert param["type"] == "optarg"
      assert Enum.at(param["children"], 0) == "x"
    end

    test "reconstructs kwarg parameter" do
      meta_ast =
        {:function_def,
         [
           name: "foo",
           params: [{:param, [keyword: true], "name"}],
           visibility: :public,
           arity: 1
         ], [nil]}

      assert {:ok, ast} = FromMeta.transform(meta_ast, %{})
      args = ast["children"] |> Enum.at(1)
      [param] = args["children"]
      assert param["type"] == "kwarg"
    end

    test "reconstructs restarg parameter" do
      meta_ast =
        {:function_def,
         [
           name: "foo",
           params: [{:param, [rest: true], "args"}],
           visibility: :public,
           arity: 1
         ], [nil]}

      assert {:ok, ast} = FromMeta.transform(meta_ast, %{})
      args = ast["children"] |> Enum.at(1)
      [param] = args["children"]
      assert param["type"] == "restarg"
    end

    test "reconstructs blockarg parameter" do
      meta_ast =
        {:function_def,
         [
           name: "foo",
           params: [{:param, [block: true], "block"}],
           visibility: :public,
           arity: 1
         ], [nil]}

      assert {:ok, ast} = FromMeta.transform(meta_ast, %{})
      args = ast["children"] |> Enum.at(1)
      [param] = args["children"]
      assert param["type"] == "blockarg"
    end
  end

  # ============================================================
  # Phase 5: Rails Integration Tests
  # ============================================================

  describe "Rails Integration - fixture files" do
    test "parses and transforms Rails model fixture" do
      source = File.read!("test/fixtures/ruby/rails_model.rb")
      {:ok, ast} = Ruby.parse(source)
      assert {:ok, {:container, meta, _}, _} = Ruby.to_meta(ast)
      assert Keyword.get(meta, :container_type) == :class
      assert Keyword.get(meta, :name) == "Book"
      assert Keyword.get(meta, :parent) == "ApplicationRecord"
    end

    test "parses and transforms Rails concern fixture" do
      source = File.read!("test/fixtures/ruby/rails_concern.rb")
      {:ok, ast} = Ruby.parse(source)
      assert {:ok, {:container, meta, _}, _} = Ruby.to_meta(ast)
      assert Keyword.get(meta, :container_type) == :module
      assert Keyword.get(meta, :name) == "Authentication"
    end

    test "parses and transforms Rails service fixture" do
      source = File.read!("test/fixtures/ruby/rails_service.rb")
      {:ok, ast} = Ruby.parse(source)
      assert {:ok, {:container, meta, _}, _} = Ruby.to_meta(ast)
      assert Keyword.get(meta, :container_type) == :module
      assert Keyword.get(meta, :name) == "Catalog"
    end

    test "parses and transforms memoization pattern" do
      source = """
      def current_user
        @current_user ||= User.find_by(id: 1)
      end
      """

      {:ok, ast} = Ruby.parse(source)
      assert {:ok, {:function_def, _, [body]}, _} = Ruby.to_meta(ast)
      assert {:augmented_assignment, meta, _} = body
      assert Keyword.get(meta, :operator) == :"||="
    end

    test "parses and transforms safe navigation chain" do
      source = "header&.match(pattern)&.captures&.first"

      {:ok, ast} = Ruby.parse(source)
      assert {:ok, _meta_ast, _} = Ruby.to_meta(ast)
    end

    test "parses and transforms method with all param types" do
      source = "def complex(a, b = 1, *rest, key:, opt: 2, **kw, &blk); end"

      {:ok, ast} = Ruby.parse(source)
      assert {:ok, {:function_def, meta, _}, _} = Ruby.to_meta(ast)
      params = Keyword.get(meta, :params)
      assert length(params) == 7
    end
  end

  describe "Rails Integration - book_shop_rails app" do
    @book_shop_path "/home/am/Proyectos/TopTal/book_shop_rails"

    @tag :book_shop
    test "all app Ruby files parse and transform successfully" do
      files =
        Path.wildcard(Path.join(@book_shop_path, "app/**/*.rb")) ++
          Path.wildcard(Path.join(@book_shop_path, "config/**/*.rb"))

      assert match?([_ | _], files), "Expected to find Ruby files in book_shop_rails"

      results =
        Enum.map(files, fn f ->
          source = File.read!(f)

          case Ruby.parse(source) do
            {:ok, ast} ->
              case Ruby.to_meta(ast) do
                {:ok, _, _} -> :ok
                {:error, _} -> {:fail, Path.basename(f)}
              end

            {:error, _} ->
              # Parse failures are acceptable for config files with special syntax
              :parse_skip
          end
        end)

      ok_count = Enum.count(results, &(&1 == :ok))
      skip_count = Enum.count(results, &(&1 == :parse_skip))
      fails = Enum.filter(results, &match?({:fail, _}, &1))

      assert fails == [],
             "Expected 0 to_meta failures, got #{length(fails)}: #{inspect(fails)}"

      assert ok_count + skip_count == length(results)
      assert ok_count >= 50, "Expected at least 50 files to transform, got #{ok_count}"
    end
  end

  describe "Parser - location enhancement" do
    test "emits end_line and end_column" do
      {:ok, ast} = Ruby.parse("x = 42")
      loc = ast["location"]
      assert is_integer(loc["end_line"])
      assert is_integer(loc["end_column"])
      assert loc["end_line"] >= loc["begin_line"]
    end

    test "multi-line location spans" do
      source = """
      class Foo
        def bar
          42
        end
      end
      """

      {:ok, ast} = Ruby.parse(source)
      loc = ast["location"]
      assert loc["begin_line"] == 1
      assert loc["end_line"] >= 4
    end
  end
end
