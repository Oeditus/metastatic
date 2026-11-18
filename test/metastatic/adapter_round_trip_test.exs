defmodule Metastatic.AdapterRoundTripTest do
  @moduledoc """
  Regression tests for defects fixed in the 2026-11-18 audit.

  Each block names the defect it locks down, so a future regression points
  straight at the behaviour that broke.
  """

  use ExUnit.Case, async: true

  alias Metastatic.{Adapter, AST, Document, Validator}
  alias Metastatic.Adapters.Elixir, as: ElixirAdapter

  describe "defect 7: Adapter.round_trip/2 keeps parse metadata" do
    test "round-trips a simple expression through the Elixir adapter" do
      assert {:ok, "x + 5"} = Adapter.round_trip(ElixirAdapter, "x + 5")
    end

    test "round-trips a module" do
      source = "defmodule A do\n  def f(x), do: x + 1\nend"
      assert {:ok, result} = Adapter.round_trip(ElixirAdapter, source)
      assert result =~ "defmodule A do"
    end

    test "propagates a parse error instead of raising" do
      assert {:error, _} = Adapter.round_trip(ElixirAdapter, "def f(")
    end

    test "is documented with a runnable example" do
      # The previous doctest referenced a non-existent `MyAdapter`, so it was
      # never exercised. The doc now uses a real adapter.
      {:docs_v1, _, _, _, _, _, docs} = Code.fetch_docs(Adapter)

      {_, _, _, doc, _} =
        Enum.find(docs, fn
          {{:function, :round_trip, 2}, _, _, _, _} -> true
          _ -> false
        end)

      assert doc["en"] =~ "Metastatic.Adapters.Elixir"
    end
  end

  describe "defect 4: nil is a legal MetaAST child" do
    test "conforms?/1 accepts nil" do
      assert AST.conforms?(nil)
    end

    test "conforms?/1 accepts a conditional with a nil else-branch" do
      ast =
        {:conditional, [],
         [
           {:variable, [], "c"},
           {:block, [], [{:literal, [subtype: :integer], 1}]},
           nil
         ]}

      assert AST.conforms?(ast)
    end

    test "Validator accepts a document containing nil children" do
      ast =
        {:conditional, [],
         [
           {:variable, [], "c"},
           {:block, [], [{:literal, [subtype: :integer], 1}]},
           nil
         ]}

      doc = Document.new(ast, :elixir)
      assert {:ok, _meta} = Validator.validate(doc)
    end

    test "conforms?/1 still rejects a non-node, non-nil term" do
      refute AST.conforms?(:just_an_atom)
      refute AST.conforms?("a string")
    end
  end

  describe "defect 4: :wildcard node type" do
    test "is a core node type" do
      assert AST.layer(:wildcard) == :core
    end

    test "conforms" do
      assert AST.conforms?({:wildcard, [], nil})
    end

    test "survives a document round-trip through the validator" do
      ast =
        {:pattern_match, [],
         [
           {:variable, [], "x"},
           {:match_arm, [pattern: {:wildcard, [], nil}], [{:literal, [subtype: :integer], 2}]}
         ]}

      doc = Document.new(ast, :elixir)
      assert {:ok, _} = Validator.validate(doc)
    end
  end

  describe "defect 18: NL.AST.text/2 include_code option" do
    alias Metastatic.NL.AST

    setup do
      doc =
        AST.document([
          AST.paragraph([AST.token("Hello")]),
          AST.code_block("IO.puts(1)", language: "elixir")
        ])

      %{doc: doc}
    end

    test "omits code by default", %{doc: doc} do
      refute AST.text(doc) =~ "IO.puts"
      assert AST.text(doc) == "Hello"
    end

    test "includes code when asked", %{doc: doc} do
      text = AST.text(doc, include_code: true)
      assert text =~ "IO.puts(1)"
      assert text =~ "Hello"
    end

    test "includes inline code when asked" do
      doc = AST.document([AST.paragraph([AST.inline_code("x = 1")])])
      assert AST.text(doc) == ""
      assert AST.text(doc, include_code: true) =~ "x = 1"
    end

    test "text/1 keeps its one-argument arity" do
      doc = AST.document([AST.paragraph([AST.token("Hi")])])
      assert AST.text(doc) == "Hi"
    end
  end
end
