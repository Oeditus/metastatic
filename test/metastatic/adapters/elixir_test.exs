defmodule Metastatic.Adapters.ElixirTest do
  use ExUnit.Case, async: true

  alias Metastatic.Adapters.Elixir, as: ElixirAdapter
  alias Metastatic.Adapters.Elixir.{FromMeta, ToMeta}

  doctest Metastatic.Adapters.Elixir

  describe "parse/1" do
    test "parses valid Elixir source code" do
      assert {:ok, {:+, _meta, [{:x, _, _}, 5]}} = ElixirAdapter.parse("x + 5")
    end

    test "parses integer literals" do
      assert {:ok, 42} = ElixirAdapter.parse("42")
    end

    test "parses string literals" do
      assert {:ok, "hello"} = ElixirAdapter.parse("\"hello\"")
    end

    test "returns error for invalid syntax" do
      # Use actually invalid syntax
      assert {:error, error_msg} = ElixirAdapter.parse("x +")
      assert error_msg =~ "Syntax error"
    end

    test "parses function calls" do
      assert {:ok, {:foo, _meta, [1, 2, 3]}} = ElixirAdapter.parse("foo(1, 2, 3)")
    end

    test "parses if expressions" do
      assert {:ok, {:if, _, _}} = ElixirAdapter.parse("if true, do: 1, else: 2")
    end
  end

  describe "unparse/1" do
    test "converts AST back to source code" do
      ast = {:+, [], [{:x, [], nil}, 5]}
      assert {:ok, "x + 5"} = ElixirAdapter.unparse(ast)
    end

    test "handles complex expressions" do
      ast = {:if, [], [true, [do: 1, else: 2]]}
      assert {:ok, source} = ElixirAdapter.unparse(ast)
      assert source =~ "if"
    end
  end

  describe "file_extensions/0" do
    test "returns Elixir file extensions" do
      assert [".ex", ".exs"] = ElixirAdapter.file_extensions()
    end
  end

  describe "ToMeta - literals" do
    test "transforms integer literals" do
      assert {:ok, {:literal, :integer, 42}, %{}} = ToMeta.transform(42)
    end

    test "transforms float literals" do
      assert {:ok, {:literal, :float, 3.14}, %{}} = ToMeta.transform(3.14)
    end

    test "transforms string literals" do
      assert {:ok, {:literal, :string, "hello"}, %{}} = ToMeta.transform("hello")
    end

    test "transforms boolean literals" do
      assert {:ok, {:literal, :boolean, true}, %{}} = ToMeta.transform(true)
      assert {:ok, {:literal, :boolean, false}, %{}} = ToMeta.transform(false)
    end

    test "transforms nil" do
      assert {:ok, {:literal, :null, nil}, %{}} = ToMeta.transform(nil)
    end

    test "transforms atoms as symbols" do
      assert {:ok, {:literal, :symbol, :atom}, %{}} = ToMeta.transform(:atom)
    end
  end

  describe "ToMeta - variables" do
    test "transforms variable references" do
      ast = {:x, [], nil}
      assert {:ok, {:variable, "x"}, metadata} = ToMeta.transform(ast)
      assert %{context: nil} = metadata
    end

    test "preserves variable context" do
      ast = {:my_var, [line: 10], MyModule}
      assert {:ok, {:variable, "my_var"}, metadata} = ToMeta.transform(ast)
      assert %{context: MyModule, elixir_meta: [line: 10]} = metadata
    end
  end

  describe "ToMeta - binary operators" do
    test "transforms arithmetic addition" do
      ast = {:+, [], [{:x, [], nil}, 5]}
      assert {:ok, {:binary_op, :arithmetic, :+, left, right}, %{}} = ToMeta.transform(ast)
      assert {:variable, "x"} = left
      assert {:literal, :integer, 5} = right
    end

    test "transforms arithmetic subtraction" do
      ast = {:-, [], [10, {:y, [], nil}]}
      assert {:ok, {:binary_op, :arithmetic, :-, left, right}, %{}} = ToMeta.transform(ast)
      assert {:literal, :integer, 10} = left
      assert {:variable, "y"} = right
    end

    test "transforms multiplication and division" do
      mult_ast = {:*, [], [2, 3]}
      assert {:ok, {:binary_op, :arithmetic, :*, _, _}, %{}} = ToMeta.transform(mult_ast)

      div_ast = {:/, [], [10, 2]}
      assert {:ok, {:binary_op, :arithmetic, :/, _, _}, %{}} = ToMeta.transform(div_ast)
    end

    test "transforms comparison operators" do
      eq_ast = {:==, [], [1, 2]}
      assert {:ok, {:binary_op, :comparison, :==, _, _}, %{}} = ToMeta.transform(eq_ast)

      lt_ast = {:<, [], [1, 2]}
      assert {:ok, {:binary_op, :comparison, :<, _, _}, %{}} = ToMeta.transform(lt_ast)

      gte_ast = {:>=, [], [5, 3]}
      assert {:ok, {:binary_op, :comparison, :>=, _, _}, %{}} = ToMeta.transform(gte_ast)
    end

    test "transforms boolean operators" do
      and_ast = {:and, [], [true, false]}
      assert {:ok, {:binary_op, :boolean, :and, _, _}, %{}} = ToMeta.transform(and_ast)

      or_ast = {:or, [], [true, false]}
      assert {:ok, {:binary_op, :boolean, :or, _, _}, %{}} = ToMeta.transform(or_ast)
    end

    test "transforms string concatenation" do
      ast = {:<>, [], ["hello", " world"]}
      assert {:ok, {:binary_op, :arithmetic, :<>, _, _}, %{}} = ToMeta.transform(ast)
    end
  end

  describe "ToMeta - unary operators" do
    test "transforms logical not" do
      ast = {:not, [], [true]}
      assert {:ok, {:unary_op, :boolean, :not, operand}, %{}} = ToMeta.transform(ast)
      assert {:literal, :boolean, true} = operand
    end

    test "transforms negation" do
      ast = {:-, [], [42]}
      assert {:ok, {:unary_op, :arithmetic, :-, operand}, %{}} = ToMeta.transform(ast)
      assert {:literal, :integer, 42} = operand
    end

    test "transforms positive sign" do
      ast = {:+, [], [42]}
      assert {:ok, {:unary_op, :arithmetic, :+, operand}, %{}} = ToMeta.transform(ast)
      assert {:literal, :integer, 42} = operand
    end
  end

  describe "ToMeta - function calls" do
    test "transforms local function calls" do
      ast = {:foo, [], [1, 2]}
      assert {:ok, {:function_call, "foo", args}, %{}} = ToMeta.transform(ast)
      assert [_, _] = args
    end

    test "transforms function calls with no arguments" do
      ast = {:bar, [], []}
      assert {:ok, {:function_call, "bar", []}, %{}} = ToMeta.transform(ast)
    end

    test "transforms remote function calls" do
      # Use a different module to test remote calls (not Enum, which has special handling)
      ast = {{:., [], [{:__aliases__, [], [:String]}, :upcase]}, [], ["hello"]}

      assert {:ok, {:function_call, "String.upcase", _args}, %{call_type: :remote}} =
               ToMeta.transform(ast)
    end

    test "transforms Enum.map to collection_op" do
      # Enum.map gets special Extended layer handling
      ast =
        {{:., [], [{:__aliases__, [], [:Enum]}, :map]}, [],
         [[1, 2, 3], {:fn, [], [{:->, [], [[{:x, [], nil}], {:x, [], nil}]}]}]}

      assert {:ok, {:collection_op, :map, fun, collection}, %{}} = ToMeta.transform(ast)
      assert {:lambda, _, _, _} = fun
      assert {:list, _} = collection
    end

    test "transforms Enum.filter to collection_op" do
      ast =
        {{:., [], [{:__aliases__, [], [:Enum]}, :filter]}, [],
         [[1, 2, 3], {:fn, [], [{:->, [], [[{:x, [], nil}], true]}]}]}

      assert {:ok, {:collection_op, :filter, fun, _collection}, %{}} = ToMeta.transform(ast)
      assert {:lambda, _, _, _} = fun
    end

    test "transforms Enum.reduce to collection_op" do
      ast =
        {{:., [], [{:__aliases__, [], [:Enum]}, :reduce]}, [],
         [
           [1, 2, 3],
           0,
           {:fn, [],
            [
              {:->, [],
               [[{:acc, [], nil}, {:x, [], nil}], {:+, [], [{:acc, [], nil}, {:x, [], nil}]}]}
            ]}
         ]}

      assert {:ok, {:collection_op, :reduce, fun, _collection, initial}, %{}} =
               ToMeta.transform(ast)

      assert {:lambda, _, _, _} = fun
      assert {:literal, :integer, 0} = initial
    end
  end

  describe "ToMeta - conditionals" do
    test "transforms if with then and else" do
      ast = {:if, [], [true, [do: 1, else: 2]]}

      assert {:ok, {:conditional, condition, then_branch, else_branch}, %{}} =
               ToMeta.transform(ast)

      assert {:literal, :boolean, true} = condition
      assert {:literal, :integer, 1} = then_branch
      assert {:literal, :integer, 2} = else_branch
    end

    test "transforms if without else" do
      ast = {:if, [], [{:x, [], nil}, [do: 42]]}
      assert {:ok, {:conditional, _condition, _then_branch, nil}, %{}} = ToMeta.transform(ast)
    end

    test "transforms unless" do
      ast = {:unless, [], [false, [do: 1]]}

      assert {:ok, {:conditional, condition, _then, _else}, %{original_form: :unless}} =
               ToMeta.transform(ast)

      # unless negates the condition
      assert {:unary_op, :boolean, :not, _} = condition
    end

    test "transforms case expression" do
      ast = {:case, [], [{:x, [], nil}, [do: [{:->, [], [[1], :one]}, {:->, [], [[2], :two]}]]]}
      assert {:ok, {:pattern_match, _scrutinee, arms}, %{}} = ToMeta.transform(ast)
      assert [_, _] = arms
    end
  end

  describe "ToMeta - blocks" do
    test "transforms multi-expression blocks" do
      ast = {:__block__, [], [1, 2, 3]}
      assert {:ok, {:block, expressions}, %{}} = ToMeta.transform(ast)
      assert [_, _, _] = expressions
    end
  end

  describe "ToMeta - inline_match (pattern matching)" do
    test "transforms simple match: x = 5" do
      ast = {:=, [], [{:x, [], nil}, 5]}

      assert {:ok, {:inline_match, pattern, value}, metadata} = ToMeta.transform(ast)
      assert {:variable, "x"} = pattern
      assert {:literal, :integer, 5} = value
      assert is_map(metadata)
    end

    test "transforms tuple destructuring: {x, y} = {1, 2}" do
      # {x, y} = {1, 2}
      left = {{:x, [], nil}, {:y, [], nil}}
      right = {1, 2}
      ast = {:=, [], [left, right]}

      assert {:ok, {:inline_match, pattern, value}, _metadata} = ToMeta.transform(ast)
      assert {:tuple, [var_x, var_y]} = pattern
      assert {:variable, "x"} = var_x
      assert {:variable, "y"} = var_y
      assert {:tuple, [lit1, lit2]} = value
      assert {:literal, :integer, 1} = lit1
      assert {:literal, :integer, 2} = lit2
    end

    test "transforms nested pattern: {:ok, value} = result" do
      # {:ok, value} = result
      pattern = {:ok, {:value, [], nil}}
      value = {:result, [], nil}
      ast = {:=, [], [pattern, value]}

      assert {:ok, {:inline_match, pattern_meta, value_meta}, _metadata} = ToMeta.transform(ast)
      assert {:tuple, [ok_atom, var_value]} = pattern_meta
      assert {:literal, :symbol, :ok} = ok_atom
      assert {:variable, "value"} = var_value
      assert {:variable, "result"} = value_meta
    end

    test "transforms pin operator: ^x = 5" do
      # ^x = 5
      pin_ast = {:^, [], [{:x, [], nil}]}
      ast = {:=, [], [pin_ast, 5]}

      assert {:ok, {:inline_match, pattern, value}, _metadata} = ToMeta.transform(ast)
      assert {:pin, {:variable, "x"}} = pattern
      assert {:literal, :integer, 5} = value
    end
  end

  describe "ToMeta - anonymous functions" do
    test "transforms simple anonymous function" do
      ast = {:fn, [], [{:->, [], [[{:x, [], nil}], {:+, [], [{:x, [], nil}, 1]}]}]}
      assert {:ok, {:lambda, params, captures, _body}, %{}} = ToMeta.transform(ast)
      assert [{:param, "x", nil, nil}] = params
      assert [] = captures
    end
  end

  describe "ToMeta - comprehensions (Extended layer)" do
    test "transforms simple for comprehension to collection_op" do
      # for x <- [1, 2, 3], do: x * 2
      ast =
        {:for, [], [{:<-, [], [{:x, [], nil}, [1, 2, 3]]}, [do: {:*, [], [{:x, [], nil}, 2]}]]}

      assert {:ok, {:collection_op, :map, lambda, collection}, %{original_form: :comprehension}} =
               ToMeta.transform(ast)

      assert {:lambda, [{:param, "x", nil, nil}], _captures, _body} = lambda
      assert {:list, _} = collection
    end
  end

  describe "ToMeta - Native layer constructs" do
    test "transforms pipe operator as language_specific" do
      # x |> f()
      ast = {:|>, [], [{:x, [], nil}, {:f, [], []}]}

      assert {:ok, {:language_specific, :elixir, _, :pipe}, metadata} = ToMeta.transform(ast)
      assert %{left: {:variable, "x"}, right: {:function_call, "f", []}} = metadata
    end

    test "transforms with expression as language_specific" do
      # with {:ok, x} <- result, do: x
      pattern = {:ok, {:x, [], nil}}
      expr = {:result, [], nil}
      body = {:x, [], nil}
      ast = {:with, [], [{:<-, [], [pattern, expr]}, [do: body]]}

      assert {:ok, {:language_specific, :elixir, _, :with}, %{}} = ToMeta.transform(ast)
    end
  end

  describe "FromMeta - literals" do
    test "transforms integer literals back" do
      assert {:ok, 42} = FromMeta.transform({:literal, :integer, 42}, %{})
    end

    test "transforms float literals back" do
      assert {:ok, 3.14} = FromMeta.transform({:literal, :float, 3.14}, %{})
    end

    test "transforms string literals back" do
      assert {:ok, "hello"} = FromMeta.transform({:literal, :string, "hello"}, %{})
    end

    test "transforms boolean literals back" do
      assert {:ok, true} = FromMeta.transform({:literal, :boolean, true}, %{})
      assert {:ok, false} = FromMeta.transform({:literal, :boolean, false}, %{})
    end

    test "transforms nil back" do
      assert {:ok, nil} = FromMeta.transform({:literal, :null, nil}, %{})
    end

    test "transforms symbols back" do
      assert {:ok, :atom} = FromMeta.transform({:literal, :symbol, :atom}, %{})
    end
  end

  describe "FromMeta - variables" do
    test "transforms variables back with default context" do
      assert {:ok, {:x, [], nil}} = FromMeta.transform({:variable, "x"}, %{})
    end

    test "restores variable context from metadata" do
      metadata = %{context: MyModule, elixir_meta: [line: 10]}

      assert {:ok, {:my_var, [line: 10], MyModule}} =
               FromMeta.transform({:variable, "my_var"}, metadata)
    end
  end

  describe "FromMeta - binary operators" do
    test "transforms arithmetic operators back" do
      meta_ast = {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}}
      assert {:ok, {:+, [], [{:x, [], nil}, 5]}} = FromMeta.transform(meta_ast, %{})
    end

    test "transforms comparison operators back" do
      meta_ast = {:binary_op, :comparison, :==, {:literal, :integer, 1}, {:literal, :integer, 2}}
      assert {:ok, {:==, [], [1, 2]}} = FromMeta.transform(meta_ast, %{})
    end

    test "transforms boolean operators back" do
      meta_ast =
        {:binary_op, :boolean, :and, {:literal, :boolean, true}, {:literal, :boolean, false}}

      assert {:ok, {:and, [], [true, false]}} = FromMeta.transform(meta_ast, %{})
    end
  end

  describe "FromMeta - unary operators" do
    test "transforms logical not back" do
      meta_ast = {:unary_op, :boolean, :not, {:literal, :boolean, true}}
      assert {:ok, {:not, [], [true]}} = FromMeta.transform(meta_ast, %{})
    end

    test "transforms negation back" do
      meta_ast = {:unary_op, :arithmetic, :-, {:literal, :integer, 42}}
      assert {:ok, {:-, [], [42]}} = FromMeta.transform(meta_ast, %{})
    end
  end

  describe "FromMeta - function calls" do
    test "transforms local function calls back" do
      meta_ast = {:function_call, "foo", [{:literal, :integer, 1}, {:literal, :integer, 2}]}
      assert {:ok, {:foo, [], [1, 2]}} = FromMeta.transform(meta_ast, %{})
    end

    test "transforms remote function calls back" do
      meta_ast =
        {:function_call, "Enum.map", [{:list, []}, {:lambda, [], {:literal, :integer, 1}}]}

      assert {:ok, {{:., [], [{:__aliases__, [], [:Enum]}, :map]}, [], _args}} =
               FromMeta.transform(meta_ast, %{})
    end
  end

  describe "FromMeta - conditionals" do
    test "transforms if back" do
      meta_ast =
        {:conditional, {:literal, :boolean, true}, {:literal, :integer, 1},
         {:literal, :integer, 2}}

      assert {:ok, {:if, [], [true, [do: 1, else: 2]]}} = FromMeta.transform(meta_ast, %{})
    end

    test "transforms if without else back" do
      meta_ast = {:conditional, {:literal, :boolean, true}, {:literal, :integer, 1}, nil}
      assert {:ok, {:if, [], [true, [do: 1]]}} = FromMeta.transform(meta_ast, %{})
    end
  end

  describe "FromMeta - blocks" do
    test "transforms single-expression block to single expression" do
      meta_ast = {:block, [{:literal, :integer, 1}]}
      assert {:ok, 1} = FromMeta.transform(meta_ast, %{})
    end

    test "transforms multi-expression block" do
      meta_ast =
        {:block, [{:literal, :integer, 1}, {:literal, :integer, 2}, {:literal, :integer, 3}]}

      assert {:ok, {:__block__, [], [1, 2, 3]}} = FromMeta.transform(meta_ast, %{})
    end

    test "transforms empty block to nil" do
      meta_ast = {:block, []}
      assert {:ok, nil} = FromMeta.transform(meta_ast, %{})
    end
  end

  describe "FromMeta - inline_match (pattern matching)" do
    test "transforms simple match back: x = 5" do
      meta_ast = {:inline_match, {:variable, "x"}, {:literal, :integer, 5}}
      assert {:ok, {:=, [], [{:x, [], nil}, 5]}} = FromMeta.transform(meta_ast, %{})
    end

    test "transforms tuple destructuring back: {x, y} = {1, 2}" do
      meta_ast =
        {:inline_match, {:tuple, [{:variable, "x"}, {:variable, "y"}]},
         {:tuple, [{:literal, :integer, 1}, {:literal, :integer, 2}]}}

      assert {:ok, {:=, [], [pattern, value]}} = FromMeta.transform(meta_ast, %{})
      assert {{:x, [], nil}, {:y, [], nil}} = pattern
      assert {1, 2} = value
    end

    test "transforms nested pattern back: {:ok, value} = result" do
      meta_ast =
        {:inline_match, {:tuple, [{:literal, :symbol, :ok}, {:variable, "value"}]},
         {:variable, "result"}}

      assert {:ok, {:=, [], [pattern, {:result, [], nil}]}} = FromMeta.transform(meta_ast, %{})
      assert {:ok, {:value, [], nil}} = pattern
    end

    test "transforms pin operator back: ^x = 5" do
      meta_ast = {:inline_match, {:pin, {:variable, "x"}}, {:literal, :integer, 5}}
      assert {:ok, {:=, [], [{:^, [], [{:x, [], nil}]}, 5]}} = FromMeta.transform(meta_ast, %{})
    end

    test "preserves metadata in round-trip" do
      meta_ast = {:inline_match, {:variable, "x"}, {:literal, :integer, 5}}
      metadata = %{elixir_meta: [line: 10]}

      assert {:ok, {:=, [line: 10], _}} = FromMeta.transform(meta_ast, metadata)
    end
  end

  describe "FromMeta - anonymous functions" do
    test "transforms lambda back" do
      meta_ast = {:lambda, [{:param, "x", nil, nil}], {:variable, "x"}}

      assert {:ok, {:fn, [], [{:->, [], [[{:x, [], nil}], {:x, [], nil}]}]}} =
               FromMeta.transform(meta_ast, %{})
    end
  end

  describe "round-trip transformations" do
    test "integer round-trips" do
      assert_round_trip("42", 42)
    end

    test "float round-trips" do
      assert_round_trip("3.14", 3.14)
    end

    test "string round-trips" do
      assert_round_trip("\"hello\"", "hello")
    end

    test "arithmetic expression round-trips" do
      source = "x + 5"
      {:ok, ast} = ElixirAdapter.parse(source)
      {:ok, meta_ast, metadata} = ToMeta.transform(ast)
      {:ok, ast2} = FromMeta.transform(meta_ast, metadata)
      {:ok, source2} = ElixirAdapter.unparse(ast2)
      assert source == source2
    end

    test "function call round-trips" do
      source = "foo(1, 2, 3)"
      {:ok, ast} = ElixirAdapter.parse(source)
      {:ok, meta_ast, metadata} = ToMeta.transform(ast)
      {:ok, ast2} = FromMeta.transform(meta_ast, metadata)
      {:ok, source2} = ElixirAdapter.unparse(ast2)
      assert source == source2
    end

    test "if expression round-trips semantically" do
      # Note: formatting may differ slightly, so we check semantic equivalence
      source = "if true, do: 1, else: 2"
      {:ok, ast} = ElixirAdapter.parse(source)
      {:ok, meta_ast, metadata} = ToMeta.transform(ast)
      {:ok, ast2} = FromMeta.transform(meta_ast, metadata)
      {:ok, source2} = ElixirAdapter.unparse(ast2)

      # Both should parse to semantically equivalent ASTs
      {:ok, original_ast} = ElixirAdapter.parse(source)
      {:ok, round_trip_ast} = ElixirAdapter.parse(source2)

      {:ok, original_meta, _} = ToMeta.transform(original_ast)
      {:ok, round_trip_meta, _} = ToMeta.transform(round_trip_ast)

      assert original_meta == round_trip_meta
    end

    test "complex expression round-trips" do
      source = "x + y * 2"
      {:ok, ast} = ElixirAdapter.parse(source)
      {:ok, meta_ast, metadata} = ToMeta.transform(ast)
      {:ok, ast2} = FromMeta.transform(meta_ast, metadata)
      {:ok, source2} = ElixirAdapter.unparse(ast2)
      assert source == source2
    end
  end

  describe "integration with Adapter helpers" do
    test "round_trip/2 works end-to-end" do
      source = "x + 5"
      assert {:ok, result} = Metastatic.Adapter.round_trip(ElixirAdapter, source)
      assert result == source
    end

    test "abstract/3 creates a Document" do
      source = "42"
      assert {:ok, doc} = Metastatic.Adapter.abstract(ElixirAdapter, source, :elixir)
      assert %Metastatic.Document{} = doc
      assert doc.language == :elixir
      assert doc.ast == {:literal, :integer, 42}
      assert doc.original_source == source
    end

    test "reify/2 converts Document to source" do
      doc = %Metastatic.Document{
        ast: {:literal, :integer, 42},
        language: :elixir,
        metadata: %{},
        original_source: "42"
      }

      assert {:ok, "42"} = Metastatic.Adapter.reify(ElixirAdapter, doc)
    end
  end

  # Helper function

  defp assert_round_trip(source, expected_ast) do
    {:ok, ast} = ElixirAdapter.parse(source)
    assert ast == expected_ast

    {:ok, meta_ast, metadata} = ToMeta.transform(ast)
    {:ok, ast2} = FromMeta.transform(meta_ast, metadata)
    assert ast == ast2
  end
end
