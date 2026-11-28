defmodule Metastatic.Adapters.MarchConformanceTest do
  @moduledoc """
  Uniform conformance suite for the March adapter (see
  `Metastatic.Test.AdapterConformance`).
  """
  use ExUnit.Case, async: true

  @moduletag :march

  alias Metastatic.Adapters.March

  if March.available?() do
    use Metastatic.Test.AdapterConformance,
      adapter: March,
      language: :march,
      sample: "1 + 2",
      sample_ast:
        {:binary_op, [category: :arithmetic, operator: :+],
         [{:literal, [subtype: :integer], 1}, {:literal, [subtype: :integer], 2}]},
      invalid_sample: "fn ("
  else
    @moduletag skip: "March OCaml parser binary or dune required"
    test "March bridge is optional", do: :ok
  end
end
