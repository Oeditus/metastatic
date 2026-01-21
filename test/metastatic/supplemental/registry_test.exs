defmodule Metastatic.Supplemental.RegistryTest do
  use ExUnit.Case, async: false

  alias Metastatic.Supplemental
  alias Metastatic.Supplemental.Info
  alias Metastatic.Supplemental.Registry
  alias Metastatic.Supplemental.Error.ConflictError

  # Mock supplemental modules for testing
  defmodule MockPythonActorSupplemental do
    @behaviour Supplemental

    @impl true
    def info do
      %Info{
        name: :mock_python_actor,
        language: :python,
        constructs: [:actor_call, :actor_cast],
        requires: ["pykka >= 3.0"],
        description: "Mock Python actor supplemental"
      }
    end

    @impl true
    def transform({:actor_call, _actor, _message, _timeout}, :python, _metadata) do
      {:ok, %{"_type" => "Call"}}
    end

    def transform(_, _, _), do: :error
  end

  defmodule MockPythonAsyncSupplemental do
    @behaviour Supplemental

    @impl true
    def info do
      %Info{
        name: :mock_python_async,
        language: :python,
        constructs: [:async_operation],
        requires: [],
        description: "Mock Python async supplemental"
      }
    end

    @impl true
    def transform({:async_operation, _op}, :python, _metadata) do
      {:ok, %{"_type" => "Await"}}
    end

    def transform(_, _, _), do: :error
  end

  defmodule ConflictingSupplemental do
    @behaviour Supplemental

    @impl true
    def info do
      %Info{
        name: :conflicting,
        language: :python,
        constructs: [:actor_call],
        # Conflicts with MockPythonActorSupplemental
        requires: [],
        description: "Conflicting supplemental"
      }
    end

    @impl true
    def transform(_, _, _), do: :error
  end

  setup do
    # Clear registry before each test
    Registry.clear()
    :ok
  end

  describe "registration" do
    test "registers a valid supplemental module" do
      assert :ok = Registry.register(MockPythonActorSupplemental)

      assert MockPythonActorSupplemental in Registry.list_all()
    end

    test "registers multiple non-conflicting supplementals" do
      assert :ok = Registry.register(MockPythonActorSupplemental)
      assert :ok = Registry.register(MockPythonAsyncSupplemental)

      all = Registry.list_all()
      assert MockPythonActorSupplemental in all
      assert MockPythonAsyncSupplemental in all
      assert length(all) == 2
    end

    test "prevents registration of conflicting supplementals" do
      assert :ok = Registry.register(MockPythonActorSupplemental)

      assert {:error, %ConflictError{} = error} = Registry.register(ConflictingSupplemental)
      assert error.construct == :actor_call
      assert error.language == :python
      assert length(error.modules) == 2
    end

    test "allows same construct for different languages" do
      # In a real scenario, you'd have supplementals for different languages
      # For now, verify the conceptual registration works
      assert :ok = Registry.register(MockPythonActorSupplemental)
      # Would be: assert :ok = Registry.register(MockJavaScriptActorSupplemental)
    end
  end

  describe "unregistration" do
    test "unregisters a registered supplemental" do
      Registry.register(MockPythonActorSupplemental)
      assert MockPythonActorSupplemental in Registry.list_all()

      Registry.unregister(MockPythonActorSupplemental)
      refute MockPythonActorSupplemental in Registry.list_all()
    end

    test "unregistering removes from all indices" do
      Registry.register(MockPythonActorSupplemental)

      assert Registry.get_for_construct(:python, :actor_call) == MockPythonActorSupplemental
      assert Registry.list_for_language(:python) == [MockPythonActorSupplemental]

      Registry.unregister(MockPythonActorSupplemental)

      assert Registry.get_for_construct(:python, :actor_call) == nil
      assert Registry.list_for_language(:python) == []
    end

    test "unregistering non-existent module is safe" do
      assert :ok = Registry.unregister(MockPythonActorSupplemental)
    end
  end

  describe "lookup by language" do
    test "lists all supplementals for a language" do
      Registry.register(MockPythonActorSupplemental)
      Registry.register(MockPythonAsyncSupplemental)

      python_modules = Registry.list_for_language(:python)
      assert length(python_modules) == 2
      assert MockPythonActorSupplemental in python_modules
      assert MockPythonAsyncSupplemental in python_modules
    end

    test "returns empty list for language with no supplementals" do
      assert Registry.list_for_language(:javascript) == []
    end
  end

  describe "lookup by construct" do
    test "gets supplemental for specific construct" do
      Registry.register(MockPythonActorSupplemental)

      assert Registry.get_for_construct(:python, :actor_call) == MockPythonActorSupplemental
      assert Registry.get_for_construct(:python, :actor_cast) == MockPythonActorSupplemental
    end

    test "returns nil for unsupported construct" do
      Registry.register(MockPythonActorSupplemental)

      assert Registry.get_for_construct(:python, :unsupported_construct) == nil
    end

    test "returns nil for different language" do
      Registry.register(MockPythonActorSupplemental)

      assert Registry.get_for_construct(:javascript, :actor_call) == nil
    end
  end

  describe "available_constructs/1" do
    test "lists all constructs for a language" do
      Registry.register(MockPythonActorSupplemental)
      Registry.register(MockPythonAsyncSupplemental)

      constructs = Registry.available_constructs(:python)
      assert :actor_call in constructs
      assert :actor_cast in constructs
      assert :async_operation in constructs
      assert length(constructs) == 3
    end

    test "returns empty list for language with no supplementals" do
      assert Registry.available_constructs(:ruby) == []
    end

    test "returns sorted list" do
      Registry.register(MockPythonActorSupplemental)
      Registry.register(MockPythonAsyncSupplemental)

      constructs = Registry.available_constructs(:python)
      assert constructs == Enum.sort(constructs)
    end
  end

  describe "list_all/0" do
    test "lists all registered supplementals" do
      Registry.register(MockPythonActorSupplemental)
      Registry.register(MockPythonAsyncSupplemental)

      all = Registry.list_all()
      assert length(all) == 2
      assert MockPythonActorSupplemental in all
      assert MockPythonAsyncSupplemental in all
    end

    test "returns empty list when no supplementals registered" do
      assert Registry.list_all() == []
    end
  end

  describe "clear/0" do
    test "removes all registered supplementals" do
      Registry.register(MockPythonActorSupplemental)
      Registry.register(MockPythonAsyncSupplemental)

      assert length(Registry.list_all()) == 2

      Registry.clear()

      assert Registry.list_all() == []
      assert Registry.list_for_language(:python) == []
      assert Registry.get_for_construct(:python, :actor_call) == nil
    end
  end
end
