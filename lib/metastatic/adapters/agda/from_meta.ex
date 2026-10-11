defmodule Metastatic.Adapters.Agda.FromMeta do
  @moduledoc """
  Transform MetaAST (M2) back to Agda AST (M1).

  This module implements the reification function ρ_Agda that converts
  meta-level representations back to Agda-specific AST structures.
  """

  @doc """
  Transform MetaAST back to Agda AST.

  Returns `{:ok, agda_ast}` on success or `{:error, reason}` on failure.
  """
  @spec transform(term(), map()) :: {:ok, term()} | {:error, String.t()}
  def transform(meta_ast, metadata \\ %{})

  # Literals
  def transform({:literal, meta, value}, _metadata) when is_list(meta) do
    subtype = Keyword.get(meta, :subtype, :integer)
    transform_literal(subtype, value)
  end

  # Variables
  def transform({:variable, _meta, name}, _metadata) do
    {:ok, %{"type" => "var", "name" => name}}
  end

  # Binary Operations
  def transform({:binary_op, meta, [left, right]}, _metadata) when is_list(meta) do
    op = Keyword.get(meta, :operator, :+)

    with {:ok, left_ast} <- transform(left, %{}),
         {:ok, right_ast} <- transform(right, %{}) do
      {:ok,
       %{
         "type" => "infix",
         "operator" => Atom.to_string(op),
         "left" => left_ast,
         "right" => right_ast
       }}
    end
  end

  # Function Calls / Application
  def transform({:function_call, meta, args}, _metadata) when is_list(meta) do
    name = Keyword.get(meta, :name, "f")

    with {:ok, args_ast} <- transform_list(args) do
      {:ok,
       %{
         "type" => "raw_app",
         "elements" => [%{"type" => "var", "name" => name} | args_ast]
       }}
    end
  end

  # Lambdas
  def transform({:lambda, meta, [body]}, _metadata) when is_list(meta) do
    params = Keyword.get(meta, :params, ["x"])

    with {:ok, body_ast} <- transform(body, %{}) do
      param_objs =
        Enum.map(params, fn p ->
          %{"type" => "domain_free", "name" => p, "implicit" => false}
        end)

      {:ok,
       %{
         "type" => "lambda",
         "parameters" => param_objs,
         "body" => body_ast
       }}
    end
  end

  # Type Annotations / Arrows
  def transform({:type_annotation, meta, [from, to]}, _metadata) when is_list(meta) do
    with {:ok, from_ast} <- transform(from, %{}),
         {:ok, to_ast} <- transform(to, %{}) do
      {:ok,
       %{
         "type" => "arrow",
         "from" => from_ast,
         "to" => to_ast
       }}
    end
  end

  # Function Definitions
  def transform({:function_def, meta, [body]}, _metadata) when is_list(meta) do
    name = Keyword.get(meta, :name, "f")
    params = Keyword.get(meta, :params, [])

    with {:ok, body_ast} <- transform(body, %{}) do
      lhs =
        if params == [] do
          %{"type" => "var_pat", "name" => name}
        else
          %{
            "type" => "app_pat",
            "elements" => [
              %{"type" => "var_pat", "name" => name}
              | Enum.map(params, fn p -> %{"type" => "var_pat", "name" => p} end)
            ]
          }
        end

      {:ok,
       %{
         "type" => "fun_clause",
         "lhs" => lhs,
         "rhs" => %{"type" => "rhs", "expression" => body_ast},
         "where" => nil
       }}
    end
  end

  # Type Definitions (signatures, data, records)
  def transform({:type_def, meta, children}, _metadata) when is_list(meta) do
    name = Keyword.get(meta, :name, "T")
    kind = Keyword.get(meta, :kind, :signature)

    case {kind, children} do
      {:signature, [sig]} ->
        with {:ok, sig_ast} <- transform(sig, %{}) do
          {:ok,
           %{
             "type" => "type_sig",
             "name" => name,
             "signature" => sig_ast
           }}
        end

      {:data, [type_expr | ctors]} ->
        with {:ok, type_ast} <- transform(type_expr, %{}),
             {:ok, ctors_ast} <- transform_list(ctors) do
          {:ok,
           %{
             "type" => "data",
             "name" => name,
             "params" => [],
             "typeExpr" => type_ast,
             "constructors" => ctors_ast
           }}
        end

      _ ->
        {:ok,
         %{
           "type" => "other_decl",
           "text" => "#{name} : Set"
         }}
    end
  end

  # Modules / Containers
  def transform({:container, meta, decls}, _metadata) when is_list(meta) do
    name = Keyword.get(meta, :name)

    with {:ok, decls_ast} <- transform_list(decls) do
      {:ok,
       %{
         "type" => "module",
         "name" => name,
         "declarations" => decls_ast
       }}
    end
  end

  # Imports
  def transform({:import, meta, _}, _metadata) when is_list(meta) do
    mod = Keyword.get(meta, :module, "")
    open = Keyword.get(meta, :open, false)

    {:ok,
     %{
       "type" => "import",
       "module" => mod,
       "open" => open
     }}
  end

  # Language-specific nodes
  def transform({:language_specific, meta, children}, _metadata) when is_list(meta) do
    construct = Keyword.get(meta, :construct)

    case construct do
      :postulate ->
        with {:ok, decls_ast} <- transform_list(children) do
          {:ok, %{"type" => "postulate", "declarations" => decls_ast}}
        end

      :fixity ->
        fixity = Keyword.get(meta, :fixity, "infix 20")
        names = Keyword.get(meta, :names, [])
        {:ok, %{"type" => "infix_decl", "fixity" => fixity, "names" => names}}

      _ ->
        text = Keyword.get(meta, :text, "")
        {:ok, %{"type" => "other_decl", "text" => text}}
    end
  end

  def transform(other, _) do
    {:error, "Unsupported MetaAST node for Agda: #{inspect(other)}"}
  end

  defp transform_literal(:integer, val),
    do: {:ok, %{"type" => "literal", "value" => %{"literalType" => "int", "value" => val}}}

  defp transform_literal(:float, val),
    do: {:ok, %{"type" => "literal", "value" => %{"literalType" => "float", "value" => val}}}

  defp transform_literal(:string, val),
    do: {:ok, %{"type" => "literal", "value" => %{"literalType" => "string", "value" => val}}}

  defp transform_literal(:char, val),
    do: {:ok, %{"type" => "literal", "value" => %{"literalType" => "char", "value" => val}}}

  defp transform_literal(_, val),
    do:
      {:ok,
       %{"type" => "literal", "value" => %{"literalType" => "string", "value" => to_string(val)}}}

  defp transform_list(elements) when is_list(elements) do
    Enum.reduce_while(elements, {:ok, []}, fn elem, {:ok, acc} ->
      case transform(elem, %{}) do
        {:ok, ast} -> {:cont, {:ok, [ast | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, list} -> {:ok, Enum.reverse(list)}
      error -> error
    end
  end
end
