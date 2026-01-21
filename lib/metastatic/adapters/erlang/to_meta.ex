defmodule Metastatic.Adapters.Erlang.ToMeta do
  @moduledoc """
  Transform Erlang AST (M1) to MetaAST (M2).

  This module implements the abstraction function α_Erlang that lifts
  Erlang-specific AST structures to the meta-level representation.

  ## Erlang AST Patterns

  Erlang uses a consistent tuple-based format:
  - Literals: `{type, line, value}`
  - Variables: `{:var, line, name}`
  - Binary ops: `{:op, line, op, left, right}`
  - Calls: `{:call, line, func, args}`

  ## Metadata Preservation

  The transformation preserves M1-specific information:
  - `:line` - line number from source
  - `:erlang_form` - original Erlang construct type
  """

  @doc """
  Transform Erlang AST to MetaAST.

  Returns `{:ok, meta_ast, metadata}` on success or `{:error, reason}` on failure.
  """
  @spec transform(term()) :: {:ok, term(), map()} | {:error, String.t()}

  # Literals - M2.1 Core Layer

  def transform({:integer, _line, value}) do
    {:ok, {:literal, :integer, value}, %{}}
  end

  def transform({:float, _line, value}) do
    {:ok, {:literal, :float, value}, %{}}
  end

  def transform({:string, _line, charlist}) when is_list(charlist) do
    # Erlang strings are charlists - convert to binary
    string = List.to_string(charlist)
    {:ok, {:literal, :string, string}, %{}}
  end

  def transform({:char, _line, char}) do
    # Erlang char literal - treat as small integer
    {:ok, {:literal, :integer, char}, %{erlang_form: :char}}
  end

  # Atoms - special handling for booleans and null
  def transform({:atom, _line, true}) do
    {:ok, {:literal, :boolean, true}, %{}}
  end

  def transform({:atom, _line, false}) do
    {:ok, {:literal, :boolean, false}, %{}}
  end

  def transform({:atom, _line, nil}) do
    {:ok, {:literal, :null, nil}, %{}}
  end

  def transform({:atom, _line, :undefined}) do
    {:ok, {:literal, :null, nil}, %{erlang_atom: :undefined}}
  end

  def transform({:atom, _line, atom}) do
    {:ok, {:literal, :symbol, atom}, %{}}
  end

  # Variables - M2.1 Core Layer

  def transform({:var, line, name}) when is_atom(name) do
    metadata = %{line: line}
    {:ok, {:variable, Atom.to_string(name)}, metadata}
  end

  # Binary Operators - M2.1 Core Layer

  # Arithmetic operators
  def transform({:op, _line, op, left, right})
      when op in [:+, :-, :*, :/, :div, :rem, :band, :bor, :bxor, :bsl, :bsr] do
    with {:ok, left_meta, _} <- transform(left),
         {:ok, right_meta, _} <- transform(right) do
      {:ok, {:binary_op, :arithmetic, op, left_meta, right_meta}, %{}}
    end
  end

  # Comparison operators
  def transform({:op, _line, op, left, right})
      when op in [:==, :"/=", :<, :>, :"=<", :>=, :"=:=", :"=/="] do
    # Normalize Erlang comparison operators to standard ones
    normalized_op =
      case op do
        :"/=" -> :!=
        :"=<" -> :<=
        :"=:=" -> :===
        :"=/=" -> :!==
        other -> other
      end

    with {:ok, left_meta, _} <- transform(left),
         {:ok, right_meta, _} <- transform(right) do
      {:ok, {:binary_op, :comparison, normalized_op, left_meta, right_meta}, %{}}
    end
  end

  # Boolean operators
  def transform({:op, _line, op, left, right}) when op in [:andalso, :orelse] do
    # Normalize to standard boolean operators
    normalized_op =
      case op do
        :andalso -> :and
        :orelse -> :or
      end

    with {:ok, left_meta, _} <- transform(left),
         {:ok, right_meta, _} <- transform(right) do
      {:ok, {:binary_op, :boolean, normalized_op, left_meta, right_meta}, %{erlang_op: op}}
    end
  end

  # Unary Operators - M2.1 Core Layer

  def transform({:op, _line, :not, operand}) do
    with {:ok, operand_meta, _} <- transform(operand) do
      {:ok, {:unary_op, :boolean, :not, operand_meta}, %{}}
    end
  end

  def transform({:op, _line, :-, operand}) do
    with {:ok, operand_meta, _} <- transform(operand) do
      {:ok, {:unary_op, :arithmetic, :-, operand_meta}, %{}}
    end
  end

  def transform({:op, _line, :+, operand}) do
    with {:ok, operand_meta, _} <- transform(operand) do
      {:ok, {:unary_op, :arithmetic, :+, operand_meta}, %{}}
    end
  end

  def transform({:op, _line, :bnot, operand}) do
    with {:ok, operand_meta, _} <- transform(operand) do
      {:ok, {:unary_op, :arithmetic, :bnot, operand_meta}, %{}}
    end
  end

  # Function Calls - M2.1 Core Layer

  # Local function call
  def transform({:call, _line, {:atom, _, func_name}, args}) when is_list(args) do
    with {:ok, args_meta} <- transform_list(args) do
      {:ok, {:function_call, Atom.to_string(func_name), args_meta}, %{}}
    end
  end

  # Remote function call (Module:function)
  def transform({:call, _line, {:remote, _, {:atom, _, module}, {:atom, _, func}}, args})
      when is_list(args) do
    with {:ok, args_meta} <- transform_list(args) do
      qualified_name = "#{module}.#{func}"
      {:ok, {:function_call, qualified_name, args_meta}, %{call_type: :remote}}
    end
  end

  # Conditionals - M2.1 Core Layer

  # If expression
  def transform({:if, _line, clauses}) when is_list(clauses) do
    # Erlang if is like cond - convert to nested conditionals
    case transform_if_clauses(clauses) do
      {:ok, meta_ast} -> {:ok, meta_ast, %{original_form: :if}}
      error -> error
    end
  end

  # Case expression - M2.2 Extended Layer
  def transform({:case, _line, expr, clauses}) when is_list(clauses) do
    with {:ok, scrutinee_meta, _} <- transform(expr),
         {:ok, arms} <- transform_case_clauses(clauses) do
      {:ok, {:pattern_match, scrutinee_meta, arms}, %{}}
    end
  end

  # Blocks (multiple expressions)
  def transform({:block, expressions}) when is_list(expressions) do
    with {:ok, exprs_meta} <- transform_list(expressions) do
      {:ok, {:block, exprs_meta}, %{}}
    end
  end

  # Match expression (pattern = expr) - keep as assignment for now
  def transform({:match, _line, pattern, expr}) do
    with {:ok, pattern_meta, _} <- transform_pattern(pattern),
         {:ok, expr_meta, _} <- transform(expr) do
      # Represent as a special form
      {:ok, {:language_specific, :erlang, {:match, pattern, expr}, :pattern_match},
       %{pattern: pattern_meta, expression: expr_meta}}
    end
  end

  # Tuples
  def transform({:tuple, _line, elements}) when is_list(elements) do
    with {:ok, elements_meta} <- transform_list(elements) do
      {:ok, {:literal, :collection, elements_meta}, %{collection_type: :tuple}}
    end
  end

  # Lists (cons and nil)
  def transform({nil, _line}) do
    {:ok, {:literal, :collection, []}, %{collection_type: :list}}
  end

  def transform({:cons, _line, head, tail}) do
    with {:ok, head_meta, _} <- transform(head),
         {:ok, tail_meta, _} <- transform(tail) do
      # Represent cons as a language-specific construct
      {:ok, {:language_specific, :erlang, {:cons, head, tail}, :list_cons},
       %{head: head_meta, tail: tail_meta}}
    end
  end

  # Catch-all
  def transform(unsupported) do
    {:error, "Unsupported Erlang AST construct: #{inspect(unsupported)}"}
  end

  # Helper Functions

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

  defp transform_if_clauses([]) do
    {:ok, {:literal, :null, nil}}
  end

  defp transform_if_clauses([{:clause, _line, [], guards, body} | rest]) do
    # Erlang if clauses have guards instead of simple conditions
    # For now, treat guard as condition
    condition =
      case guards do
        [[single_guard]] -> single_guard
        [multiple_guards] when length(multiple_guards) > 1 -> List.first(multiple_guards)
        _ -> {:atom, 0, true}
      end

    with {:ok, cond_meta, _} <- transform(condition),
         {:ok, body_meta} <- transform_body(body),
         {:ok, else_meta} <- transform_if_clauses(rest) do
      {:ok, {:conditional, cond_meta, body_meta, else_meta}}
    end
  end

  defp transform_case_clauses(clauses) when is_list(clauses) do
    clauses
    |> Enum.reduce_while({:ok, []}, fn {:clause, _line, [pattern], guards, body}, {:ok, acc} ->
      with {:ok, pattern_meta, _} <- transform_pattern(pattern),
           {:ok, body_meta} <- transform_body(body) do
        # Ignore guards for now
        _ = guards
        arm = {:match_arm, pattern_meta, nil, body_meta}
        {:cont, {:ok, [arm | acc]}}
      else
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, arms} -> {:ok, Enum.reverse(arms)}
      error -> error
    end
  end

  defp transform_pattern({:var, _, :_}) do
    # Wildcard pattern
    {:ok, :_, %{}}
  end

  defp transform_pattern(pattern) do
    # Regular patterns are just expressions
    transform(pattern)
  end

  defp transform_body([single]) do
    with {:ok, expr_meta, _} <- transform(single) do
      {:ok, expr_meta}
    end
  end

  defp transform_body(multiple) when length(multiple) > 1 do
    with {:ok, exprs_meta} <- transform_list(multiple) do
      {:ok, {:block, exprs_meta}}
    end
  end
end
