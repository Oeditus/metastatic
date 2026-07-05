defmodule Metastatic.Adapters.ErlangTest do
  use ExUnit.Case, async: true

  alias Metastatic.Adapters.Elixir, as: ElixirAdapter
  alias Metastatic.Adapters.Elixir.ToMeta, as: ElixirToMeta
  alias Metastatic.Adapters.Erlang, as: ErlangAdapter
  alias Metastatic.Adapters.Erlang.{FromMeta, ToMeta}

  doctest Metastatic.Adapters.Erlang

  describe "parse/1" do
    test "parses integer literals" do
      assert {:ok, {:integer, 1, 42}} = ErlangAdapter.parse("42.")
    end

    test "parses arithmetic expressions" do
      assert {:ok, {:op, _, :+, {:var, _, :X}, {:integer, _, 5}}} = ErlangAdapter.parse("X + 5.")
    end

    test "parses function calls" do
      assert {:ok, {:call, _, {:atom, _, :foo}, args}} = ErlangAdapter.parse("foo(1, 2, 3).")
      assert [_, _, _] = args
    end

    test "returns error for invalid syntax" do
      assert {:error, error_msg} = ErlangAdapter.parse("X +")
      assert error_msg =~ "error"
    end
  end

  describe "unparse/1" do
    test "converts AST back to source code" do
      ast = {:op, 1, :+, {:var, 1, :X}, {:integer, 1, 5}}
      assert {:ok, result} = ErlangAdapter.unparse(ast)
      assert result =~ "X"
      assert result =~ "5"
    end
  end

  describe "file_extensions/0" do
    test "returns Erlang file extensions" do
      assert [".erl", ".hrl"] = ErlangAdapter.file_extensions()
    end
  end

  describe "ToMeta - literals" do
    test "transforms integer literals" do
      assert {:ok, {:literal, _, 42}, %{}} = ToMeta.transform({:integer, 1, 42})
    end

    test "transforms float literals" do
      assert {:ok, {:literal, _, 3.14}, %{}} = ToMeta.transform({:float, 1, 3.14})
    end

    test "transforms string literals" do
      assert {:ok, {:literal, _, "hello"}, %{}} =
               ToMeta.transform({:string, 1, ~c"hello"})
    end

    test "transforms boolean literals" do
      assert {:ok, {:literal, _, true}, %{}} =
               ToMeta.transform({:atom, 1, true})

      assert {:ok, {:literal, _, false}, %{}} =
               ToMeta.transform({:atom, 1, false})
    end

    test "transforms nil" do
      assert {:ok, {:literal, _, nil}, %{}} = ToMeta.transform({:atom, 1, nil})
    end

    test "transforms undefined" do
      assert {:ok, {:literal, _, nil}, %{erlang_atom: :undefined}} =
               ToMeta.transform({:atom, 1, :undefined})
    end

    test "transforms atoms as symbols" do
      assert {:ok, {:literal, _, :atom}, %{}} =
               ToMeta.transform({:atom, 1, :atom})
    end
  end

  describe "ToMeta - variables" do
    test "transforms variable references" do
      assert {:ok, {:variable, meta, "X"}, %{}} = ToMeta.transform({:var, 1, :X})
      assert Keyword.get(meta, :line) == 1
    end
  end

  describe "ToMeta - binary operators" do
    test "transforms arithmetic addition" do
      ast = {:op, 1, :+, {:var, 1, :X}, {:integer, 1, 5}}

      assert {:ok, {:binary_op, [category: :arithmetic, operator: :+, line: _], [left, right]},
              %{}} =
               ToMeta.transform(ast)

      assert {:variable, _, "X"} = left
      assert {:literal, _, 5} = right
    end

    test "transforms comparison operators" do
      ast = {:op, 1, :==, {:integer, 1, 1}, {:integer, 1, 2}}

      assert {:ok, {:binary_op, [category: :comparison, operator: :==, line: _], _children}, %{}} =
               ToMeta.transform(ast)
    end

    test "normalizes Erlang-specific comparison operators" do
      ast = {:op, 1, :"/=", {:integer, 1, 1}, {:integer, 1, 2}}

      assert {:ok, {:binary_op, [category: :comparison, operator: :!=, line: _], _children}, %{}} =
               ToMeta.transform(ast)
    end

    test "transforms boolean operators" do
      ast = {:op, 1, :andalso, {:atom, 1, true}, {:atom, 1, false}}

      assert {:ok, {:binary_op, [category: :boolean, operator: :and, line: _], _children},
              %{erlang_op: :andalso}} = ToMeta.transform(ast)
    end
  end

  describe "ToMeta - unary operators" do
    test "transforms logical not" do
      ast = {:op, 1, :not, {:atom, 1, true}}

      assert {:ok, {:unary_op, [category: :boolean, operator: :not, line: _], [operand]}, %{}} =
               ToMeta.transform(ast)

      assert {:literal, _, true} = operand
    end

    test "transforms negation" do
      ast = {:op, 1, :-, {:integer, 1, 42}}

      assert {:ok, {:unary_op, [category: :arithmetic, operator: :-, line: _], [operand]}, %{}} =
               ToMeta.transform(ast)

      assert {:literal, _, 42} = operand
    end
  end

  describe "ToMeta - function calls" do
    test "transforms local function calls" do
      ast = {:call, 1, {:atom, 1, :foo}, [{:integer, 1, 1}, {:integer, 1, 2}]}
      assert {:ok, {:function_call, [name: "foo", line: _], args}, %{}} = ToMeta.transform(ast)
      assert [_, _] = args
    end

    test "transforms remote function calls" do
      ast =
        {:call, 1, {:remote, 1, {:atom, 1, :lists}, {:atom, 1, :map}},
         [{:atom, 1, :fun}, {nil, 1}]}

      assert {:ok, {:function_call, [name: "lists.map", line: _], _args}, %{call_type: :remote}} =
               ToMeta.transform(ast)
    end
  end

  describe "ToMeta - lists (cons flattening)" do
    test "transforms empty list" do
      assert {:ok, {:list, _, []}, _} = ToMeta.transform({nil, 1})
    end

    test "transforms single-element list" do
      # [1] in Erlang AST
      ast = {:cons, 1, {:integer, 1, 1}, {nil, 1}}
      assert {:ok, {:list, _, elements}, _} = ToMeta.transform(ast)
      assert [{:literal, _, 1}] = elements
    end

    test "transforms multi-element list" do
      # [1, 2, 3] in Erlang AST
      ast =
        {:cons, 1, {:integer, 1, 1},
         {:cons, 1, {:integer, 1, 2}, {:cons, 1, {:integer, 1, 3}, {nil, 1}}}}

      assert {:ok, {:list, _, elements}, _} = ToMeta.transform(ast)

      assert [
               {:literal, _, 1},
               {:literal, _, 2},
               {:literal, _, 3}
             ] = elements
    end

    test "transforms heterogeneous list" do
      # [1, :hello, X] in Erlang AST
      ast =
        {:cons, 1, {:integer, 1, 1},
         {:cons, 1, {:atom, 1, :hello}, {:cons, 1, {:var, 1, :X}, {nil, 1}}}}

      assert {:ok, {:list, _, [_, _, _]}, _} = ToMeta.transform(ast)
    end

    test "transforms improper list to language_specific" do
      # [1 | 2] in Erlang AST -- improper list
      ast = {:cons, 1, {:integer, 1, 1}, {:integer, 1, 2}}

      assert {:ok, {:language_specific, meta, _}, _} = ToMeta.transform(ast)
      assert Keyword.get(meta, :hint) == :improper_list
    end

    test "transforms nested list" do
      # [[1, 2], 3] in Erlang AST
      inner = {:cons, 1, {:integer, 1, 1}, {:cons, 1, {:integer, 1, 2}, {nil, 1}}}
      ast = {:cons, 1, inner, {:cons, 1, {:integer, 1, 3}, {nil, 1}}}

      assert {:ok, {:list, _, [inner_list, three]}, _} = ToMeta.transform(ast)
      assert {:list, _, [_, _]} = inner_list
      assert {:literal, _, 3} = three
    end
  end

  describe "round-trip - lists" do
    test "round-trips proper list" do
      # [1, 2, 3]
      ast =
        {:cons, 1, {:integer, 1, 1},
         {:cons, 1, {:integer, 1, 2}, {:cons, 1, {:integer, 1, 3}, {nil, 1}}}}

      assert {:ok, meta_ast, metadata} = ToMeta.transform(ast)
      assert {:list, _, [_, _, _]} = meta_ast

      assert {:ok, ast2} = FromMeta.transform(meta_ast, metadata)
      # Verify it reconstructs a proper cons chain
      assert {:cons, _, {:integer, _, 1},
              {:cons, _, {:integer, _, 2}, {:cons, _, {:integer, _, 3}, {nil, _}}}} =
               ast2
    end

    test "round-trips empty list" do
      ast = {nil, 1}
      assert {:ok, meta_ast, metadata} = ToMeta.transform(ast)
      assert {:list, _, []} = meta_ast

      assert {:ok, ast2} = FromMeta.transform(meta_ast, metadata)
      assert {nil, _} = ast2
    end

    test "round-trips single-element list" do
      ast = {:cons, 1, {:integer, 1, 42}, {nil, 1}}
      assert {:ok, meta_ast, metadata} = ToMeta.transform(ast)
      assert {:list, _, [{:literal, _, 42}]} = meta_ast

      assert {:ok, ast2} = FromMeta.transform(meta_ast, metadata)
      assert {:cons, _, {:integer, _, 42}, {nil, _}} = ast2
    end
  end

  describe "ToMeta - inline_match (pattern matching)" do
    test "transforms simple match: X = 5" do
      ast = {:match, 1, {:var, 1, :X}, {:integer, 1, 5}}

      assert {:ok, {:inline_match, _, [pattern, value]}, _metadata} = ToMeta.transform(ast)
      assert {:variable, _, "X"} = pattern
      assert {:literal, _, 5} = value
    end

    test "transforms tuple destructuring: {X, Y} = {1, 2}" do
      # {X, Y} = {1, 2}
      pattern = {:tuple, 1, [{:var, 1, :X}, {:var, 1, :Y}]}
      value = {:tuple, 1, [{:integer, 1, 1}, {:integer, 1, 2}]}
      ast = {:match, 1, pattern, value}

      assert {:ok, {:inline_match, _, [pattern_meta, value_meta]}, _metadata} =
               ToMeta.transform(ast)

      assert {:tuple, _, [var_x, var_y]} = pattern_meta
      assert {:variable, _, "X"} = var_x
      assert {:variable, _, "Y"} = var_y
      assert {:tuple, _, [lit1, lit2]} = value_meta
      assert {:literal, _, 1} = lit1
      assert {:literal, _, 2} = lit2
    end

    test "transforms list cons pattern: [H | T] = List" do
      # [H | T] = List
      pattern = {:cons, 1, {:var, 1, :H}, {:var, 1, :T}}
      value = {:var, 1, :List}
      ast = {:match, 1, pattern, value}

      assert {:ok, {:inline_match, _, [pattern_meta, value_meta]}, _metadata} =
               ToMeta.transform(ast)

      assert {:cons_pattern, meta, [head, tail]} = pattern_meta
      assert Keyword.get(meta, :line) == 1
      assert {:variable, _, "H"} = head
      assert {:variable, _, "T"} = tail
      assert {:variable, _, "List"} = value_meta
    end

    test "transforms wildcard pattern: _ = Value" do
      # _ = Value
      ast = {:match, 1, {:var, 1, :_}, {:var, 1, :Value}}

      assert {:ok, {:inline_match, _, [pattern, value]}, _metadata} = ToMeta.transform(ast)
      assert :_ = pattern
      assert {:variable, _, "Value"} = value
    end
  end

  describe "FromMeta - literals" do
    test "transforms integer literals back" do
      assert {:ok, {:integer, 0, 42}} =
               FromMeta.transform({:literal, [subtype: :integer], 42}, %{})
    end

    test "transforms string literals back" do
      assert {:ok, {:string, 0, ~c"hello"}} =
               FromMeta.transform({:literal, [subtype: :string], "hello"}, %{})
    end

    test "transforms boolean literals back" do
      assert {:ok, {:atom, 0, true}} =
               FromMeta.transform({:literal, [subtype: :boolean], true}, %{})
    end
  end

  describe "FromMeta - variables" do
    test "transforms variables back" do
      assert {:ok, {:var, 0, :X}} = FromMeta.transform({:variable, [scope: :local], "X"}, %{})
    end
  end

  describe "FromMeta - binary operators" do
    test "transforms arithmetic operators back" do
      meta_ast =
        {:binary_op, [category: :arithmetic, operator: :+],
         [{:variable, [scope: :local], "X"}, {:literal, [subtype: :integer], 5}]}

      assert {:ok, {:op, 0, :+, {:var, 0, :X}, {:integer, 0, 5}}} =
               FromMeta.transform(meta_ast, %{})
    end

    test "denormalizes comparison operators" do
      meta_ast =
        {:binary_op, [category: :comparison, operator: :!=],
         [{:literal, [subtype: :integer], 1}, {:literal, [subtype: :integer], 2}]}

      assert {:ok, {:op, 0, :"/=", _, _}} = FromMeta.transform(meta_ast, %{})
    end
  end

  describe "FromMeta - function calls" do
    test "transforms local function calls back" do
      meta_ast =
        {:function_call, [name: "foo"],
         [{:literal, [subtype: :integer], 1}, {:literal, [subtype: :integer], 2}]}

      assert {:ok, {:call, 0, {:atom, 0, :foo}, [{:integer, 0, 1}, {:integer, 0, 2}]}} =
               FromMeta.transform(meta_ast, %{})
    end
  end

  describe "FromMeta - inline_match (pattern matching)" do
    test "transforms simple match back: X = 5" do
      meta_ast =
        {:inline_match, [],
         [{:variable, [scope: :local], "X"}, {:literal, [subtype: :integer], 5}]}

      assert {:ok, {:match, 0, {:var, 0, :X}, {:integer, 0, 5}}} =
               FromMeta.transform(meta_ast, %{})
    end

    test "transforms tuple destructuring back: {X, Y} = {1, 2}" do
      meta_ast =
        {:inline_match, [],
         [
           {:tuple, [], [{:variable, [scope: :local], "X"}, {:variable, [scope: :local], "Y"}]},
           {:tuple, [], [{:literal, [subtype: :integer], 1}, {:literal, [subtype: :integer], 2}]}
         ]}

      assert {:ok, {:match, 0, pattern, value}} = FromMeta.transform(meta_ast, %{})
      assert {:tuple, 0, [{:var, 0, :X}, {:var, 0, :Y}]} = pattern
      assert {:tuple, 0, [{:integer, 0, 1}, {:integer, 0, 2}]} = value
    end

    test "transforms cons pattern back: [H | T] = List" do
      meta_ast =
        {:inline_match, [],
         [
           {:cons_pattern, [],
            [{:variable, [scope: :local], "H"}, {:variable, [scope: :local], "T"}]},
           {:variable, [scope: :local], "List"}
         ]}

      assert {:ok, {:match, 0, {:cons, 0, {:var, 0, :H}, {:var, 0, :T}}, {:var, 0, :List}}} =
               FromMeta.transform(meta_ast, %{})
    end

    test "transforms wildcard pattern back: _ = Value" do
      meta_ast = {:inline_match, [], [:_, {:variable, [scope: :local], "Value"}]}

      assert {:ok, {:match, 0, {:var, 0, :_}, {:var, 0, :Value}}} =
               FromMeta.transform(meta_ast, %{})
    end

    test "preserves line numbers in round-trip" do
      meta_ast =
        {:inline_match, [],
         [{:variable, [scope: :local], "X"}, {:literal, [subtype: :integer], 5}]}

      metadata = %{line: 42}

      assert {:ok, {:match, 42, _, _}} = FromMeta.transform(meta_ast, metadata)
    end
  end

  describe "round-trip transformations" do
    test "integer round-trips" do
      source = "42."
      {:ok, ast} = ErlangAdapter.parse(source)
      {:ok, meta_ast, metadata} = ToMeta.transform(ast)
      {:ok, ast2} = FromMeta.transform(meta_ast, metadata)
      # Check semantic equivalence (ignoring line numbers)
      assert {:integer, _, 42} = ast
      assert {:integer, _, 42} = ast2
    end

    test "arithmetic expression round-trips" do
      source = "X + 5."
      {:ok, ast} = ErlangAdapter.parse(source)
      {:ok, meta_ast, metadata} = ToMeta.transform(ast)
      {:ok, ast2} = FromMeta.transform(meta_ast, metadata)

      # Check structural equivalence (ignoring line metadata)
      assert {:binary_op, _, [{:variable, _, "X"}, {:literal, _, 5}]} = meta_ast
      {:ok, meta_ast2, _} = ToMeta.transform(ast2)
      assert {:binary_op, _, [{:variable, _, "X"}, {:literal, _, 5}]} = meta_ast2
    end

    test "function call round-trips" do
      source = "foo(1, 2)."
      {:ok, ast} = ErlangAdapter.parse(source)
      {:ok, meta_ast, metadata} = ToMeta.transform(ast)
      {:ok, ast2} = FromMeta.transform(meta_ast, metadata)

      # Check structural equivalence (ignoring line metadata)
      assert {:function_call, _, [_, _]} = meta_ast
      {:ok, meta_ast2, _} = ToMeta.transform(ast2)
      assert {:function_call, _, [_, _]} = meta_ast2
    end
  end

  describe "to_meta/1 enrichment" do
    test "enriches function calls through Enricher pipeline" do
      # Remote call: lists:map(Fun, List)
      ast =
        {:call, 1, {:remote, 1, {:atom, 1, :lists}, {:atom, 1, :map}},
         [{:var, 1, :Fun}, {:var, 1, :List}]}

      {:ok, meta_ast, _metadata} = ErlangAdapter.to_meta(ast)

      # Should produce a function_call (enricher traverses without error)
      assert {:function_call, meta, [_, _]} = meta_ast
      assert Keyword.get(meta, :name) == "lists.map"
    end

    test "enrichment does not alter non-matching nodes" do
      ast = {:integer, 1, 42}
      {:ok, meta_ast, _metadata} = ErlangAdapter.to_meta(ast)

      # Literal should pass through enricher unchanged
      assert {:literal, [subtype: :integer, line: 1], 42} = meta_ast
    end

    test "enriches nested function calls in blocks" do
      # Block: foo(1), bar(2)
      ast =
        {:block,
         [
           {:call, 1, {:atom, 1, :foo}, [{:integer, 1, 1}]},
           {:call, 2, {:atom, 2, :bar}, [{:integer, 2, 2}]}
         ]}

      {:ok, meta_ast, _metadata} = ErlangAdapter.to_meta(ast)

      assert {:block, [], [call1, call2]} = meta_ast
      assert {:function_call, _, _} = call1
      assert {:function_call, _, _} = call2
    end

    test "propagates errors from ToMeta through enrichment" do
      # An unsupported structure should still return error
      result = ErlangAdapter.to_meta({:unsupported_weird_form, 1, :x, :y, :z})
      assert {:error, _} = result
    end
  end

  describe "cross-language equivalence" do
    test "same MetaAST from equivalent Elixir and Erlang code" do
      # Elixir: x + 5
      {:ok, elixir_ast} = ElixirAdapter.parse("x + 5")
      {:ok, elixir_meta, _} = ElixirToMeta.transform(elixir_ast)

      # Erlang: X + 5
      {:ok, erlang_ast} = ErlangAdapter.parse("X + 5.")
      {:ok, erlang_meta, _} = ToMeta.transform(erlang_ast)

      # Both should produce semantically equivalent MetaAST (ignoring variable name case)
      # Elixir uses lowercase 'x', Erlang uses uppercase 'X' - this is expected
      # New 3-tuple format: {:binary_op, meta, [left, right]}
      assert match?(
               {:binary_op, _, [{:variable, _, _}, {:literal, _, 5}]},
               elixir_meta
             )

      assert match?(
               {:binary_op, _, [{:variable, _, _}, {:literal, _, 5}]},
               erlang_meta
             )
    end
  end
end
