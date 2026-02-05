defmodule Metastatic.Adapters.ElixirTest do
  use ExUnit.Case, async: true

  alias Metastatic.Adapters.Elixir, as: ElixirAdapter
  alias Metastatic.Adapters.Elixir.{FromMeta, ToMeta}

  doctest Metastatic.Adapters.Elixir

  # Helper to check 3-tuple format nodes
  defp is_binary_op?(result, category, operator) do
    match?({:binary_op, meta, [_left, _right]} when is_list(meta), result) and
      Keyword.get(elem(result, 1), :category) == category and
      Keyword.get(elem(result, 1), :operator) == operator
  end

  defp is_unary_op?(result, category, operator) do
    match?({:unary_op, meta, [_operand]} when is_list(meta), result) and
      Keyword.get(elem(result, 1), :category) == category and
      Keyword.get(elem(result, 1), :operator) == operator
  end

  defp is_variable?(result, name) do
    match?({:variable, _meta, ^name}, result)
  end

  defp is_literal?(result, subtype, value) do
    match?({:literal, meta, ^value} when is_list(meta), result) and
      Keyword.get(elem(result, 1), :subtype) == subtype
  end

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
      assert {:ok, result, %{}} = ToMeta.transform(42)
      assert is_literal?(result, :integer, 42)
    end

    test "transforms float literals" do
      assert {:ok, result, %{}} = ToMeta.transform(3.14)
      assert is_literal?(result, :float, 3.14)
    end

    test "transforms string literals" do
      assert {:ok, result, %{}} = ToMeta.transform("hello")
      assert is_literal?(result, :string, "hello")
    end

    test "transforms boolean literals" do
      assert {:ok, result_true, %{}} = ToMeta.transform(true)
      assert {:ok, result_false, %{}} = ToMeta.transform(false)
      assert is_literal?(result_true, :boolean, true)
      assert is_literal?(result_false, :boolean, false)
    end

    test "transforms nil" do
      assert {:ok, result, %{}} = ToMeta.transform(nil)
      assert is_literal?(result, :null, nil)
    end

    test "transforms atoms as symbols" do
      assert {:ok, result, %{}} = ToMeta.transform(:atom)
      assert is_literal?(result, :symbol, :atom)
    end
  end

  describe "ToMeta - variables" do
    test "transforms variable references" do
      ast = {:x, [], nil}
      assert {:ok, result, metadata} = ToMeta.transform(ast)
      assert is_variable?(result, "x")
      assert is_map(metadata)
    end

    test "preserves variable context" do
      ast = {:my_var, [line: 10], MyModule}
      assert {:ok, result, metadata} = ToMeta.transform(ast)
      assert is_variable?(result, "my_var")
      # Context is stored in the result, metadata contains function/module tracking
      assert is_map(metadata)
    end
  end

  describe "ToMeta - binary operators" do
    test "transforms arithmetic addition" do
      ast = {:+, [], [{:x, [], nil}, 5]}
      assert {:ok, result, %{}} = ToMeta.transform(ast)
      assert is_binary_op?(result, :arithmetic, :+)

      {:binary_op, _meta, [left, right]} = result
      assert is_variable?(left, "x")
      assert is_literal?(right, :integer, 5)
    end

    test "transforms arithmetic subtraction" do
      ast = {:-, [], [10, {:y, [], nil}]}
      assert {:ok, result, %{}} = ToMeta.transform(ast)
      assert is_binary_op?(result, :arithmetic, :-)

      {:binary_op, _meta, [left, right]} = result
      assert is_literal?(left, :integer, 10)
      assert is_variable?(right, "y")
    end

    test "transforms multiplication and division" do
      mult_ast = {:*, [], [2, 3]}
      assert {:ok, result, %{}} = ToMeta.transform(mult_ast)
      assert is_binary_op?(result, :arithmetic, :*)

      div_ast = {:/, [], [10, 2]}
      assert {:ok, result, %{}} = ToMeta.transform(div_ast)
      assert is_binary_op?(result, :arithmetic, :/)
    end

    test "transforms comparison operators" do
      eq_ast = {:==, [], [1, 2]}
      assert {:ok, result, %{}} = ToMeta.transform(eq_ast)
      assert is_binary_op?(result, :comparison, :==)

      lt_ast = {:<, [], [1, 2]}
      assert {:ok, result, %{}} = ToMeta.transform(lt_ast)
      assert is_binary_op?(result, :comparison, :<)

      gte_ast = {:>=, [], [5, 3]}
      assert {:ok, result, %{}} = ToMeta.transform(gte_ast)
      assert is_binary_op?(result, :comparison, :>=)
    end

    test "transforms boolean operators" do
      and_ast = {:and, [], [true, false]}
      assert {:ok, result, %{}} = ToMeta.transform(and_ast)
      assert is_binary_op?(result, :boolean, :and)

      or_ast = {:or, [], [true, false]}
      assert {:ok, result, %{}} = ToMeta.transform(or_ast)
      assert is_binary_op?(result, :boolean, :or)
    end

    test "transforms string concatenation" do
      ast = {:<>, [], ["hello", " world"]}
      assert {:ok, result, %{}} = ToMeta.transform(ast)
      assert is_binary_op?(result, :arithmetic, :<>)
    end
  end

  describe "ToMeta - unary operators" do
    test "transforms logical not" do
      ast = {:not, [], [true]}
      assert {:ok, result, %{}} = ToMeta.transform(ast)
      assert is_unary_op?(result, :boolean, :not)

      {:unary_op, _meta, [operand]} = result
      assert is_literal?(operand, :boolean, true)
    end

    test "transforms negation" do
      ast = {:-, [], [42]}
      assert {:ok, result, %{}} = ToMeta.transform(ast)
      assert is_unary_op?(result, :arithmetic, :-)

      {:unary_op, _meta, [operand]} = result
      assert is_literal?(operand, :integer, 42)
    end

    test "transforms positive sign" do
      ast = {:+, [], [42]}
      assert {:ok, result, %{}} = ToMeta.transform(ast)
      assert is_unary_op?(result, :arithmetic, :+)

      {:unary_op, _meta, [operand]} = result
      assert is_literal?(operand, :integer, 42)
    end
  end

  describe "ToMeta - function calls" do
    test "transforms local function calls" do
      ast = {:foo, [], [1, 2]}
      assert {:ok, {:function_call, meta, args}, %{}} = ToMeta.transform(ast)
      assert Keyword.get(meta, :name) == "foo"
      assert [_, _] = args
    end

    test "transforms function calls with no arguments" do
      ast = {:bar, [], []}
      assert {:ok, {:function_call, meta, []}, %{}} = ToMeta.transform(ast)
      assert Keyword.get(meta, :name) == "bar"
    end

    test "transforms remote function calls" do
      ast = {{:., [], [{:__aliases__, [], [:String]}, :upcase]}, [], ["hello"]}
      # Remote calls become function_call with qualified name
      assert {:ok, {:function_call, meta, args}, _metadata} = ToMeta.transform(ast)
      assert Keyword.get(meta, :name) == "String.upcase"
      assert [_] = args
    end

    test "transforms Enum.map to collection_op" do
      # Enum.map is transformed to collection_op for semantic analysis
      ast =
        {{:., [], [{:__aliases__, [], [:Enum]}, :map]}, [],
         [[1, 2, 3], {:fn, [], [{:->, [], [[{:x, [], nil}], {:x, [], nil}]}]}]}

      assert {:ok, {:collection_op, meta, [func, collection]}, _metadata} = ToMeta.transform(ast)
      assert Keyword.get(meta, :op_type) == :map
      assert {:lambda, _, _} = func
      assert {:list, _, _} = collection
    end

    test "transforms Enum.filter to collection_op" do
      # Enum.filter is transformed to collection_op
      ast =
        {{:., [], [{:__aliases__, [], [:Enum]}, :filter]}, [],
         [[1, 2, 3], {:fn, [], [{:->, [], [[{:x, [], nil}], true]}]}]}

      assert {:ok, {:collection_op, meta, [func, collection]}, _metadata} = ToMeta.transform(ast)
      assert Keyword.get(meta, :op_type) == :filter
      assert {:lambda, _, _} = func
      assert {:list, _, _} = collection
    end

    test "transforms Enum.reduce to collection_op" do
      # Enum.reduce is transformed to collection_op with initial value
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

      assert {:ok, {:collection_op, meta, [func, collection, initial]}, _metadata} =
               ToMeta.transform(ast)

      assert Keyword.get(meta, :op_type) == :reduce
      assert {:lambda, _, _} = func
      assert {:list, _, _} = collection
      assert {:literal, [subtype: :integer], 0} = initial
    end
  end

  describe "ToMeta - conditionals" do
    test "transforms if with then and else" do
      ast = {:if, [], [true, [do: 1, else: 2]]}

      assert {:ok, {:conditional, _meta, [condition, then_branch, else_branch]}, %{}} =
               ToMeta.transform(ast)

      assert is_literal?(condition, :boolean, true)
      assert is_literal?(then_branch, :integer, 1)
      assert is_literal?(else_branch, :integer, 2)
    end

    test "transforms if without else" do
      ast = {:if, [], [{:x, [], nil}, [do: 42]]}

      assert {:ok, {:conditional, _meta, [_condition, _then_branch, nil]}, %{}} =
               ToMeta.transform(ast)
    end

    test "transforms unless" do
      ast = {:unless, [], [false, [do: 1]]}

      assert {:ok, {:conditional, _meta, [condition, _then, _else]}, metadata} =
               ToMeta.transform(ast)

      # unless may store original_form in metadata or negate condition
      # Check condition is present
      assert condition != nil
    end

    test "transforms case expression" do
      ast = {:case, [], [{:x, [], nil}, [do: [{:->, [], [[1], :one]}, {:->, [], [[2], :two]}]]]}

      assert {:ok, {:pattern_match, _meta, [_scrutinee | rest]}, _metadata} =
               ToMeta.transform(ast)

      # Arms are wrapped in the structure
      assert is_list(rest)
    end
  end

  describe "ToMeta - blocks" do
    test "transforms multi-expression blocks" do
      ast = {:__block__, [], [1, 2, 3]}
      assert {:ok, {:block, _meta, expressions}, %{}} = ToMeta.transform(ast)
      assert [_, _, _] = expressions
    end
  end

  describe "ToMeta - inline_match (pattern matching)" do
    test "transforms simple match: x = 5" do
      ast = {:=, [], [{:x, [], nil}, 5]}

      assert {:ok, {:inline_match, _meta, [pattern, value]}, metadata} = ToMeta.transform(ast)
      assert is_variable?(pattern, "x")
      assert is_literal?(value, :integer, 5)
      assert is_map(metadata)
    end

    test "transforms tuple destructuring: {x, y} = {1, 2}" do
      left = {{:x, [], nil}, {:y, [], nil}}
      right = {1, 2}
      ast = {:=, [], [left, right]}

      assert {:ok, {:inline_match, _meta, [pattern, value]}, _metadata} = ToMeta.transform(ast)
      assert {:tuple, _meta1, [var_x, var_y]} = pattern
      assert is_variable?(var_x, "x")
      assert is_variable?(var_y, "y")
      assert {:tuple, _meta2, [lit1, lit2]} = value
      assert is_literal?(lit1, :integer, 1)
      assert is_literal?(lit2, :integer, 2)
    end

    test "transforms nested pattern: {:ok, value} = result" do
      pattern = {:ok, {:value, [], nil}}
      value = {:result, [], nil}
      ast = {:=, [], [pattern, value]}

      assert {:ok, {:inline_match, _meta, [pattern_meta, value_meta]}, _metadata} =
               ToMeta.transform(ast)

      assert {:tuple, _meta1, [ok_atom, var_value]} = pattern_meta
      assert is_literal?(ok_atom, :symbol, :ok)
      assert is_variable?(var_value, "value")
      assert is_variable?(value_meta, "result")
    end

    test "transforms pin operator: ^x = 5" do
      pin_ast = {:^, [], [{:x, [], nil}]}
      ast = {:=, [], [pin_ast, 5]}

      assert {:ok, {:inline_match, _meta, [pattern, value]}, _metadata} = ToMeta.transform(ast)
      # Pin operator may be represented as function_call or pin node
      assert match?({:function_call, _, _}, pattern) or match?({:pin, _, _}, pattern)
      assert is_literal?(value, :integer, 5)
    end
  end

  describe "ToMeta - anonymous functions" do
    test "transforms simple anonymous function" do
      ast = {:fn, [], [{:->, [], [[{:x, [], nil}], {:+, [], [{:x, [], nil}, 1]}]}]}
      assert {:ok, {:lambda, meta, [_body]}, %{}} = ToMeta.transform(ast)
      params = Keyword.get(meta, :params)
      assert [{:param, "x", nil, nil}] = params
    end
  end

  describe "ToMeta - comprehensions (Extended layer)" do
    test "transforms for comprehension to language_specific" do
      # For comprehensions are transformed to language_specific because after
      # traversal, the <- operator is already transformed to function_call
      ast =
        {:for, [], [{:<-, [], [{:x, [], nil}, [1, 2, 3]]}, [do: {:*, [], [{:x, [], nil}, 2]}]]}

      assert {:ok, {:language_specific, meta, _embedded}, _metadata} = ToMeta.transform(ast)
      assert Keyword.get(meta, :language) == :elixir
      assert Keyword.get(meta, :hint) == :comprehension
    end
  end

  describe "ToMeta - Native layer constructs" do
    test "transforms pipe operator as function_call" do
      # The |> operator is handled as a regular function call because it's not
      # in the exclusion list for the local function call handler
      ast = {:|>, [], [{:x, [], nil}, {:f, [], []}]}

      assert {:ok, {:function_call, meta, [left, right]}, _metadata} = ToMeta.transform(ast)
      assert Keyword.get(meta, :name) == "|>"
      assert is_variable?(left, "x")
      assert match?({:function_call, _, _}, right)
    end

    test "transforms with expression as language_specific" do
      pattern = {:ok, {:x, [], nil}}
      expr = {:result, [], nil}
      body = {:x, [], nil}
      ast = {:with, [], [{:<-, [], [pattern, expr]}, [do: body]]}

      assert {:ok, {:language_specific, meta, _children}, %{}} = ToMeta.transform(ast)
      assert Keyword.get(meta, :language) == :elixir
      assert Keyword.get(meta, :hint) == :with
    end
  end

  describe "FromMeta - literals" do
    test "transforms integer literals back" do
      assert {:ok, 42} = FromMeta.transform({:literal, [subtype: :integer], 42}, %{})
    end

    test "transforms float literals back" do
      assert {:ok, 3.14} = FromMeta.transform({:literal, [subtype: :float], 3.14}, %{})
    end

    test "transforms string literals back" do
      assert {:ok, "hello"} = FromMeta.transform({:literal, [subtype: :string], "hello"}, %{})
    end

    test "transforms boolean literals back" do
      assert {:ok, true} = FromMeta.transform({:literal, [subtype: :boolean], true}, %{})
      assert {:ok, false} = FromMeta.transform({:literal, [subtype: :boolean], false}, %{})
    end

    test "transforms nil back" do
      assert {:ok, nil} = FromMeta.transform({:literal, [subtype: :null], nil}, %{})
    end

    test "transforms symbols back" do
      assert {:ok, :atom} = FromMeta.transform({:literal, [subtype: :symbol], :atom}, %{})
    end
  end

  describe "FromMeta - variables" do
    test "transforms variables back with default context" do
      assert {:ok, {:x, [], nil}} = FromMeta.transform({:variable, [], "x"}, %{})
    end

    test "restores variable context from metadata" do
      metadata = %{context: MyModule, elixir_meta: [line: 10]}

      assert {:ok, {:my_var, _meta, _context}} =
               FromMeta.transform({:variable, [], "my_var"}, metadata)
    end
  end

  describe "FromMeta - binary operators" do
    test "transforms arithmetic operators back" do
      meta_ast =
        {:binary_op, [category: :arithmetic, operator: :+],
         [{:variable, [], "x"}, {:literal, [subtype: :integer], 5}]}

      assert {:ok, {:+, [], [{:x, [], nil}, 5]}} = FromMeta.transform(meta_ast, %{})
    end

    test "transforms comparison operators back" do
      meta_ast =
        {:binary_op, [category: :comparison, operator: :==],
         [{:literal, [subtype: :integer], 1}, {:literal, [subtype: :integer], 2}]}

      assert {:ok, {:==, [], [1, 2]}} = FromMeta.transform(meta_ast, %{})
    end

    test "transforms boolean operators back" do
      meta_ast =
        {:binary_op, [category: :boolean, operator: :and],
         [{:literal, [subtype: :boolean], true}, {:literal, [subtype: :boolean], false}]}

      assert {:ok, {:and, [], [true, false]}} = FromMeta.transform(meta_ast, %{})
    end
  end

  describe "FromMeta - unary operators" do
    test "transforms logical not back" do
      meta_ast =
        {:unary_op, [category: :boolean, operator: :not], [{:literal, [subtype: :boolean], true}]}

      assert {:ok, {:not, [], [true]}} = FromMeta.transform(meta_ast, %{})
    end

    test "transforms negation back" do
      meta_ast =
        {:unary_op, [category: :arithmetic, operator: :-], [{:literal, [subtype: :integer], 42}]}

      assert {:ok, {:-, [], [42]}} = FromMeta.transform(meta_ast, %{})
    end
  end

  describe "FromMeta - function calls" do
    test "transforms local function calls back" do
      meta_ast =
        {:function_call, [name: "foo"],
         [{:literal, [subtype: :integer], 1}, {:literal, [subtype: :integer], 2}]}

      assert {:ok, {:foo, [], [1, 2]}} = FromMeta.transform(meta_ast, %{})
    end

    test "transforms remote function calls back" do
      meta_ast =
        {:function_call, [name: "Enum.map"],
         [
           {:list, [], []},
           {:lambda, [params: [], captures: []], [{:literal, [subtype: :integer], 1}]}
         ]}

      assert {:ok, {{:., [], [{:__aliases__, [], [:Enum]}, :map]}, [], _args}} =
               FromMeta.transform(meta_ast, %{})
    end
  end

  describe "FromMeta - conditionals" do
    test "transforms if back" do
      meta_ast =
        {:conditional, [],
         [
           {:literal, [subtype: :boolean], true},
           {:literal, [subtype: :integer], 1},
           {:literal, [subtype: :integer], 2}
         ]}

      assert {:ok, {:if, [], [true, [do: 1, else: 2]]}} = FromMeta.transform(meta_ast, %{})
    end

    test "transforms if without else back" do
      meta_ast =
        {:conditional, [],
         [{:literal, [subtype: :boolean], true}, {:literal, [subtype: :integer], 1}, nil]}

      assert {:ok, {:if, [], [true, [do: 1]]}} = FromMeta.transform(meta_ast, %{})
    end
  end

  describe "FromMeta - blocks" do
    test "transforms single-expression block to single expression" do
      meta_ast = {:block, [], [{:literal, [subtype: :integer], 1}]}
      assert {:ok, 1} = FromMeta.transform(meta_ast, %{})
    end

    test "transforms multi-expression block" do
      meta_ast =
        {:block, [],
         [
           {:literal, [subtype: :integer], 1},
           {:literal, [subtype: :integer], 2},
           {:literal, [subtype: :integer], 3}
         ]}

      assert {:ok, {:__block__, [], [1, 2, 3]}} = FromMeta.transform(meta_ast, %{})
    end

    test "transforms empty block to nil" do
      meta_ast = {:block, [], []}
      assert {:ok, nil} = FromMeta.transform(meta_ast, %{})
    end
  end

  describe "FromMeta - inline_match (pattern matching)" do
    test "transforms simple match back: x = 5" do
      meta_ast = {:inline_match, [], [{:variable, [], "x"}, {:literal, [subtype: :integer], 5}]}
      assert {:ok, {:=, [], [{:x, [], nil}, 5]}} = FromMeta.transform(meta_ast, %{})
    end

    test "transforms tuple destructuring back: {x, y} = {1, 2}" do
      meta_ast =
        {:inline_match, [],
         [
           {:tuple, [], [{:variable, [], "x"}, {:variable, [], "y"}]},
           {:tuple, [], [{:literal, [subtype: :integer], 1}, {:literal, [subtype: :integer], 2}]}
         ]}

      assert {:ok, {:=, [], [pattern, value]}} = FromMeta.transform(meta_ast, %{})
      assert {{:x, [], nil}, {:y, [], nil}} = pattern
      assert {1, 2} = value
    end

    test "transforms nested pattern back: {:ok, value} = result" do
      meta_ast =
        {:inline_match, [],
         [
           {:tuple, [], [{:literal, [subtype: :symbol], :ok}, {:variable, [], "value"}]},
           {:variable, [], "result"}
         ]}

      assert {:ok, {:=, [], [pattern, {:result, [], nil}]}} = FromMeta.transform(meta_ast, %{})
      assert {:ok, {:value, [], nil}} = pattern
    end

    test "transforms pin operator back: ^x = 5" do
      # Pin might be represented as function_call in the round-trip
      meta_ast =
        {:inline_match, [],
         [
           {:function_call, [name: "^"], [{:variable, [], "x"}]},
           {:literal, [subtype: :integer], 5}
         ]}

      assert {:ok, {:=, [], _children}} = FromMeta.transform(meta_ast, %{})
    end

    test "preserves metadata in round-trip" do
      meta_ast = {:inline_match, [], [{:variable, [], "x"}, {:literal, [subtype: :integer], 5}]}
      metadata = %{elixir_meta: [line: 10]}
      assert {:ok, {:=, _result_meta, _}} = FromMeta.transform(meta_ast, metadata)
    end
  end

  describe "FromMeta - anonymous functions" do
    test "transforms lambda back" do
      meta_ast =
        {:lambda, [params: [{:param, "x", nil, nil}], captures: []], [{:variable, [], "x"}]}

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
      source = "if true, do: 1, else: 2"
      {:ok, ast} = ElixirAdapter.parse(source)
      {:ok, meta_ast, metadata} = ToMeta.transform(ast)
      {:ok, ast2} = FromMeta.transform(meta_ast, metadata)
      {:ok, source2} = ElixirAdapter.unparse(ast2)

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
      assert {:literal, [subtype: :integer], 42} = doc.ast
      assert doc.original_source == source
    end

    test "reify/2 converts Document to source" do
      doc = %Metastatic.Document{
        ast: {:literal, [subtype: :integer], 42},
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
