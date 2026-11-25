defmodule Metastatic.Adapters.GleamConformanceTest do
  @moduledoc """
  Uniform conformance suite for the Gleam adapter (see
  `Metastatic.Test.AdapterConformance`).

  The suite parses, abstracts, reifies and unparses real source, so it needs
  the `metastatic-gleam-parser` bridge to be buildable. When no Rust toolchain
  is available the whole module is skipped rather than failed — the bridge is
  compiled on demand from `priv/parsers/gleam/`, and a host application that
  never deploys it should not fail its test suite because of that.
  """
  use ExUnit.Case, async: true

  @moduletag :gleam

  alias Metastatic.Adapters.Gleam

  if Gleam.available?() do
    use Metastatic.Test.AdapterConformance,
      adapter: Gleam,
      language: :gleam,
      # A snippet the adapter can parse...
      sample: "pub fn add(a: Int, b: Int) -> Int {\n  a + b\n}\n",
      # ...and a MetaAST it can reify back to source.
      sample_ast:
        {:binary_op, [category: :arithmetic, operator: :+],
         [{:literal, [subtype: :integer], 1}, {:literal, [subtype: :integer], 2}]},
      # `this is not valid @@#$%` happens to *parse* as Gleam? No — but the
      # reliable failure is an unbalanced delimiter, which no Gleam grammar
      # accepts.
      invalid_sample: "pub fn broken( {\n"
  else
    @tag :skip
    test "Gleam bridge unavailable — conformance suite skipped" do
      flunk("""
      The metastatic-gleam-parser bridge is not available, so the conformance
      suite cannot run.

      The bridge is built from `priv/parsers/gleam/` on first use. To build it:

          cd priv/parsers/gleam && cargo build --release

      or install Rust/Cargo so the adapter can build it into the user cache,
      or put a prebuilt `metastatic-gleam-parser` on PATH.
      """)
    end
  end
end
