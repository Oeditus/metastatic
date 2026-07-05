defmodule Metastatic.Semantic.Callbacks.ElixirResolverTest do
  use ExUnit.Case, async: false

  alias Metastatic.Semantic.Callbacks
  alias Metastatic.Semantic.Callbacks.ElixirResolver

  setup do
    Callbacks.clear()
    Callbacks.register_builtins()
    ElixirResolver.clear_cache()
    :ok
  end

  describe "resolve_behaviours/1" do
    test "resolves GenServer as a behaviour (it is one)" do
      behaviours = ElixirResolver.resolve_behaviours("GenServer")
      assert "GenServer" in behaviours
    end

    test "resolves Supervisor as a behaviour" do
      behaviours = ElixirResolver.resolve_behaviours("Supervisor")
      assert "Supervisor" in behaviours
    end

    test "returns empty list for non-existent modules" do
      assert [] = ElixirResolver.resolve_behaviours("Totally.Nonexistent.Module.XYZ")
    end

    test "returns empty list for modules without behaviours" do
      behaviours = ElixirResolver.resolve_behaviours("String")
      assert behaviours == []
    end

    test "caches results across calls" do
      _first = ElixirResolver.resolve_behaviours("GenServer")
      second = ElixirResolver.resolve_behaviours("GenServer")
      assert "GenServer" in second
    end

    test "clear_cache resets cached results" do
      _first = ElixirResolver.resolve_behaviours("GenServer")
      ElixirResolver.clear_cache()
      # Should still work after clearing
      result = ElixirResolver.resolve_behaviours("GenServer")
      assert "GenServer" in result
    end
  end

  describe "resolve_behaviours/1 - auto-registration" do
    test "auto-registers discovered callbacks in the Callbacks registry" do
      # Clear and only keep non-GenServer builtins
      Callbacks.clear()

      # Resolve GenServer -- should auto-register its callbacks
      ElixirResolver.resolve_behaviours("GenServer")

      # Now check that GenServer callbacks are in the registry
      assert Callbacks.callback?(:elixir, "GenServer", "handle_call", 3)
      assert Callbacks.callback?(:elixir, "GenServer", "init", 1)
    end
  end

  describe "integration with enricher" do
    test "dynamically resolved behaviours enable callback annotation" do
      # Clear everything to start fresh
      Callbacks.clear()
      ElixirResolver.clear_cache()

      # Before resolution, GenServer callbacks should not be known
      refute Callbacks.callback?(:elixir, "GenServer", "handle_call", 3)

      # Resolve via the resolver
      behaviours = ElixirResolver.resolve_behaviours("GenServer")
      assert "GenServer" in behaviours

      # Now callbacks should be registered
      assert Callbacks.callback?(:elixir, "GenServer", "handle_call", 3)
      assert Callbacks.callback?(:elixir, "GenServer", "init", 1)
      assert Callbacks.callback?(:elixir, "GenServer", "terminate", 2)
    end
  end
end

# Test fixture: a module that defines a custom behaviour
defmodule Metastatic.Test.CustomBehaviour do
  @callback handle_work(term()) :: :ok | {:error, term()}
  @callback setup(keyword()) :: {:ok, term()}
end

defmodule Metastatic.Test.CustomBehaviourUser do
  @moduledoc false
  defmacro __using__(_opts) do
    quote do
      @behaviour Metastatic.Test.CustomBehaviour
    end
  end
end
