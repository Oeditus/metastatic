defmodule Metastatic.Adapters.Rust.BackendTest do
  @moduledoc """
  Phase 6 coverage: the optional lossless `ra_ap_syntax` backend.

  The default `prettyplease` backend normalises formatting; the `ra` backend
  round-trips source **byte for byte**, comments included. Both are exercised
  here, and the `ra` assertions skip cleanly when the bridge was built without
  `--features ra` (the bridge then falls back and says so in its metadata,
  which is itself worth asserting).
  """
  use ExUnit.Case, async: true

  alias Metastatic.Adapters.Rust

  # Deliberately idiosyncratic: `prettyplease` rewrites every line of it.
  @lossy_source "fn   main( ) {\n\n    // a comment\n    let x=1;   \n}\n"

  describe "prettyplease backend (default)" do
    test "normalises formatting" do
      assert {:ok, formatted} = Rust.format(@lossy_source)
      assert formatted == "fn main() {\n    let x = 1;\n}\n"
    end

    test "drops comments" do
      assert {:ok, formatted} = Rust.format(@lossy_source)
      refute formatted =~ "a comment"
    end

    test "is the default when no backend is given" do
      assert Rust.format(@lossy_source) == Rust.format(@lossy_source, backend: :prettyplease)
    end
  end

  describe "ra backend" do
    # The `ra` backend only exists when the bridge binary was built with
    # `--features ra`. CI builds the crate through `cargo run` with default
    # features, so these assertions must be conditional on what the *binary*
    # actually reports rather than on what the test wishes were true.
    #
    # `Rust.format/2` always succeeds: when `ra` is unavailable the bridge falls
    # back to `prettyplease` and says so via `lossless: false`.
    setup do
      [lossless: Rust.lossless_backend?()]
    end

    test "round-trips source byte for byte", %{lossless: lossless} do
      source = @lossy_source

      case Rust.format(source, backend: :ra) do
        {:ok, ^source} ->
          assert lossless, "byte-exact output implies the ra backend ran"

        {:ok, other} ->
          refute lossless,
                 "the bridge reported a lossless backend but normalised the source: " <>
                   inspect(other)

        {:error, reason} ->
          flunk("ra backend failed: #{reason}")
      end
    end

    test "preserves comments", %{lossless: lossless} do
      {:ok, printed} = Rust.format(@lossy_source, backend: :ra)

      if lossless do
        assert printed =~ "// a comment"
      else
        # Documented fallback: `prettyplease` drops comments.
        refute printed =~ "// a comment"
      end
    end

    test "preserves blank lines and trailing whitespace", %{lossless: lossless} do
      {:ok, printed} = Rust.format(@lossy_source, backend: :ra)

      if lossless do
        assert printed =~ "\n\n"
        assert printed =~ "let x=1;   \n"
      else
        assert printed == "fn main() {\n    let x = 1;\n}\n"
      end
    end

    test "still rejects unparseable source" do
      assert {:error, _reason} = Rust.format("fn f( {", backend: :ra)
    end

    test "unknown backends fall back to prettyplease" do
      assert Rust.format(@lossy_source, backend: :nonsense) == Rust.format(@lossy_source)
    end
  end

  describe "backend independence" do
    test "both backends produce source that re-parses to the same MetaAST" do
      {:ok, pretty} = Rust.format(@lossy_source)
      {:ok, lossless} = Rust.format(@lossy_source, backend: :ra)

      {:ok, native_a} = Rust.parse(pretty)
      {:ok, native_b} = Rust.parse(lossless)

      {:ok, meta_a, _} = Rust.to_meta(native_a)
      {:ok, meta_b, _} = Rust.to_meta(native_b)

      assert Metastatic.AST.canonicalize(meta_a) == Metastatic.AST.canonicalize(meta_b)
    end
  end
end
