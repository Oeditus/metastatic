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

  # M2.3 Native Layer - Passthrough

  def transform({:language_specific, :haskell, original_ast, _construct_type}, _metadata) do
    {:ok, original_ast}
  end

  # Catch-all

  def transform(unsupported, _metadata) do
    {:error, "Unsupported MetaAST construct for Haskell reification: #{inspect(unsupported)}"}
  end
end
