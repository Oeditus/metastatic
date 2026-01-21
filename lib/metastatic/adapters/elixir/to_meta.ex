defmodule Metastatic.Adapters.Elixir.ToMeta do
  @moduledoc """
  Transform Elixir AST (M1) to MetaAST (M2).

  This module implements the abstraction function α_Elixir that lifts
  Elixir-specific AST structures to the meta-level representation.

  ## Transformation Strategy

  The transformation follows a pattern-matching approach, handling each
  Elixir AST construct and mapping it to the appropriate MetaAST node type.

  ### M2.1 (Core Layer)

  - Literals: integers, floats, strings, booleans, nil, atoms
  - Variables: single-identifier references
  - Binary operators: arithmetic, comparison, boolean
  - Unary operators: negation, logical not
  - Function calls
  - Conditionals: if/unless
  - Blocks: multiple sequential expressions
  - Early returns: (simulated via throw/catch in Elixir)

  ### M2.2 (Extended Layer)

  - Anonymous functions (fn)
  - Collection operations (Enum.map, filter, reduce)
  - Pattern matching (case)
  - List comprehensions (for)

  ### M2.3 (Native Layer)

  - Pipe operator (|>)
  - with expressions
  - Macros (quote/unquote)

  ## Metadata Preservation

  The transformation preserves M1-specific information in metadata:
  - `:line` - line number from original source
  - `:context` - variable context (Elixir, nil, module name)
  - `:elixir_meta` - original Elixir metadata keyword list

  This enables high-fidelity round-trips (M1 → M2 → M1).
  """

  @doc """
  Transform Elixir AST to MetaAST.

  Returns `{:ok, meta_ast, metadata}` on success or `{:error, reason}` on failure.

  ## Examples

      iex> transform(42)
      {:ok, {:literal, :integer, 42}, %{}}

      iex> transform({:x, [], Elixir})
      {:ok, {:variable, "x"}, %{context: Elixir}}

      iex> transform({:+, [], [{:x, [], Elixir}, 5]})
      {:ok, {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}}, %{}}
  """
  @spec transform(term()) :: {:ok, term(), map()} | {:error, String.t()}

  # Literals - M2.1 Core Layer

  def transform(value) when is_integer(value) do
    {:ok, {:literal, :integer, value}, %{}}
  end

  def transform(value) when is_float(value) do
    {:ok, {:literal, :float, value}, %{}}
  end

  def transform(value) when is_binary(value) do
    {:ok, {:literal, :string, value}, %{}}
  end

  def transform(true) do
    {:ok, {:literal, :boolean, true}, %{}}
  end

  def transform(false) do
    {:ok, {:literal, :boolean, false}, %{}}
  end

  def transform(nil) do
    {:ok, {:literal, :null, nil}, %{}}
  end

  def transform(atom) when is_atom(atom) and atom not in [true, false, nil] do
    # Atoms become symbols
    {:ok, {:literal, :symbol, atom}, %{}}
  end

  # List literals - M2.1 Core Layer
  def transform(list) when is_list(list) do
    # Lists in Elixir can be literal lists like [1, 2, 3]
    with {:ok, items_meta} <- transform_list(list) do
      {:ok, {:literal, :collection, items_meta}, %{collection_type: :list}}
    end
  end

  # Tuple literals - M2.1 Core Layer
  # Two-element tuple shorthand: {x, y}
  # Need to distinguish between actual tuples and Elixir AST nodes
  def transform({left, right}) do
    # Check if this is an Elixir AST node (has metadata and context)
    # AST nodes are 3-tuples: {atom, metadata, context}
    # So if left is a 2-tuple, it's likely a real tuple
    case {left, right, is_tuple(left), is_tuple(right)} do
      # Both are 3-element tuples (likely AST nodes) - this is a tuple of AST nodes
      {{_, _, _}, {_, _, _}, true, true} ->
        with {:ok, left_meta, _} <- transform(left),
             {:ok, right_meta, _} <- transform(right) do
          {:ok, {:tuple, [left_meta, right_meta]}, %{}}
        end

      # At least one is NOT a 3-tuple, so this is a literal tuple
      _ ->
        with {:ok, left_meta, _} <- transform(left),
             {:ok, right_meta, _} <- transform(right) do
          {:ok, {:tuple, [left_meta, right_meta]}, %{}}
        end
    end
  end

  # Three or more element tuple: {x, y, z, ...}
  def transform({:{}, _meta, elements}) when is_list(elements) do
    with {:ok, elements_meta} <- transform_list(elements) do
      {:ok, {:tuple, elements_meta}, %{}}
    end
  end

  # Variables - M2.1 Core Layer

  def transform({var, meta, context}) when is_atom(var) and is_atom(context) do
    # Variable reference
    # Check if it's a special form or actual variable
    var_str = Atom.to_string(var)

    if special_form?(var) do
      # This is a special form or keyword, treat differently
      {:ok, {:literal, :symbol, var}, %{elixir_meta: meta}}
    else
      # Regular variable
      metadata = %{context: context}
      metadata = if meta != [], do: Map.put(metadata, :elixir_meta, meta), else: metadata
      {:ok, {:variable, var_str}, metadata}
    end
  end

  # Binary Operators - M2.1 Core Layer

  # Arithmetic operators
  def transform({op, _meta, [left, right]}) when op in [:+, :-, :*, :/, :rem, :div] do
    with {:ok, left_meta, _} <- transform(left),
         {:ok, right_meta, _} <- transform(right) do
      {:ok, {:binary_op, :arithmetic, op, left_meta, right_meta}, %{}}
    end
  end

  # Comparison operators
  def transform({op, _meta, [left, right]})
      when op in [:==, :!=, :<, :>, :<=, :>=, :===, :!==] do
    with {:ok, left_meta, _} <- transform(left),
         {:ok, right_meta, _} <- transform(right) do
      {:ok, {:binary_op, :comparison, op, left_meta, right_meta}, %{}}
    end
  end

  # Boolean operators
  def transform({op, _meta, [left, right]}) when op in [:and, :or] do
    with {:ok, left_meta, _} <- transform(left),
         {:ok, right_meta, _} <- transform(right) do
      {:ok, {:binary_op, :boolean, op, left_meta, right_meta}, %{}}
    end
  end

  # String concatenation
  def transform({:<>, _meta, [left, right]}) do
    with {:ok, left_meta, _} <- transform(left),
         {:ok, right_meta, _} <- transform(right) do
      {:ok, {:binary_op, :arithmetic, :<>, left_meta, right_meta}, %{}}
    end
  end

  # Pipe operator - M2.3 Native Layer
  def transform({:|>, _meta, [left, right]}) do
    # Pipe is language-specific to Elixir/Erlang
    with {:ok, left_meta, _} <- transform(left),
         {:ok, right_meta, _} <- transform(right) do
      {:ok, {:language_specific, :elixir, {:|>, [], [left, right]}, :pipe},
       %{left: left_meta, right: right_meta}}
    end
  end

  # Match Operator (=) - M2.1 Core Layer
  # In Elixir, = is pattern matching, not assignment
  def transform({:=, meta, [left, right]}) do
    with {:ok, pattern_meta, pattern_metadata} <- transform_pattern(left),
         {:ok, value_meta, value_metadata} <- transform(right) do
      # Preserve Elixir metadata for round-trip fidelity
      metadata = %{
        elixir_meta: meta,
        pattern_metadata: pattern_metadata,
        value_metadata: value_metadata
      }

      {:ok, {:inline_match, pattern_meta, value_meta}, metadata}
    end
  end

  # Unary Operators - M2.1 Core Layer

  def transform({:not, _meta, [operand]}) do
    with {:ok, operand_meta, _} <- transform(operand) do
      {:ok, {:unary_op, :boolean, :not, operand_meta}, %{}}
    end
  end

  def transform({:-, _meta, [operand]}) do
    with {:ok, operand_meta, _} <- transform(operand) do
      {:ok, {:unary_op, :arithmetic, :-, operand_meta}, %{}}
    end
  end

  def transform({:+, _meta, [operand]}) do
    with {:ok, operand_meta, _} <- transform(operand) do
      {:ok, {:unary_op, :arithmetic, :+, operand_meta}, %{}}
    end
  end

  # Module Definitions - M2.3 Native Layer

  # defmodule
  def transform({:defmodule, meta, [name, [do: body]]}) do
    with {:ok, body_meta, _} <- transform(body) do
      module_name = module_to_string(name)

      {:ok,
       {:language_specific, :elixir, {:defmodule, meta, [name, [do: body]]}, :module_definition},
       %{module_name: module_name, body: body_meta}}
    end
  end

  # def / defp (function definitions)
  def transform({func_type, meta, [signature, [do: body]]})
      when func_type in [:def, :defp, :defmacro, :defmacrop] do
    with {:ok, body_meta, _} <- transform(body) do
      func_name = extract_function_name(signature)

      {:ok,
       {:language_specific, :elixir, {func_type, meta, [signature, [do: body]]},
        :function_definition},
       %{function_name: func_name, function_type: func_type, body: body_meta}}
    end
  end

  # Module attributes (@moduledoc, @doc, etc.)
  def transform({:@, meta, [{attr_name, attr_meta, [value]}]}) do
    {:ok,
     {:language_specific, :elixir, {:@, meta, [{attr_name, attr_meta, [value]}]},
      :module_attribute}, %{attribute: attr_name, value: value}}
  end

  # Function Calls - M2.1 Core Layer

  # Remote call (Module.function)
  def transform({{:., _, [module, func]}, _meta, args}) when is_list(args) do
    module_name = module_to_string(module)
    func_name = Atom.to_string(func)
    qualified_name = "#{module_name}.#{func_name}"

    # Check for Enum operations - M2.2 Extended Layer
    case {module_name, func_name, args} do
      {"Enum", "map", [collection, fun]} ->
        transform_enum_map(collection, fun)

      {"Enum", "filter", [collection, fun]} ->
        transform_enum_filter(collection, fun)

      {"Enum", "reduce", [collection, initial, fun]} ->
        transform_enum_reduce(collection, initial, fun)

      _ ->
        with {:ok, args_meta} <- transform_list(args) do
          {:ok, {:function_call, qualified_name, args_meta}, %{call_type: :remote}}
        end
    end
  end

  # Local call
  def transform({func, _meta, args}) when is_atom(func) and is_list(args) do
    func_name = Atom.to_string(func)

    # Check if this is actually a function call or a special form
    case {func, args} do
      # Anonymous functions
      {:fn, _} ->
        transform_fn({:fn, nil, args})

      # Conditionals
      {:if, _} ->
        transform_if(args)

      {:unless, _} ->
        transform_unless(args)

      {:cond, _} ->
        transform_cond(args)

      {:case, _} ->
        transform_case(args)

      # Comprehensions
      {:for, _} ->
        transform_comprehension(args)

      # with expressions
      {:with, _} ->
        transform_with(args)

      # Blocks
      {:__block__, _} ->
        transform_block(args)

      # Regular function call
      _ ->
        with {:ok, args_meta} <- transform_list(args) do
          {:ok, {:function_call, func_name, args_meta}, %{}}
        end
    end
  end

  # Anonymous Functions - M2.2 Extended Layer

  def transform({:fn, meta, clauses}) do
    transform_fn({:fn, meta, clauses})
  end

  # Catch-all for unsupported constructs
  def transform(unsupported) do
    {:error, "Unsupported Elixir AST construct: #{inspect(unsupported)}"}
  end

  # Conditionals - M2.1 Core Layer

  defp transform_if([condition, clauses]) do
    then_clause = Keyword.get(clauses, :do)
    else_clause = Keyword.get(clauses, :else)

    with {:ok, cond_meta, _} <- transform(condition),
         {:ok, then_meta, _} <- transform(then_clause),
         {:ok, else_meta, _} <- transform_or_nil(else_clause) do
      {:ok, {:conditional, cond_meta, then_meta, else_meta}, %{}}
    end
  end

  defp transform_unless([condition, clauses]) do
    then_clause = Keyword.get(clauses, :do)
    else_clause = Keyword.get(clauses, :else)

    # unless is "if not"
    with {:ok, cond_meta, _} <- transform(condition),
         {:ok, then_meta, _} <- transform(then_clause),
         {:ok, else_meta, _} <- transform_or_nil(else_clause) do
      # Negate condition
      negated_cond = {:unary_op, :boolean, :not, cond_meta}
      {:ok, {:conditional, negated_cond, then_meta, else_meta}, %{original_form: :unless}}
    end
  end

  defp transform_cond([clauses]) do
    # cond is a series of condition -> body pairs
    # Transform to nested if/else
    with {:ok, meta_ast} <- cond_to_nested_if(clauses) do
      {:ok, meta_ast, %{original_form: :cond}}
    end
  end

  # Standalone case: case expr do ... end
  defp transform_case([scrutinee, clauses]) do
    # case expression with pattern matching
    case_clauses = Keyword.get(clauses, :do, [])

    with {:ok, scrutinee_meta, _} <- transform(scrutinee),
         {:ok, arms} <- transform_case_arms(case_clauses) do
      {:ok, {:pattern_match, scrutinee_meta, arms}, %{}}
    end
  end

  # Piped case: expr |> case do ... end
  # The scrutinee comes from the pipe, so args only contains the clauses
  defp transform_case([clauses]) do
    # The scrutinee is implicit from the pipe - we need to get it from context
    # For now, create a placeholder that indicates this needs pipe handling
    case_clauses = Keyword.get(clauses, :do, [])

    with {:ok, _arms} <- transform_case_arms(case_clauses) do
      # Mark this as needing the pipe argument
      {:ok,
       {:language_specific, :elixir, {:case, [], [clauses]}, "piped case expression"},
       %{}}
    end
  end

  # Blocks - M2.1 Core Layer

  defp transform_block(expressions) do
    with {:ok, exprs_meta} <- transform_list(expressions) do
      {:ok, {:block, exprs_meta}, %{}}
    end
  end

  # Helper Functions

  defp transform_list(items) when is_list(items) do
    items
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
      # Transform each item
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

  defp transform_or_nil(nil), do: {:ok, nil, %{}}
  defp transform_or_nil(value), do: transform(value)

  defp module_to_string({:__aliases__, _, parts}) do
    Enum.map_join(parts, ".", &Atom.to_string/1)
  end

  defp module_to_string(atom) when is_atom(atom) do
    Atom.to_string(atom)
  end

  defp special_form?(atom) do
    atom in [
      :__block__,
      :__aliases__,
      :__MODULE__,
      :__DIR__,
      :__ENV__,
      :__CALLER__,
      :__STACKTRACE__,
      :_,
      :^,
      :when
    ]
  end

  defp cond_to_nested_if([]) do
    # Empty cond - shouldn't happen but handle gracefully
    {:ok, {:literal, :null, nil}}
  end

  defp cond_to_nested_if([{:->, _, [[condition], body]} | rest]) do
    with {:ok, cond_meta, _} <- transform(condition),
         {:ok, body_meta, _} <- transform(body),
         {:ok, else_meta} <- cond_to_nested_if(rest) do
      {:ok, {:conditional, cond_meta, body_meta, else_meta}}
    end
  end

  defp cond_to_nested_if([_invalid | rest]) do
    # Skip invalid clauses and continue
    cond_to_nested_if(rest)
  end

  defp transform_case_arms(clauses) do
    clauses
    |> Enum.reduce_while({:ok, []}, fn {:->, _, [[pattern], body]}, {:ok, acc} ->
      with {:ok, pattern_meta, _} <- transform_pattern(pattern),
           {:ok, body_meta, _} <- transform(body) do
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

  defp transform_pattern(pattern) do
    # Pattern matching patterns - similar to regular transforms but allow wildcards
    case pattern do
      # Wildcard pattern
      {:_, _, _} ->
        {:ok, :_, %{}}

      # Pin operator: ^variable
      {:^, meta, [var]} ->
        with {:ok, var_meta, var_metadata} <- transform(var) do
          {:ok, {:pin, var_meta}, Map.merge(%{elixir_meta: meta}, var_metadata)}
        end

      # Tuple pattern: {x, y, z}
      {:{}, _meta, elements} ->
        with {:ok, elements_meta} <- transform_pattern_list(elements) do
          {:ok, {:tuple, elements_meta}, %{}}
        end

      # Two-element tuple shorthand: {x, y}
      {left, right} when not is_atom(left) or not is_atom(right) ->
        with {:ok, left_meta, _} <- transform_pattern(left),
             {:ok, right_meta, _} <- transform_pattern(right) do
          {:ok, {:tuple, [left_meta, right_meta]}, %{}}
        end

      # List pattern: [h | t] or [1, 2, 3]
      [_ | _] = list ->
        transform_list_pattern(list)

      [] ->
        {:ok, {:literal, :collection, []}, %{collection_type: :list}}

      # Variable or literal
      _ ->
        transform(pattern)
    end
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

  defp transform_list_pattern(list) do
    # Check if it's a cons pattern [head | tail]
    case list do
      [head | tail] when is_list(tail) and tail != [] ->
        # Check if tail is a single variable (cons pattern)
        case tail do
          [{var, _, context}] when is_atom(var) and is_atom(context) ->
            # This is [head | tail] pattern
            with {:ok, head_meta, _} <- transform_pattern(head),
                 {:ok, tail_meta, _} <- transform_pattern({var, [], context}) do
              {:ok, {:cons_pattern, head_meta, tail_meta}, %{}}
            end

          _ ->
            # List with multiple elements - transform each
            with {:ok, elements_meta} <- transform_pattern_list(list) do
              {:ok, {:literal, :collection, elements_meta}, %{collection_type: :list}}
            end
        end

      [single] ->
        # Single element list
        with {:ok, element_meta, _} <- transform_pattern(single) do
          {:ok, {:literal, :collection, [element_meta]}, %{collection_type: :list}}
        end

      _ ->
        # Empty or literal list
        with {:ok, elements_meta} <- transform_pattern_list(list) do
          {:ok, {:literal, :collection, elements_meta}, %{collection_type: :list}}
        end
    end
  end

  defp transform_fn({:fn, _meta, clauses}) do
    # Anonymous function with one or more clauses
    with {:ok, transformed_clauses} <- transform_fn_clauses(clauses) do
      # For single clause, return simple lambda
      # For multiple clauses, return pattern_match lambda
      case transformed_clauses do
        [single_clause] ->
          {:ok, single_clause, %{}}

        multiple_clauses ->
          {:ok, {:language_specific, :elixir, {:fn, nil, clauses}, :multi_clause_fn},
           %{clauses: multiple_clauses}}
      end
    end
  end

  defp transform_fn_clauses(clauses) do
    clauses
    |> Enum.reduce_while({:ok, []}, fn {:->, _, [params, body]}, {:ok, acc} ->
      with {:ok, params_meta} <- transform_fn_params(params),
           {:ok, body_meta, _} <- transform(body) do
        lambda = {:lambda, params_meta, body_meta}
        {:cont, {:ok, [lambda | acc]}}
      else
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, clauses} -> {:ok, Enum.reverse(clauses)}
      error -> error
    end
  end

  defp transform_fn_params(params) do
    params
    |> Enum.reduce_while({:ok, []}, fn param, {:ok, acc} ->
      case param do
        # Simple variable: x, acc, etc.
        {name, _, context} when is_atom(name) and is_atom(context) ->
          {:cont, {:ok, [{:param, Atom.to_string(name), nil, nil} | acc]}}

        # Tuple pattern: {x, y}, {fun, arity}, etc.
        {:{}, _, _elements} = tuple_pattern ->
          # For tuple patterns, create a param with pattern metadata
          # The pattern will be preserved but we use a generic name
          {:cont, {:ok, [{:param, "_pattern", nil, %{pattern: tuple_pattern}} | acc]}}

        # Two-element tuple (special syntax): {x, y}
        {left, right} when not is_list(left) and not is_list(right) ->
          # Two-element tuple pattern
          {:cont, {:ok, [{:param, "_pattern", nil, %{pattern: {left, right}}} | acc]}}

        _ ->
          {:halt, {:error, "Unsupported parameter pattern: #{inspect(param)}"}}
      end
    end)
    |> case do
      {:ok, params} -> {:ok, Enum.reverse(params)}
      error -> error
    end
  end

  # Comprehensions - M2.2 Extended Layer

  defp transform_comprehension(args) do
    # for comprehension: for x <- collection, do: expr
    # Extract generators and body
    {generators, opts} = extract_comprehension_parts(args)
    body = Keyword.get(opts, :do)

    case generators do
      [{:<-, _, [var, collection]}] ->
        # Simple map-like comprehension
        with {:ok, var_name} <- extract_var_name(var),
             {:ok, collection_meta, _} <- transform(collection),
             {:ok, body_meta, _} <- transform(body) do
          # Build lambda for the body
          lambda = {:lambda, [{:param, var_name, nil, nil}], body_meta}
          {:ok, {:collection_op, :map, lambda, collection_meta}, %{original_form: :comprehension}}
        end

      _ ->
        # Complex comprehension - use language_specific
        {:ok, {:language_specific, :elixir, {:for, nil, args}, :comprehension}, %{}}
    end
  end

  defp extract_comprehension_parts(args) do
    # Separate generators from options
    {generators, _rest} =
      Enum.split_while(args, fn
        {:<-, _, _} -> true
        _ -> false
      end)

    opts =
      List.last(args)
      |> case do
        opts when is_list(opts) -> opts
        _ -> []
      end

    {generators, opts}
  end

  defp extract_var_name({var, _, _}) when is_atom(var) do
    {:ok, Atom.to_string(var)}
  end

  defp extract_var_name(_), do: {:error, "Complex pattern not supported"}

  # Enum Operations - M2.2 Extended Layer

  defp transform_enum_map(collection, fun) do
    with {:ok, collection_meta, _} <- transform(collection),
         {:ok, fun_meta, _} <- transform(fun) do
      {:ok, {:collection_op, :map, fun_meta, collection_meta}, %{}}
    end
  end

  defp transform_enum_filter(collection, fun) do
    with {:ok, collection_meta, _} <- transform(collection),
         {:ok, fun_meta, _} <- transform(fun) do
      {:ok, {:collection_op, :filter, fun_meta, collection_meta}, %{}}
    end
  end

  defp transform_enum_reduce(collection, initial, fun) do
    with {:ok, collection_meta, _} <- transform(collection),
         {:ok, initial_meta, _} <- transform(initial),
         {:ok, fun_meta, _} <- transform(fun) do
      {:ok, {:collection_op, :reduce, fun_meta, collection_meta, initial_meta}, %{}}
    end
  end

  # with expressions - M2.3 Native Layer

  defp transform_with(args) do
    # with is complex and Elixir-specific - preserve as language_specific
    {:ok, {:language_specific, :elixir, {:with, nil, args}, :with}, %{}}
  end

  # Helper to extract function name from signature
  defp extract_function_name({name, _, _}) when is_atom(name), do: Atom.to_string(name)
  defp extract_function_name({name, _, _args}) when is_atom(name), do: Atom.to_string(name)
  defp extract_function_name(nil), do: "anonymous"
  defp extract_function_name(_), do: "unknown"
end
