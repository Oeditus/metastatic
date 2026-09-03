defmodule Metastatic.Adapters.MarchTest do
  use ExUnit.Case, async: true

  alias Metastatic.Adapters.March
  alias Metastatic.Adapters.March.{FromMeta, Subprocess, ToMeta}
  alias Metastatic.AST
  alias Metastatic.Languages

  describe "Language Registry & Detection" do
    test "march adapter is registered in Languages module" do
      assert {:ok, March} == Languages.get_adapter(:march)
      assert :march in Languages.supported_languages()
    end

    test "detects .march file extension" do
      assert {:ok, :march} == Languages.detect_language("counter.march")
      assert {:ok, :march} == Languages.detect_language("app.mch")
    end
  end

  describe "March AST Abstraction (ToMeta)" do
    test "transforms basic functions to MetaAST" do
      code = """
      fn add(x: Int, y: Int) : Int do
        let sum = x + y
        sum
      end
      """

      assert {:ok, ast} = Subprocess.parse(code)
      assert {:ok, meta_ast, _meta} = ToMeta.transform(ast)
      assert AST.conforms?(meta_ast)
    end

    test "transforms actors and on-handlers to MetaAST" do
      code = """
      actor Counter do
        state { count: Int }
        init { count: 0 }
        on Inc(n: Int) do
          let next = count + n
          next
        end
      end
      """

      assert {:ok, ast} = Subprocess.parse(code)
      assert {:ok, meta_ast, _meta} = ToMeta.transform(ast)

      assert {:container, meta, handlers} = meta_ast
      assert Keyword.get(meta, :subtype) == :actor
      assert Keyword.get(meta, :name) == "Counter"

      assert [handler] = handlers
      assert {:function_def, h_meta, _body} = handler
      assert Keyword.get(h_meta, :callback_for) == "on_message"
      assert Keyword.get(h_meta, :name) == "on:Inc"
    end

    test "transforms multi-handler actor with record updates" do
      code = """
      actor StateHolder do
        state { count: Int, label: String }
        init { count: 0, label: "counter" }
        on Increment(n: Int) do
          { state with count: count + n }
        end
        on Reset() do
          { state with count: 0 }
        end
      end
      """

      assert {:ok, ast} = Subprocess.parse(code)
      assert {:ok, meta_ast, _meta} = ToMeta.transform(ast)
      assert AST.conforms?(meta_ast)
    end

    test "transforms pattern matching on constructor patterns" do
      code = """
      fn area(s: Shape) : Float do
        match s do
          Circle(r) -> 3.14 * r * r
          Rect(w, h) -> w * h
          Point -> 0.0
        end
      end
      """

      assert {:ok, ast} = Subprocess.parse(code)
      assert {:ok, meta_ast, _meta} = ToMeta.transform(ast)
      assert AST.conforms?(meta_ast)
    end

    test "transforms algebraic data types (ADTs)" do
      code = """
      type Shape = Circle(Float) | Rect(Float, Float) | Point
      """

      assert {:ok, ast} = Subprocess.parse(code)
      assert {:ok, meta_ast, _meta} = ToMeta.transform(ast)
      assert AST.conforms?(meta_ast)
    end

    test "transforms needs capabilities, use imports, pfn, and ++ operators" do
      code = """
      mod App do
        needs IO.Console
        use Std.String

        pfn private_helper(name: String) : String do
          "Hello " ++ name
        end

        fn main do
          Console.println(private_helper("March"))
        end
      end
      """

      assert {:ok, ast} = Subprocess.parse(code)
      assert {:ok, meta_ast, _meta} = ToMeta.transform(ast)
      assert AST.conforms?(meta_ast)

      assert {:container, _meta, children} = meta_ast

      assert Enum.any?(children, fn
               {:import, meta, []} -> Keyword.get(meta, :import_type) == :needs
               _ -> false
             end)
    end
  end

  describe "March AST Reification & Round-Trip" do
    test "reifies MetaAST back to March M1 AST" do
      meta_ast =
        {:block, [scope: :module],
         [
           {:function_def, [name: "add", params: [{:param, [], "x"}, {:param, [], "y"}]],
            [
              {:binary_op, [category: :arithmetic, operator: :+],
               [{:variable, [scope: :local], "x"}, {:variable, [scope: :local], "y"}]}
            ]}
         ]}

      assert {:ok, m1_ast} = FromMeta.transform(meta_ast)
      assert is_map(m1_ast)
      assert m1_ast["_type"] == "Program"
    end

    test "round-trip function source transformation" do
      source = """
      fn add(x: Int, y: Int) do
        let res = x + y
        res
      end
      """

      assert {:ok, ast} = March.parse(source)
      assert {:ok, meta_ast, metadata} = March.to_meta(ast)
      assert {:ok, ast2} = March.from_meta(meta_ast, metadata)
      assert {:ok, generated_source} = March.unparse(ast2)
      assert is_binary(generated_source)
      assert generated_source =~ "fn add"
    end

    test "round-trip actor source transformation" do
      source = """
      actor Counter do
        on Inc(n: Int) do
          let next = count + n
          next
        end
      end
      """

      assert {:ok, ast} = March.parse(source)
      assert {:ok, meta_ast, metadata} = March.to_meta(ast)
      assert {:ok, ast2} = March.from_meta(meta_ast, metadata)
      assert {:ok, generated_source} = March.unparse(ast2)
      assert is_binary(generated_source)
      assert generated_source =~ "actor Counter"
      assert generated_source =~ "on Inc"
    end

    test "round-trip capability & import module source transformation" do
      source = """
      mod App do
        needs IO.Console
        use Std.String

        fn main do
          Console.println("Hello March")
        end
      end
      """

      assert {:ok, ast} = March.parse(source)
      assert {:ok, meta_ast, metadata} = March.to_meta(ast)
      assert {:ok, ast2} = March.from_meta(meta_ast, metadata)
      assert {:ok, generated_source} = March.unparse(ast2)
      assert is_binary(generated_source)
      assert generated_source =~ "mod App"
      assert generated_source =~ "needs IO.Console"
      assert generated_source =~ "use Std.String"
    end
  end
end
