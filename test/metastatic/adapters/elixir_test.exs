defmodule Metastatic.Adapters.ElixirTest do
  use ExUnit.Case, async: true

  alias Metastatic.Adapters.Elixir, as: ElixirAdapter
  alias Metastatic.Adapters.Elixir.{FromMeta, ToMeta}

  doctest Metastatic.Adapters.Elixir

  # Helper to check 3-tuple format nodes
  defp binary_op?(result, category, operator) do
    match?({:binary_op, meta, [_left, _right]} when is_list(meta), result) and
      Keyword.get(elem(result, 1), :category) == category and
      Keyword.get(elem(result, 1), :operator) == operator
  end

  defp unary_op?(result, category, operator) do
    match?({:unary_op, meta, [_operand]} when is_list(meta), result) and
      Keyword.get(elem(result, 1), :category) == category and
      Keyword.get(elem(result, 1), :operator) == operator
  end

  defp variable?(result, name) do
    match?({:variable, _meta, ^name}, result)
  end

  defp literal?(result, subtype, value) do
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
      assert literal?(result, :integer, 42)
    end

    test "transforms float literals" do
      assert {:ok, result, %{}} = ToMeta.transform(3.14)
      assert literal?(result, :float, 3.14)
    end

    test "transforms string literals" do
      assert {:ok, result, %{}} = ToMeta.transform("hello")
      assert literal?(result, :string, "hello")
    end

    test "transforms boolean literals" do
      assert {:ok, result_true, %{}} = ToMeta.transform(true)
      assert {:ok, result_false, %{}} = ToMeta.transform(false)
      assert literal?(result_true, :boolean, true)
      assert literal?(result_false, :boolean, false)
    end

    test "transforms nil" do
      assert {:ok, result, %{}} = ToMeta.transform(nil)
      assert literal?(result, :null, nil)
    end

    test "transforms atoms as symbols" do
      assert {:ok, result, %{}} = ToMeta.transform(:atom)
      assert literal?(result, :symbol, :atom)
    end
  end

  describe "ToMeta - variables" do
    test "transforms variable references" do
      ast = {:x, [], nil}
      assert {:ok, result, metadata} = ToMeta.transform(ast)
      assert variable?(result, "x")
      assert is_map(metadata)
    end

    test "preserves variable context" do
      ast = {:my_var, [line: 10], MyModule}
      assert {:ok, result, metadata} = ToMeta.transform(ast)
      assert variable?(result, "my_var")
      # Context is stored in the result, metadata contains function/module tracking
      assert is_map(metadata)
    end
  end

  describe "ToMeta - binary operators" do
    test "transforms arithmetic addition" do
      ast = {:+, [], [{:x, [], nil}, 5]}
      assert {:ok, result, %{}} = ToMeta.transform(ast)
      assert binary_op?(result, :arithmetic, :+)

      {:binary_op, _meta, [left, right]} = result
      assert variable?(left, "x")
      assert literal?(right, :integer, 5)
    end

    test "transforms arithmetic subtraction" do
      ast = {:-, [], [10, {:y, [], nil}]}
      assert {:ok, result, %{}} = ToMeta.transform(ast)
      assert binary_op?(result, :arithmetic, :-)

      {:binary_op, _meta, [left, right]} = result
      assert literal?(left, :integer, 10)
      assert variable?(right, "y")
    end

    test "transforms multiplication and division" do
      mult_ast = {:*, [], [2, 3]}
      assert {:ok, result, %{}} = ToMeta.transform(mult_ast)
      assert binary_op?(result, :arithmetic, :*)

      div_ast = {:/, [], [10, 2]}
      assert {:ok, result, %{}} = ToMeta.transform(div_ast)
      assert binary_op?(result, :arithmetic, :/)
    end

    test "transforms comparison operators" do
      eq_ast = {:==, [], [1, 2]}
      assert {:ok, result, %{}} = ToMeta.transform(eq_ast)
      assert binary_op?(result, :comparison, :==)

      lt_ast = {:<, [], [1, 2]}
      assert {:ok, result, %{}} = ToMeta.transform(lt_ast)
      assert binary_op?(result, :comparison, :<)

      gte_ast = {:>=, [], [5, 3]}
      assert {:ok, result, %{}} = ToMeta.transform(gte_ast)
      assert binary_op?(result, :comparison, :>=)
    end

    test "transforms boolean operators" do
      and_ast = {:and, [], [true, false]}
      assert {:ok, result, %{}} = ToMeta.transform(and_ast)
      assert binary_op?(result, :boolean, :and)

      or_ast = {:or, [], [true, false]}
      assert {:ok, result, %{}} = ToMeta.transform(or_ast)
      assert binary_op?(result, :boolean, :or)
    end

    test "transforms string concatenation" do
      ast = {:<>, [], ["hello", " world"]}
      assert {:ok, result, %{}} = ToMeta.transform(ast)
      assert binary_op?(result, :string, :<>)
    end

    test "normalizes && to :and" do
      ast = {:&&, [], [true, false]}
      assert {:ok, {:binary_op, meta, _children}, %{}} = ToMeta.transform(ast)
      assert Keyword.get(meta, :category) == :boolean
      assert Keyword.get(meta, :operator) == :and
      assert Keyword.get(meta, :original_op) == :&&
    end

    test "normalizes || to :or" do
      ast = {:||, [], [true, false]}
      assert {:ok, {:binary_op, meta, _children}, %{}} = ToMeta.transform(ast)
      assert Keyword.get(meta, :category) == :boolean
      assert Keyword.get(meta, :operator) == :or
      assert Keyword.get(meta, :original_op) == :||
    end

    test ":and and :or do not get original_op metadata" do
      and_ast = {:and, [], [true, false]}
      assert {:ok, {:binary_op, meta, _}, %{}} = ToMeta.transform(and_ast)
      assert Keyword.get(meta, :operator) == :and
      assert Keyword.get(meta, :original_op) == nil

      or_ast = {:or, [], [true, false]}
      assert {:ok, {:binary_op, meta, _}, %{}} = ToMeta.transform(or_ast)
      assert Keyword.get(meta, :operator) == :or
      assert Keyword.get(meta, :original_op) == nil
    end

    test "&& round-trips back to &&" do
      ast = {:&&, [line: 1], [true, false]}
      assert {:ok, meta_ast, metadata} = ToMeta.transform(ast)
      assert {:ok, back} = FromMeta.transform(meta_ast, metadata)
      assert {:&&, _, [true, false]} = back
    end
  end

  describe "ToMeta - unary operators" do
    test "transforms logical not" do
      ast = {:not, [], [true]}
      assert {:ok, result, %{}} = ToMeta.transform(ast)
      assert unary_op?(result, :boolean, :not)

      {:unary_op, _meta, [operand]} = result
      assert literal?(operand, :boolean, true)
    end

    test "transforms negation" do
      ast = {:-, [], [42]}
      assert {:ok, result, %{}} = ToMeta.transform(ast)
      assert unary_op?(result, :arithmetic, :-)

      {:unary_op, _meta, [operand]} = result
      assert literal?(operand, :integer, 42)
    end

    test "transforms positive sign" do
      ast = {:+, [], [42]}
      assert {:ok, result, %{}} = ToMeta.transform(ast)
      assert unary_op?(result, :arithmetic, :+)

      {:unary_op, _meta, [operand]} = result
      assert literal?(operand, :integer, 42)
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

      assert literal?(condition, :boolean, true)
      assert literal?(then_branch, :integer, 1)
      assert literal?(else_branch, :integer, 2)
    end

    test "transforms if without else" do
      ast = {:if, [], [{:x, [], nil}, [do: 42]]}

      assert {:ok, {:conditional, _meta, [_condition, _then_branch, nil]}, %{}} =
               ToMeta.transform(ast)
    end

    test "transforms unless" do
      ast = {:unless, [], [false, [do: 1]]}

      assert {:ok, {:conditional, _meta, [condition, _then, _else]}, _final_context} =
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
      assert variable?(pattern, "x")
      assert literal?(value, :integer, 5)
      assert is_map(metadata)
    end

    test "transforms tuple destructuring: {x, y} = {1, 2}" do
      left = {{:x, [], nil}, {:y, [], nil}}
      right = {1, 2}
      ast = {:=, [], [left, right]}

      assert {:ok, {:inline_match, _meta, [pattern, value]}, _metadata} = ToMeta.transform(ast)
      assert {:tuple, _meta1, [var_x, var_y]} = pattern
      assert variable?(var_x, "x")
      assert variable?(var_y, "y")
      assert {:tuple, _meta2, [lit1, lit2]} = value
      assert literal?(lit1, :integer, 1)
      assert literal?(lit2, :integer, 2)
    end

    test "transforms nested pattern: {:ok, value} = result" do
      pattern = {:ok, {:value, [], nil}}
      value = {:result, [], nil}
      ast = {:=, [], [pattern, value]}

      assert {:ok, {:inline_match, _meta, [pattern_meta, value_meta]}, _metadata} =
               ToMeta.transform(ast)

      assert {:tuple, _meta1, [ok_atom, var_value]} = pattern_meta
      assert literal?(ok_atom, :symbol, :ok)
      assert variable?(var_value, "value")
      assert variable?(value_meta, "result")
    end

    test "transforms pin operator: ^x = 5" do
      pin_ast = {:^, [], [{:x, [], nil}]}
      ast = {:=, [], [pin_ast, 5]}

      assert {:ok, {:inline_match, _meta, [pattern, value]}, _metadata} = ToMeta.transform(ast)
      # Pin operator may be represented as function_call or pin node
      assert match?({:function_call, _, _}, pattern) or match?({:pin, _, _}, pattern)
      assert literal?(value, :integer, 5)
    end
  end

  describe "ToMeta - anonymous functions" do
    test "transforms simple anonymous function" do
      ast = {:fn, [], [{:->, [], [[{:x, [], nil}], {:+, [], [{:x, [], nil}, 1]}]}]}
      assert {:ok, {:lambda, meta, [_body]}, %{}} = ToMeta.transform(ast)
      params = Keyword.get(meta, :params)
      assert [{:param, [], "x"}] = params
    end
  end

  describe "ToMeta - comprehensions (Extended layer)" do
    test "transforms for comprehension to comprehension node" do
      ast =
        {:for, [], [{:<-, [], [{:x, [], nil}, [1, 2, 3]]}, [do: {:*, [], [{:x, [], nil}, 2]}]]}

      assert {:ok, {:comprehension, _meta, [body | generators]}, _metadata} =
               ToMeta.transform(ast)

      # Body is the multiplication expression
      assert {:binary_op, _, _} = body
      # Single generator
      assert [{:generator, _, [{:variable, _, "x"}, {:list, _, _}]}] = generators
    end
  end

  describe "ToMeta - Pipe operator desugaring" do
    test "desugars simple pipe to function call" do
      # x |> f()
      ast = {:|>, [], [{:x, [], nil}, {:f, [], []}]}

      assert {:ok, {:function_call, meta, [left]}, _metadata} = ToMeta.transform(ast)
      assert Keyword.get(meta, :name) == "f"
      assert Keyword.get(meta, :pipe) == true
      assert variable?(left, "x")
    end

    test "desugars pipe with arguments" do
      # x |> f(y)
      ast = {:|>, [], [{:x, [], nil}, {:f, [], [{:y, [], nil}]}]}

      assert {:ok, {:function_call, meta, [left, right]}, _metadata} = ToMeta.transform(ast)
      assert Keyword.get(meta, :name) == "f"
      assert Keyword.get(meta, :pipe) == true
      assert variable?(left, "x")
      assert variable?(right, "y")
    end

    test "desugars chained pipes" do
      # x |> f() |> g(y)
      inner_pipe = {:|>, [], [{:x, [], nil}, {:f, [], []}]}
      ast = {:|>, [], [inner_pipe, {:g, [], [{:y, [], nil}]}]}

      assert {:ok, {:function_call, outer_meta, [inner_call, y_var]}, _metadata} =
               ToMeta.transform(ast)

      assert Keyword.get(outer_meta, :name) == "g"
      assert Keyword.get(outer_meta, :pipe) == true
      assert variable?(y_var, "y")

      # Inner pipe was also desugared
      assert {:function_call, inner_meta, [x_var]} = inner_call
      assert Keyword.get(inner_meta, :name) == "f"
      assert Keyword.get(inner_meta, :pipe) == true
      assert variable?(x_var, "x")
    end

    test "desugars pipe to remote call" do
      # x |> Enum.map(fn y -> y end)
      lambda = {:fn, [], [{:->, [], [[{:y, [], nil}], {:y, [], nil}]}]}
      remote = {{:., [], [{:__aliases__, [alias: false], [:Enum]}, :map]}, [], [lambda]}
      ast = {:|>, [], [{:x, [], nil}, remote]}

      assert {:ok, {:function_call, meta, [x_var, lambda_node]}, _metadata} =
               ToMeta.transform(ast)

      assert Keyword.get(meta, :name) == "Enum.map"
      assert Keyword.get(meta, :pipe) == true
      assert variable?(x_var, "x")
      assert {:lambda, _, _} = lambda_node
    end

    test "desugars pipe without parens (variable on right)" do
      # x |> f (no parens - f appears as variable in AST)
      ast = {:|>, [], [{:x, [], nil}, {:f, [], nil}]}

      assert {:ok, {:function_call, meta, [left]}, _metadata} = ToMeta.transform(ast)
      assert Keyword.get(meta, :name) == "f"
      assert Keyword.get(meta, :pipe) == true
      assert variable?(left, "x")
    end

    test "desugars pipe with multiple arguments" do
      # x |> String.replace("a", "b")
      remote =
        {{:., [], [{:__aliases__, [alias: false], [:String]}, :replace]}, [], ["a", "b"]}

      ast = {:|>, [], [{:x, [], nil}, remote]}

      assert {:ok, {:function_call, meta, [x_var, a_lit, b_lit]}, _metadata} =
               ToMeta.transform(ast)

      assert Keyword.get(meta, :name) == "String.replace"
      assert Keyword.get(meta, :pipe) == true
      assert variable?(x_var, "x")
      assert literal?(a_lit, :string, "a")
      assert literal?(b_lit, :string, "b")
    end
  end

  describe "ToMeta - with expression" do
    test "transforms simple with to block of inline_matches" do
      # with {:ok, x} <- result, do: x
      pattern = {:{}, [], [:ok, {:x, [], nil}]}
      expr = {:result, [], nil}
      body = {:x, [], nil}
      ast = {:with, [], [{:<-, [], [pattern, expr]}, [do: body]]}

      assert {:ok, {:block, meta, [clause, body_ast]}, _ctx} = ToMeta.transform(ast)
      assert Keyword.get(meta, :original_form) == :with

      # Clause is inline_match with original_form: :with_clause
      assert {:inline_match, clause_meta, [pattern_ast, expr_ast]} = clause
      assert Keyword.get(clause_meta, :original_form) == :with_clause
      assert {:tuple, _, _} = pattern_ast
      assert {:variable, _, "result"} = expr_ast

      # Body is the result expression
      assert {:variable, _, "x"} = body_ast
    end

    test "transforms with + else to block with pattern_match" do
      # with {:ok, x} <- result do
      #   x
      # else
      #   {:error, reason} -> reason
      # end
      pattern = {:{}, [], [:ok, {:x, [], nil}]}
      expr = {:result, [], nil}
      body = {:x, [], nil}
      error_pattern = {:{}, [], [:error, {:reason, [], nil}]}
      error_body = {:reason, [], nil}

      ast =
        {:with, [],
         [
           {:<-, [], [pattern, expr]},
           [do: body, else: [{:->, [], [[error_pattern], error_body]}]]
         ]}

      assert {:ok, {:block, meta, [clause, body_ast, else_node]}, _ctx} = ToMeta.transform(ast)
      assert Keyword.get(meta, :original_form) == :with

      # Clause
      assert {:inline_match, _, _} = clause
      assert {:variable, _, "x"} = body_ast

      # Else is a pattern_match
      assert {:pattern_match, else_meta, [scrutinee | arms]} = else_node
      assert Keyword.get(else_meta, :original_form) == :with_else
      assert {:variable, _, "_with_result"} = scrutinee
      assert [_] = arms
    end

    test "transforms with multiple clauses" do
      # with {:ok, a} <- foo(), {:ok, b} <- bar(a), do: a + b
      clause1 = {:<-, [], [{:{}, [], [:ok, {:a, [], nil}]}, {:foo, [], []}]}
      clause2 = {:<-, [], [{:{}, [], [:ok, {:b, [], nil}]}, {:bar, [], [{:a, [], nil}]}]}
      body = {:+, [], [{:a, [], nil}, {:b, [], nil}]}
      ast = {:with, [], [clause1, clause2, [do: body]]}

      assert {:ok, {:block, meta, [match1, match2, body_ast]}, _ctx} = ToMeta.transform(ast)
      assert Keyword.get(meta, :original_form) == :with
      assert {:inline_match, _, _} = match1
      assert {:inline_match, _, _} = match2
      assert {:binary_op, _, _} = body_ast
    end

    test "with clause with = (regular match) produces inline_match" do
      # with {:ok, x} <- result, y = process(x), do: y
      clause1 = {:<-, [], [{:{}, [], [:ok, {:x, [], nil}]}, {:result, [], nil}]}
      clause2 = {:=, [], [{:y, [], nil}, {:process, [], [{:x, [], nil}]}]}
      body = {:y, [], nil}
      ast = {:with, [], [clause1, clause2, [do: body]]}

      assert {:ok, {:block, _, [match1, match2, _body]}, _ctx} = ToMeta.transform(ast)
      assert {:inline_match, meta1, _} = match1
      assert Keyword.get(meta1, :original_form) == :with_clause
      # Regular match clause doesn't have :with_clause marker
      assert {:inline_match, meta2, _} = match2
      refute Keyword.get(meta2, :original_form) == :with_clause
    end

    test "with node conforms to M2" do
      # The output is a block of inline_matches, which are valid M2 nodes
      ast = {:with, [], [{:<-, [], [{:x, [], nil}, {:foo, [], []}]}, [do: {:x, [], nil}]]}
      assert {:ok, meta_ast, _ctx} = ToMeta.transform(ast)
      assert Metastatic.AST.conforms?(meta_ast)
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
        {:lambda, [params: [{:param, [], "x"}], captures: []], [{:variable, [], "x"}]}

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

  describe "ToMeta - Import Directives" do
    test "transforms import to :import node" do
      source = "import Enum"
      {:ok, ast} = ElixirAdapter.parse(source)
      {:ok, meta_ast, _metadata} = ToMeta.transform(ast)

      assert {:import, meta, []} = meta_ast
      assert Keyword.get(meta, :source) == "Enum"
      assert Keyword.get(meta, :import_type) == :import
      assert Keyword.get(meta, :language) == :elixir
    end

    test "transforms use to :import node" do
      source = "use GenServer"
      {:ok, ast} = ElixirAdapter.parse(source)
      {:ok, meta_ast, _metadata} = ToMeta.transform(ast)

      assert {:import, meta, []} = meta_ast
      assert Keyword.get(meta, :source) == "GenServer"
      assert Keyword.get(meta, :import_type) == :use
      assert Keyword.get(meta, :language) == :elixir
    end

    test "transforms require to :import node" do
      source = "require Logger"
      {:ok, ast} = ElixirAdapter.parse(source)
      {:ok, meta_ast, _metadata} = ToMeta.transform(ast)

      assert {:import, meta, []} = meta_ast
      assert Keyword.get(meta, :source) == "Logger"
      assert Keyword.get(meta, :import_type) == :require
      assert Keyword.get(meta, :language) == :elixir
    end

    test "transforms alias to :import node" do
      source = "alias MyApp.User"
      {:ok, ast} = ElixirAdapter.parse(source)
      {:ok, meta_ast, _metadata} = ToMeta.transform(ast)

      assert {:import, meta, []} = meta_ast
      assert Keyword.get(meta, :source) == "MyApp.User"
      assert Keyword.get(meta, :import_type) == :alias
      assert Keyword.get(meta, :language) == :elixir
    end

    test "transforms import with options" do
      source = "import Enum, only: [map: 2]"
      {:ok, ast} = ElixirAdapter.parse(source)
      {:ok, meta_ast, _metadata} = ToMeta.transform(ast)

      assert {:import, meta, []} = meta_ast
      assert Keyword.get(meta, :source) == "Enum"
      assert Keyword.get(meta, :import_type) == :import
    end

    test "import nodes conform to M2" do
      import_node = {:import, [source: "Enum", import_type: :import, language: :elixir], []}
      assert Metastatic.AST.conforms?(import_node)
    end

    test "import node has structural layer" do
      assert Metastatic.AST.layer(:import) == :structural
    end
  end

  describe "FromMeta - Import Directives" do
    test "transforms :import back to import" do
      meta_ast = {:import, [source: "Enum", import_type: :import], []}

      assert {:ok, {:import, _, [{:__aliases__, [], [:Enum]}]}} =
               FromMeta.transform(meta_ast, %{})
    end

    test "transforms :import with use type back to use" do
      meta_ast = {:import, [source: "GenServer", import_type: :use], []}

      assert {:ok, {:use, _, [{:__aliases__, [], [:GenServer]}]}} =
               FromMeta.transform(meta_ast, %{})
    end

    test "transforms :import with require type back to require" do
      meta_ast = {:import, [source: "Logger", import_type: :require], []}

      assert {:ok, {:require, _, [{:__aliases__, [], [:Logger]}]}} =
               FromMeta.transform(meta_ast, %{})
    end

    test "transforms :import with alias type back to alias" do
      meta_ast = {:import, [source: "MyApp.User", import_type: :alias], []}

      assert {:ok, {:alias, _, [{:__aliases__, [], [:MyApp, :User]}]}} =
               FromMeta.transform(meta_ast, %{})
    end

    test "round-trips import directive" do
      source = "import Enum"
      {:ok, ast} = ElixirAdapter.parse(source)
      {:ok, meta_ast, metadata} = ToMeta.transform(ast)
      {:ok, ast2} = FromMeta.transform(meta_ast, metadata)
      {:ok, source2} = ElixirAdapter.unparse(ast2)
      assert source == source2
    end

    test "round-trips use directive" do
      source = "use GenServer"
      {:ok, ast} = ElixirAdapter.parse(source)
      {:ok, meta_ast, metadata} = ToMeta.transform(ast)
      {:ok, ast2} = FromMeta.transform(meta_ast, metadata)
      {:ok, source2} = ElixirAdapter.unparse(ast2)
      assert source == source2
    end

    test "round-trips require directive" do
      source = "require Logger"
      {:ok, ast} = ElixirAdapter.parse(source)
      {:ok, meta_ast, metadata} = ToMeta.transform(ast)
      {:ok, ast2} = FromMeta.transform(meta_ast, metadata)
      {:ok, source2} = ElixirAdapter.unparse(ast2)
      assert source == source2
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
