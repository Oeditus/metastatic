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

  def transform({:pattern_match, meta, [scrutinee, arms]}, metadata) when is_list(meta) do
    line = Map.get(metadata, :line, 0)

    with {:ok, scrutinee_erl} <- transform(scrutinee, metadata),
         {:ok, clauses} <- transform_match_arms(arms, metadata) do
      {:ok, {:case, line, scrutinee_erl, clauses}}
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
    |> Enum.reduce_while({:ok, []}, fn {:match_arm, _meta, [pattern, _guard, body]}, {:ok, acc} ->
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
end
