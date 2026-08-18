defmodule Metastatic.Adapters.TypeScriptTest do
  use ExUnit.Case, async: true

  @moduletag :typescript

  alias Metastatic.Adapters.TypeScript

  describe "TypeScript parsing and transformation" do
    test "parses TypeScript code with type annotations" do
      code = "function greet(name: string, count: number): string { return name; }"
      assert {:ok, ast} = TypeScript.parse(code)
      assert is_map(ast)
    end

    test "transforms TypeScript interface declaration to MetaAST" do
      code = "interface User { id: number; name: string; }"
      assert {:ok, ast} = TypeScript.parse(code)
      assert {:ok, meta_ast, _metadata} = TypeScript.to_meta(ast)
      assert match?({:language_specific, _, _}, meta_ast) or match?({:block, _, _}, meta_ast)
    end

    test "round-trips TypeScript fixture" do
      source = File.read!("test/fixtures/typescript/interfaces.ts")
      assert {:ok, ast1} = TypeScript.parse(source)
      assert {:ok, meta_ast, metadata} = TypeScript.to_meta(ast1)
      assert {:ok, ast2} = TypeScript.from_meta(meta_ast, metadata)
      assert {:ok, generated_source} = TypeScript.unparse(ast2)

      assert generated_source =~ "getUser"
    end
  end
end
