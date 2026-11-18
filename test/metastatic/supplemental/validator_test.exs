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

  defmodule MockSpawner do
    @behaviour Supplemental

    @impl true
    def info do
      %Info{
        name: :mock_spawner,
        language: :python,
        constructs: [:spawn_actor],
        requires: [],
        description: "Mock spawner supplemental"
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

    test "detects a construct claimed by a registered supplemental" do
      :ok = Registry.register(MockActor)

      ast = {:actor_call, [], [{:variable, [], "w"}]}
      assert Validator.detect_required_constructs(ast) == [:actor_call]
    end

    test "ignores unknown node types that no supplemental claims" do
      # An adapter-specific node nobody declares is not a "requirement".
      # Reporting it made `mix metastatic.supplemental_check` cry wolf on
      # perfectly ordinary code.
      ast = {:some_adapter_specific_node, [], []}
      assert Validator.detect_required_constructs(ast) == []
    end

    test "detects constructs nested inside core nodes" do
      :ok = Registry.register(MockActor)

      ast = {:block, [], [{:actor_call, [], []}, {:literal, [subtype: :integer], 1}]}
      assert :actor_call in Validator.detect_required_constructs(ast)
    end

    test "deduplicates repeated constructs and sorts them" do
      :ok = Registry.register(MockActor)
      :ok = Registry.register(MockSpawner)

      ast = {:block, [], [{:actor_call, [], []}, {:actor_call, [], []}, {:spawn_actor, [], []}]}
      assert Validator.detect_required_constructs(ast) == [:actor_call, :spawn_actor]
    end

    test "does not descend into incidental {:ok, _}-style tuples" do
      # A 2-tuple is not a MetaAST node, so it must not be reported.
      assert Validator.detect_required_constructs({:ok, :whatever}) == []
    end
  end

  describe "analyze/2 and compatible?/2" do
    test "nothing is required when no supplemental claims the construct" do
      d = doc({:actor_call, [], []})

      assert {:ok, result} = Validator.analyze(d, :python)
      assert result.required == []
      assert result.missing == []
      assert Validator.compatible?(d, :python)
    end

    test "reports the construct as required once a supplemental claims it" do
      :ok = Registry.register(MockActor)
      d = doc({:actor_call, [], []})

      assert {:ok, result} = Validator.analyze(d, :python)
      assert result.required == [:actor_call]
      assert result.missing == []
      assert Validator.compatible?(d, :python)
    end

    test "reports missing when the required construct has no supplemental for the target" do
      :ok = Registry.register(MockActor)
      d = doc({:actor_call, [], []})

      # MockActor is registered for :python only.
      assert {:error, result} = Validator.analyze(d, :javascript)
      assert result.missing == [:actor_call]
      refute Validator.compatible?(d, :javascript)
    end

    test "reports success for an AST needing no supplementals" do
      d = doc({:literal, [subtype: :integer], 1})
      assert {:ok, _} = Validator.analyze(d, :python)
      assert Validator.compatible?(d, :python)
    end
  end
end
