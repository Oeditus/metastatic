defmodule Metastatic.Adapters.RubyConformanceTest do
  @moduledoc """
  Uniform conformance suite for the Ruby adapter (see
  `Metastatic.Test.AdapterConformance`).
  """
  use ExUnit.Case, async: true

  use Metastatic.Test.AdapterConformance,
    adapter: Metastatic.Adapters.Ruby,
    language: :ruby,
    sample: "1 + 2",
    sample_ast:
      {:binary_op, [category: :arithmetic, operator: :+],
       [{:literal, [subtype: :integer], 1}, {:literal, [subtype: :integer], 2}]}
end
