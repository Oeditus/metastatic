defmodule Metastatic.Adapters.JavaScriptTest do
  use ExUnit.Case, async: true

  @moduletag :javascript

  alias Metastatic.Adapters.JavaScript
  alias Metastatic.Adapters.JavaScript.ToMeta

  describe "parse/1" do
    test "parses valid JavaScript source code" do
      assert {:ok, ast} = JavaScript.parse("const x = 42;")
      assert is_map(ast)
      assert ast["type"] in ["File", "Program"]
    end

    test "returns error for syntax error" do
      assert {:error, reason} = JavaScript.parse("const x =")
      assert reason =~ "SyntaxError"
    end
  end

  describe "ToMeta - core transformations" do
    test "transforms integer literal" do
      ast_node = %{"type" => "NumericLiteral", "value" => 42}
      assert {:ok, {:literal, meta, 42}, %{}} = ToMeta.transform(ast_node)
      assert meta[:subtype] == :integer
    end

    test "transforms string literal" do
      ast_node = %{"type" => "StringLiteral", "value" => "hello"}
      assert {:ok, {:literal, meta, "hello"}, %{}} = ToMeta.transform(ast_node)
      assert meta[:subtype] == :string
    end

    test "transforms variable" do
      ast_node = %{"type" => "Identifier", "name" => "count"}
      assert {:ok, {:variable, meta, "count"}, %{}} = ToMeta.transform(ast_node)
      assert meta[:scope] == :local
    end

    test "transforms binary operation" do
      ast_node = %{
        "type" => "BinaryExpression",
        "operator" => "+",
        "left" => %{"type" => "Identifier", "name" => "x"},
        "right" => %{"type" => "NumericLiteral", "value" => 5}
      }

      assert {:ok, {:binary_op, meta, [left, right]}, %{}} = ToMeta.transform(ast_node)
      assert meta[:category] == :arithmetic
      assert meta[:operator] == :+
      assert left == {:variable, [scope: :local], "x"}
      assert right == {:literal, [subtype: :integer], 5}
    end

    test "transforms function call" do
      ast_node = %{
        "type" => "CallExpression",
        "callee" => %{"type" => "Identifier", "name" => "greet"},
        "arguments" => [%{"type" => "StringLiteral", "value" => "Alice"}]
      }

      assert {:ok, {:function_call, meta, [callee, arg]}, %{}} = ToMeta.transform(ast_node)
      assert meta[:name] == "greet"
      assert callee == {:variable, [scope: :local], "greet"}
      assert arg == {:literal, [subtype: :string], "Alice"}
    end

    test "transforms function declaration" do
      ast_node = %{
        "type" => "FunctionDeclaration",
        "id" => %{"type" => "Identifier", "name" => "add"},
        "params" => [
          %{"type" => "Identifier", "name" => "a"},
          %{"type" => "Identifier", "name" => "b"}
        ],
        "body" => %{
          "type" => "BlockStatement",
          "body" => [
            %{
              "type" => "ReturnStatement",
              "argument" => %{
                "type" => "BinaryExpression",
                "operator" => "+",
                "left" => %{"type" => "Identifier", "name" => "a"},
                "right" => %{"type" => "Identifier", "name" => "b"}
              }
            }
          ]
        }
      }

      assert {:ok, {:function_def, meta, [params, body]}, %{}} = ToMeta.transform(ast_node)
      assert meta[:name] == "add"
      assert length(params) == 2

      assert body ==
               {:block, [],
                [
                  {:return, [],
                   [
                     {:binary_op, [category: :arithmetic, operator: :+],
                      [{:variable, [scope: :local], "a"}, {:variable, [scope: :local], "b"}]}
                   ]}
                ]}
    end

    test "transforms conditional if statement" do
      ast_node = %{
        "type" => "IfStatement",
        "test" => %{"type" => "BooleanLiteral", "value" => true},
        "consequent" => %{"type" => "BlockStatement", "body" => []},
        "alternate" => nil
      }

      assert {:ok, {:conditional, _meta, [test, cons]}, %{}} = ToMeta.transform(ast_node)
      assert test == {:literal, [subtype: :boolean], true}
      assert cons == {:block, [], []}
    end
  end

  describe "Full Round-Trip Pipeline" do
    test "round-trips literals fixture" do
      source = File.read!("test/fixtures/javascript/core/literals.js")
      assert {:ok, ast1} = JavaScript.parse(source)
      assert {:ok, meta_ast, metadata} = JavaScript.to_meta(ast1)
      assert {:ok, ast2} = JavaScript.from_meta(meta_ast, metadata)
      assert {:ok, generated_source} = JavaScript.unparse(ast2)

      assert generated_source =~ "const a = 42;"
      assert generated_source =~ "const c = \"hello world\";"
    end

    test "round-trips functions fixture" do
      source = File.read!("test/fixtures/javascript/core/functions.js")
      assert {:ok, ast1} = JavaScript.parse(source)
      assert {:ok, meta_ast, metadata} = JavaScript.to_meta(ast1)
      assert {:ok, ast2} = JavaScript.from_meta(meta_ast, metadata)
      assert {:ok, generated_source} = JavaScript.unparse(ast2)

      assert generated_source =~ "function add"
      assert generated_source =~ "a + b"
    end

    test "round-trips classes fixture" do
      source = File.read!("test/fixtures/javascript/extended/classes.js")
      assert {:ok, ast1} = JavaScript.parse(source)
      assert {:ok, meta_ast, metadata} = JavaScript.to_meta(ast1)
      assert {:ok, ast2} = JavaScript.from_meta(meta_ast, metadata)
      assert {:ok, generated_source} = JavaScript.unparse(ast2)

      assert generated_source =~ "class Calculator"
      assert generated_source =~ "constructor"
    end
  end
end
