defmodule Metastatic.Adapters.Elixir.FixtureRoundTripTest do
  @moduledoc """
  Reification-direction round-trip over the checked-in Elixir fixture corpus.

  `test/metastatic/adapters/elixir/round_trip_test.exs` covers hand-picked
  snippets. This test walks every `.ex` file under `test/fixtures/elixir/` and
  asserts the full pipeline:

      source -> M1 -> M2 -> M1' -> source'

  re-parses to a structurally identical AST. Comparing *parsed* ASTs (rather
  than source strings) makes the assertion insensitive to formatting while
  still catching the semantic drift that the 2026-11-18 audit found — a
  wildcard becoming an atom pattern, `nil` becoming `_`, a map update becoming
  `Map.merge/2`.

  Failures name the fixture file, so a regression points at the corpus entry
  that reproduces it.
  """

  use ExUnit.Case, async: true

  alias Metastatic.Adapters.Elixir, as: ElixirAdapter

  @fixture_root Path.expand("../../../fixtures/elixir", __DIR__)

  @fixtures @fixture_root
            |> Path.join("**/*.ex")
            |> Path.wildcard()
            |> Enum.sort()

  test "the fixture corpus is not empty" do
    assert @fixtures != [], "No .ex fixtures found under #{@fixture_root}"
  end

  for fixture <- @fixtures do
    @fixture fixture
    test "#{Path.relative_to(fixture, @fixture_root)} round-trips structurally" do
      source = File.read!(@fixture)

      assert {:ok, meta_ast, metadata} = parse_and_abstract(source),
             "abstraction failed for #{@fixture}"

      assert {:ok, reified} = ElixirAdapter.from_meta(meta_ast, metadata),
             "reification failed for #{@fixture}"

      assert {:ok, output} = ElixirAdapter.unparse(reified),
             "unparse failed for #{@fixture}"

      assert {:ok, original_ast} = Code.string_to_quoted(source)

      assert {:ok, output_ast} = Code.string_to_quoted(output),
             "round-tripped source does not parse for #{@fixture}:\n#{output}"

      assert strip_meta(original_ast) == strip_meta(output_ast), """
      Semantic drift for #{Path.relative_to(@fixture, @fixture_root)}

      Original AST:
        #{inspect(strip_meta(original_ast), pretty: true, limit: :infinity)}

      Round-tripped AST:
        #{inspect(strip_meta(output_ast), pretty: true, limit: :infinity)}

      Round-tripped source:
      #{output}
      """
    end
  end

  defp parse_and_abstract(source) do
    with {:ok, native_ast} <- ElixirAdapter.parse(source) do
      ElixirAdapter.to_meta(native_ast)
    end
  end

  # Drop every metadata keyword list so only structure remains.
  defp strip_meta(ast) do
    Macro.postwalk(ast, fn
      {form, meta, args} when is_list(meta) -> {form, [], args}
      other -> other
    end)
  end
end
