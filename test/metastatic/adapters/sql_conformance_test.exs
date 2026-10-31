defmodule Metastatic.Adapters.SQLConformanceTest do
  @moduledoc """
  Uniform conformance suite for the SQL adapter (see
  `Metastatic.Test.AdapterConformance`).
  """
  use ExUnit.Case, async: true

  use Metastatic.Test.AdapterConformance,
    adapter: Metastatic.Adapters.SQL,
    language: :sql,
    sample: "1 + 2",
    sample_ast:
      {:binary_op, [category: :arithmetic, operator: :+],
       [{:literal, [subtype: :integer], 1}, {:literal, [subtype: :integer], 2}]}
end
