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

  ## Context Threading (M1 Metadata Enrichment)

  The adapter now threads contextual information through the transformation,
  attaching module name, function name, arity, and visibility to each node's
  location metadata. This enables rich context-aware analysis while maintaining
  M2 abstraction.

  Context structure:

      %{
        language: :elixir,
        module: "MyApp.UserController",
        function: "create",
        arity: 2,
        visibility: :public
      }

  This enables high-fidelity round-trips (M1 → M2 → M1).
  """

  alias Metastatic.AST

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
  # Note: List literals don't have metadata in Elixir AST, so no location added
  def transform(list) when is_list(list) do
    # Lists in Elixir can be literal lists like [1, 2, 3]
    with {:ok, items_meta} <- transform_list(list) do
      {:ok, {:list, items_meta}, %{}}
    end
  end

  # Map literals - M2.1 Core Layer
  def transform({:%{}, _meta, [{:|, _bar_meta, [map_name, pairs]}]}) when is_list(pairs) do
    reshaped =
      quote do: Enum.reduce(pairs, unquote(map_name), fn {k, v}, acc -> Map.put(acc, k, v) end)

    transform(reshaped)
  end

  def transform({:%{}, meta, pairs}) when is_list(pairs) do
    # Map literal: %{key => value, ...}
    with {:ok, pairs_meta} <- transform_map_pairs(pairs) do
      ast = {:map, pairs_meta}
      {:ok, add_location(ast, meta), %{}}
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

  # Module aliases: User, MyApp.User, etc.
  def transform({:__aliases__, meta, parts}) when is_list(parts) do
    # __aliases__ represents module names like User, MyApp.User
    # Treat as a variable reference to the module
    module_name = module_to_string({:__aliases__, meta, parts})
    {:ok, {:variable, module_name}, %{}}
  end

  def transform({var, meta, context}) when is_atom(var) and is_atom(context) do
    # Variable reference
    # Check if it's a special form or actual variable
    var_str = Atom.to_string(var)

    if special_form?(var) do
      # This is a special form or keyword, treat differently
      ast = {:literal, :symbol, var}
      {:ok, add_location(ast, meta), %{elixir_meta: meta}}
    else
      # Regular variable
      ast = {:variable, var_str}
      metadata = %{context: context}
      metadata = if meta != [], do: Map.put(metadata, :elixir_meta, meta), else: metadata
      {:ok, add_location(ast, meta), metadata}
    end
  end

  # Binary Operators - M2.1 Core Layer

  # Arithmetic operators
  def transform({op, meta, [left, right]}) when op in [:+, :-, :*, :/, :rem, :div] do
    with {:ok, left_meta, _} <- transform(left),
         {:ok, right_meta, _} <- transform(right) do
      ast = {:binary_op, :arithmetic, op, left_meta, right_meta}
      {:ok, add_location(ast, meta), %{}}
    end
  end

  # Comparison operators
  def transform({op, meta, [left, right]})
      when op in [:==, :!=, :<, :>, :<=, :>=, :===, :!==] do
    with {:ok, left_meta, _} <- transform(left),
         {:ok, right_meta, _} <- transform(right) do
      ast = {:binary_op, :comparison, op, left_meta, right_meta}
      {:ok, add_location(ast, meta), %{}}
    end
  end

  # Boolean operators
  def transform({op, meta, [left, right]}) when op in [:and, :or] do
    with {:ok, left_meta, _} <- transform(left),
         {:ok, right_meta, _} <- transform(right) do
      ast = {:binary_op, :boolean, op, left_meta, right_meta}
      {:ok, add_location(ast, meta), %{}}
    end
  end

  # String concatenation
  def transform({:<>, meta, [left, right]}) do
    with {:ok, left_meta, _} <- transform(left),
         {:ok, right_meta, _} <- transform(right) do
      ast = {:binary_op, :arithmetic, :<>, left_meta, right_meta}
      {:ok, add_location(ast, meta), %{}}
    end
  end

  # Pipe operator - M2.3 Native Layer
  # [TODO] UNPIPE it!
  # ast |> Enum.reduce(fn {{fun, meta, args}, 0}, {value, 0} -> {{fun, meta, [value | args]}, 0} end)
  def transform({:|>, _meta, [left, {_fun, _fun_meta, _args} = right]}) do
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

  def transform({:not, meta, [operand]}) do
    with {:ok, operand_meta, _} <- transform(operand) do
      ast = {:unary_op, :boolean, :not, operand_meta}
      {:ok, add_location(ast, meta), %{}}
    end
  end

  def transform({:-, meta, [operand]}) do
    with {:ok, operand_meta, _} <- transform(operand) do
      ast = {:unary_op, :arithmetic, :-, operand_meta}
      {:ok, add_location(ast, meta), %{}}
    end
  end

  def transform({:+, meta, [operand]}) do
    with {:ok, operand_meta, _} <- transform(operand) do
      ast = {:unary_op, :arithmetic, :+, operand_meta}
      {:ok, add_location(ast, meta), %{}}
    end
  end

  # Module Definitions - M2.2s Structural Layer

  # defmodule - maps to container
  def transform({:defmodule, meta, [name, [do: body]]}) do
    with {:ok, body_meta, _} <- transform(body) do
      module_name = module_to_string(name)

      # Add module context to the container node itself, not its children
      module_context = %{
        language: :elixir,
        module: module_name
      }

      # Use container type for module
      # Format: {:container, type, name, parent, type_params, implements, body}
      container = {:container, :module, module_name, nil, [], [], body_meta}

      {:ok, add_location_with_context(container, meta, module_context),
       %{elixir_meta: meta, original_name: name}}
    end
  end

  # def / defp (function definitions) - maps to function_def
  def transform({func_type, meta, [signature, [do: body]]})
      when func_type in [:def, :defp, :defmacro, :defmacrop] do
    with {:ok, body_meta, _} <- transform(body) do
      func_name = extract_function_name(signature)
      params = extract_function_params(signature)
      arity = length(params)
      visibility = if func_type in [:defp, :defmacrop], do: :private, else: :public

      # Add function context to the function_def node itself, not its children
      func_context = %{
        language: :elixir,
        function: func_name,
        arity: arity,
        visibility: visibility
      }

      # Use function_def type
      func_def =
        {:function_def, func_name, params, nil, %{visibility: visibility}, body_meta}

      {:ok, add_location_with_context(func_def, meta, func_context),
       %{elixir_meta: meta, function_type: func_type}}
    end
  end

  # Module attributes (@moduledoc, @doc, etc.)
  def transform({:@, meta, [{attr_name, attr_meta, [value]}]}) do
    # Transform the value so literals can be analyzed
    with {:ok, value_meta, _} <- transform(value) do
      # Use assignment to represent module attribute
      # @attr value becomes an assignment
      {:ok, {:assignment, {:variable, "@" <> Atom.to_string(attr_name)}, value_meta},
       %{elixir_meta: meta, attribute_meta: attr_meta, attribute_type: :module_attribute}}
    end
  end

  # Function Calls - M2.1 Core Layer

  # Function capture - M2.2 Extended Layer
  # Handles various forms:
  # &1, &2, etc. - argument references
  # &(&1 + 1) - anonymous function with capture
  # &Module.function/arity - named function capture
  # &function/arity - local function capture
  def transform({:&, meta, [body]}) do
    transform_function_capture(body, meta)
  end

  # Map field access
  def transform({{:., _, [{var, _var_meta, nil_or_empty}, field]}, _meta, []})
      when nil_or_empty in [nil, []] do
    {:ok, {:attribute_access, {:variable, var}, field}, %{kind: :map}}
  end

  # Anonymous function call
  # {{:., _fun_meta, [{fun_name, _fun_name_meta, _nil}]}, _meta, args}
  def transform({{:., _fun_meta, [{fun_name, _fun_name_meta, _nil}]}, _meta, args})
      when is_list(args) do
    with {:ok, args_meta} <- transform_list(args) do
      {:ok, {:function_call, fun_name, args_meta}, %{call_type: :local}}
    end
  end

  # Remote call (Module.function)
  # [TODO] This is simplified, better traverse is needed
  def transform(
        {{:., _outer_meta,
          [{{:., _inner_meta, [_inner_module, _inner_func]}, _, _inner_args} = inner, _fun_or_key]},
         _, _outer_args} = whole
      ) do
    require Logger
    Logger.notice("Incomplete transform: " <> inspect(whole))
    transform(inner)
  end

  def transform(
        {{:., _call_meta, [{:@, _inner_meta, [_inner_arg]}, _func]} = inner, _outer_meta,
         _outer_args} = whole
      ) do
    require Logger
    Logger.notice("Incomplete transform: " <> inspect(whole))
    transform(inner)
  end

  def transform({{:., _call_meta, [module, func]}, _meta, args}) when is_list(args) do
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

      # try/rescue/catch
      {:try, _} ->
        transform_try(args)

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

  # unquote(:"coerce_#{key}")(value)
  # [TODO] handle this somehow
  def transform({{:unquote, _unquote_meta, _quoted_content}, _meta, _args} = unexpected) do
    require Logger
    Logger.notice("Unsupported unquote: " <> inspect(unexpected))
    {:ok, [], %{}}
  end

  # Catch-all for unsupported constructs
  def transform(unsupported) do
    {:error, "Unsupported Elixir AST construct: #{inspect(unsupported)}"}
  end

  # Conditionals - M2.1 Core Layer

  # Standalone if: if condition do ... end
  defp transform_if([condition, clauses]) do
    then_clause = Keyword.get(clauses, :do)
    else_clause = Keyword.get(clauses, :else)

    with {:ok, cond_meta, _} <- transform(condition),
         {:ok, then_meta, _} <- transform(then_clause),
         {:ok, else_meta, _} <- transform_or_nil(else_clause) do
      {:ok, {:conditional, cond_meta, then_meta, else_meta}, %{}}
    end
  end

  # Piped if: expr |> if do ... end
  # The condition comes from the pipe, so args only contains the clauses
  defp transform_if([clauses]) do
    # The condition is implicit from the pipe - mark as language-specific for now
    {:ok, {:language_specific, :elixir, {:if, [], [clauses]}, "piped if expression"}, %{}}
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
    # Extract the clause list from [do: [clauses]]
    clause_list = Keyword.get(clauses, :do, [])

    with {:ok, meta_ast} <- cond_to_nested_if(clause_list) do
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
      {:ok, {:language_specific, :elixir, {:case, [], [clauses]}, "piped case expression"}, %{}}
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
    # Handle special forms like __MODULE__ in alias paths
    parts_strings =
      Enum.map(parts, fn
        atom when is_atom(atom) -> Atom.to_string(atom)
        {:__MODULE__, _, _} -> "__MODULE__"
        other -> inspect(other)
      end)

    Enum.join(parts_strings, ".")
  end

  defp module_to_string(atom) when is_atom(atom), do: Atom.to_string(atom)
  # Handle variable or dynamic module reference (e.g., {:module, meta, nil})
  defp module_to_string({name, _meta, context}) when is_atom(name) and is_atom(context) do
    Atom.to_string(name)
  end

  # Fallback for complex expressions (function calls, etc.) - return inspected form
  defp module_to_string(expr), do: inspect(expr)

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

  defp transform_case_arms([_ | _] = clauses) do
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

  # [TODO] this is a stub, needs better handling
  defp transform_case_arms(_clauses), do: {:ok, []}

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
      # Extract guard if present
      {params_list, guard} = extract_guard_from_params(params)

      with {:ok, params_meta} <- transform_fn_params(params_list),
           {:ok, guard_meta} <- transform_guard(guard),
           {:ok, body_meta, _} <- transform(body) do
        # Create lambda - use match_arm if guard present
        lambda =
          if guard_meta do
            # Lambda clause with guard
            # Pattern is just the params as a tuple or single param
            pattern =
              case params_meta do
                [single] -> single
                multiple -> {:tuple, multiple}
              end

            {:match_arm, pattern, guard_meta, body_meta}
          else
            # Simple lambda without guard - use 3-tuple with empty captures
            {:lambda, params_meta, [], body_meta}
          end

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

  defp extract_guard_from_params(params) do
    # Check if any parameter has a guard (when clause)
    # In Elixir AST: fn x when is_integer(x) -> ... end
    # params is [{:when, _, [param, guard_expr]}] or just [param1, param2, ...]
    case params do
      [{:when, _, params_part_and_guard_expr}] ->
        {params, [guard_expr]} = Enum.split(params_part_and_guard_expr, -1)
        {params, guard_expr}

      _ ->
        # No guard
        {params, nil}
    end
  end

  defp transform_guard(nil), do: {:ok, nil}

  defp transform_guard(guard_expr) do
    case transform(guard_expr) do
      {:ok, guard_meta, _} -> {:ok, guard_meta}
      error -> error
    end
  end

  defp transform_fn_params(params) do
    params
    |> Enum.reduce_while({:ok, []}, fn param, {:ok, acc} ->
      case param do
        # guards
        # {key, %{} = map}, {into, path, errors} when not is_struct(map)
        {:when, _guard_meta, _} ->
          {params_list, _guard} = extract_guard_from_params(param)
          {:cont, {:ok, [transform_fn_params(params_list) | acc]}}

        # Simple variable: x, acc, etc.
        {name, _meta, context} when is_atom(name) and is_atom(context) ->
          {:cont, {:ok, [{:param, Atom.to_string(name), nil, nil} | acc]}}

        # Map match: %{} = map
        # {:=, [line: 231], [{:%{}, [line: 231], []}, {:map, [line: 231], nil}]}
        {:=, _meta, [{_pattern, _, pattern_context}, {match, _match_meta, _match_context}]}
        when is_list(pattern_context) ->
          {:cont, {:ok, [{:param, Atom.to_string(match), nil, nil} | acc]}}

        {:=, _meta, [{match, _match_meta, _match_context}, {_pattern, _, pattern_context}]}
        when is_list(pattern_context) ->
          {:cont, {:ok, [{:param, Atom.to_string(match), nil, nil} | acc]}}

        {:=, _meta, [{_pattern, _pattern_context}, {match, _match_meta, _match_context}]} ->
          {:cont, {:ok, [{:param, Atom.to_string(match), nil, nil} | acc]}}

        # Map pattern: %{key: value}, %{"key" => value}, etc.
        {:%{}, _, _fields} = map_pattern ->
          # Map patterns in params - preserve as pattern metadata
          {:cont, {:ok, [{:param, "_map_pattern", nil, %{pattern: map_pattern}} | acc]}}

        # Tuple pattern: {x, y}, {fun, arity}, etc.
        {:{}, _, _elements} = tuple_pattern ->
          # For tuple patterns, create a param with pattern metadata
          # The pattern will be preserved but we use a generic name
          {:cont, {:ok, [{:param, "_pattern", nil, %{pattern: tuple_pattern}} | acc]}}

        # Two-element tuple (special syntax) or match: `{x, y}` or `_ = %{}`
        {left, right} when not is_list(left) ->
          {:cont, {:ok, [{:param, "_pattern", nil, %{pattern: {left, right}}} | acc]}}

        # Match (reversed order)
        {left, right} when not is_list(right) ->
          {:cont, {:ok, [{:param, "_pattern", nil, %{pattern: {right, left}}} | acc]}}

        literal when is_number(literal) or is_atom(literal) or is_binary(literal) ->
          {:cont, transform(literal)}

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
          lambda = {:lambda, [{:param, var_name, nil, nil}], [], body_meta}
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

  # try/rescue/catch - M2.2 Extended Layer
  defp transform_try(args) do
    # try/rescue in Elixir: try do ... rescue ... end
    # args is [[do: try_block, rescue: rescue_clauses]]
    clauses = List.first(args, [])
    try_block = Keyword.get(clauses, :do)
    rescue_clauses = Keyword.get(clauses, :rescue, [])
    catch_clauses = Keyword.get(clauses, :catch, [])
    else_block = Keyword.get(clauses, :else)
    after_block = Keyword.get(clauses, :after)

    with {:ok, try_meta, _} <- transform(try_block),
         {:ok, catch_list} <- transform_rescue_clauses(rescue_clauses ++ catch_clauses),
         {:ok, else_meta, _} <- transform_or_nil(else_block) do
      # Transform to exception_handling node
      # Note: ignoring after_block for now as it doesn't fit MetaAST model
      {:ok, {:exception_handling, try_meta, catch_list, else_meta}, %{after: after_block}}
    end
  end

  defp transform_rescue_clauses(clauses) do
    clauses
    |> Enum.reduce_while({:ok, []}, fn clause, {:ok, acc} ->
      case clause do
        # Match on exception pattern: Exception -> body
        # or: _ -> body (catch-all)
        {:->, _, [[pattern], body]} ->
          with {:ok, pattern_meta, _} <- transform_pattern(pattern),
               {:ok, body_meta, _} <- transform(body) do
            # MetaAST spec requires 3-tuple: {exception_pattern, var, body}
            # In Elixir, the pattern IS the binding, so we use the pattern as both
            # For _ pattern, use :_ atom
            exception_type = extract_exception_type(pattern_meta)
            {:cont, {:ok, [{exception_type, pattern_meta, body_meta} | acc]}}
          else
            error -> {:halt, error}
          end

        _ ->
          {:halt, {:error, "Invalid rescue clause: #{inspect(clause)}"}}
      end
    end)
    |> case do
      {:ok, clauses} -> {:ok, Enum.reverse(clauses)}
      error -> error
    end
  end

  # Extract exception type from pattern
  # _ -> :_, Variable name -> :error, specific exception -> exception name
  defp extract_exception_type(:_), do: :_
  defp extract_exception_type({:variable, name}), do: String.to_atom(name)
  defp extract_exception_type(_), do: :error

  # Helper to extract function name from signature
  # Handle guarded functions: def foo(x) when guard -> body
  # The signature is {:when, _, [{:foo, _, args}, guard]}
  defp extract_function_name({:when, _, [{name, _, _args}, _guard]}) when is_atom(name) do
    Atom.to_string(name)
  end

  defp extract_function_name({name, _, _}) when is_atom(name), do: Atom.to_string(name)
  defp extract_function_name({name, _, _args}) when is_atom(name), do: Atom.to_string(name)
  defp extract_function_name(nil), do: "anonymous"
  defp extract_function_name(_), do: "unknown"

  # Helper to extract function parameters from signature
  defp extract_function_params({:when, _, [{_name, _, args}, _guard]}), do: params_to_meta(args)
  defp extract_function_params({_name, _, args}) when is_list(args), do: params_to_meta(args)
  defp extract_function_params({_name, _, nil}), do: []
  defp extract_function_params(_), do: []

  defp params_to_meta(nil), do: []
  defp params_to_meta([]), do: []

  defp params_to_meta(args) when is_list(args) do
    Enum.map(args, fn
      {name, _, _} when is_atom(name) -> {:param, Atom.to_string(name), nil, nil}
      _ -> {:param, "_", nil, nil}
    end)
  end

  # Helper to transform map key-value pairs
  defp transform_map_pairs(pairs) do
    pairs
    |> Enum.reduce_while({:ok, []}, fn pair, {:ok, acc} ->
      case pair do
        {key, value} ->
          with {:ok, key_meta, _} <- transform(key),
               {:ok, value_meta, _} <- transform(value) do
            {:cont, {:ok, [{key_meta, value_meta} | acc]}}
          else
            error -> {:halt, error}
          end

        unexpected ->
          require Logger
          Logger.notice("Unexpected map transform: " <> inspect(unexpected))
          {:cont, {:ok, acc}}
      end
    end)
    |> case do
      {:ok, pairs} -> {:ok, Enum.reverse(pairs)}
      error -> error
    end
  end

  # Helper to add location information to MetaAST nodes
  # Elixir AST metadata is a keyword list with :line key
  defp add_location(ast, metadata) when is_list(metadata) do
    case Keyword.get(metadata, :line) do
      nil -> ast
      line when is_integer(line) -> AST.with_location(ast, %{line: line, language: :elixir})
      _ -> ast
    end
  end

  defp add_location(ast, _), do: ast

  # Helper to add location and context metadata to MetaAST nodes
  defp add_location_with_context(ast, metadata, context)
       when is_list(metadata) and is_map(context) do
    line = Keyword.get(metadata, :line)

    loc = if line, do: Map.put(context, :line, line), else: context

    if map_size(loc) > 0 do
      AST.with_location(ast, loc)
    else
      ast
    end
  end

  defp add_location_with_context(ast, _metadata, context) when is_map(context) do
    if map_size(context) > 0 do
      AST.with_location(ast, context)
    else
      ast
    end
  end

  defp add_location_with_context(ast, metadata, _context), do: add_location(ast, metadata)

  # Function capture transformation
  # Converts &(...) syntax to equivalent anonymous functions

  # Simple argument reference: &1, &2, etc.
  defp transform_function_capture(n, _meta) when is_integer(n) do
    # &1 becomes fn arg_1 -> arg_1 end
    param_name = "arg_#{n}"
    param = {:param, param_name, nil, nil}
    body = {:variable, param_name}
    {:ok, {:lambda, [param], [], body}, %{capture_form: :argument_reference}}
  end

  # Named function capture: &Module.function/arity or &function/arity
  defp transform_function_capture({:/, _, [function_ref, arity]}, _meta)
       when is_integer(arity) do
    # Extract function name
    function_name =
      case function_ref do
        {{:., _, [module, func]}, _, []} ->
          # Remote function: &Module.function/arity
          module_name = module_to_string(module)
          func_name = Atom.to_string(func)
          "#{module_name}.#{func_name}"

        {func, _, _} when is_atom(func) ->
          # Local function: &function/arity
          Atom.to_string(func)

        _ ->
          "unknown"
      end

    # Create lambda with N parameters that calls the function
    params = for i <- 1..arity//1, do: {:param, "arg_#{i}", nil, nil}
    args = for i <- 1..arity//1, do: {:variable, "arg_#{i}"}
    body = {:function_call, function_name, args}

    {:ok, {:lambda, params, [], body}, %{capture_form: :named_function}}
  end

  # Complex capture: &(&1 + 1), &(&1 + &2), etc.
  defp transform_function_capture(body, _meta) do
    # Find all argument captures in the body
    arg_nums = find_capture_arguments(body)

    if Enum.empty?(arg_nums) do
      # No captures found - this might be an error or edge case
      # Just transform the body as-is and wrap in a zero-arity lambda
      with {:ok, body_meta, _} <- transform(body) do
        {:ok, {:lambda, [], [], body_meta}, %{capture_form: :no_arguments}}
      end
    else
      # Determine arity from maximum argument number
      arity = Enum.max(arg_nums)

      # Generate unique parameter names
      params = for i <- 1..arity, do: {:param, "arg_#{i}", nil, nil}

      # Transform body, replacing captures with parameter references
      with {:ok, body_meta, _} <- transform_capture_body(body, arity) do
        {:ok, {:lambda, params, [], body_meta}, %{capture_form: :expression, arity: arity}}
      end
    end
  end

  # Find all &N references in the capture body
  defp find_capture_arguments(ast) do
    find_capture_arguments(ast, MapSet.new())
  end

  defp find_capture_arguments({:&, _, [n]}, acc) when is_integer(n) do
    MapSet.put(acc, n)
  end

  defp find_capture_arguments({:&, _, [_body]}, acc) do
    # Nested capture - don't recurse into it
    acc
  end

  defp find_capture_arguments(tuple, acc) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.reduce(acc, &find_capture_arguments/2)
  end

  defp find_capture_arguments(list, acc) when is_list(list) do
    Enum.reduce(list, acc, &find_capture_arguments/2)
  end

  defp find_capture_arguments(_other, acc), do: acc

  # Transform the capture body, replacing &N with parameter variables
  defp transform_capture_body(ast, arity) do
    transformed_ast = replace_capture_args(ast, arity)
    transform(transformed_ast)
  end

  # Replace &N with variable references
  defp replace_capture_args({:&, meta, [n]}, _arity) when is_integer(n) do
    # Replace &1 with variable reference (use atom for variable name)
    {String.to_atom("arg_#{n}"), meta, nil}
  end

  defp replace_capture_args({:&, _, [_body]} = nested_capture, _arity) do
    # Nested capture - don't modify it, will be transformed later
    nested_capture
  end

  defp replace_capture_args(tuple, arity) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.map(&replace_capture_args(&1, arity))
    |> List.to_tuple()
  end

  defp replace_capture_args(list, arity) when is_list(list) do
    Enum.map(list, &replace_capture_args(&1, arity))
  end

  defp replace_capture_args(other, _arity), do: other
end
