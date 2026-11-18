defmodule Metastatic.Adapters.RustTest do
  @moduledoc """
  Unit tests for the Rust adapter's bridge layer (Phase 1).

  Covers what the uniform conformance suite cannot: the toolchain-resolution and
  failure paths. Every one of those must return `{:error, reason}` — the adapter
  must never raise and never hang, whatever the environment looks like.
  """
  use ExUnit.Case, async: true

  @moduletag :rust

  alias Metastatic.Adapters.Rust
  alias Metastatic.Adapters.Rust.Subprocess

  describe "parse/1" do
    test "parses a function definition" do
      assert {:ok, ast} = Rust.parse("fn add(x: i32, y: i32) -> i32 {\n    x + y\n}\n")

      assert ast["kind"] == "File"
      assert [function] = ast["children"]
      assert function["kind"] == "Function"
      assert function["name"] == "add"
    end

    test "parses a bare expression" do
      # `syn::parse_file` only accepts items, so the bridge retries as an
      # expression. Every other adapter accepts `1 + 2`, and the conformance
      # suite depends on it.
      assert {:ok, ast} = Rust.parse("1 + 2")
      assert ast["kind"] == "Binary"
      assert ast["name"] == "+"
    end

    test "reports a syntax error with a line number" do
      assert {:error, message} = Rust.parse("fn broken( {")
      assert message =~ "ParseError"
      assert message =~ "line 1"
    end

    test "rejects junk" do
      assert {:error, _reason} = Rust.parse("this is not valid @@#$%")
    end
  end

  describe "unparse/1" do
    test "round-trips a function definition" do
      source = "fn add(x: i32, y: i32) -> i32 {\n    x + y\n}\n"

      assert {:ok, ast} = Rust.parse(source)
      assert {:ok, printed} = Rust.unparse(ast)

      assert printed =~ "fn add(x: i32, y: i32) -> i32"
      assert printed =~ "x + y"
    end

    test "round-trips a bare expression" do
      assert {:ok, ast} = Rust.parse("1 + 2")
      assert {:ok, printed} = Rust.unparse(ast)
      assert String.trim(printed) == "1 + 2"
    end

    test "returns an error for a non-JSON AST" do
      assert {:error, message} = Rust.unparse(:not_json)
      assert is_binary(message)
    end
  end

  describe "format/1" do
    test "normalises formatting" do
      assert {:ok, formatted} = Rust.format("fn  main( ){let x=1;}")
      assert formatted =~ "fn main()"
    end

    test "reports a syntax error rather than raising" do
      assert {:error, _reason} = Rust.format("fn broken( {")
    end
  end

  describe "selftest/0" do
    test "reports a healthy bridge" do
      assert {:ok, report} = Rust.selftest()
      assert report["status"] == "ok"
      assert report["spans_populated"] == true
      assert report["ast_round_trip"] == true
      assert report["print_round_trip"] == true
    end
  end

  describe "toolchain resolution" do
    test "available?/0 reports the bridge is usable" do
      assert Rust.available?()
    end

    test "parser_executable/0 resolves a real path" do
      # In CI the crate is built on demand by `cargo run`, so the resolved
      # executable is `cargo` itself rather than a prebuilt binary. The
      # contract is "a path to something runnable", not "a prebuilt binary".
      assert path = Subprocess.parser_executable()
      assert File.exists?(path)
    end
  end

  describe "missing toolchain" do
    setup do
      # Hide both the prebuilt binary and cargo for the duration of the test.
      original = Application.get_env(:metastatic, :priv_dirs)

      Application.put_env(:metastatic, :priv_dirs, ["/nonexistent/metastatic/priv"])

      on_exit(fn ->
        if original do
          Application.put_env(:metastatic, :priv_dirs, original)
        else
          Application.delete_env(:metastatic, :priv_dirs)
        end
      end)

      :ok
    end

    test "parse/1 returns a clear error instead of raising" do
      case Rust.parse("fn main() {}") do
        {:ok, _ast} ->
          # A `metastatic-rust-parser` on PATH still satisfies the adapter; that
          # is a valid environment, so there is nothing to assert.
          :ok

        {:error, message} ->
          assert is_binary(message)
          assert message =~ "unavailable" or message =~ "missing"
      end
    end
  end

  describe "language registration" do
    test "is discoverable and maps .rs" do
      assert Metastatic.Languages.supported?(:rust)
      assert {:ok, Rust} = Metastatic.Languages.get_adapter(:rust)
      assert {:ok, :rust} = Metastatic.Languages.detect_language("lib.rs")
      assert ".rs" in Rust.file_extensions()
    end

    test "Builder.from_source/2 works end to end" do
      assert {:ok, doc} = Metastatic.Builder.from_source("fn main() {}", :rust)
      assert doc.language == :rust
      assert {:ok, source} = Metastatic.Builder.to_source(doc)
      assert source =~ "fn main()"
    end
  end
end
