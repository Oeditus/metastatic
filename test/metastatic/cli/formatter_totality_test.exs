defmodule Metastatic.CLI.FormatterTotalityTest do
  @moduledoc """
  `Metastatic.CLI.Formatter.to_map/1` and its renderers must be **total**:
  every MetaAST shape the adapters can produce has to render, because the
  formatter is the last step of `mix metastatic.inspect`.

  Defect 17: a conditional with anything other than 2 or 3 children raised
  `CaseClauseError`, so `--format tree` crashed on a single-arm `case`.
  """

  use ExUnit.Case, async: true

  alias Metastatic.CLI.Formatter

  describe "conditional arity" do
    test "renders a 3-element conditional" do
      ast =
        {:conditional, [],
         [
           {:variable, [], "c"},
           {:block, [], [{:literal, [subtype: :integer], 1}]},
           {:block, [], [{:literal, [subtype: :integer], 2}]}
         ]}

      assert Formatter.format(ast, :tree) =~ "conditional"
    end

    test "renders a 2-element conditional" do
      ast = {:conditional, [], [{:variable, [], "c"}, {:block, [], []}]}
      assert Formatter.format(ast, :tree) =~ "conditional"
    end

    test "renders a 1-element conditional instead of raising" do
      ast = {:conditional, [], [{:variable, [], "c"}]}
      assert Formatter.format(ast, :tree) =~ "conditional"
    end

    test "renders a 0-element conditional instead of raising" do
      ast = {:conditional, [], []}
      assert Formatter.format(ast, :tree) =~ "conditional"
    end

    test "renders an over-long conditional instead of raising" do
      ast =
        {:conditional, [],
         [
           {:variable, [], "a"},
           {:variable, [], "b"},
           {:variable, [], "c"},
           {:variable, [], "d"}
         ]}

      assert Formatter.format(ast, :tree) =~ "conditional"
    end

    test "all three formats survive a degenerate conditional" do
      ast = {:conditional, [], [{:variable, [], "c"}]}

      for format <- [:tree, :json, :plain] do
        assert is_binary(Formatter.format(ast, format))
      end
    end
  end

  describe "unknown node types" do
    test "fall back to the type name in every format" do
      ast = {:some_future_node, [foo: :bar], []}

      for format <- [:tree, :json, :plain] do
        assert is_binary(Formatter.format(ast, format))
      end
    end
  end
end
