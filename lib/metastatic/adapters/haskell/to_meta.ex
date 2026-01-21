defmodule Metastatic.Adapters.Haskell.ToMeta do
  @moduledoc """
  Transform Haskell AST (M1) to MetaAST (M2).

  Implements the abstraction function α_Haskell that lifts Haskell-specific
  AST structures to the meta-level representation.

  ## Transformation Strategy

  ### M2.1 (Core Layer)
  - Literals: integers, floats, strings, chars
  - Variables: unqualified and qualified names
  - Binary operators: arithmetic, comparison, boolean
  - Function application
  - Conditionals: if-then-else
  - Lambdas: anonymous functions
  - Let bindings

  ### M2.2 (Extended Layer)
  - List comprehensions
  - Case expressions (pattern matching)
  - Do notation (monadic sequencing)

  ### M2.3 (Native Layer)
  - Type signatures
  - Data type definitions
  - Type class definitions
  - Module definitions
  """

  @doc """
  Transform Haskell AST to MetaAST.

  Returns `{:ok, meta_ast, metadata}` on success or `{:error, reason}` on failure.
  """
  @spec transform(term()) :: {:ok, term(), map()} | {:error, String.t()}

  # M2.1 Core Layer - Literals

  def transform(%{"type" => "literal", "value" => value}) do
    transform_literal(value)
  end

  # M2.1 Core Layer - Variables

  def transform(%{"type" => "var", "name" => name}) do
    {:ok, {:variable, name}, %{}}
  end

  # M2.1 Core Layer - Constructors (data constructors)

  def transform(%{"type" => "con", "name" => name}) do
    {:ok, {:literal, :constructor, name}, %{}}
  end

  # M2.1 Core Layer - Function Application

  def transform(%{"type" => "app", "function" => func, "argument" => arg}) do
    with {:ok, func_meta, _} <- transform(func),
         {:ok, arg_meta, _} <- transform(arg) do
      # Haskell function application: f x
      case func_meta do
        {:function_call, name, args} ->
          # Accumulate curried arguments
          {:ok, {:function_call, name, args ++ [arg_meta]}, %{}}

        _ ->
          # First application
          {:ok, {:function_call, format_function(func_meta), [arg_meta]}, %{}}
      end
    end
  end

  # M2.1 Core Layer - Infix Operators

  def transform(%{"type" => "infix", "left" => left, "operator" => op, "right" => right}) do
    with {:ok, left_meta, _} <- transform(left),
         {:ok, right_meta, _} <- transform(right) do
      op_atom = normalize_op(op)

      cond do
        is_arithmetic_op?(op_atom) ->
          {:ok, {:binary_op, :arithmetic, op_atom, left_meta, right_meta}, %{}}

        is_comparison_op?(op_atom) ->
          {:ok, {:binary_op, :comparison, op_atom, left_meta, right_meta}, %{}}

        is_boolean_op?(op_atom) ->
          {:ok, {:binary_op, :boolean, op_atom, left_meta, right_meta}, %{}}

        true ->
          # Custom operator - treat as function call
          {:ok, {:function_call, op, [left_meta, right_meta]}, %{custom_op: true}}
      end
    end
  end

  # M2.1 Core Layer - Lambda Expressions

  def transform(%{"type" => "lambda", "patterns" => patterns, "body" => body}) do
    with {:ok, params} <- extract_lambda_params(patterns),
         {:ok, body_meta, _} <- transform(body) do
      {:ok, {:lambda, params, body_meta}, %{}}
    end
  end

  # M2.1 Core Layer - Let Bindings

  def transform(%{"type" => "let", "bindings" => bindings, "body" => body}) do
    with {:ok, bindings_meta} <- transform_bindings(bindings),
         {:ok, body_meta, _} <- transform(body) do
      # Represent as block with assignments followed by body
      statements = bindings_meta ++ [body_meta]
      {:ok, {:block, statements}, %{construct: :let}}
    end
  end

  # M2.1 Core Layer - If-Then-Else

  def transform(%{"type" => "if", "condition" => cond, "then" => then_exp, "else" => else_exp}) do
    with {:ok, cond_meta, _} <- transform(cond),
         {:ok, then_meta, _} <- transform(then_exp),
         {:ok, else_meta, _} <- transform(else_exp) do
      {:ok, {:conditional, cond_meta, then_meta, else_meta}, %{}}
    end
  end

  # M2.1 Core Layer - Lists

  def transform(%{"type" => "list", "elements" => elements}) do
    with {:ok, elements_meta} <- transform_list(elements) do
      {:ok, {:literal, :collection, elements_meta}, %{collection_type: :list}}
    end
  end

  # M2.1 Core Layer - Tuples

  def transform(%{"type" => "tuple", "elements" => elements}) do
    with {:ok, elements_meta} <- transform_list(elements) do
      {:ok, {:literal, :collection, elements_meta}, %{collection_type: :tuple}}
    end
  end

  # M2.2 Extended Layer - Case Expressions (Pattern Matching)

  def transform(%{"type" => "case", "scrutinee" => scrutinee, "alternatives" => alts}) do
    with {:ok, scrutinee_meta, _} <- transform(scrutinee),
         {:ok, branches_meta} <- transform_case_alts(alts) do
      # No explicit else in Haskell case - last pattern is typically catch-all
      {:ok, {:pattern_match, scrutinee_meta, branches_meta, nil}, %{}}
    end
  end

  # M2.2 Extended Layer - List Comprehensions

  def transform(%{
        "type" => "list_comp",
        "expression" => expr,
        "qualifiers" => quals
      }) do
    with {:ok, expr_meta, _} <- transform(expr),
         {:ok, quals_meta} <- transform_qualifiers(quals) do
      # Represent as collection_op with custom metadata
      {:ok,
       {:language_specific, :haskell, %{"expr" => expr_meta, "quals" => quals_meta}, :list_comp},
       %{}}
    end
  end

  # M2.2 Extended Layer - Do Notation

  def transform(%{"type" => "do", "statements" => stmts}) do
    with {:ok, stmts_meta} <- transform_do_statements(stmts) do
      {:ok, {:block, stmts_meta}, %{construct: :do_notation}}
    end
  end

  # M2.3 Native Layer - Module

  def transform(%{"type" => "module", "declarations" => decls}) do
    with {:ok, decls_meta} <- transform_declarations(decls) do
      {:ok, {:language_specific, :haskell, %{"declarations" => decls_meta}, :module}, %{}}
    end
  end

  # M2.3 Native Layer - Type Signature

  def transform(%{"type" => "type_sig", "names" => names, "signature" => sig}) do
    {:ok,
     {:language_specific, :haskell, %{"names" => names, "signature" => sig}, :type_signature},
     %{}}
  end

  # M2.3 Native Layer - Data Type Declaration

  def transform(%{
        "type" => "data_decl",
        "data_or_new" => kind,
        "name" => name,
        "constructors" => cons
      }) do
    {:ok,
     {:language_specific, :haskell, %{"kind" => kind, "name" => name, "constructors" => cons},
      :data_decl}, %{}}
  end

  # M2.3 Native Layer - Type Alias

  def transform(%{"type" => "type_alias", "name" => name, "definition" => def_type}) do
    {:ok,
     {:language_specific, :haskell, %{"name" => name, "definition" => def_type}, :type_alias},
     %{}}
  end

  # M2.3 Native Layer - Type Class Declaration

  def transform(%{"type" => "class_decl", "name" => name, "methods" => methods}) do
    {:ok, {:language_specific, :haskell, %{"name" => name, "methods" => methods}, :class_decl},
     %{}}
  end

  # M2.3 Native Layer - Instance Declaration

  def transform(%{"type" => "instance_decl", "rule" => rule, "methods" => methods}) do
    {:ok, {:language_specific, :haskell, %{"rule" => rule, "methods" => methods}, :instance_decl},
     %{}}
  end

  # M2.3 Native Layer - Function Binding

  def transform(%{"type" => "fun_bind", "matches" => matches}) do
    # Try to extract function name and transform to a more useful representation
    case extract_function_from_matches(matches) do
      {:ok, name, body} ->
        {:ok, {:assignment, {:variable, name}, body}, %{construct: :function_binding}}

      :error ->
        {:ok, {:language_specific, :haskell, %{"matches" => matches}, :function_binding}, %{}}
    end
  end

  # Unsupported constructs

  def transform(unsupported) do
    {:error, "Unsupported Haskell AST construct: #{inspect(unsupported)}"}
  end

  # Helper Functions

  defp transform_literal(%{"literalType" => "int", "value" => value}) do
    {:ok, {:literal, :integer, value}, %{}}
  end

  defp transform_literal(%{"literalType" => "float", "value" => value}) do
    {:ok, {:literal, :float, value}, %{}}
  end

  defp transform_literal(%{"literalType" => "string", "value" => value}) do
    {:ok, {:literal, :string, value}, %{}}
  end

  defp transform_literal(%{"literalType" => "char", "value" => value}) do
    {:ok, {:literal, :char, value}, %{}}
  end

  defp transform_literal(_), do: {:error, "Unknown literal type"}

  defp transform_list(items) when is_list(items) do
    items
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
      case transform(item) do
        {:ok, meta, _} -> {:cont, {:ok, [meta | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, items} -> {:ok, Enum.reverse(items)}
      error -> error
    end
  end

  defp extract_lambda_params(patterns) when is_list(patterns) do
    params =
      Enum.map(patterns, fn
        %{"type" => "var_pat", "name" => name} -> name
        _ -> "_"
      end)

    {:ok, params}
  end

  defp transform_bindings(bindings) when is_list(bindings) do
    bindings
    |> Enum.reduce_while({:ok, []}, fn binding, {:ok, acc} ->
      case transform_binding(binding) do
        {:ok, meta} -> {:cont, {:ok, [meta | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, bindings} -> {:ok, Enum.reverse(bindings)}
      error -> error
    end
  end

  defp transform_binding(%{"type" => "pat_bind", "pattern" => pat, "rhs" => rhs}) do
    with {:ok, var_name} <- extract_pattern_var(pat),
         {:ok, value_meta, _} <- transform(rhs) do
      {:ok, {:assignment, {:variable, var_name}, value_meta}}
    end
  end

  defp transform_binding(_), do: {:error, "Unsupported binding"}

  defp extract_pattern_var(%{"type" => "var_pat", "name" => name}), do: {:ok, name}
  defp extract_pattern_var(_), do: {:error, "Complex pattern in let binding"}

  defp transform_case_alts(alts) when is_list(alts) do
    alts
    |> Enum.reduce_while({:ok, []}, fn alt, {:ok, acc} ->
      case transform_case_alt(alt) do
        {:ok, branch} -> {:cont, {:ok, [branch | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, branches} -> {:ok, Enum.reverse(branches)}
      error -> error
    end
  end

  defp transform_case_alt(%{"pattern" => pat, "rhs" => rhs}) do
    with {:ok, pat_meta} <- transform_pattern(pat),
         {:ok, rhs_meta, _} <- transform(rhs) do
      {:ok, {pat_meta, rhs_meta}}
    end
  end

  defp transform_pattern(%{"type" => "var_pat", "name" => name}) do
    {:ok, {:variable, name}}
  end

  defp transform_pattern(%{"type" => "lit_pat", "literal" => lit}) do
    case transform_literal(lit) do
      {:ok, lit_meta, _} -> {:ok, lit_meta}
      error -> error
    end
  end

  defp transform_pattern(%{"type" => "wildcard"}) do
    {:ok, :_}
  end

  defp transform_pattern(_), do: {:error, "Unsupported pattern"}

  defp transform_qualifiers(quals) when is_list(quals) do
    quals
    |> Enum.reduce_while({:ok, []}, fn qual, {:ok, acc} ->
      case transform_qualifier(qual) do
        {:ok, meta} -> {:cont, {:ok, [meta | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, quals_list} -> {:ok, Enum.reverse(quals_list)}
      error -> error
    end
  end

  defp transform_qualifier(%{"type" => "generator", "pattern" => pat, "expression" => expr}) do
    with {:ok, pat_meta} <- transform_pattern(pat),
         {:ok, expr_meta, _} <- transform(expr) do
      {:ok, {:generator, pat_meta, expr_meta}}
    end
  end

  defp transform_qualifier(%{"type" => "qualifier", "expression" => expr}) do
    with {:ok, expr_meta, _} <- transform(expr) do
      {:ok, {:qualifier, expr_meta}}
    end
  end

  defp transform_qualifier(other), do: {:error, "Unsupported qualifier: #{inspect(other)}"}

  defp transform_do_statements(stmts) when is_list(stmts) do
    stmts
    |> Enum.reduce_while({:ok, []}, fn stmt, {:ok, acc} ->
      case transform_statement(stmt) do
        {:ok, meta} -> {:cont, {:ok, [meta | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, stmts_list} -> {:ok, Enum.reverse(stmts_list)}
      error -> error
    end
  end

  defp transform_statement(%{"type" => "generator", "pattern" => pat, "expression" => expr}) do
    with {:ok, pat_meta} <- transform_pattern(pat),
         {:ok, expr_meta, _} <- transform(expr) do
      {:ok, {:generator, pat_meta, expr_meta}}
    end
  end

  defp transform_statement(%{"type" => "qualifier", "expression" => expr}) do
    with {:ok, expr_meta, _} <- transform(expr) do
      {:ok, expr_meta}
    end
  end

  defp transform_statement(%{"type" => "let_stmt", "bindings" => bindings}) do
    transform_bindings(bindings)
  end

  defp transform_statement(other), do: {:error, "Unsupported statement: #{inspect(other)}"}

  defp format_function({:variable, name}), do: name
  defp format_function(_), do: "func"

  defp normalize_op(op) when is_binary(op), do: String.to_atom(op)
  defp normalize_op(op) when is_atom(op), do: op

  defp is_arithmetic_op?(op) when is_atom(op) do
    op in [:+, :-, :*, :/, :div, :mod, :^, :**]
  end

  defp is_comparison_op?(op) when is_atom(op) do
    op in [:==, :"/=", :<, :>, :<=, :>=]
  end

  defp is_boolean_op?(op) when is_atom(op) do
    op in [:&&, :||, :and, :or]
  end

  defp transform_declarations(decls) when is_list(decls) do
    decls
    |> Enum.reduce_while({:ok, []}, fn decl, {:ok, acc} ->
      case transform(decl) do
        {:ok, meta, _} -> {:cont, {:ok, [meta | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, decls_list} -> {:ok, Enum.reverse(decls_list)}
      error -> error
    end
  end

  defp extract_function_from_matches([match | _]) do
    # Extract function name and body from first match
    # Simplified: only handles simple cases
    case match do
      %{"name" => name, "patterns" => patterns, "rhs" => rhs} ->
        with {:ok, params} <- extract_match_params(patterns),
             {:ok, body_meta, _} <- transform(rhs) do
          # If it has parameters, represent as lambda
          if length(params) > 0 do
            {:ok, name, {:lambda, params, body_meta}}
          else
            {:ok, name, body_meta}
          end
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp extract_function_from_matches(_), do: :error

  defp extract_match_params(patterns) when is_list(patterns) do
    params =
      Enum.map(patterns, fn
        %{"type" => "var_pat", "name" => name} -> name
        _ -> "_"
      end)

    {:ok, params}
  end
end
