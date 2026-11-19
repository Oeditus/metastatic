defmodule Metastatic.Adapters.LfeFixturesTest do
  @moduledoc """
  Fixture-driven conformance for the LFE adapter.

  Every `.lfe` file under `test/fixtures/lfe/` must:

    * parse,
    * abstract to a structurally conforming MetaAST,
    * reify and unparse,
    * and re-parse to a **semantically equivalent** MetaAST.

  The fixtures mirror the Rust tree (`core/`, `extended/`, `structural/`,
  `native/`) so the constructs the adapter claims to support are the ones
  exercised. The whole module is skipped when LFE is not loadable — LFE is
  flagged `experimental` precisely because its toolchain is not part of OTP.
  """

  use ExUnit.Case, async: true

  @moduletag :lfe

  alias Metastatic.Adapters.Lfe

  if Lfe.available?() do
    alias Metastatic.AST

    @fixtures Path.expand("../../fixtures/lfe", __DIR__)

    for path <- Path.wildcard(Path.join(@fixtures, "**/*.lfe")) do
      name = Path.relative_to(path, @fixtures)

      test "#{name} parses, conforms and round-trips" do
        source = File.read!(unquote(path))

        assert {:ok, forms} = Lfe.parse(source), "failed to parse #{unquote(name)}"

        assert {:ok, meta, metadata} = Lfe.to_meta(forms)

        assert AST.conforms?(meta),
               "#{unquote(name)} produced a non-conforming MetaAST: #{inspect(meta, limit: 5)}"

        assert {:ok, reified} = Lfe.from_meta(meta, metadata)
        assert {:ok, out} = Lfe.unparse(reified)

        assert {:ok, forms2} = Lfe.parse(out),
               "#{unquote(name)} did not re-parse after a round-trip:\n#{out}"

        assert {:ok, meta2, _} = Lfe.to_meta(forms2)

        assert AST.canonicalize(meta2) == AST.canonicalize(meta),
               "#{unquote(name)} did not round-trip semantically:\n#{out}"
      end
    end
  else
    @tag :skip
    test "LFE toolchain unavailable — fixture suite skipped" do
      flunk("""
      The LFE toolchain is not available, so the fixture suite cannot run.

      Install LFE (`git clone https://github.com/lfe/lfe.git && cd lfe && make`)
      and put its `ebin` on the code path, or vendor it at
      `priv/parsers/lfe/ebin`.
      """)
    end
  end
end
