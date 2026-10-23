defmodule Metastatic.Adapters.TypeScriptConformanceTest do
  @moduledoc """
  Uniform conformance suite for the TypeScript adapter (see
  `Metastatic.Test.AdapterConformance`).
  """
  use ExUnit.Case, async: true

  use Metastatic.Test.AdapterConformance,
    adapter: Metastatic.Adapters.TypeScript,
    language: :typescript,
    sample: "1 + 2;",
    sample_ast:
      {:binary_op, [category: :arithmetic, operator: :+],
       [{:literal, [subtype: :integer], 1}, {:literal, [subtype: :integer], 2}]}
end
