defmodule Metastatic.Adapters.CureConformanceTest do
  @moduledoc """
  Uniform conformance suite for the Cure adapter (see
  `Metastatic.Test.AdapterConformance`).
  """
  use ExUnit.Case, async: true

  @moduletag :cure

  alias Metastatic.Adapters.Cure

  if Cure.available?() do
    use Metastatic.Test.AdapterConformance,
      adapter: Cure,
      language: :cure,
      sample: "1 + 2",
      sample_ast:
        {:binary_op, [category: :arithmetic, operator: :+],
         [{:literal, [subtype: :integer], 1}, {:literal, [subtype: :integer], 2}]},
      invalid_sample: "fn ("
  else
    @moduletag skip: "Cure compiler or CLI required"
    test "Cure adapter is optional", do: :ok
  end
end
