defmodule Metastatic.Adapters.RustConformanceTest do
  @moduledoc """
  Uniform conformance suite for the Rust adapter (see
  `Metastatic.Test.AdapterConformance`).

  The suite parses, abstracts, reifies and unparses real source, so it needs the
  Rust bridge to be buildable. When no toolchain is available the whole module
  is excluded rather than failed — the same "honest matrix" discipline
  `cross_language_conformance_test.exs` uses.
  """
  use ExUnit.Case, async: true

  @moduletag :rust

  alias Metastatic.Adapters.Rust

  if Rust.available?() do
    use Metastatic.Test.AdapterConformance,
      adapter: Rust,
      language: :rust,
      sample: "1 + 2",
      sample_ast:
        {:binary_op, [category: :arithmetic, operator: :+],
         [{:literal, [subtype: :integer], 1}, {:literal, [subtype: :integer], 2}]}
  else
    @tag :skip
    test "Rust bridge unavailable — conformance suite skipped" do
      flunk("""
      The Rust bridge is not available, so the conformance suite cannot run.

      Build it with:

          cd priv/parsers/rust && cargo build --release --locked

      or install `metastatic-rust-parser` on PATH.
      """)
    end
  end
end
