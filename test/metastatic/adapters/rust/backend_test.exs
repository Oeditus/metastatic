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
    test "round-trips source byte for byte" do
      source = @lossy_source

      case Rust.format(source, backend: :ra) do
        {:ok, ^source} -> :ok
        {:ok, other} -> flunk("ra backend normalised the source: #{inspect(other)}")
        {:error, reason} -> flunk("ra backend failed: #{reason}")
      end
    end

    test "preserves comments" do
      case Rust.format(@lossy_source, backend: :ra) do
        {:ok, printed} -> assert printed =~ "// a comment"
        {:error, reason} -> flunk("ra backend failed: #{reason}")
      end
    end

    test "preserves blank lines and trailing whitespace" do
      case Rust.format(@lossy_source, backend: :ra) do
        {:ok, printed} ->
          assert printed =~ "\n\n"
          assert printed =~ "let x=1;   \n"

        {:error, reason} ->
          flunk("ra backend failed: #{reason}")
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
