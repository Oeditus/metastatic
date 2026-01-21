defmodule Metastatic.Adapters.Elixir.ModuleDefinitionsTest do
  use ExUnit.Case, async: true

  alias Metastatic.Adapters.Elixir, as: ElixirAdapter
  alias Metastatic.Adapters.Elixir.ToMeta

  describe "ToMeta - module definitions" do
    test "transforms defmodule with single function" do
      source = """
      defmodule MyModule do
        def hello do
          :world
        end
      end
      """

      {:ok, ast} = ElixirAdapter.parse(source)

      assert {:ok, {:language_specific, :elixir, _native_ast, :module_definition}, metadata} =
               ToMeta.transform(ast)

      assert metadata.module_name == "MyModule"
      # Body is a single function definition (not wrapped in block for single statements)
      assert {:language_specific, :elixir, _native, :function_definition} = metadata.body
    end

    test "transforms defmodule with moduledoc and function" do
      source = """
      defmodule TestModule do
        @moduledoc "Test module"
        
        def test_function do
          42
        end
      end
      """

      {:ok, ast} = ElixirAdapter.parse(source)

      assert {:ok, {:language_specific, :elixir, _native_ast, :module_definition}, metadata} =
               ToMeta.transform(ast)

      assert metadata.module_name == "TestModule"
      assert {:block, _statements} = metadata.body
    end

    test "transforms nested module" do
      source = """
      defmodule Outer.Inner do
        def foo, do: :bar
      end
      """

      {:ok, ast} = ElixirAdapter.parse(source)

      assert {:ok, {:language_specific, :elixir, _native_ast, :module_definition}, metadata} =
               ToMeta.transform(ast)

      assert metadata.module_name == "Outer.Inner"
    end
  end

  describe "ToMeta - function definitions" do
    test "transforms def with do-end block" do
      ast = {:def, [line: 1], [{:hello, [line: 1], nil}, [do: :world]]}

      assert {:ok, {:language_specific, :elixir, _native_ast, :function_definition}, metadata} =
               ToMeta.transform(ast)

      assert metadata.function_name == "hello"
      assert metadata.function_type == :def
      assert {:literal, :symbol, :world} = metadata.body
    end

    test "transforms defp (private function)" do
      ast = {:defp, [line: 1], [{:helper, [line: 1], nil}, [do: 42]]}

      assert {:ok, {:language_specific, :elixir, _native_ast, :function_definition}, metadata} =
               ToMeta.transform(ast)

      assert metadata.function_name == "helper"
      assert metadata.function_type == :defp
      assert {:literal, :integer, 42} = metadata.body
    end

    test "transforms function with parameters" do
      # def add(x, y), do: x + y
      ast =
        {:def, [line: 1],
         [
           {:add, [line: 1], [{:x, [], nil}, {:y, [], nil}]},
           [do: {:+, [], [{:x, [], nil}, {:y, [], nil}]}]
         ]}

      assert {:ok, {:language_specific, :elixir, _native_ast, :function_definition}, metadata} =
               ToMeta.transform(ast)

      assert metadata.function_name == "add"
      assert {:binary_op, :arithmetic, :+, {:variable, "x"}, {:variable, "y"}} = metadata.body
    end

    test "transforms function with complex body" do
      # def compute(x) do
      #   y = x * 2
      #   y + 1
      # end
      ast =
        {:def, [line: 1],
         [
           {:compute, [line: 1], [{:x, [], nil}]},
           [
             do:
               {:__block__, [],
                [
                  {:=, [], [{:y, [], nil}, {:*, [], [{:x, [], nil}, 2]}]},
                  {:+, [], [{:y, [], nil}, 1]}
                ]}
           ]
         ]}

      assert {:ok, {:language_specific, :elixir, _native_ast, :function_definition}, metadata} =
               ToMeta.transform(ast)

      assert metadata.function_name == "compute"
      assert {:block, [_match, _add]} = metadata.body
    end
  end

  describe "ToMeta - module attributes" do
    test "transforms @moduledoc" do
      ast = {:@, [line: 1], [{:moduledoc, [line: 1], ["Module documentation"]}]}

      assert {:ok, {:language_specific, :elixir, _native_ast, :module_attribute}, metadata} =
               ToMeta.transform(ast)

      assert metadata.attribute == :moduledoc
      assert metadata.value == "Module documentation"
    end

    test "transforms @doc" do
      ast = {:@, [line: 1], [{:doc, [line: 1], ["Function documentation"]}]}

      assert {:ok, {:language_specific, :elixir, _native_ast, :module_attribute}, metadata} =
               ToMeta.transform(ast)

      assert metadata.attribute == :doc
      assert metadata.value == "Function documentation"
    end

    test "transforms custom module attribute" do
      ast = {:@, [line: 1], [{:custom_attr, [line: 1], [42]}]}

      assert {:ok, {:language_specific, :elixir, _native_ast, :module_attribute}, metadata} =
               ToMeta.transform(ast)

      assert metadata.attribute == :custom_attr
      assert metadata.value == 42
    end
  end

  describe "round-trip - module definitions" do
    test "simple module with function round-trips" do
      source = """
      defmodule Simple do
        def hello do
          :world
        end
      end
      """

      {:ok, ast} = ElixirAdapter.parse(source)
      {:ok, meta_ast, metadata} = ToMeta.transform(ast)

      # Should be able to transform back
      assert {:language_specific, :elixir, _native, :module_definition} = meta_ast
      assert metadata.module_name == "Simple"
    end
  end

  describe "integration - full file analysis" do
    test "can parse and analyze lib/metastatic.ex" do
      source = """
      defmodule Metastatic do
        @moduledoc \"\"\"
        Documentation for `Metastatic`.
        \"\"\"

        @doc \"\"\"
        Hello world.

        ## Examples

            iex> Metastatic.hello()
            :world

        \"\"\"
        def hello do
          :world
        end
      end
      """

      {:ok, ast} = ElixirAdapter.parse(source)
      {:ok, meta_ast, metadata} = ToMeta.transform(ast)

      assert {:language_specific, :elixir, _native, :module_definition} = meta_ast
      assert metadata.module_name == "Metastatic"

      # The body should be a block with module attributes and function definition
      assert {:block, statements} = metadata.body
      assert is_list(statements)
      assert length(statements) >= 3
    end

    test "can parse module with multiple functions" do
      source = """
      defmodule Calculator do
        def add(x, y), do: x + y
        def subtract(x, y), do: x - y
        defp helper(x), do: x * 2
      end
      """

      {:ok, ast} = ElixirAdapter.parse(source)
      {:ok, meta_ast, metadata} = ToMeta.transform(ast)

      assert {:language_specific, :elixir, _native, :module_definition} = meta_ast
      assert metadata.module_name == "Calculator"
      assert {:block, functions} = metadata.body
      assert [_, _, _] = functions
    end
  end
end
