defmodule Metastatic.SupplementalTest do
  use ExUnit.Case, async: true

  alias Metastatic.Supplemental

  alias Metastatic.Supplemental.Error.{
    ConflictError,
    IncompatibleSupplementalError,
    MissingSupplementalError,
    UnsupportedConstructError
  }

  alias Metastatic.Supplemental.Info

  # Mock supplemental module for testing
  defmodule MockSupplemental do
    @behaviour Supplemental

    @impl true
    def info do
      %Info{
        name: :mock_test,
        language: :python,
        constructs: [:test_construct, :another_construct],
        requires: ["test-lib >= 1.0"],
        description: "Mock supplemental for testing"
      }
    end

    @impl true
    def transform({:test_construct, value}, :python, _metadata) do
      {:ok, %{"_type" => "TestNode", "value" => value}}
    end

    def transform(_, _, _), do: :error
  end

  describe "Supplemental.Info" do
    test "creates valid info struct" do
      info = %Info{
        name: :test,
        language: :python,
        constructs: [:actor_call],
        requires: ["pykka >= 3.0"],
        description: "Test supplemental"
      }

      assert info.name == :test
      assert info.language == :python
      assert info.constructs == [:actor_call]
      assert info.requires == ["pykka >= 3.0"]
      assert info.description == "Test supplemental"
    end

    test "valid?/1 returns true for valid info" do
      info = %Info{
        name: :test,
        language: :python,
        constructs: [:actor_call],
        description: "Test"
      }

      assert Info.valid?(info)
    end

    test "valid?/1 returns false for nil name" do
      info = %Info{
        name: nil,
        language: :python,
        constructs: [:actor_call],
        description: "Test"
      }

      refute Info.valid?(info)
    end

    test "valid?/1 returns false for empty constructs" do
      info = %Info{
        name: :test,
        language: :python,
        constructs: [],
        description: "Test"
      }

      refute Info.valid?(info)
    end

    test "valid?/1 returns false for empty description" do
      info = %Info{
        name: :test,
        language: :python,
        constructs: [:actor_call],
        description: ""
      }

      refute Info.valid?(info)
    end

    test "valid?/1 returns false for non-Info struct" do
      refute Info.valid?(%{})
      refute Info.valid?(nil)
    end
  end

  describe "Supplemental helper functions" do
    test "supported_constructs/1 returns list of constructs" do
      assert Supplemental.supported_constructs(MockSupplemental) == [
               :test_construct,
               :another_construct
             ]
    end

    test "language/1 returns target language" do
      assert Supplemental.language(MockSupplemental) == :python
    end

    test "dependencies/1 returns required dependencies" do
      assert Supplemental.dependencies(MockSupplemental) == ["test-lib >= 1.0"]
    end
  end

  describe "MockSupplemental implementation" do
    test "info/0 returns valid Info struct" do
      info = MockSupplemental.info()

      assert %Info{} = info
      assert info.name == :mock_test
      assert Info.valid?(info)
    end

    test "transform/3 handles supported construct" do
      assert {:ok, result} = MockSupplemental.transform({:test_construct, "value"}, :python, %{})
      assert result == %{"_type" => "TestNode", "value" => "value"}
    end

    test "transform/3 returns error for unsupported construct" do
      assert :error = MockSupplemental.transform({:unsupported, "value"}, :python, %{})
    end

    test "transform/3 returns error for wrong language" do
      assert :error = MockSupplemental.transform({:test_construct, "value"}, :javascript, %{})
    end
  end

  describe "Error types" do
    test "MissingSupplementalError" do
      error = MissingSupplementalError.exception(construct: :actor_call, language: :python)

      assert error.construct == :actor_call
      assert error.language == :python
      assert error.message =~ "No supplemental registered"
      assert error.message =~ ":actor_call"
      assert error.message =~ ":python"
    end

    test "IncompatibleSupplementalError with available version" do
      error =
        IncompatibleSupplementalError.exception(
          supplemental: :pykka,
          required: "pykka >= 3.0",
          available: "2.5"
        )

      assert error.supplemental == :pykka
      assert error.required == "pykka >= 3.0"
      assert error.available == "2.5"
      assert error.message =~ "requires pykka >= 3.0"
      assert error.message =~ "found 2.5"
    end

    test "IncompatibleSupplementalError without available version" do
      error =
        IncompatibleSupplementalError.exception(
          supplemental: :pykka,
          required: "pykka >= 3.0"
        )

      assert error.available == "not installed"
      assert error.message =~ "not installed"
    end

    test "UnsupportedConstructError" do
      error = UnsupportedConstructError.exception(construct: :actor_call, language: :ruby)

      assert error.construct == :actor_call
      assert error.language == :ruby
      assert error.message =~ "not supported"
      assert error.message =~ ":actor_call"
      assert error.message =~ ":ruby"
    end

    test "ConflictError" do
      error =
        ConflictError.exception(
          construct: :actor_call,
          language: :python,
          modules: [Module1, Module2]
        )

      assert error.construct == :actor_call
      assert error.language == :python
      assert error.modules == [Module1, Module2]
      assert error.message =~ "Multiple supplementals"
      assert error.message =~ "[Module1, Module2]"
    end
  end
end
