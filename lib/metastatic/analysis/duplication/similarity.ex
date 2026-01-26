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
      iex> ast1 = {:literal, :integer, 42}
      iex> ast2 = {:literal, :integer, 42}
      iex> Metastatic.Analysis.Duplication.Similarity.calculate(ast1, ast2)
      1.0

      # Partially similar ASTs
      iex> ast1 = {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}}
      iex> ast2 = {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 10}}
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

      iex> ast1 = {:literal, :integer, 42}
      iex> ast2 = {:literal, :integer, 42}
      iex> Metastatic.Analysis.Duplication.Similarity.calculate(ast1, ast2)
      1.0

      iex> ast1 = {:variable, "x"}
      iex> ast2 = {:literal, :integer, 42}
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

      iex> ast1 = {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}}
      iex> ast2 = {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}}
      iex> Metastatic.Analysis.Duplication.Similarity.structural_similarity(ast1, ast2)
      1.0

      iex> ast1 = {:variable, "x"}
      iex> ast2 = {:variable, "y"}
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

      iex> ast1 = {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}}
      iex> ast2 = {:binary_op, :arithmetic, :+, {:variable, "y"}, {:literal, :integer, 10}}
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

      iex> ast1 = {:literal, :integer, 42}
      iex> ast2 = {:literal, :integer, 42}
      iex> Metastatic.Analysis.Duplication.Similarity.similar?(ast1, ast2, 0.8)
      true

      iex> ast1 = {:variable, "x"}
      iex> ast2 = {:literal, :integer, 42}
      iex> Metastatic.Analysis.Duplication.Similarity.similar?(ast1, ast2, 0.8)
      false
  """
  @spec similar?(AST.meta_ast(), AST.meta_ast(), float(), keyword()) :: boolean()
  def similar?(ast1, ast2, threshold \\ 0.8, opts \\ []) do
    calculate(ast1, ast2, opts) >= threshold
  end

  # Private functions

  # Count total nodes in AST
  defp count_nodes({:binary_op, _, _, left, right}) do
    1 + count_nodes(left) + count_nodes(right)
  end

  defp count_nodes({:unary_op, _, _, operand}) do
    1 + count_nodes(operand)
  end

  defp count_nodes({:function_call, _, args}) when is_list(args) do
    1 + Enum.sum(Enum.map(args, &count_nodes/1))
  end

  defp count_nodes({:conditional, cond, then_br, else_br}) do
    1 + count_nodes(cond) + count_nodes(then_br) +
      if(else_br, do: count_nodes(else_br), else: 0)
  end

  defp count_nodes({:block, stmts}) when is_list(stmts) do
    1 + Enum.sum(Enum.map(stmts, &count_nodes/1))
  end

  defp count_nodes({:assignment, target, value}) do
    1 + count_nodes(target) + count_nodes(value)
  end

  defp count_nodes({:inline_match, pattern, value}) do
    1 + count_nodes(pattern) + count_nodes(value)
  end

  defp count_nodes({:early_return, value}) do
    1 + count_nodes(value)
  end

  defp count_nodes({:tuple, elems}) when is_list(elems) do
    1 + Enum.sum(Enum.map(elems, &count_nodes/1))
  end

  defp count_nodes({:loop, :while, cond, body}) do
    1 + count_nodes(cond) + count_nodes(body)
  end

  defp count_nodes({:loop, _, iter, coll, body}) do
    1 + count_nodes(iter) + count_nodes(coll) + count_nodes(body)
  end

  defp count_nodes({:lambda, _, _, body}) do
    1 + count_nodes(body)
  end

  defp count_nodes({:collection_op, _, func, coll}) do
    1 + count_nodes(func) + count_nodes(coll)
  end

  defp count_nodes({:collection_op, _, func, coll, init}) do
    1 + count_nodes(func) + count_nodes(coll) + count_nodes(init)
  end

  # M2.2s: Structural/Organizational types
  defp count_nodes({:container, _type, _name, _parent, _type_params, _implements, body}) do
    1 + count_nodes(body)
  end

  defp count_nodes({:function_def, _name, params, _ret_type, opts, body}) when is_list(params) do
    param_count = Enum.sum(Enum.map(params, &count_nodes/1))

    guard_count =
      if is_map(opts) && Map.get(opts, :guards), do: count_nodes(Map.get(opts, :guards)), else: 0

    1 + param_count + guard_count + count_nodes(body)
  end

  defp count_nodes({:attribute_access, obj, _attr}) do
    1 + count_nodes(obj)
  end

  defp count_nodes({:augmented_assignment, _op, target, value}) do
    1 + count_nodes(target) + count_nodes(value)
  end

  defp count_nodes({:property, _name, getter, setter, _metadata}) do
    getter_count = if getter, do: count_nodes(getter), else: 0
    setter_count = if setter, do: count_nodes(setter), else: 0
    1 + getter_count + setter_count
  end

  defp count_nodes(_), do: 1

  # Count matching nodes between two ASTs
  defp count_matching_nodes(ast1, ast2) when ast1 == ast2, do: count_nodes(ast1)

  defp count_matching_nodes({:binary_op, cat1, op1, l1, r1}, {:binary_op, cat2, op2, l2, r2}) do
    base = if cat1 == cat2 and op1 == op2, do: 1, else: 0
    base + count_matching_nodes(l1, l2) + count_matching_nodes(r1, r2)
  end

  defp count_matching_nodes({:unary_op, cat1, op1, o1}, {:unary_op, cat2, op2, o2}) do
    base = if cat1 == cat2 and op1 == op2, do: 1, else: 0
    base + count_matching_nodes(o1, o2)
  end

  defp count_matching_nodes({:function_call, _, args1}, {:function_call, _, args2})
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

  defp count_matching_nodes({:conditional, c1, t1, e1}, {:conditional, c2, t2, e2}) do
    1 + count_matching_nodes(c1, c2) + count_matching_nodes(t1, t2) +
      case {e1, e2} do
        {nil, nil} -> 0
        {nil, _} -> 0
        {_, nil} -> 0
        {e1, e2} -> count_matching_nodes(e1, e2)
      end
  end

  defp count_matching_nodes({:block, s1}, {:block, s2})
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

  defp count_matching_nodes({:assignment, t1, v1}, {:assignment, t2, v2}) do
    1 + count_matching_nodes(t1, t2) + count_matching_nodes(v1, v2)
  end

  # M2.2s: Structural/Organizational types
  defp count_matching_nodes(
         {:container, type1, _name1, _parent1, _type_params1, _implements1, body1},
         {:container, type2, _name2, _parent2, _type_params2, _implements2, body2}
       ) do
    base = if type1 == type2, do: 1, else: 0
    base + count_matching_nodes(body1, body2)
  end

  defp count_matching_nodes(
         {:function_def, _name1, params1, _ret_type1, opts1, body1},
         {:function_def, _name2, params2, _ret_type2, opts2, body2}
       )
       when is_list(params1) and is_list(params2) do
    param_matches =
      if length(params1) == length(params2) do
        Enum.zip(params1, params2)
        |> Enum.map(fn {p1, p2} -> count_matching_nodes(p1, p2) end)
        |> Enum.sum()
      else
        0
      end

    guard_matches =
      case {is_map(opts1) && Map.get(opts1, :guards), is_map(opts2) && Map.get(opts2, :guards)} do
        {g1, g2} when g1 != nil and g2 != nil -> count_matching_nodes(g1, g2)
        _ -> 0
      end

    1 + param_matches + guard_matches + count_matching_nodes(body1, body2)
  end

  defp count_matching_nodes({:attribute_access, obj1, attr1}, {:attribute_access, obj2, attr2}) do
    base = if attr1 == attr2, do: 1, else: 0
    base + count_matching_nodes(obj1, obj2)
  end

  defp count_matching_nodes(
         {:augmented_assignment, op1, target1, value1},
         {:augmented_assignment, op2, target2, value2}
       ) do
    base = if op1 == op2, do: 1, else: 0
    base + count_matching_nodes(target1, target2) + count_matching_nodes(value1, value2)
  end

  defp count_matching_nodes(
         {:property, _name1, getter1, setter1, _metadata1},
         {:property, _name2, getter2, setter2, _metadata2}
       ) do
    getter_matches =
      case {getter1, getter2} do
        {g1, g2} when g1 != nil and g2 != nil -> count_matching_nodes(g1, g2)
        _ -> 0
      end

    setter_matches =
      case {setter1, setter2} do
        {s1, s2} when s1 != nil and s2 != nil -> count_matching_nodes(s1, s2)
        _ -> 0
      end

    1 + getter_matches + setter_matches
  end

  defp count_matching_nodes({:literal, type, _}, {:literal, type, _}), do: 1
  defp count_matching_nodes({:variable, _}, {:variable, _}), do: 1

  defp count_matching_nodes(_, _), do: 0
end
