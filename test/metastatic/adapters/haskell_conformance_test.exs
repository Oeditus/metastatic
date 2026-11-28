defmodule Metastatic.Adapters.HaskellConformanceTest do
  @moduledoc """
  Uniform conformance suite for the Haskell adapter (see
  `Metastatic.Test.AdapterConformance`).
  """
  use ExUnit.Case, async: true

  @moduletag :haskell

  alias Metastatic.Adapters.Haskell

  if Haskell.available?() do
    use Metastatic.Test.AdapterConformance,
      adapter: Haskell,
      language: :haskell,
      sample: "1 + 2",
      sample_ast:
        {:binary_op, [category: :arithmetic, operator: :+],
         [{:literal, [subtype: :integer], 1}, {:literal, [subtype: :integer], 2}]}
  else
    @moduletag skip: "Haskell parser binary or Stack toolchain required"
    test "Haskell bridge is optional", do: :ok
  end
end
