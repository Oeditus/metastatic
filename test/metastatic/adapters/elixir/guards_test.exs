defmodule Metastatic.Adapters.Elixir.GuardsTest do
  use ExUnit.Case, async: true

  alias Metastatic.Adapters.Elixir.ToMeta

  describe "Anonymous functions with guards" do
    test "transforms simple guarded anonymous function" do
      # fn x when is_integer(x) -> x * 2 end
      ast =
        {:fn, [],
         [
           {:->, [],
            [
              [{:when, [], [{:x, [], nil}, {:is_integer, [], [{:x, [], nil}]}]}],
              {:*, [], [{:x, [], nil}, 2]}
            ]}
         ]}

      assert {:ok, result, %{}} = ToMeta.transform(ast)
      # Guarded functions use match_arm structure
      assert {:match_arm, pattern, guard, body} = result
      assert {:param, "x", nil, nil} = pattern
      assert {:function_call, "is_integer", [_]} = guard
      assert {:binary_op, :arithmetic, :*, _, _} = body
    end

    test "transforms anonymous function without guard" do
      # fn x -> x + 1 end
      ast = {:fn, [], [{:->, [], [[{:x, [], nil}], {:+, [], [{:x, [], nil}, 1]}]}]}

      assert {:ok, result, %{}} = ToMeta.transform(ast)
      # Non-guarded functions use standard lambda
      assert {:lambda, params, captures, body} = result
      assert [{:param, "x", nil, nil}] = params
      assert [] = captures
      assert {:binary_op, :arithmetic, :+, _, _} = body
    end

    test "transforms multi-clause function with guards" do
      # fn
      #   x when is_integer(x) -> x * 2
      #   x when is_float(x) -> x * 2.0
      #   _ -> 0
      # end
      ast =
        {:fn, [],
         [
           {:->, [],
            [
              [{:when, [], [{:x, [], nil}, {:is_integer, [], [{:x, [], nil}]}]}],
              {:*, [], [{:x, [], nil}, 2]}
            ]},
           {:->, [],
            [
              [{:when, [], [{:x, [], nil}, {:is_float, [], [{:x, [], nil}]}]}],
              {:*, [], [{:x, [], nil}, 2.0]}
            ]},
           {:->, [], [[{:_, [], nil}], 0]}
         ]}

      assert {:ok, result, %{clauses: clauses}} = ToMeta.transform(ast)
      # Multi-clause functions are language_specific
      assert {:language_specific, :elixir, _, :multi_clause_fn} = result
      # First two clauses have guards
      assert [first, second, third] = clauses
      assert {:match_arm, {:param, "x", nil, nil}, {:function_call, "is_integer", _}, _} = first
      assert {:match_arm, {:param, "x", nil, nil}, {:function_call, "is_float", _}, _} = second
      # Third clause has no guard
      assert {:lambda, _, _, _} = third
    end

    test "transforms guard with multiple conditions" do
      # fn x when is_integer(x) and x > 0 -> x end
      ast =
        {:fn, [],
         [
           {:->, [],
            [
              [
                {:when, [],
                 [
                   {:x, [], nil},
                   {:and, [],
                    [
                      {:is_integer, [], [{:x, [], nil}]},
                      {:>, [], [{:x, [], nil}, 0]}
                    ]}
                 ]}
              ],
              {:x, [], nil}
            ]}
         ]}

      assert {:ok, result, %{}} = ToMeta.transform(ast)
      assert {:match_arm, pattern, guard, _body} = result
      assert {:param, "x", nil, nil} = pattern
      # Guard should be a boolean operation combining two conditions
      assert {:binary_op, :boolean, :and, _, _} = guard
    end

    test "transforms guarded function with multiple parameters" do
      # fn x, y when is_integer(x) and is_integer(y) -> x + y end
      ast =
        {:fn, [],
         [
           {:->, [],
            [
              [
                {:when, [],
                 [
                   [{:x, [], nil}, {:y, [], nil}],
                   {:and, [],
                    [
                      {:is_integer, [], [{:x, [], nil}]},
                      {:is_integer, [], [{:y, [], nil}]}
                    ]}
                 ]}
              ],
              {:+, [], [{:x, [], nil}, {:y, [], nil}]}
            ]}
         ]}

      assert {:ok, result, %{}} = ToMeta.transform(ast)
      assert {:match_arm, pattern, guard, _body} = result
      # Multiple params become a tuple pattern
      assert {:tuple, [param_x, param_y]} = pattern
      assert {:param, "x", nil, nil} = param_x
      assert {:param, "y", nil, nil} = param_y
      assert {:binary_op, :boolean, :and, _, _} = guard
    end
  end
end
