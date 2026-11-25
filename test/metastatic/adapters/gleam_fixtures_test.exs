defmodule Metastatic.Adapters.GleamFixturesTest do
  @moduledoc """
  Fixture-driven conformance for the Gleam adapter.

  Every `.gleam` file under `test/fixtures/gleam/` must:

    * parse,
    * abstract to a structurally conforming MetaAST,
    * reify and unparse,
    * and re-parse to a **semantically equivalent** MetaAST.

  The fixtures mirror the Rust and Go trees (`core/`, `extended/`,
  `structural/`, `native/`), so the constructs the adapter claims to support
  are the ones exercised. The whole module is skipped when the bridge is not
  buildable — the bridge is compiled on demand from `priv/parsers/gleam/`, and
  a host application that never deploys it should not fail because of that.
  """

  use ExUnit.Case, async: true

  @moduletag :gleam

  alias Metastatic.Adapters.Gleam

  if Gleam.available?() do
    alias Metastatic.AST

    @fixtures Path.expand("../../fixtures/gleam", __DIR__)

    for path <- Path.wildcard(Path.join(@fixtures, "**/*.gleam")) do
      name = Path.relative_to(path, @fixtures)

      test "#{name} parses, conforms and round-trips" do
        source = File.read!(unquote(path))

        assert {:ok, forms} = Gleam.parse(source), "failed to parse #{unquote(name)}"

        assert {:ok, meta, metadata} = Gleam.to_meta(forms)

        assert :ok = AST.validate(meta),
               "#{unquote(name)} produced a non-conforming MetaAST: #{inspect(meta, limit: 5)}"

        assert {:ok, reified} = Gleam.from_meta(meta, metadata)
        assert {:ok, out} = Gleam.unparse(reified)

        assert {:ok, forms2} = Gleam.parse(out),
               "#{unquote(name)} did not re-parse after a round-trip:\n#{out}"

        assert {:ok, meta2, _} = Gleam.to_meta(forms2)

        assert AST.canonicalize(meta2) == AST.canonicalize(meta),
               "#{unquote(name)} did not round-trip semantically:\n#{out}"
      end
    end

    test "the fixture tree covers every MetaAST layer" do
      # A fixture suite that only exercises literals would pass while the
      # adapter is broken for everything else. This asserts the corpus actually
      # reaches each layer, so a future "simplification" that drops a fixture
      # fails here rather than silently reducing coverage.
      layers =
        @fixtures
        |> Path.join("**/*.gleam")
        |> Path.wildcard()
        |> Enum.flat_map(fn path ->
          {:ok, forms} = Gleam.parse(File.read!(path))
          {:ok, meta, _} = Gleam.to_meta(forms)
          collect_layers(meta, MapSet.new())
        end)
        |> MapSet.new()

      assert :core in layers
      assert :extended in layers
      assert :structural in layers
    end

    # Walks a MetaAST collecting the layer of every node.
    defp collect_layers({type, _meta, children}, acc) when is_list(children) do
      acc = MapSet.put(acc, AST.layer(type))
      Enum.reduce(children, acc, &collect_layers/2)
    end

    defp collect_layers({type, _meta, _value}, acc), do: MapSet.put(acc, AST.layer(type))
    defp collect_layers(_other, acc), do: acc
  else
    @tag :skip
    test "Gleam bridge unavailable — fixture suite skipped" do
      flunk("""
      The metastatic-gleam-parser bridge is not available, so the fixture suite
      cannot run.

      Build it with `cd priv/parsers/gleam && cargo build --release`, or
      install Rust/Cargo so the adapter can build it on demand.
      """)
    end
  end
end
