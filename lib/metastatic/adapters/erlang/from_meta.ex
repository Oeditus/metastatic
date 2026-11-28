defmodule Metastatic.Adapters.Erlang.FromMeta do
  @moduledoc """
  Transform MetaAST (M2) back to Erlang AST (M1).

  This module implements the reification function ρ_Erlang that instantiates
  meta-level representations back into Erlang-specific AST structures.
  """

  @doc """
  Transform MetaAST back to Erlang AST.

  Returns `{:ok, erlang_ast}` on success or `{:error, reason}` on failure.
  """
  @spec transform(term(), map()) :: {:ok, term()} | {:error, String.t()}

  # Literals - M2.1 Core Layer (New 3-tuple format)

  def transform({:literal, meta, value}, metadata) when is_list(meta) do
    line = Map.get(metadata, :line, 0)
    subtype = Keyword.get(meta, :subtype)

    case subtype do
      :integer ->
        {:ok, {:integer, line, value}}

      :float ->
        {:ok, {:float, line, value}}

      :string ->
        # Convert string back to charlist for Erlang
        charlist = String.to_charlist(value)
        {:ok, {:string, line, charlist}}

      :boolean ->
        {:ok, {:atom, line, value}}

      :null ->
        # Check if original was 'undefined'
        atom =
          case Map.get(metadata, :erlang_atom) do
            :undefined -> :undefined
            _ -> nil
          end

        {:ok, {:atom, line, atom}}

      :symbol ->
        {:ok, {:atom, line, value}}
    end
  end

  # Lists - M2.1 Core Layer (New 3-tuple format)
  def transform({:list, meta, items}, metadata) when is_list(meta) do
    line = Map.get(metadata, :line, 0)

    with {:ok, elements} <- transform_list(items, metadata) do
      list_ast = build_list(elements, line)
      {:ok, list_ast}
    end
  end

  # Variables - M2.1 Core Layer (New 3-tuple format)

  def transform({:variable, meta, name}, metadata) when is_list(meta) and is_binary(name) do
    line = Map.get(metadata, :line, 0)
    var_atom = String.to_atom(name)
    {:ok, {:var, line, var_atom}}
  end

  # Binary Operators - M2.1 Core Layer (New 3-tuple format)

  def transform({:binary_op, meta, [left, right]}, metadata) when is_list(meta) do
    line = Map.get(metadata, :line, 0)
    op = Keyword.get(meta, :operator)

    # Denormalize operators back to Erlang syntax
    erlang_op =
      case op do
        :!= -> :"/="
        :<= -> :"=<"
        :=== -> :"=:="
        :!== -> :"=/="
        :and -> Map.get(metadata, :erlang_op, :andalso)
        :or -> Map.get(metadata, :erlang_op, :orelse)
        other -> other
      end

    with {:ok, left_erl} <- transform(left, metadata),
         {:ok, right_erl} <- transform(right, metadata) do
      {:ok, {:op, line, erlang_op, left_erl, right_erl}}
    end
  end

  # Unary Operators - M2.1 Core Layer (New 3-tuple format)

  def transform({:unary_op, meta, [operand]}, metadata) when is_list(meta) do
    line = Map.get(metadata, :line, 0)
    op = Keyword.get(meta, :operator)

    with {:ok, operand_erl} <- transform(operand, metadata) do
      {:ok, {:op, line, op, operand_erl}}
    end
  end

  # Function Calls - M2.1 Core Layer (New 3-tuple format)

  def transform({:function_call, meta, args}, metadata) when is_list(meta) do
    line = Map.get(metadata, :line, 0)
    name = Keyword.get(meta, :name)

    with {:ok, args_erl} <- transform_list(args, metadata) do
      # Check if this is a remote call
      case String.split(name, ".") do
        [single_name] ->
          # Local call
          func_atom = String.to_atom(single_name)
          {:ok, {:call, line, {:atom, line, func_atom}, args_erl}}

        parts when length(parts) > 1 ->
          # Remote call
          {func_name, module_parts} = List.pop_at(parts, -1)
          module_name = module_parts |> Enum.join(".") |> String.to_atom()
          func_atom = String.to_atom(func_name)

          {:ok,
           {:call, line, {:remote, line, {:atom, line, module_name}, {:atom, line, func_atom}},
            args_erl}}
      end
    end
  end

  # Conditionals - M2.1 Core Layer (New 3-tuple format)

  def transform({:conditional, meta, [condition, then_branch, else_branch]}, metadata)
      when is_list(meta) do
    line = Map.get(metadata, :line, 0)

    with {:ok, cond_erl} <- transform(condition, metadata),
         {:ok, then_erl} <- transform(then_branch, metadata),
         {:ok, else_erl} <- transform_or_nil(else_branch, metadata) do
      # Build if clauses
      then_clause = {:clause, line, [], [[cond_erl]], [then_erl]}

      clauses =
        if else_erl do
          # Add else clause with 'true' guard
          else_clause = {:clause, line, [], [[{:atom, line, true}]], [else_erl]}
          [then_clause, else_clause]
        else
          [then_clause]
        end

      {:ok, {:if, line, clauses}}
    end
  end

  # Blocks - M2.1 Core Layer (New 3-tuple format)

  def transform({:block, meta, expressions}, metadata) when is_list(meta) do
    case expressions do
      [] ->
        {:ok, {:atom, 0, nil}}

      [single] ->
        transform(single, metadata)

      multiple ->
        with {:ok, erl_list} <- transform_list(multiple, metadata) do
          {:ok, {:block, erl_list}}
        end
    end
  end

  # Inline Match (=) - M2.1 Core Layer (New 3-tuple format)
  # Reconstruct Erlang pattern matching syntax

  def transform({:inline_match, meta, [pattern, value]}, metadata) when is_list(meta) do
    line = Map.get(metadata, :line, 0)
    pattern_metadata = Map.get(metadata, :pattern_metadata, %{})
    expr_metadata = Map.get(metadata, :expr_metadata, %{})

    with {:ok, pattern_erl} <- transform_pattern_to_erlang(pattern, pattern_metadata),
         {:ok, value_erl} <- transform(value, expr_metadata) do
      {:ok, {:match, line, pattern_erl, value_erl}}
    end
  end

  # Tuples - Used in patterns and values (New 3-tuple format)

  def transform({:tuple, meta, elements}, metadata) when is_list(meta) do
    line = Map.get(metadata, :line, 0)

    with {:ok, elements_erl} <- transform_list(elements, metadata) do
      {:ok, {:tuple, line, elements_erl}}
    end
  end

  # Cons pattern - Used in list patterns [H | T] (New 3-tuple format)

  def transform({:cons_pattern, meta, [head, tail]}, metadata) when is_list(meta) do
    line = Map.get(metadata, :line, 0)

    with {:ok, head_erl} <- transform(head, metadata),
         {:ok, tail_erl} <- transform(tail, metadata) do
      {:ok, {:cons, line, head_erl, tail_erl}}
    end
  end

  # Pattern Matching - M2.2 Extended Layer (New 3-tuple format)

  def transform({:pattern_match, meta, [scrutinee | arms]}, metadata)
      when is_list(meta) and is_list(arms) do
    line = Map.get(metadata, :line, 0)

    with {:ok, scrutinee_erl} <- transform(scrutinee, metadata),
         {:ok, clauses} <- transform_match_arms(arms, metadata) do
      {:ok, {:case, line, scrutinee_erl, clauses}}
    end
  end

  # Parameters - M2.2s Structural Layer

  def transform({:param, meta, name}, metadata) when is_list(meta) and is_binary(name) do
    line = Keyword.get(meta, :line, Map.get(metadata, :line, 0))

    case Keyword.get(meta, :pattern) do
      nil -> {:ok, {:var, line, String.to_atom(name)}}
      pattern -> transform_pattern(pattern, metadata)
    end
  end

  # Maps & Pairs - M2.1 Core Layer

  def transform({:map, meta, pairs}, metadata) when is_list(meta) and is_list(pairs) do
    line = Keyword.get(meta, :line, Map.get(metadata, :line, 0))

    with {:ok, fields} <- transform_list(pairs, metadata) do
      {:ok, {:map, line, fields}}
    end
  end

  def transform({:pair, meta, [key, value]}, metadata) when is_list(meta) do
    line = Keyword.get(meta, :line, Map.get(metadata, :line, 0))

    with {:ok, key_erl} <- transform(key, metadata),
         {:ok, val_erl} <- transform(value, metadata) do
      {:ok, {:map_field_assoc, line, key_erl, val_erl}}
    end
  end

  # Lambdas (fun expressions) - M2.2 Extended Layer

  def transform({:lambda, meta, body}, metadata) when is_list(meta) and is_list(body) do
    line = Keyword.get(meta, :line, Map.get(metadata, :line, 0))
    params = Keyword.get(meta, :params, [])

    with {:ok, params_erl} <- transform_params(params, line, metadata),
         {:ok, body_erl} <- transform_body_exprs(body, metadata) do
      {:ok, {:fun, line, {:clauses, [{:clause, line, params_erl, [], body_erl}]}}}
    end
  end

  # Exception Handling (try/catch/after) - M2.2 Extended Layer

  def transform({:exception_handling, meta, [body, handlers, finally_expr]}, metadata)
      when is_list(meta) do
    line = Keyword.get(meta, :line, Map.get(metadata, :line, 0))

    with {:ok, body_erl} <- transform_body_exprs([body], metadata),
         {:ok, catch_clauses} <- transform_catch_handlers(handlers, line, metadata),
         {:ok, after_erl} <- transform_after_body(finally_expr, metadata) do
      {:ok, {:try, line, body_erl, [], catch_clauses, after_erl}}
    end
  end

  # Function Definitions - M2.2s Structural Layer

  def transform({:function_def, meta, body}, metadata) when is_list(meta) and is_list(body) do
    line = Keyword.get(meta, :line, Map.get(metadata, :line, 0))
    name = Keyword.get(meta, :name, "anonymous")
    params = Keyword.get(meta, :params, [])
    arity = Keyword.get(meta, :arity, length(params))

    with {:ok, params_erl} <- transform_params(params, line, metadata),
         {:ok, body_erl} <- transform_body_exprs(body, metadata) do
      clause = {:clause, line, params_erl, [], body_erl}
      {:ok, {:function, line, String.to_atom(name), arity, [clause]}}
    end
  end

  # Containers (Modules) - M2.2s Structural Layer

  def transform({:container, meta, body}, metadata) when is_list(meta) and is_list(body) do
    line = Keyword.get(meta, :line, Map.get(metadata, :line, 0))
    name = Keyword.get(meta, :name, "unnamed")
    mod_attr = {:attribute, line, :module, String.to_atom(name)}

    case body do
      [] ->
        {:ok, mod_attr}

      forms ->
        with {:ok, forms_erl} <- transform_list(forms, metadata) do
          {:ok, {:block, [mod_attr | forms_erl]}}
        end
    end
  end

  # Imports & Exports - M2.2s Structural Layer

  def transform({:import, meta, _children}, metadata) when is_list(meta) do
    line = Keyword.get(meta, :line, Map.get(metadata, :line, 0))
    import_type = Keyword.get(meta, :import_type, :import)
    names = Keyword.get(meta, :names, [])
    fun_arities = Enum.map(names, &parse_fun_arity/1)

    case import_type do
      :export ->
        {:ok, {:attribute, line, :export, fun_arities}}

      _ ->
        source = Keyword.get(meta, :source, "unknown")
        {:ok, {:attribute, line, :import, {String.to_atom(source), fun_arities}}}
    end
  end

  # Language-Specific - M2.3 Native Layer (New 3-tuple format)

  def transform({:language_specific, meta, native_ast}, _metadata) when is_list(meta) do
    # Return the native Erlang AST as-is
    {:ok, native_ast}
  end

  # Wildcard pattern
  def transform(:_, metadata) do
    line = Map.get(metadata, :line, 0)
    {:ok, {:var, line, :_}}
  end

  # Catch-all
  def transform(unknown, _metadata) do
    {:error, "Unsupported MetaAST construct for Erlang: #{inspect(unknown)}"}
  end

  # Helper Functions

  defp transform_list(items, metadata) when is_list(items) do
    items
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
      case transform(item, metadata) do
        {:ok, erl} -> {:cont, {:ok, [erl | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, items} -> {:ok, Enum.reverse(items)}
      error -> error
    end
  end

  defp transform_or_nil(nil, _metadata), do: {:ok, nil}
  defp transform_or_nil(value, metadata), do: transform(value, metadata)

  defp build_list([], line) do
    {nil, line}
  end

  defp build_list([head | tail], line) do
    {:cons, line, head, build_list(tail, line)}
  end

  defp transform_match_arms(arms, metadata) do
    line = Map.get(metadata, :line, 0)

    arms
    |> Enum.reduce_while({:ok, []}, fn {:match_arm, meta, body_list}, {:ok, acc} ->
      pattern = Keyword.get(meta, :pattern)
      body = List.last(body_list)

      with {:ok, pattern_erl} <- transform_pattern(pattern, metadata),
           {:ok, body_erl} <- transform(body, metadata) do
        clause = {:clause, line, [pattern_erl], [], [body_erl]}
        {:cont, {:ok, [clause | acc]}}
      else
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, clauses} -> {:ok, Enum.reverse(clauses)}
      error -> error
    end
  end

  defp transform_pattern(:_, metadata) do
    line = Map.get(metadata, :line, 0)
    {:ok, {:var, line, :_}}
  end

  defp transform_pattern(pattern, metadata) do
    transform(pattern, metadata)
  end

  defp transform_pattern_to_erlang(:_, metadata) do
    line = Map.get(metadata, :line, 0)
    {:ok, {:var, line, :_}}
  end

  defp transform_pattern_to_erlang(pattern, metadata) do
    # Pattern transformation is the same as regular transformation
    # since we handle tuples and cons patterns in the main transform/2
    transform(pattern, metadata)
  end

  defp transform_params(params, line, metadata) when is_list(params) do
    params
    |> Enum.reduce_while({:ok, []}, fn param, {:ok, acc} ->
      res =
        case param do
          {:param, _, _} = p -> transform(p, metadata)
          name when is_binary(name) -> {:ok, {:var, line, String.to_atom(name)}}
          other -> transform_pattern(other, metadata)
        end

      case res do
        {:ok, erl} -> {:cont, {:ok, [erl | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, items} -> {:ok, Enum.reverse(items)}
      error -> error
    end
  end

  defp transform_body_exprs([{:block, _, exprs}], metadata) when is_list(exprs) and exprs != [] do
    transform_list(exprs, metadata)
  end

  defp transform_body_exprs([], _metadata), do: {:ok, [{:atom, 0, :ok}]}

  defp transform_body_exprs(exprs, metadata) when is_list(exprs) do
    transform_list(exprs, metadata)
  end

  defp transform_catch_handlers(nil, _line, _metadata), do: {:ok, []}

  defp transform_catch_handlers(handlers, line, metadata) when is_list(handlers) do
    handlers
    |> Enum.reduce_while({:ok, []}, fn handler, {:ok, acc} ->
      {class, pattern, body} =
        case handler do
          {:match_arm, arm_meta, arm_body} ->
            {Keyword.get(arm_meta, :class, :error), Keyword.get(arm_meta, :pattern, :_),
             List.last(arm_body)}

          {p, b} ->
            {:error, p, b}

          other ->
            {:error, :_, other}
        end

      with {:ok, pat_erl} <- transform_pattern(pattern, metadata),
           {:ok, body_erl} <- transform(body, metadata) do
        class_ast = {:atom, line, class}
        stack_ast = {:var, line, :_}

        clause =
          {:clause, line, [{:tuple, line, [class_ast, pat_erl, stack_ast]}], [], [body_erl]}

        {:cont, {:ok, [clause | acc]}}
      else
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, clauses} -> {:ok, Enum.reverse(clauses)}
      error -> error
    end
  end

  defp transform_after_body(nil, _metadata), do: {:ok, []}
  defp transform_after_body(expr, metadata), do: transform_body_exprs([expr], metadata)

  defp parse_fun_arity(str) when is_binary(str) do
    case String.split(str, "/") do
      [name, arity_str] ->
        case Integer.parse(arity_str) do
          {arity, ""} -> {String.to_atom(name), arity}
          _ -> {String.to_atom(str), 0}
        end

      _ ->
        {String.to_atom(str), 0}
    end
  end

  defp parse_fun_arity({name, arity}) when is_atom(name) and is_integer(arity), do: {name, arity}
end
