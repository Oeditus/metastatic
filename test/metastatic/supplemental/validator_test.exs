defmodule Metastatic.Supplemental.ValidatorTest do
  use ExUnit.Case, async: false

  alias Metastatic.{Document, Supplemental}
  alias Metastatic.Supplemental.{Info, Registry, Validator}

  defmodule MockActor do
    @behaviour Supplemental

    @impl true
    def info do
      %Info{
        name: :mock_actor,
        language: :python,
        constructs: [:actor_call],
        requires: [],
        description: "Mock actor supplemental"
      }
    end

    @impl true
    def transform(_, _, _), do: {:ok, %{}}
  end

  setup do
    Registry.clear()
    on_exit(fn -> Registry.clear() end)
    :ok
  end

  defp doc(ast), do: Document.new(ast, :elixir)

  describe "detect_required_constructs/1" do
    test "returns [] for a purely core AST" do
      ast =
        {:binary_op, [operator: :+], [{:variable, [], "x"}, {:literal, [subtype: :integer], 1}]}

      assert Validator.detect_required_constructs(ast) == []
    end

    test "detects a non-core construct" do
      ast = {:actor_call, [], [{:variable, [], "w"}]}
      assert Validator.detect_required_constructs(ast) == [:actor_call]
    end

    test "detects constructs nested inside core nodes" do
      ast = {:block, [], [{:actor_call, [], []}, {:literal, [subtype: :integer], 1}]}
      assert :actor_call in Validator.detect_required_constructs(ast)
    end

    test "deduplicates repeated constructs and sorts them" do
      ast = {:block, [], [{:actor_call, [], []}, {:actor_call, [], []}, {:spawn_actor, [], []}]}
      assert Validator.detect_required_constructs(ast) == [:actor_call, :spawn_actor]
    end

    test "does not descend into incidental {:ok, _}-style tuples" do
      # A 2-tuple is not a MetaAST node, so it must not be reported.
      assert Validator.detect_required_constructs({:ok, :whatever}) == []
    end
  end

  describe "analyze/2 and compatible?/2" do
    test "reports missing constructs when nothing is registered" do
      d = doc({:actor_call, [], []})

      assert {:error, result} = Validator.analyze(d, :python)
      assert result.required == [:actor_call]
      assert result.missing == [:actor_call]
      refute Validator.compatible?(d, :python)
    end

    test "reports success when the construct is available" do
      :ok = Registry.register(MockActor)
      d = doc({:actor_call, [], []})

      assert {:ok, result} = Validator.analyze(d, :python)
      assert result.missing == []
      assert Validator.compatible?(d, :python)
    end

    test "reports success for an AST needing no supplementals" do
      d = doc({:literal, [subtype: :integer], 1})
      assert {:ok, _} = Validator.analyze(d, :python)
      assert Validator.compatible?(d, :python)
    end
  end
end
