defmodule Metastatic.Adapters.PythonConformanceTest do
  @moduledoc """
  Uniform conformance suite for the Python adapter (see
  `Metastatic.Test.AdapterConformance`).
  """
  use ExUnit.Case, async: true

  use Metastatic.Test.AdapterConformance,
    adapter: Metastatic.Adapters.Python,
    language: :python,
    sample: "1 + 2",
    sample_ast:
      {:binary_op, [category: :arithmetic, operator: :+],
       [{:literal, [subtype: :integer], 1}, {:literal, [subtype: :integer], 2}]}
end
