defmodule Metastatic.Adapter.RegistryTest do
  use ExUnit.Case, async: false

  alias Metastatic.Adapter.Registry

  # Mock adapter for testing
  defmodule MockAdapter do
    @behaviour Metastatic.Adapter

    @impl true
    def parse(_source), do: {:ok, %{}}

    @impl true
    def to_meta(_native_ast), do: {:ok, {:literal, [subtype: :integer], 42}, %{}}

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
    # Registry is already started by the application.
    # Clear any existing registrations before each test.
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

    test "re-registering the same adapter is idempotent" do
      assert :ok = Registry.register(:mock, MockAdapter)
      assert :ok = Registry.register(:mock, MockAdapter)
      assert {:ok, MockAdapter} = Registry.get(:mock)
    end

    test "refuses to silently replace a registered adapter" do
      assert :ok = Registry.register(:mock, MockAdapter)

      assert {:error, {:already_registered, :mock, MockAdapter}} =
               Registry.register(:mock, Metastatic.Adapters.Elixir)
    end

    test "does not own file extensions (that is Languages' job)" do
      # The registry stores adapters only; extension -> language detection is
      # derived at compile time in `Metastatic.Languages`, so there is exactly
      # one source of truth for it.
      assert :ok = Registry.register(:mock, MockAdapter)
      assert {:error, :unknown_extension} = Registry.detect_language("test.mock")
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

    test "unregistering does not affect Languages' extension map" do
      Registry.register(:mock, MockAdapter)
      Registry.unregister(:mock)

      # `.ex` is owned by `Metastatic.Languages`, not by this registry.
      assert {:ok, :elixir} = Registry.detect_language("app.ex")
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
    test "delegates to Languages for known extensions" do
      assert {:ok, :elixir} = Registry.detect_language("script.ex")
      assert {:ok, :python} = Registry.detect_language("script.py")
    end

    test "returns error for unknown extension" do
      assert {:error, :unknown_extension} = Registry.detect_language("unknown.xyz")
    end

    test "handles multiple extensions per language" do
      assert {:ok, :javascript} = Registry.detect_language("app.js")
      assert {:ok, :javascript} = Registry.detect_language("component.jsx")
    end

    test "uses full filename with path" do
      assert {:ok, :elixir} = Registry.detect_language("/path/to/file.ex")
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
end
