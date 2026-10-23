defmodule Metastatic.CLI.FormatterTest do
  use ExUnit.Case, async: true

  alias Metastatic.{CLI.Formatter, Document}

  @binary_op {:binary_op, [category: :arithmetic, operator: :+],
              [{:variable, [], "x"}, {:literal, [subtype: :integer], 5}]}

  describe "to_map/1 (canonical intermediate)" do
    test "literal carries subtype and value" do
      m = Formatter.to_map({:literal, [subtype: :integer], 42})
      assert m.type == :literal
      assert m.children == 42
      assert m.label == "literal (integer)"
    end

    test "variable carries its name" do
      m = Formatter.to_map({:variable, [], "x"})
      assert m.type == :variable
      assert m.label == "variable: x"
    end

    test "composite nodes carry normalised child maps" do
      m = Formatter.to_map(@binary_op)
      assert m.type == :binary_op
      assert [%{type: :variable}, %{type: :literal}] = m.children
    end

    test "map pairs are normalised to :pair nodes" do
      ast =
        {:map, [],
         [{:pair, [], [{:literal, [subtype: :symbol], :a}, {:literal, [subtype: :integer], 1}]}]}

      m = Formatter.to_map(ast)
      assert [%{type: :pair, children: [%{type: :literal}, %{type: :literal}]}] = m.children
    end

    test "unknown node types fall back gracefully" do
      m = Formatter.to_map({:some_future_node, [foo: :bar], []})
      assert m.type == :some_future_node
      assert m.label == "some_future_node"
    end

    test "non-node terms are wrapped" do
      m = Formatter.to_map(:just_an_atom)
      assert m.type == :unknown
    end
  end

  describe "tree format" do
    test "renders a binary op with indented children" do
      assert Formatter.format(@binary_op, :tree) ==
               "binary_op (arithmetic: +)\n  variable: x\n  literal (integer): 5"
    end

    test "renders conditional with condition/then/else roles" do
      ast =
        {:conditional, [],
         [
           {:variable, [], "c"},
           {:block, [], [{:literal, [subtype: :integer], 1}]},
           {:block, [], [{:literal, [subtype: :integer], 2}]}
         ]}

      out = Formatter.format(ast, :tree)
      assert out =~ "conditional"
      assert out =~ "  condition:"
      assert out =~ "  then:"
      assert out =~ "  else:"
    end

    test "omits else branch when absent" do
      ast = {:conditional, [], [{:variable, [], "c"}, {:block, [], []}]}
      refute Formatter.format(ast, :tree) =~ "else:"
    end

    test "renders map key/value pairs" do
      ast =
        {:map, [],
         [{:pair, [], [{:literal, [subtype: :symbol], :a}, {:literal, [subtype: :integer], 1}]}]}

      out = Formatter.format(ast, :tree)
      assert out =~ "map"
      assert out =~ "key:"
      assert out =~ "value:"
    end
  end

  describe "plain format" do
    test "renders a binary op compactly" do
      assert Formatter.format(@binary_op, :plain) ==
               "binary_op(arithmetic, +, variable(x), literal(integer, 5))"
    end

    test "renders a function call with args" do
      ast = {:function_call, [name: "add"], [{:variable, [], "x"}, {:variable, [], "y"}]}
      assert Formatter.format(ast, :plain) == "function_call(add, [variable(x), variable(y)])"
    end

    test "unhandled node types reduce to the type name" do
      assert Formatter.format({:block, [], []}, :plain) == "block"
    end
  end

  describe "json format" do
    test "encodes a binary op with typed fields" do
      out = Formatter.format(@binary_op, :json)
      assert out =~ ~s("type": "binary_op")
      assert out =~ ~s("category": "arithmetic")
      assert out =~ ~s("operator": "+")
      assert out =~ ~s("type": "variable")
      assert out =~ ~s("name": "x")
    end

    test "encodes a conditional with then_branch" do
      ast = {:conditional, [], [{:variable, [], "c"}, {:block, [], []}, {:block, [], []}]}
      out = Formatter.format(ast, :json)
      assert out =~ ~s("type": "conditional")
      assert out =~ ~s("condition":)
      assert out =~ ~s("then_branch":)
      assert out =~ ~s("else_branch":)
    end

    test "produces valid JSON" do
      assert {:ok, _} = Jason.decode(Formatter.format(@binary_op, :json))
    end
  end

  describe "format_document/2" do
    test "prefixes language and AST header" do
      doc = Document.new(@binary_op, :python)
      out = Formatter.format_document(doc, :plain)
      assert out =~ "Language: python"
      assert out =~ "AST:"
      assert out =~ "binary_op(arithmetic"
    end
  end
end
