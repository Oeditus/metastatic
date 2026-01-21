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

  # Literals - M2.1 Core Layer

  def transform({:literal, :integer, value}, metadata) do
    line = Map.get(metadata, :line, 0)
    {:ok, {:integer, line, value}}
  end

  def transform({:literal, :float, value}, metadata) do
    line = Map.get(metadata, :line, 0)
    {:ok, {:float, line, value}}
  end

  def transform({:literal, :string, value}, metadata) do
    line = Map.get(metadata, :line, 0)
    # Convert string back to charlist for Erlang
    charlist = String.to_charlist(value)
    {:ok, {:string, line, charlist}}
  end

  def transform({:literal, :boolean, value}, metadata) do
    line = Map.get(metadata, :line, 0)
    {:ok, {:atom, line, value}}
  end

  def transform({:literal, :null, nil}, metadata) do
    line = Map.get(metadata, :line, 0)
    # Check if original was 'undefined'
    atom =
      case Map.get(metadata, :erlang_atom) do
        :undefined -> :undefined
        _ -> nil
      end

    {:ok, {:atom, line, atom}}
  end

  def transform({:literal, :symbol, atom}, metadata) do
    line = Map.get(metadata, :line, 0)
    {:ok, {:atom, line, atom}}
  end

  def transform({:literal, :collection, items}, metadata) do
    line = Map.get(metadata, :line, 0)

    case Map.get(metadata, :collection_type) do
      :tuple ->
        with {:ok, elements} <- transform_list(items, metadata) do
          {:ok, {:tuple, line, elements}}
        end

      :list ->
        # Build list from items
        with {:ok, elements} <- transform_list(items, metadata) do
          list_ast = build_list(elements, line)
          {:ok, list_ast}
        end

      _ ->
        # Default to list
        with {:ok, elements} <- transform_list(items, metadata) do
          list_ast = build_list(elements, line)
          {:ok, list_ast}
        end
    end
  end

  # Variables - M2.1 Core Layer

  def transform({:variable, name}, metadata) when is_binary(name) do
    line = Map.get(metadata, :line, 0)
    var_atom = String.to_atom(name)
    {:ok, {:var, line, var_atom}}
  end

  # Binary Operators - M2.1 Core Layer

  def transform({:binary_op, _category, op, left, right}, metadata) do
    line = Map.get(metadata, :line, 0)

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

  # Unary Operators - M2.1 Core Layer

  def transform({:unary_op, _category, op, operand}, metadata) do
    line = Map.get(metadata, :line, 0)

    with {:ok, operand_erl} <- transform(operand, metadata) do
      {:ok, {:op, line, op, operand_erl}}
    end
  end

  # Function Calls - M2.1 Core Layer

  def transform({:function_call, name, args}, metadata) do
    line = Map.get(metadata, :line, 0)

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

  # Conditionals - M2.1 Core Layer

  def transform({:conditional, condition, then_branch, else_branch}, metadata) do
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

  # Blocks - M2.1 Core Layer

  def transform({:block, expressions}, metadata) do
    case expressions do
      [] -> {:ok, {:atom, 0, nil}}
      [single] -> transform(single, metadata)
      multiple -> {:ok, {:block, multiple}}
    end
  end

  # Pattern Matching - M2.2 Extended Layer

  def transform({:pattern_match, scrutinee, arms}, metadata) do
    line = Map.get(metadata, :line, 0)

    with {:ok, scrutinee_erl} <- transform(scrutinee, metadata),
         {:ok, clauses} <- transform_match_arms(arms, metadata) do
      {:ok, {:case, line, scrutinee_erl, clauses}}
    end
  end

  # Language-Specific - M2.3 Native Layer

  def transform({:language_specific, :erlang, native_ast, _hint}, _metadata) do
    # Return the native Erlang AST as-is
    {:ok, native_ast}
  end

  def transform({:language_specific, other_lang, _ast, _hint}, _metadata) do
    {:error, "Cannot reify #{other_lang} language-specific construct to Erlang"}
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
    |> Enum.reduce_while({:ok, []}, fn {:match_arm, pattern, _guard, body}, {:ok, acc} ->
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
end
