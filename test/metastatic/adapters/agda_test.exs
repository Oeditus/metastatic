defmodule Metastatic.Adapters.AgdaTest do
  use ExUnit.Case, async: true

  @moduletag :agda

  alias Metastatic.Adapters.Agda
  alias Metastatic.Adapters.Agda.{FromMeta, ToMeta, Unparser}
  alias Metastatic.Languages

  describe "parse/1 via subprocess bridge" do
    test "parses integer literal" do
      assert {:ok, ast} = Agda.parse("42")
      assert is_map(ast)
      assert ast["type"] == "literal"
      assert ast["value"]["value"] == 42
    end

    test "parses binary infix operation" do
      assert {:ok, ast} = Agda.parse("1 + 2")
      assert is_map(ast)
      assert ast["type"] == "infix"
      assert ast["operator"] == "+"
      assert ast["left"]["type"] == "literal"
      assert ast["right"]["type"] == "literal"
    end

    test "parses lambda expression" do
      assert {:ok, ast} = Agda.parse("\\ x -> x")
      assert is_map(ast)
      assert ast["type"] == "lambda"
      assert [%{"name" => "x"}] = ast["parameters"]
      assert ast["body"]["type"] == "var"
      assert ast["body"]["name"] == "x"
    end

    test "parses function type signature" do
      assert {:ok, ast} = Agda.parse("f : Nat -> Nat")
      assert is_map(ast)
      assert ast["type"] == "module"
      assert [decl] = ast["declarations"]
      # Wrapped in synthetic module or direct decl
      actual_decl = if decl["type"] == "module", do: hd(decl["declarations"]), else: decl
      assert actual_decl["type"] == "type_sig"
      assert actual_decl["name"] == "f"
    end

    test "parses full Agda module" do
      source = """
      module BoolLogic where

      data Bool : Set where
        true  : Bool
        false : Bool
      """

      assert {:ok, ast} = Agda.parse(source)
      assert is_map(ast)
      assert ast["type"] == "module"
      assert [mod] = ast["declarations"]
      assert mod["type"] == "module"
      assert mod["name"] == "BoolLogic"
      assert [data_decl] = mod["declarations"]
      assert data_decl["type"] == "data"
      assert data_decl["name"] == "Bool"
    end
  end

  describe "ToMeta - Literals & Expressions (M2.1 Core)" do
    test "transforms integer literal" do
      ast = %{
        "type" => "literal",
        "value" => %{"literalType" => "int", "value" => 100}
      }

      assert {:ok, {:literal, meta, 100}, %{subtype: :integer}} = ToMeta.transform(ast)
      assert Keyword.get(meta, :subtype) == :integer
    end

    test "transforms float literal" do
      ast = %{
        "type" => "literal",
        "value" => %{"literalType" => "float", "value" => 3.14}
      }

      assert {:ok, {:literal, meta, 3.14}, %{subtype: :float}} = ToMeta.transform(ast)
      assert Keyword.get(meta, :subtype) == :float
    end

    test "transforms string literal" do
      ast = %{
        "type" => "literal",
        "value" => %{"literalType" => "string", "value" => "hello"}
      }

      assert {:ok, {:literal, meta, "hello"}, %{subtype: :string}} = ToMeta.transform(ast)
      assert Keyword.get(meta, :subtype) == :string
    end

    test "transforms local variable" do
      ast = %{"type" => "var", "name" => "myVar"}

      assert {:ok, {:variable, meta, "myVar"}, %{}} = ToMeta.transform(ast)
      assert Keyword.get(meta, :scope) == :local
    end

    test "transforms constructor variable (capitalized)" do
      ast = %{"type" => "var", "name" => "True"}

      assert {:ok, {:variable, meta, "True"}, %{}} = ToMeta.transform(ast)
      assert Keyword.get(meta, :scope) == :constructor
    end

    test "transforms arithmetic infix operation" do
      ast = %{
        "type" => "infix",
        "operator" => "+",
        "left" => %{"type" => "literal", "value" => %{"literalType" => "int", "value" => 1}},
        "right" => %{"type" => "literal", "value" => %{"literalType" => "int", "value" => 2}}
      }

      assert {:ok, {:binary_op, meta, [left, right]}, %{operator: "+"}} = ToMeta.transform(ast)
      assert Keyword.get(meta, :category) == :arithmetic
      assert Keyword.get(meta, :operator) == :+
      assert {:literal, _, 1} = left
      assert {:literal, _, 2} = right
    end

    test "transforms comparison and unicode operators" do
      ast = %{
        "type" => "infix",
        "operator" => "≤",
        "left" => %{"type" => "var", "name" => "x"},
        "right" => %{"type" => "var", "name" => "y"}
      }

      assert {:ok, {:binary_op, meta, _}, _} = ToMeta.transform(ast)
      assert Keyword.get(meta, :category) == :comparison
      assert Keyword.get(meta, :operator) == :"≤"
    end

    test "transforms lambda" do
      ast = %{
        "type" => "lambda",
        "parameters" => [%{"name" => "x"}, %{"name" => "y"}],
        "body" => %{"type" => "var", "name" => "x"}
      }

      assert {:ok, {:lambda, meta, [body]}, %{}} = ToMeta.transform(ast)
      assert Keyword.get(meta, :params) == ["x", "y"]
      assert {:variable, _, "x"} = body
    end

    test "transforms arrow function types" do
      ast = %{
        "type" => "arrow",
        "from" => %{"type" => "var", "name" => "A"},
        "to" => %{"type" => "var", "name" => "B"}
      }

      assert {:ok, {:type_annotation, meta, [from, to]}, %{}} = ToMeta.transform(ast)
      assert Keyword.get(meta, :kind) == :arrow
      assert {:variable, _, "A"} = from
      assert {:variable, _, "B"} = to
    end
  end

  describe "ToMeta - Declarations & Structure (M2.2 & M2.3)" do
    test "transforms type signature" do
      ast = %{
        "type" => "type_sig",
        "name" => "not",
        "signature" => %{
          "type" => "arrow",
          "from" => %{"type" => "var", "name" => "Bool"},
          "to" => %{"type" => "var", "name" => "Bool"}
        }
      }

      assert {:ok, {:type_def, meta, [sig]}, %{}} = ToMeta.transform(ast)
      assert Keyword.get(meta, :name) == "not"
      assert Keyword.get(meta, :kind) == :signature
      assert {:type_annotation, _, _} = sig
    end

    test "transforms function clause" do
      ast = %{
        "type" => "fun_clause",
        "lhs" => %{
          "type" => "app_pat",
          "elements" => [
            %{"type" => "var_pat", "name" => "not"},
            %{"type" => "var_pat", "name" => "true"}
          ]
        },
        "rhs" => %{
          "type" => "rhs",
          "expression" => %{"type" => "var", "name" => "false"}
        }
      }

      assert {:ok, {:function_def, meta, [rhs]}, %{}} = ToMeta.transform(ast)
      assert Keyword.get(meta, :name) == "not"
      assert Keyword.get(meta, :params) == ["true"]
      assert {:variable, _, "false"} = rhs
    end

    test "transforms data definition" do
      ast = %{
        "type" => "data",
        "name" => "Nat",
        "params" => [],
        "typeExpr" => %{"type" => "var", "name" => "Set"},
        "constructors" => [
          %{
            "type" => "type_sig",
            "name" => "zero",
            "signature" => %{"type" => "var", "name" => "Nat"}
          },
          %{
            "type" => "type_sig",
            "name" => "suc",
            "signature" => %{
              "type" => "arrow",
              "from" => %{"type" => "var", "name" => "Nat"},
              "to" => %{"type" => "var", "name" => "Nat"}
            }
          }
        ]
      }

      assert {:ok, {:type_def, meta, [type_expr | ctors]}, %{}} = ToMeta.transform(ast)
      assert Keyword.get(meta, :name) == "Nat"
      assert Keyword.get(meta, :kind) == :data
      assert {:variable, _, "Set"} = type_expr
      assert length(ctors) == 2
    end

    test "transforms module container" do
      ast = %{
        "type" => "module",
        "name" => "Logic",
        "declarations" => [
          %{
            "type" => "type_sig",
            "name" => "P",
            "signature" => %{"type" => "var", "name" => "Set"}
          }
        ]
      }

      assert {:ok, {:container, meta, decls}, %{}} = ToMeta.transform(ast)
      assert Keyword.get(meta, :container_type) == :module
      assert Keyword.get(meta, :name) == "Logic"
      assert Keyword.get(meta, :language) == :agda
      assert [d] = decls
      assert {:type_def, _, _} = d
    end

    test "transforms import directives" do
      ast = %{"type" => "import", "module" => "Data.Nat", "open" => true}
      assert {:ok, {:import, meta, []}, %{}} = ToMeta.transform(ast)
      assert Keyword.get(meta, :module) == "Data.Nat"
      assert Keyword.get(meta, :open) == true
    end

    test "transforms postulates" do
      ast = %{
        "type" => "postulate",
        "declarations" => [
          %{
            "type" => "type_sig",
            "name" => "axiom",
            "signature" => %{"type" => "var", "name" => "A"}
          }
        ]
      }

      assert {:ok, {:language_specific, meta, decls}, %{}} = ToMeta.transform(ast)
      assert Keyword.get(meta, :construct) == :postulate
      assert Keyword.get(meta, :language) == :agda
      assert length(decls) == 1
    end
  end

  describe "FromMeta (M2 -> M1 Reification)" do
    test "reifies integer literal" do
      meta = {:literal, [subtype: :integer], 42}
      assert {:ok, ast} = FromMeta.transform(meta)
      assert ast["type"] == "literal"
      assert ast["value"]["value"] == 42
    end

    test "reifies binary operation" do
      meta =
        {:binary_op, [operator: :+],
         [{:literal, [subtype: :integer], 1}, {:literal, [subtype: :integer], 2}]}

      assert {:ok, ast} = FromMeta.transform(meta)
      assert ast["type"] == "infix"
      assert ast["operator"] == "+"
    end

    test "reifies lambda" do
      meta = {:lambda, [params: ["x"]], [{:variable, [], "x"}]}
      assert {:ok, ast} = FromMeta.transform(meta)
      assert ast["type"] == "lambda"
      assert [%{"name" => "x"}] = ast["parameters"]
    end

    test "reifies type signature" do
      meta =
        {:type_def, [name: "id", kind: :signature],
         [{:type_annotation, [kind: :arrow], [{:variable, [], "A"}, {:variable, [], "A"}]}]}

      assert {:ok, ast} = FromMeta.transform(meta)
      assert ast["type"] == "type_sig"
      assert ast["name"] == "id"
    end
  end

  describe "Unparser & Round-Trip" do
    test "unparses arithmetic expression" do
      ast = %{
        "type" => "infix",
        "operator" => "+",
        "left" => %{"type" => "literal", "value" => %{"literalType" => "int", "value" => 1}},
        "right" => %{"type" => "literal", "value" => %{"literalType" => "int", "value" => 2}}
      }

      assert {:ok, code} = Unparser.unparse(ast)
      assert code == "1 + 2"
    end

    test "unparses lambda" do
      ast = %{
        "type" => "lambda",
        "parameters" => [%{"name" => "x"}],
        "body" => %{"type" => "var", "name" => "x"}
      }

      assert {:ok, code} = Unparser.unparse(ast)
      assert code == "\\ x -> x"
    end

    test "unparses data definition" do
      ast = %{
        "type" => "data",
        "name" => "Bool",
        "typeExpr" => %{"type" => "var", "name" => "Set"},
        "constructors" => [
          %{
            "type" => "type_sig",
            "name" => "true",
            "signature" => %{"type" => "var", "name" => "Bool"}
          },
          %{
            "type" => "type_sig",
            "name" => "false",
            "signature" => %{"type" => "var", "name" => "Bool"}
          }
        ]
      }

      assert {:ok, code} = Unparser.unparse(ast)
      assert String.contains?(code, "data Bool : Set where")
      assert String.contains?(code, "true : Bool")
      assert String.contains?(code, "false : Bool")
    end

    test "performs full round-trip via Metastatic.Adapter" do
      assert {:ok, round_tripped} = Metastatic.Adapter.round_trip(Agda, "1 + 2")
      assert String.trim(round_tripped) == "1 + 2"
    end
  end

  describe "Languages integration" do
    test "detects .agda and .lagda extensions" do
      assert {:ok, :agda} = Languages.detect_language("Math.agda")
      assert {:ok, :agda} = Languages.detect_language("Paper.lagda")
      assert ".agda" in Languages.supported_extensions()
      assert ".lagda" in Languages.supported_extensions()
    end

    test "registers Agda as supported language" do
      assert Languages.supported?(:agda)
      assert :agda in Languages.supported_languages()
      assert {:ok, Agda} = Languages.get_adapter(:agda)
    end
  end
end
