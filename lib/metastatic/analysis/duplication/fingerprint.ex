defmodule Metastatic.Analysis.Duplication.Fingerprint do
  @moduledoc """
  Structural fingerprinting for ASTs.

  Generates hash-based fingerprints that uniquely identify AST structures.
  Supports both exact fingerprints (sensitive to variable/literal names) and
  normalized fingerprints (structure-only matching).

  ## Fingerprint Types

  - **Exact**: Identical ASTs produce identical fingerprints
  - **Normalized**: ASTs with same structure but different names produce identical fingerprints

  ## Usage

      alias Metastatic.Analysis.Duplication.Fingerprint

      ast = {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}}

      # Exact fingerprint
      Fingerprint.exact(ast)
      # => "ABC123..."

      # Normalized fingerprint (ignores variable/literal names)
      Fingerprint.normalized(ast)
      # => "DEF456..."

  ## Examples

      # Exact fingerprints
      iex> ast = {:literal, [subtype: :integer], 42}
      iex> fp = Metastatic.Analysis.Duplication.Fingerprint.exact(ast)
      iex> is_binary(fp) and String.length(fp) > 0
      true

      # Normalized fingerprints ignore values
      iex> ast1 = {:literal, [subtype: :integer], 42}
      iex> ast2 = {:literal, [subtype: :integer], 99}
      iex> fp1 = Metastatic.Analysis.Duplication.Fingerprint.normalized(ast1)
      iex> fp2 = Metastatic.Analysis.Duplication.Fingerprint.normalized(ast2)
      iex> fp1 == fp2
      true
  """

  alias Metastatic.AST

  @doc """
  Generates an exact fingerprint for an AST.

  Identical ASTs (including variable names and literal values) produce
  identical fingerprints. Uses SHA-256 hashing.

  ## Examples

      iex> ast1 = {:variable, [], "x"}
      iex> ast2 = {:variable, [], "x"}
      iex> Metastatic.Analysis.Duplication.Fingerprint.exact(ast1) == Metastatic.Analysis.Duplication.Fingerprint.exact(ast2)
      true

      iex> ast1 = {:variable, [], "x"}
      iex> ast2 = {:variable, [], "y"}
      iex> Metastatic.Analysis.Duplication.Fingerprint.exact(ast1) == Metastatic.Analysis.Duplication.Fingerprint.exact(ast2)
      false
  """
  @spec exact(AST.meta_ast()) :: String.t()
  def exact(ast) do
    :crypto.hash(:sha256, inspect(ast))
    |> Base.encode16()
  end

  @doc """
  Generates a normalized fingerprint for an AST.

  ASTs with the same structure but different variable names or literal
  values produce identical fingerprints. This is useful for Type II
  clone detection.

  ## Examples

      iex> ast1 = {:variable, [], "x"}
      iex> ast2 = {:variable, [], "y"}
      iex> Metastatic.Analysis.Duplication.Fingerprint.normalized(ast1) == Metastatic.Analysis.Duplication.Fingerprint.normalized(ast2)
      true

      iex> ast1 = {:literal, [subtype: :integer], 42}
      iex> ast2 = {:literal, [subtype: :integer], 100}
      iex> Metastatic.Analysis.Duplication.Fingerprint.normalized(ast1) == Metastatic.Analysis.Duplication.Fingerprint.normalized(ast2)
      true

      iex> ast1 = {:binary_op, [category: :arithmetic, operator: :+], [{:variable, [], "a"}, {:literal, [subtype: :integer], 1}]}
      iex> ast2 = {:binary_op, [category: :arithmetic, operator: :+], [{:variable, [], "b"}, {:literal, [subtype: :integer], 2}]}
      iex> Metastatic.Analysis.Duplication.Fingerprint.normalized(ast1) == Metastatic.Analysis.Duplication.Fingerprint.normalized(ast2)
      true
  """
  @spec normalized(AST.meta_ast()) :: String.t()
  def normalized(ast) do
    normalized_ast = normalize_ast(ast)

    :crypto.hash(:sha256, inspect(normalized_ast))
    |> Base.encode16()
  end

  @doc """
  Extracts a sequence of tokens from an AST.

  Tokens include node types, operators, and structure markers.
  Useful for token-based similarity comparison.

  ## Examples

      iex> ast = {:literal, [subtype: :integer], 42}
      iex> Metastatic.Analysis.Duplication.Fingerprint.tokens(ast)
      [:literal, :integer]

      iex> ast = {:binary_op, [category: :arithmetic, operator: :+], [{:variable, [], "x"}, {:literal, [subtype: :integer], 5}]}
      iex> tokens = Metastatic.Analysis.Duplication.Fingerprint.tokens(ast)
      iex> :binary_op in tokens and :arithmetic in tokens and :+ in tokens
      true
  """
  @spec tokens(AST.meta_ast()) :: [atom()]
  def tokens(ast) do
    extract_tokens(ast, [])
    |> Enum.reverse()
  end

  @doc """
  Compares two fingerprints for equality.

  ## Examples

      iex> ast = {:literal, [subtype: :integer], 42}
      iex> fp1 = Metastatic.Analysis.Duplication.Fingerprint.exact(ast)
      iex> fp2 = Metastatic.Analysis.Duplication.Fingerprint.exact(ast)
      iex> Metastatic.Analysis.Duplication.Fingerprint.match?(fp1, fp2)
      true

      iex> ast1 = {:literal, [subtype: :integer], 42}
      iex> ast2 = {:literal, [subtype: :string], "hello"}
      iex> fp1 = Metastatic.Analysis.Duplication.Fingerprint.exact(ast1)
      iex> fp2 = Metastatic.Analysis.Duplication.Fingerprint.exact(ast2)
      iex> Metastatic.Analysis.Duplication.Fingerprint.match?(fp1, fp2)
      false
  """
  @spec match?(String.t(), String.t()) :: boolean()
  def match?(fp1, fp2) when is_binary(fp1) and is_binary(fp2) do
    fp1 == fp2
  end

  # Private functions

  # Normalize an AST by replacing variable names and literal values with placeholders
  # 3-tuple format: {type, meta, value_or_children}
  defp normalize_ast({:variable, _meta, _name}), do: {:variable, [], :_}

  defp normalize_ast({:literal, meta, _value}) do
    subtype = Keyword.get(meta, :subtype)
    {:literal, [subtype: subtype], :_}
  end

  defp normalize_ast({:binary_op, meta, [left, right]}) do
    {:binary_op, meta, [normalize_ast(left), normalize_ast(right)]}
  end

  defp normalize_ast({:unary_op, meta, [operand]}) do
    {:unary_op, meta, [normalize_ast(operand)]}
  end

  defp normalize_ast({:function_call, _meta, args}) when is_list(args) do
    {:function_call, [name: :_], Enum.map(args, &normalize_ast/1)}
  end

  defp normalize_ast({:conditional, meta, [cond_expr, then_branch, else_branch]}) do
    {:conditional, meta,
     [
       normalize_ast(cond_expr),
       normalize_ast(then_branch),
       if(else_branch, do: normalize_ast(else_branch), else: nil)
     ]}
  end

  defp normalize_ast({:early_return, meta, [value]}) do
    {:early_return, meta, [normalize_ast(value)]}
  end

  defp normalize_ast({:block, meta, statements}) when is_list(statements) do
    {:block, meta, Enum.map(statements, &normalize_ast/1)}
  end

  defp normalize_ast({:assignment, meta, [target, value]}) do
    {:assignment, meta, [normalize_ast(target), normalize_ast(value)]}
  end

  defp normalize_ast({:inline_match, meta, [pattern, value]}) do
    {:inline_match, meta, [normalize_ast(pattern), normalize_ast(value)]}
  end

  defp normalize_ast({:tuple, meta, elements}) when is_list(elements) do
    {:tuple, meta, Enum.map(elements, &normalize_ast/1)}
  end

  defp normalize_ast({:list, meta, elements}) when is_list(elements) do
    {:list, meta, Enum.map(elements, &normalize_ast/1)}
  end

  defp normalize_ast({:map, meta, pairs}) when is_list(pairs) do
    {:map, meta, Enum.map(pairs, fn {k, v} -> {normalize_ast(k), normalize_ast(v)} end)}
  end

  # M2.2 Extended layer (3-tuple format)
  defp normalize_ast({:loop, meta, children}) when is_list(children) do
    {:loop, meta, Enum.map(children, &normalize_ast/1)}
  end

  defp normalize_ast({:lambda, meta, [body]}) do
    normalized_meta = Keyword.put(meta, :params, :_) |> Keyword.put(:captures, :_)
    {:lambda, normalized_meta, [normalize_ast(body)]}
  end

  defp normalize_ast({:collection_op, meta, children}) when is_list(children) do
    {:collection_op, meta, Enum.map(children, &normalize_ast/1)}
  end

  defp normalize_ast({:pattern_match, meta, [scrutinee, arms]}) when is_list(arms) do
    normalized_arms = Enum.map(arms, &normalize_ast/1)
    {:pattern_match, meta, [normalize_ast(scrutinee), normalized_arms]}
  end

  defp normalize_ast({:match_arm, meta, [pattern, body]}) do
    {:match_arm, meta, [normalize_ast(pattern), normalize_ast(body)]}
  end

  defp normalize_ast({:exception_handling, meta, [try_block, handlers, finally_block]}) do
    normalized_handlers = Enum.map(handlers, &normalize_ast/1)

    {:exception_handling, meta,
     [
       normalize_ast(try_block),
       normalized_handlers,
       if(finally_block, do: normalize_ast(finally_block), else: nil)
     ]}
  end

  defp normalize_ast({:async_operation, meta, [operation]}) do
    {:async_operation, meta, [normalize_ast(operation)]}
  end

  # M2.2s Structural/Organizational layer (3-tuple format)
  defp normalize_ast({:container, meta, body}) when is_list(body) do
    container_type = Keyword.get(meta, :container_type)

    normalized_meta = [
      container_type: container_type,
      name: :_,
      parent: :_,
      type_params: :_,
      implements: :_
    ]

    {:container, normalized_meta, Enum.map(body, &normalize_ast/1)}
  end

  defp normalize_ast({:function_def, meta, [body]}) do
    # Preserve visibility and param count but normalize names
    visibility = Keyword.get(meta, :visibility)
    params = Keyword.get(meta, :params, [])
    normalized_params = if is_list(params), do: Enum.map(params, fn _ -> :_ end), else: :_
    normalized_meta = [name: :_, params: normalized_params, visibility: visibility]
    {:function_def, normalized_meta, [normalize_ast(body)]}
  end

  defp normalize_ast({:attribute_access, meta, [receiver]}) do
    {:attribute_access, Keyword.put(meta, :attribute, :_), [normalize_ast(receiver)]}
  end

  defp normalize_ast({:augmented_assignment, meta, [target, value]}) do
    {:augmented_assignment, meta, [normalize_ast(target), normalize_ast(value)]}
  end

  defp normalize_ast({:property, meta, children}) when is_list(children) do
    normalized_children =
      Enum.map(children, fn
        nil -> nil
        child -> normalize_ast(child)
      end)

    {:property, Keyword.put(meta, :name, :_), normalized_children}
  end

  # M2.3 Native layer - preserve structure hints but not data
  defp normalize_ast({:language_specific, meta, children}) when is_list(children) do
    lang = Keyword.get(meta, :language)
    hint = Keyword.get(meta, :hint)
    {:language_specific, [language: lang, hint: hint], [:_]}
  end

  # Handle plain lists (e.g., container bodies)
  defp normalize_ast(list) when is_list(list) do
    Enum.map(list, &normalize_ast/1)
  end

  # Wildcard and other atoms pass through
  defp normalize_ast(:_), do: :_
  defp normalize_ast(nil), do: nil
  defp normalize_ast(other), do: other

  # Extract tokens for token-based similarity (3-tuple format)
  defp extract_tokens({:variable, _meta, _name}, acc), do: [:variable | acc]

  defp extract_tokens({:literal, meta, _value}, acc) do
    subtype = Keyword.get(meta, :subtype)
    [subtype, :literal | acc]
  end

  defp extract_tokens({:binary_op, meta, [left, right]}, acc) do
    category = Keyword.get(meta, :category)
    op = Keyword.get(meta, :operator)
    acc = [op, category, :binary_op | acc]
    acc = extract_tokens(left, acc)
    extract_tokens(right, acc)
  end

  defp extract_tokens({:unary_op, meta, [operand]}, acc) do
    category = Keyword.get(meta, :category)
    op = Keyword.get(meta, :operator)
    acc = [op, category, :unary_op | acc]
    extract_tokens(operand, acc)
  end

  defp extract_tokens({:function_call, _meta, args}, acc) when is_list(args) do
    acc = [:function_call | acc]
    Enum.reduce(args, acc, fn arg, a -> extract_tokens(arg, a) end)
  end

  defp extract_tokens({:conditional, _meta, [cond_expr, then_branch, else_branch]}, acc) do
    acc = [:conditional | acc]
    acc = extract_tokens(cond_expr, acc)
    acc = extract_tokens(then_branch, acc)

    if else_branch do
      extract_tokens(else_branch, acc)
    else
      acc
    end
  end

  defp extract_tokens({:early_return, _meta, [value]}, acc) do
    acc = [:early_return | acc]
    extract_tokens(value, acc)
  end

  defp extract_tokens({:block, _meta, statements}, acc) when is_list(statements) do
    acc = [:block | acc]
    Enum.reduce(statements, acc, fn stmt, a -> extract_tokens(stmt, a) end)
  end

  defp extract_tokens({:assignment, _meta, [target, value]}, acc) do
    acc = [:assignment | acc]
    acc = extract_tokens(target, acc)
    extract_tokens(value, acc)
  end

  defp extract_tokens({:inline_match, _meta, [pattern, value]}, acc) do
    acc = [:inline_match | acc]
    acc = extract_tokens(pattern, acc)
    extract_tokens(value, acc)
  end

  defp extract_tokens({:tuple, _meta, elements}, acc) when is_list(elements) do
    acc = [:tuple | acc]
    Enum.reduce(elements, acc, fn elem, a -> extract_tokens(elem, a) end)
  end

  defp extract_tokens({:list, _meta, elements}, acc) when is_list(elements) do
    acc = [:list | acc]
    Enum.reduce(elements, acc, fn elem, a -> extract_tokens(elem, a) end)
  end

  defp extract_tokens({:map, _meta, pairs}, acc) when is_list(pairs) do
    acc = [:map | acc]

    Enum.reduce(pairs, acc, fn {k, v}, a ->
      a = extract_tokens(k, a)
      extract_tokens(v, a)
    end)
  end

  # M2.2 Extended (3-tuple format)
  defp extract_tokens({:loop, meta, children}, acc) when is_list(children) do
    loop_type = Keyword.get(meta, :loop_type, :for)
    acc = [loop_type, :loop | acc]
    Enum.reduce(children, acc, fn child, a -> extract_tokens(child, a) end)
  end

  defp extract_tokens({:lambda, _meta, [body]}, acc) do
    acc = [:lambda | acc]
    extract_tokens(body, acc)
  end

  defp extract_tokens({:collection_op, meta, children}, acc) when is_list(children) do
    op_type = Keyword.get(meta, :op_type, :map)
    acc = [op_type, :collection_op | acc]
    Enum.reduce(children, acc, fn child, a -> extract_tokens(child, a) end)
  end

  defp extract_tokens({:async_operation, meta, [operation]}, acc) do
    op_type = Keyword.get(meta, :op_type)
    acc = [op_type, :async_operation | acc]
    extract_tokens(operation, acc)
  end

  # M2.2s Structural/Organizational (3-tuple format)
  defp extract_tokens({:container, meta, body}, acc) when is_list(body) do
    container_type = Keyword.get(meta, :container_type)
    acc = [container_type, :container | acc]
    Enum.reduce(body, acc, fn elem, a -> extract_tokens(elem, a) end)
  end

  defp extract_tokens({:function_def, meta, [body]}, acc) do
    acc = [:function_def | acc]
    visibility = Keyword.get(meta, :visibility)
    acc = if visibility, do: [visibility | acc], else: acc
    params = Keyword.get(meta, :params, [])

    acc =
      if is_list(params),
        do: Enum.reduce(params, acc, fn p, a -> extract_param_tokens(p, a) end),
        else: acc

    extract_tokens(body, acc)
  end

  defp extract_tokens({:attribute_access, _meta, [receiver]}, acc) do
    acc = [:attribute_access | acc]
    extract_tokens(receiver, acc)
  end

  defp extract_tokens({:augmented_assignment, meta, [target, value]}, acc) do
    op = Keyword.get(meta, :operator)
    acc = [op, :augmented_assignment | acc]
    acc = extract_tokens(target, acc)
    extract_tokens(value, acc)
  end

  defp extract_tokens({:property, _meta, children}, acc) when is_list(children) do
    acc = [:property | acc]

    Enum.reduce(children, acc, fn
      nil, a -> a
      child, a -> extract_tokens(child, a)
    end)
  end

  # M2.3 Native (3-tuple format)
  defp extract_tokens({:language_specific, meta, _children}, acc) do
    lang = Keyword.get(meta, :language)
    hint = Keyword.get(meta, :hint)
    tokens = [lang, :language_specific]
    tokens = if hint, do: [hint | tokens], else: tokens
    tokens ++ acc
  end

  # Handle plain lists (e.g., container bodies)
  defp extract_tokens(list, acc) when is_list(list) do
    Enum.reduce(list, acc, fn elem, a -> extract_tokens(elem, a) end)
  end

  defp extract_tokens(:_, acc), do: [:wildcard | acc]
  defp extract_tokens(nil, acc), do: acc
  defp extract_tokens(_other, acc), do: acc

  # Helper for extracting tokens from function parameters
  defp extract_param_tokens(param, acc) when is_binary(param), do: [:param | acc]

  # New format: {:param, name, pattern, default}
  defp extract_param_tokens({:param, _name, pattern, default}, acc) do
    acc = [:param | acc]
    acc = if pattern, do: extract_tokens(pattern, acc), else: acc
    if default, do: extract_tokens(default, acc), else: acc
  end

  # Old format compatibility
  defp extract_param_tokens({:pattern, pattern}, acc),
    do: extract_tokens(pattern, [:pattern_param | acc])

  defp extract_param_tokens({:default, _name, default}, acc),
    do: extract_tokens(default, [:default_param | acc])
end
