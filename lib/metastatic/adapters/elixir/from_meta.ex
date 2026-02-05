defmodule Metastatic.Adapters.Elixir.FromMeta do
  @moduledoc """
  Transform MetaAST (M2) back to Elixir AST (M1).

  This module implements the reification function ρ_Elixir that instantiates
  meta-level representations back into Elixir-specific AST structures.

  ## New 3-Tuple Format

  All MetaAST nodes are uniform 3-element tuples:

      {type_atom, keyword_meta, children_or_value}

  Where:
  - `type_atom` - Node type (e.g., `:literal`, `:binary_op`, `:function_def`)
  - `keyword_meta` - Keyword list with metadata (line, subtype, operator, etc.)
  - `children_or_value` - Value for leaf nodes, list of children for composites

  ## Transformation Strategy

  Uses `Metastatic.AST.traverse/4` for bottom-up AST transformation:
  1. Post-order traversal: Children are transformed before parents
  2. Metadata extraction: Node attributes extracted from keyword metadata
  3. Original metadata restoration: Uses `:original_meta` when available

  ## Examples

      iex> meta_ast = {:literal, [subtype: :integer], 42}
      iex> {:ok, elixir_ast} = FromMeta.transform(meta_ast, %{})
      iex> elixir_ast
      42

      iex> meta_ast = {:binary_op, [category: :arithmetic, operator: :+],
      ...>   [{:variable, [], "x"}, {:literal, [subtype: :integer], 5}]}
      iex> {:ok, elixir_ast} = FromMeta.transform(meta_ast, %{})
      iex> elixir_ast
      {:+, [], [{:x, [], nil}, 5]}
  """

  alias Metastatic.AST

  @doc """
  Transform MetaAST back to Elixir AST.

  Returns `{:ok, elixir_ast}` on success or `{:error, reason}` on failure.

  ## Examples

      iex> FromMeta.transform({:literal, [subtype: :integer], 42}, %{})
      {:ok, 42}

      iex> FromMeta.transform({:variable, [], "x"}, %{context: Elixir})
      {:ok, {:x, [], Elixir}}
  """
  @spec transform(term(), map()) :: {:ok, term()} | {:error, String.t()}
  def transform(meta_ast, metadata \\ %{}) do
    try do
      {elixir_ast, _acc} =
        AST.traverse(meta_ast, metadata, &pre_transform/2, &post_transform/2)

      {:ok, elixir_ast}
    rescue
      e -> {:error, "Transform failed: #{Exception.message(e)}"}
    catch
      {:unsupported, reason} -> {:error, reason}
    end
  end

  # ----- Pre-Transform: Pass through -----
  # All work is done in post_transform
  defp pre_transform(ast, acc), do: {ast, acc}

  # ----- Post-Transform: Node Conversion -----

  # Already-transformed Elixir AST nodes - pass through
  # (When we recursively build, we get raw Elixir AST)
  defp post_transform(ast, acc) when not is_tuple(ast) or tuple_size(ast) != 3 do
    {ast, acc}
  end

  # Check if this is a MetaAST node (3-tuple with atom type and keyword meta)
  defp post_transform({type, meta, children} = ast, acc)
       when is_atom(type) and is_list(meta) do
    if meta_ast_type?(type) do
      transform_node(type, meta, children, acc)
    else
      # Regular Elixir AST - pass through
      {ast, acc}
    end
  end

  # Non-MetaAST tuples - pass through
  defp post_transform(ast, acc), do: {ast, acc}

  # ----- Node Type Detection -----

  @meta_ast_types [
    # Core
    :literal,
    :variable,
    :list,
    :map,
    :pair,
    :tuple,
    :binary_op,
    :unary_op,
    :function_call,
    :conditional,
    :early_return,
    :block,
    :assignment,
    :inline_match,
    # Extended
    :loop,
    :lambda,
    :collection_op,
    :pattern_match,
    :match_arm,
    :exception_handling,
    :async_operation,
    # Structural
    :container,
    :function_def,
    :attribute_access,
    :augmented_assignment,
    :property,
    # Native
    :language_specific,
    # Helpers
    :pin,
    :cons_pattern
  ]

  defp meta_ast_type?(type), do: type in @meta_ast_types

  # ----- Literal Transformations -----

  defp transform_node(:literal, meta, value, acc) do
    subtype = Keyword.get(meta, :subtype)

    elixir_value =
      case subtype do
        :integer -> value
        :float -> value
        :string -> value
        :boolean -> value
        :null -> nil
        :symbol -> value
        :regex -> value
        _ -> value
      end

    {elixir_value, acc}
  end

  # ----- Variable Transformation -----

  defp transform_node(:variable, meta, name, acc) when is_binary(name) do
    var_atom = String.to_atom(name)
    # Use original_meta if available, otherwise build from current meta
    elixir_meta = Keyword.get(meta, :original_meta, extract_elixir_meta(meta))
    context = Map.get(acc, :context, nil)
    {{var_atom, elixir_meta, context}, acc}
  end

  # ----- Binary Operators -----

  defp transform_node(:binary_op, meta, [left, right], acc) do
    op = Keyword.get(meta, :operator)
    elixir_meta = Keyword.get(meta, :original_meta, extract_elixir_meta(meta))
    {{op, elixir_meta, [left, right]}, acc}
  end

  # ----- Unary Operators -----

  defp transform_node(:unary_op, meta, [operand], acc) do
    op = Keyword.get(meta, :operator)
    elixir_meta = Keyword.get(meta, :original_meta, extract_elixir_meta(meta))
    {{op, elixir_meta, [operand]}, acc}
  end

  # ----- Inline Match (=) -----

  defp transform_node(:inline_match, meta, [pattern, value], acc) do
    elixir_meta = Keyword.get(meta, :original_meta, extract_elixir_meta(meta))
    {{:=, elixir_meta, [pattern, value]}, acc}
  end

  # ----- Lists -----

  defp transform_node(:list, _meta, elements, acc) when is_list(elements) do
    {elements, acc}
  end

  # ----- Maps -----

  defp transform_node(:map, meta, pairs, acc) when is_list(pairs) do
    elixir_meta = Keyword.get(meta, :original_meta, extract_elixir_meta(meta))
    # pairs are already transformed - convert {:pair, [], [k, v]} → {k, v}
    elixir_pairs = Enum.map(pairs, &pair_to_elixir/1)
    {{:%{}, elixir_meta, elixir_pairs}, acc}
  end

  # ----- Pairs (for maps) -----

  defp transform_node(:pair, _meta, [key, value], acc) do
    # Return as Elixir pair tuple
    {{key, value}, acc}
  end

  # ----- Tuples -----

  defp transform_node(:tuple, meta, elements, acc) when is_list(elements) do
    elixir_meta = Keyword.get(meta, :original_meta, extract_elixir_meta(meta))

    case elements do
      [] ->
        {{:{}, elixir_meta, []}, acc}

      [e1, e2] ->
        # Two-element tuple uses shorthand notation
        {{e1, e2}, acc}

      _ ->
        # Three or more elements use explicit tuple syntax
        {{:{}, elixir_meta, elements}, acc}
    end
  end

  # ----- Blocks -----

  defp transform_node(:block, meta, statements, acc) when is_list(statements) do
    elixir_meta = Keyword.get(meta, :original_meta, extract_elixir_meta(meta))

    case statements do
      [] -> {nil, acc}
      [single] -> {single, acc}
      multiple -> {{:__block__, elixir_meta, multiple}, acc}
    end
  end

  # ----- Function Calls -----

  defp transform_node(:function_call, meta, args, acc) when is_list(args) do
    name = Keyword.get(meta, :name, "unknown")
    elixir_meta = Keyword.get(meta, :original_meta, extract_elixir_meta(meta))

    case String.split(name, ".") do
      [single_name] ->
        # Local call
        func_atom = String.to_atom(single_name)
        {{func_atom, elixir_meta, args}, acc}

      parts when length(parts) > 1 ->
        # Remote call
        {func_name, module_parts} = List.pop_at(parts, -1)
        module_ast = build_module_alias(module_parts)
        func_atom = String.to_atom(func_name)
        {{{:., [], [module_ast, func_atom]}, elixir_meta, args}, acc}
    end
  end

  # ----- Conditionals -----

  defp transform_node(:conditional, meta, [condition, then_branch, else_branch], acc) do
    elixir_meta = Keyword.get(meta, :original_meta, extract_elixir_meta(meta))

    # Check if this was originally an unless
    case Keyword.get(meta, :original_form) do
      :unless ->
        # Reconstruct unless (need to undo the negation)
        actual_cond =
          case condition do
            {:not, [], [inner_cond]} -> inner_cond
            {:unary_op, _, [inner_cond]} -> inner_cond
            _ -> {:not, [], [condition]}
          end

        clauses = build_if_clauses(then_branch, else_branch)
        {{:unless, elixir_meta, [actual_cond, clauses]}, acc}

      :cond ->
        # This was a cond - but we've nested it, just emit as if
        clauses = build_if_clauses(then_branch, else_branch)
        {{:if, elixir_meta, [condition, clauses]}, acc}

      _ ->
        # Regular if
        clauses = build_if_clauses(then_branch, else_branch)
        {{:if, elixir_meta, [condition, clauses]}, acc}
    end
  end

  # ----- Pattern Matching (case) -----

  defp transform_node(:pattern_match, meta, [scrutinee | arms], acc) do
    elixir_meta = Keyword.get(meta, :original_meta, extract_elixir_meta(meta))
    arms_ex = Enum.map(arms, &match_arm_to_elixir/1)
    {{:case, elixir_meta, [scrutinee, [do: arms_ex]]}, acc}
  end

  # ----- Match Arms -----

  defp transform_node(:match_arm, meta, body, acc) do
    pattern = Keyword.get(meta, :pattern)
    _guard = Keyword.get(meta, :guard)
    elixir_meta = Keyword.get(meta, :original_meta, extract_elixir_meta(meta))

    body_ex =
      case body do
        [single] -> single
        multiple -> {:__block__, [], multiple}
      end

    # Return the clause format {:->, meta, [[pattern], body]}
    {{:->, elixir_meta, [[pattern], body_ex]}, acc}
  end

  # ----- Lambda (anonymous functions) -----

  defp transform_node(:lambda, meta, body, acc) when is_list(body) do
    params = Keyword.get(meta, :params, [])
    elixir_meta = Keyword.get(meta, :original_meta, extract_elixir_meta(meta))

    params_ex =
      Enum.map(params, fn
        {:param, name, _type, _default} ->
          {String.to_atom(name), [], nil}

        name when is_binary(name) ->
          {String.to_atom(name), [], nil}

        other ->
          other
      end)

    body_ex =
      case body do
        [single] -> single
        multiple -> {:__block__, [], multiple}
      end

    clause = {:->, [], [params_ex, body_ex]}
    {{:fn, elixir_meta, [clause]}, acc}
  end

  # ----- Collection Operations -----

  defp transform_node(:collection_op, meta, children, acc) do
    op_type = Keyword.get(meta, :op_type)
    elixir_meta = Keyword.get(meta, :original_meta, extract_elixir_meta(meta))
    enum_module = {:__aliases__, [], [:Enum]}

    case {op_type, children} do
      {:map, [func, collection]} ->
        {{{:., [], [enum_module, :map]}, elixir_meta, [collection, func]}, acc}

      {:filter, [func, collection]} ->
        {{{:., [], [enum_module, :filter]}, elixir_meta, [collection, func]}, acc}

      {:reduce, [func, collection, initial]} ->
        {{{:., [], [enum_module, :reduce]}, elixir_meta, [collection, initial, func]}, acc}

      _ ->
        throw({:unsupported, "Unknown collection_op type: #{inspect(op_type)}"})
    end
  end

  # ----- Early Return -----

  defp transform_node(:early_return, _meta, value, acc) do
    # Elixir doesn't have direct return - use throw
    {{:throw, [], [{:return, value}]}, acc}
  end

  # ----- Containers (modules, classes) -----

  defp transform_node(:container, meta, body, acc) when is_list(body) do
    container_type = Keyword.get(meta, :container_type)
    name = Keyword.get(meta, :name, "Unknown")
    elixir_meta = Keyword.get(meta, :original_meta, extract_elixir_meta(meta))

    case container_type do
      :module ->
        module_alias = name_to_alias(name)

        body_ex =
          case body do
            [] -> nil
            [single] -> single
            multiple -> {:__block__, [], multiple}
          end

        {{:defmodule, elixir_meta, [module_alias, [do: body_ex]]}, acc}

      _ ->
        throw({:unsupported, "Unsupported container type: #{inspect(container_type)}"})
    end
  end

  # ----- Function Definitions -----

  defp transform_node(:function_def, meta, body, acc) when is_list(body) do
    name = Keyword.get(meta, :name, "unknown")
    params = Keyword.get(meta, :params, [])
    visibility = Keyword.get(meta, :visibility, :public)
    elixir_meta = Keyword.get(meta, :original_meta, extract_elixir_meta(meta))

    func_atom = String.to_atom(name)
    def_type = if visibility == :private, do: :defp, else: :def

    params_ex =
      Enum.map(params, fn
        {:param, param_name, _type, _default} ->
          {String.to_atom(param_name), [], nil}

        param_name when is_binary(param_name) ->
          {String.to_atom(param_name), [], nil}

        other ->
          other
      end)

    body_ex =
      case body do
        [] -> nil
        [single] -> single
        multiple -> {:__block__, [], multiple}
      end

    signature = {func_atom, elixir_meta, params_ex}
    {{def_type, elixir_meta, [signature, [do: body_ex]]}, acc}
  end

  # ----- Pin Operator -----

  defp transform_node(:pin, meta, var, acc) do
    elixir_meta = Keyword.get(meta, :original_meta, extract_elixir_meta(meta))
    {{:^, elixir_meta, [var]}, acc}
  end

  # ----- Cons Pattern [head | tail] -----

  defp transform_node(:cons_pattern, _meta, [head, tail], acc) do
    {[head | tail], acc}
  end

  # ----- Language Specific -----

  defp transform_node(:language_specific, meta, native_ast, acc) do
    language = Keyword.get(meta, :language)

    if language == :elixir do
      {native_ast, acc}
    else
      throw({:unsupported, "Cannot reify #{language} language-specific construct to Elixir"})
    end
  end

  # ----- Loops -----

  defp transform_node(:loop, meta, children, acc) do
    loop_type = Keyword.get(meta, :loop_type)
    elixir_meta = Keyword.get(meta, :original_meta, extract_elixir_meta(meta))

    case {loop_type, children} do
      {:for, [iterator, collection, body]} ->
        # for var <- collection, do: body
        generator = {:<-, [], [iterator, collection]}

        body_ex =
          case body do
            {:block, _, stmts} when is_list(stmts) -> {:__block__, [], stmts}
            _ -> body
          end

        {{:for, elixir_meta, [generator, [do: body_ex]]}, acc}

      {:for_each, [iterator, collection, body]} ->
        # Enum.each
        enum_module = {:__aliases__, [], [:Enum]}
        lambda = {:fn, [], [{:->, [], [[iterator], body]}]}
        {{{:., [], [enum_module, :each]}, elixir_meta, [collection, lambda]}, acc}

      {:while, [_condition, _body]} ->
        # Elixir doesn't have while - would need recursion or Stream
        throw({:unsupported, "while loops not supported in Elixir"})

      _ ->
        throw({:unsupported, "Unknown loop type: #{inspect(loop_type)}"})
    end
  end

  # ----- Exception Handling -----

  defp transform_node(:exception_handling, meta, children, acc) do
    elixir_meta = Keyword.get(meta, :original_meta, extract_elixir_meta(meta))

    case children do
      [try_block | rest] ->
        # Build try expression
        clauses = [do: try_block]

        clauses =
          Enum.reduce(rest, clauses, fn
            {:catch_clause, _, [pattern, body]} ->
              catch_clause = {:->, [], [[pattern], body]}
              Keyword.update(clauses, :catch, [catch_clause], &[catch_clause | &1])

            {:rescue_clause, _, [pattern, body]} ->
              rescue_clause = {:->, [], [[pattern], body]}
              Keyword.update(clauses, :rescue, [rescue_clause], &[rescue_clause | &1])

            {:finally_clause, _, [body]} ->
              Keyword.put(clauses, :after, body)

            _ ->
              clauses
          end)

        {{:try, elixir_meta, [clauses]}, acc}

      _ ->
        throw({:unsupported, "Invalid exception_handling structure"})
    end
  end

  # ----- Attribute Access -----

  defp transform_node(:attribute_access, meta, [receiver], acc) do
    attribute = Keyword.get(meta, :attribute)
    elixir_meta = Keyword.get(meta, :original_meta, extract_elixir_meta(meta))
    attr_atom = String.to_atom(attribute)
    {{{:., [], [receiver, attr_atom]}, elixir_meta, []}, acc}
  end

  # ----- Catch-all -----

  defp transform_node(type, meta, children, _acc) do
    throw({:unsupported, "Unsupported MetaAST construct: #{inspect({type, meta, children})}"})
  end

  # ----- Helper Functions -----

  # Extract basic Elixir metadata from keyword meta
  defp extract_elixir_meta(meta) do
    meta
    |> Keyword.take([:line, :column, :end_line, :end_column])
    |> Keyword.reject(fn {_k, v} -> is_nil(v) end)
  end

  # Convert {:pair, [], [key, value]} to {key, value}
  defp pair_to_elixir({:pair, _, [key, value]}), do: {key, value}
  defp pair_to_elixir({key, value}), do: {key, value}
  defp pair_to_elixir(other), do: other

  # Build module alias AST
  defp build_module_alias(parts) do
    atoms = Enum.map(parts, &String.to_atom/1)
    {:__aliases__, [], atoms}
  end

  # Convert string name to module alias AST
  defp name_to_alias(name) do
    parts = String.split(name, ".")
    atoms = Enum.map(parts, &String.to_atom/1)
    {:__aliases__, [], atoms}
  end

  # Build if/unless clauses
  defp build_if_clauses(then_branch, nil), do: [do: then_branch]
  defp build_if_clauses(then_branch, else_branch), do: [do: then_branch, else: else_branch]

  # Convert match arm to Elixir clause
  defp match_arm_to_elixir({:match_arm, meta, body}) do
    pattern = Keyword.get(meta, :pattern)
    elixir_meta = Keyword.get(meta, :original_meta, [])

    body_ex =
      case body do
        [single] -> single
        multiple -> {:__block__, [], multiple}
      end

    {:->, elixir_meta, [[pattern], body_ex]}
  end

  defp match_arm_to_elixir({:->, meta, args}), do: {:->, meta, args}
  defp match_arm_to_elixir(other), do: other
end
