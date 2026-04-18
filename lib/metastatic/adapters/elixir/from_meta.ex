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
    {elixir_ast, _acc} =
      AST.traverse(meta_ast, metadata, &pre_transform/2, &post_transform/2)

    {:ok, elixir_ast}
  rescue
    e -> {:error, "Transform failed: #{Exception.message(e)}"}
  catch
    {:unsupported, reason} -> {:error, reason}
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
  # When :original_macro metadata is present (from ExPanda expansion),
  # restore the original surface-level macro call for round-trip fidelity.
  defp post_transform({type, meta, children} = ast, acc)
       when is_atom(type) and is_list(meta) do
    if meta_ast_type?(type) do
      case Keyword.get(meta, :original_macro) do
        nil ->
          transform_node(type, meta, children, acc)

        original_macro_ast when is_tuple(original_macro_ast) ->
          # The stored value is the original Elixir AST macro call.
          # Return it directly, skipping reconstruction from the expanded form.
          {original_macro_ast, acc}
      end
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
    :import,
    :type_annotation,
    # New types
    :range,
    :string_interpolation,
    :comprehension,
    :generator,
    :filter,
    # Native
    :language_specific,
    # Helpers
    :pin,
    :assert_type,
    :cons_pattern,
    # v0.20.0 bitstring grammar and trivia
    :bin_segment,
    :comment
  ]

  defp meta_ast_type?(type), do: type in @meta_ast_types

  # ----- Literal Transformations -----

  defp transform_node(:literal, meta, value, acc) do
    subtype = Keyword.get(meta, :subtype)
    elixir_meta = Keyword.get(meta, :original_meta, extract_elixir_meta(meta))

    case subtype do
      :bytes when is_list(value) ->
        # Segment-list payload (Cure v0.20.0+). The individual
        # `:bin_segment` nodes have already been post-transformed to
        # Elixir `{:"::", ...}` tuples (or bare values for unspecified
        # segments). Wrap them in the Elixir `<<>>` form.
        {{:<<>>, elixir_meta, value}, acc}

      :bytes when is_binary(value) ->
        # Legacy raw-binary payload.
        bytes = :binary.bin_to_list(value)
        {{:<<>>, elixir_meta, bytes}, acc}

      _ ->
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
  end

  # ----- Bitstring Segment (Cure v0.20.0+) -----

  # After post-order traversal `value` is already a raw Elixir AST
  # node. Build either a bare value (no specifiers) or an Elixir
  # `{:"::", meta, [value, spec]}` wrapper whose `spec` is a
  # specifier chain joined by `-`.
  defp transform_node(:bin_segment, meta, [value], acc) do
    elixir_meta = Keyword.get(meta, :original_meta, extract_elixir_meta(meta))
    spec = build_bin_segment_spec(meta, acc)

    case spec do
      nil -> {value, acc}
      spec_ast -> {{:"::", elixir_meta, [value, spec_ast]}, acc}
    end
  end

  # ----- Trivia Comment (Cure v0.20.0+) -----

  # Elixir has no surface syntax for free-standing comments inside the
  # AST; they are stripped by the tokenizer. Map `:comment` to the unit
  # `nil` so callers can treat it as a no-op while still surviving
  # `Macro.to_string/1`. Formatters that care about comments should
  # consume the MetaAST directly rather than going through this adapter.
  defp transform_node(:comment, _meta, _text, acc), do: {nil, acc}

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
    # Use original_op for round-trip fidelity (e.g., :&& instead of normalized :and)
    op = Keyword.get(meta, :original_op, Keyword.get(meta, :operator))
    elixir_meta = Keyword.get(meta, :original_meta, extract_elixir_meta(meta))
    {{op, elixir_meta, [left, right]}, acc}
  end

  # ----- Unary Operators -----

  defp transform_node(:unary_op, meta, [operand], acc) do
    op = Keyword.get(meta, :operator)
    elixir_meta = Keyword.get(meta, :original_meta, extract_elixir_meta(meta))
    {{op, elixir_meta, [operand]}, acc}
  end

  # ----- Range -----

  defp transform_node(:range, meta, [start, stop], acc) do
    elixir_meta = Keyword.get(meta, :original_meta, extract_elixir_meta(meta))

    case Keyword.get(meta, :step) do
      nil ->
        # Simple range: start..stop
        {{:.., elixir_meta, [start, stop]}, acc}

      step ->
        # Range with step: start..stop//step
        # Step is stored in metadata and NOT traversed by AST.traverse,
        # so we must transform it manually here.
        {:ok, step_ex} = __MODULE__.transform(step, acc)
        {{:..//, elixir_meta, [start, stop, step_ex]}, acc}
    end
  end

  # ----- String Interpolation -----

  defp transform_node(:string_interpolation, meta, parts, acc) when is_list(parts) do
    elixir_meta = Keyword.get(meta, :original_meta, extract_elixir_meta(meta))

    elixir_parts =
      Enum.map(parts, fn
        # Plain string literal - after traversal it's a raw string
        value when is_binary(value) -> value
        # Expression part - wrap in interpolation syntax
        expr -> {:"::", [], [{{:., [], [Kernel, :to_string]}, [], [expr]}, {:binary, [], nil}]}
      end)

    {{:<<>>, elixir_meta, elixir_parts}, acc}
  end

  # ----- Inline Match (=) -----

  defp transform_node(:inline_match, meta, [pattern, value], acc) do
    elixir_meta = Keyword.get(meta, :original_meta, extract_elixir_meta(meta))

    case Keyword.get(meta, :original_form) do
      # with clause: reconstruct as `<-` instead of `=`
      :with_clause ->
        {{:<-, elixir_meta, [pattern, value]}, acc}

      _ ->
        {{:=, elixir_meta, [pattern, value]}, acc}
    end
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

    case Keyword.get(meta, :original_form) do
      :with ->
        # Reconstruct with expression from inline_match clauses + body
        reconstruct_with(statements, elixir_meta, acc)

      _ ->
        case statements do
          [] -> {nil, acc}
          [single] -> {single, acc}
          multiple -> {{:__block__, elixir_meta, multiple}, acc}
        end
    end
  end

  # ----- Function Calls -----

  defp transform_node(:function_call, meta, args, acc) when is_list(args) do
    name = Keyword.get(meta, :name, "unknown")
    elixir_meta = Keyword.get(meta, :original_meta, extract_elixir_meta(meta))

    case Keyword.get(meta, :original_form) do
      # Range with step: 1..10//2 -> {:"..//", meta, [start, stop, step]}
      :range_step ->
        {{:..//, elixir_meta, args}, acc}

      _ ->
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
  end

  # ----- Conditionals -----

  defp transform_node(:conditional, meta, [condition, then_branch, else_branch], acc) do
    elixir_meta = Keyword.get(meta, :original_meta, extract_elixir_meta(meta))

    case Keyword.get(meta, :original_form) do
      :unless ->
        # Reconstruct unless (undo the negation)
        actual_cond =
          case condition do
            {:not, [], [inner_cond]} -> inner_cond
            {:unary_op, _, [inner_cond]} -> inner_cond
            _ -> {:not, [], [condition]}
          end

        clauses = build_if_clauses(then_branch, else_branch)
        {{:unless, elixir_meta, [actual_cond, clauses]}, acc}

      :cond ->
        # Unflatten nested conditionals back to cond clauses
        cond_clauses = collect_cond_clauses(condition, then_branch, else_branch)
        {{:cond, elixir_meta, [[do: cond_clauses]]}, acc}

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

    # Pattern is stored in metadata and not traversed by AST.traverse,
    # so we must transform it manually here.
    pattern_ex =
      if pattern do
        {:ok, transformed} = __MODULE__.transform(pattern, acc)
        transformed
      else
        :_
      end

    body_ex =
      case body do
        [single] -> single
        multiple -> {:__block__, [], multiple}
      end

    # Return the clause format {:->, meta, [[pattern], body]}
    {{:->, elixir_meta, [[pattern_ex], body_ex]}, acc}
  end

  # ----- Lambda (anonymous functions) -----

  defp transform_node(:lambda, meta, body, acc) when is_list(body) do
    elixir_meta = Keyword.get(meta, :original_meta, extract_elixir_meta(meta))
    multi_clause = Keyword.get(meta, :multi_clause, false)
    capture_form = Keyword.get(meta, :capture_form)

    cond do
      # Function capture: &func/arity or &(&1 + &2)
      capture_form in [:named_function, :argument_reference, :expression] ->
        reconstruct_capture(meta, body, elixir_meta, acc)

      # Multi-clause fn: fn :a -> 1; :b -> 2 end
      multi_clause ->
        clauses =
          Enum.map(body, fn
            {:match_arm, arm_meta, arm_body} ->
              pattern = Keyword.get(arm_meta, :pattern)
              arm_ex_meta = Keyword.get(arm_meta, :original_meta, [])

              arm_body_ex =
                case arm_body do
                  [single] -> single
                  multiple -> {:__block__, [], multiple}
                end

              params =
                case pattern do
                  {:tuple, _, elts} -> elts
                  single -> [single]
                end

              {:->, arm_ex_meta, [params, arm_body_ex]}

            # Fallback for already-transformed clauses
            {:->, _, _} = clause ->
              clause

            other ->
              {:->, [], [[:_], other]}
          end)

        {{:fn, elixir_meta, clauses}, acc}

      # Single-clause lambda: fn x -> x end
      true ->
        params = Keyword.get(meta, :params, [])

        params_ex =
          Enum.map(params, fn
            {:param, _meta, name} when is_binary(name) ->
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
    guards = Keyword.get(meta, :guards)
    elixir_meta = Keyword.get(meta, :original_meta, extract_elixir_meta(meta))

    func_atom = String.to_atom(name)
    def_type = if visibility == :private, do: :defp, else: :def

    params_ex =
      Enum.map(params, fn
        {:param, _meta, param_name} when is_binary(param_name) ->
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

    # Wrap signature with guard clause if present.
    # Guards are stored in metadata and not traversed by AST.traverse,
    # so we must transform them manually here.
    signature =
      if guards do
        {:ok, guards_ex} = __MODULE__.transform(guards, acc)
        {:when, elixir_meta, [signature, guards_ex]}
      else
        signature
      end

    {{def_type, elixir_meta, [signature, [do: body_ex]]}, acc}
  end

  # ----- Assignment -----

  defp transform_node(:assignment, meta, [target, value], acc) do
    elixir_meta = Keyword.get(meta, :original_meta, extract_elixir_meta(meta))

    case Keyword.get(meta, :attribute_type) do
      :module_attribute ->
        # Module attribute: @attr value
        # After traversal, target was {:variable, [], "@attr_name"} which became
        # {:'@attr_name', [], nil}. Strip the @ prefix to get the attribute atom.
        attr_name =
          case target do
            {var_atom, _, _} when is_atom(var_atom) ->
              var_atom
              |> Atom.to_string()
              |> String.trim_leading("@")
              |> String.to_atom()

            _ ->
              :unknown
          end

        {{:@, elixir_meta, [{attr_name, elixir_meta, [value]}]}, acc}

      _ ->
        # Plain assignment (imperative binding)
        {{:=, elixir_meta, [target, value]}, acc}
    end
  end

  # ----- Pin Operator -----

  # Canonical MetaAST shape: {:pin, meta, [inner]} (list with one child).
  # Matches the Cure v0.18.0 convention and this module's documented spec.
  defp transform_node(:pin, meta, [inner], acc) do
    elixir_meta = Keyword.get(meta, :original_meta, extract_elixir_meta(meta))
    {{:^, elixir_meta, [inner]}, acc}
  end

  # Compile-time type assertion (Cure v0.19.0+).
  # Elixir has no direct surface syntax for this; reify to the inner
  # expression and drop the wrapper, which matches Cure's codegen behaviour.
  defp transform_node(:assert_type, _meta, [expr, _type_ast], acc) do
    {expr, acc}
  end

  # ----- Cons Pattern [head | tail] -----

  defp transform_node(:cons_pattern, _meta, [head, tail], acc) do
    {[head | tail], acc}
  end

  # ----- Comprehension -----

  defp transform_node(:comprehension, meta, [body | generators_and_filters], acc) do
    elixir_meta = Keyword.get(meta, :original_meta, extract_elixir_meta(meta))

    # generators/filters are already transformed by AST.traverse to Elixir forms
    clauses =
      Enum.map(generators_and_filters, fn
        # After traversal, generator becomes {:<-, meta, [var, coll]} (Elixir AST)
        {:<-, _, _} = gen -> gen
        # Filter becomes raw Elixir AST condition
        filter -> filter
      end)

    into = Keyword.get(meta, :into)
    opts = [do: body]
    opts = if into, do: Keyword.put(opts, :into, into), else: opts

    {{:for, elixir_meta, clauses ++ [opts]}, acc}
  end

  # ----- Generator (inside comprehension) -----

  defp transform_node(:generator, meta, [variable, collection], acc) do
    elixir_meta = Keyword.get(meta, :original_meta, extract_elixir_meta(meta))
    {{:<-, elixir_meta, [variable, collection]}, acc}
  end

  # ----- Filter (inside comprehension) -----

  defp transform_node(:filter, _meta, [condition], acc) do
    {condition, acc}
  end

  # ----- Type Annotation -----

  defp transform_node(:type_annotation, meta, [type_expr], acc) do
    annotation_type = Keyword.get(meta, :annotation_type, :spec)
    elixir_meta = Keyword.get(meta, :original_meta, extract_elixir_meta(meta))

    # type_expr is a language_specific node wrapping the original Elixir type AST.
    # After traversal, the language_specific handler returns the native AST.
    # So type_expr here is already the raw Elixir type AST.
    {{:@, elixir_meta, [{annotation_type, elixir_meta, [type_expr]}]}, acc}
  end

  # ----- Language Specific -----

  defp transform_node(:language_specific, meta, native_ast, acc) do
    language = Keyword.get(meta, :language)

    case language do
      :elixir ->
        {native_ast, acc}

      _ ->
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
        # After bottom-up traversal, match_arm children are already transformed
        # to {:->, ...} clauses. Separate clause handlers from a potential after block.
        {rescue_clauses, after_block} = split_exception_handlers(rest)

        # Build keyword list in the order Macro.to_string expects: do, rescue, after
        clauses = [do: try_block]
        clauses = if rescue_clauses != [], do: clauses ++ [rescue: rescue_clauses], else: clauses
        clauses = if after_block, do: clauses ++ [after: after_block], else: clauses

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

  # ----- Import Directives -----

  defp transform_node(:import, meta, [], acc) do
    import_type = Keyword.get(meta, :import_type, :import)
    source = Keyword.get(meta, :source, "Unknown")
    elixir_meta = Keyword.get(meta, :original_meta, extract_elixir_meta(meta))

    # Build module alias from source name
    module_ast = name_to_alias(source)

    {{import_type, elixir_meta, [module_ast]}, acc}
  end

  # ----- Catch-all -----

  defp transform_node(type, meta, children, _acc) do
    throw({:unsupported, "Unsupported MetaAST construct: #{inspect({type, meta, children})}"})
  end

  # ----- Bitstring Segment Helpers -----

  # Build the Elixir specifier AST for a single bin_segment.
  # Returns nil when no specifier was supplied (the bare value is used
  # directly as a segment). Otherwise builds a `-` chain, e.g.
  # `integer-big-size(8)-unit(1)`.
  defp build_bin_segment_spec(meta, acc) do
    type = Keyword.get(meta, :type)
    sign = Keyword.get(meta, :signedness)
    endian = Keyword.get(meta, :endianness)
    size_ast = Keyword.get(meta, :size)
    unit = Keyword.get(meta, :unit)

    parts =
      []
      |> prepend_if(type, fn t -> {t, [], nil} end)
      |> prepend_if(sign, fn s -> {s, [], nil} end)
      |> prepend_if(endian, fn e -> {e, [], nil} end)
      |> Enum.reverse()

    parts =
      case size_ast do
        nil ->
          parts

        ast ->
          {:ok, size_ex} = __MODULE__.transform(ast, acc)
          parts ++ [{:size, [], [size_ex]}]
      end

    parts =
      case unit do
        nil -> parts
        n when is_integer(n) -> parts ++ [{:unit, [], [n]}]
      end

    join_bin_specifiers(parts)
  end

  defp prepend_if(list, nil, _fun), do: list
  defp prepend_if(list, value, fun), do: [fun.(value) | list]

  defp join_bin_specifiers([]), do: nil
  defp join_bin_specifiers([single]), do: single

  defp join_bin_specifiers([first | rest]) do
    Enum.reduce(rest, first, fn next, acc -> {:-, [], [acc, next]} end)
  end

  # ----- Lambda Helpers -----

  # Reconstruct & capture syntax from lambda metadata
  defp reconstruct_capture(meta, body, elixir_meta, acc) do
    capture_form = Keyword.get(meta, :capture_form)

    case capture_form do
      :named_function ->
        case body do
          [{:function_call, func_meta, _args}] ->
            func_name = Keyword.get(func_meta, :name, "unknown")
            arity = Keyword.get(meta, :arity, length(Keyword.get(meta, :params, [])))
            func_ref = build_capture_func_ref(func_name)
            {{:&, elixir_meta, [{:/, [], [func_ref, arity]}]}, acc}

          _ ->
            build_fn_fallback(meta, body, elixir_meta, acc)
        end

      :argument_reference ->
        {{:&, elixir_meta, [1]}, acc}

      :expression ->
        arity = Keyword.get(meta, :arity, length(Keyword.get(meta, :params, [])))
        capture_body = rebuild_capture_body(body, arity)
        {{:&, elixir_meta, [capture_body]}, acc}

      _ ->
        build_fn_fallback(meta, body, elixir_meta, acc)
    end
  end

  defp build_capture_func_ref(func_name) do
    case String.split(func_name, ".") do
      [single] ->
        {String.to_atom(single), [], nil}

      parts ->
        {func, module_parts} = List.pop_at(parts, -1)
        module_ast = build_module_alias(module_parts)
        {{:., [], [module_ast, String.to_atom(func)]}, [], []}
    end
  end

  defp rebuild_capture_body(body, arity) do
    substitution = for i <- 1..arity//1, into: %{}, do: {"arg_#{i}", i}

    body_ex =
      case body do
        [single] -> single
        multiple -> {:__block__, [], multiple}
      end

    substitute_capture_args(body_ex, substitution)
  end

  defp substitute_capture_args({var_atom, meta, nil} = ast, subs) when is_atom(var_atom) do
    name = Atom.to_string(var_atom)

    case Map.get(subs, name) do
      nil -> ast
      n -> {:&, meta, [n]}
    end
  end

  defp substitute_capture_args({form, meta, args}, subs) when is_list(args) do
    {form, meta, Enum.map(args, &substitute_capture_args(&1, subs))}
  end

  defp substitute_capture_args(other, _subs), do: other

  defp build_fn_fallback(meta, body, elixir_meta, acc) do
    params = Keyword.get(meta, :params, [])

    params_ex =
      Enum.map(params, fn
        {:param, _, name} when is_binary(name) -> {String.to_atom(name), [], nil}
        name when is_binary(name) -> {String.to_atom(name), [], nil}
        other -> other
      end)

    body_ex =
      case body do
        [single] -> single
        multiple -> {:__block__, [], multiple}
      end

    clause = {:->, [], [params_ex, body_ex]}
    {{:fn, elixir_meta, [clause]}, acc}
  end

  # ----- Exception Handling Helpers -----

  # Split exception handler children into clause handlers and optional after block.
  # After bottom-up traversal, match_arm nodes become {:->, ...} clauses.
  # The after block (if present) is the last element and is NOT a clause.
  defp split_exception_handlers([]), do: {[], nil}

  defp split_exception_handlers(rest) do
    {clauses, tail} =
      Enum.split_while(rest, fn
        {:->, _, _} -> true
        _ -> false
      end)

    case tail do
      [after_block] -> {clauses, after_block}
      [] -> {clauses, nil}
      _ -> {clauses, {:__block__, [], tail}}
    end
  end

  # ----- Cond Reconstruction Helpers -----

  # Collect cond clauses from nested conditional chain.
  # After bottom-up traversal, inner conditionals are already transformed
  # to {:if, ...} Elixir AST. We need to handle both MetaAST and Elixir forms.
  defp collect_cond_clauses(condition, then_branch, else_branch) do
    clause = {:->, [], [[condition], then_branch]}

    case else_branch do
      # MetaAST conditional (shouldn't normally happen after traversal, but handle)
      {:conditional, _meta, [next_cond, next_then, next_else]} ->
        [clause | collect_cond_clauses(next_cond, next_then, next_else)]

      # Already-transformed Elixir {:if, meta, [condition, [do: then, else: else]]}
      {:if, _meta, [next_cond, kw_clauses]} when is_list(kw_clauses) ->
        next_then = Keyword.get(kw_clauses, :do)
        next_else = Keyword.get(kw_clauses, :else)
        [clause | collect_cond_clauses(next_cond, next_then, next_else)]

      nil ->
        [clause]

      _ ->
        [clause]
    end
  end

  # ----- With Reconstruction Helpers -----

  # Reconstruct a with expression from a block of statements.
  # After bottom-up traversal, inline_match nodes with :with_clause
  # are already transformed to {:<-, meta, [pattern, expr]}.
  # The remaining statements form the body.
  defp reconstruct_with(statements, elixir_meta, acc) do
    # Split: `<-` clauses are with clauses, everything after is body
    {with_clauses, body_stmts} =
      Enum.split_while(statements, fn
        {:<-, _meta, _args} -> true
        _ -> false
      end)

    body =
      case body_stmts do
        [] -> nil
        [single] -> single
        multiple -> {:__block__, [], multiple}
      end

    with_args = with_clauses ++ [[do: body]]
    {{:with, elixir_meta, with_args}, acc}
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
