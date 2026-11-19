defmodule Metastatic.Adapters.Haskell.FromMeta do
  @moduledoc """
  Transform MetaAST (M2) back to Haskell AST (M1).

  This module implements the reification function ρ_Haskell that converts
  meta-level representations back to Haskell-specific AST structures.

  ## 3-Tuple Format

  All MetaAST nodes use the uniform 3-tuple structure:
  `{type_atom, keyword_meta, children_or_value}`

  ## Status

  Basic M2.1 Core Layer support implemented.
  M2.2 Extended and M2.3 Native layers to be completed in future iterations.
  """

  @doc """
  Transform MetaAST back to Haskell AST.

  Returns `{:ok, haskell_ast}` on success or `{:error, reason}` on failure.
  """
  @spec transform(term(), map()) :: {:ok, term()} | {:error, String.t()}

  # M2.1 Core Layer - Literals (3-tuple format)

  def transform({:literal, meta, value}, _metadata) when is_list(meta) do
    subtype = Keyword.get(meta, :subtype, :unknown)
    transform_literal(subtype, value)
  end

  # M2.1 Core Layer - Variables (3-tuple format)

  def transform({:variable, _meta, name}, _metadata) do
    {:ok, %{"type" => "var", "name" => name}}
  end

  # M2.1 Core Layer - Unary Operations (3-tuple format)

  def transform({:unary_op, meta, [operand]}, _metadata) when is_list(meta) do
    op = Keyword.get(meta, :operator)

    with {:ok, operand_ast} <- transform(operand, %{}) do
      case op do
        :- ->
          {:ok, %{"type" => "negate", "expression" => operand_ast}}

        _ ->
          {:ok,
           %{"type" => "prefix", "operator" => Atom.to_string(op), "expression" => operand_ast}}
      end
    end
  end

  # M2.1 Core Layer - Binary Operations (3-tuple format)
  def transform({:binary_op, meta, [left, right]}, _metadata) when is_list(meta) do
    op = Keyword.get(meta, :operator)

    if Keyword.get(meta, :category) == :pattern do
      # Infix constructor pattern: x : xs
      with {:ok, left_ast} <- transform_pattern(left),
           {:ok, right_ast} <- transform_pattern(right) do
        {:ok,
         %{
           "type" => "infix_pat",
           "left" => left_ast,
           "operator" => to_string(op),
           "right" => right_ast
         }}
      end
    else
      with {:ok, left_ast} <- transform(left, %{}),
           {:ok, right_ast} <- transform(right, %{}) do
        {:ok,
         %{
           "type" => "infix",
           "left" => left_ast,
           "operator" => to_string(op),
           "right" => right_ast
         }}
      end
    end
  end

  # M2.1 Core Layer - Ranges (enum sequences)

  def transform({:range, meta, [from, to]}, _metadata) when is_list(meta) do
    with {:ok, from_ast} <- transform(from, %{}),
         {:ok, to_ast} <- transform(to, %{}) do
      {:ok, %{"type" => "enum_from_to", "from" => from_ast, "to" => to_ast}}
    end
  end

  # Pattern-shaped nodes reached outside a match arm (e.g. do-notation
  # generators) are reified with the pattern reifier.

  def transform({:tuple, meta, elements}, _metadata) when is_list(meta) do
    if Keyword.get(meta, :pattern, false) do
      transform_pattern({:tuple, meta, elements})
    else
      transform_collection(elements, :tuple)
    end
  end

  def transform({:list, meta, elements}, _metadata) when is_list(meta) do
    if Keyword.get(meta, :pattern, false) do
      transform_pattern({:list, meta, elements})
    else
      transform_collection(elements, Keyword.get(meta, :collection_type, :list))
    end
  end

  def transform({:function_call, meta, args}, _metadata) when is_list(meta) do
    if Keyword.get(meta, :pattern, false) do
      transform_pattern({:function_call, meta, args})
    else
      transform_function_call(Keyword.get(meta, :name), args)
    end
  end

  # M2.1 Core Layer - Maps (Haskell record construction)

  def transform({:map, meta, pairs}, _metadata) when is_list(meta) do
    if Keyword.get(meta, :record, false) do
      transform_record_constr(Keyword.get(meta, :constructor), pairs)
    else
      {:error, "Unsupported MetaAST construct for Haskell reification: map without :record"}
    end
  end

  # M2.1 Core Layer - Lambda (3-tuple format)

  def transform({:lambda, meta, [body]}, _metadata) when is_list(meta) do
    params = Keyword.get(meta, :params, [])

    patterns =
      Enum.map(params, fn
        {:param, _meta, name} when is_binary(name) -> %{"type" => "var_pat", "name" => name}
        name when is_binary(name) -> %{"type" => "var_pat", "name" => name}
        _ -> %{"type" => "var_pat", "name" => "_"}
      end)

    with {:ok, body_ast} <- transform(body, %{}) do
      {:ok,
       %{
         "type" => "lambda",
         "patterns" => patterns,
         "body" => body_ast
       }}
    end
  end

  # M2.1 Core Layer - Conditionals (3-tuple format)

  def transform({:conditional, _meta, [condition, then_branch, else_branch]}, _metadata) do
    with {:ok, cond_ast} <- transform(condition, %{}),
         {:ok, then_ast} <- transform(then_branch, %{}),
         {:ok, else_ast} <- transform(else_branch, %{}) do
      {:ok,
       %{
         "type" => "if",
         "condition" => cond_ast,
         "then" => then_ast,
         "else" => else_ast
       }}
    end
  end

  # M2.1 Core Layer - Blocks (3-tuple format)

  def transform({:block, meta, statements}, _metadata) when is_list(meta) do
    construct = Keyword.get(meta, :construct)
    transform_block(statements, construct)
  end

  # M2.1 Core Layer - Assignment (3-tuple format)

  def transform({:assignment, _meta, [{:variable, _, name}, value]}, _metadata) do
    with {:ok, value_ast} <- transform(value, %{}) do
      {:ok,
       %{
         "type" => "pat_bind",
         "pattern" => %{"type" => "var_pat", "name" => name},
         "rhs" => value_ast
       }}
    end
  end

  # M2.2 Extended Layer - Pattern Matching (3-tuple format)

  def transform({:pattern_match, _meta, [scrutinee | arms]}, _metadata)
      when is_list(arms) do
    with {:ok, scrutinee_ast} <- transform(scrutinee, %{}),
         {:ok, branches_ast} <- transform_match_arms(arms) do
      {:ok,
       %{
         "type" => "case",
         "scrutinee" => scrutinee_ast,
         "alternatives" => branches_ast
       }}
    end
  end

  # M2.3 Native Layer - Passthrough (3-tuple format)

  def transform({:language_specific, meta, original_ast}, _metadata) when is_list(meta) do
    language = Keyword.get(meta, :language)

    if language == :haskell do
      {:ok, original_ast}
    else
      {:error, "Cannot reify language_specific node for #{language} to Haskell"}
    end
  end

  # Nil handling

  def transform(nil, _metadata), do: {:ok, nil}

  # Wildcard pattern

  def transform(:_, _metadata), do: {:ok, %{"type" => "wildcard"}}

  # Catch-all

  def transform(unsupported, _metadata) do
    {:error, "Unsupported MetaAST construct for Haskell reification: #{inspect(unsupported)}"}
  end

  # Helper Functions

  defp transform_literal(:integer, value) do
    {:ok,
     %{
       "type" => "literal",
       "value" => %{"literalType" => "int", "value" => value}
     }}
  end

  defp transform_literal(:float, value) do
    {:ok,
     %{
       "type" => "literal",
       "value" => %{"literalType" => "float", "value" => value}
     }}
  end

  defp transform_literal(:string, value) do
    {:ok,
     %{
       "type" => "literal",
       "value" => %{"literalType" => "string", "value" => value}
     }}
  end

  defp transform_literal(:char, value) do
    {:ok,
     %{
       "type" => "literal",
       "value" => %{"literalType" => "char", "value" => value}
     }}
  end

  defp transform_literal(:constructor, name) do
    {:ok, %{"type" => "con", "name" => name}}
  end

  defp transform_literal(type, value) do
    {:error, "Unsupported literal type: #{inspect(type)} with value #{inspect(value)}"}
  end

  defp transform_list(items) when is_list(items) do
    items
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
      case transform(item, %{}) do
        {:ok, ast} -> {:cont, {:ok, [ast | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, items_ast} -> {:ok, Enum.reverse(items_ast)}
      error -> error
    end
  end

  defp transform_function_call(name, args) do
    with {:ok, args_ast} <- transform_list(args) do
      # Build curried application for Haskell
      func_ast = %{"type" => "var", "name" => name}

      result =
        Enum.reduce(args_ast, func_ast, fn arg, acc ->
          %{
            "type" => "app",
            "function" => acc,
            "argument" => arg
          }
        end)

      {:ok, result}
    end
  end

  defp transform_record_constr(name, pairs) when is_binary(name) and is_list(pairs) do
    pairs
    |> Enum.reduce_while({:ok, []}, fn
      {:pair, _meta, [key, value]}, {:ok, acc} ->
        with {:ok, key_name} <- record_field_name(key),
             {:ok, value_ast} <- transform(value, %{}) do
          field = %{"name" => key_name, "value" => value_ast}
          {:cont, {:ok, [field | acc]}}
        else
          {:error, _} = err -> {:halt, err}
        end

      other, {:ok, _acc} ->
        {:halt, {:error, "Expected pair in record construction, got: #{inspect(other)}"}}
    end)
    |> case do
      {:ok, fields} ->
        {:ok, %{"type" => "record_constr", "name" => name, "fields" => Enum.reverse(fields)}}

      error ->
        error
    end
  end

  defp transform_record_constr(nil, _pairs) do
    {:error, "Record construction requires a :constructor name"}
  end

  defp record_field_name({:literal, _meta, name}) when is_binary(name), do: {:ok, name}
  defp record_field_name({:variable, _meta, name}) when is_binary(name), do: {:ok, name}

  defp record_field_name(other),
    do: {:error, "Unsupported record field name: #{inspect(other)}"}

  defp transform_let_block(statements) do
    # Extract assignments and body
    {assignments, body_stmts} =
      Enum.split_while(statements, fn
        {:assignment, _, _} -> true
        _ -> false
      end)

    with {:ok, bindings_ast} <- transform_let_bindings(assignments),
         {:ok, body_ast} <- transform_let_body(body_stmts) do
      {:ok,
       %{
         "type" => "let",
         "bindings" => bindings_ast,
         "body" => body_ast
       }}
    end
  end

  defp transform_let_bindings(assignments) do
    assignments
    |> Enum.reduce_while({:ok, []}, fn
      {:assignment, _meta, [{:variable, _, name}, value]}, {:ok, acc} ->
        case transform(value, %{}) do
          {:ok, value_ast} ->
            binding = %{
              "type" => "pat_bind",
              "pattern" => %{"type" => "var_pat", "name" => name},
              "rhs" => value_ast
            }

            {:cont, {:ok, [binding | acc]}}

          {:error, _} = err ->
            {:halt, err}
        end

      other, {:ok, _acc} ->
        {:halt, {:error, "Expected assignment in let bindings, got: #{inspect(other)}"}}
    end)
    |> case do
      {:ok, bindings} -> {:ok, Enum.reverse(bindings)}
      error -> error
    end
  end

  defp transform_let_body([]), do: {:ok, %{"type" => "con", "name" => "()"}}

  defp transform_let_body([single]), do: transform(single, %{})

  defp transform_let_body(stmts) do
    with {:ok, stmts_ast} <- transform_list(stmts) do
      {:ok, %{"type" => "begin", "statements" => stmts_ast}}
    end
  end

  defp transform_match_arms(arms) when is_list(arms) do
    arms
    |> Enum.reduce_while({:ok, []}, fn arm, {:ok, acc} ->
      case transform_match_arm(arm) do
        {:ok, branch_ast} -> {:cont, {:ok, [branch_ast | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, branches_ast} -> {:ok, Enum.reverse(branches_ast)}
      error -> error
    end
  end

  # Standard match_arm format: {:match_arm, [pattern: pattern], [body]}
  defp transform_match_arm({:match_arm, meta, body_list}) when is_list(meta) do
    pattern = Keyword.get(meta, :pattern)
    body = List.last(body_list)

    with {:ok, pattern_ast} <- transform_pattern(pattern),
         {:ok, body_ast} <- transform(body, %{}) do
      {:ok, %{"pattern" => pattern_ast, "rhs" => body_ast}}
    end
  end

  defp transform_match_arm(other) do
    {:error, "Expected match_arm in case branch, got: #{inspect(other)}"}
  end

  defp transform_pattern({:variable, _meta, name}) do
    {:ok, %{"type" => "var_pat", "name" => name}}
  end

  defp transform_pattern({:literal, meta, value}) when is_list(meta) do
    subtype = Keyword.get(meta, :subtype)

    if subtype in [:integer, :string, :char] do
      literal_ast = %{
        "literalType" => Atom.to_string(subtype),
        "value" => value
      }

      {:ok, %{"type" => "lit_pat", "literal" => literal_ast}}
    else
      {:error, "Unsupported literal type in pattern: #{subtype}"}
    end
  end

  defp transform_pattern(:_) do
    {:ok, %{"type" => "wildcard"}}
  end

  # Constructor pattern: {:function_call, [name: "Just"], [arg]}
  defp transform_pattern({:function_call, meta, args}) when is_list(meta) do
    with {:ok, args_ast} <- transform_pattern_list(args) do
      {:ok, %{"type" => "con_pat", "name" => Keyword.get(meta, :name), "patterns" => args_ast}}
    end
  end

  # Tuple pattern
  defp transform_pattern({:tuple, _meta, elements}) when is_list(elements) do
    with {:ok, elements_ast} <- transform_pattern_list(elements) do
      {:ok, %{"type" => "tuple_pat", "elements" => elements_ast}}
    end
  end

  # List pattern
  defp transform_pattern({:list, _meta, elements}) when is_list(elements) do
    with {:ok, elements_ast} <- transform_pattern_list(elements) do
      {:ok, %{"type" => "list_pat", "elements" => elements_ast}}
    end
  end

  # Infix constructor pattern: x : xs
  defp transform_pattern({:binary_op, meta, [left, right]}) when is_list(meta) do
    with {:ok, left_ast} <- transform_pattern(left),
         {:ok, right_ast} <- transform_pattern(right) do
      {:ok,
       %{
         "type" => "infix_pat",
         "left" => left_ast,
         "operator" => to_string(Keyword.get(meta, :operator)),
         "right" => right_ast
       }}
    end
  end

  # Record pattern
  defp transform_pattern({:map, meta, pairs}) when is_list(meta) do
    with true <- Keyword.get(meta, :record, false),
         {:ok, fields} <- transform_record_pattern_fields(pairs) do
      {:ok,
       %{
         "type" => "record_pat",
         "name" => Keyword.get(meta, :constructor),
         "fields" => fields
       }}
    else
      _ -> {:error, "Unsupported map pattern for reification"}
    end
  end

  defp transform_pattern(other),
    do: {:error, "Unsupported pattern for reification: #{inspect(other)}"}

  defp transform_pattern_list(pats) when is_list(pats) do
    pats
    |> Enum.reduce_while({:ok, []}, fn pat, {:ok, acc} ->
      case transform_pattern(pat) do
        {:ok, ast} -> {:cont, {:ok, [ast | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, asts} -> {:ok, Enum.reverse(asts)}
      error -> error
    end
  end

  defp transform_record_pattern_fields(pairs) when is_list(pairs) do
    pairs
    |> Enum.reduce_while({:ok, []}, fn
      {:pair, _meta, [key, value]}, {:ok, acc} ->
        with {:ok, key_name} <- record_field_name(key),
             {:ok, pat_ast} <- transform_pattern(value) do
          {:cont, {:ok, [%{"name" => key_name, "pattern" => pat_ast} | acc]}}
        else
          {:error, _} = err -> {:halt, err}
        end

      other, {:ok, _acc} ->
        {:halt, {:error, "Expected pair in record pattern, got: #{inspect(other)}"}}
    end)
    |> case do
      {:ok, fields} -> {:ok, Enum.reverse(fields)}
      error -> error
    end
  end

  defp transform_collection(elements, :list) do
    with {:ok, elements_ast} <- transform_list(elements) do
      {:ok, %{"type" => "list", "elements" => elements_ast}}
    end
  end

  defp transform_collection(elements, :tuple) do
    with {:ok, elements_ast} <- transform_list(elements) do
      {:ok, %{"type" => "tuple", "elements" => elements_ast}}
    end
  end

  defp transform_collection(elements, _collection_type) do
    # Default to list
    with {:ok, elements_ast} <- transform_list(elements) do
      {:ok, %{"type" => "list", "elements" => elements_ast}}
    end
  end

  defp transform_block(statements, :let) do
    transform_let_block(statements)
  end

  defp transform_block(statements, _construct) do
    # Generic block - transform as begin block
    with {:ok, statements_ast} <- transform_list(statements) do
      case statements_ast do
        [single] -> {:ok, single}
        multiple -> {:ok, %{"type" => "begin", "statements" => multiple}}
      end
    end
  end
end
