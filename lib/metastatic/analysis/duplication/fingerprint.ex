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
      iex> ast = {:literal, :integer, 42}
      iex> fp = Metastatic.Analysis.Duplication.Fingerprint.exact(ast)
      iex> is_binary(fp) and String.length(fp) > 0
      true

      # Normalized fingerprints ignore values
      iex> ast1 = {:literal, :integer, 42}
      iex> ast2 = {:literal, :integer, 99}
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

      iex> ast1 = {:variable, "x"}
      iex> ast2 = {:variable, "x"}
      iex> Metastatic.Analysis.Duplication.Fingerprint.exact(ast1) == Metastatic.Analysis.Duplication.Fingerprint.exact(ast2)
      true

      iex> ast1 = {:variable, "x"}
      iex> ast2 = {:variable, "y"}
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

      iex> ast1 = {:variable, "x"}
      iex> ast2 = {:variable, "y"}
      iex> Metastatic.Analysis.Duplication.Fingerprint.normalized(ast1) == Metastatic.Analysis.Duplication.Fingerprint.normalized(ast2)
      true

      iex> ast1 = {:literal, :integer, 42}
      iex> ast2 = {:literal, :integer, 100}
      iex> Metastatic.Analysis.Duplication.Fingerprint.normalized(ast1) == Metastatic.Analysis.Duplication.Fingerprint.normalized(ast2)
      true

      iex> ast1 = {:binary_op, :arithmetic, :+, {:variable, "a"}, {:literal, :integer, 1}}
      iex> ast2 = {:binary_op, :arithmetic, :+, {:variable, "b"}, {:literal, :integer, 2}}
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

      iex> ast = {:literal, :integer, 42}
      iex> Metastatic.Analysis.Duplication.Fingerprint.tokens(ast)
      [:literal, :integer]

      iex> ast = {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}}
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

      iex> ast = {:literal, :integer, 42}
      iex> fp1 = Metastatic.Analysis.Duplication.Fingerprint.exact(ast)
      iex> fp2 = Metastatic.Analysis.Duplication.Fingerprint.exact(ast)
      iex> Metastatic.Analysis.Duplication.Fingerprint.match?(fp1, fp2)
      true

      iex> ast1 = {:literal, :integer, 42}
      iex> ast2 = {:literal, :string, "hello"}
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
  defp normalize_ast({:variable, _name}), do: {:variable, :_}
  defp normalize_ast({:literal, type, _value}), do: {:literal, type, :_}

  defp normalize_ast({:binary_op, category, op, left, right}) do
    {:binary_op, category, op, normalize_ast(left), normalize_ast(right)}
  end

  defp normalize_ast({:unary_op, category, op, operand}) do
    {:unary_op, category, op, normalize_ast(operand)}
  end

  defp normalize_ast({:function_call, _name, args}) when is_list(args) do
    {:function_call, :_, Enum.map(args, &normalize_ast/1)}
  end

  defp normalize_ast({:conditional, cond, then_branch, else_branch}) do
    {:conditional, normalize_ast(cond), normalize_ast(then_branch),
     if(else_branch, do: normalize_ast(else_branch), else: nil)}
  end

  defp normalize_ast({:early_return, value}) do
    {:early_return, normalize_ast(value)}
  end

  defp normalize_ast({:block, statements}) when is_list(statements) do
    {:block, Enum.map(statements, &normalize_ast/1)}
  end

  defp normalize_ast({:assignment, target, value}) do
    {:assignment, normalize_ast(target), normalize_ast(value)}
  end

  defp normalize_ast({:inline_match, pattern, value}) do
    {:inline_match, normalize_ast(pattern), normalize_ast(value)}
  end

  defp normalize_ast({:tuple, elements}) when is_list(elements) do
    {:tuple, Enum.map(elements, &normalize_ast/1)}
  end

  # M2.2 Extended layer
  defp normalize_ast({:loop, :while, cond, body}) do
    {:loop, :while, normalize_ast(cond), normalize_ast(body)}
  end

  defp normalize_ast({:loop, kind, item, collection, body}) do
    {:loop, kind, normalize_ast(item), normalize_ast(collection), normalize_ast(body)}
  end

  defp normalize_ast({:lambda, _params, _captures, body}) do
    {:lambda, :_, :_, normalize_ast(body)}
  end

  defp normalize_ast({:collection_op, kind, func, collection}) do
    {:collection_op, kind, normalize_ast(func), normalize_ast(collection)}
  end

  defp normalize_ast({:collection_op, kind, func, collection, initial}) do
    {:collection_op, kind, normalize_ast(func), normalize_ast(collection), normalize_ast(initial)}
  end

  defp normalize_ast({:pattern_match, scrutinee, arms}) when is_list(arms) do
    normalized_arms =
      Enum.map(arms, fn {pattern, body} ->
        {normalize_ast(pattern), normalize_ast(body)}
      end)

    {:pattern_match, normalize_ast(scrutinee), normalized_arms}
  end

  defp normalize_ast({:exception_handling, try_block, rescue_clauses, finally_block})
       when is_list(rescue_clauses) do
    normalized_rescues =
      Enum.map(rescue_clauses, fn {ex, var, body} ->
        {ex, normalize_ast(var), normalize_ast(body)}
      end)

    {:exception_handling, normalize_ast(try_block), normalized_rescues,
     if(finally_block, do: normalize_ast(finally_block), else: nil)}
  end

  defp normalize_ast({:async_operation, kind, operation}) do
    {:async_operation, kind, normalize_ast(operation)}
  end

  # M2.2s Structural/Organizational layer
  defp normalize_ast({:container, type, _name, _metadata, members}) when is_list(members) do
    {:container, type, :_, :_, Enum.map(members, &normalize_ast/1)}
  end

  defp normalize_ast({:function_def, visibility, _name, params, _metadata, body})
       when is_list(params) do
    normalized_params = Enum.map(params, &normalize_param/1)
    {:function_def, visibility, :_, normalized_params, :_, normalize_ast(body)}
  end

  defp normalize_ast({:attribute_access, receiver, _attribute}) do
    {:attribute_access, normalize_ast(receiver), :_}
  end

  defp normalize_ast({:augmented_assignment, op, target, value}) do
    {:augmented_assignment, op, normalize_ast(target), normalize_ast(value)}
  end

  defp normalize_ast({:property, _name, getter, setter, _metadata}) do
    {:property, :_, if(getter, do: normalize_ast(getter), else: nil),
     if(setter, do: normalize_ast(setter), else: nil), :_}
  end

  # Helper for normalizing function parameters
  defp normalize_param(param) when is_binary(param), do: :_
  defp normalize_param({:pattern, pattern}), do: {:pattern, normalize_ast(pattern)}
  defp normalize_param({:default, _name, default}), do: {:default, :_, normalize_ast(default)}

  # M2.3 Native layer - preserve structure hints but not data
  defp normalize_ast({:language_specific, lang, _native, hint, _metadata}) do
    {:language_specific, lang, :_, hint, :_}
  end

  defp normalize_ast({:language_specific, lang, _native, hint}) do
    {:language_specific, lang, :_, hint}
  end

  defp normalize_ast({:language_specific, lang, _native}) do
    {:language_specific, lang, :_}
  end

  # Wildcard and other atoms pass through
  defp normalize_ast(:_), do: :_
  defp normalize_ast(nil), do: nil
  defp normalize_ast(other), do: other

  # Extract tokens for token-based similarity
  defp extract_tokens({:variable, _name}, acc), do: [:variable | acc]
  defp extract_tokens({:literal, type, _value}, acc), do: [type, :literal | acc]

  defp extract_tokens({:binary_op, category, op, left, right}, acc) do
    acc = [op, category, :binary_op | acc]
    acc = extract_tokens(left, acc)
    extract_tokens(right, acc)
  end

  defp extract_tokens({:unary_op, category, op, operand}, acc) do
    acc = [op, category, :unary_op | acc]
    extract_tokens(operand, acc)
  end

  defp extract_tokens({:function_call, _name, args}, acc) when is_list(args) do
    acc = [:function_call | acc]
    Enum.reduce(args, acc, fn arg, a -> extract_tokens(arg, a) end)
  end

  defp extract_tokens({:conditional, cond, then_branch, else_branch}, acc) do
    acc = [:conditional | acc]
    acc = extract_tokens(cond, acc)
    acc = extract_tokens(then_branch, acc)

    if else_branch do
      extract_tokens(else_branch, acc)
    else
      acc
    end
  end

  defp extract_tokens({:early_return, value}, acc) do
    acc = [:early_return | acc]
    extract_tokens(value, acc)
  end

  defp extract_tokens({:block, statements}, acc) when is_list(statements) do
    acc = [:block | acc]
    Enum.reduce(statements, acc, fn stmt, a -> extract_tokens(stmt, a) end)
  end

  defp extract_tokens({:assignment, target, value}, acc) do
    acc = [:assignment | acc]
    acc = extract_tokens(target, acc)
    extract_tokens(value, acc)
  end

  defp extract_tokens({:inline_match, pattern, value}, acc) do
    acc = [:inline_match | acc]
    acc = extract_tokens(pattern, acc)
    extract_tokens(value, acc)
  end

  defp extract_tokens({:tuple, elements}, acc) when is_list(elements) do
    acc = [:tuple | acc]
    Enum.reduce(elements, acc, fn elem, a -> extract_tokens(elem, a) end)
  end

  # M2.2 Extended
  defp extract_tokens({:loop, :while, cond, body}, acc) do
    acc = [:while, :loop | acc]
    acc = extract_tokens(cond, acc)
    extract_tokens(body, acc)
  end

  defp extract_tokens({:loop, kind, item, collection, body}, acc) do
    acc = [kind, :loop | acc]
    acc = extract_tokens(item, acc)
    acc = extract_tokens(collection, acc)
    extract_tokens(body, acc)
  end

  defp extract_tokens({:lambda, _params, _captures, body}, acc) do
    acc = [:lambda | acc]
    extract_tokens(body, acc)
  end

  defp extract_tokens({:collection_op, kind, func, collection}, acc) do
    acc = [kind, :collection_op | acc]
    acc = extract_tokens(func, acc)
    extract_tokens(collection, acc)
  end

  defp extract_tokens({:collection_op, kind, func, collection, initial}, acc) do
    acc = [kind, :collection_op | acc]
    acc = extract_tokens(func, acc)
    acc = extract_tokens(collection, acc)
    extract_tokens(initial, acc)
  end

  defp extract_tokens({:async_operation, kind, operation}, acc) do
    acc = [kind, :async_operation | acc]
    extract_tokens(operation, acc)
  end

  # M2.2s Structural/Organizational
  defp extract_tokens({:container, type, _name, _metadata, members}, acc) when is_list(members) do
    acc = [type, :container | acc]
    Enum.reduce(members, acc, fn member, a -> extract_tokens(member, a) end)
  end

  defp extract_tokens({:function_def, visibility, _name, params, _metadata, body}, acc)
       when is_list(params) do
    acc = [visibility, :function_def | acc]
    acc = Enum.reduce(params, acc, fn param, a -> extract_param_tokens(param, a) end)
    extract_tokens(body, acc)
  end

  defp extract_tokens({:attribute_access, receiver, _attribute}, acc) do
    acc = [:attribute_access | acc]
    extract_tokens(receiver, acc)
  end

  defp extract_tokens({:augmented_assignment, op, target, value}, acc) do
    acc = [op, :augmented_assignment | acc]
    acc = extract_tokens(target, acc)
    extract_tokens(value, acc)
  end

  defp extract_tokens({:property, _name, getter, setter, _metadata}, acc) do
    acc = [:property | acc]
    acc = if getter, do: extract_tokens(getter, acc), else: acc
    if setter, do: extract_tokens(setter, acc), else: acc
  end

  # Helper for extracting tokens from function parameters
  defp extract_param_tokens(param, acc) when is_binary(param), do: [:param | acc]

  defp extract_param_tokens({:pattern, pattern}, acc),
    do: extract_tokens(pattern, [:pattern_param | acc])

  defp extract_param_tokens({:default, _name, default}, acc),
    do: extract_tokens(default, [:default_param | acc])

  # M2.3 Native
  defp extract_tokens({:language_specific, lang, _native, hint, _metadata}, acc) do
    [hint, lang, :language_specific | acc]
  end

  defp extract_tokens({:language_specific, lang, _native, hint}, acc) do
    [hint, lang, :language_specific | acc]
  end

  defp extract_tokens({:language_specific, lang, _native}, acc) do
    [lang, :language_specific | acc]
  end

  defp extract_tokens(:_, acc), do: [:wildcard | acc]
  defp extract_tokens(nil, acc), do: acc
  defp extract_tokens(_other, acc), do: acc
end
