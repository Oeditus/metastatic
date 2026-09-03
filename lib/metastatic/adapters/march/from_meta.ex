defmodule Metastatic.Adapters.March.FromMeta do
  @moduledoc """
  Transform MetaAST (M2) to March AST (M1).

  Reifies standard MetaAST 3-tuples back into March AST JSON maps.
  """

  @doc """
  Transform MetaAST tuple or list to March AST map representation.
  """
  @spec transform(term(), map()) :: {:ok, map() | list()} | {:error, String.t()}
  def transform(meta_ast, metadata \\ %{})

  def transform(nodes, metadata) when is_list(nodes) do
    with {:ok, transformed} <- transform_list(nodes, metadata) do
      {:ok, transformed}
    end
  end

  def transform({:block, _meta, statements}, metadata) do
    with {:ok, body} <- transform_list(statements, metadata) do
      {:ok, %{"_type" => "Program", "body" => body}}
    end
  end

  def transform({:container, meta, children}, metadata) do
    subtype = Keyword.get(meta, :subtype, :module)
    name = Keyword.get(meta, :name, "Unnamed")

    case subtype do
      :module ->
        with {:ok, body} <- transform_list(children, metadata) do
          {:ok, %{"_type" => "Module", "name" => name, "body" => body}}
        end

      :actor ->
        state = Keyword.get(meta, :state)
        init = Keyword.get(meta, :init)

        with {:ok, handlers} <- transform_list(children, metadata) do
          {:ok,
           %{
             "_type" => "Actor",
             "name" => name,
             "state" => state,
             "init" => init,
             "handlers" => handlers
           }}
        end

      _ ->
        with {:ok, body} <- transform_list(children, metadata) do
          {:ok, %{"_type" => "Module", "name" => name, "body" => body}}
        end
    end
  end

  def transform({:function_def, meta, body}, metadata) do
    name = Keyword.get(meta, :name, "unnamed")
    params_meta = Keyword.get(meta, :params, [])
    callback_for = Keyword.get(meta, :callback_for)

    params = Enum.map(params_meta, &reify_param/1)
    ret_type = Keyword.get(meta, :return_type)
    vis = Keyword.get(meta, :visibility)

    with {:ok, body_transformed} <- transform_list(body, metadata) do
      if callback_for == "on_message" or String.starts_with?(name, "on:") do
        msg_name = String.replace_leading(name, "on:", "")

        {:ok,
         %{
           "_type" => "OnHandler",
           "message" => msg_name,
           "params" => params,
           "body" => body_transformed
         }}
      else
        res = %{
          "_type" => "FunctionDef",
          "name" => name,
          "params" => params,
          "body" => body_transformed
        }

        res = if ret_type, do: Map.put(res, "return_type", ret_type), else: res
        res = if vis, do: Map.put(res, "visibility", Atom.to_string(vis)), else: res
        {:ok, res}
      end
    end
  end

  def transform({:import, meta, _}, _metadata) do
    case Keyword.get(meta, :import_type) do
      :needs ->
        cap = Keyword.get(meta, :capability, "")
        {:ok, %{"_type" => "Needs", "capability" => cap}}

      _ ->
        source = Keyword.get(meta, :source, "")
        {:ok, %{"_type" => "Use", "module" => source}}
    end
  end

  def transform({:assignment, meta, [var_node, val_node]}, metadata) do
    subtype = Keyword.get(meta, :subtype, :let)
    {:variable, _, var_name} = var_node

    with {:ok, val_transformed} <- transform(val_node, metadata) do
      if subtype == :let do
        {:ok, %{"_type" => "Let", "name" => var_name, "value" => val_transformed}}
      else
        {:ok, %{"_type" => "Let", "name" => var_name, "value" => val_transformed}}
      end
    end
  end

  def transform({:record_update, _meta, [target_node | updates]}, metadata) do
    {:variable, _, target_name} = target_node

    fields =
      Enum.map(updates, fn {:pair, _, [{:literal, _, f}, v]} ->
        {:ok, v_transformed} = transform(v, metadata)
        %{"field" => f, "value" => v_transformed}
      end)

    {:ok, %{"_type" => "RecordUpdate", "target" => target_name, "fields" => fields}}
  end

  def transform({:pattern_match, _meta, [expr_node | arm_nodes]}, metadata) do
    with {:ok, expr_transformed} <- transform(expr_node, metadata),
         {:ok, arms_transformed} <- reify_match_arms(arm_nodes, metadata) do
      {:ok, %{"_type" => "Match", "expr" => expr_transformed, "arms" => arms_transformed}}
    end
  end

  def transform({:binary_op, meta, [left, right]}, metadata) do
    op_atom = Keyword.get(meta, :operator, :+)
    op_str = Atom.to_string(op_atom)

    with {:ok, left_transformed} <- transform(left, metadata),
         {:ok, right_transformed} <- transform(right, metadata) do
      {:ok,
       %{
         "_type" => "BinOp",
         "op" => op_str,
         "left" => left_transformed,
         "right" => right_transformed
       }}
    end
  end

  def transform({:function_call, meta, args}, metadata) do
    func_name = Keyword.get(meta, :name, "call")

    with {:ok, args_transformed} <- transform_list(args, metadata) do
      {:ok, %{"_type" => "Call", "func" => func_name, "args" => args_transformed}}
    end
  end

  def transform({:attribute_access, meta, [rec_node]}, _metadata) do
    attr = Keyword.get(meta, :attribute, "")
    {:variable, _, rec_name} = rec_node

    {:ok, %{"_type" => "AttributeAccess", "receiver" => rec_name, "attribute" => attr}}
  end

  def transform({:variable, _meta, name}, _metadata) do
    {:ok, %{"_type" => "Name", "id" => name}}
  end

  def transform({:literal, meta, val}, _metadata) do
    subtype = Keyword.get(meta, :subtype, :integer)
    st_str = Atom.to_string(subtype)
    {:ok, %{"_type" => "Constant", "value" => val, "subtype" => st_str}}
  end

  def transform({:language_specific, _meta, native}, _metadata) do
    {:ok, native}
  end

  def transform(other, _metadata) do
    {:error, "Unsupported MetaAST node for March reification: #{inspect(other)}"}
  end

  # Helpers

  defp transform_list(nodes, metadata) when is_list(nodes) do
    results =
      Enum.reduce_while(nodes, {:ok, []}, fn node, {:ok, acc} ->
        case transform(node, metadata) do
          {:ok, transformed} -> {:cont, {:ok, [transformed | acc]}}
          {:error, _} = err -> {:halt, err}
        end
      end)

    case results do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      err -> err
    end
  end

  defp reify_param({:param, meta, name}) when is_binary(name) do
    type = Keyword.get(meta, :type_annotation)
    res = %{"name" => name}
    if type, do: Map.put(res, "type", type), else: res
  end

  defp reify_param(kw) when is_list(kw) do
    name = Keyword.get(kw, :name, "x")
    type = Keyword.get(kw, :type_annotation)
    res = %{"name" => name}
    if type, do: Map.put(res, "type", type), else: res
  end

  defp reify_param(other) when is_binary(other), do: %{"name" => other}
  defp reify_param(other), do: %{"name" => inspect(other)}

  defp reify_match_arms(arms, metadata) when is_list(arms) do
    results =
      Enum.map(arms, fn {:match_arm, _, [pat, body]} ->
        pat_transformed = reify_pattern(pat)
        {:ok, body_transformed} = transform(body, metadata)
        %{"pattern" => pat_transformed, "body" => body_transformed}
      end)

    {:ok, results}
  end

  defp reify_pattern({:function_call, meta, args}) do
    cname = Keyword.get(meta, :name, "Constructor")
    arg_pats = Enum.map(args, &reify_pattern/1)
    %{"_type" => "ConstructorPattern", "name" => cname, "args" => arg_pats}
  end

  defp reify_pattern({:variable, _, name}) do
    %{"_type" => "VariablePattern", "name" => name}
  end

  defp reify_pattern(other), do: %{"_type" => "VariablePattern", "name" => inspect(other)}
end
