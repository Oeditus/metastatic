defmodule Metastatic.MetaASTTest do
  use ExUnit.Case, async: true

  alias Metastatic.MetaAST

  @leaf {:literal, [subtype: :integer], 42}
  @tree {:binary_op, [category: :arithmetic, operator: :+],
         [{:variable, [], "x"}, {:literal, [subtype: :integer], 5}]}

  describe "accessors" do
    test "type/1, meta/1, children/1" do
      assert MetaAST.type(@tree) == :binary_op
      assert MetaAST.meta(@tree) == [category: :arithmetic, operator: :+]
      assert MetaAST.children(@leaf) == 42
      assert length(MetaAST.children(@tree)) == 2
    end
  end

  describe "metadata helpers" do
    test "get_meta/2,3 reads values with defaults" do
      assert MetaAST.get_meta(@leaf, :subtype) == :integer
      assert MetaAST.get_meta(@leaf, :line) == nil
      assert MetaAST.get_meta(@leaf, :line, 0) == 0
    end

    test "put_meta/3 sets a key" do
      assert MetaAST.get_meta(MetaAST.put_meta(@leaf, :line, 7), :line) == 7
    end

    test "update_meta/2 merges a keyword list" do
      updated = MetaAST.update_meta(@leaf, line: 3, col: 4)
      assert MetaAST.get_meta(updated, :line) == 3
      assert MetaAST.get_meta(updated, :col) == 4
      assert MetaAST.get_meta(updated, :subtype) == :integer
    end

    test "update_meta/4 applies a function to a value" do
      updated = MetaAST.update_meta(@leaf, :line, 0, &(&1 + 1))
      assert MetaAST.get_meta(updated, :line) == 1
    end

    test "update_children/2 replaces the payload" do
      assert MetaAST.children(MetaAST.update_children(@leaf, 99)) == 99
    end
  end

  describe "traverse/4" do
    test "visits every node in pre-order" do
      {_ast, types} =
        MetaAST.traverse(@tree, [], fn n, acc -> {n, [MetaAST.type(n) | acc]} end, fn n, acc ->
          {n, acc}
        end)

      assert Enum.reverse(types) == [:binary_op, :variable, :literal]
    end

    test "walks nodes embedded in metadata" do
      inner = {:token, [pos: :noun], "cat"}
      node = {:coreference, [target: inner], []}

      {_ast, seen} =
        MetaAST.traverse(node, [], fn n, acc -> {n, [MetaAST.type(n) | acc]} end, fn n, acc ->
          {n, acc}
        end)

      assert :token in seen
    end

    test "prewalk/2 and postwalk/2 transform leaves" do
      doubled =
        MetaAST.postwalk(@tree, fn
          {:literal, m, v} -> {:literal, m, v * 2}
          n -> n
        end)

      assert MetaAST.children(doubled) |> List.last() == {:literal, [subtype: :integer], 10}
    end
  end

  describe "prewalker/1,3 and path/2" do
    test "prewalker/1 yields nodes depth-first" do
      assert @tree |> MetaAST.prewalker() |> Enum.map(&MetaAST.type/1) ==
               [:binary_op, :variable, :literal]
    end

    test "prewalker/3 threads an accumulator" do
      assert @tree |> MetaAST.prewalker(0, fn _n, acc -> {acc, acc + 1} end) |> Enum.to_list() ==
               [0, 1, 2]
    end

    test "path/2 returns the path from a match to the root" do
      path =
        MetaAST.path(@tree, fn
          {:literal, _, 5} -> true
          _ -> false
        end)

      assert Enum.map(path, &MetaAST.type/1) == [:literal, :binary_op]
    end

    test "path/2 returns nil when nothing matches" do
      assert MetaAST.path(@tree, fn _ -> false end) == nil
    end
  end
end
