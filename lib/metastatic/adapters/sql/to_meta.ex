defmodule Metastatic.Adapters.SQL.ToMeta do
  @moduledoc """
  Transform SQL AST from `sqlparser-rs` (M1) to MetaAST (M2).

  Transforms statements, expressions, operators, and literals into uniform
  MetaAST 3-tuples: `{type_atom, keyword_meta, children_or_value}`.

  Enriches queries with `op_kind` semantic metadata in the `:db` domain:
  - `:query` - Complex queries with WHERE conditions
  - `:retrieve_all` - SELECT without filter
  - `:aggregate` - Queries containing aggregate functions (COUNT, SUM, AVG, etc.)
  - `:create` - INSERT statements
  - `:update` - UPDATE statements
  - `:delete` - DELETE statements
  """

  @doc """
  Transform SQL AST (map or list) to MetaAST.

  Returns `{:ok, meta_ast, metadata}` on success or `{:error, reason}` on failure.
  """
  @spec transform(term(), keyword()) :: {:ok, term(), map()} | {:error, String.t()}
  def transform(ast, opts \\ [])

  # List of statements (top-level program or multiple statements)
  def transform(statements, opts) when is_list(statements) do
    case statements do
      [] ->
        {:ok, {:block, [], []}, %{}}

      [single] ->
        transform(single, opts)

      multiple ->
        results =
          Enum.reduce_while(multiple, {:ok, []}, fn stmt, {:ok, acc} ->
            case transform(stmt, opts) do
              {:ok, meta, _} -> {:cont, {:ok, [meta | acc]}}
              error -> {:halt, error}
            end
          end)

        case results do
          {:ok, list} -> {:ok, {:block, [], Enum.reverse(list)}, %{}}
          error -> error
        end
    end
  end

  # Wrapped standalone expression {"Expr" => expr}
  def transform(%{"Expr" => expr}, _opts) do
    with {:ok, meta_node} <- transform_expr(expr) do
      {:ok, meta_node, %{}}
    end
  end

  # Single statement maps
  def transform(%{"Query" => query} = statement, _opts) do
    with {:ok, meta_node} <- transform_query(query, statement) do
      {:ok, meta_node, %{}}
    end
  end

  def transform(%{"Insert" => insert} = statement, _opts) do
    with {:ok, meta_node} <- transform_insert(insert, statement) do
      {:ok, meta_node, %{}}
    end
  end

  def transform(%{"Update" => update} = statement, _opts) do
    with {:ok, meta_node} <- transform_update(update, statement) do
      {:ok, meta_node, %{}}
    end
  end

  def transform(%{"Delete" => delete} = statement, _opts) do
    with {:ok, meta_node} <- transform_delete(delete, statement) do
      {:ok, meta_node, %{}}
    end
  end

  def transform(%{"CreateTable" => create_table} = statement, _opts) do
    with {:ok, meta_node} <- transform_create_table(create_table, statement) do
      {:ok, meta_node, %{}}
    end
  end

  # Fallback for unrecognized statements or raw expression maps
  def transform(node, _opts) when is_map(node) do
    {:ok, meta_node} = transform_expr(node)
    {:ok, meta_node, %{}}
  end

  def transform(other, _opts) do
    {:error, "Unsupported SQL AST: #{inspect(other)}"}
  end

  # ----- Statement Transformers -----

  defp transform_query(%{"body" => %{"Select" => select}} = _query, full_stmt) do
    table_name = extract_table_name(select["from"])
    projections = select["projection"] || []
    where_expr = select["selection"]

    is_aggregate = has_aggregate_function?(projections)
    has_where = not is_nil(where_expr)

    operation =
      cond do
        is_aggregate -> :aggregate
        has_where -> :query
        true -> :retrieve_all
      end

    op_kind = [
      domain: :db,
      operation: operation,
      target: table_name || "unknown",
      framework: :sql
    ]

    with {:ok, proj_nodes} <- transform_projections(projections),
         {:ok, where_nodes} <- transform_optional_expr(where_expr) do
      args = proj_nodes ++ where_nodes

      meta =
        [name: "SELECT", op_kind: op_kind] ++
          if(table_name, do: [table: table_name], else: []) ++
          [original_ast: full_stmt]

      {:ok, {:function_call, meta, args}}
    end
  end

  defp transform_query(query, full_stmt) do
    # Fallback for set expressions (UNION, INTERSECT, etc.)
    {:ok, {:language_specific, [language: :sql, hint: :query, original_ast: full_stmt], query}}
  end

  defp transform_insert(insert, full_stmt) do
    table_name = extract_name_from_table_factor(insert["table"])

    op_kind = [
      domain: :db,
      operation: :create,
      target: table_name || "unknown",
      framework: :sql
    ]

    columns =
      (insert["columns"] || [])
      |> Enum.flat_map(fn col_list ->
        Enum.map(col_list, fn
          %{"Identifier" => %{"value" => name}} -> {:variable, [scope: :local], name}
          _ -> {:variable, [scope: :local], "col"}
        end)
      end)

    values = extract_insert_values(insert["source"])

    args = [
      {:list, [hint: :columns], columns},
      {:list, [hint: :values], values}
    ]

    meta =
      [name: "INSERT", op_kind: op_kind] ++
        if(table_name, do: [table: table_name], else: []) ++
        [original_ast: full_stmt]

    {:ok, {:function_call, meta, args}}
  end

  defp transform_update(update, full_stmt) do
    table_name =
      case update["table"] do
        %{"relation" => %{"Table" => %{"name" => idents}}} ->
          idents_to_name(idents)

        _ ->
          nil
      end

    op_kind = [
      domain: :db,
      operation: :update,
      target: table_name || "unknown",
      framework: :sql
    ]

    assignments =
      (update["assignments"] || [])
      |> Enum.map(fn assignment ->
        target_name =
          case assignment["target"] do
            %{"ColumnName" => idents} -> idents_to_name(idents)
            _ -> "unknown"
          end

        {:ok, val_node} = transform_expr(assignment["value"])

        {:assignment, [name: target_name], [val_node]}
      end)

    with {:ok, where_nodes} <- transform_optional_expr(update["selection"]) do
      args = assignments ++ where_nodes

      meta =
        [name: "UPDATE", op_kind: op_kind] ++
          if(table_name, do: [table: table_name], else: []) ++
          [original_ast: full_stmt]

      {:ok, {:function_call, meta, args}}
    end
  end

  defp transform_delete(delete, full_stmt) do
    table_name =
      case delete["from"] do
        %{"WithFromKeyword" => [%{"relation" => %{"Table" => %{"name" => idents}}} | _]} ->
          idents_to_name(idents)

        _ ->
          nil
      end

    op_kind = [
      domain: :db,
      operation: :delete,
      target: table_name || "unknown",
      framework: :sql
    ]

    with {:ok, where_nodes} <- transform_optional_expr(delete["selection"]) do
      meta =
        [name: "DELETE", op_kind: op_kind] ++
          if(table_name, do: [table: table_name], else: []) ++
          [original_ast: full_stmt]

      {:ok, {:function_call, meta, where_nodes}}
    end
  end

  defp transform_create_table(create_table, full_stmt) do
    table_name = idents_to_name(create_table["name"])

    columns =
      (create_table["columns"] || [])
      |> Enum.map(fn col ->
        col_name = get_in(col, ["name", "value"]) || "col"
        {:variable, [scope: :local], col_name}
      end)

    op_kind = [
      domain: :db,
      operation: :create,
      target: table_name || "unknown",
      framework: :sql
    ]

    meta =
      [name: "CREATE_TABLE", op_kind: op_kind] ++
        if(table_name, do: [table: table_name], else: []) ++
        [original_ast: full_stmt]

    {:ok, {:function_call, meta, columns}}
  end

  # ----- Expression Transformers -----

  @doc """
  Transform a SQL expression, preserving unsupported forms as language-specific nodes.

  ## Examples

      iex> Metastatic.Adapters.SQL.ToMeta.transform_expr(%{"Identifier" => %{"value" => "id"}})
      {:ok, {:variable, [scope: :local], "id"}}
  """
  @spec transform_expr(term()) :: {:ok, Metastatic.AST.meta_ast()}
  def transform_expr(%{"Value" => %{"value" => val} = node}) do
    loc = extract_location(node)

    meta_node =
      case val do
        {"Number" = _tag, [num_str, _]} ->
          if String.contains?(num_str, ".") do
            case Float.parse(num_str) do
              {f, _} -> {:literal, [subtype: :float] ++ loc, f}
              :error -> {:literal, [subtype: :string] ++ loc, num_str}
            end
          else
            case Integer.parse(num_str) do
              {i, _} -> {:literal, [subtype: :integer] ++ loc, i}
              :error -> {:literal, [subtype: :string] ++ loc, num_str}
            end
          end

        %{"Number" => [num_str, _]} ->
          if String.contains?(num_str, ".") do
            case Float.parse(num_str) do
              {f, _} -> {:literal, [subtype: :float] ++ loc, f}
              :error -> {:literal, [subtype: :string] ++ loc, num_str}
            end
          else
            case Integer.parse(num_str) do
              {i, _} -> {:literal, [subtype: :integer] ++ loc, i}
              :error -> {:literal, [subtype: :string] ++ loc, num_str}
            end
          end

        %{"SingleQuotedString" => str} ->
          {:literal, [subtype: :string] ++ loc, str}

        %{"DoubleQuotedString" => str} ->
          {:literal, [subtype: :string] ++ loc, str}

        %{"Boolean" => bool} ->
          {:literal, [subtype: :boolean] ++ loc, bool}

        "Null" ->
          {:literal, [subtype: :null] ++ loc, nil}

        _ ->
          {:literal, [subtype: :string] ++ loc, inspect(val)}
      end

    {:ok, meta_node}
  end

  def transform_expr(%{"Identifier" => %{"value" => name} = node}) do
    loc = extract_location(node)
    {:ok, {:variable, [scope: :local] ++ loc, name}}
  end

  def transform_expr(%{"CompoundIdentifier" => idents}) when is_list(idents) do
    # users.id -> {:attribute_access, [field: "id"], [{:variable, [], "users"}]}
    names =
      Enum.map(idents, fn
        %{"Identifier" => %{"value" => val}} -> val
        %{"value" => val} -> val
        val when is_binary(val) -> val
        _ -> "unknown"
      end)

    case names do
      [first | rest] ->
        root = {:variable, [scope: :local], first}

        node =
          Enum.reduce(rest, root, fn field, acc ->
            {:attribute_access, [field: field], [acc]}
          end)

        {:ok, node}

      [] ->
        {:ok, {:variable, [scope: :local], "unknown"}}
    end
  end

  def transform_expr(%{"BinaryOp" => %{"left" => left, "op" => op_str, "right" => right} = node}) do
    loc = extract_location(node)

    with {:ok, left_node} <- transform_expr(left),
         {:ok, right_node} <- transform_expr(right) do
      {category, op_atom} = map_binary_op(op_str)
      {:ok, {:binary_op, [category: category, operator: op_atom] ++ loc, [left_node, right_node]}}
    end
  end

  def transform_expr(%{"UnaryOp" => %{"op" => op_str, "expr" => expr} = node}) do
    loc = extract_location(node)

    with {:ok, child_node} <- transform_expr(expr) do
      {category, op_atom} = map_unary_op(op_str)
      {:ok, {:unary_op, [category: category, operator: op_atom] ++ loc, [child_node]}}
    end
  end

  def transform_expr(%{"Function" => %{"name" => name_idents, "args" => args_obj} = node}) do
    loc = extract_location(node)
    func_name = idents_to_name(name_idents) || "func"

    args = extract_function_args(args_obj)

    transformed_args =
      Enum.map(args, fn arg ->
        {:ok, arg_node} = transform_expr(arg)
        arg_node
      end)

    {:ok, {:function_call, [name: func_name] ++ loc, transformed_args}}
  end

  def transform_expr(%{
        "InList" => %{"expr" => expr, "list" => list, "negated" => negated} = node
      }) do
    loc = extract_location(node)

    with {:ok, expr_node} <- transform_expr(expr) do
      list_items =
        Enum.map(list, fn item ->
          {:ok, item_node} = transform_expr(item)
          item_node
        end)

      op = if negated, do: :not_in, else: :in

      {:ok,
       {:binary_op, [category: :comparison, operator: op] ++ loc,
        [expr_node, {:list, [], list_items}]}}
    end
  end

  def transform_expr(%{"Wildcard" => _}) do
    {:ok, {:variable, [scope: :local], "*"}}
  end

  def transform_expr(%{"UnnamedExpr" => expr}) do
    transform_expr(expr)
  end

  def transform_expr(%{"ExprWithAlias" => %{"expr" => expr, "alias" => alias_obj}}) do
    alias_name =
      case alias_obj do
        %{"value" => val} -> val
        _ -> "alias"
      end

    with {:ok, inner_node} <- transform_expr(expr) do
      {:ok, {:assignment, [name: alias_name], [inner_node]}}
    end
  end

  def transform_expr(other) do
    {:ok, {:language_specific, [language: :sql, hint: :expr], other}}
  end

  # ----- Helpers -----

  defp transform_projections(projections) do
    nodes =
      Enum.map(projections, fn proj ->
        {:ok, node} = transform_expr(proj)
        node
      end)

    {:ok, nodes}
  end

  defp transform_optional_expr(nil), do: {:ok, []}

  defp transform_optional_expr(expr) do
    {:ok, node} = transform_expr(expr)
    {:ok, [node]}
  end

  defp extract_table_name([%{"relation" => %{"Table" => %{"name" => idents}}} | _]) do
    idents_to_name(idents)
  end

  defp extract_table_name(_), do: nil

  defp extract_name_from_table_factor(%{"TableName" => idents}), do: idents_to_name(idents)
  defp extract_name_from_table_factor(_), do: nil

  defp idents_to_name(idents) when is_list(idents) do
    idents
    |> Enum.map(fn
      %{"Identifier" => %{"value" => v}} -> v
      %{"value" => v} -> v
      v when is_binary(v) -> v
      _ -> ""
    end)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(".")
  end

  defp idents_to_name(_), do: nil

  defp has_aggregate_function?(projections) do
    Enum.any?(projections, fn
      %{"UnnamedExpr" => %{"Function" => %{"name" => name_idents}}} ->
        name = idents_to_name(name_idents) |> to_string() |> String.upcase()
        name in ["COUNT", "SUM", "AVG", "MIN", "MAX"]

      %{"Function" => %{"name" => name_idents}} ->
        name = idents_to_name(name_idents) |> to_string() |> String.upcase()
        name in ["COUNT", "SUM", "AVG", "MIN", "MAX"]

      _ ->
        false
    end)
  end

  defp extract_insert_values(%{"body" => %{"Values" => %{"rows" => rows}}}) when is_list(rows) do
    Enum.map(rows, fn
      %{"content" => content} when is_list(content) ->
        items =
          Enum.map(content, fn item ->
            {:ok, item_node} = transform_expr(item)
            item_node
          end)

        {:list, [], items}

      _ ->
        {:list, [], []}
    end)
  end

  defp extract_insert_values(_), do: []

  defp extract_function_args(%{"List" => %{"args" => args}}) when is_list(args) do
    Enum.map(args, fn
      %{"Unnamed" => %{"Expr" => expr}} -> expr
      %{"Unnamed" => expr} -> expr
      %{"Expr" => expr} -> expr
      other -> other
    end)
  end

  defp extract_function_args(args) when is_list(args), do: args
  defp extract_function_args(_), do: []

  defp map_binary_op(op) do
    case op do
      "Plus" -> {:arithmetic, :+}
      "Minus" -> {:arithmetic, :-}
      "Multiply" -> {:arithmetic, :*}
      "Divide" -> {:arithmetic, :/}
      "Modulo" -> {:arithmetic, :%}
      "Eq" -> {:comparison, :==}
      "NotEq" -> {:comparison, :!=}
      "Gt" -> {:comparison, :>}
      "GtEq" -> {:comparison, :>=}
      "Lt" -> {:comparison, :<}
      "LtEq" -> {:comparison, :<=}
      "And" -> {:boolean, :and}
      "Or" -> {:boolean, :or}
      "Like" -> {:string, :like}
      "ILike" -> {:string, :ilike}
      _ -> {:comparison, :==}
    end
  end

  defp map_unary_op(op) do
    case op do
      "Not" -> {:boolean, :not}
      "Minus" -> {:arithmetic, :-}
      "Plus" -> {:arithmetic, :+}
      _ -> {:arithmetic, :+}
    end
  end

  defp extract_location(%{"span" => %{"start" => %{"line" => line, "column" => col}}}) do
    [line: line, col: col]
  end

  defp extract_location(_), do: []
end
