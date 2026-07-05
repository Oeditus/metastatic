defmodule Metastatic.Adapter.RegistryTest do
  use ExUnit.Case, async: false

  alias Metastatic.Adapter.Registry

  # Mock adapter for testing
  defmodule MockAdapter do
    @behaviour Metastatic.Adapter

    @impl true
    def parse(_source), do: {:ok, %{}}

    @impl true
    def to_meta(_native_ast), do: {:ok, {:literal, :integer, 42}, %{}}

    @impl true
    def from_meta(_meta_ast, _metadata), do: {:ok, %{}}

    @impl true
    def unparse(_native_ast), do: {:ok, "42"}

    @impl true
    def file_extensions, do: [".mock"]
  end

  # Invalid adapter (missing callbacks)
  defmodule InvalidAdapter do
    def parse(_source), do: {:ok, %{}}
    # Missing other required callbacks
  end

  setup do
    # Registry is already started by the application
    # Clear any existing registrations before each test
    Registry.list()
    |> Map.keys()
    |> Enum.each(&Registry.unregister/1)

    :ok
  end

  describe "register/2" do
    test "registers a valid adapter" do
      assert :ok = Registry.register(:mock, MockAdapter)
      assert {:ok, MockAdapter} = Registry.get(:mock)
    end

    test "rejects an invalid adapter" do
      assert {:error, :invalid_adapter} = Registry.register(:invalid, InvalidAdapter)
    end

    test "overwrites existing registration" do
      assert :ok = Registry.register(:mock, MockAdapter)
      assert {:ok, MockAdapter} = Registry.get(:mock)

      # Can re-register with same adapter
      assert :ok = Registry.register(:mock, MockAdapter)
      assert {:ok, MockAdapter} = Registry.get(:mock)
    end

    test "registers file extensions" do
      assert :ok = Registry.register(:mock, MockAdapter)
      assert {:ok, :mock} = Registry.detect_language("test.mock")
    end
  end

  describe "get/1" do
    test "returns adapter when registered" do
      Registry.register(:mock, MockAdapter)
      assert {:ok, MockAdapter} = Registry.get(:mock)
    end

    test "returns error when not registered" do
      assert {:error, :not_found} = Registry.get(:unknown)
    end
  end

  describe "unregister/1" do
    test "removes registered adapter" do
      Registry.register(:mock, MockAdapter)
      assert {:ok, MockAdapter} = Registry.get(:mock)

      assert :ok = Registry.unregister(:mock)
      assert {:error, :not_found} = Registry.get(:mock)
    end

    test "removes associated file extensions" do
      Registry.register(:mock, MockAdapter)
      assert {:ok, :mock} = Registry.detect_language("test.mock")

      Registry.unregister(:mock)
      assert {:error, :unknown_extension} = Registry.detect_language("test.mock")
    end

    test "is idempotent" do
      Registry.register(:mock, MockAdapter)
      assert :ok = Registry.unregister(:mock)
      assert :ok = Registry.unregister(:mock)
    end
  end

  describe "list/0" do
    test "returns empty map when no adapters registered" do
      assert %{} = Registry.list()
    end

    test "returns all registered adapters" do
      Registry.register(:mock, MockAdapter)
      adapters = Registry.list()

      assert %{mock: MockAdapter} = adapters
    end

    test "returns multiple adapters" do
      Registry.register(:mock1, MockAdapter)
      Registry.register(:mock2, MockAdapter)

      adapters = Registry.list()
      assert map_size(adapters) == 2
      assert adapters.mock1 == MockAdapter
      assert adapters.mock2 == MockAdapter
    end
  end

  describe "detect_language/1" do
    test "detects language from extension" do
      Registry.register(:mock, MockAdapter)
      assert {:ok, :mock} = Registry.detect_language("script.mock")
    end

    test "returns error for unknown extension" do
      assert {:error, :unknown_extension} = Registry.detect_language("unknown.xyz")
    end

    test "handles multiple extensions per language" do
      defmodule MultiExtAdapter do
        @behaviour Metastatic.Adapter

        @impl true
        def parse(_), do: {:ok, %{}}
        @impl true
        def to_meta(_), do: {:ok, {:literal, :integer, 1}, %{}}
        @impl true
        def from_meta(_, _), do: {:ok, %{}}
        @impl true
        def unparse(_), do: {:ok, "1"}
        @impl true
        def file_extensions, do: [".js", ".jsx"]
      end

      Registry.register(:javascript, MultiExtAdapter)
      assert {:ok, :javascript} = Registry.detect_language("app.js")
      assert {:ok, :javascript} = Registry.detect_language("component.jsx")
    end

    test "uses full filename with path" do
      Registry.register(:mock, MockAdapter)
      assert {:ok, :mock} = Registry.detect_language("/path/to/file.mock")
    end
  end

  describe "registered?/1" do
    test "returns true when language is registered" do
      Registry.register(:mock, MockAdapter)
      assert Registry.registered?(:mock)
    end

    test "returns false when language is not registered" do
      refute Registry.registered?(:unknown)
    end
  end

  describe "validate_all/0" do
    test "returns ok when all adapters are valid" do
      Registry.register(:mock, MockAdapter)
      assert {:ok, []} = Registry.validate_all()
    end

    test "returns ok when no adapters registered" do
      assert {:ok, []} = Registry.validate_all()
    end
  end

  describe "concurrent access" do
    test "handles concurrent registrations" do
      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            Registry.register(:"mock#{i}", MockAdapter)
          end)
        end

      results = Task.await_many(tasks)
      assert Enum.all?(results, &(&1 == :ok))

      adapters = Registry.list()
      assert map_size(adapters) == 10
    end

    test "handles concurrent reads and writes" do
      Registry.register(:mock, MockAdapter)

      tasks =
        for _ <- 1..20 do
          Task.async(fn ->
            case :rand.uniform(2) do
              1 -> Registry.get(:mock)
              2 -> Registry.list()
            end
          end)
        end

      results = Task.await_many(tasks)
      assert length(results) == 20
    end
  end

  describe "integration with real adapters" do
    test "extension conflict handling" do
      # Register first adapter with .js extension
      defmodule JSAdapter do
        @behaviour Metastatic.Adapter

        @impl true
        def parse(_), do: {:ok, %{}}
        @impl true
        def to_meta(_), do: {:ok, {:literal, :integer, 1}, %{}}
        @impl true
        def from_meta(_, _), do: {:ok, %{}}
        @impl true
        def unparse(_), do: {:ok, "1"}
        @impl true
        def file_extensions, do: [".js"]
      end

      Registry.register(:javascript, JSAdapter)
      assert {:ok, :javascript} = Registry.detect_language("app.js")

      # Register second adapter with same .js extension
      # (This overwrites the extension mapping)
      Registry.register(:typescript, JSAdapter)
      # TypeScript now claims .js extension
      assert {:ok, :typescript} = Registry.detect_language("app.js")
    end
  end
end
