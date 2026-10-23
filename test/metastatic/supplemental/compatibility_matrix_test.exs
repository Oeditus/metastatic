defmodule Metastatic.Supplemental.CompatibilityMatrixTest do
  use ExUnit.Case, async: false

  alias Metastatic.Supplemental
  alias Metastatic.Supplemental.{CompatibilityMatrix, Info, Registry}

  defmodule MockActor do
    @behaviour Supplemental

    @impl true
    def info do
      %Info{
        name: :mock_actor,
        language: :python,
        constructs: [:actor_call, :actor_cast],
        requires: ["pykka >= 3.0"],
        description: "Mock actor supplemental"
      }
    end

    @impl true
    def transform(_, _, _), do: {:ok, %{}}
  end

  defmodule MockAsync do
    @behaviour Supplemental

    @impl true
    def info do
      %Info{
        name: :mock_async,
        language: :python,
        constructs: [:async_operation],
        requires: [],
        description: "Mock async supplemental"
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

  describe "build/0" do
    test "returns an empty matrix when nothing is registered" do
      assert CompatibilityMatrix.build() == %{}
    end

    test "maps each construct to its language and providing module" do
      :ok = Registry.register(MockActor)
      matrix = CompatibilityMatrix.build()

      assert matrix[:actor_call][:python] == [MockActor]
      assert matrix[:actor_cast][:python] == [MockActor]
      refute Map.has_key?(matrix, :async_operation)
    end

    test "aggregates multiple supplementals for the same language" do
      :ok = Registry.register(MockActor)
      :ok = Registry.register(MockAsync)
      matrix = CompatibilityMatrix.build()

      assert matrix[:actor_call][:python] == [MockActor]
      assert matrix[:async_operation][:python] == [MockAsync]
    end
  end

  describe "supported?/2" do
    test "is true for a registered construct/language pair" do
      :ok = Registry.register(MockActor)
      assert CompatibilityMatrix.supported?(:actor_call, :python)
    end

    test "is false for an unsupported language" do
      :ok = Registry.register(MockActor)
      refute CompatibilityMatrix.supported?(:actor_call, :go)
    end
  end

  describe "languages_for_construct/1 and constructs_for_language/1" do
    test "lists languages providing a construct" do
      :ok = Registry.register(MockActor)
      assert CompatibilityMatrix.languages_for_construct(:actor_call) == [:python]
    end

    test "returns [] for an unknown construct" do
      assert CompatibilityMatrix.languages_for_construct(:does_not_exist) == []
    end

    test "lists constructs for a language, sorted" do
      :ok = Registry.register(MockActor)
      assert CompatibilityMatrix.constructs_for_language(:python) == [:actor_call, :actor_cast]
    end
  end

  describe "providers_for/2" do
    test "returns the providing modules" do
      :ok = Registry.register(MockActor)
      assert CompatibilityMatrix.providers_for(:actor_call, :python) == [MockActor]
    end

    test "returns [] when nothing provides the construct" do
      assert CompatibilityMatrix.providers_for(:nope, :python) == []
    end
  end

  describe "format_table/1" do
    test "renders a text table" do
      :ok = Registry.register(MockActor)
      table = CompatibilityMatrix.format_table()
      assert is_binary(table)
      assert table =~ "Construct"
      assert table =~ "actor_call"
    end

    test "renders a markdown table" do
      :ok = Registry.register(MockActor)
      table = CompatibilityMatrix.format_table(format: :markdown)
      assert table =~ "| Construct |"
      assert table =~ "| actor_call |"
    end

    test "handles an empty matrix" do
      assert is_binary(CompatibilityMatrix.format_table())
    end
  end

  describe "detailed_report/0" do
    test "reports no supplementals when empty" do
      report = CompatibilityMatrix.detailed_report()
      assert report =~ "No supplemental modules registered"
    end

    test "lists module details, language, constructs and requirements" do
      :ok = Registry.register(MockActor)
      report = CompatibilityMatrix.detailed_report()

      assert report =~ "MockActor"
      assert report =~ "Target Language: python"
      assert report =~ "actor_call"
      assert report =~ "pykka >= 3.0"
    end

    test "shows (none) for a supplemental without requirements" do
      :ok = Registry.register(MockAsync)
      assert CompatibilityMatrix.detailed_report() =~ "Dependencies: (none)"
    end
  end
end
