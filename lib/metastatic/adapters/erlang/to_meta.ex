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

  # Literals - M2.1 Core Layer (New 3-tuple format)

  def transform({:integer, line, value}) do
    {:ok, {:literal, [subtype: :integer] ++ line_meta(line), value}, %{}}
  end

  def transform({:float, line, value}) do
    {:ok, {:literal, [subtype: :float] ++ line_meta(line), value}, %{}}
  end

  def transform({:string, line, charlist}) when is_list(charlist) do
    # Erlang strings are charlists - convert to binary
    string = List.to_string(charlist)
    {:ok, {:literal, [subtype: :string] ++ line_meta(line), string}, %{}}
  end

  def transform({:char, line, char}) do
    # Erlang char literal
    {:ok, {:literal, [subtype: :char] ++ line_meta(line), char}, %{erlang_form: :char}}
  end

  # Atoms - special handling for booleans and null
  def transform({:atom, line, true}) do
    {:ok, {:literal, [subtype: :boolean] ++ line_meta(line), true}, %{}}
  end

  def transform({:atom, line, false}) do
    {:ok, {:literal, [subtype: :boolean] ++ line_meta(line), false}, %{}}
  end

  def transform({:atom, line, nil}) do
    {:ok, {:literal, [subtype: :null] ++ line_meta(line), nil}, %{}}
  end

  def transform({:atom, line, :undefined}) do
    {:ok, {:literal, [subtype: :null] ++ line_meta(line), nil}, %{erlang_atom: :undefined}}
  end

  def transform({:atom, line, atom}) do
    {:ok, {:literal, [subtype: :symbol] ++ line_meta(line), atom}, %{}}
  end

  # Variables - M2.1 Core Layer (New 3-tuple format)

  def transform({:var, line, name}) when is_atom(name) do
    {:ok, {:variable, [scope: :local] ++ line_meta(line), Atom.to_string(name)}, %{}}
  end

  # Binary Operators - M2.1 Core Layer (New 3-tuple format)

  # Arithmetic operators
  def transform({:op, line, op, left, right})
      when op in [:+, :-, :*, :/, :div, :rem] do
    with {:ok, left_meta, _} <- transform(left),
         {:ok, right_meta, _} <- transform(right) do
      {:ok,
       {:binary_op, [category: :arithmetic, operator: op] ++ line_meta(line),
        [left_meta, right_meta]}, %{}}
    end
  end

  # Bitwise operators
  def transform({:op, line, op, left, right})
      when op in [:band, :bor, :bxor, :bsl, :bsr] do
    with {:ok, left_meta, _} <- transform(left),
         {:ok, right_meta, _} <- transform(right) do
      {:ok,
       {:binary_op, [category: :bitwise, operator: op] ++ line_meta(line),
        [left_meta, right_meta]}, %{}}
    end
  end

  # Comparison operators
  def transform({:op, line, op, left, right})
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
      {:ok,
       {:binary_op, [category: :comparison, operator: normalized_op] ++ line_meta(line),
        [left_meta, right_meta]}, %{}}
    end
  end

  # Boolean operators
  def transform({:op, line, op, left, right}) when op in [:andalso, :orelse] do
    # Normalize to standard boolean operators
    normalized_op =
      case op do
        :andalso -> :and
        :orelse -> :or
      end

    with {:ok, left_meta, _} <- transform(left),
         {:ok, right_meta, _} <- transform(right) do
      {:ok,
       {:binary_op, [category: :boolean, operator: normalized_op] ++ line_meta(line),
        [left_meta, right_meta]}, %{erlang_op: op}}
    end
  end

  # Unary Operators - M2.1 Core Layer (New 3-tuple format)

  def transform({:op, line, :not, operand}) do
    with {:ok, operand_meta, _} <- transform(operand) do
      {:ok, {:unary_op, [category: :boolean, operator: :not] ++ line_meta(line), [operand_meta]},
       %{}}
    end
  end

  def transform({:op, line, :-, operand}) do
    with {:ok, operand_meta, _} <- transform(operand) do
      {:ok, {:unary_op, [category: :arithmetic, operator: :-] ++ line_meta(line), [operand_meta]},
       %{}}
    end
  end

  def transform({:op, line, :+, operand}) do
    with {:ok, operand_meta, _} <- transform(operand) do
      {:ok, {:unary_op, [category: :arithmetic, operator: :+] ++ line_meta(line), [operand_meta]},
       %{}}
    end
  end

  def transform({:op, line, :bnot, operand}) do
    with {:ok, operand_meta, _} <- transform(operand) do
      {:ok, {:unary_op, [category: :bitwise, operator: :bnot] ++ line_meta(line), [operand_meta]},
       %{}}
    end
  end

  # Function Calls - M2.1 Core Layer (New 3-tuple format)

  # Local function call
  def transform({:call, line, {:atom, _, func_name}, args}) when is_list(args) do
    with {:ok, args_meta} <- transform_list(args) do
      {:ok, {:function_call, [name: Atom.to_string(func_name)] ++ line_meta(line), args_meta},
       %{}}
    end
  end

  # Remote function call (Module:function)
  def transform({:call, line, {:remote, _, {:atom, _, module}, {:atom, _, func}}, args})
      when is_list(args) do
    with {:ok, args_meta} <- transform_list(args) do
      qualified_name = "#{module}.#{func}"

      {:ok, {:function_call, [name: qualified_name] ++ line_meta(line), args_meta},
       %{call_type: :remote}}
    end
  end

  # Conditionals - M2.1 Core Layer

  # If expression
  def transform({:if, line, clauses}) when is_list(clauses) do
    # Erlang if is like cond - convert to nested conditionals
    case transform_if_clauses(clauses, line) do
      {:ok, meta_ast} -> {:ok, meta_ast, %{original_form: :if}}
      error -> error
    end
  end

  # Case expression - M2.2 Extended Layer (New 3-tuple format)
  def transform({:case, line, expr, clauses}) when is_list(clauses) do
    with {:ok, scrutinee_meta, _} <- transform(expr),
         {:ok, arms} <- transform_case_clauses(clauses) do
      {:ok, {:pattern_match, line_meta(line), [scrutinee_meta | arms]}, %{}}
    end
  end

  # Blocks (multiple expressions) (New 3-tuple format)
  def transform({:block, line, expressions}) when is_list(expressions) do
    with {:ok, exprs_meta} <- transform_list(expressions) do
      {:ok, {:block, line_meta(line), exprs_meta}, %{}}
    end
  end

  # Blocks without line info (legacy form)
  def transform({:block, expressions}) when is_list(expressions) do
    with {:ok, exprs_meta} <- transform_list(expressions) do
      {:ok, {:block, [], exprs_meta}, %{}}
    end
  end

  # Match expression (pattern = expr) - M2.1 Core Layer (New 3-tuple format)
  # In Erlang, = is pattern matching with single-assignment semantics
  def transform({:match, line, pattern, expr}) do
    with {:ok, pattern_meta, pattern_metadata} <- transform_pattern(pattern),
         {:ok, expr_meta, expr_metadata} <- transform(expr) do
      metadata = %{
        pattern_metadata: pattern_metadata,
        expr_metadata: expr_metadata
      }

      {:ok, {:inline_match, line_meta(line), [pattern_meta, expr_meta]}, metadata}
    end
  end

  # Tuples - M2.1 Core Layer (New 3-tuple format)
  def transform({:tuple, line, elements}) when is_list(elements) do
    with {:ok, elements_meta} <- transform_list(elements) do
      {:ok, {:tuple, line_meta(line), elements_meta}, %{}}
    end
  end

  # Lists (cons and nil) (New 3-tuple format)
  def transform({nil, line}) do
    {:ok, {:list, line_meta(line), []}, %{collection_type: :list}}
  end

  def transform({:cons, line, _head, _tail} = cons_node) do
    case flatten_cons(cons_node) do
      {:proper, elements} ->
        with {:ok, elements_meta} <- transform_list(elements) do
          {:ok, {:list, line_meta(line), elements_meta}, %{collection_type: :list}}
        end

      {:improper, elements, tail} ->
        # Improper list (tail is not nil) -- keep as language_specific
        {:ok,
         {:language_specific, [language: :erlang, hint: :improper_list] ++ line_meta(line),
          %{elements: elements, tail: tail}}, %{}}
    end
  end

  # Module attribute: -module(Name).
  def transform({:attribute, line, :module, name}) do
    mod_name = if is_atom(name), do: Atom.to_string(name), else: inspect(name)

    {:ok,
     {:container, [container_type: :module, name: mod_name, language: :erlang] ++ line_meta(line),
      []}, %{}}
  end

  # Export attribute: -export([...]).
  def transform({:attribute, line, :export, funs}) when is_list(funs) do
    names = Enum.map(funs, fn {name, arity} -> "#{name}/#{arity}" end)

    {:ok,
     {:import,
      [source: "self", names: names, import_type: :export, language: :erlang] ++ line_meta(line),
      []}, %{erlang_form: :export}}
  end

  # Other attributes (behaviour, spec, type, etc.)
  def transform({:attribute, line, attr_name, value}) do
    {:ok,
     {:language_specific, [language: :erlang, hint: :attribute] ++ line_meta(line),
      %{name: attr_name, value: value}}, %{}}
  end

  # Function definition: {function, Line, Name, Arity, Clauses}
  def transform({:function, line, name, arity, clauses}) when is_list(clauses) do
    func_name = Atom.to_string(name)

    with {:ok, clause_bodies} <- transform_function_clauses(clauses) do
      # For single clause, extract params from it; for multi-clause use first
      params = extract_erlang_params(clauses)

      body =
        case clause_bodies do
          [single] -> [single]
          multiple -> [{:pattern_match, [original_form: :multi_clause], multiple}]
        end

      meta =
        [
          name: func_name,
          params: params,
          visibility: :public,
          arity: arity,
          function: func_name,
          language: :erlang
        ] ++ line_meta(line)

      {:ok, {:function_def, meta, body}, %{}}
    end
  end

  # Fun expression: fun(X) -> X end
  def transform({:fun, line, {:clauses, clauses}}) when is_list(clauses) do
    case clauses do
      [{:clause, _cl, params, _guards, body}] ->
        with {:ok, param_names} <- transform_fun_params(params),
             {:ok, body_meta} <- transform_body(body) do
          {:ok, {:lambda, [params: param_names, captures: []] ++ line_meta(line), [body_meta]},
           %{}}
        end

      _ ->
        # Multi-clause fun
        {:ok,
         {:language_specific, [language: :erlang, hint: :multi_clause_fun] ++ line_meta(line),
          clauses}, %{}}
    end
  end

  # Fun reference: fun Name/Arity or fun Mod:Fun/Arity
  def transform({:fun, line, {:function, name, arity}}) do
    func_name = Atom.to_string(name)
    params = for i <- 1..arity//1, do: {:param, [], "arg_#{i}"}
    args = for i <- 1..arity//1, do: {:variable, [], "arg_#{i}"}
    body_ast = {:function_call, [name: func_name], args}

    {:ok,
     {:lambda, [params: params, capture_form: :named_function] ++ line_meta(line), [body_ast]},
     %{}}
  end

  def transform({:fun, line, {:function, module, name, arity}}) do
    func_name = "#{module}.#{name}"
    params = for i <- 1..arity//1, do: {:param, [], "arg_#{i}"}
    args = for i <- 1..arity//1, do: {:variable, [], "arg_#{i}"}
    body_ast = {:function_call, [name: func_name], args}

    {:ok,
     {:lambda, [params: params, capture_form: :named_function] ++ line_meta(line), [body_ast]},
     %{}}
  end

  # Try/catch/after
  def transform({:try, line, body, case_clauses, catch_clauses, after_body}) do
    with {:ok, body_meta} <- transform_body(body),
         {:ok, handlers} <- transform_catch_clauses(catch_clauses),
         {:ok, finally_meta} <- transform_after(after_body) do
      _ = case_clauses
      {:ok, {:exception_handling, line_meta(line), [body_meta, handlers, finally_meta]}, %{}}
    end
  end

  # Receive expression
  def transform({:receive, line, clauses}) when is_list(clauses) do
    {:ok, {:language_specific, [language: :erlang, hint: :receive] ++ line_meta(line), clauses},
     %{}}
  end

  # Receive with timeout
  def transform({:receive, line, clauses, timeout, after_body}) do
    {:ok,
     {:language_specific, [language: :erlang, hint: :receive] ++ line_meta(line),
      %{clauses: clauses, timeout: timeout, after: after_body}}, %{}}
  end

  # Map literal #{}
  def transform({:map, line, pairs}) when is_list(pairs) do
    with {:ok, pair_metas} <- transform_map_pairs(pairs) do
      {:ok, {:map, line_meta(line), pair_metas}, %{}}
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

  defp transform_if_clauses(clauses, line)

  defp transform_if_clauses([], _line) do
    {:ok, {:literal, [subtype: :null], nil}}
  end

  defp transform_if_clauses([{:clause, clause_line, [], guards, body} | rest], line) do
    # Erlang if clauses have guards instead of simple conditions
    # For now, treat guard as condition
    condition =
      case guards do
        [[single_guard]] -> single_guard
        [multiple_guards] when length(multiple_guards) > 1 -> List.first(multiple_guards)
        _ -> {:atom, 0, true}
      end

    effective_line = if clause_line > 0, do: clause_line, else: line

    with {:ok, cond_meta, _} <- transform(condition),
         {:ok, body_meta} <- transform_body(body),
         {:ok, else_meta} <- transform_if_clauses(rest, line) do
      {:ok, {:conditional, line_meta(effective_line), [cond_meta, body_meta, else_meta]}}
    end
  end

  defp transform_case_clauses(clauses) when is_list(clauses) do
    clauses
    |> Enum.reduce_while({:ok, []}, fn {:clause, line, [pattern], guards, body}, {:ok, acc} ->
      with {:ok, pattern_meta, _} <- transform_pattern(pattern),
           {:ok, body_meta} <- transform_body(body) do
        # Ignore guards for now
        _ = guards
        arm = {:match_arm, [pattern: pattern_meta] ++ line_meta(line), [body_meta]}
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

  defp transform_pattern({:tuple, line, elements}) when is_list(elements) do
    # Tuple pattern: {X, Y, Z}
    with {:ok, elements_meta} <- transform_pattern_list(elements) do
      {:ok, {:tuple, [], elements_meta}, %{line: line}}
    end
  end

  defp transform_pattern({:cons, line, head, tail}) do
    # List cons pattern: [H | T]
    with {:ok, head_meta, _} <- transform_pattern(head),
         {:ok, tail_meta, _} <- transform_pattern(tail) do
      {:ok, {:cons_pattern, [], [head_meta, tail_meta]}, %{line: line}}
    end
  end

  defp transform_pattern({nil, line}) do
    # Empty list pattern: []
    {:ok, {:list, [], []}, %{collection_type: :list, line: line}}
  end

  defp transform_pattern(pattern) do
    # Regular patterns are just expressions
    transform(pattern)
  end

  defp transform_pattern_list(patterns) when is_list(patterns) do
    patterns
    |> Enum.reduce_while({:ok, []}, fn pattern, {:ok, acc} ->
      case transform_pattern(pattern) do
        {:ok, pattern_meta, _} -> {:cont, {:ok, [pattern_meta | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, patterns} -> {:ok, Enum.reverse(patterns)}
      error -> error
    end
  end

  # Flatten cons chain into a list of elements.
  # Returns {:proper, elements} for proper lists (nil-terminated)
  # or {:improper, elements, tail} for improper lists.
  defp flatten_cons({:cons, _line, head, {nil, _}}), do: {:proper, [head]}

  defp flatten_cons({:cons, _line, head, {:cons, _, _, _} = tail}) do
    case flatten_cons(tail) do
      {:proper, rest} -> {:proper, [head | rest]}
      {:improper, rest, final_tail} -> {:improper, [head | rest], final_tail}
    end
  end

  defp flatten_cons({:cons, _line, head, tail}), do: {:improper, [head], tail}

  defp transform_body([single]) do
    with {:ok, expr_meta, _} <- transform(single) do
      {:ok, expr_meta}
    end
  end

  defp transform_body(multiple) when length(multiple) > 1 do
    with {:ok, exprs_meta} <- transform_list(multiple) do
      {:ok, {:block, [], exprs_meta}}
    end
  end

  # Function clause transformation
  defp transform_function_clauses(clauses) do
    clauses
    |> Enum.reduce_while({:ok, []}, fn {:clause, _line, _params, _guards, body}, {:ok, acc} ->
      case transform_body(body) do
        {:ok, body_meta} -> {:cont, {:ok, [body_meta | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, bodies} -> {:ok, Enum.reverse(bodies)}
      error -> error
    end
  end

  defp extract_erlang_params([{:clause, _, params, _, _} | _]) do
    Enum.map(params, fn
      {:var, _, name} -> {:param, [], Atom.to_string(name)}
      _ -> {:param, [], "_"}
    end)
  end

  defp extract_erlang_params(_), do: []

  defp transform_fun_params(params) when is_list(params) do
    result =
      Enum.map(params, fn
        {:var, _, name} -> {:param, [], Atom.to_string(name)}
        _ -> {:param, [], "_"}
      end)

    {:ok, result}
  end

  defp transform_catch_clauses([]), do: {:ok, []}

  defp transform_catch_clauses(clauses) when is_list(clauses) do
    clauses
    |> Enum.reduce_while({:ok, []}, fn {:clause, line, [pattern], _guards, body}, {:ok, acc} ->
      with {:ok, pattern_meta, _} <- transform_pattern(pattern),
           {:ok, body_meta} <- transform_body(body) do
        arm = {:match_arm, [pattern: pattern_meta] ++ line_meta(line), [body_meta]}
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

  defp transform_after([]), do: {:ok, nil}
  defp transform_after(body) when is_list(body), do: transform_body(body)

  defp transform_map_pairs(pairs) when is_list(pairs) do
    pairs
    |> Enum.reduce_while({:ok, []}, fn pair, {:ok, acc} ->
      case transform_map_pair(pair) do
        {:ok, p} -> {:cont, {:ok, [p | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, ps} -> {:ok, Enum.reverse(ps)}
      error -> error
    end
  end

  defp transform_map_pair({:map_field_assoc, _line, key, value}) do
    with {:ok, key_meta, _} <- transform(key),
         {:ok, value_meta, _} <- transform(value) do
      {:ok, {:pair, [], [key_meta, value_meta]}}
    end
  end

  defp transform_map_pair({:map_field_exact, _line, key, value}) do
    with {:ok, key_meta, _} <- transform(key),
         {:ok, value_meta, _} <- transform(value) do
      {:ok, {:pair, [], [key_meta, value_meta]}}
    end
  end

  # Builds keyword meta with :line when the line number is a positive integer.
  defp line_meta(line) when is_integer(line) and line > 0, do: [line: line]
  defp line_meta(_), do: []
end
