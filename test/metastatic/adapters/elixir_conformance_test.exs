defmodule Metastatic.Adapters.ElixirConformanceTest do
  @moduledoc """
  Uniform conformance suite for the Elixir adapter (see
  `Metastatic.Test.AdapterConformance`).
  """
  use ExUnit.Case, async: true

  use Metastatic.Test.AdapterConformance,
    adapter: Metastatic.Adapters.Elixir,
    language: :elixir,
    sample: "1 + 2",
    sample_ast:
      {:binary_op, [category: :arithmetic, operator: :+],
       [{:literal, [subtype: :integer], 1}, {:literal, [subtype: :integer], 2}]}
end
