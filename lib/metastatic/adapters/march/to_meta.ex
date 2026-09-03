defmodule Metastatic.Adapters.March.ToMeta do
  @moduledoc """
  Transform March AST (M1) to MetaAST (M2).

  Converts March AST JSON maps into MetaAST 3-tuples:
      {type_atom, keyword_meta, children_or_value}
  """

  @doc """
  Transform March AST node or list of nodes to MetaAST.
  """
  @spec transform(map() | list() | nil) :: {:ok, term(), map()} | {:error, String.t()}
  def transform(nil), do: {:ok, nil, %{}}

  def transform(nodes) when is_list(nodes) do
    with {:ok, transformed} <- transform_list(nodes) do
      {:ok, transformed, %{}}
    end
  end

  def transform(%{"_type" => "Program", "body" => body} = node) do
    with {:ok, statements} <- transform_list(body) do
      ast =
        case statements do
          [] -> {:block, [scope: :module], []}
          [single] -> single
          multiple -> {:block, [scope: :module], multiple}
        end

      {:ok, add_location(ast, node), %{}}
    end
  end

  def transform(%{"_type" => "Module", "name" => name, "body" => body} = node) do
    with {:ok, children} <- transform_list(body) do
      meta = [container_type: :module, subtype: :module, name: name]
      {:ok, add_location({:container, meta, children}, node), %{}}
    end
  end

  def transform(%{"_type" => "Actor", "name" => name} = node) do
    state_ast = Map.get(node, "state")
    init_ast = Map.get(node, "init")
    handlers_raw = Map.get(node, "handlers", [])

    with {:ok, transformed_handlers} <- transform_list(handlers_raw) do
      meta = [
        container_type: :actor,
        subtype: :actor,
        name: name,
        state: state_ast,
        init: init_ast
      ]

      {:ok, add_location({:container, meta, transformed_handlers}, node), %{}}
    end
  end

  def transform(%{"_type" => "OnHandler", "message" => msg_name, "body" => body} = node) do
    params_raw = Map.get(node, "params", [])
    params = Enum.map(params_raw, &transform_param/1)

    with {:ok, transformed_body} <- transform_list(body) do
      meta = [
        name: "on:#{msg_name}",
        callback_for: "on_message",
        params: params
      ]

      {:ok, add_location({:function_def, meta, transformed_body}, node), %{}}
    end
  end

  def transform(%{"_type" => "Needs", "capability" => cap} = node) do
    meta = [import_type: :needs, source: cap, capability: cap]
    {:ok, add_location({:import, meta, []}, node), %{}}
  end

  def transform(%{"_type" => "Use", "module" => mod_name} = node) do
    meta = [import_type: :use, source: mod_name]
    {:ok, add_location({:import, meta, []}, node), %{}}
  end

  def transform(%{"_type" => "FunctionDef", "name" => name, "body" => body} = node) do
    params_raw = Map.get(node, "params", [])
    params = Enum.map(params_raw, &transform_param/1)
    ret_type = Map.get(node, "return_type")
    vis = Map.get(node, "visibility")

    meta = [name: name, params: params]
    meta = if ret_type, do: Keyword.put(meta, :return_type, ret_type), else: meta
    meta = if vis, do: Keyword.put(meta, :visibility, String.to_atom(vis)), else: meta

    with {:ok, transformed_body} <- transform_list(body) do
      {:ok, add_location({:function_def, meta, transformed_body}, node), %{}}
    end
  end

  def transform(%{"_type" => "Let", "name" => var_name, "value" => val} = node) do
    with {:ok, val_ast, _} <- transform(val) do
      var_node = {:variable, [scope: :local], var_name}
      ast = {:assignment, [subtype: :let], [var_node, val_ast]}
      {:ok, add_location(ast, node), %{}}
    end
  end

  def transform(%{"_type" => "RecordUpdate", "target" => target, "fields" => fields} = node) do
    target_node = {:variable, [scope: :local], target}

    updates =
      Enum.map(fields, fn %{"field" => f, "value" => v} ->
        {:ok, v_ast, _} = transform(v)
        {:pair, [], [{:literal, [subtype: :symbol], String.to_atom(f)}, v_ast]}
      end)

    ast = {:record_update, [name: target], [target_node | updates]}
    {:ok, add_location(ast, node), %{}}
  end

  def transform(%{"_type" => "Match", "expr" => expr, "arms" => arms} = node) do
    with {:ok, expr_ast, _} <- transform(expr),
         {:ok, arm_asts} <- transform_match_arms(arms) do
      ast = {:pattern_match, [], [expr_ast | arm_asts]}
      {:ok, add_location(ast, node), %{}}
    end
  end

  def transform(%{"_type" => "BinOp", "op" => op, "left" => left, "right" => right} = node) do
    with {:ok, left_ast, _} <- transform(left),
         {:ok, right_ast, _} <- transform(right) do
      {category, op_atom} = classify_operator(op)
      ast = {:binary_op, [category: category, operator: op_atom], [left_ast, right_ast]}
      {:ok, add_location(ast, node), %{}}
    end
  end

  def transform(%{"_type" => "Call", "func" => func, "args" => args} = node) do
    with {:ok, arg_asts} <- transform_list(args) do
      ast = {:function_call, [name: func], arg_asts}
      {:ok, add_location(ast, node), %{}}
    end
  end

  def transform(%{"_type" => "AttributeAccess", "receiver" => rec, "attribute" => attr} = node) do
    rec_node = {:variable, [scope: :local], rec}
    ast = {:attribute_access, [attribute: attr], [rec_node]}
    {:ok, add_location(ast, node), %{}}
  end

  def transform(%{"_type" => "Name", "id" => id} = node) do
    ast = {:variable, [scope: :local], id}
    {:ok, add_location(ast, node), %{}}
  end

  def transform(%{"_type" => "Constant", "value" => val, "subtype" => subtype} = node) do
    st_atom = String.to_existing_atom(subtype)
    ast = {:literal, [subtype: st_atom], val}
    {:ok, add_location(ast, node), %{}}
  end

  def transform(other) do
    {:ok, {:language_specific, [native_kind: Map.get(other, "_type", "unknown")], other}, %{}}
  end

  # Helpers

  defp transform_list(nodes) when is_list(nodes) do
    results =
      Enum.reduce_while(nodes, {:ok, []}, fn node, {:ok, acc} ->
        case transform(node) do
          {:ok, meta_ast, _} -> {:cont, {:ok, [meta_ast | acc]}}
          {:error, _} = err -> {:halt, err}
        end
      end)

    case results do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      err -> err
    end
  end

  defp transform_param(%{"name" => name} = p) do
    type = Map.get(p, "type")
    meta = []
    meta = if type, do: Keyword.put(meta, :type_annotation, type), else: meta
    {:param, meta, name}
  end

  defp transform_match_arms(arms) when is_list(arms) do
    transformed =
      Enum.map(arms, fn %{"pattern" => pat, "body" => body} ->
        pat_ast = transform_pattern(pat)
        {:ok, body_ast, _} = transform(body)
        {:match_arm, [], [pat_ast, body_ast]}
      end)

    {:ok, transformed}
  end

  defp transform_pattern(%{"_type" => "ConstructorPattern", "name" => name, "args" => args}) do
    arg_pats = Enum.map(args, &transform_pattern/1)
    {:function_call, [name: name, pattern: true], arg_pats}
  end

  defp transform_pattern(%{"_type" => "VariablePattern", "name" => name}) do
    {:variable, [scope: :pattern], name}
  end

  defp classify_operator(op) do
    case op do
      "+" -> {:arithmetic, :+}
      "-" -> {:arithmetic, :-}
      "*" -> {:arithmetic, :*}
      "/" -> {:arithmetic, :/}
      "==" -> {:comparison, :==}
      "!=" -> {:comparison, :!=}
      "<" -> {:comparison, :<}
      ">" -> {:comparison, :>}
      "<=" -> {:comparison, :<=}
      ">=" -> {:comparison, :>=}
      "&&" -> {:boolean, :and}
      "||" -> {:boolean, :or}
      "|>" -> {:string, :|>}
      "++" -> {:string, :++}
      _ -> {:arithmetic, String.to_atom(op)}
    end
  end

  defp add_location({tag, meta, children}, node) when is_list(meta) and is_map(node) do
    loc_meta = []

    loc_meta =
      if line = Map.get(node, "lineno"), do: Keyword.put(loc_meta, :line, line), else: loc_meta

    loc_meta =
      if col = Map.get(node, "col_offset"), do: Keyword.put(loc_meta, :col, col), else: loc_meta

    {tag, loc_meta ++ meta, children}
  end

  defp add_location(other, _node), do: other
end
