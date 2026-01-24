defmodule Metastatic.Analysis.RegistryTest do
  use ExUnit.Case, async: false

  alias Metastatic.Analysis.Registry

  # Test analyzer modules
  defmodule TestAnalyzer do
    @behaviour Metastatic.Analysis.Analyzer

    @impl true
    def info do
      %{
        name: :test_analyzer,
        category: :correctness,
        description: "Test analyzer",
        severity: :warning,
        explanation: "For testing",
        configurable: false
      }
    end

    @impl true
    def analyze(_node, _context), do: []
  end

  defmodule AnotherTestAnalyzer do
    @behaviour Metastatic.Analysis.Analyzer

    @impl true
    def info do
      %{
        name: :another_test,
        category: :style,
        description: "Another test analyzer",
        severity: :info,
        explanation: "For testing",
        configurable: true
      }
    end

    @impl true
    def analyze(_node, _context), do: []
  end

  setup do
    # Clear registry before each test
    Registry.clear()
    :ok
  end

  describe "register/1" do
    test "registers a valid analyzer" do
      assert :ok = Registry.register(TestAnalyzer)
      assert TestAnalyzer in Registry.list_all()
    end

    test "rejects invalid module" do
      defmodule NotAnAnalyzer do
        def some_func, do: :ok
      end

      assert {:error, _} = Registry.register(NotAnAnalyzer)
    end

    test "rejects analyzer with conflicting name" do
      assert :ok = Registry.register(TestAnalyzer)

      defmodule ConflictingAnalyzer do
        @behaviour Metastatic.Analysis.Analyzer

        @impl true
        def info do
          %{
            name: :test_analyzer,
            category: :style,
            description: "Conflicting",
            severity: :warning,
            explanation: "Conflict",
            configurable: false
          }
        end

        @impl true
        def analyze(_node, _context), do: []
      end

      assert {:error, message} = Registry.register(ConflictingAnalyzer)
      assert message =~ "already registered"
    end
  end

  describe "unregister/1" do
    test "unregisters an analyzer" do
      :ok = Registry.register(TestAnalyzer)
      assert TestAnalyzer in Registry.list_all()

      :ok = Registry.unregister(TestAnalyzer)
      refute TestAnalyzer in Registry.list_all()
    end

    test "is idempotent" do
      :ok = Registry.register(TestAnalyzer)
      :ok = Registry.unregister(TestAnalyzer)
      :ok = Registry.unregister(TestAnalyzer)
    end
  end

  describe "list_all/0" do
    test "returns empty list when no analyzers registered" do
      assert Registry.list_all() == []
    end

    test "returns all registered analyzers" do
      :ok = Registry.register(TestAnalyzer)
      :ok = Registry.register(AnotherTestAnalyzer)

      all = Registry.list_all()
      assert TestAnalyzer in all
      assert AnotherTestAnalyzer in all
      assert [_, _] = all
    end
  end

  describe "list_by_category/1" do
    test "returns empty list for unused category" do
      assert Registry.list_by_category(:performance) == []
    end

    test "returns analyzers in specific category" do
      :ok = Registry.register(TestAnalyzer)
      :ok = Registry.register(AnotherTestAnalyzer)

      correctness = Registry.list_by_category(:correctness)
      assert TestAnalyzer in correctness
      refute AnotherTestAnalyzer in correctness

      style = Registry.list_by_category(:style)
      assert AnotherTestAnalyzer in style
      refute TestAnalyzer in style
    end
  end

  describe "get_by_name/1" do
    test "returns nil for nonexistent analyzer" do
      assert Registry.get_by_name(:nonexistent) == nil
    end

    test "returns analyzer by name" do
      :ok = Registry.register(TestAnalyzer)
      assert Registry.get_by_name(:test_analyzer) == TestAnalyzer
    end
  end

  describe "list_categories/0" do
    test "returns empty list when no analyzers" do
      assert Registry.list_categories() == []
    end

    test "returns sorted list of categories" do
      :ok = Registry.register(TestAnalyzer)
      :ok = Registry.register(AnotherTestAnalyzer)

      categories = Registry.list_categories()
      assert :correctness in categories
      assert :style in categories
      assert categories == Enum.sort(categories)
    end
  end

  describe "configure/2 and get_config/1" do
    test "sets and retrieves configuration" do
      :ok = Registry.register(TestAnalyzer)

      config = %{threshold: 10, enabled: true}
      :ok = Registry.configure(TestAnalyzer, config)

      assert Registry.get_config(TestAnalyzer) == config
    end

    test "merges configuration" do
      :ok = Registry.register(TestAnalyzer)

      :ok = Registry.configure(TestAnalyzer, %{threshold: 10})
      :ok = Registry.configure(TestAnalyzer, %{enabled: true})

      assert Registry.get_config(TestAnalyzer) == %{threshold: 10, enabled: true}
    end

    test "returns empty map for unconfigured analyzer" do
      :ok = Registry.register(TestAnalyzer)
      assert Registry.get_config(TestAnalyzer) == %{}
    end
  end

  describe "clear/0" do
    test "removes all analyzers" do
      :ok = Registry.register(TestAnalyzer)
      :ok = Registry.register(AnotherTestAnalyzer)

      assert [_, _] = Registry.list_all()

      :ok = Registry.clear()
      assert Registry.list_all() == []
    end
  end
end
