defmodule Metastatic.Adapters.AgdaConformanceTest do
  @moduledoc """
  Uniform conformance suite for the Agda adapter (see
  `Metastatic.Test.AdapterConformance`).
  """
  use ExUnit.Case, async: true

  @moduletag :agda

  alias Metastatic.Adapters.Agda

  if Agda.available?() do
    use Metastatic.Test.AdapterConformance,
      adapter: Agda,
      language: :agda,
      sample: "1 + 2",
      sample_ast:
        {:binary_op, [category: :arithmetic, operator: :+],
         [{:literal, [subtype: :integer], 1}, {:literal, [subtype: :integer], 2}]},
      invalid_sample: "module where = = ="
  else
    @moduletag skip: "Agda parser binary or GHC toolchain required"
    test "Agda bridge is optional", do: :ok
  end
end
