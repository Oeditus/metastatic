defmodule Metastatic.Adapters.ErlangConformanceTest do
  @moduledoc """
  Uniform conformance suite for the Erlang adapter (see
  `Metastatic.Test.AdapterConformance`).
  """
  use ExUnit.Case, async: true

  use Metastatic.Test.AdapterConformance,
    adapter: Metastatic.Adapters.Erlang,
    language: :erlang,
    sample: "1 + 2.",
    sample_ast:
      {:binary_op, [category: :arithmetic, operator: :+],
       [{:literal, [subtype: :integer], 1}, {:literal, [subtype: :integer], 2}]}
end
