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

  # M2.1 Core Layer - Binary Operations (3-tuple format)

  def transform({:binary_op, meta, [left, right]}, _metadata) when is_list(meta) do
    op = Keyword.get(meta, :operator)

    with {:ok, left_ast} <- transform(left, %{}),
         {:ok, right_ast} <- transform(right, %{}) do
      {:ok,
       %{
         "type" => "infix",
         "left" => left_ast,
         "operator" => Atom.to_string(op),
         "right" => right_ast
       }}
    end
  end

  # M2.1 Core Layer - Lambda (3-tuple format)

  def transform({:lambda, meta, [body]}, _metadata) when is_list(meta) do
    params = Keyword.get(meta, :params, [])
    patterns = Enum.map(params, fn param -> %{"type" => "var_pat", "name" => param} end)

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

  # M2.1 Core Layer - Function Calls (3-tuple format)

  def transform({:function_call, meta, args}, _metadata) when is_list(meta) do
    name = Keyword.get(meta, :name)
    transform_function_call(name, args)
  end

  # M2.1 Core Layer - Lists (3-tuple format)

  def transform({:list, meta, elements}, _metadata) when is_list(meta) do
    collection_type = Keyword.get(meta, :collection_type, :list)
    transform_collection(elements, collection_type)
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

  def transform({:pattern_match, _meta, [scrutinee, branches, _else_branch]}, _metadata) do
    with {:ok, scrutinee_ast} <- transform(scrutinee, %{}),
         {:ok, branches_ast} <- transform_case_branches(branches) do
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

  defp transform_case_branches(branches) when is_list(branches) do
    branches
    |> Enum.reduce_while({:ok, []}, fn branch, {:ok, acc} ->
      case transform_case_branch(branch) do
        {:ok, branch_ast} -> {:cont, {:ok, [branch_ast | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, branches_ast} -> {:ok, Enum.reverse(branches_ast)}
      error -> error
    end
  end

  # 3-tuple pair format: {:pair, [], [pattern, body]}
  defp transform_case_branch({:pair, _meta, [pattern, body]}) do
    with {:ok, pattern_ast} <- transform_pattern(pattern),
         {:ok, body_ast} <- transform(body, %{}) do
      {:ok, %{"pattern" => pattern_ast, "rhs" => body_ast}}
    end
  end

  defp transform_case_branch(other) do
    {:error, "Expected pair in case branch, got: #{inspect(other)}"}
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

  defp transform_pattern(other),
    do: {:error, "Unsupported pattern for reification: #{inspect(other)}"}

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
