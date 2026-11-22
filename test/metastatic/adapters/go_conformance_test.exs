defmodule Metastatic.Adapters.GoConformanceTest do
  use ExUnit.Case, async: true

  alias Metastatic.Adapters.Go.Subprocess

  if Subprocess.available?() do
    use Metastatic.Test.AdapterConformance,
      adapter: Metastatic.Adapters.Go,
      language: :go,
      sample: "1 + 2",
      sample_ast:
        {:binary_op, [category: :arithmetic, operator: :+],
         [{:literal, [subtype: :integer], 1}, {:literal, [subtype: :integer], 2}]}
  else
    @moduletag skip: "Go toolchain or prebuilt bridge required"
    test "Go bridge is optional", do: :ok
  end
end
