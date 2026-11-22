defmodule Metastatic.Adapters.JavaScript.SubprocessTest do
  use ExUnit.Case, async: true

  alias Metastatic.Adapters.JavaScript.Subprocess

  describe "parse/2" do
    test "successfully parses valid JavaScript code" do
      code = "const x = 42;"
      assert {:ok, ast} = Subprocess.parse(code)
      assert is_map(ast)
      assert ast["type"] in ["File", "Program"]
    end

    test "successfully parses valid TypeScript code under the :typescript dialect" do
      code = "function add(a: number, b: number): number { return a + b; }"
      assert {:ok, ast} = Subprocess.parse(code, :typescript)
      assert is_map(ast)
    end

    test "rejects TypeScript-only syntax under the :javascript dialect" do
      code = "function add(a: number, b: number): number { return a + b; }"
      assert {:error, reason} = Subprocess.parse(code, :javascript)
      assert is_binary(reason)
    end

    test "defaults to the :javascript dialect" do
      assert {:ok, _} = Subprocess.parse("const x = 42;")
      assert {:error, _} = Subprocess.parse("let x: number = 1;")
    end

    test "returns error for syntax error" do
      code = "const x ="
      assert {:error, reason} = Subprocess.parse(code)
      assert String.contains?(reason, "SyntaxError")
    end

    test "reports a partially recovered parse as an error" do
      # `errorRecovery` would otherwise return a meaningless partial tree.
      assert {:error, _} = Subprocess.parse("interface I { a: number }", :javascript)
    end
  end

  describe "unparse/1" do
    test "successfully unparses Babel AST JSON back to source" do
      code = "const x = 42;"
      {:ok, ast} = Subprocess.parse(code)
      assert {:ok, source} = Subprocess.unparse(ast)
      assert String.contains?(source, "const x = 42")
    end
  end
end
