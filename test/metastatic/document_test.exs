defmodule Metastatic.DocumentTest do
  use ExUnit.Case, async: true

  alias Metastatic.Document

  doctest Metastatic.Document

  # Helper to build 3-tuple MetaAST nodes
  defp literal(subtype, value), do: {:literal, [subtype: subtype], value}
  defp variable(name), do: {:variable, [], name}

  defp binary_op(category, operator, left, right),
    do: {:binary_op, [category: category, operator: operator], [left, right]}

  describe "new/3" do
    test "creates valid document" do
      ast = literal(:integer, 42)
      doc = Document.new(ast, :python, %{source: "42"})

      assert doc.ast == ast
      assert doc.language == :python
      assert doc.metadata.source == "42"
    end

    test "creates document with empty metadata" do
      ast = variable("x")
      doc = Document.new(ast, :javascript)

      assert doc.ast == ast
      assert doc.language == :javascript
      assert doc.metadata == %{}
    end
  end

  describe "valid?/1" do
    test "returns true for valid document" do
      ast = literal(:integer, 42)
      doc = Document.new(ast, :python)

      assert Document.valid?(doc)
    end

    test "returns false for invalid AST" do
      doc = %Document{
        ast: {:invalid_type, [], "bad"},
        language: :python,
        metadata: %{}
      }

      refute Document.valid?(doc)
    end
  end

  describe "update_ast/2" do
    test "updates AST while preserving other fields" do
      doc = Document.new(literal(:integer, 42), :python, %{source: "42"})
      new_ast = literal(:integer, 100)

      updated = Document.update_ast(doc, new_ast)

      assert updated.ast == new_ast
      assert updated.language == :python
      assert updated.metadata == %{source: "42"}
    end
  end

  describe "update_metadata/2" do
    test "merges metadata" do
      doc = Document.new(literal(:integer, 42), :python, %{source: "42"})

      updated = Document.update_metadata(doc, %{mutated: true, lines: 1})

      assert updated.metadata.source == "42"
      assert updated.metadata.mutated == true
      assert updated.metadata.lines == 1
    end

    test "overwrites existing keys" do
      doc = Document.new(literal(:integer, 42), :python, %{version: 1})

      updated = Document.update_metadata(doc, %{version: 2})

      assert updated.metadata.version == 2
    end
  end

  describe "variables/1" do
    test "extracts variables from AST" do
      ast = binary_op(:arithmetic, :+, variable("x"), variable("y"))
      doc = Document.new(ast, :python)

      assert Document.variables(doc) == MapSet.new(["x", "y"])
    end

    test "returns empty set for literal" do
      doc = Document.new(literal(:integer, 42), :python)

      assert Document.variables(doc) == MapSet.new([])
    end
  end
end
