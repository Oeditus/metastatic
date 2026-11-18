defmodule Metastatic.CLI.InspectorTest do
  @moduledoc """
  Regression tests for the CLI inspector (defect 16).

  The inspector used to carry its own copy of the MetaAST layer table, which
  had drifted from `Metastatic.AST.layer/1` (the `:structural` layer was
  missing entirely), and its map traversal matched `{k, v}` tuples instead of
  the canonical `{:pair, meta, [k, v]}` nodes.
  """

  use ExUnit.Case, async: true

  alias Metastatic.{CLI.Inspector, Document}

  defp inspect_ast(ast, opts \\ []) do
    {:ok, result} = Inspector.inspect_document(Document.new(ast, :elixir), opts)
    result
  end

  describe "layer classification follows AST.layer/1" do
    test "core nodes report :core" do
      assert inspect_ast({:literal, [subtype: :integer], 1}).layer == :core
    end

    test "extended nodes report :extended" do
      assert inspect_ast({:loop, [loop_type: :while], []}).layer == :extended
    end

    test "structural nodes report :extended, not :core" do
      # `container`/`function_def` are `:structural` in `AST.layer/1`; the CLI
      # vocabulary folds them into `:extended`.
      ast = {:container, [container_type: :module, name: "A"], []}
      assert inspect_ast(ast).layer == :extended
    end

    test "native nodes report :native" do
      assert inspect_ast({:language_specific, [language: :elixir], nil}).layer == :native
    end
  end

  describe "map traversal understands canonical :pair nodes" do
    setup do
      ast =
        {:map, [],
         [
           {:pair, [], [{:literal, [subtype: :symbol], :a}, {:literal, [subtype: :integer], 1}]},
           {:pair, [], [{:literal, [subtype: :symbol], :b}, {:literal, [subtype: :integer], 2}]}
         ]}

      %{ast: ast}
    end

    test "counts both keys and values", %{ast: ast} do
      # 1 map + 4 leaves (2 keys + 2 values). `:pair` nodes are structural
      # containers here, so they are not counted separately — what matters is
      # that the leaves are reached at all, which the old `{k, v}` match
      # silently skipped.
      assert inspect_ast(ast).node_count == 5
    end

    test "depth reaches through the pairs", %{ast: ast} do
      # map -> pair -> leaf. `:pair` is a container, so the leaf sits at depth 2
      # below the map's own level. Before the fix the pairs were skipped
      # entirely and the map reported depth 1.
      assert inspect_ast(ast).depth == 2
    end
  end

  describe "layer filtering" do
    test "keeps the requested layer" do
      ast = {:literal, [subtype: :integer], 1}
      assert inspect_ast(ast, layer: :core).ast == ast
    end

    test "drops nodes from other layers" do
      ast = {:language_specific, [language: :elixir], nil}
      assert inspect_ast(ast, layer: :core).ast == nil
    end
  end
end
