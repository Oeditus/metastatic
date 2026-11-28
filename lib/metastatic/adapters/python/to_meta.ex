defmodule Metastatic.Adapters.Python.ToMeta do
  @moduledoc """
  Transform Python AST (M1) to MetaAST (M2).

  Implements the abstraction function α_Python that lifts Python-specific
  AST structures to the meta-level representation.

  ## Transformation Strategy

  Python's AST is represented as nested maps with "_type" keys. We pattern
  match on these structures and transform them to MetaAST tuples.

  ### M2.1 (Core Layer)

  - Literals: Constant nodes → {:literal, type, value}
  - Variables: Name nodes → {:variable, name}
  - Binary operators: BinOp → {:binary_op, category, op, left, right}
  - Unary operators: UnaryOp → {:unary_op, category, op, operand}
  - Function calls: Call → {:function_call, name, args}
  - Conditionals: If, IfExp → {:conditional, condition, then, else}
  - Blocks: Module, multiple statements → {:block, statements}
  - Early returns: Return, Break, Continue → {:early_return, kind, value}

  ### M2.2 (Extended Layer)

  - Loops: While → {:loop, :while, condition, body}
  - Loops: For → {:loop, :for_each, iterator, collection, body}
  - Lambdas: Lambda → {:lambda, params, captures, body}
  - Collection ops: Simple ListComp → {:collection_op, :map, lambda, collection}
  - Exception handling: Try → {:exception_handling, try_block, rescue_clauses, finally_block}

  ## Metadata Preservation

  The transformation preserves Python-specific information:
  - `:lineno` - line number
  - `:col_offset` - column offset
  - `:python_node_type` - original Python AST node type

  This enables high-fidelity round-trips (M1 → M2 → M1).
  """

  alias Metastatic.AST

  @doc """
  Transform Python AST to MetaAST.

  Returns `{:ok, meta_ast, metadata}` on success or `{:error, reason}` on failure.

  ## New 3-Tuple Format

  All MetaAST nodes are uniform 3-element tuples:

      {type_atom, keyword_meta, children_or_value}

  ## Examples

      iex> transform(%{"_type" => "Constant", "value" => 42})
      {:ok, {:literal, [subtype: :integer], 42}, %{}}

      iex> transform(%{"_type" => "Name", "id" => "x"})
      {:ok, {:variable, [scope: :local], "x"}, %{}}

      iex> transform(%{"_type" => "BinOp", "op" => %{"_type" => "Add"}, ...})
      {:ok, {:binary_op, [category: :arithmetic, operator: :+], [left, right]}, %{}}
  """
  @spec transform(map()) :: {:ok, term(), map()} | {:error, String.t()}

  # Module - top-level container
  #
  # A leading bare string statement is the module docstring. It is kept in the
  # body and recorded in `:docstring`, because a lone string statement is
  # indistinguishable from an expression statement once reified — a module
  # docstring used to reify as a stray string expression before `import ast`.
  def transform(%{"_type" => "Module", "body" => body} = node) do
    with {:ok, statements} <- transform_list(body) do
      meta = docstring_meta(body)

      case statements do
        [] -> {:ok, add_location({:block, meta, []}, node), %{}}
        [single] -> {:ok, single, %{}}
        multiple -> {:ok, add_location({:block, meta, multiple}, node), %{}}
      end
    end
  end

  # Expression statement - unwrap the value
  def transform(%{"_type" => "Expr", "value" => value}) do
    transform(value)
  end

  # Literals - M2.1 Core Layer

  # Values that JSON cannot carry are tagged by `parser.py` and decoded here.
  #
  # `bytes` becomes a `:bytes` literal (the M2 payload is the raw binary);
  # `Ellipsis` and complex numbers have no M2 literal subtype, so they are
  # preserved verbatim as `:language_specific` rather than failing the file.
  #
  # These clauses must precede the generic `Constant` clause below, which
  # would otherwise match the tagged maps first.
  def transform(%{"_type" => "Constant", "value" => %{"__bytes__" => encoded}} = node) do
    with {:ok, raw} <- Base.decode64(encoded) do
      {:ok, add_location({:literal, [subtype: :bytes], raw}, node), %{}}
    end
  end

  def transform(%{"_type" => "Constant", "value" => %{"__python_repr__" => repr}} = node) do
    hint = if repr == "Ellipsis", do: :ellipsis, else: :complex_literal
    {:ok, {:language_specific, [language: :python, hint: hint], node}, %{}}
  end

  # Constant node (Python 3.8+)
  #
  # `kind` records a string prefix (`u" "`, `r"\d"`). It is only present when
  # the source used one, and dropping it changes the AST, so it is carried as
  # `:string_kind`.
  def transform(%{"_type" => "Constant", "value" => value} = node) do
    literal = infer_literal_type(value)
    literal = put_string_kind(literal, Map.get(node, "kind"))
    {:ok, add_location(literal, node), %{}}
  end

  # Legacy literal nodes (Python 3.7 compatibility)
  def transform(%{"_type" => "Num", "n" => value} = node) when is_integer(value) do
    {:ok, add_location({:literal, [subtype: :integer], value}, node), %{}}
  end

  def transform(%{"_type" => "Num", "n" => value} = node) when is_float(value) do
    {:ok, add_location({:literal, [subtype: :float], value}, node), %{}}
  end

  def transform(%{"_type" => "Str", "s" => value} = node) do
    {:ok, add_location({:literal, [subtype: :string], value}, node), %{}}
  end

  def transform(%{"_type" => "NameConstant", "value" => true} = node) do
    {:ok, add_location({:literal, [subtype: :boolean], true}, node), %{}}
  end

  def transform(%{"_type" => "NameConstant", "value" => false} = node) do
    {:ok, add_location({:literal, [subtype: :boolean], false}, node), %{}}
  end

  def transform(%{"_type" => "NameConstant", "value" => nil} = node) do
    {:ok, add_location({:literal, [subtype: :null], nil}, node), %{}}
  end

  # Variables - M2.1 Core Layer

  def transform(%{"_type" => "Name", "id" => name} = node) do
    {:ok, add_location({:variable, [scope: :local], name}, node), %{}}
  end

  # Binary Operators - M2.1 Core Layer

  def transform(%{"_type" => "BinOp", "op" => op, "left" => left, "right" => right} = node) do
    with {:ok, op_meta} <- transform_binop(op),
         {:ok, left_meta, _} <- transform(left),
         {:ok, right_meta, _} <- transform(right) do
      {category, operator} = op_meta
      ast = {:binary_op, [category: category, operator: operator], [left_meta, right_meta]}
      {:ok, add_location(ast, node), %{}}
    end
  end

  # Comparison Operators - M2.1 Core Layer

  def transform(
        %{"_type" => "Compare", "left" => left, "ops" => [op], "comparators" => [right]} = node
      ) do
    with {:ok, op_meta} <- transform_compare_op(op),
         {:ok, left_meta, _} <- transform(left),
         {:ok, right_meta, _} <- transform(right) do
      ast = {:binary_op, [category: :comparison, operator: op_meta], [left_meta, right_meta]}
      {:ok, add_location(ast, node), %{}}
    end
  end

  # Multiple comparisons (a < b < c) - chain them
  def transform(%{
        "_type" => "Compare",
        "left" => left,
        "ops" => ops,
        "comparators" => comparators
      })
      when length(ops) > 1 do
    # For now, treat as language_specific
    native = %{"_type" => "Compare", "left" => left, "ops" => ops, "comparators" => comparators}
    {:ok, {:language_specific, [language: :python, hint: :chained_comparison], native}, %{}}
  end

  # Boolean Operators - M2.1 Core Layer

  def transform(%{"_type" => "BoolOp", "op" => op, "values" => [left, right]} = node) do
    with {:ok, op_meta} <- transform_bool_op(op),
         {:ok, left_meta, _} <- transform(left),
         {:ok, right_meta, _} <- transform(right) do
      ast = {:binary_op, [category: :boolean, operator: op_meta], [left_meta, right_meta]}
      {:ok, add_location(ast, node), %{}}
    end
  end

  # Multiple boolean operations - chain them
  #
  # `a and b and c` is n-ary in Python's AST but binary in M2, so it is
  # chained left-associatively: `(a and b) and c`. `FromMeta` flattens the
  # chain back into one n-ary `BoolOp`, which reproduces Python's own shape.
  #
  # The chain is marked `:chained` so `FromMeta` only flattens what this
  # clause built. Without the mark, a genuinely nested `a and (b and c)`
  # would be flattened too, changing the tree.
  def transform(%{"_type" => "BoolOp", "op" => op, "values" => values} = node)
      when length(values) > 2 do
    with {:ok, op_meta} <- transform_bool_op(op),
         {:ok, transformed_values} <- transform_list(values) do
      [first, second | rest] = transformed_values

      initial =
        {:binary_op, [category: :boolean, operator: op_meta, chained: true], [first, second]}

      result =
        Enum.reduce(rest, initial, fn value, acc ->
          {:binary_op, [category: :boolean, operator: op_meta, chained: true], [acc, value]}
        end)

      {:ok, add_location(result, node), %{}}
    end
  end

  # Unary Operators - M2.1 Core Layer

  def transform(%{"_type" => "UnaryOp", "op" => op, "operand" => operand} = node) do
    with {:ok, {category, operator}} <- transform_unary_op(op),
         {:ok, operand_meta, _} <- transform(operand) do
      ast = {:unary_op, [category: category, operator: operator], [operand_meta]}
      {:ok, add_location(ast, node), %{}}
    end
  end

  # Function Calls - M2.1 Core Layer
  #
  # Keyword arguments and unpacking are part of the call, not decoration:
  # dropping them silently rewrote `foo(1, x=2, **kw)` as `foo(1)`. They ride
  # along in metadata (as `:param` nodes, matching how `:function_def`
  # describes its parameters) so `FromMeta` can rebuild the exact call.
  #
  # A callee that is an *expression* (`f(x).decode()`, `a[0](y)`) has no
  # dotted name. It is carried in `:receiver` so the receiver is not lost —
  # reporting an empty name used to reify `base64.b64encode(v).decode()` as a
  # bare `.decode()`.
  def transform(%{"_type" => "Call", "func" => func, "args" => args} = node) do
    keywords = Map.get(node, "keywords") || []

    with {:ok, func_name, receiver} <- call_target(func),
         {:ok, args_meta} <- transform_list(args),
         {:ok, kwargs_meta} <- transform_call_keywords(keywords) do
      meta =
        [name: func_name] ++
          if(receiver, do: [receiver: receiver], else: []) ++
          if(kwargs_meta != [], do: [kwargs: kwargs_meta], else: [])

      ast = {:function_call, meta, args_meta}
      {:ok, add_location(ast, node), %{}}
    end
  end

  # Conditionals - M2.1 Core Layer

  # If statement
  #
  # `If` and `IfExp` share the `:conditional` node, so `FromMeta` cannot tell
  # them apart from the shape alone (an `if` whose branches are expressions
  # looks exactly like a ternary). `:statement` records which one this was so
  # a statement `if` reifies as `If` instead of an unparseable `IfExp`.
  def transform(%{"_type" => "If", "test" => test, "body" => body, "orelse" => orelse} = node) do
    with {:ok, test_meta, _} <- transform(test),
         {:ok, body_meta, _} <- transform_body(body),
         {:ok, else_meta, _} <- transform_body_or_nil(orelse) do
      ast = {:conditional, [statement: true], [test_meta, body_meta, else_meta]}
      {:ok, add_location(ast, node), %{}}
    end
  end

  # If expression (ternary)
  def transform(%{"_type" => "IfExp", "test" => test, "body" => body, "orelse" => orelse} = node) do
    with {:ok, test_meta, _} <- transform(test),
         {:ok, body_meta, _} <- transform(body),
         {:ok, else_meta, _} <- transform(orelse) do
      ast = {:conditional, [], [test_meta, body_meta, else_meta]}
      {:ok, add_location(ast, node), %{}}
    end
  end

  # Early Returns - M2.1 Core Layer

  def transform(%{"_type" => "Return", "value" => value} = node) do
    with {:ok, value_meta, _} <- transform_or_nil(value) do
      ast = {:early_return, [kind: :return], [value_meta]}
      {:ok, add_location(ast, node), %{}}
    end
  end

  def transform(%{"_type" => "Break"} = node) do
    {:ok, add_location({:early_return, [kind: :break], [nil]}, node), %{}}
  end

  def transform(%{"_type" => "Continue"} = node) do
    {:ok, add_location({:early_return, [kind: :continue], [nil]}, node), %{}}
  end

  # Assignment - M2.1 Core Layer
  # In Python, = is assignment (imperative binding/mutation)

  # Simple assignment: x = 5
  def transform(%{"_type" => "Assign", "targets" => [target], "value" => value} = node) do
    with {:ok, target_meta, target_metadata} <- transform(target),
         {:ok, value_meta, value_metadata} <- transform(value) do
      metadata = %{
        target_metadata: target_metadata,
        value_metadata: value_metadata
      }

      ast = {:assignment, [], [target_meta, value_meta]}
      {:ok, add_location(ast, node), metadata}
    end
  end

  # Multiple assignment: x = y = 5
  # Python allows chaining: a = b = c = 5
  # Transform to nested assignments: a = (b = (c = 5))
  def transform(%{"_type" => "Assign", "targets" => targets, "value" => value} = node)
      when length(targets) > 1 do
    with {:ok, value_meta, value_metadata} <- transform(value) do
      # Build nested assignments from right to left
      result =
        targets
        |> Enum.reverse()
        |> Enum.reduce({:ok, value_meta, value_metadata}, fn target, {:ok, current_value, _} ->
          with {:ok, target_meta, target_metadata} <- transform(target) do
            metadata = %{
              target_metadata: target_metadata,
              value_metadata: %{}
            }

            {:ok, add_location({:assignment, [], [target_meta, current_value]}, node), metadata}
          end
        end)

      result
    end
  end

  # Augmented assignment: x += 1, x *= 2, etc.
  # Now uses proper :augmented_assignment M2 type
  def transform(
        %{"_type" => "AugAssign", "target" => target, "op" => op, "value" => value} = node
      ) do
    with {:ok, target_meta, _} <- transform(target),
         {:ok, {category, operator}} <- transform_binop(op),
         {:ok, value_meta, _} <- transform(value) do
      {:ok,
       add_location(
         {:augmented_assignment, [category: category, operator: operator],
          [target_meta, value_meta]},
         node
       ), %{}}
    end
  end

  # Annotated assignment: x: int = 5 (Python 3.6+)
  # Ignore the annotation for now
  # `x: int = 1`. The annotation is kept in `:annotation` so the assignment
  # reifies as an `AnnAssign` again; without it the annotation was dropped and
  # `x: int = 1` came back as a plain `x = 1`.
  def transform(%{"_type" => "AnnAssign", "target" => target, "value" => value} = node)
      when not is_nil(value) do
    with {:ok, target_meta, target_metadata} <- transform(target),
         {:ok, value_meta, value_metadata} <- transform(value) do
      metadata = %{
        target_metadata: target_metadata,
        value_metadata: value_metadata
      }

      meta = annotation_meta(node)

      {:ok, add_location({:assignment, meta, [target_meta, value_meta]}, node), metadata}
    end
  end

  # Annotated assignment without value: x: int (declaration only)
  def transform(%{"_type" => "AnnAssign", "target" => _target, "value" => nil} = node) do
    # Type-only annotation, treat as language-specific
    {:ok, {:language_specific, [language: :python, hint: :type_annotation], node}, %{}}
  end

  # Lists - M2.1 Core Layer
  def transform(%{"_type" => "List", "elts" => elements} = node) do
    with {:ok, elements_meta} <- transform_list(elements) do
      ast = {:list, [], elements_meta}
      {:ok, add_location(ast, node), %{}}
    end
  end

  # Sets - M2.1 Core Layer
  #
  # A set literal has no dedicated M2 node; it is a collection whose
  # elements are unordered and unique. It is carried as a `:list` with
  # `:collection_type` metadata so `FromMeta` can restore the braces.
  def transform(%{"_type" => "Set", "elts" => elements} = node) do
    with {:ok, elements_meta} <- transform_list(elements) do
      ast = {:list, [collection_type: :set], elements_meta}
      {:ok, add_location(ast, node), %{}}
    end
  end

  # Dicts (Maps) - M2.1 Core Layer
  # `{**a, "b": 1}` has a `nil` key for the unpacked mapping; M2 `:map` has no
  # unpacking form, so the whole literal is preserved verbatim rather than
  # silently dropping the unpacked entries. Checked before transforming the
  # keys, since `transform_list/1` cannot transform a `nil` key.
  def transform(%{"_type" => "Dict", "keys" => keys} = node) when is_list(keys) do
    if Enum.any?(keys, &is_nil/1) do
      {:ok, {:language_specific, [language: :python, hint: :dict_unpacking], node}, %{}}
    else
      transform_dict(node)
    end
  end

  # Tuples - Used in patterns and values
  def transform(%{"_type" => "Tuple", "elts" => elements} = node) do
    with {:ok, elements_meta} <- transform_list(elements) do
      {:ok, add_location({:tuple, [], elements_meta}, node), %{}}
    end
  end

  # Loops - M2.2 Extended Layer

  # While loop
  #
  # Python's `while ... else:` runs the `else` block when the loop finishes
  # without `break`; `:orelse` carries it so it is not silently dropped.
  def transform(%{"_type" => "While", "test" => test, "body" => body} = node) do
    with {:ok, test_meta, _} <- transform(test),
         {:ok, body_meta, _} <- transform_body(body),
         {:ok, else_meta, _} <- transform_body_or_nil(Map.get(node, "orelse", [])) do
      meta =
        [loop_type: :while] ++ if(else_meta, do: [orelse: else_meta], else: [])

      ast = {:loop, meta, [test_meta, body_meta]}
      {:ok, add_location(ast, node), %{}}
    end
  end

  # For loop
  def transform(%{"_type" => "For", "target" => target, "iter" => iter, "body" => body} = node) do
    with {:ok, target_meta, _} <- transform(target),
         {:ok, iter_meta, _} <- transform(iter),
         {:ok, body_meta, _} <- transform_body(body),
         {:ok, else_meta, _} <- transform_body_or_nil(Map.get(node, "orelse", [])) do
      meta =
        [loop_type: :for_each] ++ if(else_meta, do: [orelse: else_meta], else: [])

      ast = {:loop, meta, [target_meta, iter_meta, body_meta]}
      {:ok, add_location(ast, node), %{}}
    end
  end

  # Lambdas - M2.2 Extended Layer

  def transform(%{"_type" => "Lambda", "args" => args, "body" => body} = node) do
    with {:ok, params} <- extract_lambda_params(args),
         {:ok, body_meta, _} <- transform(body) do
      # Lambdas don't capture variables explicitly in Python AST
      {:ok, add_location({:lambda, [params: params, captures: []], [body_meta]}, node), %{}}
    end
  end

  # Collection Operations - M2.2 Extended Layer

  # Simple list comprehension without filters → map
  #
  # Only a plain synchronous single generator qualifies. An `async for`
  # generator falls through to the general `:comprehension` clause below,
  # which keeps `is_async` — the `:map` shape has nowhere to put it.
  def transform(
        %{
          "_type" => "ListComp",
          "elt" => elt,
          "generators" => [%{"target" => target, "iter" => iter, "ifs" => []} = gen]
        } = node
      ) do
    if Map.get(gen, "is_async", 0) == 1 do
      transform_list_comp(node)
    else
      transform_simple_list_comp(node, target, iter, elt)
    end
  end

  # List comprehension with filters, several generators, or an async
  # generator → `:comprehension` (the `:map` shape above cannot hold them).
  def transform(%{"_type" => "ListComp"} = node), do: transform_list_comp(node)

  # Exception Handling - M2.2 Extended Layer

  def transform(
        %{
          "_type" => "Try",
          "body" => body,
          "handlers" => handlers,
          "orelse" => orelse,
          "finalbody" => finalbody
        } = node
      ) do
    with {:ok, body_meta, _} <- transform_body(body),
         {:ok, rescue_clauses} <- transform_exception_handlers(handlers),
         {:ok, else_meta, _} <- transform_body_or_nil(orelse),
         {:ok, finally_meta, _} <- transform_body_or_nil(finalbody) do
      meta = if(else_meta, do: [orelse: else_meta], else: [])

      {:ok,
       add_location({:exception_handling, meta, [body_meta, rescue_clauses, finally_meta]}, node),
       %{}}
    end
  end

  # Native Layer - M2.3: Python-Specific Constructs

  # Function definitions with decorators - transform function body, keep decorators in meta
  def transform(%{"_type" => "FunctionDef", "decorator_list" => [_ | _] = decorators} = node) do
    if contains_yield?(Map.get(node, "body", [])) do
      {:ok, {:language_specific, [language: :python, hint: :function_with_generator], node}, %{}}
    else
      with {:ok, decorator_names} <- extract_decorator_names(decorators) do
        node_without_decorators = Map.put(node, "decorator_list", [])
        decorator_args = extract_decorator_args(decorators)

        case transform_function_def(node_without_decorators) do
          {:ok, {:function_def, meta, body}, metadata} ->
            decorator_meta =
              decorator_meta(decorator_names, decorator_args) ++ decorator_expr_meta(decorators)

            {:ok, {:function_def, decorator_meta ++ meta, body}, metadata}

          other ->
            other
        end
      end
    end
  end

  # Generator functions (FunctionDef containing Yield/YieldFrom) - keep as language_specific
  def transform(%{"_type" => "FunctionDef", "body" => body} = node) do
    if contains_yield?(body) do
      {:ok, {:language_specific, [language: :python, hint: :function_with_generator], node}, %{}}
    else
      transform_function_def(node)
    end
  end

  # Async function definitions - transform body, mark with async: true
  def transform(%{"_type" => "AsyncFunctionDef"} = node) do
    # Transform like regular FunctionDef but add async: true
    func_node = Map.put(node, "_type", "FunctionDef")
    decorators = Map.get(node, "decorator_list", [])

    case {decorators, contains_yield?(Map.get(node, "body", []))} do
      {_, true} ->
        {:ok, {:language_specific, [language: :python, hint: :async_generator], node}, %{}}

      {[_ | _] = decs, false} ->
        with {:ok, decorator_names} <- extract_decorator_names(decs) do
          clean = Map.put(func_node, "decorator_list", [])
          decorator_args = extract_decorator_args(decs)

          case transform_function_def(clean) do
            {:ok, {:function_def, meta, body}, metadata} ->
              decorator_meta =
                decorator_meta(decorator_names, decorator_args) ++ decorator_expr_meta(decs)

              meta = [async: true] ++ decorator_meta ++ meta
              {:ok, {:function_def, meta, body}, metadata}

            other ->
              other
          end
        end

      {[], false} ->
        case transform_function_def(func_node) do
          {:ok, {:function_def, meta, body}, metadata} ->
            {:ok, {:function_def, [async: true] ++ meta, body}, metadata}

          other ->
            other
        end
    end
  end

  # Class definitions with decorators - transform class body, keep decorators in meta
  def transform(%{"_type" => "ClassDef", "decorator_list" => [_ | _] = decorators} = node) do
    with {:ok, decorator_names} <- extract_decorator_names(decorators) do
      node_without_decorators = Map.put(node, "decorator_list", [])
      decorator_args = extract_decorator_args(decorators)

      case transform(node_without_decorators) do
        {:ok, {:container, meta, body}, metadata} ->
          decorator_meta =
            decorator_meta(decorator_names, decorator_args) ++ decorator_expr_meta(decorators)

          {:ok, {:container, decorator_meta ++ meta, body}, metadata}

        other ->
          other
      end
    end
  end

  # Class definitions - transform to M2.2s :container
  def transform(%{"_type" => "ClassDef", "name" => name, "body" => body} = node) do
    with {:ok, body_stmts} <- transform_list(body) do
      bases = Map.get(node, "bases", [])

      # `:bases` holds the base *names* (for analyzers); `:base_exprs` holds
      # the full base expressions, so `class A(B[int])` reifies as `B[int]`
      # rather than collapsing to `unknown`.
      base_names = Enum.map(bases, &format_base_name/1)
      base_exprs = Enum.map(bases, fn base -> elem(transform(base), 1) end)

      # `class A(metaclass=ABCMeta)` — class keyword arguments. Dropping them
      # silently changed the class's metaclass.
      class_keywords =
        case transform_call_keywords(Map.get(node, "keywords", []) || []) do
          {:ok, keywords} -> keywords
          _ -> []
        end

      meta =
        [container_type: :class, name: name, module: name, language: :python] ++
          if(base_names != [], do: [bases: base_names], else: []) ++
          if(base_exprs != [], do: [base_exprs: base_exprs], else: []) ++
          if(class_keywords != [], do: [class_keywords: class_keywords], else: []) ++
          location_meta(node)

      {:ok, {:container, meta, body_stmts}, %{}}
    end
  end

  # Context managers (with statement) - transform to block with bindings
  #
  # `:with_items` records the `withitem` nodes so `FromMeta` can rebuild the
  # `With` statement. Without it the items were reified as a bare statement
  # list, which unparsed to nonsense (`open(a) as fopen(b) as g`).
  def transform(%{"_type" => "With", "items" => items, "body" => body} = node) do
    with {:ok, bindings} <- transform_with_items(items),
         {:ok, body_stmts} <- transform_list(body) do
      body_ast =
        case body_stmts do
          [single] -> single
          multiple -> {:block, [], multiple}
        end

      statements = bindings ++ [body_ast]

      meta =
        [original_form: :with, with_items: length(items)] ++ location_meta(node)

      {:ok, {:block, meta, statements}, %{}}
    end
  end

  # Async context managers (async with)
  def transform(%{"_type" => "AsyncWith"} = node) do
    {:ok, {:language_specific, [language: :python, hint: :async_context_manager], node}, %{}}
  end

  # Generators (yield) - M2.2 Extended Layer
  def transform(%{"_type" => "Yield", "value" => value} = node) do
    with {:ok, value_meta, _} <- transform_or_nil(value) do
      children = if is_nil(value_meta), do: [], else: [value_meta]
      {:ok, add_location({:yield, [kind: :yield], children}, node), %{}}
    end
  end

  def transform(%{"_type" => "Yield"} = node) do
    {:ok, add_location({:yield, [kind: :yield], []}, node), %{}}
  end

  # Yield from (Python 3.3+) - M2.2 Extended Layer
  def transform(%{"_type" => "YieldFrom", "value" => value} = node) do
    with {:ok, value_meta, _} <- transform(value) do
      {:ok, add_location({:yield, [kind: :yield_from], [value_meta]}, node), %{}}
    end
  end

  # Await expressions
  def transform(%{"_type" => "Await"} = node) do
    {:ok, {:language_specific, [language: :python, hint: :await], node}, %{}}
  end

  # Async for loops
  def transform(%{"_type" => "AsyncFor"} = node) do
    {:ok, {:language_specific, [language: :python, hint: :async_for], node}, %{}}
  end

  # Import statements - M2.2s Structural Layer
  def transform(%{"_type" => "Import", "names" => names} = node) do
    case names do
      [%{"name" => name} = alias_node] ->
        asname = Map.get(alias_node, "asname")

        meta =
          [source: name, import_type: :module, language: :python] ++
            if(asname, do: [alias: asname], else: []) ++
            location_meta(node)

        {:ok, {:import, meta, []}, %{}}

      aliases when is_list(aliases) ->
        import_nodes =
          Enum.map(aliases, fn %{"name" => name} = alias_entry ->
            asname = Map.get(alias_entry, "asname")

            meta =
              [source: name, import_type: :module, language: :python] ++
                if(asname, do: [alias: asname], else: []) ++
                location_meta(node)

            {:import, meta, []}
          end)

        # `import a, b` is one `Import` node with several aliases. The block
        # is marked so `FromMeta` merges it back instead of emitting one
        # `import` statement per module.
        {:ok, {:block, [original_form: :multi_import], import_nodes}, %{}}
    end
  end

  # Import from statements - M2.2s Structural Layer
  def transform(%{"_type" => "ImportFrom", "module" => module, "names" => names} = node) do
    imported_names =
      Enum.map(names, fn
        %{"name" => name} -> name
        name when is_binary(name) -> name
      end)

    # `from x import y as z` — the `as` names are positional, aligned with
    # `:names`. Dropping them rewrote `from gettext import gettext as _` as
    # `from gettext import gettext`, silently changing which symbol was bound.
    aliases =
      names
      |> Enum.map(fn
        %{"asname" => asname} -> asname
        _ -> nil
      end)

    source = module || ""
    level = Map.get(node, "level", 0)

    meta =
      [source: source, names: imported_names, import_type: :from, language: :python] ++
        if(Enum.any?(aliases, &is_binary/1), do: [name_aliases: aliases], else: []) ++
        if(level > 0, do: [relative_level: level], else: []) ++
        location_meta(node)

    {:ok, {:import, meta, []}, %{}}
  end

  # Dict comprehensions → comprehension with comp_type: :dict
  def transform(
        %{"_type" => "DictComp", "key" => key, "value" => value, "generators" => generators} =
          node
      ) do
    with {:ok, key_meta, _} <- transform(key),
         {:ok, value_meta, _} <- transform(value),
         {:ok, gens_and_filters} <- transform_comprehension_generators(generators) do
      body = {:pair, [], [key_meta, value_meta]}

      {:ok,
       add_location(
         {:comprehension, [comp_type: :dict], [body | gens_and_filters]},
         node
       ), %{}}
    end
  end

  # Set comprehensions → comprehension with comp_type: :set
  def transform(%{"_type" => "SetComp", "elt" => elt, "generators" => generators} = node) do
    with {:ok, elt_meta, _} <- transform(elt),
         {:ok, gens_and_filters} <- transform_comprehension_generators(generators) do
      {:ok,
       add_location(
         {:comprehension, [comp_type: :set], [elt_meta | gens_and_filters]},
         node
       ), %{}}
    end
  end

  # Generator expressions → comprehension with comp_type: :generator
  def transform(%{"_type" => "GeneratorExp", "elt" => elt, "generators" => generators} = node) do
    with {:ok, elt_meta, _} <- transform(elt),
         {:ok, gens_and_filters} <- transform_comprehension_generators(generators) do
      {:ok,
       add_location(
         {:comprehension, [comp_type: :generator], [elt_meta | gens_and_filters]},
         node
       ), %{}}
    end
  end

  # Match statements (Python 3.10+) → pattern_match
  def transform(%{"_type" => "Match", "subject" => subject, "cases" => cases} = node) do
    with {:ok, subject_meta, _} <- transform(subject),
         {:ok, arms} <- transform_match_cases(cases) do
      {:ok, add_location({:pattern_match, [], [subject_meta | arms]}, node), %{}}
    end
  end

  # Walrus operator (Python 3.8+) → inline_match
  def transform(%{"_type" => "NamedExpr", "target" => target, "value" => value} = node) do
    with {:ok, target_meta, _} <- transform(target),
         {:ok, value_meta, _} <- transform(value) do
      {:ok, add_location({:inline_match, [], [target_meta, value_meta]}, node), %{}}
    end
  end

  # F-strings (Python 3.6+) - M2.1 Core Layer
  #
  # A `JoinedStr` is a sequence of `Constant` (literal text) and
  # `FormattedValue` (an interpolated expression) parts, which maps directly
  # onto M2's `:string_interpolation`. Previously this fell through to the
  # catch-all and the whole f-string became opaque `:language_specific`.
  def transform(%{"_type" => "JoinedStr", "values" => values} = node) do
    with {:ok, parts} <- transform_fstring_parts(values) do
      {:ok, add_location({:string_interpolation, [], parts}, node), %{}}
    end
  end

  # A `FormattedValue` on its own (only reachable through a JoinedStr in
  # practice) is just its expression.
  def transform(%{"_type" => "FormattedValue", "value" => value}) do
    transform(value)
  end

  # Global/nonlocal declarations
  def transform(%{"_type" => "Global"} = node) do
    {:ok, {:language_specific, [language: :python, hint: :global], node}, %{}}
  end

  def transform(%{"_type" => "Nonlocal"} = node) do
    {:ok, {:language_specific, [language: :python, hint: :nonlocal], node}, %{}}
  end

  # Assert statements
  def transform(%{"_type" => "Assert"} = node) do
    {:ok, {:language_specific, [language: :python, hint: :assert], node}, %{}}
  end

  # Raise statements - M2.1 Core Layer (:throw)
  def transform(%{"_type" => "Raise", "exc" => exc} = node) when not is_nil(exc) do
    with {:ok, exc_meta, _} <- transform(exc),
         {:ok, cause_meta, _} <- transform_or_nil(Map.get(node, "cause")) do
      # `raise X from Y` — the cause expression is kept, not just a flag, so
      # the `from Y` clause survives the round-trip.
      meta =
        [kind: :raise] ++
          if(cause_meta, do: [has_cause: true, cause: cause_meta], else: []) ++
          location_meta(node)

      {:ok, {:throw, meta, [exc_meta]}, %{}}
    end
  end

  # Bare raise (re-raise current exception)
  def transform(%{"_type" => "Raise"} = node) do
    {:ok, add_location({:throw, [kind: :reraise], []}, node), %{}}
  end

  # Delete statements
  def transform(%{"_type" => "Delete"} = node) do
    {:ok, {:language_specific, [language: :python, hint: :delete], node}, %{}}
  end

  # Pass statement
  def transform(%{"_type" => "Pass"} = node) do
    {:ok, {:language_specific, [language: :python, hint: :pass], node}, %{}}
  end

  # Attribute access (obj.attr) - M2.2s Structural Layer
  def transform(%{"_type" => "Attribute", "value" => value, "attr" => attr} = node) do
    with {:ok, receiver_meta, _} <- transform(value) do
      ast = {:attribute_access, [attribute: attr] ++ location_meta(node), [receiver_meta]}
      {:ok, ast, %{}}
    end
  end

  # Subscription (obj[key], obj[start:stop:step]) - M2.2s Structural Layer
  #
  # MetaAST has no dedicated index node, so a subscript is expressed as a
  # function call to the `[]` accessor with the receiver as the first
  # argument. That keeps the receiver and the index in the tree (so analyzers
  # can still see both) while staying inside the M2 core layer.
  def transform(%{"_type" => "Subscript", "value" => value, "slice" => slice} = node) do
    with {:ok, receiver_meta, _} <- transform(value),
         {:ok, index_meta, _} <- transform(slice) do
      ast = {:function_call, [name: "[]"] ++ location_meta(node), [receiver_meta, index_meta]}
      {:ok, ast, %{}}
    end
  end

  # Slices - the `slice` field of a Subscript.
  #
  # Python 3.9+ emits the bound expressions directly; 3.8 wrapped them in an
  # `Index` node. Both shapes are accepted, and `ExtSlice` (multi-dimensional
  # `a[i, j]`) becomes a tuple of slices.
  def transform(%{"_type" => "Slice", "lower" => lower, "upper" => upper} = node) do
    step = Map.get(node, "step")

    with {:ok, lower_meta, _} <- transform_or_nil(lower),
         {:ok, upper_meta, _} <- transform_or_nil(upper),
         {:ok, step_meta, _} <- transform_or_nil(step) do
      meta =
        [kind: :slice] ++ if(step_meta, do: [step: step_meta], else: []) ++ location_meta(node)

      {:ok, {:range, meta, [lower_meta, upper_meta]}, %{}}
    end
  end

  # Python 3.8 compatibility: `Index` is a transparent wrapper.
  def transform(%{"_type" => "Index", "value" => value}), do: transform(value)

  def transform(%{"_type" => "ExtSlice", "dims" => dims} = node) do
    with {:ok, dims_meta} <- transform_list(dims) do
      {:ok, add_location({:tuple, [], dims_meta}, node), %{}}
    end
  end

  # Context nodes (`Load`/`Store`/`Del`) carry no information of their own;
  # they only annotate the *parent* node, so they transform to a null literal
  # rather than failing the whole file.
  def transform(%{"_type" => ctx} = node) when ctx in ["Load", "Store", "Del"] do
    {:ok, add_location({:literal, [subtype: :null], nil}, node), %{}}
  end

  # Catch-all for constructs the core layer does not model.
  #
  # Returning an error here made an entire file unparseable because of one
  # unsupported node (a `Subscript` in `parser.py` aborted the whole module).
  # Preserving the native node as `:language_specific` keeps the rest of the
  # tree usable and lets `FromMeta` restore the node verbatim.
  def transform(unsupported) when is_map(unsupported) do
    hint = unsupported |> Map.get("_type", "unknown") |> Macro.underscore() |> String.to_atom()

    {:ok,
     {:language_specific, [language: :python, hint: hint] ++ location_meta(unsupported),
      unsupported}, %{}}
  end

  def transform(unsupported) do
    {:error, "Unsupported Python AST construct: #{inspect(unsupported)}"}
  end

  # `:decorators` (names) plus `:decorator_args` (call arguments, aligned with
  # the names; `nil` for a decorator that is not a call).
  defp decorator_meta(names, args) do
    [decorators: names] ++ if(args == [], do: [], else: [decorator_args: args])
  end

  # Decorators whose callee is not a plain dotted name (`@a.b(1)(2)`) cannot
  # be rebuilt from a name string. Their full expression is kept verbatim.
  defp decorator_expr_meta(decorators) when is_list(decorators) do
    exprs =
      decorators
      |> Enum.with_index()
      |> Enum.flat_map(fn {decorator, index} ->
        if decorator_name_expressible?(decorator) do
          []
        else
          case transform(decorator) do
            {:ok, expr, _} -> [{index, expr}]
            _ -> []
          end
        end
      end)

    if exprs == [], do: [], else: [decorator_exprs: exprs]
  end

  # A decorator is name-expressible when it is a plain dotted name, optionally
  # called with arguments (`@app.route("/")`). A call whose callee is itself a
  # call (`@a.b(1)(2)`) is not: the name alone cannot rebuild it.
  defp decorator_name_expressible?(%{"_type" => "Name"}), do: true
  defp decorator_name_expressible?(%{"_type" => "Attribute"}), do: true

  defp decorator_name_expressible?(%{"_type" => "Call", "func" => func}),
    do: dotted_name?(func)

  defp decorator_name_expressible?(_), do: false

  defp dotted_name?(%{"_type" => "Name"}), do: true
  defp dotted_name?(%{"_type" => "Attribute", "value" => value}), do: dotted_name?(value)
  defp dotted_name?(_), do: false

  defp transform_dict(%{"_type" => "Dict", "keys" => keys, "values" => values} = node) do
    with {:ok, keys_meta} <- transform_list(keys),
         {:ok, values_meta} <- transform_list(values) do
      # Transform pairs to {:pair, [], [key, value]} format
      pairs = Enum.zip_with(keys_meta, values_meta, fn k, v -> {:pair, [], [k, v]} end)
      ast = {:map, [], pairs}
      {:ok, add_location(ast, node), %{}}
    end
  end

  defp put_fstring_meta({type, meta, children}, node) when is_list(meta) do
    conversion = Map.get(node, "conversion", -1)

    meta =
      meta ++
        if(is_integer(conversion) and conversion >= 0,
          do: [conversion: conversion],
          else: []
        ) ++
        format_spec_meta(Map.get(node, "format_spec"))

    {type, meta, children}
  end

  defp put_fstring_meta(other, _node), do: other

  # A format spec is itself a `JoinedStr` of literal text and nested
  # interpolations (e.g. `f"{x:{width}}"`). The literal text is the common
  # case and is stored as a plain string.
  defp format_spec_meta(nil), do: []

  # A format spec may itself interpolate (`f"{x:{width}}"`), so it is kept as
  # a nested `:string_interpolation` rather than only handling literal text.
  defp format_spec_meta(%{"_type" => "JoinedStr", "values" => values} = node) do
    case values do
      [%{"_type" => "Constant", "value" => text}] when is_binary(text) ->
        [format_spec: text]

      _ ->
        case transform_fstring_parts(values) do
          {:ok, parts} -> [format_spec: {:string_interpolation, [], parts}]
          _ -> [format_spec: {:language_specific, [language: :python], node}]
        end
    end
  end

  defp format_spec_meta(other), do: [format_spec: other]

  # Helper Functions

  # List comprehension with filters (or an async generator) → comprehension

  defp put_string_kind({:literal, meta, value}, kind)
       when is_binary(value) and is_binary(kind) do
    {:literal, meta ++ [string_kind: kind], value}
  end

  defp put_string_kind(literal, _kind), do: literal

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

  defp transform_or_nil(nil), do: {:ok, nil, %{}}
  defp transform_or_nil(value), do: transform(value)

  defp transform_body([]), do: {:ok, {:block, [], []}, %{}}
  defp transform_body([single]), do: transform(single)

  defp transform_body(statements) when is_list(statements) do
    with {:ok, transformed} <- transform_list(statements) do
      {:ok, {:block, [], transformed}, %{}}
    end
  end

  defp transform_body_or_nil([]), do: {:ok, nil, %{}}
  defp transform_body_or_nil(body), do: transform_body(body)

  defp infer_literal_type(value) when is_integer(value),
    do: {:literal, [subtype: :integer], value}

  defp infer_literal_type(value) when is_float(value), do: {:literal, [subtype: :float], value}
  defp infer_literal_type(value) when is_binary(value), do: {:literal, [subtype: :string], value}
  defp infer_literal_type(true), do: {:literal, [subtype: :boolean], true}
  defp infer_literal_type(false), do: {:literal, [subtype: :boolean], false}
  defp infer_literal_type(nil), do: {:literal, [subtype: :null], nil}

  # Operator transformations

  defp transform_binop(%{"_type" => "Add"}), do: {:ok, {:arithmetic, :+}}
  defp transform_binop(%{"_type" => "Sub"}), do: {:ok, {:arithmetic, :-}}
  defp transform_binop(%{"_type" => "Mult"}), do: {:ok, {:arithmetic, :*}}
  defp transform_binop(%{"_type" => "Div"}), do: {:ok, {:arithmetic, :/}}
  defp transform_binop(%{"_type" => "FloorDiv"}), do: {:ok, {:arithmetic, :div}}
  defp transform_binop(%{"_type" => "Mod"}), do: {:ok, {:arithmetic, :rem}}
  defp transform_binop(%{"_type" => "Pow"}), do: {:ok, {:arithmetic, :**}}

  # Bitwise operators. The operator atoms are the ones the other adapters
  # already use for this category (`:band`, `:bsl`, ...), so a Python `a & b`
  # and an Erlang `A band B` produce the same MetaAST.
  defp transform_binop(%{"_type" => "BitAnd"}), do: {:ok, {:bitwise, :band}}
  defp transform_binop(%{"_type" => "BitOr"}), do: {:ok, {:bitwise, :bor}}
  defp transform_binop(%{"_type" => "BitXor"}), do: {:ok, {:bitwise, :bxor}}
  defp transform_binop(%{"_type" => "LShift"}), do: {:ok, {:bitwise, :bsl}}
  defp transform_binop(%{"_type" => "RShift"}), do: {:ok, {:bitwise, :bsr}}

  # Matrix multiplication has no meta-level operator; it is carried as
  # arithmetic with its own atom so the source spelling survives.
  defp transform_binop(%{"_type" => "MatMult"}), do: {:ok, {:arithmetic, :@}}

  defp transform_binop(op), do: {:error, "Unsupported binary operator: #{inspect(op)}"}

  defp transform_compare_op(%{"_type" => "Eq"}), do: {:ok, :==}
  defp transform_compare_op(%{"_type" => "NotEq"}), do: {:ok, :!=}
  defp transform_compare_op(%{"_type" => "Lt"}), do: {:ok, :<}
  defp transform_compare_op(%{"_type" => "LtE"}), do: {:ok, :<=}
  defp transform_compare_op(%{"_type" => "Gt"}), do: {:ok, :>}
  defp transform_compare_op(%{"_type" => "GtE"}), do: {:ok, :>=}
  defp transform_compare_op(%{"_type" => "Is"}), do: {:ok, :===}
  defp transform_compare_op(%{"_type" => "IsNot"}), do: {:ok, :!==}
  # Membership tests. MetaAST has no dedicated `in` operator atom, so these
  # are carried as comparison operators with their Python spelling; `FromMeta`
  # maps them straight back to `In`/`NotIn`.
  defp transform_compare_op(%{"_type" => "In"}), do: {:ok, :in}
  defp transform_compare_op(%{"_type" => "NotIn"}), do: {:ok, :not_in}
  defp transform_compare_op(op), do: {:error, "Unsupported comparison operator: #{inspect(op)}"}

  defp transform_bool_op(%{"_type" => "And"}), do: {:ok, :and}
  defp transform_bool_op(%{"_type" => "Or"}), do: {:ok, :or}
  defp transform_bool_op(op), do: {:error, "Unsupported boolean operator: #{inspect(op)}"}

  defp transform_unary_op(%{"_type" => "Not"}), do: {:ok, {:boolean, :not}}
  defp transform_unary_op(%{"_type" => "USub"}), do: {:ok, {:arithmetic, :-}}
  defp transform_unary_op(%{"_type" => "UAdd"}), do: {:ok, {:arithmetic, :+}}
  defp transform_unary_op(%{"_type" => "Invert"}), do: {:ok, {:bitwise, :bnot}}
  defp transform_unary_op(op), do: {:error, "Unsupported unary operator: #{inspect(op)}"}

  # Call keyword arguments → `:param` nodes.
  #
  # Three shapes appear in `Call.keywords`:
  #   * `keyword(arg="x", value=...)`   → `{:param, [kind: :keyword], "x"}`
  #   * `keyword(arg=nil, value=...)`    → `**expr` unpacking
  #   * `None` (from an older parser)    → `**expr` unpacking
  # The unpacked expression is kept in the param's `:default` slot, which is
  # where `:param` already stores the value bound to a name.
  defp transform_call_keywords(keywords) when is_list(keywords) do
    keywords
    |> Enum.reduce_while({:ok, []}, fn keyword, {:ok, acc} ->
      case transform_call_keyword(keyword) do
        {:ok, param} -> {:cont, {:ok, [param | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, params} -> {:ok, Enum.reverse(params)}
      error -> error
    end
  end

  defp transform_call_keywords(_), do: {:ok, []}

  defp transform_call_keyword(%{"arg" => nil, "value" => value}) do
    with {:ok, value_meta, _} <- transform(value) do
      {:ok, {:param, [kind: :keyword_variadic, default: value_meta], "**"}}
    end
  end

  defp transform_call_keyword(%{"arg" => arg, "value" => value}) when is_binary(arg) do
    with {:ok, value_meta, _} <- transform(value) do
      {:ok, {:param, [kind: :keyword, default: value_meta], arg}}
    end
  end

  defp transform_call_keyword(nil) do
    {:ok, {:param, [kind: :keyword_variadic, default: {:variable, [scope: :local], "_"}], "**"}}
  end

  defp transform_call_keyword(other) do
    {:error, "Unsupported call keyword: #{inspect(other, limit: 5)}"}
  end

  # F-string parts. Literal text becomes a `:string` literal; every
  # `FormattedValue` becomes the MetaAST of the interpolated expression.
  # Adjacent literals are merged so `f"a{b}c"` yields three parts, not five.
  defp transform_fstring_parts(values) when is_list(values) do
    values
    |> Enum.reduce_while({:ok, []}, fn value, {:ok, acc} ->
      case transform_fstring_part(value) do
        {:ok, part} -> {:cont, {:ok, append_fstring_part(acc, part)}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, parts} -> {:ok, Enum.reverse(parts)}
      error -> error
    end
  end

  defp transform_fstring_parts(_), do: {:ok, []}

  defp transform_fstring_part(%{"_type" => "Constant", "value" => text} = node)
       when is_binary(text) do
    {:ok, add_location({:literal, [subtype: :string], text}, node)}
  end

  # `f"{v:06d}"` — the conversion (`!r`) and format spec (`:06d`) are part of
  # the interpolation. They are attached as metadata on the interpolated
  # expression; dropping them silently rewrote `f"{v:06d}"` as `f"{v}"`.
  defp transform_fstring_part(%{"_type" => "FormattedValue", "value" => value} = node) do
    with {:ok, value_meta, _} <- transform(value) do
      {:ok, put_fstring_meta(value_meta, node)}
    end
  end

  defp transform_fstring_part(other) do
    case transform(other) do
      {:ok, meta, _} -> {:ok, meta}
      error -> error
    end
  end

  defp append_fstring_part([{:literal, meta, previous} | rest], {:literal, _meta, next})
       when is_binary(previous) and is_binary(next) do
    [{:literal, meta, previous <> next} | rest]
  end

  defp append_fstring_part(acc, part), do: [part | acc]

  # Transform regular FunctionDef to {:function_def, meta, body}
  defp transform_function_def(
         %{"_type" => "FunctionDef", "name" => name, "body" => body, "args" => args} = node
       ) do
    with {:ok, params, posonly_count} <- extract_function_params(args),
         {:ok, body_stmts} <- transform_list(body) do
      meta =
        [
          name: name,
          params: params,
          visibility: :public,
          arity: length(params),
          function: name,
          language: :python
        ] ++
          if(posonly_count > 0, do: [positional_only: posonly_count], else: []) ++
          docstring_meta(body) ++ location_meta(node)

      # The return annotation expression itself, not just a flag: a flag told
      # `FromMeta` that a type existed but not which one, so `-> bool` was lost.
      meta = meta ++ return_annotation_meta(Map.get(node, "returns"))

      {:ok, {:function_def, meta, body_stmts}, %{}}
    end
  end

  # A leading bare string statement is a docstring. It is kept in the body
  # (so the tree stays faithful) *and* recorded in `:docstring`, because a
  # lone string statement is indistinguishable from an expression statement
  # once reified — `def f(): "Doc."` unparsed to `def f():'Doc.'`.
  defp docstring_meta([
         %{"_type" => "Expr", "value" => %{"_type" => "Constant", "value" => text}} | _
       ])
       when is_binary(text) do
    [docstring: text]
  end

  defp docstring_meta(_), do: []

  # Extract function parameters from Python args structure.
  # Produces :param nodes with kind: metadata:
  #   :positional        — regular positional args (def f(x, y))
  #   :keyword           — keyword-only args (after bare * in signature)
  #   :variadic          — *args (variadic positional)
  #   :keyword_variadic  — **kwargs (variadic keyword)
  #
  # Default values live in `defaults` (aligned to the end of the positional
  # list) and `kw_defaults` (aligned to `kwonlyargs`, with `nil` for a
  # keyword-only parameter that has no default). They are attached to the
  # matching `:param` as `:default` so `FromMeta` can restore them.
  defp extract_function_params(%{"args" => args} = args_node) do
    # `posonlyargs` are the parameters before `/`; `args` follows it. Together
    # they form the positional list that `defaults` aligns to.
    posonly = Map.get(args_node, "posonlyargs", []) || []
    all_positional = posonly ++ args

    positional_defaults = Map.get(args_node, "defaults", [])

    # `defaults` aligns to the *end* of the positional list, so pad the front.
    positional_defaults =
      List.duplicate(nil, max(length(all_positional) - length(positional_defaults), 0)) ++
        positional_defaults

    positional =
      all_positional
      |> Enum.with_index()
      |> Enum.map(fn {arg_node, index} ->
        default = Enum.at(positional_defaults, index)
        positional_param(arg_node, default)
      end)

    positional_only_count = length(posonly)

    kwonlyargs =
      case Map.get(args_node, "kwonlyargs") do
        nil ->
          []

        kw_args ->
          kw_defaults = Map.get(args_node, "kw_defaults", [])

          kw_args
          |> Enum.with_index()
          |> Enum.map(fn {arg_node, index} ->
            keyword_param(arg_node, Enum.at(kw_defaults, index))
          end)
      end

    # *args (variadic positional)
    vararg =
      case Map.get(args_node, "vararg") do
        %{"arg" => arg_name} = arg_node ->
          [{:param, [kind: :variadic] ++ annotation_meta(arg_node), "*#{arg_name}"}]

        _ ->
          []
      end

    # **kwargs (variadic keyword)
    kwarg =
      case Map.get(args_node, "kwarg") do
        %{"arg" => arg_name} = arg_node ->
          [{:param, [kind: :keyword_variadic] ++ annotation_meta(arg_node), "**#{arg_name}"}]

        _ ->
          []
      end

    {:ok, positional ++ kwonlyargs ++ vararg ++ kwarg, positional_only_count}
  end

  defp extract_function_params(_), do: {:ok, [], 0}

  # Build a positional `:param`, attaching `:default` and `:has_type` when the
  # Python node carries them.
  defp positional_param(%{"arg" => arg_name} = arg_node, default) do
    {:param, annotation_meta(arg_node) ++ default_meta(default), arg_name}
  end

  defp positional_param(_, default),
    do: {:param, default_meta(default), "_"}

  defp keyword_param(%{"arg" => arg_name} = arg_node, default) do
    {:param, [kind: :keyword] ++ annotation_meta(arg_node) ++ default_meta(default), arg_name}
  end

  defp keyword_param(_, default), do: {:param, [kind: :keyword] ++ default_meta(default), "_"}

  defp default_meta(nil), do: []

  defp default_meta(default_node) do
    case transform(default_node) do
      {:ok, default_meta, _} -> [default: default_meta]
      _ -> []
    end
  end

  # A function's return annotation (`-> int`).
  defp return_annotation_meta(nil), do: []

  defp return_annotation_meta(annotation) do
    case transform(annotation) do
      {:ok, annotation_meta, _} -> [has_return_type: true, return_type: annotation_meta]
      _ -> []
    end
  end

  # A parameter annotation (`a: int`). The annotation *expression* is kept,
  # not just a `has_type: true` flag: the flag told `FromMeta` that a type
  # existed but not which one, so every annotation was dropped on the way
  # back (`def f(a: int)` reified as `def f(a)`).
  defp annotation_meta(%{"annotation" => nil}), do: []

  defp annotation_meta(%{"annotation" => annotation}) do
    case transform(annotation) do
      {:ok, annotation_meta, _} -> [has_type: true, annotation: annotation_meta]
      _ -> []
    end
  end

  defp annotation_meta(_), do: []

  # Build location metadata from Python AST node
  defp location_meta(%{"lineno" => line} = node) do
    loc = [line: line]
    loc = if Map.has_key?(node, "col_offset"), do: [{:col, node["col_offset"]} | loc], else: loc

    loc =
      if Map.has_key?(node, "end_lineno"),
        do: [{:end_line, node["end_lineno"]} | loc],
        else: loc

    loc =
      if Map.has_key?(node, "end_col_offset"),
        do: [{:end_col, node["end_col_offset"]} | loc],
        else: loc

    loc
  end

  defp location_meta(_), do: []

  # A class base's display name. Subscripts keep their receiver's name
  # (`B[int]` → `B`) since the full expression lives in `:base_exprs`.
  defp format_base_name(%{"_type" => "Name", "id" => id}), do: id
  defp format_base_name(%{"_type" => "Attribute"} = attr), do: format_attribute_name(attr)
  defp format_base_name(%{"_type" => "Subscript", "value" => value}), do: format_base_name(value)
  defp format_base_name(%{"_type" => "Call", "func" => func}), do: format_base_name(func)
  defp format_base_name(_), do: "unknown"

  # Format nested Attribute name (e.g. module.submodule)
  defp format_attribute_name(%{"_type" => "Attribute", "value" => value, "attr" => attr}) do
    "#{format_attribute_name(value)}.#{attr}"
  end

  defp format_attribute_name(%{"_type" => "Name", "id" => name}), do: name
  defp format_attribute_name(_), do: "unknown"

  # Check if body contains Yield or YieldFrom expressions
  defp contains_yield?(body) when is_list(body) do
    Enum.any?(body, &contains_yield_node?/1)
  end

  defp contains_yield?(node), do: contains_yield_node?(node)

  defp contains_yield_node?(%{"_type" => "Yield"}), do: true
  defp contains_yield_node?(%{"_type" => "YieldFrom"}), do: true

  defp contains_yield_node?(%{} = node) when is_map(node) do
    # Recursively check all values in the node
    Enum.any?(Map.values(node), fn
      value when is_list(value) -> contains_yield?(value)
      value when is_map(value) -> contains_yield_node?(value)
      _ -> false
    end)
  end

  defp contains_yield_node?(_), do: false

  # Resolve a callee into `{name, receiver}`.
  #
  # `receiver` is `nil` when the callee is a plain (possibly dotted) name, and
  # the callee expression itself when it is not — `f(x).decode()` has no
  # dotted name, so the receiver is carried verbatim and rebuilt by
  # `FromMeta` instead of being dropped.
  defp call_target(%{"_type" => "Name", "id" => name}), do: {:ok, name, nil}

  defp call_target(%{"_type" => "Attribute", "value" => obj, "attr" => attr} = node) do
    case call_target(obj) do
      {:ok, obj_name, nil} -> {:ok, "#{obj_name}.#{attr}", nil}
      {:ok, _obj_name, _receiver} -> expression_target(node)
      error -> error
    end
  end

  # A subscript callee (`a[k](x)`, `a[k].m(x)`) has no dotted name: the index
  # is part of the callee and cannot be expressed in one. Naming it `a[]`
  # used to *drop* the index, which reified `a['k'].split(',')` as
  # `a[].split(',')` — invalid Python. The expression is carried instead.
  defp call_target(%{"_type" => "Subscript"} = node), do: expression_target(node)

  # Any other callee (`f(x)(y)`, `f(x).decode()`, a lambda): there is no name
  # to report, so the expression is carried as the receiver.
  defp call_target(func) when is_map(func), do: expression_target(func)

  defp call_target(func), do: {:error, "Unsupported function reference: #{inspect(func)}"}

  defp expression_target(node) do
    case transform(node) do
      {:ok, receiver, _} -> {:ok, "", receiver}
      error -> error
    end
  end

  # Lambda parameter extraction
  #
  # `args` is the parameter list; `defaults` (aligned to the end of that list)
  # carries the default-value expressions, which are attached as `:default`.
  defp extract_lambda_params(%{"args" => args} = args_node) when is_list(args) do
    defaults =
      args_node
      |> Map.get("defaults", [])
      |> then(fn defaults ->
        List.duplicate(nil, max(length(args) - length(defaults), 0)) ++ defaults
      end)

    positional =
      args
      |> Enum.with_index()
      |> Enum.map(fn {arg_node, index} ->
        default = Enum.at(defaults, index)

        case arg_node do
          %{"arg" => name} -> {:param, default_meta(default), name}
          %{"id" => name} -> {:param, default_meta(default), name}
          _ -> {:param, default_meta(default), "_"}
        end
      end)

    # A lambda can be variadic too: `lambda *args, **kw: ...`. Dropping these
    # reified `lambda *values: values` as `lambda: values`.
    vararg =
      case Map.get(args_node, "vararg") do
        %{"arg" => name} -> [{:param, [kind: :variadic], "*#{name}"}]
        _ -> []
      end

    kwarg =
      case Map.get(args_node, "kwarg") do
        %{"arg" => name} -> [{:param, [kind: :keyword_variadic], "**#{name}"}]
        _ -> []
      end

    {:ok, positional ++ vararg ++ kwarg}
  end

  defp extract_lambda_params(_), do: {:ok, []}

  # Exception handler transformation

  defp transform_exception_handlers(handlers) when is_list(handlers) do
    handlers
    |> Enum.reduce_while({:ok, []}, fn handler, {:ok, acc} ->
      case transform_exception_handler(handler) do
        {:ok, clause} -> {:cont, {:ok, [clause | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, clauses} -> {:ok, Enum.reverse(clauses)}
      error -> error
    end
  end

  # A `Try` handler is an `ExceptHandler` node. Its `"type"` field is the
  # exception class expression (`nil` for a bare `except:`), and `"name"` is
  # the optional `as` binding.
  #
  # The M2 shape for a handler is a `:match_arm` whose pattern is the bound
  # variable (or a wildcard when nothing is bound) and whose metadata carries
  # the exception type. `AST.conforms?/1` requires exactly that shape, so
  # emitting a bare `{type, var, body}` tuple made the whole tree invalid.
  defp transform_exception_handler(%{"_type" => "ExceptHandler"} = handler) do
    exception_type = Map.get(handler, "type")
    name = Map.get(handler, "name")
    body = Map.get(handler, "body", [])

    with {:ok, type_meta} <- extract_exception_type(exception_type),
         {:ok, pattern, _} <- transform_or_name(name),
         {:ok, body_meta, _} <- transform_body(body) do
      {:ok, exception_match_arm(type_meta, pattern, body_meta, handler)}
    end
  end

  # Legacy/alternate shape: the handler type is already a plain string.
  defp transform_exception_handler(%{"type" => type, "name" => name, "body" => body} = handler) do
    with {:ok, exception_type} <- extract_exception_type(type),
         {:ok, pattern, _} <- transform_or_name(name),
         {:ok, body_meta, _} <- transform_body(body) do
      {:ok, exception_match_arm(exception_type, pattern, body_meta, handler)}
    end
  end

  defp transform_exception_handler(%{"type" => type, "body" => body} = handler) do
    with {:ok, exception_type} <- extract_exception_type(type),
         {:ok, body_meta, _} <- transform_body(body) do
      {:ok, exception_match_arm(exception_type, nil, body_meta, handler)}
    end
  end

  defp transform_exception_handler(other) do
    {:error, "Unsupported except handler: #{inspect(other, limit: 5)}"}
  end

  defp exception_match_arm(exception_type, pattern, body_meta, handler) do
    meta =
      [exception_type: exception_type, pattern: pattern] ++ location_meta(handler)

    {:match_arm, meta, [body_meta]}
  end

  # Python's built-in exception hierarchy names. They are carried verbatim so
  # `raise`/`except ValueError` round-trips as `ValueError` instead of being
  # flattened to the generic `Exception`.
  #
  # A tuple of exception types (`except (A, B):`) is preserved as a
  # `:language_specific` node, since M2 has no union type.
  # A bare `except:` catches everything. It is distinguished from
  # `except Exception:` so the reified source keeps the original spelling.
  defp extract_exception_type(nil), do: {:ok, nil}

  defp extract_exception_type(%{"_type" => "Name", "id" => name}) do
    {:ok, safe_exception_atom(name)}
  end

  defp extract_exception_type(%{"_type" => "Attribute"} = node) do
    {:ok, safe_exception_atom(format_attribute_name(node))}
  end

  defp extract_exception_type(%{"_type" => "Tuple"} = node) do
    {:ok, {:language_specific, [language: :python, hint: :exception_tuple], node}}
  end

  defp extract_exception_type(other), do: {:ok, other}

  # `String.to_atom/1` on parser output would leak one atom per distinct
  # exception class in the input. `safe_exception_atom/1` keeps the set
  # bounded to names that already exist as atoms, falling back to a
  # `:language_specific` node (which `FromMeta` restores verbatim) for
  # anything else.
  defp safe_exception_atom(name) when is_binary(name) do
    String.to_existing_atom(name)
  rescue
    ArgumentError ->
      {:language_specific, [language: :python, hint: :exception_name],
       %{"_type" => "Name", "id" => name, "ctx" => %{"_type" => "Load"}}}
  end

  defp safe_exception_atom(name), do: name

  defp transform_or_name(nil), do: {:ok, nil, %{}}

  defp transform_or_name(name) when is_binary(name),
    do: {:ok, {:variable, [scope: :local], name}, %{}}

  defp transform_or_name(node), do: transform(node)

  # Transform comprehension generators (shared by ListComp, DictComp, SetComp, GeneratorExp)
  defp transform_comprehension_generators(generators) when is_list(generators) do
    generators
    |> Enum.reduce_while({:ok, []}, fn gen, {:ok, acc} ->
      case transform_comprehension_generator(gen) do
        {:ok, items} -> {:cont, {:ok, acc ++ items}}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp transform_comprehension_generator(
         %{"target" => target, "iter" => iter, "ifs" => ifs} = gen_node
       ) do
    with {:ok, target_meta, _} <- transform(target),
         {:ok, iter_meta, _} <- transform(iter) do
      # `async for` inside a comprehension (`[x async for x in a])` sets
      # `is_async` on the generator; it is part of the AST, so it is kept.
      gen_meta = if Map.get(gen_node, "is_async", 0) == 1, do: [async: true], else: []

      generator = add_location({:generator, gen_meta, [target_meta, iter_meta]}, gen_node)

      filters =
        Enum.map(ifs, fn if_expr ->
          case transform(if_expr) do
            {:ok, filter_meta, _} -> add_location({:filter, [], [filter_meta]}, if_expr)
            _ -> nil
          end
        end)
        |> Enum.reject(&is_nil/1)

      {:ok, [generator | filters]}
    end
  end

  defp transform_comprehension_generator(_), do: {:ok, []}

  # Transform match statement cases (Python 3.10+)
  defp transform_match_cases(cases) when is_list(cases) do
    cases
    |> Enum.reduce_while({:ok, []}, fn match_case, {:ok, acc} ->
      case transform_match_case(match_case) do
        {:ok, arm} -> {:cont, {:ok, [arm | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, arms} -> {:ok, Enum.reverse(arms)}
      error -> error
    end
  end

  defp transform_match_case(%{"pattern" => pattern, "body" => body} = case_node) do
    guard = Map.get(case_node, "guard")

    with {:ok, body_stmts} <- transform_list(body) do
      body_ast =
        case body_stmts do
          [single] -> single
          multiple -> {:block, [], multiple}
        end

      # Pattern is kept as language_specific since Python match patterns are complex
      pattern_ast = {:language_specific, [language: :python, hint: :match_pattern], pattern}

      arm_meta =
        [pattern: pattern_ast] ++
          if(guard, do: [guard: {:language_specific, [language: :python], guard}], else: []) ++
          location_meta(case_node)

      {:ok, {:match_arm, arm_meta, [body_ast]}}
    end
  end

  # Extract decorator names from decorator list.
  #
  # A decorator may be a bare name (`@property`), a dotted name
  # (`@app.route`) or a call (`@app.route("/")`). The *name* goes into
  # `:decorators`; a call's arguments additionally go into `:decorator_args`
  # so `@app.route("/")` does not round-trip to `@app.route`.
  defp extract_decorator_names(decorators) when is_list(decorators) do
    names =
      Enum.map(decorators, fn
        %{"_type" => "Name", "id" => name} -> name
        %{"_type" => "Attribute"} = attr -> format_attribute_name(attr)
        %{"_type" => "Call", "func" => func} -> extract_decorator_call_name(func)
        _ -> "unknown"
      end)

    {:ok, names}
  end

  defp extract_decorator_call_name(%{"_type" => "Name", "id" => name}), do: name

  defp extract_decorator_call_name(%{"_type" => "Attribute"} = attr),
    do: format_attribute_name(attr)

  # `@a.b(1)(2)` — the callee is itself a call, so there is no dotted name.
  # The name is left empty and the full expression is carried in
  # `:decorator_exprs` instead of collapsing to the literal `"unknown"`.
  defp extract_decorator_call_name(_), do: ""

  # Decorator call arguments, aligned with `:decorators`. `nil` marks a
  # decorator that is not a call.
  defp extract_decorator_args(decorators) when is_list(decorators) do
    args =
      Enum.map(decorators, fn
        %{"_type" => "Call", "args" => call_args, "keywords" => call_keywords} ->
          with {:ok, args_meta} <- transform_list(call_args),
               {:ok, kwargs_meta} <- transform_call_keywords(call_keywords || []) do
            # `@dataclass(frozen=True)` — the keyword arguments are part of
            # the decorator. They are kept alongside the positional ones as
            # `:param` nodes, distinguished by `kind: :keyword`.
            args_meta ++ kwargs_meta
          else
            _ -> nil
          end

        _ ->
          nil
      end)

    if Enum.all?(args, &is_nil/1), do: [], else: args
  end

  # Transform with statement items to bindings
  defp transform_with_items(items) when is_list(items) do
    items
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
      case transform_with_item(item) do
        {:ok, binding} -> {:cont, {:ok, [binding | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, bindings} -> {:ok, Enum.reverse(bindings)}
      error -> error
    end
  end

  defp transform_with_item(%{"context_expr" => expr, "optional_vars" => vars} = item) do
    with {:ok, expr_meta, _} <- transform(expr) do
      case vars do
        nil ->
          {:ok, expr_meta}

        var ->
          with {:ok, var_meta, _} <- transform(var) do
            {:ok,
             add_location(
               {:inline_match, [original_form: :with_item], [var_meta, expr_meta]},
               item
             )}
          end
      end
    end
  end

  defp transform_with_item(_), do: {:ok, {:literal, [subtype: :null], nil}}

  # Add location information from Python AST node to MetaAST
  defp add_location(ast, %{"lineno" => line} = node) do
    loc = %{line: line}

    loc =
      if Map.has_key?(node, "col_offset"), do: Map.put(loc, :col, node["col_offset"]), else: loc

    loc =
      if Map.has_key?(node, "end_lineno"),
        do: Map.put(loc, :end_line, node["end_lineno"]),
        else: loc

    loc =
      if Map.has_key?(node, "end_col_offset"),
        do: Map.put(loc, :end_col, node["end_col_offset"]),
        else: loc

    AST.with_location(ast, loc)
  end

  defp add_location(ast, _node), do: ast

  defp transform_list_comp(
         %{"_type" => "ListComp", "elt" => elt, "generators" => generators} = node
       ) do
    with {:ok, elt_meta, _} <- transform(elt),
         {:ok, gens_and_filters} <- transform_comprehension_generators(generators) do
      {:ok,
       add_location(
         {:comprehension, [comp_type: :list], [elt_meta | gens_and_filters]},
         node
       ), %{}}
    end
  end

  defp transform_simple_list_comp(node, target, iter, elt) do
    with {:ok, target_meta, _} <- transform(target),
         {:ok, iter_meta, _} <- transform(iter),
         {:ok, elt_meta, _} <- transform(elt) do
      # Convert to: {:collection_op, [op_type: :map], [lambda, collection]}
      #
      # A tuple target (`[x for x, y in pairs]`) cannot be named, so it is
      # kept as a `:pattern` param rather than collapsed to a placeholder —
      # `_x` used to replace the real destructuring.
      params =
        case target_meta do
          {:variable, _, name} -> [{:param, [], name}]
          pattern -> [{:param, [pattern: pattern], "_"}]
        end

      lambda = {:lambda, [params: params, captures: []], [elt_meta]}
      {:ok, add_location({:collection_op, [op_type: :map], [lambda, iter_meta]}, node), %{}}
    end
  end
end
