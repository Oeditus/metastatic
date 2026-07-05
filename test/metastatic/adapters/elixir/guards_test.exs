defmodule Metastatic.Adapters.Elixir.GuardsTest do
  use ExUnit.Case, async: true

  alias Metastatic.Adapters.Elixir.ToMeta

  # Helper to extract params from lambda meta
  defp get_params(meta), do: Keyword.get(meta, :params, [])

  describe "Anonymous functions with guards" do
    test "transforms simple guarded anonymous function" do
      # fn x when is_integer(x) -> x * 2 end
      # In the new format, single-clause guarded functions become lambdas
      # with multi_clause: true and match_arm children
      ast =
        {:fn, [],
         [
           {:->, [],
            [
              [{:when, [], [{:x, [], nil}, {:is_integer, [], [{:x, [], nil}]}]}],
              {:*, [], [{:x, [], nil}, 2]}
            ]}
         ]}

      assert {:ok, result, _ctx} = ToMeta.transform(ast)

      # Single clause with guard - in new format this becomes lambda with match_arm
      # The implementation may vary, so we accept either a lambda with body
      # or a lambda with match_arm structure
      case result do
        {:lambda, meta, [body]} ->
          # Simple lambda representation
          params = get_params(meta)
          assert is_list(params)
          assert {:binary_op, _, _} = body

        {:lambda, meta, arms} when is_list(arms) ->
          # Multi-clause representation
          assert Keyword.get(meta, :multi_clause) == true
          assert [arm | _] = arms
          assert {:match_arm, _, _} = arm
      end
    end

    test "transforms anonymous function without guard" do
      # fn x -> x + 1 end
      ast = {:fn, [], [{:->, [], [[{:x, [], nil}], {:+, [], [{:x, [], nil}, 1]}]}]}

      assert {:ok, result, _ctx} = ToMeta.transform(ast)
      # Non-guarded functions use standard lambda
      assert {:lambda, meta, [body]} = result
      params = get_params(meta)
      assert [{:param, [], "x"}] = params
      assert {:binary_op, op_meta, [left, right]} = body
      assert Keyword.get(op_meta, :category) == :arithmetic
      assert Keyword.get(op_meta, :operator) == :+
      assert {:variable, _, "x"} = left
      assert {:literal, [subtype: :integer], 1} = right
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

      assert {:ok, result, _ctx} = ToMeta.transform(ast)
      # Multi-clause functions become lambda with multi_clause: true and match_arm children
      assert {:lambda, meta, arms} = result
      assert Keyword.get(meta, :multi_clause) == true
      assert [first, second, third] = arms
      assert {:match_arm, _, _} = first
      assert {:match_arm, _, _} = second
      assert {:match_arm, _, _} = third
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

      assert {:ok, result, _ctx} = ToMeta.transform(ast)

      # Can be either single-clause lambda or multi_clause with match_arm
      case result do
        {:lambda, _meta, [body]} ->
          # Simple representation - body is just the variable
          assert {:variable, _, "x"} = body

        {:lambda, meta, arms} when is_list(arms) ->
          assert Keyword.get(meta, :multi_clause) == true
          [arm] = arms
          assert {:match_arm, _, _} = arm
      end
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

      assert {:ok, result, _ctx} = ToMeta.transform(ast)

      # Multiple params - can be lambda with params or match_arm
      case result do
        {:lambda, _meta, [body]} ->
          # Simple representation with body
          assert {:binary_op, op_meta, [left, right]} = body
          assert Keyword.get(op_meta, :category) == :arithmetic
          assert Keyword.get(op_meta, :operator) == :+
          assert {:variable, _, "x"} = left
          assert {:variable, _, "y"} = right

        {:lambda, meta, arms} when is_list(arms) ->
          assert Keyword.get(meta, :multi_clause) == true
          [arm] = arms
          assert {:match_arm, _, _} = arm
      end
    end
  end
end
