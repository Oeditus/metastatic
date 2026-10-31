defmodule Metastatic.Adapters.SQL.ToMetaTest do
  use ExUnit.Case, async: true

  alias Metastatic.Adapters.SQL.ToMeta

  doctest ToMeta

  @unknown %{"UnsupportedExpression" => %{"value" => "preserved"}}
  @native_node {:language_specific, [language: :sql, hint: :expr], @unknown}

  test "preserves unsupported expressions and raw statement maps" do
    assert {:ok, @native_node} = ToMeta.transform_expr(@unknown)
    assert {:ok, @native_node, %{}} = ToMeta.transform(@unknown)
    assert {:ok, @native_node, %{}} = ToMeta.transform(%{"Expr" => @unknown})
  end

  test "preserves unsupported projections and WHERE expressions" do
    statement = %{
      "Query" => %{
        "body" => %{"Select" => %{"projection" => [@unknown], "selection" => @unknown}}
      }
    }

    assert {:ok, {:function_call, _, [@native_node, @native_node]}, %{}} =
             ToMeta.transform(statement)
  end

  test "preserves unsupported assignment values" do
    statement = %{
      "Update" => %{
        "assignments" => [
          %{"target" => %{"ColumnName" => ["name"]}, "value" => @unknown}
        ]
      }
    }

    assert {:ok, {:function_call, _, [{:assignment, [name: "name"], [@native_node]}]}, %{}} =
             ToMeta.transform(statement)
  end

  test "preserves unsupported function arguments" do
    expression = %{"Function" => %{"name" => ["custom"], "args" => [@unknown]}}

    assert {:ok, {:function_call, [name: "custom"], [@native_node]}} =
             ToMeta.transform_expr(expression)
  end

  test "preserves unsupported IN list items" do
    expression = %{
      "InList" => %{
        "expr" => %{"Identifier" => %{"value" => "id"}},
        "list" => [@unknown],
        "negated" => false
      }
    }

    assert {:ok,
            {:binary_op, [category: :comparison, operator: :in],
             [{:variable, [scope: :local], "id"}, {:list, [], [@native_node]}]}} =
             ToMeta.transform_expr(expression)
  end

  test "preserves unsupported INSERT values" do
    statement = %{
      "Insert" => %{
        "source" => %{"body" => %{"Values" => %{"rows" => [%{"content" => [@unknown]}]}}}
      }
    }

    assert {:ok,
            {:function_call, _,
             [
               {:list, [hint: :columns], []},
               {:list, [hint: :values], [{:list, [], [@native_node]}]}
             ]}, %{}} = ToMeta.transform(statement)
  end

  test "still rejects unsupported top-level values and propagates statement errors" do
    assert {:error, "Unsupported SQL AST: :invalid"} = ToMeta.transform(:invalid)
    assert {:error, "Unsupported SQL AST: :invalid"} = ToMeta.transform([@unknown, :invalid])
  end
end
