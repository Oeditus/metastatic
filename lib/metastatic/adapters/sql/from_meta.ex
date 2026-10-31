defmodule Metastatic.Adapters.SQL.FromMeta do
  @moduledoc """
  Transform MetaAST (M2) back to SQL AST for `sqlparser-rs` (M1).

  Reifies universal AST nodes back into native SQL AST structures.
  If an `original_ast` entry exists in metadata, it is preserved for 100% round-trip fidelity.
  """

  @doc """
  Transform MetaAST back to SQL AST map or list.

  Returns `{:ok, sql_ast}` on success or `{:error, reason}` on failure.
  """
  @spec transform(term(), map()) :: {:ok, term()} | {:error, String.t()}
  def transform(meta_ast, metadata \\ %{})

  def transform({:language_specific, meta, native_ast}, _metadata) when is_list(meta) do
    {:ok, native_ast}
  end

  def transform({type, meta, children}, metadata) when is_list(meta) do
    if Keyword.has_key?(meta, :original_ast) do
      {:ok, Keyword.get(meta, :original_ast)}
    else
      transform_node(type, meta, children, metadata)
    end
  end

  def transform(other, _metadata) do
    {:error, "Cannot reify MetaAST to SQL: #{inspect(other)}"}
  end

  # ----- Node Transformers -----

  # Literals
  defp transform_node(:literal, _meta, value, _metadata) do
    val_map =
      cond do
        is_integer(value) ->
          %{"Number" => ["#{value}", false]}

        is_float(value) ->
          %{"Number" => ["#{value}", false]}

        is_binary(value) ->
          %{"SingleQuotedString" => value}

        is_boolean(value) ->
          %{"Boolean" => value}

        is_nil(value) ->
          "Null"

        true ->
          %{"SingleQuotedString" => to_string(value)}
      end

    {:ok, %{"Expr" => %{"Value" => %{"value" => val_map}}}}
  end

  # Variables / Identifiers
  defp transform_node(:variable, _meta, "*", _metadata) do
    {:ok, %{"Expr" => %{"Wildcard" => nil}}}
  end

  defp transform_node(:variable, _meta, name, _metadata) do
    {:ok, %{"Expr" => %{"Identifier" => %{"value" => to_string(name), "quote_style" => nil}}}}
  end

  # Compound Identifier: table.column
  defp transform_node(:attribute_access, meta, [{:variable, _, table}], _metadata) do
    field = Keyword.get(meta, :field, "col")

    idents = [
      %{"Identifier" => %{"value" => to_string(table), "quote_style" => nil}},
      %{"Identifier" => %{"value" => to_string(field), "quote_style" => nil}}
    ]

    {:ok, %{"Expr" => %{"CompoundIdentifier" => idents}}}
  end

  # Binary Operations
  defp transform_node(:binary_op, meta, [left, right], metadata) do
    operator = Keyword.get(meta, :operator, :==)

    with {:ok, left_res} <- transform(left, metadata),
         {:ok, right_res} <- transform(right, metadata) do
      op_str = map_binary_operator_to_sql(operator)

      expr_map = %{
        "BinaryOp" => %{
          "left" => unwrap_expr(left_res),
          "op" => op_str,
          "right" => unwrap_expr(right_res)
        }
      }

      {:ok, %{"Expr" => expr_map}}
    end
  end

  # Unary Operations
  defp transform_node(:unary_op, meta, [child], metadata) do
    operator = Keyword.get(meta, :operator, :not)

    with {:ok, child_res} <- transform(child, metadata) do
      op_str = map_unary_operator_to_sql(operator)

      expr_map = %{
        "UnaryOp" => %{
          "op" => op_str,
          "expr" => unwrap_expr(child_res)
        }
      }

      {:ok, %{"Expr" => expr_map}}
    end
  end

  # Blocks (list of statements)
  defp transform_node(:block, _meta, stmts, metadata) when is_list(stmts) do
    results =
      Enum.reduce_while(stmts, {:ok, []}, fn stmt, {:ok, acc} ->
        case transform(stmt, metadata) do
          {:ok, s} -> {:cont, {:ok, [unwrap_statement(s) | acc]}}
          error -> {:halt, error}
        end
      end)

    case results do
      {:ok, list} -> {:ok, Enum.reverse(list)}
      error -> error
    end
  end

  # Function Calls & Synthesized Statements
  defp transform_node(:function_call, meta, args, metadata) do
    name = Keyword.get(meta, :name, "func")

    case String.upcase(name) do
      "SELECT" ->
        table_name = Keyword.get(meta, :table, "table")
        table_idents = [%{"Identifier" => %{"value" => table_name, "quote_style" => nil}}]

        projections =
          case args do
            [] ->
              [%{"UnnamedExpr" => %{"Wildcard" => nil}}]

            list ->
              Enum.map(list, fn arg ->
                case transform(arg, metadata) do
                  {:ok, res} -> %{"UnnamedExpr" => unwrap_expr(res)}
                  _ -> %{"UnnamedExpr" => %{"Wildcard" => nil}}
                end
              end)
          end

        stmt = %{
          "Query" => %{
            "with" => nil,
            "body" => %{
              "Select" => %{
                "distinct" => nil,
                "top" => nil,
                "projection" => projections,
                "into" => nil,
                "from" => [
                  %{
                    "relation" => %{
                      "Table" => %{
                        "name" => table_idents,
                        "alias" => nil,
                        "args" => nil,
                        "with_hints" => []
                      }
                    },
                    "joins" => []
                  }
                ],
                "lateral_views" => [],
                "selection" => nil,
                "group_by" => %{"Expressions" => [[], []]},
                "cluster_by" => [],
                "distribute_by" => [],
                "sort_by" => [],
                "having" => nil,
                "named_window" => [],
                "qualify" => nil
              }
            },
            "order_by" => nil,
            "limit_clause" => nil,
            "fetch" => nil,
            "locks" => []
          }
        }

        {:ok, [stmt]}

      other_func ->
        # Standard SQL function (e.g. COUNT, LOWER)
        transformed_args =
          Enum.map(args, fn arg ->
            case transform(arg, metadata) do
              {:ok, res} ->
                %{"Unnamed" => %{"Expr" => unwrap_expr(res)}}

              _ ->
                %{"Unnamed" => %{"Expr" => %{"Wildcard" => nil}}}
            end
          end)

        func_map = %{
          "Function" => %{
            "name" => [%{"Identifier" => %{"value" => other_func, "quote_style" => nil}}],
            "args" => %{"List" => %{"args" => transformed_args}},
            "over" => nil,
            "filter" => nil,
            "null_treatment" => nil,
            "within_group" => []
          }
        }

        {:ok, %{"Expr" => func_map}}
    end
  end

  defp transform_node(type, _meta, _children, _metadata) do
    {:error, "Unsupported MetaAST type for SQL reification: #{inspect(type)}"}
  end

  # ----- Helpers -----

  def unwrap_expr(%{"Expr" => inner}), do: inner
  def unwrap_expr(other), do: other

  def unwrap_statement([stmt]), do: stmt
  def unwrap_statement(stmt), do: stmt

  defp map_binary_operator_to_sql(op) do
    case op do
      :+ -> "Plus"
      :- -> "Minus"
      :* -> "Multiply"
      :/ -> "Divide"
      :% -> "Modulo"
      :== -> "Eq"
      :!= -> "NotEq"
      :> -> "Gt"
      :>= -> "GtEq"
      :< -> "Lt"
      :<= -> "LtEq"
      :and -> "And"
      :or -> "Or"
      :like -> "Like"
      :ilike -> "ILike"
      _ -> "Eq"
    end
  end

  defp map_unary_operator_to_sql(op) do
    case op do
      :not -> "Not"
      :- -> "Minus"
      :+ -> "Plus"
      _ -> "Plus"
    end
  end
end
