defmodule Metastatic.Adapters.Elixir.CapturesTest do
  use ExUnit.Case, async: true

  alias Metastatic.Adapters.Elixir.ToMeta

  describe "Function captures - simple argument references" do
    test "transforms &1 to lambda returning first argument" do
      ast = {:&, [], [1]}

      assert {:ok, {:lambda, params, [], body}, metadata} = ToMeta.transform(ast)
      assert [{:param, "arg_1", nil, nil}] = params
      assert {:variable, "arg_1"} = body
      assert metadata.capture_form == :argument_reference
    end

    test "transforms &2 to lambda returning second argument" do
      ast = {:&, [], [2]}

      assert {:ok, {:lambda, params, [], body}, metadata} = ToMeta.transform(ast)
      assert [{:param, "arg_2", nil, nil}] = params
      assert {:variable, "arg_2"} = body
      assert metadata.capture_form == :argument_reference
    end

    test "transforms &3 to lambda returning third argument" do
      ast = {:&, [], [3]}

      assert {:ok, {:lambda, params, [], body}, _metadata} = ToMeta.transform(ast)
      assert [{:param, "arg_3", nil, nil}] = params
      assert {:variable, "arg_3"} = body
    end
  end

  describe "Function captures - named function references" do
    test "transforms &Integer.parse/1 to lambda calling Integer.parse" do
      # &Integer.parse/1
      ast = {:&, [], [{:/, [], [{{:., [], [{:__aliases__, [], [:Integer]}, :parse]}, [], []}, 1]}]}

      assert {:ok, {:lambda, params, [], body}, metadata} = ToMeta.transform(ast)
      assert [{:param, "arg_1", nil, nil}] = params
      assert {:function_call, "Integer.parse", [arg]} = body
      assert {:variable, "arg_1"} = arg
      assert metadata.capture_form == :named_function
    end

    test "transforms &Enum.map/2 to lambda calling Enum.map" do
      # &Enum.map/2
      ast = {:&, [], [{:/, [], [{{:., [], [{:__aliases__, [], [:Enum]}, :map]}, [], []}, 2]}]}

      assert {:ok, {:lambda, params, [], body}, _metadata} = ToMeta.transform(ast)
      assert [_, _] = params
      assert [{:param, "arg_1", nil, nil}, {:param, "arg_2", nil, nil}] = params
      assert {:function_call, "Enum.map", args} = body
      assert [_, _] = args
    end

    test "transforms &String.upcase/1 to lambda calling String.upcase" do
      # &String.upcase/1
      ast = {:&, [], [{:/, [], [{{:., [], [{:__aliases__, [], [:String]}, :upcase]}, [], []}, 1]}]}

      assert {:ok, {:lambda, params, [], body}, _metadata} = ToMeta.transform(ast)
      assert [{:param, "arg_1", nil, nil}] = params
      assert {:function_call, "String.upcase", _args} = body
    end
  end

  describe "Function captures - expression captures" do
    test "transforms &(&1 + 1) to lambda with addition" do
      # &(&1 + 1)
      ast = {:&, [], [{:+, [], [{:&, [], [1]}, 1]}]}

      assert {:ok, {:lambda, params, [], body}, metadata} = ToMeta.transform(ast)
      assert [{:param, "arg_1", nil, nil}] = params
      assert {:binary_op, :arithmetic, :+, left, right} = body
      assert {:variable, "arg_1"} = left
      assert {:literal, :integer, 1} = right
      assert metadata.capture_form == :expression
      assert metadata.arity == 1
    end

    test "transforms &(&1 + &2) to binary lambda" do
      # &(&1 + &2)
      ast = {:&, [], [{:+, [], [{:&, [], [1]}, {:&, [], [2]}]}]}

      assert {:ok, {:lambda, params, [], body}, metadata} = ToMeta.transform(ast)
      assert [_, _] = params
      assert [{:param, "arg_1", nil, nil}, {:param, "arg_2", nil, nil}] = params
      assert {:binary_op, :arithmetic, :+, left, right} = body
      assert {:variable, "arg_1"} = left
      assert {:variable, "arg_2"} = right
      assert metadata.arity == 2
    end

    test "transforms &(&1 * 2 + &2) to complex expression" do
      # &(&1 * 2 + &2)
      ast = {:&, [], [{:+, [], [{:*, [], [{:&, [], [1]}, 2]}, {:&, [], [2]}]}]}

      assert {:ok, {:lambda, params, [], body}, metadata} = ToMeta.transform(ast)
      assert [_, _] = params
      # Body should be: (&1 * 2) + &2
      assert {:binary_op, :arithmetic, :+, left_side, right_side} = body
      assert {:binary_op, :arithmetic, :*, _, _} = left_side
      assert {:variable, "arg_2"} = right_side
      assert metadata.arity == 2
    end

    test "transforms &String.upcase(&1) to function call with capture" do
      # &String.upcase(&1)
      ast = {:&, [], [{{:., [], [{:__aliases__, [], [:String]}, :upcase]}, [], [{:&, [], [1]}]}]}

      assert {:ok, {:lambda, params, [], body}, metadata} = ToMeta.transform(ast)
      assert [{:param, "arg_1", nil, nil}] = params
      assert {:function_call, "String.upcase", args} = body
      assert [arg] = args
      assert {:variable, "arg_1"} = arg
      assert metadata.capture_form == :expression
      assert metadata.arity == 1
    end

    test "transforms &elem(&1, 0) to function call" do
      # &elem(&1, 0)
      ast = {:&, [], [{:elem, [], [{:&, [], [1]}, 0]}]}

      assert {:ok, {:lambda, params, [], body}, _metadata} = ToMeta.transform(ast)
      assert [{:param, "arg_1", nil, nil}] = params
      assert {:function_call, "elem", args} = body
      assert [_, _] = args
    end

    test "transforms &(&1 > 0) to comparison" do
      # &(&1 > 0)
      ast = {:&, [], [{:>, [], [{:&, [], [1]}, 0]}]}

      assert {:ok, {:lambda, params, [], body}, _metadata} = ToMeta.transform(ast)
      assert [{:param, "arg_1", nil, nil}] = params
      assert {:binary_op, :comparison, :>, left, right} = body
      assert {:variable, "arg_1"} = left
      assert {:literal, :integer, 0} = right
    end
  end

  describe "Function captures - arity detection" do
    test "detects arity 1 from single &1 reference" do
      ast = {:&, [], [{:+, [], [{:&, [], [1]}, 10]}]}
      assert {:ok, {:lambda, params, [], _body}, metadata} = ToMeta.transform(ast)
      assert length(params) == 1
      assert metadata.arity == 1
    end

    test "detects arity 2 from &1 and &2 references" do
      ast = {:&, [], [{:+, [], [{:&, [], [1]}, {:&, [], [2]}]}]}
      assert {:ok, {:lambda, params, [], _body}, metadata} = ToMeta.transform(ast)
      assert length(params) == 2
      assert metadata.arity == 2
    end

    test "detects arity 3 when &3 is the highest" do
      # &(&1 + &2 + &3)
      ast = {:&, [], [{:+, [], [{:+, [], [{:&, [], [1]}, {:&, [], [2]}]}, {:&, [], [3]}]}]}
      assert {:ok, {:lambda, params, [], _body}, metadata} = ToMeta.transform(ast)
      assert length(params) == 3
      assert metadata.arity == 3
    end

    test "creates params for all numbers up to max even if some are unused" do
      # &(&1 + &3) - note: &2 is not used but param should still be created
      ast = {:&, [], [{:+, [], [{:&, [], [1]}, {:&, [], [3]}]}]}
      assert {:ok, {:lambda, params, [], _body}, metadata} = ToMeta.transform(ast)
      # Should create params for arg_1, arg_2, arg_3
      assert length(params) == 3
      assert [{:param, "arg_1", nil, nil}, {:param, "arg_2", nil, nil}, {:param, "arg_3", nil, nil}] = params
      assert metadata.arity == 3
    end
  end

  describe "Function captures - complex cases" do
    test "transforms &Map.get(&1, :key) with atom literal" do
      # &Map.get(&1, :key)
      ast = {:&, [], [{{:., [], [{:__aliases__, [], [:Map]}, :get]}, [], [{:&, [], [1]}, :key]}]}

      assert {:ok, {:lambda, params, [], body}, _metadata} = ToMeta.transform(ast)
      assert [{:param, "arg_1", nil, nil}] = params
      assert {:function_call, "Map.get", args} = body
      assert [var, key] = args
      assert {:variable, "arg_1"} = var
      assert {:literal, :symbol, :key} = key
    end

    test "transforms &{&1, &2} to tuple creation" do
      # &{&1, &2}
      # In Elixir AST, {&1, &2} within a capture
      ast = {:&, [], [{{:&, [], [1]}, {:&, [], [2]}}]}

      assert {:ok, {:lambda, params, [], body}, metadata} = ToMeta.transform(ast)
      assert [_, _] = params
      assert {:tuple, elements} = body
      assert [_, _] = elements
      assert metadata.arity == 2
    end

    test "transforms &[&1, &2, &3] to list creation" do
      # &[&1, &2, &3]
      ast = {:&, [], [[{:&, [], [1]}, {:&, [], [2]}, {:&, [], [3]}]]}

      assert {:ok, {:lambda, params, [], body}, metadata} = ToMeta.transform(ast)
      assert length(params) == 3
      assert {:list, elements} = body
      assert [_, _, _] = elements
      assert metadata.arity == 3
    end
  end

  describe "Function captures - edge cases" do
    test "handles capture with no argument references (though unusual)" do
      # &(1 + 2) - no &1, &2, etc.
      ast = {:&, [], [{:+, [], [1, 2]}]}

      assert {:ok, {:lambda, params, [], body}, metadata} = ToMeta.transform(ast)
      # Should create zero-arity lambda
      assert [] = params
      assert {:binary_op, :arithmetic, :+, _, _} = body
      assert metadata.capture_form == :no_arguments
    end

    test "handles nested function calls in capture" do
      # &String.length(String.upcase(&1))
      inner_call = {{:., [], [{:__aliases__, [], [:String]}, :upcase]}, [], [{:&, [], [1]}]}
      ast = {:&, [], [{{:., [], [{:__aliases__, [], [:String]}, :length]}, [], [inner_call]}]}

      assert {:ok, {:lambda, params, [], body}, _metadata} = ToMeta.transform(ast)
      assert [{:param, "arg_1", nil, nil}] = params
      assert {:function_call, "String.length", [inner]} = body
      assert {:function_call, "String.upcase", _} = inner
    end
  end
end
