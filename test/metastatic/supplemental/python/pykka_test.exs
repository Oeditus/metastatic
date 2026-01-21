defmodule Metastatic.Supplemental.Python.PykkaTest do
  use ExUnit.Case, async: true

  alias Metastatic.Supplemental.Python.Pykka

  describe "info/0" do
    test "returns valid supplemental info" do
      info = Pykka.info()

      assert info.name == :pykka_actor
      assert info.language == :python
      assert :actor_call in info.constructs
      assert :actor_cast in info.constructs
      assert :spawn_actor in info.constructs
      assert "pykka >= 3.0" in info.requires
    end
  end

  describe "transform/3 - actor_call" do
    test "transforms actor_call with atom message" do
      meta_ast = {:actor_call, {:variable, "actor_ref"}, {:literal, :atom, :get_state}, 5000}

      assert {:ok, result} = Pykka.transform(meta_ast, :python, %{})
      assert result["_type"] == "Call"
      assert result["func"]["attr"] == "ask"
      assert result["func"]["value"]["id"] == "actor_ref"
      assert length(result["keywords"]) == 1
      assert hd(result["keywords"])["arg"] == "timeout"
      assert hd(result["keywords"])["value"]["value"] == 5.0
    end

    test "transforms actor_call with variable message" do
      meta_ast = {:actor_call, {:variable, "my_actor"}, {:variable, "message"}, 3000}

      assert {:ok, result} = Pykka.transform(meta_ast, :python, %{})
      assert result["args"] |> hd() |> Map.get("id") == "message"
    end
  end

  describe "transform/3 - actor_cast" do
    test "transforms actor_cast" do
      meta_ast = {:actor_cast, {:variable, "actor_ref"}, {:literal, :string, "hello"}}

      assert {:ok, result} = Pykka.transform(meta_ast, :python, %{})
      assert result["_type"] == "Call"
      assert result["func"]["attr"] == "tell"
      assert result["func"]["value"]["id"] == "actor_ref"
      assert result["keywords"] == []
    end
  end

  describe "transform/3 - spawn_actor" do
    test "transforms spawn_actor with arguments" do
      meta_ast =
        {:spawn_actor, {:variable, "MyActor"}, [{:literal, :integer, 42}, {:variable, "config"}]}

      assert {:ok, result} = Pykka.transform(meta_ast, :python, %{})
      assert result["_type"] == "Call"
      assert result["func"]["attr"] == "start"
      assert result["func"]["value"]["id"] == "MyActor"
      assert length(result["args"]) == 2
    end
  end

  describe "transform/3 - error cases" do
    test "returns error for unsupported construct" do
      assert :error = Pykka.transform({:unsupported_construct, "data"}, :python, %{})
    end

    test "returns error for different language" do
      meta_ast = {:actor_call, {:variable, "actor"}, {:literal, :atom, :msg}, 1000}
      assert :error = Pykka.transform(meta_ast, :javascript, %{})
    end
  end
end
