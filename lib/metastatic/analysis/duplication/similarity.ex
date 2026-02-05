defmodule Metastatic.Analysis.Duplication.Similarity do
  @moduledoc """
  Similarity calculation between ASTs for Type III clone detection.

  Implements multiple similarity metrics:
  - Structural similarity (tree-based matching)
  - Token-based similarity (Jaccard coefficient)
  - Combined similarity score

  ## Usage

      alias Metastatic.Analysis.Duplication.Similarity

      ast1 = {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}}
      ast2 = {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 10}}

      Similarity.calculate(ast1, ast2)
      # => 0.8 (80% similar)

  ## Examples

      # Identical ASTs
      iex> ast1 = {:literal, [subtype: :integer], 42}
      iex> ast2 = {:literal, [subtype: :integer], 42}
      iex> Metastatic.Analysis.Duplication.Similarity.calculate(ast1, ast2)
      1.0

      # Partially similar ASTs
      iex> ast1 = {:binary_op, [category: :arithmetic, operator: :+], [{:variable, [], "x"}, {:literal, [subtype: :integer], 5}]}
      iex> ast2 = {:binary_op, [category: :arithmetic, operator: :+], [{:variable, [], "x"}, {:literal, [subtype: :integer], 10}]}
      iex> score = Metastatic.Analysis.Duplication.Similarity.calculate(ast1, ast2)
      iex> score > 0.5
      true
  """

  alias Metastatic.Analysis.Duplication.Fingerprint
  alias Metastatic.AST

  @doc """
  Calculates overall similarity between two ASTs.

  Returns a float between 0.0 (completely different) and 1.0 (identical).
  Combines structural and token-based similarity.

  ## Options

  - `:method` - Similarity method (`:structural`, `:token`, `:combined`) (default: `:combined`)
  - `:weights` - Weights for combined method `{structural_weight, token_weight}` (default: `{0.6, 0.4}`)

  ## Examples

      iex> ast1 = {:literal, [subtype: :integer], 42}
      iex> ast2 = {:literal, [subtype: :integer], 42}
      iex> Metastatic.Analysis.Duplication.Similarity.calculate(ast1, ast2)
      1.0

      iex> ast1 = {:variable, [], "x"}
      iex> ast2 = {:literal, [subtype: :integer], 42}
      iex> Metastatic.Analysis.Duplication.Similarity.calculate(ast1, ast2)
      0.0
  """
  @spec calculate(AST.meta_ast(), AST.meta_ast(), keyword()) :: float()
  def calculate(ast1, ast2, opts \\ []) do
    method = Keyword.get(opts, :method, :combined)

    case method do
      :structural ->
        structural_similarity(ast1, ast2)

      :token ->
        token_similarity(ast1, ast2)

      :combined ->
        {struct_weight, token_weight} = Keyword.get(opts, :weights, {0.6, 0.4})
        struct_sim = structural_similarity(ast1, ast2)
        token_sim = token_similarity(ast1, ast2)
        struct_weight * struct_sim + token_weight * token_sim
    end
  end

  @doc """
  Calculates structural similarity between two ASTs.

  Compares the tree structure by counting matching nodes.
  Returns ratio of matching nodes to total nodes.

  ## Examples

      iex> ast1 = {:binary_op, [category: :arithmetic, operator: :+], [{:variable, [], "x"}, {:literal, [subtype: :integer], 5}]}
      iex> ast2 = {:binary_op, [category: :arithmetic, operator: :+], [{:variable, [], "x"}, {:literal, [subtype: :integer], 5}]}
      iex> Metastatic.Analysis.Duplication.Similarity.structural_similarity(ast1, ast2)
      1.0

      iex> ast1 = {:variable, [], "x"}
      iex> ast2 = {:variable, [], "y"}
      iex> score = Metastatic.Analysis.Duplication.Similarity.structural_similarity(ast1, ast2)
      iex> score > 0.0
      true
  """
  @spec structural_similarity(AST.meta_ast(), AST.meta_ast()) :: float()
  def structural_similarity(ast1, ast2) do
    # If exactly identical, return 1.0
    if ast1 == ast2 do
      1.0
    else
      # Use normalized fingerprints for structural comparison
      if Fingerprint.normalized(ast1) == Fingerprint.normalized(ast2) do
        1.0
      else
        # Calculate based on shared structure
        size1 = count_nodes(ast1)
        size2 = count_nodes(ast2)
        matching = count_matching_nodes(ast1, ast2)

        # Similarity = matching / average size
        avg_size = (size1 + size2) / 2

        if avg_size == 0 do
          0.0
        else
          matching / avg_size
        end
      end
    end
  end

  @doc """
  Calculates token-based similarity using Jaccard coefficient.

  Compares token sets extracted from ASTs.
  Returns |intersection| / |union|.

  ## Examples

      iex> ast1 = {:binary_op, [category: :arithmetic, operator: :+], [{:variable, [], "x"}, {:literal, [subtype: :integer], 5}]}
      iex> ast2 = {:binary_op, [category: :arithmetic, operator: :+], [{:variable, [], "y"}, {:literal, [subtype: :integer], 10}]}
      iex> score = Metastatic.Analysis.Duplication.Similarity.token_similarity(ast1, ast2)
      iex> score > 0.5
      true
  """
  @spec token_similarity(AST.meta_ast(), AST.meta_ast()) :: float()
  def token_similarity(ast1, ast2) do
    tokens1 = Fingerprint.tokens(ast1) |> MapSet.new()
    tokens2 = Fingerprint.tokens(ast2) |> MapSet.new()

    intersection = MapSet.intersection(tokens1, tokens2) |> MapSet.size()
    union = MapSet.union(tokens1, tokens2) |> MapSet.size()

    if union == 0 do
      0.0
    else
      intersection / union
    end
  end

  @doc """
  Checks if two ASTs are similar above a threshold.

  ## Examples

      iex> ast1 = {:literal, [subtype: :integer], 42}
      iex> ast2 = {:literal, [subtype: :integer], 42}
      iex> Metastatic.Analysis.Duplication.Similarity.similar?(ast1, ast2, 0.8)
      true

      iex> ast1 = {:variable, [], "x"}
      iex> ast2 = {:literal, [subtype: :integer], 42}
      iex> Metastatic.Analysis.Duplication.Similarity.similar?(ast1, ast2, 0.8)
      false
  """
  @spec similar?(AST.meta_ast(), AST.meta_ast(), float(), keyword()) :: boolean()
  def similar?(ast1, ast2, threshold \\ 0.8, opts \\ []) do
    calculate(ast1, ast2, opts) >= threshold
  end

  # Private functions

  # Count total nodes in AST (3-tuple format)
  defp count_nodes({:binary_op, _meta, [left, right]}) do
    1 + count_nodes(left) + count_nodes(right)
  end

  defp count_nodes({:unary_op, _meta, [operand]}) do
    1 + count_nodes(operand)
  end

  defp count_nodes({:function_call, _meta, args}) when is_list(args) do
    1 + Enum.sum(Enum.map(args, &count_nodes/1))
  end

  defp count_nodes({:conditional, _meta, [cond_expr, then_br, else_br]}) do
    1 + count_nodes(cond_expr) + count_nodes(then_br) +
      if(else_br, do: count_nodes(else_br), else: 0)
  end

  defp count_nodes({:block, _meta, stmts}) when is_list(stmts) do
    1 + Enum.sum(Enum.map(stmts, &count_nodes/1))
  end

  defp count_nodes({:assignment, _meta, [target, value]}) do
    1 + count_nodes(target) + count_nodes(value)
  end

  defp count_nodes({:inline_match, _meta, [pattern, value]}) do
    1 + count_nodes(pattern) + count_nodes(value)
  end

  defp count_nodes({:early_return, _meta, [value]}) do
    1 + count_nodes(value)
  end

  defp count_nodes({:tuple, _meta, elems}) when is_list(elems) do
    1 + Enum.sum(Enum.map(elems, &count_nodes/1))
  end

  defp count_nodes({:loop, meta, children}) do
    loop_type = Keyword.get(meta, :loop_type)

    case {loop_type, children} do
      {:while, [cond_expr, body]} -> 1 + count_nodes(cond_expr) + count_nodes(body)
      {_, [iter, coll, body]} -> 1 + count_nodes(iter) + count_nodes(coll) + count_nodes(body)
      {_, [cond_expr, body]} -> 1 + count_nodes(cond_expr) + count_nodes(body)
      _ -> 1
    end
  end

  defp count_nodes({:lambda, _meta, [body]}) do
    1 + count_nodes(body)
  end

  defp count_nodes({:collection_op, meta, children}) do
    case Keyword.get(meta, :initial) do
      nil ->
        case children do
          [func, coll] -> 1 + count_nodes(func) + count_nodes(coll)
          _ -> 1
        end

      _ ->
        case children do
          [func, coll, init] -> 1 + count_nodes(func) + count_nodes(coll) + count_nodes(init)
          _ -> 1
        end
    end
  end

  # M2.2s: Structural/Organizational types (3-tuple)
  defp count_nodes({:container, _meta, body}) when is_list(body) do
    1 + Enum.sum(Enum.map(body, &count_nodes/1))
  end

  defp count_nodes({:function_def, meta, [body]}) do
    params = Keyword.get(meta, :params, [])
    guards = Keyword.get(meta, :guards)
    param_count = if is_list(params), do: length(params), else: 0
    guard_count = if guards, do: count_nodes(guards), else: 0
    1 + param_count + guard_count + count_nodes(body)
  end

  defp count_nodes({:attribute_access, _meta, [receiver]}) do
    1 + count_nodes(receiver)
  end

  defp count_nodes({:augmented_assignment, _meta, [target, value]}) do
    1 + count_nodes(target) + count_nodes(value)
  end

  defp count_nodes({:property, _meta, children}) when is_list(children) do
    child_count =
      Enum.sum(
        Enum.map(children, fn
          nil -> 0
          child -> count_nodes(child)
        end)
      )

    1 + child_count
  end

  # Leaf nodes
  defp count_nodes({:literal, _meta, _value}), do: 1
  defp count_nodes({:variable, _meta, _name}), do: 1
  defp count_nodes(_), do: 1

  # Count matching nodes between two ASTs (3-tuple format)
  defp count_matching_nodes(ast1, ast2) when ast1 == ast2, do: count_nodes(ast1)

  defp count_matching_nodes({:binary_op, meta1, [l1, r1]}, {:binary_op, meta2, [l2, r2]}) do
    cat1 = Keyword.get(meta1, :category)
    op1 = Keyword.get(meta1, :operator)
    cat2 = Keyword.get(meta2, :category)
    op2 = Keyword.get(meta2, :operator)
    base = if cat1 == cat2 and op1 == op2, do: 1, else: 0
    base + count_matching_nodes(l1, l2) + count_matching_nodes(r1, r2)
  end

  defp count_matching_nodes({:unary_op, meta1, [o1]}, {:unary_op, meta2, [o2]}) do
    cat1 = Keyword.get(meta1, :category)
    op1 = Keyword.get(meta1, :operator)
    cat2 = Keyword.get(meta2, :category)
    op2 = Keyword.get(meta2, :operator)
    base = if cat1 == cat2 and op1 == op2, do: 1, else: 0
    base + count_matching_nodes(o1, o2)
  end

  defp count_matching_nodes({:function_call, _meta1, args1}, {:function_call, _meta2, args2})
       when is_list(args1) and is_list(args2) do
    if length(args1) == length(args2) do
      arg_matches =
        Enum.zip(args1, args2)
        |> Enum.map(fn {a1, a2} -> count_matching_nodes(a1, a2) end)
        |> Enum.sum()

      1 + arg_matches
    else
      0
    end
  end

  defp count_matching_nodes(
         {:conditional, _meta1, [c1, t1, e1]},
         {:conditional, _meta2, [c2, t2, e2]}
       ) do
    1 + count_matching_nodes(c1, c2) + count_matching_nodes(t1, t2) +
      case {e1, e2} do
        {nil, nil} -> 0
        {nil, _} -> 0
        {_, nil} -> 0
        {e1, e2} -> count_matching_nodes(e1, e2)
      end
  end

  defp count_matching_nodes({:block, _meta1, s1}, {:block, _meta2, s2})
       when is_list(s1) and is_list(s2) do
    if length(s1) == length(s2) do
      stmt_matches =
        Enum.zip(s1, s2)
        |> Enum.map(fn {a1, a2} -> count_matching_nodes(a1, a2) end)
        |> Enum.sum()

      1 + stmt_matches
    else
      min_len = min(length(s1), length(s2))
      matching_stmts = Enum.zip(Enum.take(s1, min_len), Enum.take(s2, min_len))
      Enum.map(matching_stmts, fn {a1, a2} -> count_matching_nodes(a1, a2) end) |> Enum.sum()
    end
  end

  defp count_matching_nodes({:assignment, _meta1, [t1, v1]}, {:assignment, _meta2, [t2, v2]}) do
    1 + count_matching_nodes(t1, t2) + count_matching_nodes(v1, v2)
  end

  # M2.2s: Structural/Organizational types (3-tuple)
  defp count_matching_nodes({:container, meta1, body1}, {:container, meta2, body2})
       when is_list(body1) and is_list(body2) do
    type1 = Keyword.get(meta1, :container_type)
    type2 = Keyword.get(meta2, :container_type)
    base = if type1 == type2, do: 1, else: 0

    if length(body1) == length(body2) do
      body_matches =
        Enum.zip(body1, body2)
        |> Enum.map(fn {b1, b2} -> count_matching_nodes(b1, b2) end)
        |> Enum.sum()

      base + body_matches
    else
      base
    end
  end

  defp count_matching_nodes({:function_def, meta1, [body1]}, {:function_def, meta2, [body2]}) do
    params1 = Keyword.get(meta1, :params, [])
    params2 = Keyword.get(meta2, :params, [])
    guards1 = Keyword.get(meta1, :guards)
    guards2 = Keyword.get(meta2, :guards)

    param_matches =
      if length(params1) == length(params2) do
        # params are strings, count as matching if same count
        length(params1)
      else
        0
      end

    guard_matches =
      case {guards1, guards2} do
        {g1, g2} when g1 != nil and g2 != nil -> count_matching_nodes(g1, g2)
        _ -> 0
      end

    1 + param_matches + guard_matches + count_matching_nodes(body1, body2)
  end

  defp count_matching_nodes(
         {:attribute_access, meta1, [obj1]},
         {:attribute_access, meta2, [obj2]}
       ) do
    attr1 = Keyword.get(meta1, :attribute)
    attr2 = Keyword.get(meta2, :attribute)
    base = if attr1 == attr2, do: 1, else: 0
    base + count_matching_nodes(obj1, obj2)
  end

  defp count_matching_nodes(
         {:augmented_assignment, meta1, [target1, value1]},
         {:augmented_assignment, meta2, [target2, value2]}
       ) do
    op1 = Keyword.get(meta1, :operator)
    op2 = Keyword.get(meta2, :operator)
    base = if op1 == op2, do: 1, else: 0
    base + count_matching_nodes(target1, target2) + count_matching_nodes(value1, value2)
  end

  defp count_matching_nodes({:property, _meta1, children1}, {:property, _meta2, children2})
       when is_list(children1) and is_list(children2) do
    if length(children1) == length(children2) do
      child_matches =
        Enum.zip(children1, children2)
        |> Enum.map(fn
          {nil, nil} -> 0
          {nil, _} -> 0
          {_, nil} -> 0
          {c1, c2} -> count_matching_nodes(c1, c2)
        end)
        |> Enum.sum()

      1 + child_matches
    else
      1
    end
  end

  defp count_matching_nodes({:literal, meta1, _}, {:literal, meta2, _}) do
    type1 = Keyword.get(meta1, :subtype)
    type2 = Keyword.get(meta2, :subtype)
    if type1 == type2, do: 1, else: 0
  end

  defp count_matching_nodes({:variable, _, _}, {:variable, _, _}), do: 1

  defp count_matching_nodes(_, _), do: 0
end
