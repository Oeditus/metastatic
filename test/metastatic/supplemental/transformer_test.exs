defmodule Metastatic.Supplemental.TransformerTest do
  use ExUnit.Case, async: false

  alias Metastatic.Supplemental
  alias Metastatic.Supplemental.Error.MissingSupplementalError
  alias Metastatic.Supplemental.Info
  alias Metastatic.Supplemental.Registry
  alias Metastatic.Supplemental.Transformer

  defmodule MockSupplemental do
    @behaviour Supplemental

    @impl true
    def info do
      %Info{
        name: :mock_transformer_test,
        language: :python,
        constructs: [:test_construct],
        requires: [],
        description: "Mock for transformer testing"
      }
    end

    @impl true
    def transform({:test_construct, value}, :python, _metadata) do
      {:ok, %{"_type" => "Transformed", "value" => value}}
    end

    def transform(_, _, _), do: :error
  end

  setup do
    Registry.clear()
    :ok
  end

  describe "transform/3" do
    test "transforms using registered supplemental" do
      Registry.register(MockSupplemental)

      assert {:ok, result} = Transformer.transform({:test_construct, "data"}, :python, %{})
      assert result == %{"_type" => "Transformed", "value" => "data"}
    end

    test "returns error when no supplemental registered" do
      assert :error = Transformer.transform({:test_construct, "data"}, :python, %{})
    end

    test "returns error for unsupported construct" do
      Registry.register(MockSupplemental)

      assert :error = Transformer.transform({:unsupported_construct, "data"}, :python, %{})
    end

    test "returns error for different language" do
      Registry.register(MockSupplemental)

      assert :error = Transformer.transform({:test_construct, "data"}, :javascript, %{})
    end
  end

  describe "transform!/3" do
    test "transforms using registered supplemental" do
      Registry.register(MockSupplemental)

      assert {:ok, result} = Transformer.transform!({:test_construct, "data"}, :python, %{})
      assert result == %{"_type" => "Transformed", "value" => "data"}
    end

    test "raises MissingSupplementalError when no supplemental registered" do
      assert_raise MissingSupplementalError, fn ->
        Transformer.transform!({:test_construct, "data"}, :python, %{})
      end
    end

    test "raises MissingSupplementalError for unsupported construct" do
      Registry.register(MockSupplemental)

      assert_raise MissingSupplementalError, fn ->
        Transformer.transform!({:unsupported_construct, "data"}, :python, %{})
      end
    end
  end

  describe "available?/2" do
    test "returns true when supplemental is registered" do
      Registry.register(MockSupplemental)

      assert Transformer.available?(:test_construct, :python)
    end

    test "returns false when no supplemental registered" do
      refute Transformer.available?(:test_construct, :python)
    end

    test "returns false for unsupported construct" do
      Registry.register(MockSupplemental)

      refute Transformer.available?(:unsupported_construct, :python)
    end
  end

  describe "supported_constructs/1" do
    test "lists all supported constructs for language" do
      Registry.register(MockSupplemental)

      constructs = Transformer.supported_constructs(:python)
      assert :test_construct in constructs
    end

    test "returns empty list when no supplementals registered" do
      assert Transformer.supported_constructs(:python) == []
    end
  end
end
