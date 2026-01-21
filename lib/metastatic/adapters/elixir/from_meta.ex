defmodule Metastatic.Adapters.Elixir.FromMeta do
  @moduledoc """
  Transform MetaAST (M2) back to Elixir AST (M1).

  This module implements the reification function ρ_Elixir that instantiates
  meta-level representations back into Elixir-specific AST structures.

  ## Transformation Strategy

  The transformation reverses the abstraction performed by `ToMeta`, using
  metadata to restore M1-specific information when needed.

  ## Round-Trip Fidelity

  The transformation aims for high fidelity:
  - Metadata preserves line numbers, contexts, and formatting hints
  - Variable contexts are restored from metadata
  - Special forms are reconstructed from metadata markers

  ## Default Values

  When metadata is absent or incomplete:
  - Line number defaults to 0
  - Variable context defaults to `Elixir`
  - Empty metadata keyword list `[]` is used
  """

  @doc """
  Transform MetaAST back to Elixir AST.

  Returns `{:ok, elixir_ast}` on success or `{:error, reason}` on failure.

  ## Examples

      iex> transform({:literal, :integer, 42}, %{})
      {:ok, 42}

      iex> transform({:variable, "x"}, %{context: Elixir})
      {:ok, {:x, [], Elixir}}

      iex> transform({:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}}, %{})
      {:ok, {:+, [], [{:x, [], Elixir}, 5]}}
  """
  @spec transform(term(), map()) :: {:ok, term()} | {:error, String.t()}

  # Literals - M2.1 Core Layer

  def transform({:literal, :integer, value}, _metadata) do
    {:ok, value}
  end

  def transform({:literal, :float, value}, _metadata) do
    {:ok, value}
  end

  def transform({:literal, :string, value}, _metadata) do
    {:ok, value}
  end

  def transform({:literal, :boolean, value}, _metadata) do
    {:ok, value}
  end

  def transform({:literal, :null, nil}, _metadata) do
    {:ok, nil}
  end

  def transform({:literal, :symbol, atom}, _metadata) do
    {:ok, atom}
  end

  def transform({:literal, :collection, items}, metadata) do
    case transform_list(items, metadata) do
      {:ok, transformed_items} ->
        # Return as list literal
        {:ok, transformed_items}

      error ->
        error
    end
  end

  # Variables - M2.1 Core Layer

  def transform({:variable, name}, metadata) when is_binary(name) do
    var_atom = String.to_atom(name)
    # Default context depends on caller - use what's in metadata or nil
    context = Map.get(metadata, :context, nil)
    elixir_meta = Map.get(metadata, :elixir_meta, [])

    {:ok, {var_atom, elixir_meta, context}}
  end

  # Binary Operators - M2.1 Core Layer

  def transform({:binary_op, _category, op, left, right}, metadata) do
    with {:ok, left_ex} <- transform(left, metadata),
         {:ok, right_ex} <- transform(right, metadata) do
      {:ok, {op, [], [left_ex, right_ex]}}
    end
  end

  # Unary Operators - M2.1 Core Layer

  def transform({:unary_op, _category, op, operand}, metadata) do
    with {:ok, operand_ex} <- transform(operand, metadata) do
      {:ok, {op, [], [operand_ex]}}
    end
  end

  # Function Calls - M2.1 Core Layer

  def transform({:function_call, name, args}, metadata) do
    with {:ok, args_ex} <- transform_list(args, metadata) do
      # Check if this is a remote call (Module.function)
      case String.split(name, ".") do
        [single_name] ->
          # Local call
          func_atom = String.to_atom(single_name)
          {:ok, {func_atom, [], args_ex}}

        parts when length(parts) > 1 ->
          # Remote call
          {func_name, module_parts} = List.pop_at(parts, -1)
          module_ast = build_module_alias(module_parts)
          func_atom = String.to_atom(func_name)

          {:ok, {{:., [], [module_ast, func_atom]}, [], args_ex}}
      end
    end
  end

  # Conditionals - M2.1 Core Layer

  def transform({:conditional, condition, then_branch, else_branch}, metadata) do
    with {:ok, cond_ex} <- transform(condition, metadata),
         {:ok, then_ex} <- transform(then_branch, metadata),
         {:ok, else_ex} <- transform_or_keep_nil(else_branch, metadata) do
      # Check if this was originally an unless
      case Map.get(metadata, :original_form) do
        :unless ->
          # Reconstruct unless (need to undo the negation)
          actual_cond =
            case cond_ex do
              {:not, [], [inner_cond]} -> inner_cond
              _ -> {:not, [], [cond_ex]}
            end

          clauses = if else_ex, do: [do: then_ex, else: else_ex], else: [do: then_ex]
          {:ok, {:unless, [], [actual_cond, clauses]}}

        _ ->
          # Regular if
          clauses = if else_ex, do: [do: then_ex, else: else_ex], else: [do: then_ex]
          {:ok, {:if, [], [cond_ex, clauses]}}
      end
    end
  end

  # Blocks - M2.1 Core Layer

  def transform({:block, expressions}, metadata) do
    with {:ok, exprs_ex} <- transform_list(expressions, metadata) do
      case exprs_ex do
        [] -> {:ok, nil}
        [single] -> {:ok, single}
        multiple -> {:ok, {:__block__, [], multiple}}
      end
    end
  end

  # Early Returns - M2.1 Core Layer

  def transform({:early_return, kind, value}, metadata) do
    with {:ok, value_ex} <- transform_or_keep_nil(value, metadata) do
      # Elixir doesn't have direct return/break/continue
      # These would be represented as throws or special constructs
      case kind do
        :return ->
          {:ok, {:throw, [], [{:return, value_ex}]}}

        :break ->
          {:ok, {:throw, [], [:break]}}

        :continue ->
          {:ok, {:throw, [], [:continue]}}
      end
    end
  end

  # Pattern Matching - M2.2 Extended Layer

  def transform({:pattern_match, scrutinee, arms}, metadata) do
    with {:ok, scrutinee_ex} <- transform(scrutinee, metadata),
         {:ok, arms_ex} <- transform_match_arms(arms, metadata) do
      {:ok, {:case, [], [scrutinee_ex, [do: arms_ex]]}}
    end
  end

  # Anonymous Functions - M2.2 Extended Layer

  def transform({:lambda, params, body}, metadata) do
    with {:ok, params_ex} <- transform_params(params, metadata),
         {:ok, body_ex} <- transform(body, metadata) do
      clause = {:->, [], [params_ex, body_ex]}
      {:ok, {:fn, [], [clause]}}
    end
  end

  # Collection Operations - M2.2 Extended Layer

  def transform({:collection_op, :map, fun, collection}, metadata) do
    with {:ok, collection_ex} <- transform(collection, metadata),
         {:ok, fun_ex} <- transform(fun, metadata) do
      # Check if this was originally a comprehension
      case Map.get(metadata, :original_form) do
        :comprehension ->
          # Transform back to for comprehension
          transform_to_comprehension(:map, fun_ex, collection_ex)

        _ ->
          # Regular Enum.map
          enum_module = {:__aliases__, [], [:Enum]}
          {:ok, {{:., [], [enum_module, :map]}, [], [collection_ex, fun_ex]}}
      end
    end
  end

  def transform({:collection_op, :filter, fun, collection}, metadata) do
    with {:ok, collection_ex} <- transform(collection, metadata),
         {:ok, fun_ex} <- transform(fun, metadata) do
      enum_module = {:__aliases__, [], [:Enum]}
      {:ok, {{:., [], [enum_module, :filter]}, [], [collection_ex, fun_ex]}}
    end
  end

  def transform({:collection_op, :reduce, fun, collection, initial}, metadata) do
    with {:ok, collection_ex} <- transform(collection, metadata),
         {:ok, initial_ex} <- transform(initial, metadata),
         {:ok, fun_ex} <- transform(fun, metadata) do
      enum_module = {:__aliases__, [], [:Enum]}
      {:ok, {{:., [], [enum_module, :reduce]}, [], [collection_ex, initial_ex, fun_ex]}}
    end
  end

  # Language-Specific - M2.3 Native Layer

  def transform({:language_specific, :elixir, native_ast, _hint}, _metadata) do
    # Return the native Elixir AST as-is
    {:ok, native_ast}
  end

  def transform({:language_specific, other_lang, _ast, _hint}, _metadata) do
    {:error, "Cannot reify #{other_lang} language-specific construct to Elixir"}
  end

  # Catch-all for unsupported constructs

  def transform(unknown, _metadata) do
    {:error, "Unsupported MetaAST construct: #{inspect(unknown)}"}
  end

  # Helper Functions

  defp transform_list(items, metadata) when is_list(items) do
    items
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
      case transform(item, metadata) do
        {:ok, ex} -> {:cont, {:ok, [ex | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, items} -> {:ok, Enum.reverse(items)}
      error -> error
    end
  end

  defp transform_or_keep_nil(nil, _metadata), do: {:ok, nil}
  defp transform_or_keep_nil(value, metadata), do: transform(value, metadata)

  defp build_module_alias(parts) do
    atoms = Enum.map(parts, &String.to_atom/1)
    {:__aliases__, [], atoms}
  end

  defp transform_match_arms(arms, metadata) do
    arms
    |> Enum.reduce_while({:ok, []}, fn arm, {:ok, acc} ->
      case transform_match_arm(arm, metadata) do
        {:ok, arm_ex} -> {:cont, {:ok, [arm_ex | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, arms} -> {:ok, Enum.reverse(arms)}
      error -> error
    end
  end

  defp transform_match_arm({:match_arm, pattern, guard, body}, metadata) do
    with {:ok, pattern_ex} <- transform_pattern(pattern, metadata),
         {:ok, body_ex} <- transform(body, metadata) do
      # Ignore guard for now (would need special handling)
      _ = guard
      {:ok, {:->, [], [[pattern_ex], body_ex]}}
    end
  end

  defp transform_pattern(:_, _metadata) do
    # Wildcard pattern
    {:ok, {:_, [], nil}}
  end

  defp transform_pattern(pattern, metadata) do
    # Regular pattern is just a transformation
    transform(pattern, metadata)
  end

  defp transform_params(params, _metadata) do
    params_ex =
      Enum.map(params, fn
        {:param, name, _type_hint, _default} ->
          {String.to_atom(name), [], nil}

        other ->
          # Fallback - shouldn't happen
          other
      end)

    {:ok, params_ex}
  end

  defp transform_to_comprehension(:map, lambda_ex, collection_ex) do
    # Extract variable and body from lambda
    case lambda_ex do
      {:fn, [], [{:->, [], [[{var, [], nil}], body]}]} ->
        # Simple comprehension: for var <- collection, do: body
        generator = {:<-, [], [{var, [], nil}, collection_ex]}
        {:ok, {:for, [], [generator, [do: body]]}}

      _ ->
        # Can't convert to comprehension, use Enum.map
        enum_module = {:__aliases__, [], [:Enum]}
        {:ok, {{:., [], [enum_module, :map]}, [], [collection_ex, lambda_ex]}}
    end
  end
end
