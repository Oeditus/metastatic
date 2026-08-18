defmodule Metastatic.Adapters.JavaScript.SubprocessTest do
  use ExUnit.Case, async: true

  alias Metastatic.Adapters.JavaScript.Subprocess

  describe "parse/1" do
    test "successfully parses valid JavaScript code" do
      code = "const x = 42;"
      assert {:ok, ast} = Subprocess.parse(code)
      assert is_map(ast)
      assert ast["type"] in ["File", "Program"]
    end

    test "successfully parses valid TypeScript code" do
      code = "function add(a: number, b: number): number { return a + b; }"
      assert {:ok, ast} = Subprocess.parse(code)
      assert is_map(ast)
    end

    test "returns error for syntax error" do
      code = "const x ="
      assert {:error, reason} = Subprocess.parse(code)
      assert String.contains?(reason, "SyntaxError")
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
