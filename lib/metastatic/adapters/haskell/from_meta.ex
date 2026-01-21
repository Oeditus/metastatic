defmodule Metastatic.Adapters.Haskell.FromMeta do
  @moduledoc """
  Transform MetaAST (M2) back to Haskell AST (M1).

  This module implements the reification function ρ_Haskell that converts
  meta-level representations back to Haskell-specific AST structures.

  ## Status

  Basic M2.1 Core Layer support implemented.
  M2.2 Extended and M2.3 Native layers to be completed in future iterations.
  """

  @doc """
  Transform MetaAST back to Haskell AST.

  Returns `{:ok, haskell_ast}` on success or `{:error, reason}` on failure.
  """
  @spec transform(term(), map()) :: {:ok, term()} | {:error, String.t()}

  # M2.1 Core Layer - Literals

  def transform({:literal, :integer, value}, _metadata) do
    {:ok,
     %{
       "type" => "literal",
       "value" => %{"literalType" => "int", "value" => value}
     }}
  end

  def transform({:literal, :float, value}, _metadata) do
    {:ok,
     %{
       "type" => "literal",
       "value" => %{"literalType" => "float", "value" => value}
     }}
  end

  def transform({:literal, :string, value}, _metadata) do
    {:ok,
     %{
       "type" => "literal",
       "value" => %{"literalType" => "string", "value" => value}
     }}
  end

  # M2.1 Core Layer - Variables

  def transform({:variable, name}, _metadata) do
    {:ok, %{"type" => "var", "name" => name}}
  end

  # M2.1 Core Layer - Binary Operations

  def transform({:binary_op, _category, op, left, right}, _metadata) do
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

  # M2.1 Core Layer - Lambda

  def transform({:lambda, params, body}, _metadata) do
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

  # M2.1 Core Layer - Conditionals

  def transform({:conditional, condition, then_branch, else_branch}, _metadata) do
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

  # M2.1 Core Layer - Function Calls

  def transform({:function_call, name, args}, _metadata) do
    transform_function_call(name, args)
  end

  # M2.1 Core Layer - Collections

  def transform({:literal, :collection, elements, metadata}, _ignore) do
    transform_collection(elements, metadata)
  end

  def transform({:literal, :collection, elements}, metadata) when is_map(metadata) do
    transform_collection(elements, metadata)
  end

  def transform({:literal, :constructor, name}, _metadata) do
    {:ok, %{"type" => "con", "name" => name}}
  end

  # M2.1 Core Layer - Blocks (let bindings)

  def transform({:block, statements, metadata}, _ignore) do
    transform_block(statements, metadata)
  end

  def transform({:block, statements}, metadata) when is_map(metadata) do
    transform_block(statements, metadata)
  end

  # M2.2 Extended Layer - Pattern Matching

  def transform({:pattern_match, scrutinee, branches, _else_branch}, _metadata) do
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

  # M2.3 Native Layer - Passthrough

  def transform({:language_specific, :haskell, original_ast, _construct_type}, _metadata) do
    {:ok, original_ast}
  end

  # Nil handling

  def transform(nil, _metadata), do: {:ok, nil}

  # Catch-all

  def transform(unsupported, _metadata) do
    {:error, "Unsupported MetaAST construct for Haskell reification: #{inspect(unsupported)}"}
  end

  # Helper Functions

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
    |> Enum.reduce_while({:ok, []}, fn {:assignment, {:variable, name}, value}, {:ok, acc} ->
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

  defp transform_case_branches(branches) do
    branches
    |> Enum.reduce_while({:ok, []}, fn {pattern, body}, {:ok, acc} ->
      case transform_case_branch(pattern, body) do
        {:ok, branch_ast} -> {:cont, {:ok, [branch_ast | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, branches_ast} -> {:ok, Enum.reverse(branches_ast)}
      error -> error
    end
  end

  defp transform_case_branch(pattern, body) do
    with {:ok, pattern_ast} <- transform_pattern(pattern),
         {:ok, body_ast} <- transform(body, %{}) do
      {:ok, %{"pattern" => pattern_ast, "rhs" => body_ast}}
    end
  end

  defp transform_pattern({:variable, name}) do
    {:ok, %{"type" => "var_pat", "name" => name}}
  end

  defp transform_pattern({:literal, type, value}) when type in [:integer, :string, :char] do
    literal_ast = %{
      "literalType" => Atom.to_string(type),
      "value" => value
    }

    {:ok, %{"type" => "lit_pat", "literal" => literal_ast}}
  end

  defp transform_pattern(:_) do
    {:ok, %{"type" => "wildcard"}}
  end

  defp transform_pattern(_), do: {:error, "Unsupported pattern for reification"}

  defp transform_collection(elements, %{collection_type: :list}) do
    with {:ok, elements_ast} <- transform_list(elements) do
      {:ok, %{"type" => "list", "elements" => elements_ast}}
    end
  end

  defp transform_collection(elements, %{collection_type: :tuple}) do
    with {:ok, elements_ast} <- transform_list(elements) do
      {:ok, %{"type" => "tuple", "elements" => elements_ast}}
    end
  end

  defp transform_collection(elements, _metadata) do
    # Default to list
    with {:ok, elements_ast} <- transform_list(elements) do
      {:ok, %{"type" => "list", "elements" => elements_ast}}
    end
  end

  defp transform_block(statements, %{construct: :let}) do
    transform_let_block(statements)
  end

  defp transform_block(statements, _metadata) do
    # Generic block - transform as begin block
    with {:ok, statements_ast} <- transform_list(statements) do
      case statements_ast do
        [single] -> {:ok, single}
        multiple -> {:ok, %{"type" => "begin", "statements" => multiple}}
      end
    end
  end
end
