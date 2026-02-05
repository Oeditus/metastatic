defmodule Metastatic.Adapters.Python.FromMeta do
  @moduledoc """
  Transform MetaAST (M2) back to Python AST (M1).

  Implements the reification function ρ_Python that instantiates
  meta-level representations back into Python-specific AST structures.

  ## Transformation Strategy

  The transformation reverses the abstraction performed by `ToMeta`, using
  metadata to restore Python-specific information when needed.

  ### M2.1 (Core Layer) → Python AST
  - Literals, variables, operators, function calls, conditionals, blocks, early returns

  ### M2.2 (Extended Layer) → Python AST
  - Loops: {:loop, :while, ...} → While, {:loop, :for_each, ...} → For
  - Lambdas: {:lambda, params, captures, body} → Lambda
  - Collection ops: {:collection_op, :map, ...} → ListComp or map() call
  - Exception handling: {:exception_handling, ...} → Try

  ## Round-Trip Fidelity

  The transformation aims for high fidelity:
  - Metadata preserves line numbers and formatting hints
  - Default values are provided when metadata is absent
  """

  @doc """
  Transform MetaAST back to Python AST.

  Returns `{:ok, python_ast}` on success or `{:error, reason}` on failure.
  """
  @spec transform(term(), map()) :: {:ok, map()} | {:error, String.t()}

  # Literals - M2.1 Core Layer (New 3-tuple format)

  def transform({:literal, meta, value}, _metadata) when is_list(meta) do
    {:ok, %{"_type" => "Constant", "value" => value, "kind" => nil}}
  end

  # Lists - M2.1 Core Layer (New 3-tuple format)
  def transform({:list, meta, elements}, metadata) when is_list(meta) do
    with {:ok, elements_py} <- transform_list(elements, metadata) do
      {:ok, %{"_type" => "List", "elts" => elements_py, "ctx" => %{"_type" => "Load"}}}
    end
  end

  # Maps (Dicts) - M2.1 Core Layer (New 3-tuple format)
  def transform({:map, meta, pairs}, metadata) when is_list(meta) do
    # Pairs are now {:pair, [], [key, value]} tuples
    {keys, values} =
      Enum.reduce(pairs, {[], []}, fn
        {:pair, _, [k, v]}, {ks, vs} -> {[k | ks], [v | vs]}
        # fallback for old tuple format
        {k, v}, {ks, vs} -> {[k | ks], [v | vs]}
      end)

    with {:ok, keys_py} <- transform_list(Enum.reverse(keys), metadata),
         {:ok, values_py} <- transform_list(Enum.reverse(values), metadata) do
      {:ok, %{"_type" => "Dict", "keys" => keys_py, "values" => values_py}}
    end
  end

  # Variables - M2.1 Core Layer (New 3-tuple format)
  def transform({:variable, meta, name}, _metadata) when is_list(meta) and is_binary(name) do
    {:ok, %{"_type" => "Name", "id" => name, "ctx" => %{"_type" => "Load"}}}
  end

  # Binary Operators - M2.1 Core Layer (New 3-tuple format)
  def transform({:binary_op, meta, [left, right]}, metadata) when is_list(meta) do
    category = Keyword.get(meta, :category)
    op = Keyword.get(meta, :operator)

    case category do
      :arithmetic ->
        transform_binop(op, left, right, metadata)

      :comparison ->
        transform_compare(op, left, right, metadata)

      :boolean ->
        transform_bool_op(op, left, right, metadata)
    end
  end

  # Unary Operators - M2.1 Core Layer (New 3-tuple format)
  def transform({:unary_op, meta, [operand]}, metadata) when is_list(meta) do
    category = Keyword.get(meta, :category)
    op = Keyword.get(meta, :operator)

    with {:ok, operand_py} <- transform(operand, metadata),
         {:ok, op_py} <- python_unary_op(category, op) do
      {:ok, %{"_type" => "UnaryOp", "op" => op_py, "operand" => operand_py}}
    end
  end

  # Function Calls - M2.1 Core Layer (New 3-tuple format)
  def transform({:function_call, meta, args}, metadata) when is_list(meta) do
    name = Keyword.get(meta, :name)

    with {:ok, func_py} <- build_function_ref(name),
         {:ok, args_py} <- transform_list(args, metadata) do
      {:ok, %{"_type" => "Call", "func" => func_py, "args" => args_py, "keywords" => []}}
    end
  end

  # Conditionals - M2.1 Core Layer (New 3-tuple format)
  def transform({:conditional, meta, [condition, then_branch, else_branch]}, metadata)
      when is_list(meta) do
    with {:ok, cond_py} <- transform(condition, metadata),
         {:ok, then_py} <- transform(then_branch, metadata),
         {:ok, else_py} <- transform_or_empty(else_branch, metadata) do
      # Check if this should be an IfExp (ternary) or If statement
      case {then_branch, else_branch} do
        # Both are expressions - use IfExp
        {{_, _, _}, {_, _, _}} when elem(then_branch, 0) != :block ->
          {:ok, %{"_type" => "IfExp", "test" => cond_py, "body" => then_py, "orelse" => else_py}}

        _ ->
          # Use If statement
          then_body = wrap_in_list(then_py)
          else_body = if else_py == [], do: [], else: wrap_in_list(else_py)
          {:ok, %{"_type" => "If", "test" => cond_py, "body" => then_body, "orelse" => else_body}}
      end
    end
  end

  # Blocks - M2.1 Core Layer (New 3-tuple format)
  def transform({:block, meta, statements}, metadata) when is_list(meta) do
    with {:ok, stmts_py} <- transform_list(statements, metadata) do
      case stmts_py do
        [] -> {:ok, %{"_type" => "Pass"}}
        [single] -> {:ok, single}
        multiple -> {:ok, %{"_type" => "Module", "body" => multiple, "type_ignores" => []}}
      end
    end
  end

  # Early Returns - M2.1 Core Layer (New 3-tuple format)
  def transform({:early_return, meta, [value]}, metadata) when is_list(meta) do
    kind = Keyword.get(meta, :kind, :return)

    case kind do
      :return ->
        with {:ok, value_py} <- transform_or_nil(value, metadata) do
          {:ok, %{"_type" => "Return", "value" => value_py}}
        end

      :break ->
        {:ok, %{"_type" => "Break"}}

      :continue ->
        {:ok, %{"_type" => "Continue"}}
    end
  end

  # Assignments - M2.1 Core Layer (New 3-tuple format)
  def transform({:assignment, meta, [target, value]}, metadata) when is_list(meta) do
    with {:ok, target_py} <- transform_assignment_target(target, metadata),
         {:ok, value_py} <- transform(value, metadata) do
      {:ok, %{"_type" => "Assign", "targets" => [target_py], "value" => value_py}}
    end
  end

  # Tuples - M2.1 Core Layer (New 3-tuple format)
  def transform({:tuple, meta, elements}, metadata) when is_list(meta) do
    with {:ok, elts_py} <- transform_list(elements, metadata) do
      {:ok, %{"_type" => "Tuple", "elts" => elts_py, "ctx" => %{"_type" => "Load"}}}
    end
  end

  # Pairs (used in maps)
  def transform({:pair, meta, [key, value]}, metadata) when is_list(meta) do
    # Pairs are handled within map transformation, but if called directly:
    with {:ok, key_py} <- transform(key, metadata),
         {:ok, value_py} <- transform(value, metadata) do
      {:ok, {key_py, value_py}}
    end
  end

  # Loops - M2.2 Extended Layer (New 3-tuple format)
  def transform({:loop, meta, children}, metadata) when is_list(meta) do
    loop_type = Keyword.get(meta, :loop_type)

    case {loop_type, children} do
      {:while, [condition, body]} ->
        with {:ok, test_py} <- transform(condition, metadata),
             {:ok, body_py} <- transform_to_body(body, metadata) do
          {:ok, %{"_type" => "While", "test" => test_py, "body" => body_py, "orelse" => []}}
        end

      {:for_each, [iterator, collection, body]} ->
        with {:ok, target_py} <- transform(iterator, metadata),
             {:ok, iter_py} <- transform(collection, metadata),
             {:ok, body_py} <- transform_to_body(body, metadata) do
          {:ok,
           %{
             "_type" => "For",
             "target" => target_py,
             "iter" => iter_py,
             "body" => body_py,
             "orelse" => []
           }}
        end
    end
  end

  # Lambdas - M2.2 Extended Layer (New 3-tuple format)
  def transform({:lambda, meta, [body]}, metadata) when is_list(meta) do
    params = Keyword.get(meta, :params, [])

    with {:ok, body_py} <- transform(body, metadata) do
      args_node = build_lambda_args(params)
      {:ok, %{"_type" => "Lambda", "args" => args_node, "body" => body_py}}
    end
  end

  # Collection Operations - M2.2 Extended Layer (New 3-tuple format)
  def transform({:collection_op, meta, [func, collection]}, metadata) when is_list(meta) do
    op_type = Keyword.get(meta, :op_type)

    case op_type do
      :map ->
        # Check if func is a simple lambda
        case func do
          {:lambda, lambda_meta, [body]} when is_list(lambda_meta) ->
            params = Keyword.get(lambda_meta, :params, [])

            case params do
              [param] ->
                param_name = extract_param_name(param)

                with {:ok, elt_py} <- transform(body, metadata),
                     {:ok, iter_py} <- transform(collection, metadata) do
                  target = %{
                    "_type" => "Name",
                    "id" => param_name,
                    "ctx" => %{"_type" => "Store"}
                  }

                  generator = %{
                    "_type" => "comprehension",
                    "target" => target,
                    "iter" => iter_py,
                    "ifs" => [],
                    "is_async" => 0
                  }

                  {:ok, %{"_type" => "ListComp", "elt" => elt_py, "generators" => [generator]}}
                end

              _ ->
                transform_map_fallback(func, collection, metadata)
            end

          _ ->
            transform_map_fallback(func, collection, metadata)
        end

      :filter ->
        with {:ok, pred_py} <- transform(func, metadata),
             {:ok, collection_py} <- transform(collection, metadata) do
          filter_func = %{"_type" => "Name", "id" => "filter", "ctx" => %{"_type" => "Load"}}

          {:ok,
           %{
             "_type" => "Call",
             "func" => filter_func,
             "args" => [pred_py, collection_py],
             "keywords" => []
           }}
        end
    end
  end

  # Collection op with initial value (reduce)
  def transform({:collection_op, meta, [func, collection, initial]}, metadata)
      when is_list(meta) do
    op_type = Keyword.get(meta, :op_type)

    case op_type do
      :reduce ->
        with {:ok, func_py} <- transform(func, metadata),
             {:ok, collection_py} <- transform(collection, metadata),
             {:ok, initial_py} <- transform(initial, metadata) do
          # Build functools.reduce reference
          reduce_func = %{
            "_type" => "Attribute",
            "value" => %{"_type" => "Name", "id" => "functools", "ctx" => %{"_type" => "Load"}},
            "attr" => "reduce",
            "ctx" => %{"_type" => "Load"}
          }

          {:ok,
           %{
             "_type" => "Call",
             "func" => reduce_func,
             "args" => [func_py, collection_py, initial_py],
             "keywords" => []
           }}
        end
    end
  end

  # Exception Handling - M2.2 Extended Layer (New 3-tuple format)
  def transform({:exception_handling, meta, [try_block, rescue_clauses, finally_block]}, metadata)
      when is_list(meta) do
    with {:ok, body_py} <- transform_to_body(try_block, metadata),
         {:ok, handlers_py} <- transform_exception_handlers(rescue_clauses, metadata),
         {:ok, finally_py} <- transform_to_body_or_empty(finally_block, metadata) do
      {:ok,
       %{
         "_type" => "Try",
         "body" => body_py,
         "handlers" => handlers_py,
         "orelse" => [],
         "finalbody" => finally_py
       }}
    end
  end

  # Language-Specific - M2.3 Native Layer (New 3-tuple format)
  def transform({:language_specific, meta, native_ast}, _metadata) when is_list(meta) do
    language = Keyword.get(meta, :language)

    case language do
      :python -> {:ok, native_ast}
      other -> {:error, "Cannot reify #{other} language-specific construct to Python"}
    end
  end

  # Catch-all

  def transform(unknown, _metadata) do
    {:error, "Unsupported MetaAST construct: #{inspect(unknown)}"}
  end

  # Helper Functions

  defp transform_map_fallback(func, collection, metadata) do
    with {:ok, func_py} <- transform(func, metadata),
         {:ok, collection_py} <- transform(collection, metadata) do
      map_func = %{"_type" => "Name", "id" => "map", "ctx" => %{"_type" => "Load"}}

      {:ok,
       %{
         "_type" => "Call",
         "func" => map_func,
         "args" => [func_py, collection_py],
         "keywords" => []
       }}
    end
  end

  defp transform_assignment_target({:variable, meta, name}, _metadata)
       when is_list(meta) and is_binary(name) do
    {:ok, %{"_type" => "Name", "id" => name, "ctx" => %{"_type" => "Store"}}}
  end

  defp transform_assignment_target({:tuple, meta, elements}, metadata) when is_list(meta) do
    with {:ok, elts_py} <- transform_assignment_targets(elements, metadata) do
      {:ok, %{"_type" => "Tuple", "elts" => elts_py, "ctx" => %{"_type" => "Store"}}}
    end
  end

  defp transform_assignment_target(target, _metadata) do
    {:error, "Unsupported assignment target: #{inspect(target)}"}
  end

  defp transform_assignment_targets(items, metadata) when is_list(items) do
    items
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
      case transform_assignment_target(item, metadata) do
        {:ok, py} -> {:cont, {:ok, [py | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, items} -> {:ok, Enum.reverse(items)}
      error -> error
    end
  end

  defp transform_list(items, metadata) when is_list(items) do
    items
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
      case transform(item, metadata) do
        {:ok, py} -> {:cont, {:ok, [py | acc]}}
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

  defp transform_or_empty(nil, _metadata), do: {:ok, []}
  defp transform_or_empty(value, metadata), do: transform(value, metadata)

  defp wrap_in_list(item) when is_map(item), do: [item]
  defp wrap_in_list(items) when is_list(items), do: items

  # Operator transformations

  defp transform_binop(op, left, right, metadata) do
    with {:ok, left_py} <- transform(left, metadata),
         {:ok, right_py} <- transform(right, metadata),
         {:ok, op_py} <- python_binop(op) do
      {:ok, %{"_type" => "BinOp", "op" => op_py, "left" => left_py, "right" => right_py}}
    end
  end

  defp transform_compare(op, left, right, metadata) do
    with {:ok, left_py} <- transform(left, metadata),
         {:ok, right_py} <- transform(right, metadata),
         {:ok, op_py} <- python_compare_op(op) do
      {:ok,
       %{"_type" => "Compare", "left" => left_py, "ops" => [op_py], "comparators" => [right_py]}}
    end
  end

  defp transform_bool_op(op, left, right, metadata) do
    with {:ok, left_py} <- transform(left, metadata),
         {:ok, right_py} <- transform(right, metadata),
         {:ok, op_py} <- python_bool_op(op) do
      {:ok, %{"_type" => "BoolOp", "op" => op_py, "values" => [left_py, right_py]}}
    end
  end

  defp python_binop(:+), do: {:ok, %{"_type" => "Add"}}
  defp python_binop(:-), do: {:ok, %{"_type" => "Sub"}}
  defp python_binop(:*), do: {:ok, %{"_type" => "Mult"}}
  defp python_binop(:/), do: {:ok, %{"_type" => "Div"}}
  defp python_binop(:div), do: {:ok, %{"_type" => "FloorDiv"}}
  defp python_binop(:rem), do: {:ok, %{"_type" => "Mod"}}
  defp python_binop(:**), do: {:ok, %{"_type" => "Pow"}}
  defp python_binop(op), do: {:error, "Unsupported arithmetic operator: #{op}"}

  defp python_compare_op(:==), do: {:ok, %{"_type" => "Eq"}}
  defp python_compare_op(:!=), do: {:ok, %{"_type" => "NotEq"}}
  defp python_compare_op(:<), do: {:ok, %{"_type" => "Lt"}}
  defp python_compare_op(:<=), do: {:ok, %{"_type" => "LtE"}}
  defp python_compare_op(:>), do: {:ok, %{"_type" => "Gt"}}
  defp python_compare_op(:>=), do: {:ok, %{"_type" => "GtE"}}
  defp python_compare_op(:===), do: {:ok, %{"_type" => "Is"}}
  defp python_compare_op(:!==), do: {:ok, %{"_type" => "IsNot"}}
  defp python_compare_op(op), do: {:error, "Unsupported comparison operator: #{op}"}

  defp python_bool_op(:and), do: {:ok, %{"_type" => "And"}}
  defp python_bool_op(:or), do: {:ok, %{"_type" => "Or"}}
  defp python_bool_op(op), do: {:error, "Unsupported boolean operator: #{op}"}

  defp python_unary_op(:boolean, :not), do: {:ok, %{"_type" => "Not"}}
  defp python_unary_op(:arithmetic, :-), do: {:ok, %{"_type" => "USub"}}
  defp python_unary_op(:arithmetic, :+), do: {:ok, %{"_type" => "UAdd"}}

  defp python_unary_op(category, op),
    do: {:error, "Unsupported unary operator: #{category} #{op}"}

  defp build_function_ref(name) when is_binary(name) do
    case String.split(name, ".") do
      [single_name] ->
        {:ok, %{"_type" => "Name", "id" => single_name, "ctx" => %{"_type" => "Load"}}}

      parts ->
        # Build nested Attribute nodes
        [first | rest] = parts
        base = %{"_type" => "Name", "id" => first, "ctx" => %{"_type" => "Load"}}

        result =
          Enum.reduce(rest, base, fn attr, acc ->
            %{
              "_type" => "Attribute",
              "value" => acc,
              "attr" => attr,
              "ctx" => %{"_type" => "Load"}
            }
          end)

        {:ok, result}
    end
  end

  # Extended layer helpers

  defp transform_to_body({:block, _meta, statements}, metadata) do
    transform_list(statements, metadata)
  end

  defp transform_to_body(single_expr, metadata) do
    with {:ok, expr_py} <- transform(single_expr, metadata) do
      {:ok, [expr_py]}
    end
  end

  defp transform_to_body_or_empty(nil, _metadata), do: {:ok, []}
  defp transform_to_body_or_empty(expr, metadata), do: transform_to_body(expr, metadata)

  defp build_lambda_args(params) when is_list(params) do
    args =
      Enum.map(params, fn param ->
        param_name = extract_param_name(param)
        %{"_type" => "arg", "arg" => param_name, "annotation" => nil}
      end)

    %{
      "_type" => "arguments",
      "args" => args,
      "posonlyargs" => [],
      "kwonlyargs" => [],
      "kw_defaults" => [],
      "defaults" => [],
      "vararg" => nil,
      "kwarg" => nil
    }
  end

  # Extract param name from various formats
  defp extract_param_name({:param, _meta, name}) when is_binary(name), do: name
  defp extract_param_name(name) when is_binary(name), do: name
  defp extract_param_name(_), do: "_"

  defp transform_exception_handlers(clauses, metadata) when is_list(clauses) do
    clauses
    |> Enum.reduce_while({:ok, []}, fn clause, {:ok, acc} ->
      case transform_exception_handler(clause, metadata) do
        {:ok, handler} -> {:cont, {:ok, [handler | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, handlers} -> {:ok, Enum.reverse(handlers)}
      error -> error
    end
  end

  defp transform_exception_handler({exception_type, var, body}, metadata) do
    with {:ok, type_py} <- build_exception_type(exception_type),
         {:ok, name_py} <- extract_var_name(var),
         {:ok, body_py} <- transform_to_body(body, metadata) do
      {:ok, %{"type" => type_py, "name" => name_py, "body" => body_py}}
    end
  end

  defp build_exception_type(:error) do
    {:ok, %{"_type" => "Name", "id" => "Exception", "ctx" => %{"_type" => "Load"}}}
  end

  defp build_exception_type(atom) when is_atom(atom) do
    name = atom |> Atom.to_string() |> String.capitalize()
    {:ok, %{"_type" => "Name", "id" => name, "ctx" => %{"_type" => "Load"}}}
  end

  defp extract_var_name(nil), do: {:ok, nil}
  defp extract_var_name({:variable, _meta, name}), do: {:ok, name}
  defp extract_var_name(_), do: {:ok, "e"}
end
