defmodule Metastatic.Adapters.ErlangTest do
  use ExUnit.Case, async: true

  alias Metastatic.Adapters.Erlang, as: ErlangAdapter
  alias Metastatic.Adapters.Erlang.{ToMeta, FromMeta}

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
      assert {:ok, {:literal, :integer, 42}, %{}} = ToMeta.transform({:integer, 1, 42})
    end

    test "transforms float literals" do
      assert {:ok, {:literal, :float, 3.14}, %{}} = ToMeta.transform({:float, 1, 3.14})
    end

    test "transforms string literals" do
      assert {:ok, {:literal, :string, "hello"}, %{}} = ToMeta.transform({:string, 1, ~c"hello"})
    end

    test "transforms boolean literals" do
      assert {:ok, {:literal, :boolean, true}, %{}} = ToMeta.transform({:atom, 1, true})
      assert {:ok, {:literal, :boolean, false}, %{}} = ToMeta.transform({:atom, 1, false})
    end

    test "transforms nil" do
      assert {:ok, {:literal, :null, nil}, %{}} = ToMeta.transform({:atom, 1, nil})
    end

    test "transforms undefined" do
      assert {:ok, {:literal, :null, nil}, %{erlang_atom: :undefined}} =
               ToMeta.transform({:atom, 1, :undefined})
    end

    test "transforms atoms as symbols" do
      assert {:ok, {:literal, :symbol, :atom}, %{}} = ToMeta.transform({:atom, 1, :atom})
    end
  end

  describe "ToMeta - variables" do
    test "transforms variable references" do
      assert {:ok, {:variable, "X"}, %{line: 1}} = ToMeta.transform({:var, 1, :X})
    end
  end

  describe "ToMeta - binary operators" do
    test "transforms arithmetic addition" do
      ast = {:op, 1, :+, {:var, 1, :X}, {:integer, 1, 5}}
      assert {:ok, {:binary_op, :arithmetic, :+, left, right}, %{}} = ToMeta.transform(ast)
      assert {:variable, "X"} = left
      assert {:literal, :integer, 5} = right
    end

    test "transforms comparison operators" do
      ast = {:op, 1, :==, {:integer, 1, 1}, {:integer, 1, 2}}
      assert {:ok, {:binary_op, :comparison, :==, _, _}, %{}} = ToMeta.transform(ast)
    end

    test "normalizes Erlang-specific comparison operators" do
      ast = {:op, 1, :"/=", {:integer, 1, 1}, {:integer, 1, 2}}
      assert {:ok, {:binary_op, :comparison, :!=, _, _}, %{}} = ToMeta.transform(ast)
    end

    test "transforms boolean operators" do
      ast = {:op, 1, :andalso, {:atom, 1, true}, {:atom, 1, false}}

      assert {:ok, {:binary_op, :boolean, :and, _, _}, %{erlang_op: :andalso}} =
               ToMeta.transform(ast)
    end
  end

  describe "ToMeta - unary operators" do
    test "transforms logical not" do
      ast = {:op, 1, :not, {:atom, 1, true}}
      assert {:ok, {:unary_op, :boolean, :not, operand}, %{}} = ToMeta.transform(ast)
      assert {:literal, :boolean, true} = operand
    end

    test "transforms negation" do
      ast = {:op, 1, :-, {:integer, 1, 42}}
      assert {:ok, {:unary_op, :arithmetic, :-, operand}, %{}} = ToMeta.transform(ast)
      assert {:literal, :integer, 42} = operand
    end
  end

  describe "ToMeta - function calls" do
    test "transforms local function calls" do
      ast = {:call, 1, {:atom, 1, :foo}, [{:integer, 1, 1}, {:integer, 1, 2}]}
      assert {:ok, {:function_call, "foo", args}, %{}} = ToMeta.transform(ast)
      assert [_, _] = args
    end

    test "transforms remote function calls" do
      ast =
        {:call, 1, {:remote, 1, {:atom, 1, :lists}, {:atom, 1, :map}},
         [{:atom, 1, :fun}, {nil, 1}]}

      assert {:ok, {:function_call, "lists.map", _args}, %{call_type: :remote}} =
               ToMeta.transform(ast)
    end
  end

  describe "FromMeta - literals" do
    test "transforms integer literals back" do
      assert {:ok, {:integer, 0, 42}} = FromMeta.transform({:literal, :integer, 42}, %{})
    end

    test "transforms string literals back" do
      assert {:ok, {:string, 0, ~c"hello"}} =
               FromMeta.transform({:literal, :string, "hello"}, %{})
    end

    test "transforms boolean literals back" do
      assert {:ok, {:atom, 0, true}} = FromMeta.transform({:literal, :boolean, true}, %{})
    end
  end

  describe "FromMeta - variables" do
    test "transforms variables back" do
      assert {:ok, {:var, 0, :X}} = FromMeta.transform({:variable, "X"}, %{})
    end
  end

  describe "FromMeta - binary operators" do
    test "transforms arithmetic operators back" do
      meta_ast = {:binary_op, :arithmetic, :+, {:variable, "X"}, {:literal, :integer, 5}}

      assert {:ok, {:op, 0, :+, {:var, 0, :X}, {:integer, 0, 5}}} =
               FromMeta.transform(meta_ast, %{})
    end

    test "denormalizes comparison operators" do
      meta_ast = {:binary_op, :comparison, :!=, {:literal, :integer, 1}, {:literal, :integer, 2}}
      assert {:ok, {:op, 0, :"/=", _, _}} = FromMeta.transform(meta_ast, %{})
    end
  end

  describe "FromMeta - function calls" do
    test "transforms local function calls back" do
      meta_ast = {:function_call, "foo", [{:literal, :integer, 1}, {:literal, :integer, 2}]}

      assert {:ok, {:call, 0, {:atom, 0, :foo}, [{:integer, 0, 1}, {:integer, 0, 2}]}} =
               FromMeta.transform(meta_ast, %{})
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

      # Check semantic equivalence
      {:ok, meta_ast2, _} = ToMeta.transform(ast2)
      assert meta_ast == meta_ast2
    end

    test "function call round-trips" do
      source = "foo(1, 2)."
      {:ok, ast} = ErlangAdapter.parse(source)
      {:ok, meta_ast, metadata} = ToMeta.transform(ast)
      {:ok, ast2} = FromMeta.transform(meta_ast, metadata)

      {:ok, meta_ast2, _} = ToMeta.transform(ast2)
      assert meta_ast == meta_ast2
    end
  end

  describe "cross-language equivalence" do
    test "same MetaAST from equivalent Elixir and Erlang code" do
      # Elixir: x + 5
      {:ok, elixir_ast} = Metastatic.Adapters.Elixir.parse("x + 5")
      {:ok, elixir_meta, _} = Metastatic.Adapters.Elixir.ToMeta.transform(elixir_ast)

      # Erlang: X + 5
      {:ok, erlang_ast} = ErlangAdapter.parse("X + 5.")
      {:ok, erlang_meta, _} = ToMeta.transform(erlang_ast)

      # Both should produce semantically equivalent MetaAST (ignoring variable name case)
      # Elixir uses lowercase 'x', Erlang uses uppercase 'X' - this is expected
      assert {:binary_op, :arithmetic, :+, {:variable, _}, {:literal, :integer, 5}} = elixir_meta
      assert {:binary_op, :arithmetic, :+, {:variable, _}, {:literal, :integer, 5}} = erlang_meta
    end
  end
end
