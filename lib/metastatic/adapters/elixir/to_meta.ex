defmodule Metastatic.Adapters.Elixir.ToMeta do
  @moduledoc """
  Transform Elixir AST (M1) to MetaAST (M2).

  This module implements the abstraction function α_Elixir that lifts
  Elixir-specific AST structures to the meta-level representation.

  ## New 3-Tuple Format

  All MetaAST nodes are uniform 3-element tuples:

      {type_atom, keyword_meta, children_or_value}

  Where:
  - `type_atom` - Node type (e.g., `:literal`, `:binary_op`, `:function_def`)
  - `keyword_meta` - Keyword list with metadata (line, subtype, operator, etc.)
  - `children_or_value` - Value for leaf nodes, list of children for composites

  ## Metadata Preservation

  The transformation preserves M1-specific information:
  - `:original_meta` - Original Elixir AST metadata keyword list
  - `:original_code` - Source code snippet (when available)
  - `:line`, `:col` - Source location from Elixir metadata

  ## Transformation Strategy

  Uses `Macro.traverse/4` for bottom-up AST transformation:
  1. Pre-pass: Track context (module, function, arity)
  2. Post-pass: Transform Elixir nodes to MetaAST nodes

  ## Examples

      iex> {:ok, ast} = Code.string_to_quoted("x + 5")
      iex> {:ok, meta_ast, _metadata} = ToMeta.transform(ast)
      iex> meta_ast
      {:binary_op, [category: :arithmetic, operator: :+, original_meta: [line: 1]],
       [{:variable, [original_meta: [line: 1]], "x"},
        {:literal, [subtype: :integer], 5}]}
  """
  require Logger

  # Arithmetic operators
  @arithmetic_ops [:+, :-, :*, :/, :rem, :div]
  # Comparison operators
  @comparison_ops [:==, :!=, :<, :>, :<=, :>=, :===, :!==]
  # Boolean operators
  @boolean_ops [:and, :or, :&&, :||]

  @map {:__aliases__, [alias: false], [:Map]}

  @doc """
  Transform Elixir AST to MetaAST.

  Returns `{:ok, meta_ast, metadata}` on success or `{:error, reason}` on failure.

  ## Examples

      iex> ToMeta.transform(42)
      {:ok, {:literal, [subtype: :integer], 42}, %{}}

      iex> ToMeta.transform({:x, [line: 1], nil})
      {:ok, {:variable, [line: 1, original_meta: [line: 1]], "x"}, %{}}
  """
  @spec transform(term()) :: {:ok, term(), map()} | {:error, String.t()}
  def transform(elixir_ast) do
    # Initial context for tracking module/function/arity
    initial_context = %{
      module: nil,
      function: nil,
      arity: nil,
      visibility: :public
    }

    # Use Macro.traverse for bottom-up transformation
    {meta_ast, final_context} =
      Macro.traverse(
        elixir_ast,
        initial_context,
        &pre_transform/2,
        &post_transform/2
      )

    {:ok, meta_ast, final_context}
  rescue
    e -> {:error, "Transform failed: #{Exception.message(e)}"}
  end

  # ----- Pre-Transform: Context Tracking Only -----
  # We only use pre-transform to track module/function context.
  # The actual transformation happens in post_transform.

  # Track entering a module
  defp pre_transform({:defmodule, _meta, [{:__aliases__, _, parts} | _]} = ast, ctx) do
    module_name = Enum.map_join(parts, ".", &Atom.to_string/1)
    {ast, %{ctx | module: module_name}}
  end

  # Track entering a guarded function
  defp pre_transform({func_type, _meta, [{:when, _, [{name, _, args} | _]} | _]} = ast, ctx)
       when func_type in [:def, :defp, :defmacro, :defmacrop] and is_atom(name) do
    arity = if is_list(args), do: length(args), else: 0
    visibility = if func_type in [:defp, :defmacrop], do: :private, else: :public
    {ast, %{ctx | function: Atom.to_string(name), arity: arity, visibility: visibility}}
  end

  # Track entering a function
  defp pre_transform({func_type, _meta, [{name, _, args} | _]} = ast, ctx)
       when func_type in [:def, :defp, :defmacro, :defmacrop] and is_atom(name) do
    arity = if is_list(args), do: length(args), else: 0
    visibility = if func_type in [:defp, :defmacrop], do: :private, else: :public
    {ast, %{ctx | function: Atom.to_string(name), arity: arity, visibility: visibility}}
  end

  # Map update syntactic sugar → Map.merge/2
  defp pre_transform({:%{}, meta, [{:|, inner_meta, [name, values]}]}, ctx) do
    ast =
      {{:., meta, [@map, :merge]}, inner_meta,
       [name, {{:., inner_meta, [@map, :new]}, inner_meta, [values]}]}

    {ast, ctx}
  end

  # {{:., [], [{:foo, [], Elixir}, :bar]}, [no_parens: true], []}
  # {{:., [], [{:__aliases__, [alias: false], [:Map]}, :fetch!]}, [], [{:foo, [], Elixir}, :bar]}
  defp pre_transform({{:., dot_meta, [{_map, _, _}, _key] = args}, meta, []}, ctx) do
    ast = {{:., dot_meta, [@map, :fetch!]}, Keyword.delete(meta, :no_parens), args}

    {ast, ctx}
  end

  # Handle function captures in pre_transform to prevent Macro.traverse from
  # descending into the body and transforming it before we can process &1, &2, etc.
  defp pre_transform({:&, _meta, [_body]} = ast, ctx) do
    # Instead of transforming here, we mark captures to skip normal traversal.
    # We'll return a marker tuple that tells post_transform to handle the original AST.
    # Using nil as context marks it as a variable (leaf node) so Macro.traverse won't descend.
    {{:__capture_marker__, [], nil}, Map.put(ctx, :pending_capture, ast)}
  end

  # Handle try/rescue/catch in pre_transform to preserve clause structure
  # before children get transformed. We store the original and return a marker.
  defp pre_transform({:try, _meta, [[{:do, _} | _] = _clauses]} = ast, ctx) do
    {{:__try_marker__, [], nil}, Map.put(ctx, :pending_try, ast)}
  end

  # Default: pass through
  defp pre_transform(ast, ctx), do: {ast, ctx}

  # ----- Function Capture (called from pre_transform) -----

  defp transform_capture(body, meta) do
    case body do
      # &1, &2, etc - argument reference
      n when is_integer(n) ->
        param_name = "arg_#{n}"

        node_meta =
          [params: [{:param, [], param_name}], capture_form: :argument_reference] ++
            build_meta(meta)

        body_ast = {:variable, [], param_name}
        {:lambda, node_meta, [body_ast]}

      # &Module.function/arity
      {:/, _, [func_ref, arity]} when is_integer(arity) ->
        func_name = extract_captured_function_name(func_ref)
        params = for i <- 1..arity, do: {:param, [], "arg_#{i}"}
        args = for i <- 1..arity, do: {:variable, [], "arg_#{i}"}
        body_ast = {:function_call, [name: func_name], args}
        node_meta = [params: params, capture_form: :named_function] ++ build_meta(meta)
        {:lambda, node_meta, [body_ast]}

      # &(&1 + &2) - expression capture
      _ ->
        case transform_capture_body_recursive(body) do
          {transformed_body, 0} ->
            # No capture arguments - treat as zero-arity lambda
            node_meta = [params: [], capture_form: :no_arguments] ++ build_meta(meta)
            {:lambda, node_meta, [transformed_body]}

          {transformed_body, arg_count} ->
            params = for i <- 1..arg_count//1, do: {:param, [], "arg_#{i}"}

            node_meta =
              [params: params, capture_form: :expression, arity: arg_count] ++ build_meta(meta)

            {:lambda, node_meta, [transformed_body]}
        end
    end
  end

  # Transform capture body recursively without using Macro.traverse
  defp transform_capture_body_recursive(body) do
    do_transform_capture_body(body, 0)
  end

  defp do_transform_capture_body({:&, _, [n]}, max_arg) when is_integer(n) do
    # Replace &1, &2, etc. with variable references
    {{:variable, [], "arg_#{n}"}, max(max_arg, n)}
  end

  defp do_transform_capture_body({{:., dot_meta, [{:&, _, [n]}, key]}, _meta, []}, max_arg)
       when is_integer(n) do
    {{:function_call,
      [
        name: "Map.fetch!",
        original_meta: dot_meta,
        line: Keyword.get(dot_meta, :line, 1)
      ], [{:variable, [], "arg_#{n}"}, {:literal, [subtype: :symbol], key}]}, max(max_arg, n)}
  end

  defp do_transform_capture_body({op, meta, args}, max_arg) when is_atom(op) and is_list(args) do
    # Transform children first
    {transformed_args, new_max} =
      Enum.map_reduce(args, max_arg, fn arg, acc ->
        {t_arg, new_acc} = do_transform_capture_body(arg, acc)
        {t_arg, new_acc}
      end)

    # Now transform this node
    case classify_op(op) do
      {:arithmetic, operator} ->
        [left, right] = transformed_args

        {{:binary_op, [category: :arithmetic, operator: operator] ++ build_meta(meta),
          [left, right]}, new_max}

      {:comparison, operator} ->
        [left, right] = transformed_args

        {{:binary_op, [category: :comparison, operator: operator] ++ build_meta(meta),
          [left, right]}, new_max}

      {:boolean, operator} ->
        [left, right] = transformed_args

        {{:binary_op, [category: :boolean, operator: operator] ++ build_meta(meta),
          [left, right]}, new_max}

      :function_call ->
        # It's a function call
        func_name = Atom.to_string(op)
        {{:function_call, [name: func_name] ++ build_meta(meta), transformed_args}, new_max}

      unknown ->
        # Keep as-is but with transformed children
        Logger.warning("Unexpected OP: " <> inspect(unknown))
        {{op, meta, transformed_args}, new_max}
    end
  end

  # Remote function call: Module.func(args) in capture
  defp do_transform_capture_body({{:., dot_meta, [module, func]}, call_meta, args}, max_arg) do
    {transformed_args, new_max} =
      Enum.map_reduce(args, max_arg, fn arg, acc ->
        {t_arg, new_acc} = do_transform_capture_body(arg, acc)
        {t_arg, new_acc}
      end)

    module_name = extract_module_name(module)
    func_name = "#{module_name}.#{func}"
    node_meta = [name: func_name] ++ build_meta(call_meta) ++ build_meta(dot_meta)
    {{:function_call, node_meta, transformed_args}, new_max}
  end

  # Two-element tuple in capture: {&1, &2}
  defp do_transform_capture_body({left, right}, max_arg) do
    {t_left, max1} = do_transform_capture_body(left, max_arg)
    {t_right, max2} = do_transform_capture_body(right, max1)
    {{:tuple, [], [t_left, t_right]}, max2}
  end

  # List in capture: [&1, &2, &3]
  defp do_transform_capture_body(list, max_arg) when is_list(list) do
    {transformed, new_max} =
      Enum.map_reduce(list, max_arg, fn elem, acc ->
        {t_elem, new_acc} = do_transform_capture_body(elem, acc)
        {t_elem, new_acc}
      end)

    {{:list, [], transformed}, new_max}
  end

  # Literals
  defp do_transform_capture_body(value, max_arg) when is_integer(value) do
    {{:literal, [subtype: :integer], value}, max_arg}
  end

  defp do_transform_capture_body(value, max_arg) when is_float(value) do
    {{:literal, [subtype: :float], value}, max_arg}
  end

  defp do_transform_capture_body(value, max_arg) when is_binary(value) do
    {{:literal, [subtype: :string], value}, max_arg}
  end

  defp do_transform_capture_body(true, max_arg) do
    {{:literal, [subtype: :boolean], true}, max_arg}
  end

  defp do_transform_capture_body(false, max_arg) do
    {{:literal, [subtype: :boolean], false}, max_arg}
  end

  defp do_transform_capture_body(nil, max_arg) do
    {{:literal, [subtype: :null], nil}, max_arg}
  end

  defp do_transform_capture_body(atom, max_arg) when is_atom(atom) do
    {{:literal, [subtype: :symbol], atom}, max_arg}
  end

  # Fallback - keep as is
  defp do_transform_capture_body(other, max_arg) do
    {other, max_arg}
  end

  defp classify_op(op) when op in @arithmetic_ops, do: {:arithmetic, op}
  defp classify_op(op) when op in @comparison_ops, do: {:comparison, op}
  defp classify_op(op) when op in @boolean_ops, do: {:boolean, normalize_bool_op(op)}
  defp classify_op(:not), do: {:unary_boolean, :not}
  defp classify_op(op) when is_atom(op), do: :function_call
  defp classify_op(_), do: :unknown

  defp normalize_bool_op(:&&), do: :and
  defp normalize_bool_op(:||), do: :or
  defp normalize_bool_op(op), do: op

  # ----- Try/Rescue transformation (called from pre_transform marker) -----

  # Transform a try/rescue/catch block before children are transformed
  defp transform_try(clauses, meta) when is_list(clauses) do
    try_block = Keyword.get(clauses, :do)
    rescue_clauses = Keyword.get(clauses, :rescue, [])
    catch_clauses = Keyword.get(clauses, :catch, [])
    after_block = Keyword.get(clauses, :after)

    # Transform the try block body
    {:ok, try_body, _} = transform(try_block)

    # Transform rescue clauses
    handlers =
      Enum.map(rescue_clauses ++ catch_clauses, fn
        {:->, clause_meta, [[pattern], body]} ->
          {:ok, transformed_body, _} = transform(body)
          {:ok, transformed_pattern, _} = transform(pattern)
          node_meta = [pattern: transformed_pattern] ++ build_meta(clause_meta)
          {:match_arm, node_meta, flatten_body_ast(transformed_body)}

        other ->
          {:ok, transformed, _} = transform(other)
          {:match_arm, [], [transformed]}
      end)

    # Transform after block if present
    children = [try_body | handlers]

    children =
      if after_block do
        {:ok, transformed_after, _} = transform(after_block)
        children ++ [transformed_after]
      else
        children
      end

    node_meta = build_meta(meta)
    {:exception_handling, node_meta, children}
  end

  # ----- Post-Transform: Node Conversion -----

  # Handle __capture_marker__ - retrieve original capture from context and transform it
  defp post_transform({:__capture_marker__, [], nil}, ctx) do
    case Map.pop(ctx, :pending_capture) do
      {{:&, meta, [body]}, new_ctx} ->
        result = transform_capture(body, meta)
        {result, new_ctx}

      {nil, ctx} ->
        # Should not happen, but handle gracefully
        {{:literal, [subtype: :null], nil}, ctx}
    end
  end

  # Handle __try_marker__ - retrieve original try/rescue from context and transform it
  defp post_transform({:__try_marker__, [], nil}, ctx) do
    case Map.pop(ctx, :pending_try) do
      {{:try, meta, [clauses]}, new_ctx} ->
        result = transform_try(clauses, meta)
        {result, new_ctx}

      {nil, ctx} ->
        # Should not happen, but handle gracefully
        {{:literal, [subtype: :null], nil}, ctx}
    end
  end

  # Already transformed nodes - pass through
  defp post_transform({type, meta, _children} = ast, ctx)
       when is_atom(type) and is_list(meta) and
              type in [
                :literal,
                :variable,
                :binary_op,
                :unary_op,
                :function_call,
                :conditional,
                :block,
                :list,
                :map,
                :pair,
                :tuple,
                :inline_match,
                :assignment,
                :container,
                :function_def,
                :lambda,
                :pattern_match,
                :match_arm,
                :early_return,
                :attribute_access,
                :language_specific,
                :collection_op
              ] do
    {ast, ctx}
  end

  # ----- Literals -----

  # Integer
  defp post_transform(value, ctx) when is_integer(value) do
    {{:literal, [subtype: :integer], value}, ctx}
  end

  # Float
  defp post_transform(value, ctx) when is_float(value) do
    {{:literal, [subtype: :float], value}, ctx}
  end

  # String (binary)
  defp post_transform(value, ctx) when is_binary(value) do
    {{:literal, [subtype: :string], value}, ctx}
  end

  # Boolean
  defp post_transform(true, ctx) do
    {{:literal, [subtype: :boolean], true}, ctx}
  end

  defp post_transform(false, ctx) do
    {{:literal, [subtype: :boolean], false}, ctx}
  end

  # Nil
  defp post_transform(nil, ctx) do
    {{:literal, [subtype: :null], nil}, ctx}
  end

  # Atom (not true/false/nil)
  defp post_transform(atom, ctx) when is_atom(atom) do
    {{:literal, [subtype: :symbol], atom}, ctx}
  end

  # ----- Lists -----

  # List literal (already transformed children)
  defp post_transform(list, ctx) when is_list(list) do
    # Check if children are already MetaAST nodes
    if Enum.all?(list, &meta_ast_node?/1) do
      {{:list, [], list}, ctx}
    else
      # Mixed or keyword list - transform remaining elements
      transformed = Enum.map(list, &ensure_meta_ast/1)
      {{:list, [], transformed}, ctx}
    end
  end

  # ----- Variables -----

  # Variable reference
  defp post_transform({name, meta, context}, ctx)
       when is_atom(name) and is_atom(context) and not is_nil(context) do
    node_meta = build_meta(meta)
    {{:variable, node_meta, Atom.to_string(name)}, ctx}
  end

  # Variable with nil context
  defp post_transform({name, meta, nil}, ctx) when is_atom(name) do
    # Check if it's a special form
    if special_form?(name) do
      {{:literal, [subtype: :symbol] ++ build_meta(meta), name}, ctx}
    else
      node_meta = build_meta(meta)
      {{:variable, node_meta, Atom.to_string(name)}, ctx}
    end
  end

  # ----- Binary Operators -----

  # Arithmetic operators
  defp post_transform({op, meta, [left, right]}, ctx) when op in @arithmetic_ops do
    node_meta = [category: :arithmetic, operator: op] ++ build_meta(meta)
    {{:binary_op, node_meta, [left, right]}, ctx}
  end

  # String concatenation
  defp post_transform({:<>, meta, [left, right]}, ctx) do
    node_meta = [category: :arithmetic, operator: :<>] ++ build_meta(meta)
    {{:binary_op, node_meta, [left, right]}, ctx}
  end

  # Comparison operators
  defp post_transform({op, meta, [left, right]}, ctx) when op in @comparison_ops do
    node_meta = [category: :comparison, operator: op] ++ build_meta(meta)
    {{:binary_op, node_meta, [left, right]}, ctx}
  end

  # Boolean operators
  defp post_transform({op, meta, [left, right]}, ctx) when op in @boolean_ops do
    node_meta = [category: :boolean, operator: op] ++ build_meta(meta)
    {{:binary_op, node_meta, [left, right]}, ctx}
  end

  # ----- Unary Operators -----

  # Negation (unary minus) - distinguish from binary minus by single arg
  defp post_transform({:-, meta, [operand]}, ctx) do
    node_meta = [category: :arithmetic, operator: :-] ++ build_meta(meta)
    {{:unary_op, node_meta, [operand]}, ctx}
  end

  # Unary plus
  defp post_transform({:+, meta, [operand]}, ctx) do
    node_meta = [category: :arithmetic, operator: :+] ++ build_meta(meta)
    {{:unary_op, node_meta, [operand]}, ctx}
  end

  # Logical not
  defp post_transform({:not, meta, [operand]}, ctx) do
    node_meta = [category: :boolean, operator: :not] ++ build_meta(meta)
    {{:unary_op, node_meta, [operand]}, ctx}
  end

  defp post_transform({:!, meta, [operand]}, ctx) do
    node_meta = [category: :boolean, operator: :!] ++ build_meta(meta)
    {{:unary_op, node_meta, [operand]}, ctx}
  end

  # ----- Match Operator -----

  defp post_transform({:=, meta, [pattern, value]}, ctx) do
    node_meta = build_meta(meta)
    {{:inline_match, node_meta, [pattern, value]}, ctx}
  end

  # ----- Maps -----

  # Map literal - after traversal, pairs become {:tuple, [], [key_ast, value_ast]}
  defp post_transform({:%{}, meta, pairs}, ctx) when is_list(pairs) do
    # Transform pairs to {:pair, [], [key, value]} format
    pair_nodes =
      Enum.map(pairs, fn
        # Map update
        {:function_call, [{:name, "|"} | _], [struct, list]} ->
          Logger.warning("Unexpected struct update: (#{inspect(struct)} with #{inspect(list)})")

        # Already transformed as tuple: {:tuple, [], [key_ast, value_ast]}
        {:tuple, _, [key_ast, value_ast]} ->
          {:pair, [], [key_ast, value_ast]}

        # Already a pair node
        {:pair, _, _} = pair ->
          pair

        # Keyword-style pair {atom, value} - shouldn't happen after traversal but handle anyway
        {key, value} when is_atom(key) ->
          key_ast = {:literal, [subtype: :symbol], key}
          {:pair, [], [key_ast, ensure_meta_ast(value)]}

        # Other tuple - treat as key-value pair
        {key, value} ->
          {:pair, [], [ensure_meta_ast(key), ensure_meta_ast(value)]}
      end)

    node_meta = build_meta(meta)
    {{:map, node_meta, pair_nodes}, ctx}
  end

  # ----- Tuples -----

  # 2-element tuple shorthand
  defp post_transform({left, right}, ctx)
       when not is_atom(left) or
              left not in [
                :literal,
                :variable,
                :binary_op,
                :unary_op,
                :function_call,
                :conditional,
                :block,
                :list,
                :map,
                :pair,
                :tuple,
                :inline_match,
                :assignment,
                :container,
                :function_def,
                :lambda,
                :pattern_match,
                :match_arm,
                :early_return,
                :attribute_access,
                :language_specific,
                :collection_op,
                :loop,
                :exception_handling,
                :async_operation,
                :property,
                :augmented_assignment
              ] do
    {{:tuple, [], [ensure_meta_ast(left), ensure_meta_ast(right)]}, ctx}
  end

  # N-element tuple
  defp post_transform({:{}, meta, elements}, ctx) when is_list(elements) do
    node_meta = build_meta(meta)
    {{:tuple, node_meta, elements}, ctx}
  end

  # ----- Blocks -----

  defp post_transform({:__block__, meta, statements}, ctx) when is_list(statements) do
    node_meta = build_meta(meta)
    {{:block, node_meta, statements}, ctx}
  end

  # ----- Conditionals -----

  # if expression - clauses might be keyword list or transformed list
  defp post_transform({:if, meta, [condition, clauses]}, ctx) do
    {then_branch, else_branch} = extract_do_else(clauses)
    node_meta = build_meta(meta)
    {{:conditional, node_meta, [condition, then_branch, else_branch]}, ctx}
  end

  # unless expression (transform to conditional with negated condition)
  defp post_transform({:unless, meta, [condition, clauses]}, ctx) do
    {then_branch, else_branch} = extract_do_else(clauses)
    negated = {:unary_op, [category: :boolean, operator: :not], [condition]}
    node_meta = [original_form: :unless] ++ build_meta(meta)
    {{:conditional, node_meta, [negated, then_branch, else_branch]}, ctx}
  end

  # cond expression - transform to nested conditionals
  defp post_transform({:cond, meta, [clauses_wrapper]}, ctx) do
    clauses = extract_do_clauses(clauses_wrapper)
    nested = cond_to_nested_conditional(clauses)
    node_meta = [original_form: :cond] ++ build_meta(meta)
    # Merge meta into the top conditional
    case nested do
      {:conditional, inner_meta, children} ->
        {{:conditional, Keyword.merge(inner_meta, node_meta), children}, ctx}

      other ->
        {other, ctx}
    end
  end

  # ----- Case (Pattern Match) -----

  defp post_transform({:case, meta, [scrutinee, clauses_wrapper]}, ctx) do
    clauses = extract_do_clauses(clauses_wrapper)

    arms =
      Enum.map(clauses, fn
        # Original format {:->, meta, [[pattern], body]}
        {:->, clause_meta, [[pattern], body]} ->
          arm_meta = build_meta(clause_meta)
          {:match_arm, [pattern: pattern] ++ arm_meta, flatten_body(body)}

        # Transformed as function_call
        {:function_call, clause_meta, [{:list, _, [pattern]}, body]} ->
          if Keyword.get(clause_meta, :name) == "->" do
            arm_meta = build_meta(Keyword.get(clause_meta, :original_meta, []))
            {:match_arm, [pattern: pattern] ++ arm_meta, flatten_body_ast(body)}
          else
            # Unexpected format
            {:match_arm, [], [body]}
          end

        other ->
          {:match_arm, [], [other]}
      end)

    node_meta = build_meta(meta)
    {{:pattern_match, node_meta, [scrutinee | arms]}, ctx}
  end

  # ----- Function Calls -----

  # Module alias - parts may be atoms (raw) or {:literal, _, atom} (transformed)
  defp post_transform({:__aliases__, meta, parts}, ctx) when is_list(parts) do
    module_name =
      Enum.map_join(parts, ".", fn
        {:literal, _, atom} when is_atom(atom) -> Atom.to_string(atom)
        atom when is_atom(atom) -> Atom.to_string(atom)
        other -> inspect(other)
      end)

    node_meta = build_meta(meta)
    {{:variable, node_meta, module_name}, ctx}
  end

  # Remote call: Module.function(args) - raw atom function name
  defp post_transform({{:., _dot_meta, [module, func]}, meta, args}, ctx)
       when is_atom(func) and is_list(args) do
    handle_remote_call(module, func, args, meta, ctx)
  end

  # Remote call: Module.function(args) - transformed literal function name
  defp post_transform({{:., _dot_meta, [module, {:literal, _, func}]}, meta, args}, ctx)
       when is_atom(func) and is_list(args) do
    handle_remote_call(module, func, args, meta, ctx)
  end

  # Remote call: Transformed function_call representing :. operator
  # This catches cases where the inner :. got transformed to a function_call
  defp post_transform({{:function_call, dot_meta, [module, func_literal]}, meta, args}, ctx)
       when is_list(args) do
    if Keyword.get(dot_meta, :name) == "." do
      func = extract_func_name(func_literal)
      handle_remote_call(module, func, args, meta, ctx)
    else
      # Not a remote call, pass through
      {{:function_call, dot_meta, [module, func_literal]}, ctx}
    end
  end

  # Local function call
  defp post_transform({func, meta, args}, ctx)
       when is_atom(func) and is_list(args) and
              func not in [
                :fn,
                :def,
                :defp,
                :defmodule,
                :defmacro,
                :defmacrop,
                :if,
                :unless,
                :cond,
                :case,
                :try,
                :with,
                :for,
                :quote,
                :unquote,
                :@,
                :&
              ] do
    node_meta = [name: Atom.to_string(func)] ++ build_meta(meta)
    {{:function_call, node_meta, args}, ctx}
  end

  # ----- Anonymous Functions -----

  # After traversal, clauses become {:function_call, [name: "->"], [params_list, body]}
  defp post_transform({:fn, meta, clauses}, ctx) when is_list(clauses) do
    case clauses do
      # Single clause lambda - transformed clause format (check name inside body)
      [{:function_call, clause_meta, [{:list, _, params}, body]}] ->
        if Keyword.get(clause_meta, :name) == "->" do
          param_names = extract_param_names_from_meta_ast(params)
          node_meta = [params: param_names] ++ build_meta(meta)
          {{:lambda, node_meta, flatten_body_ast(body)}, ctx}
        else
          # Unexpected structure - pass through
          {{{:fn, meta, clauses}}, ctx}
        end

      # Original format (shouldn't happen after traversal but handle for safety)
      [{:->, _clause_meta, [params, body]}] ->
        param_names = extract_param_names(params)
        node_meta = [params: param_names] ++ build_meta(meta)
        {{:lambda, node_meta, flatten_body(body)}, ctx}

      # Multi-clause
      _ ->
        arms =
          Enum.map(clauses, fn
            {:function_call, clause_meta, [{:list, _, params}, body]} ->
              if Keyword.get(clause_meta, :name) == "->" do
                pattern = params_to_pattern_meta_ast(params)
                arm_meta = build_meta(Keyword.get(clause_meta, :original_meta, []))
                {:match_arm, [pattern: pattern] ++ arm_meta, flatten_body_ast(body)}
              else
                {:match_arm, [], []}
              end

            {:->, clause_meta, [params, body]} ->
              pattern = params_to_pattern(params)
              arm_meta = build_meta(clause_meta)
              {:match_arm, [pattern: pattern] ++ arm_meta, flatten_body(body)}

            _ ->
              {:match_arm, [], []}
          end)

        node_meta = [multi_clause: true] ++ build_meta(meta)
        {{:lambda, node_meta, arms}, ctx}
    end
  end

  # ----- Function Capture -----
  # Note: Captures ({:&, meta, [body]}) are handled in pre_transform to prevent
  # Macro.traverse from descending into the body and corrupting &1, &2 references.
  # The {:lambda, meta, children} nodes returned from pre_transform will pass through here.

  # ----- Module Definition -----

  # After traversal, children are transformed:
  # - name becomes {:variable, meta, "Module.Name"}
  # - body becomes {:list, [], [{:tuple, [], [{:literal, :do}, body_ast]}]}
  defp post_transform({:defmodule, meta, [name, body_container]}, ctx) do
    module_name = extract_module_name_from_meta_ast(name)
    body = extract_body_from_transformed(body_container)

    node_meta =
      [
        container_type: :module,
        name: module_name,
        module: module_name,
        language: :elixir
      ] ++ build_meta(meta)

    {{:container, node_meta, flatten_body_ast(body)}, ctx}
  end

  # ----- Function Definition -----

  # After traversal, the children are already transformed:
  # - signature becomes {:function_call, [name: "func_name"], [param vars...]}
  # - body becomes {:list, [], [{:tuple, [], [{:literal, :do}, body_ast]}]}
  defp post_transform({func_type, meta, [signature, body_container]}, ctx)
       when func_type in [:def, :defp, :defmacro, :defmacrop] do
    {func_name, params, guards} = extract_signature_from_meta_ast(signature)
    visibility = if func_type in [:defp, :defmacrop], do: :private, else: :public
    arity = length(params)

    # Extract body from the transformed container
    body = extract_body_from_transformed(body_container)

    node_meta =
      [
        name: func_name,
        params: params,
        visibility: visibility,
        arity: arity,
        function: func_name,
        language: :elixir
      ] ++ build_meta(meta)

    # Add guards if present
    node_meta = if guards, do: [guards: guards] ++ node_meta, else: node_meta

    {{:function_def, node_meta, flatten_body_ast(body)}, ctx}
  end

  # ----- Module Attributes -----

  defp post_transform({:@, meta, [{attr_name, _attr_meta, [value]}]}, ctx) do
    var_name = "@#{attr_name}"
    node_meta = [attribute_type: :module_attribute] ++ build_meta(meta)
    target = {:variable, [], var_name}
    {{:assignment, node_meta, [target, value]}, ctx}
  end

  # ----- Try/Rescue -----

  defp post_transform({:try, meta, [[do: try_block] ++ rest]}, ctx) do
    rescue_clauses = Keyword.get(rest, :rescue, [])
    catch_clauses = Keyword.get(rest, :catch, [])
    after_block = Keyword.get(rest, :after)

    handlers = transform_rescue_clauses(rescue_clauses ++ catch_clauses)
    node_meta = build_meta(meta)

    children = [try_block | handlers]
    children = if after_block, do: children ++ [after_block], else: children

    {{:exception_handling, node_meta, children}, ctx}
  end

  # ----- Pipe Operator -----

  defp post_transform({:|>, meta, [left, right]}, ctx) do
    node_meta = [language: :elixir, hint: :pipe] ++ build_meta(meta)
    {{:language_specific, node_meta, {:|>, meta, [left, right]}}, ctx}
  end

  # ----- With Expression -----

  defp post_transform({:with, meta, _args} = ast, ctx) do
    node_meta = [language: :elixir, hint: :with] ++ build_meta(meta)
    {{:language_specific, node_meta, ast}, ctx}
  end

  # ----- For Comprehension -----

  defp post_transform({:for, meta, args}, ctx) do
    {generators, opts} = extract_comprehension_parts(args)
    body = Keyword.get(opts, :do)

    case generators do
      [{:<-, _, [var, collection]}] ->
        # Simple map-like comprehension
        var_name = extract_var_name(var)
        param = {:param, [], var_name}
        lambda = {:lambda, [params: [param]], flatten_body(body)}
        node_meta = [op_type: :map, original_form: :comprehension] ++ build_meta(meta)
        {{:collection_op, node_meta, [lambda, collection]}, ctx}

      _ ->
        # Complex comprehension - preserve as language_specific
        node_meta = [language: :elixir, hint: :comprehension] ++ build_meta(meta)
        {{:language_specific, node_meta, {:for, meta, args}}, ctx}
    end
  end

  # ----- Attribute Access -----

  # Map/struct field access: map.field
  defp post_transform({{:., _dot_meta, [receiver, field]}, meta, []}, ctx)
       when is_atom(field) do
    node_meta = [attribute: Atom.to_string(field)] ++ build_meta(meta)
    {{:attribute_access, node_meta, [receiver]}, ctx}
  end

  # ----- Catch-all -----

  # Anything else passes through unchanged
  defp post_transform(ast, ctx) do
    {ast, ctx}
  end

  # ----- Helper Functions -----

  defp handle_remote_call(module, func, args, meta, ctx) when is_atom(func) do
    module_name = extract_module_name(module)
    func_name = "#{module_name}.#{func}"

    # Check for Enum operations
    case {module_name, func, args} do
      {"Enum", :map, [collection, func_arg]} ->
        node_meta = [op_type: :map] ++ build_meta(meta)
        {{:collection_op, node_meta, [func_arg, collection]}, ctx}

      {"Enum", :filter, [collection, func_arg]} ->
        node_meta = [op_type: :filter] ++ build_meta(meta)
        {{:collection_op, node_meta, [func_arg, collection]}, ctx}

      {"Enum", :reduce, [collection, initial, func_arg]} ->
        node_meta = [op_type: :reduce] ++ build_meta(meta)
        {{:collection_op, node_meta, [func_arg, collection, initial]}, ctx}

      _ ->
        node_meta = [name: func_name] ++ build_meta(meta)
        {{:function_call, node_meta, args}, ctx}
    end
  end

  defp extract_func_name({:literal, _, func}) when is_atom(func), do: func
  defp extract_func_name(func) when is_atom(func), do: func
  defp extract_func_name(_), do: :unknown

  # Build metadata keyword list from Elixir AST meta
  defp build_meta(elixir_meta) when is_list(elixir_meta) do
    base = [original_meta: elixir_meta]

    base
    |> maybe_add(:line, Keyword.get(elixir_meta, :line))
    |> maybe_add(:col, Keyword.get(elixir_meta, :column))
  end

  defp build_meta(_), do: []

  defp maybe_add(keyword, _key, nil), do: keyword
  defp maybe_add(keyword, key, value), do: Keyword.put(keyword, key, value)

  # Check if a value is already a MetaAST node
  defp meta_ast_node?({type, meta, _children})
       when is_atom(type) and is_list(meta) and
              type in [
                :literal,
                :variable,
                :binary_op,
                :unary_op,
                :function_call,
                :conditional,
                :block,
                :list,
                :map,
                :pair,
                :tuple,
                :inline_match,
                :assignment,
                :container,
                :function_def,
                :lambda,
                :pattern_match,
                :match_arm,
                :early_return,
                :attribute_access,
                :language_specific,
                :collection_op,
                :loop,
                :exception_handling,
                :async_operation,
                :property,
                :augmented_assignment
              ] do
    true
  end

  defp meta_ast_node?(_), do: false

  # Ensure a value is a MetaAST node
  defp ensure_meta_ast(value) when is_integer(value) do
    {:literal, [subtype: :integer], value}
  end

  defp ensure_meta_ast(value) when is_float(value) do
    {:literal, [subtype: :float], value}
  end

  defp ensure_meta_ast(value) when is_binary(value) do
    {:literal, [subtype: :string], value}
  end

  defp ensure_meta_ast(true), do: {:literal, [subtype: :boolean], true}
  defp ensure_meta_ast(false), do: {:literal, [subtype: :boolean], false}
  defp ensure_meta_ast(nil), do: {:literal, [subtype: :null], nil}

  defp ensure_meta_ast(atom) when is_atom(atom) do
    {:literal, [subtype: :symbol], atom}
  end

  defp ensure_meta_ast({type, meta, _children} = ast)
       when is_atom(type) and is_list(meta) do
    if meta_ast_node?(ast), do: ast, else: {:literal, [subtype: :symbol], ast}
  end

  defp ensure_meta_ast(other), do: other

  # Check if an atom is a special form
  defp special_form?(name) do
    name in [
      :__block__,
      :__aliases__,
      :__MODULE__,
      :__DIR__,
      :__ENV__,
      :__CALLER__,
      :__STACKTRACE__,
      :_,
      :^,
      :when,
      :%{},
      :{}
    ]
  end

  # Extract module name from AST
  defp extract_module_name({:__aliases__, _, parts}) do
    Enum.map_join(parts, ".", &Atom.to_string/1)
  end

  defp extract_module_name({:variable, _, name}) when is_binary(name), do: name

  # Handle transformed literal atoms (e.g., :telemetry becomes {:literal, _, :telemetry})
  defp extract_module_name({:literal, _, atom}) when is_atom(atom), do: Atom.to_string(atom)

  defp extract_module_name(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp extract_module_name({name, _, _}) when is_atom(name), do: Atom.to_string(name)
  defp extract_module_name(_), do: "unknown"

  # Extract parameter names (for lambdas)
  defp extract_param_names(params) when is_list(params) do
    Enum.map(params, fn
      {name, _, context} when is_atom(name) and is_atom(context) ->
        {:param, [], Atom.to_string(name)}

      _ ->
        {:param, [], "_"}
    end)
  end

  defp extract_param_names(_), do: []

  # Convert params list to pattern for multi-clause lambdas
  defp params_to_pattern([single]), do: single
  defp params_to_pattern(params), do: {:tuple, [], params}

  # Extract parameter names from already-transformed MetaAST params
  defp extract_param_names_from_meta_ast(params) when is_list(params) do
    Enum.map(params, fn
      {:variable, _, name} -> {:param, [], name}
      _ -> {:param, [], "_"}
    end)
  end

  defp extract_param_names_from_meta_ast(_), do: []

  # Convert transformed params list to pattern for multi-clause lambdas
  defp params_to_pattern_meta_ast([single]), do: single
  defp params_to_pattern_meta_ast(params), do: {:tuple, [], params}

  # Extract variable name
  defp extract_var_name({name, _, _}) when is_atom(name), do: Atom.to_string(name)
  defp extract_var_name(_), do: "_"

  # Flatten body to list of statements (for raw Elixir AST)
  defp flatten_body({:__block__, _, statements}), do: statements
  defp flatten_body({:block, _, statements}), do: statements
  defp flatten_body(nil), do: []
  defp flatten_body(single), do: [single]

  # Flatten body that's already transformed to MetaAST
  defp flatten_body_ast({:block, _, statements}), do: statements
  defp flatten_body_ast(nil), do: []
  defp flatten_body_ast({:literal, [subtype: :null], nil}), do: []
  defp flatten_body_ast(single), do: [single]

  # Extract function signature info from transformed MetaAST
  # With args: signature becomes {:function_call, [name: "func_name"], [params...]}
  # Without args: signature becomes {:variable, meta, "func_name"}
  defp extract_signature_from_meta_ast({:function_call, meta, params}) do
    func_name = Keyword.get(meta, :name, "anonymous")
    # Convert parameter MetaAST nodes to {:param, [], name} format
    param_list =
      Enum.map(params, fn
        {:variable, _, name} -> {:param, [], name}
        _ -> {:param, [], "_"}
      end)

    {func_name, param_list, nil}
  end

  # Zero-arity function: signature becomes a variable
  defp extract_signature_from_meta_ast({:variable, _, func_name}) do
    {func_name, [], nil}
  end

  # Handle guarded functions - signature would include guard info
  defp extract_signature_from_meta_ast(_), do: {"anonymous", [], nil}

  # Extract module name from transformed MetaAST
  # The name becomes {:variable, meta, "Module.Name"}
  defp extract_module_name_from_meta_ast({:variable, _, name}), do: name

  defp extract_module_name_from_meta_ast({:literal, _, atom}) when is_atom(atom),
    do: Atom.to_string(atom)

  defp extract_module_name_from_meta_ast(_), do: "unknown"

  # Extract body from transformed container
  # Body becomes {:list, [], [{:tuple, [], [{:literal, :do}, body_ast]}]}
  defp extract_body_from_transformed({:list, _, items}) do
    # Find the :do item
    Enum.find_value(items, nil, fn
      {:tuple, _, [{:literal, [subtype: :symbol], :do}, body]} -> body
      {:pair, _, [{:literal, [subtype: :symbol], :do}, body]} -> body
      _ -> nil
    end)
  end

  defp extract_body_from_transformed([{:tuple, _, [{:literal, [subtype: :symbol], :do}, body]}]) do
    body
  end

  defp extract_body_from_transformed(_), do: nil

  # Extract do/else branches from clauses (handles both raw keyword and transformed list)
  defp extract_do_else(clauses) when is_list(clauses) do
    # Check if this is a keyword list [do: x, else: y] or transformed list
    case clauses do
      [{key, _value} | _] when is_atom(key) ->
        # Raw keyword list
        then_branch = Keyword.get(clauses, :do)
        else_branch = Keyword.get(clauses, :else)
        {then_branch, else_branch}

      _ ->
        # Not a keyword list - might be transformed or something else
        {nil, nil}
    end
  end

  defp extract_do_else({:list, _, items}) do
    # Transformed list: {:list, [], [{:tuple, [], [{:literal, :do}, x]}, ...]}
    then_branch =
      Enum.find_value(items, nil, fn
        {:tuple, _, [{:literal, [subtype: :symbol], :do}, body]} -> body
        {:pair, _, [{:literal, [subtype: :symbol], :do}, body]} -> body
        _ -> nil
      end)

    else_branch =
      Enum.find_value(items, nil, fn
        {:tuple, _, [{:literal, [subtype: :symbol], :else}, body]} -> body
        {:pair, _, [{:literal, [subtype: :symbol], :else}, body]} -> body
        _ -> nil
      end)

    {then_branch, else_branch}
  end

  defp extract_do_else(_), do: {nil, nil}

  # Extract do clauses from wrapper (handles both raw keyword and transformed)
  defp extract_do_clauses(do: clauses) when is_list(clauses), do: clauses
  defp extract_do_clauses(do: single), do: [single]

  defp extract_do_clauses({:list, _, items}) do
    # Find :do item and extract its content
    Enum.find_value(items, [], fn
      {:tuple, _, [{:literal, [subtype: :symbol], :do}, {:list, _, clauses}]} -> clauses
      {:pair, _, [{:literal, [subtype: :symbol], :do}, {:list, _, clauses}]} -> clauses
      {:tuple, _, [{:literal, [subtype: :symbol], :do}, body]} -> [body]
      {:pair, _, [{:literal, [subtype: :symbol], :do}, body]} -> [body]
      _ -> nil
    end)
  end

  defp extract_do_clauses(_), do: []

  # Transform cond clauses to nested conditionals
  defp cond_to_nested_conditional([]), do: {:literal, [subtype: :null], nil}

  defp cond_to_nested_conditional([{:->, _, [[condition], body]} | rest]) do
    else_branch = cond_to_nested_conditional(rest)
    {:conditional, [], [condition, body, else_branch]}
  end

  # Handle transformed cond clauses
  defp cond_to_nested_conditional([
         {:function_call, meta, [{:list, _, [condition]}, body]} | rest
       ]) do
    if Keyword.get(meta, :name) == "->" do
      else_branch = cond_to_nested_conditional(rest)
      {:conditional, [], [condition, body, else_branch]}
    else
      {:literal, [subtype: :null], nil}
    end
  end

  defp cond_to_nested_conditional(_), do: {:literal, [subtype: :null], nil}

  # Transform rescue/catch clauses
  defp transform_rescue_clauses(clauses) do
    Enum.map(clauses, fn
      {:->, meta, [[pattern], body]} ->
        node_meta = [pattern: pattern] ++ build_meta(meta)
        {:match_arm, node_meta, flatten_body(body)}
    end)
  end

  # Extract comprehension parts
  defp extract_comprehension_parts(args) do
    {generators, rest} =
      Enum.split_while(args, fn
        {:<-, _, _} -> true
        _ -> false
      end)

    opts =
      case List.last(rest) do
        kw when is_list(kw) -> kw
        _ -> []
      end

    {generators, opts}
  end

  # Extract captured function name
  defp extract_captured_function_name({{:., _, [module, func]}, _, []}) do
    "#{extract_module_name(module)}.#{func}"
  end

  defp extract_captured_function_name({func, _, _}) when is_atom(func) do
    Atom.to_string(func)
  end

  defp extract_captured_function_name(_), do: "unknown"
end
