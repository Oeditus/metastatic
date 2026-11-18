defmodule Metastatic.Adapters.Rust.FixtureTest do
  @moduledoc """
  Fixture corpus for the Rust adapter (Phase 2).

  Every `.rs` file under `test/fixtures/rust/` is parsed, abstracted to MetaAST,
  reified back to a Rust AST, printed, and re-parsed. The re-parsed M1 must be
  structurally identical to the original — the same "compare parsed ASTs, not
  strings" criterion `ADAPTER_GUIDE.md` §9 sets, because `prettyplease`
  normalises formatting.

  The corpus is deliberately spread across the four MetaAST layers so that a
  regression in any one mapping row is caught by a named test.
  """
  use ExUnit.Case, async: true

  @moduletag :rust

  alias Metastatic.Adapters.Rust

  @fixtures_dir Path.join([__DIR__, "..", "..", "..", "fixtures", "rust"])

  setup_all do
    unless Rust.available?() do
      flunk("""
      The Rust bridge is not available, so the fixture corpus cannot run.

      Build it with:

          cd priv/parsers/rust && cargo build --release --locked

      or install `metastatic-rust-parser` on PATH.
      """)
    end

    :ok
  end

  # Every fixture, grouped by layer, so a failure names the layer that broke.
  @layers ~w(core extended structural native)

  for layer <- @layers do
    describe "#{layer} fixtures" do
      for path <- Path.wildcard(Path.join([@fixtures_dir, layer, "*.rs"])) do
        name = Path.basename(path, ".rs")

        test "#{name} round-trips through MetaAST" do
          path = unquote(path)
          source = File.read!(path)

          assert {:ok, native} = Rust.parse(source),
                 "#{Path.basename(path)} does not parse"

          assert {:ok, meta_ast, metadata} = Rust.to_meta(native)

          assert Metastatic.AST.conforms?(meta_ast),
                 "#{Path.basename(path)} produced a non-conforming MetaAST"

          assert {:ok, reified} = Rust.from_meta(meta_ast, metadata),
                 "#{Path.basename(path)} could not be reified"

          assert {:ok, printed} = Rust.unparse(reified),
                 "#{Path.basename(path)} could not be printed"

          assert {:ok, reparsed} = Rust.parse(printed),
                 "#{Path.basename(path)} printed unparseable Rust:\n#{printed}"

          assert strip_spans(native) == strip_spans(reparsed), """
          #{Path.basename(path)} changed structurally across the round-trip.

          --- printed ---
          #{printed}
          """
        end
      end
    end
  end

  describe "corpus coverage" do
    test "covers every layer" do
      for layer <- @layers do
        files = Path.wildcard(Path.join([@fixtures_dir, layer, "*.rs"]))
        assert files != [], "no fixtures for the #{layer} layer"
      end
    end

    test "has at least 30 fixtures" do
      count = @fixtures_dir |> Path.join("**/*.rs") |> Path.wildcard() |> length()
      assert count >= 30, "expected at least 30 fixtures, found #{count}"
    end
  end

  # Removes `span` from every node so two trees parsed from differently
  # formatted source compare equal.
  defp strip_spans(node) when is_map(node) do
    node
    |> Map.delete("span")
    |> Map.new(fn {key, value} -> {key, strip_spans(value)} end)
  end

  defp strip_spans(node) when is_list(node), do: Enum.map(node, &strip_spans/1)
  defp strip_spans(node), do: node
end
