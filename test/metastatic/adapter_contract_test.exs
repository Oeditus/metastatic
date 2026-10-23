defmodule Metastatic.AdapterContractTest do
  @moduledoc """
  Enumerates every adapter registered in `Metastatic.Languages` and asserts it
  satisfies the `Metastatic.Adapter` contract.

  This is the "quality bar" guard for R-5: adding a language to
  `Metastatic.Languages` without implementing every required callback fails
  here, so a new adapter cannot be merged below the bar.

  Per-adapter *behavioural* conformance (parse / to_meta / from_meta /
  round-trip on real source) lives in the `*ConformanceTest` modules, which use
  `Metastatic.Test.AdapterConformance`. This test covers the structural
  contract that applies to *all* adapters, including ones whose external
  toolchain is unavailable in a given environment.
  """

  use ExUnit.Case, async: true

  alias Metastatic.{Adapter, Languages}

  @required_callbacks [
    {:parse, 1},
    {:from_meta, 2},
    {:unparse, 1},
    {:file_extensions, 0}
  ]

  describe "every registered adapter satisfies the contract" do
    for language <- Languages.supported_languages() do
      test "#{language} adapter is valid" do
        language = unquote(language)

        assert {:ok, adapter} = Languages.get_adapter(language),
               "Languages.get_adapter/1 returned no adapter for #{inspect(language)}"

        assert Adapter.valid_adapter?(adapter),
               "#{inspect(adapter)} does not implement the Metastatic.Adapter behaviour"

        # `to_meta` may be arity 1 or 2 (see the optional callback).
        assert function_exported?(adapter, :to_meta, 1) or
                 function_exported?(adapter, :to_meta, 2),
               "#{inspect(adapter)} implements neither to_meta/1 nor to_meta/2"
      end
    end
  end

  describe "adapter metadata is well-formed" do
    for language <- Languages.supported_languages() do
      test "#{language} adapter declares dot-prefixed file extensions" do
        language = unquote(language)
        {:ok, adapter} = Languages.get_adapter(language)
        extensions = adapter.file_extensions()

        assert is_list(extensions)
        assert is_list(extensions)
        refute Enum.empty?(extensions)

        assert Enum.all?(extensions, fn ext ->
                 is_binary(ext) and String.starts_with?(ext, ".")
               end)

        for ext <- extensions do
          assert {:ok, ^language} = Languages.detect_language("sample" <> ext),
                 "extension #{ext} does not detect back to #{inspect(language)}"
        end
      end
    end
  end

  describe "required callback list is non-empty" do
    test "documents the required callbacks" do
      refute Enum.empty?(@required_callbacks)
    end
  end
end
