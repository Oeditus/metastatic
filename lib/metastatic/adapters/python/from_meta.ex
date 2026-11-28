defmodule Metastatic.Adapters.Python.FromMeta do
  @moduledoc """
  Transform MetaAST (M2) back to Python AST (M1).

  Implements the reification function ρ_Python that instantiates
  meta-level representations back into Python-specific AST structures.

  ## Transformation Strategy

  The transformation reverses the abstraction performed by `ToMeta`, using
  metadata to restore Python-specific information when needed.

  ### M2.1 (Core Layer) → Python AST
  - Literals, variables, operators, function calls, conditionals, blocks, early returns

  ### M2.2 (Extended Layer) → Python AST
  - Loops: {:loop, :while, ...} → While, {:loop, :for_each, ...} → For
  - Lambdas: {:lambda, params, captures, body} → Lambda
  - Collection ops: {:collection_op, :map, ...} → ListComp or map() call
  - Exception handling: {:exception_handling, ...} → Try

  ## Round-Trip Fidelity

  The transformation aims for high fidelity:
  - Metadata preserves line numbers and formatting hints
  - Default values are provided when metadata is absent
  """

  @doc """
  Transform MetaAST back to Python AST.

  Returns `{:ok, python_ast}` on success or `{:error, reason}` on failure.
  """
  @spec transform(term(), map()) :: {:ok, map()} | {:error, String.t()}

  # Literals - M2.1 Core Layer (New 3-tuple format)

  def transform({:literal, meta, value}, _metadata) when is_list(meta) do
    case Keyword.get(meta, :subtype) do
      :bytes ->
        {:ok, %{"_type" => "Constant", "value" => %{"__bytes__" => Base.encode64(value)}}}

      _ ->
        {:ok,
         %{"_type" => "Constant", "value" => value, "kind" => Keyword.get(meta, :string_kind)}}
    end
  end

  # String interpolation (f-strings) - M2.1 Core Layer
  #
  # `ToMeta` merges adjacent literal runs, so a `:string_interpolation` with a
  # single `:string` part is a plain string literal, not an f-string.
  def transform({:string_interpolation, _meta, [{:literal, meta, text}]}, _metadata)
      when is_list(meta) and is_binary(text) do
    {:ok, %{"_type" => "Constant", "value" => text, "kind" => nil}}
  end

  def transform({:string_interpolation, _meta, parts}, metadata) when is_list(parts) do
    with {:ok, values} <- transform_fstring_parts(parts, metadata) do
      {:ok, %{"_type" => "JoinedStr", "values" => values}}
    end
  end

  # Lists - M2.1 Core Layer (New 3-tuple format)
  def transform({:list, meta, elements}, metadata) when is_list(meta) do
    with {:ok, elements_py} <- transform_list(elements, metadata) do
      case Keyword.get(meta, :collection_type) do
        :set ->
          {:ok, %{"_type" => "Set", "elts" => elements_py}}

        _ ->
          {:ok, %{"_type" => "List", "elts" => elements_py, "ctx" => %{"_type" => "Load"}}}
      end
    end
  end

  # Maps (Dicts) - M2.1 Core Layer (New 3-tuple format)
  def transform({:map, meta, pairs}, metadata) when is_list(meta) do
    # Pairs are now {:pair, [], [key, value]} tuples
    {keys, values} =
      Enum.reduce(pairs, {[], []}, fn
        {:pair, _, [k, v]}, {ks, vs} -> {[k | ks], [v | vs]}
        # fallback for old tuple format
        {k, v}, {ks, vs} -> {[k | ks], [v | vs]}
      end)

    with {:ok, keys_py} <- transform_list(Enum.reverse(keys), metadata),
         {:ok, values_py} <- transform_list(Enum.reverse(values), metadata) do
      {:ok, %{"_type" => "Dict", "keys" => keys_py, "values" => values_py}}
    end
  end

  # Variables - M2.1 Core Layer (New 3-tuple format)
  def transform({:variable, meta, name}, _metadata) when is_list(meta) and is_binary(name) do
    {:ok, %{"_type" => "Name", "id" => name, "ctx" => %{"_type" => "Load"}}}
  end

  # Binary Operators - M2.1 Core Layer (New 3-tuple format)
  def transform({:binary_op, meta, [left, right]}, metadata) when is_list(meta) do
    category = Keyword.get(meta, :category)
    op = Keyword.get(meta, :operator)

    case category do
      :arithmetic ->
        transform_binop(op, left, right, metadata)

      :comparison ->
        transform_compare(op, left, right, metadata)

      :boolean ->
        transform_bool_op(op, left, right, metadata, Keyword.get(meta, :chained) == true)

      :bitwise ->
        transform_binop(op, left, right, metadata)
    end
  end

  # Unary Operators - M2.1 Core Layer (New 3-tuple format)
  def transform({:unary_op, meta, [operand]}, metadata) when is_list(meta) do
    category = Keyword.get(meta, :category)
    op = Keyword.get(meta, :operator)

    with {:ok, operand_py} <- transform(operand, metadata),
         {:ok, op_py} <- python_unary_op(category, op) do
      {:ok, %{"_type" => "UnaryOp", "op" => op_py, "operand" => operand_py}}
    end
  end

  # Function Calls - M2.1 Core Layer (New 3-tuple format)
  def transform({:function_call, meta, args}, metadata) when is_list(meta) do
    name = Keyword.get(meta, :name)
    receiver = Keyword.get(meta, :receiver)

    cond do
      # `[]` is the accessor `ToMeta` uses for a `Subscript`; rebuild the
      # original node rather than emitting a call to a function named `[]`.
      name == "[]" ->
        transform_subscript(args, metadata)

      # A callee that is an expression (`f(x).decode()`) is rebuilt from the
      # receiver recorded by `ToMeta`; the name is empty in that case.
      not is_nil(receiver) ->
        with {:ok, func_py} <- transform(receiver, metadata),
             {:ok, args_py} <- transform_list(args, metadata),
             {:ok, keywords_py} <-
               transform_call_keywords(Keyword.get(meta, :kwargs, []), metadata) do
          {:ok,
           %{"_type" => "Call", "func" => func_py, "args" => args_py, "keywords" => keywords_py}}
        end

      true ->
        with {:ok, func_py} <- build_function_ref(name),
             {:ok, args_py} <- transform_list(args, metadata),
             {:ok, keywords_py} <-
               transform_call_keywords(Keyword.get(meta, :kwargs, []), metadata) do
          {:ok,
           %{"_type" => "Call", "func" => func_py, "args" => args_py, "keywords" => keywords_py}}
        end
    end
  end

  # Conditionals - M2.1 Core Layer (New 3-tuple format)
  #
  # `:statement` (set by `ToMeta` for a Python `if` statement) decides between
  # an `If` statement and an `IfExp` ternary. Falling back to the shape alone
  # turned `if a: x = 1` into an `IfExp` whose branches were assignments,
  # which is not valid Python.
  def transform({:conditional, meta, [condition, then_branch, else_branch]}, metadata)
      when is_list(meta) do
    with {:ok, cond_py} <- transform(condition, metadata),
         {:ok, then_py} <- transform(then_branch, metadata),
         {:ok, else_py} <- transform_or_empty(else_branch, metadata) do
      if statement?(meta) do
        else_body = if else_py == [], do: [], else: wrap_in_list(else_py)

        {:ok,
         %{
           "_type" => "If",
           "test" => cond_py,
           "body" => wrap_in_list(then_py),
           "orelse" => else_body
         }}
      else
        {:ok, %{"_type" => "IfExp", "test" => cond_py, "body" => then_py, "orelse" => else_py}}
      end
    end
  end

  # Blocks - M2.1 Core Layer (New 3-tuple format)
  #
  # A block with `original_form: :with` is a Python `with` statement: the
  # leading children are `withitem` nodes and the last one is the body.
  def transform({:block, meta, statements}, metadata) when is_list(meta) do
    cond do
      Keyword.get(meta, :original_form) == :with ->
        transform_with_statement(statements, metadata)

      Keyword.get(meta, :original_form) == :multi_import ->
        transform_multi_import(statements, metadata)

      true ->
        with {:ok, stmts_py} <- transform_statement_list(statements, metadata) do
          stmts_py = restore_docstring(stmts_py, Keyword.get(meta, :docstring))

          case stmts_py do
            [] -> {:ok, %{"_type" => "Pass"}}
            [single] -> {:ok, single}
            multiple -> {:ok, %{"_type" => "Module", "body" => multiple, "type_ignores" => []}}
          end
        end
    end
  end

  # Early Returns - M2.1 Core Layer (New 3-tuple format)
  def transform({:early_return, meta, [value]}, metadata) when is_list(meta) do
    kind = Keyword.get(meta, :kind, :return)

    case kind do
      :return ->
        with {:ok, value_py} <- transform_or_nil(value, metadata) do
          {:ok, %{"_type" => "Return", "value" => value_py}}
        end

      :break ->
        {:ok, %{"_type" => "Break"}}

      :continue ->
        {:ok, %{"_type" => "Continue"}}
    end
  end

  # Assignments - M2.1 Core Layer (New 3-tuple format)
  #
  # A chained assignment (`a = b = c`) is nested by `ToMeta` — the inner
  # `:assignment` sits in the *value* slot — but Python's AST keeps it as one
  # `Assign` with several `targets`. Reifying the nesting literally produced
  # `a = \nb = c`, which is a syntax error, so the chain is flattened here.
  def transform({:assignment, meta, [target, value]}, metadata) when is_list(meta) do
    with {:ok, target_py} <- transform_assignment_target(target, metadata),
         {:ok, targets_py, value_py} <- flatten_assignment_chain(value, metadata) do
      case Keyword.get(meta, :annotation) do
        # `x: int = 1` — an annotated assignment is its own statement type.
        nil ->
          {:ok,
           %{"_type" => "Assign", "targets" => [target_py | targets_py], "value" => value_py}}

        annotation ->
          with {:ok, annotation_py} <- transform(annotation, metadata) do
            {:ok,
             %{
               "_type" => "AnnAssign",
               "target" => target_py,
               "annotation" => annotation_py,
               "value" => value_py,
               "simple" => 1
             }}
          end
      end
    end
  end

  # Augmented assignment — `x += 1`, `a @= b`. The operator category decides
  # whether it is an arithmetic, bitwise or matrix-multiply operator.
  def transform({:augmented_assignment, meta, [target, value]}, metadata)
      when is_list(meta) do
    category = Keyword.get(meta, :category, :arithmetic)
    op = Keyword.get(meta, :operator)

    with {:ok, target_py} <- transform_assignment_target(target, metadata),
         {:ok, value_py} <- transform(value, metadata),
         {:ok, op_py} <- python_augmented_op(category, op) do
      {:ok, %{"_type" => "AugAssign", "target" => target_py, "op" => op_py, "value" => value_py}}
    end
  end

  # Comprehensions — `[f(x) for x in xs if p(x)]`, dict/set/generator forms.
  #
  # The first child is the body; the rest are `:generator` and `:filter` nodes
  # in source order. Python's AST groups a generator with the filters that
  # follow it, so they are re-nested here into one `comprehension` node per
  # generator clause.
  def transform({:comprehension, meta, [body | clauses]}, metadata) when is_list(meta) do
    with {:ok, generators} <- build_comprehensions(clauses, metadata) do
      case Keyword.get(meta, :comp_type) do
        :dict ->
          # A dict comprehension body is a `:pair` node, not a `:tuple`: the
          # two halves are the key and the value, so they must be reified
          # separately rather than as a `(key, value)` tuple expression.
          case body do
            {:pair, _pair_meta, [key, value]} ->
              with {:ok, key_py} <- transform(key, metadata),
                   {:ok, value_py} <- transform(value, metadata) do
                {:ok,
                 %{
                   "_type" => "DictComp",
                   "key" => key_py,
                   "value" => value_py,
                   "generators" => generators
                 }}
              end

            _ ->
              {:error, "A dict comprehension body must be a :pair node"}
          end

        comp_type ->
          with {:ok, body_py} <- transform(body, metadata) do
            build_comprehension(comp_type, body_py, generators)
          end
      end
    end
  end

  # Pattern matching (Python 3.10+ `match` statement). The pattern itself is
  # preserved verbatim by `ToMeta` as `:language_specific`, so it is restored
  # as-is; the guard (if any) is a MetaAST expression.
  def transform({:pattern_match, _meta, [scrutinee | arms]}, metadata)
      when is_list(arms) do
    with {:ok, subject_py} <- transform(scrutinee, metadata),
         {:ok, cases_py} <- transform_match_arms(arms, metadata) do
      {:ok, %{"_type" => "Match", "subject" => subject_py, "cases" => cases_py}}
    end
  end

  def transform({:pattern_match, _meta, _children}, _metadata) do
    {:error, "A :pattern_match node needs a scrutinee and at least one arm"}
  end

  # Generators / filters outside a comprehension have no Python statement
  # form; they are reported rather than silently dropped.
  def transform({:generator, _meta, _children}, _metadata) do
    {:error, "A :generator node is only valid inside a :comprehension"}
  end

  def transform({:filter, _meta, _children}, _metadata) do
    {:error, "A :filter node is only valid inside a :comprehension"}
  end

  # Tuples - M2.1 Core Layer (New 3-tuple format)
  def transform({:tuple, meta, elements}, metadata) when is_list(meta) do
    with {:ok, elts_py} <- transform_list(elements, metadata) do
      {:ok, %{"_type" => "Tuple", "elts" => elts_py, "ctx" => %{"_type" => "Load"}}}
    end
  end

  # Pairs (used in maps)
  def transform({:pair, meta, [key, value]}, metadata) when is_list(meta) do
    # Pairs are handled within map transformation, but if called directly:
    with {:ok, key_py} <- transform(key, metadata),
         {:ok, value_py} <- transform(value, metadata) do
      {:ok, {key_py, value_py}}
    end
  end

  # Loops - M2.2 Extended Layer (New 3-tuple format)
  def transform({:loop, meta, children}, metadata) when is_list(meta) do
    loop_type = Keyword.get(meta, :loop_type)

    case {loop_type, children} do
      {:while, [condition, body]} ->
        with {:ok, test_py} <- transform(condition, metadata),
             {:ok, body_py} <- transform_to_body(body, metadata),
             {:ok, else_py} <- transform_to_body_or_empty(Keyword.get(meta, :orelse), metadata) do
          {:ok, %{"_type" => "While", "test" => test_py, "body" => body_py, "orelse" => else_py}}
        end

      {:for_each, [iterator, collection, body]} ->
        with {:ok, target_py} <- transform(iterator, metadata),
             {:ok, iter_py} <- transform(collection, metadata),
             {:ok, body_py} <- transform_to_body(body, metadata),
             {:ok, else_py} <- transform_to_body_or_empty(Keyword.get(meta, :orelse), metadata) do
          {:ok,
           %{
             "_type" => "For",
             "target" => target_py,
             "iter" => iter_py,
             "body" => body_py,
             "orelse" => else_py
           }}
        end
    end
  end

  # Lambdas - M2.2 Extended Layer (New 3-tuple format)
  def transform({:lambda, meta, [body]}, metadata) when is_list(meta) do
    params = Keyword.get(meta, :params, [])

    with {:ok, body_py} <- transform(body, metadata),
         {:ok, args_node} <- build_lambda_args(params) do
      {:ok, %{"_type" => "Lambda", "args" => args_node, "body" => body_py}}
    end
  end

  # Collection Operations - M2.2 Extended Layer (New 3-tuple format)
  def transform({:collection_op, meta, [func, collection]}, metadata) when is_list(meta) do
    op_type = Keyword.get(meta, :op_type)

    case op_type do
      :map ->
        # Check if func is a simple lambda
        case func do
          {:lambda, lambda_meta, [body]} when is_list(lambda_meta) ->
            params = Keyword.get(lambda_meta, :params, [])

            case params do
              [param] ->
                with {:ok, elt_py} <- transform(body, metadata),
                     {:ok, iter_py} <- transform(collection, metadata),
                     {:ok, target} <- comprehension_target(param, metadata) do
                  generator = %{
                    "_type" => "comprehension",
                    "target" => target,
                    "iter" => iter_py,
                    "ifs" => [],
                    "is_async" => 0
                  }

                  {:ok, %{"_type" => "ListComp", "elt" => elt_py, "generators" => [generator]}}
                end

              _ ->
                transform_map_fallback(func, collection, metadata)
            end

          _ ->
            transform_map_fallback(func, collection, metadata)
        end

      :filter ->
        with {:ok, pred_py} <- transform(func, metadata),
             {:ok, collection_py} <- transform(collection, metadata) do
          filter_func = %{"_type" => "Name", "id" => "filter", "ctx" => %{"_type" => "Load"}}

          {:ok,
           %{
             "_type" => "Call",
             "func" => filter_func,
             "args" => [pred_py, collection_py],
             "keywords" => []
           }}
        end
    end
  end

  # Collection op with initial value (reduce)
  def transform({:collection_op, meta, [func, collection, initial]}, metadata)
      when is_list(meta) do
    op_type = Keyword.get(meta, :op_type)

    case op_type do
      :reduce ->
        with {:ok, func_py} <- transform(func, metadata),
             {:ok, collection_py} <- transform(collection, metadata),
             {:ok, initial_py} <- transform(initial, metadata) do
          # Build functools.reduce reference
          reduce_func = %{
            "_type" => "Attribute",
            "value" => %{"_type" => "Name", "id" => "functools", "ctx" => %{"_type" => "Load"}},
            "attr" => "reduce",
            "ctx" => %{"_type" => "Load"}
          }

          {:ok,
           %{
             "_type" => "Call",
             "func" => reduce_func,
             "args" => [func_py, collection_py, initial_py],
             "keywords" => []
           }}
        end
    end
  end

  # Inline match — `x := expr` (walrus) or a `with ... as x` item.
  #
  # The two forms are distinguished by `:original_form`: a `with_item` is
  # rebuilt as a `withitem` (the `With` node owns the statement), while a
  # walrus becomes a `NamedExpr` expression.
  def transform({:inline_match, meta, [target, value]}, metadata) when is_list(meta) do
    with {:ok, target_py} <- transform_assignment_target(target, metadata),
         {:ok, value_py} <- transform(value, metadata) do
      case Keyword.get(meta, :original_form) do
        :with_item ->
          {:ok,
           %{"_type" => "withitem", "context_expr" => value_py, "optional_vars" => target_py}}

        _ ->
          {:ok, %{"_type" => "NamedExpr", "target" => target_py, "value" => value_py}}
      end
    end
  end

  # Throw — `raise X` / bare `raise`.
  def transform({:throw, meta, []}, _metadata) when is_list(meta) do
    {:ok, %{"_type" => "Raise", "exc" => nil, "cause" => nil}}
  end

  def transform({:throw, meta, [exception]}, metadata) when is_list(meta) do
    with {:ok, exc_py} <- transform(exception, metadata),
         {:ok, cause_py} <- transform_or_nil(Keyword.get(meta, :cause), metadata) do
      {:ok, %{"_type" => "Raise", "exc" => exc_py, "cause" => cause_py}}
    end
  end

  # Exception Handling - M2.2 Extended Layer (New 3-tuple format)
  def transform({:exception_handling, meta, [try_block, rescue_clauses, finally_block]}, metadata)
      when is_list(meta) do
    with {:ok, body_py} <- transform_to_body(try_block, metadata),
         {:ok, handlers_py} <- transform_exception_handlers(rescue_clauses, metadata),
         {:ok, else_py} <- transform_to_body_or_empty(Keyword.get(meta, :orelse), metadata),
         {:ok, finally_py} <- transform_to_body_or_empty(finally_block, metadata) do
      {:ok,
       %{
         "_type" => "Try",
         "body" => body_py,
         "handlers" => handlers_py,
         "orelse" => else_py,
         "finalbody" => finally_py
       }}
    end
  end

  # Function Definitions - M2.2s Structural Layer (New 3-tuple format)
  def transform({:function_def, meta, body}, metadata) when is_list(meta) do
    name = Keyword.get(meta, :name, "_")
    params = Keyword.get(meta, :params, [])

    with {:ok, body_py} <- transform_statement_list(body, metadata),
         {:ok, decorator_list} <-
           transform_decorators(
             Keyword.get(meta, :decorators, []),
             Keyword.get(meta, :decorator_args, []),
             Keyword.get(meta, :decorator_exprs, [])
           ),
         {:ok, args_node} <- build_function_args(params, meta) do
      body_py = restore_docstring(body_py, Keyword.get(meta, :docstring))

      {:ok,
       %{
         "_type" =>
           if(Keyword.get(meta, :async) == true, do: "AsyncFunctionDef", else: "FunctionDef"),
         "name" => name,
         "args" => args_node,
         "body" => body_py,
         "decorator_list" => decorator_list,
         "returns" => annotation_py(Keyword.get(meta, :return_type)),
         "lineno" => Keyword.get(meta, :line, 0),
         "col_offset" => Keyword.get(meta, :col, 0)
       }}
    end
  end

  # Container (Class) - M2.2s Structural Layer (New 3-tuple format)
  def transform({:container, meta, body}, metadata) when is_list(meta) do
    container_type = Keyword.get(meta, :container_type)

    case container_type do
      :class ->
        name = Keyword.get(meta, :name, "_")

        with {:ok, body_py} <- transform_statement_list(body, metadata),
             {:ok, decorator_list} <-
               transform_decorators(
                 Keyword.get(meta, :decorators, []),
                 Keyword.get(meta, :decorator_args, []),
                 Keyword.get(meta, :decorator_exprs, [])
               ),
             {:ok, bases} <- build_class_bases(meta),
             {:ok, class_keywords} <-
               transform_call_keywords(Keyword.get(meta, :class_keywords, []), metadata) do
          {:ok,
           %{
             "_type" => "ClassDef",
             "name" => name,
             "bases" => bases,
             "keywords" => class_keywords,
             "body" => body_py,
             "decorator_list" => decorator_list,
             "lineno" => Keyword.get(meta, :line, 0),
             "col_offset" => Keyword.get(meta, :col, 0)
           }}
        end

      _ ->
        {:error, "Unsupported container type for Python: #{inspect(container_type)}"}
    end
  end

  # Attribute Access - M2.2s Structural Layer (New 3-tuple format)
  def transform({:attribute_access, meta, [receiver]}, metadata) when is_list(meta) do
    attr = Keyword.get(meta, :attribute, "_")

    with {:ok, receiver_py} <- transform(receiver, metadata) do
      {:ok,
       %{
         "_type" => "Attribute",
         "value" => receiver_py,
         "attr" => attr,
         "ctx" => %{"_type" => "Load"}
       }}
    end
  end

  # Generators (yield / yield from) - M2.2 Extended Layer
  def transform({:yield, meta, children}, metadata) when is_list(meta) and is_list(children) do
    case {Keyword.get(meta, :kind, :yield), children} do
      {:yield_from, [value]} ->
        with {:ok, value_py} <- transform(value, metadata) do
          {:ok, %{"_type" => "YieldFrom", "value" => value_py}}
        end

      {_, []} ->
        {:ok, %{"_type" => "Yield", "value" => nil}}

      {_, [value]} ->
        with {:ok, value_py} <- transform(value, metadata) do
          {:ok, %{"_type" => "Yield", "value" => value_py}}
        end
    end
  end

  # Import - M2.2s Structural Layer (New 3-tuple format)
  def transform({:import, meta, []}, _metadata) when is_list(meta) do
    source = Keyword.get(meta, :source)
    names = Keyword.get(meta, :names)
    alias_name = Keyword.get(meta, :alias)

    case names do
      nil ->
        # Simple module import: import os
        alias_node = %{
          "_type" => "alias",
          "name" => source,
          "asname" => alias_name
        }

        {:ok, %{"_type" => "Import", "names" => [alias_node]}}

      names_list when is_list(names_list) ->
        # From import: from os.path import join, or `... import join as j`
        # when `:name_aliases` carries the positional `as` names.
        name_aliases = Keyword.get(meta, :name_aliases, [])

        alias_nodes =
          names_list
          |> Enum.with_index()
          |> Enum.map(fn {name, index} ->
            %{
              "_type" => "alias",
              "name" => name,
              "asname" => Enum.at(name_aliases, index)
            }
          end)

        level = Keyword.get(meta, :relative_level, 0)

        {:ok,
         %{
           "_type" => "ImportFrom",
           "module" => source,
           "names" => alias_nodes,
           "level" => level
         }}
    end
  end

  # Language-Specific - M2.3 Native Layer (New 3-tuple format)
  def transform({:language_specific, meta, native_ast}, _metadata) when is_list(meta) do
    language = Keyword.get(meta, :language)

    case language do
      :python -> {:ok, native_ast}
      other -> {:error, "Cannot reify #{other} language-specific construct to Python"}
    end
  end

  # Catch-all

  def transform(unknown, _metadata) do
    {:error, "Unsupported MetaAST construct: #{inspect(unknown)}"}
  end

  # Helper Functions

  # `import a, b` — merge the per-module `:import` nodes back into one
  # `Import` with several aliases.
  defp transform_multi_import(statements, metadata) do
    with {:ok, imports} <- transform_list(statements, metadata) do
      aliases =
        Enum.flat_map(imports, fn
          %{"_type" => "Import", "names" => names} -> names
          other -> [other]
        end)

      {:ok, %{"_type" => "Import", "names" => aliases}}
    end
  end

  # Collect the targets of a nested assignment chain, innermost value last.
  defp flatten_assignment_chain({:assignment, meta, [target, value]}, metadata)
       when is_list(meta) do
    with {:ok, target_py} <- transform_assignment_target(target, metadata),
         {:ok, targets_py, value_py} <- flatten_assignment_chain(value, metadata) do
      {:ok, [target_py | targets_py], value_py}
    end
  end

  defp flatten_assignment_chain(value, metadata) do
    with {:ok, value_py} <- transform(value, metadata) do
      {:ok, [], value_py}
    end
  end

  defp build_comprehension(:set, body_py, generators) do
    {:ok, %{"_type" => "SetComp", "elt" => body_py, "generators" => generators}}
  end

  defp build_comprehension(:generator, body_py, generators) do
    {:ok, %{"_type" => "GeneratorExp", "elt" => body_py, "generators" => generators}}
  end

  defp build_comprehension(_list, body_py, generators) do
    {:ok, %{"_type" => "ListComp", "elt" => body_py, "generators" => generators}}
  end

  defp transform_map_fallback(func, collection, metadata) do
    with {:ok, func_py} <- transform(func, metadata),
         {:ok, collection_py} <- transform(collection, metadata) do
      map_func = %{"_type" => "Name", "id" => "map", "ctx" => %{"_type" => "Load"}}

      {:ok,
       %{
         "_type" => "Call",
         "func" => map_func,
         "args" => [func_py, collection_py],
         "keywords" => []
       }}
    end
  end

  defp transform_assignment_target({:variable, meta, name}, _metadata)
       when is_list(meta) and is_binary(name) do
    {:ok, %{"_type" => "Name", "id" => name, "ctx" => %{"_type" => "Store"}}}
  end

  defp transform_assignment_target({:tuple, meta, elements}, metadata) when is_list(meta) do
    with {:ok, elts_py} <- transform_assignment_targets(elements, metadata) do
      {:ok, %{"_type" => "Tuple", "elts" => elts_py, "ctx" => %{"_type" => "Store"}}}
    end
  end

  # `[a, b] = x` — list destructuring. `ToMeta` maps it to a `:list` node, so
  # the target rebuilds as a `List` with `Store` context.
  defp transform_assignment_target({:list, meta, elements}, metadata) when is_list(meta) do
    with {:ok, elts_py} <- transform_assignment_targets(elements, metadata) do
      {:ok, %{"_type" => "List", "elts" => elts_py, "ctx" => %{"_type" => "Store"}}}
    end
  end

  # `obj[i] = v` — a subscript target. `ToMeta` renders a subscript as a call
  # to `[]`, so the Store context has to be applied to the rebuilt node.
  defp transform_assignment_target({:function_call, meta, args}, metadata)
       when is_list(meta) do
    if Keyword.get(meta, :name) == "[]" do
      with {:ok, subscript} <- transform_subscript(args, metadata) do
        {:ok, put_in(subscript["ctx"], %{"_type" => "Store"})}
      end
    else
      {:error, "Unsupported assignment target: a function call is not assignable"}
    end
  end

  # `obj.attr = v` — an attribute target.
  defp transform_assignment_target({:attribute_access, meta, [receiver]}, metadata)
       when is_list(meta) do
    with {:ok, receiver_py} <- transform(receiver, metadata) do
      {:ok,
       %{
         "_type" => "Attribute",
         "value" => receiver_py,
         "attr" => Keyword.get(meta, :attribute),
         "ctx" => %{"_type" => "Store"}
       }}
    end
  end

  # `a, *rest = items` — a starred target. `ToMeta` preserves the `Starred`
  # node verbatim as `:language_specific`; the inner value needs its `Store`
  # context, which the preserved node already carries.
  defp transform_assignment_target(
         {:language_specific, meta, %{"_type" => "Starred"} = native},
         _metadata
       )
       when is_list(meta) do
    {:ok, native}
  end

  defp transform_assignment_target(target, _metadata) do
    {:error, "Unsupported assignment target: #{inspect(target)}"}
  end

  defp transform_assignment_targets(items, metadata) when is_list(items) do
    items
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
      case transform_assignment_target(item, metadata) do
        {:ok, py} -> {:cont, {:ok, [py | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, items} -> {:ok, Enum.reverse(items)}
      error -> error
    end
  end

  # Call keywords: `:param` nodes carrying `kind: :keyword` (a named
  # argument) or `kind: :keyword_variadic` (a `**expr` unpacking).
  defp transform_call_keywords(params, metadata) when is_list(params) do
    params
    |> Enum.reduce_while({:ok, []}, fn param, {:ok, acc} ->
      case transform_call_keyword(param, metadata) do
        {:ok, keyword} -> {:cont, {:ok, [keyword | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, keywords} -> {:ok, Enum.reverse(keywords)}
      error -> error
    end
  end

  defp transform_call_keywords(_params, _metadata), do: {:ok, []}

  defp transform_call_keyword({:param, meta, name}, metadata) when is_list(meta) do
    default = Keyword.get(meta, :default)

    case Keyword.get(meta, :kind, :keyword) do
      :keyword_variadic ->
        with {:ok, value_py} <- transform_or_nil(default, metadata) do
          {:ok, %{"_type" => "keyword", "arg" => nil, "value" => value_py}}
        end

      _ ->
        with {:ok, value_py} <- transform_or_nil(default, metadata) do
          {:ok, %{"_type" => "keyword", "arg" => name, "value" => value_py}}
        end
    end
  end

  defp transform_call_keyword(other, _metadata) do
    {:error, "Unsupported call keyword: #{inspect(other)}"}
  end

  # F-string parts: literal text becomes a `Constant`, everything else is
  # wrapped in a `FormattedValue` (the shape `JoinedStr` requires).
  defp transform_fstring_parts(parts, metadata) when is_list(parts) do
    parts
    |> Enum.reduce_while({:ok, []}, fn part, {:ok, acc} ->
      case transform_fstring_part(part, metadata) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end
  end

  defp transform_fstring_part({:literal, meta, text}, _metadata)
       when is_list(meta) and is_binary(text) do
    {:ok, %{"_type" => "Constant", "value" => text, "kind" => nil}}
  end

  defp transform_fstring_part(part, metadata) do
    with {:ok, value_py} <- transform(part, metadata) do
      {:ok,
       %{
         "_type" => "FormattedValue",
         "value" => value_py,
         "conversion" => fstring_conversion(part),
         "format_spec" => fstring_format_spec(part)
       }}
    end
  end

  defp fstring_conversion({_type, meta, _children}) when is_list(meta) do
    Keyword.get(meta, :conversion, -1)
  end

  defp fstring_conversion(_), do: -1

  defp fstring_format_spec({_type, meta, _children}) when is_list(meta) do
    case Keyword.get(meta, :format_spec) do
      nil ->
        nil

      text when is_binary(text) ->
        %{
          "_type" => "JoinedStr",
          "values" => [%{"_type" => "Constant", "value" => text, "kind" => nil}]
        }

      # A format spec that itself interpolates (`f"{x:{width}}"`).
      {:string_interpolation, _, parts} ->
        case transform_fstring_parts(parts, %{}) do
          {:ok, values} -> %{"_type" => "JoinedStr", "values" => values}
          _ -> nil
        end

      other ->
        case transform(other, %{}) do
          {:ok, py} -> py
          _ -> nil
        end
    end
  end

  defp fstring_format_spec(_), do: nil

  defp transform_list(items, metadata) when is_list(items) do
    items
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
      case transform(item, metadata) do
        {:ok, py} -> {:cont, {:ok, [py | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, items} -> {:ok, Enum.reverse(items)}
      error -> error
    end
  end

  defp transform_or_nil(nil, _metadata), do: {:ok, nil}
  defp transform_or_nil(value, metadata), do: transform(value, metadata)

  defp transform_or_empty(nil, _metadata), do: {:ok, []}
  defp transform_or_empty(value, metadata), do: transform(value, metadata)

  defp wrap_in_list(item) when is_map(item), do: [item]
  defp wrap_in_list(items) when is_list(items), do: items

  defp statement?(meta), do: Keyword.get(meta, :statement) == true

  # A docstring is a bare string expression as the first statement of a body.
  # `ToMeta` records it in `:docstring`; without this the leading string was
  # reified as an expression statement and unparsed to `def f():'Doc.'`.
  defp restore_docstring(body_py, nil), do: body_py

  # The docstring is still the first body statement (it is kept in the tree for
  # fidelity), so it only needs to be *rewrapped* as an `Expr` — prepending a
  # second copy duplicated it, which pushed the real first statement down and
  # made the body structurally wrong.
  defp restore_docstring(body_py, text) when is_binary(text) and is_list(body_py) do
    doc = %{
      "_type" => "Expr",
      "value" => %{"_type" => "Constant", "value" => text, "kind" => nil}
    }

    case body_py do
      # Already a statement (`as_statement/1` wrapped it).
      [%{"_type" => "Expr", "value" => %{"value" => ^text}} | rest] -> [doc | rest]
      # Still a bare expression.
      [%{"_type" => "Constant", "value" => ^text} | rest] -> [doc | rest]
      # Not present at all: prepend it.
      _ -> [doc | body_py]
    end
  end

  defp restore_docstring(body_py, _), do: body_py

  # A `with` statement is a block whose leading children are `withitem`
  # nodes and whose last child is the body.
  defp transform_with_statement([], _metadata) do
    {:ok, %{"_type" => "With", "items" => [], "body" => [%{"_type" => "Pass"}]}}
  end

  defp transform_with_statement(statements, metadata) when is_list(statements) do
    {item_nodes, body_nodes} = Enum.split(statements, -1)

    with {:ok, items_py} <- transform_list(item_nodes, metadata),
         {:ok, body_py} <- transform_to_body(List.first(body_nodes), metadata) do
      {:ok, %{"_type" => "With", "items" => items_py, "body" => body_py}}
    end
  end

  # Decorator names are stored as strings by `ToMeta` (`"app.route"`,
  # `"staticmethod"`); rebuild the expression each one names.
  # Class bases. `:base_exprs` holds the full base expressions (so
  # `class A(B[int])` keeps its subscript); `:bases` is the fallback for
  # MetaAST produced before that key existed.
  defp build_class_bases(meta) do
    case Keyword.get(meta, :base_exprs) do
      [_ | _] = exprs ->
        exprs
        |> Enum.reduce_while({:ok, []}, fn expr, {:ok, acc} ->
          case transform(expr, %{}) do
            {:ok, py} -> {:cont, {:ok, [py | acc]}}
            {:error, _} = err -> {:halt, err}
          end
        end)
        |> case do
          {:ok, bases} -> {:ok, Enum.reverse(bases)}
          error -> error
        end

      _ ->
        {:ok,
         Enum.map(Keyword.get(meta, :bases, []), fn base_name ->
           %{"_type" => "Name", "id" => base_name, "ctx" => %{"_type" => "Load"}}
         end)}
    end
  end

  defp transform_decorators(names, args, exprs) when is_list(names) do
    # `:decorator_exprs` carries the full expression for decorators whose
    # callee is not a plain dotted name (`@a.b(1)(2)`).
    expr_map = Map.new(exprs)

    names
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {name, index}, {:ok, acc} ->
      case build_decorator(name, Enum.at(args, index), Map.get(expr_map, index)) do
        {:ok, ref} -> {:cont, {:ok, [ref | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, decorators} -> {:ok, Enum.reverse(decorators)}
      error -> error
    end
  end

  defp transform_decorators(_names, _args, _exprs), do: {:ok, []}

  # Re-nest a flat `[generator, filter, ...]` list into Python's
  # `comprehension` nodes (one per generator, carrying its own filters).
  defp build_comprehensions(clauses, metadata) when is_list(clauses) do
    clauses
    |> Enum.reduce_while({:ok, []}, fn
      {:generator, gen_meta, [target, collection]}, {:ok, acc} ->
        with {:ok, target_py} <- transform_assignment_target(target, metadata),
             {:ok, iter_py} <- transform(collection, metadata) do
          generator = %{
            "_type" => "comprehension",
            "target" => target_py,
            "iter" => iter_py,
            "ifs" => [],
            "is_async" => if(Keyword.get(gen_meta, :async) == true, do: 1, else: 0)
          }

          {:cont, {:ok, acc ++ [generator]}}
        else
          {:error, _} = err -> {:halt, err}
        end

      {:filter, _meta, [condition]}, {:ok, acc} ->
        case transform(condition, metadata) do
          {:ok, condition_py} ->
            case List.last(acc) do
              nil ->
                {:halt, {:error, "A comprehension filter must follow a generator"}}

              generator ->
                updated = Map.update!(generator, "ifs", &(&1 ++ [condition_py]))
                {:cont, {:ok, List.replace_at(acc, -1, updated)}}
            end

          {:error, _} = err ->
            {:halt, err}
        end

      other, _acc ->
        {:halt, {:error, "Unsupported comprehension clause: #{inspect(other)}"}}
    end)
  end

  defp build_comprehensions(_clauses, _metadata), do: {:ok, []}

  # `match` arms → `match_case` nodes. The pattern is the `:pattern` metadata
  # (a `:language_specific` node holding the native pattern), the guard is
  # `:guard`, and the body is the arm's single child.
  defp transform_match_arms(arms, metadata) when is_list(arms) do
    arms
    |> Enum.reduce_while({:ok, []}, fn
      {:match_arm, arm_meta, [body]}, {:ok, acc} when is_list(arm_meta) ->
        with {:ok, pattern_py} <- transform_pattern(Keyword.get(arm_meta, :pattern)),
             {:ok, guard_py} <- transform_guard(Keyword.get(arm_meta, :guard), metadata),
             {:ok, body_py} <- transform_to_body(body, metadata) do
          match_case = %{
            "_type" => "match_case",
            "pattern" => pattern_py,
            "guard" => guard_py,
            "body" => body_py
          }

          {:cont, {:ok, acc ++ [match_case]}}
        else
          {:error, _} = err -> {:halt, err}
        end

      other, _acc ->
        {:halt, {:error, "Unsupported match arm: #{inspect(other)}"}}
    end)
  end

  defp transform_pattern(nil), do: {:ok, %{"_type" => "MatchAs", "pattern" => nil, "name" => nil}}

  defp transform_pattern(pattern), do: transform(pattern, %{})

  defp transform_guard(nil, _metadata), do: {:ok, nil}
  defp transform_guard(guard, metadata), do: transform(guard, metadata)

  # Augmented-assignment operators. `ToMeta` reports the same category/operator
  # pair as the corresponding binary operator.
  defp python_augmented_op(:bitwise, op), do: python_binop(op)
  defp python_augmented_op(:arithmetic, op), do: python_binop(op)
  defp python_augmented_op(_category, op), do: python_binop(op)

  # The target of a `map` collection op. A `:pattern` param (a destructuring
  # target such as `[x for x, y in pairs]`) is reified as an assignment
  # target; otherwise the param's name becomes a plain `Name`.
  defp comprehension_target({:param, param_meta, name}, metadata) when is_list(param_meta) do
    case Keyword.get(param_meta, :pattern) do
      nil ->
        {:ok, %{"_type" => "Name", "id" => name, "ctx" => %{"_type" => "Store"}}}

      pattern ->
        transform_assignment_target(pattern, metadata)
    end
  end

  defp comprehension_target(_param, _metadata) do
    {:ok, %{"_type" => "Name", "id" => "_x", "ctx" => %{"_type" => "Store"}}}
  end

  # A decorator with call arguments (`@app.route("/")`) must be rebuilt as a
  # `Call`, not as the bare name.
  defp build_decorator(_name, _args, expr) when not is_nil(expr) do
    transform(expr, %{})
  end

  defp build_decorator(name, nil, _expr) do
    build_function_ref(name)
  end

  defp build_decorator(name, args, _expr) when is_list(args) do
    # Positional arguments and keyword arguments are both stored as `:param`
    # nodes; `kind: :keyword` marks the ones that belong in `keywords`.
    {positional, keywords} =
      Enum.split_with(args, fn
        {:param, param_meta, _name} when is_list(param_meta) ->
          Keyword.get(param_meta, :kind) != :keyword

        _ ->
          true
      end)

    with {:ok, func_py} <- build_function_ref(name),
         {:ok, args_py} <- transform_list(positional, %{}),
         {:ok, keywords_py} <- transform_call_keywords(keywords, %{}) do
      {:ok, %{"_type" => "Call", "func" => func_py, "args" => args_py, "keywords" => keywords_py}}
    end
  end

  defp build_decorator(name, _, _expr), do: build_function_ref(name)

  # Operator transformations

  defp transform_binop(op, left, right, metadata) do
    with {:ok, left_py} <- transform(left, metadata),
         {:ok, right_py} <- transform(right, metadata),
         {:ok, op_py} <- python_binop(op) do
      {:ok, %{"_type" => "BinOp", "op" => op_py, "left" => left_py, "right" => right_py}}
    end
  end

  defp transform_compare(op, left, right, metadata) do
    with {:ok, left_py} <- transform(left, metadata),
         {:ok, right_py} <- transform(right, metadata),
         {:ok, op_py} <- python_compare_op(op) do
      {:ok,
       %{"_type" => "Compare", "left" => left_py, "ops" => [op_py], "comparators" => [right_py]}}
    end
  end

  # `{:function_call, [name: "[]"], [receiver, index]}` is how `ToMeta`
  # represents a Python `Subscript`. Rebuild `obj[index]`, turning a
  # `:range`-with-`:kind == :slice` index back into a `Slice` node.
  defp transform_subscript([receiver, index], metadata) do
    with {:ok, receiver_py} <- transform(receiver, metadata),
         {:ok, index_py} <- transform_slice_index(index, metadata) do
      {:ok,
       %{
         "_type" => "Subscript",
         "value" => receiver_py,
         "slice" => index_py,
         "ctx" => %{"_type" => "Load"}
       }}
    end
  end

  defp transform_subscript(args, _metadata) do
    {:error, "Subscript expects [receiver, index], got #{length(args)} children"}
  end

  defp transform_slice_index({:range, meta, [lower, upper]}, metadata) do
    with {:ok, lower_py} <- transform_or_none(lower, metadata),
         {:ok, upper_py} <- transform_or_none(upper, metadata),
         {:ok, step_py} <- transform_or_none(Keyword.get(meta, :step), metadata) do
      {:ok, %{"_type" => "Slice", "lower" => lower_py, "upper" => upper_py, "step" => step_py}}
    end
  end

  defp transform_slice_index(index, metadata), do: transform(index, metadata)

  defp transform_or_none(nil, _metadata), do: {:ok, nil}
  defp transform_or_none(node, metadata), do: transform(node, metadata)

  # `and` / `or` are n-ary in Python's AST (`BoolOp.values`), but `ToMeta`
  # chains them into binary ops (`a and b and c` → `(a and b) and c`), marking
  # the chain with `:chained`. Only a marked chain is flattened back into one
  # n-ary `BoolOp`; a genuinely nested `a and (b and c)` keeps its nesting.
  defp transform_bool_op(op, left, right, metadata, chained?) do
    with {:ok, op_py} <- python_bool_op(op),
         {:ok, left_py} <- transform(left, metadata),
         {:ok, right_py} <- transform(right, metadata) do
      values =
        if chained? do
          flatten_bool_operands(op_py, left_py) ++ [right_py]
        else
          [left_py, right_py]
        end

      {:ok, %{"_type" => "BoolOp", "op" => op_py, "values" => values}}
    end
  end

  # A left operand that is the *same* boolean operator continues the chain.
  defp flatten_bool_operands(op_py, %{"_type" => "BoolOp", "op" => op_py, "values" => values}) do
    values
  end

  defp flatten_bool_operands(_op_py, node), do: [node]

  defp python_binop(:+), do: {:ok, %{"_type" => "Add"}}
  defp python_binop(:-), do: {:ok, %{"_type" => "Sub"}}
  defp python_binop(:*), do: {:ok, %{"_type" => "Mult"}}
  defp python_binop(:/), do: {:ok, %{"_type" => "Div"}}
  defp python_binop(:div), do: {:ok, %{"_type" => "FloorDiv"}}
  defp python_binop(:rem), do: {:ok, %{"_type" => "Mod"}}
  defp python_binop(:**), do: {:ok, %{"_type" => "Pow"}}
  defp python_binop(:@), do: {:ok, %{"_type" => "MatMult"}}
  defp python_binop(:band), do: {:ok, %{"_type" => "BitAnd"}}
  defp python_binop(:bor), do: {:ok, %{"_type" => "BitOr"}}
  defp python_binop(:bxor), do: {:ok, %{"_type" => "BitXor"}}
  defp python_binop(:bsl), do: {:ok, %{"_type" => "LShift"}}
  defp python_binop(:bsr), do: {:ok, %{"_type" => "RShift"}}
  defp python_binop(op), do: {:error, "Unsupported arithmetic operator: #{op}"}

  defp python_compare_op(:==), do: {:ok, %{"_type" => "Eq"}}
  defp python_compare_op(:!=), do: {:ok, %{"_type" => "NotEq"}}
  defp python_compare_op(:<), do: {:ok, %{"_type" => "Lt"}}
  defp python_compare_op(:<=), do: {:ok, %{"_type" => "LtE"}}
  defp python_compare_op(:>), do: {:ok, %{"_type" => "Gt"}}
  defp python_compare_op(:>=), do: {:ok, %{"_type" => "GtE"}}
  defp python_compare_op(:===), do: {:ok, %{"_type" => "Is"}}
  defp python_compare_op(:!==), do: {:ok, %{"_type" => "IsNot"}}
  defp python_compare_op(:in), do: {:ok, %{"_type" => "In"}}
  defp python_compare_op(:not_in), do: {:ok, %{"_type" => "NotIn"}}
  defp python_compare_op(op), do: {:error, "Unsupported comparison operator: #{op}"}

  defp python_bool_op(:and), do: {:ok, %{"_type" => "And"}}
  defp python_bool_op(:or), do: {:ok, %{"_type" => "Or"}}
  defp python_bool_op(op), do: {:error, "Unsupported boolean operator: #{op}"}

  defp python_unary_op(:boolean, :not), do: {:ok, %{"_type" => "Not"}}
  defp python_unary_op(:arithmetic, :-), do: {:ok, %{"_type" => "USub"}}
  defp python_unary_op(:arithmetic, :+), do: {:ok, %{"_type" => "UAdd"}}
  defp python_unary_op(:bitwise, :bnot), do: {:ok, %{"_type" => "Invert"}}

  defp python_unary_op(category, op),
    do: {:error, "Unsupported unary operator: #{category} #{op}"}

  defp build_function_ref(name) when is_binary(name) do
    case String.split(name, ".") do
      [single_name] ->
        {:ok, %{"_type" => "Name", "id" => single_name, "ctx" => %{"_type" => "Load"}}}

      parts ->
        # Build nested Attribute nodes
        [first | rest] = parts
        base = %{"_type" => "Name", "id" => first, "ctx" => %{"_type" => "Load"}}

        result =
          Enum.reduce(rest, base, fn attr, acc ->
            %{
              "_type" => "Attribute",
              "value" => acc,
              "attr" => attr,
              "ctx" => %{"_type" => "Load"}
            }
          end)

        {:ok, result}
    end
  end

  # Extended layer helpers

  # A `:block` used as a body. A `with` block is a single statement, so it
  # must be reified through `transform/2` (which rebuilds the `With` node)
  # rather than flattened into its children.
  defp transform_to_body({:block, meta, statements}, metadata) when is_list(meta) do
    if Keyword.get(meta, :original_form) == :with do
      with {:ok, stmt_py} <- transform({:block, meta, statements}, metadata) do
        {:ok, [stmt_py]}
      end
    else
      transform_statement_list(statements, metadata)
    end
  end

  defp transform_to_body(single_expr, metadata) do
    with {:ok, expr_py} <- transform(single_expr, metadata) do
      {:ok, [as_statement(expr_py)]}
    end
  end

  # A statement list. Every element must be a *statement*; a bare expression
  # (`print(x)`, a docstring) is wrapped in `Expr`, which is what Python's
  # grammar requires. Without the wrapper `ast.unparse` emitted
  # `def m():print(1)` — two statements concatenated on one line.
  defp transform_statement_list(statements, metadata) when is_list(statements) do
    statements
    |> Enum.reduce_while({:ok, []}, fn statement, {:ok, acc} ->
      case transform(statement, metadata) do
        {:ok, py} -> {:cont, {:ok, Enum.reverse(as_statements(py)) ++ acc}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, statements} -> {:ok, Enum.reverse(statements)}
      error -> error
    end
  end

  # A `:block` in a statement position is a *sequence* of statements, not one
  # statement — `import socket, struct` becomes a block of two `:import`
  # nodes. It is spliced into the surrounding list; wrapping it produced
  # `Expr(Module([...]))`, which unparsed to an empty body.
  defp as_statements(%{"_type" => "Module", "body" => body}) when is_list(body), do: body

  defp as_statements(py), do: [as_statement(py)]

  # Statement node types. Anything else in a statement position is an
  # expression and needs an `Expr` wrapper.
  @statement_types ~w(
    Assign AugAssign AnnAssign Return Raise Assert Delete Pass Break Continue
    Import ImportFrom Global Nonlocal If While For Try With FunctionDef ClassDef
    AsyncFunctionDef AsyncFor AsyncWith Match Expr
  )

  defp as_statement(%{"_type" => type} = node) when type in @statement_types, do: node
  defp as_statement(node) when is_map(node), do: %{"_type" => "Expr", "value" => node}

  defp transform_to_body_or_empty(nil, _metadata), do: {:ok, []}
  defp transform_to_body_or_empty(expr, metadata), do: transform_to_body(expr, metadata)

  # Lambda arguments. A lambda can carry `*args` / `**kwargs` and defaults
  # (`lambda *values: ...`), so it shares the parameter-splitting logic with
  # `build_function_args` rather than assuming every param is positional.
  defp build_lambda_args(params) when is_list(params) do
    {positional, vararg, kwarg} =
      Enum.reduce(params, {[], nil, nil}, fn
        {:param, _meta, "**" <> name}, {pos, va, _kw} ->
          {pos, va, %{"_type" => "arg", "arg" => name, "annotation" => nil}}

        {:param, _meta, "*"}, acc ->
          acc

        {:param, _meta, "*" <> name}, {pos, _va, kw} ->
          {pos, %{"_type" => "arg", "arg" => name, "annotation" => nil}, kw}

        {:param, meta, name}, {pos, va, kw} when is_binary(name) and is_list(meta) ->
          arg = build_arg(name, meta)
          {pos ++ [arg], va, kw}

        name, {pos, va, kw} when is_binary(name) ->
          {pos ++ [build_arg(name, [])], va, kw}

        _, acc ->
          acc
      end)

    defaults =
      params
      |> Enum.map(fn
        {:param, meta, name} when is_list(meta) and is_binary(name) ->
          if String.starts_with?(name, "*"), do: nil, else: Keyword.get(meta, :default)

        _ ->
          nil
      end)

    {:ok, defaults_py} = transform_defaults(defaults, %{})

    {:ok,
     %{
       "_type" => "arguments",
       "args" => positional,
       "posonlyargs" => [],
       "kwonlyargs" => [],
       "kw_defaults" => [],
       "defaults" => defaults_py,
       "vararg" => vararg,
       "kwarg" => kwarg
     }}
  end

  # `defaults` is aligned to the end of the positional parameter list, so the
  # leading `nil`s (parameters without a default) are trimmed here and the
  # remainder is transformed. A `nil` inside the remaining list is a
  # keyword-only parameter without a default, which the AST spells as `nil`.
  # Positional `defaults`: aligned to the *end* of the parameter list, so
  # leading `nil`s (parameters without a default) are trimmed.
  defp transform_defaults(defaults, metadata) when is_list(defaults) do
    defaults
    |> Enum.reverse()
    |> Enum.drop_while(&is_nil/1)
    |> Enum.reverse()
    |> transform_default_slots(metadata)
  end

  defp transform_defaults(_defaults, _metadata), do: {:ok, []}

  # Keyword-only `kw_defaults`: aligned one-to-one with `kwonlyargs`, so a
  # `nil` (no default) is significant and must be kept. Trimming it made the
  # list shorter than `kwonlyargs`, which `ast.unparse` renders as a bare `*`
  # — `def f(error, *, encoder)` came back as `def f(error, *)`.
  defp transform_kw_defaults(defaults, metadata) when is_list(defaults) do
    transform_default_slots(defaults, metadata)
  end

  defp transform_kw_defaults(_defaults, _metadata), do: {:ok, []}

  defp transform_default_slots(slots, metadata) when is_list(slots) do
    slots
    |> Enum.reduce_while({:ok, []}, fn
      nil, {:ok, acc} ->
        {:cont, {:ok, [nil | acc]}}

      default, {:ok, acc} ->
        case transform(default, metadata) do
          {:ok, py} -> {:cont, {:ok, [py | acc]}}
          {:error, _} = err -> {:halt, err}
        end
    end)
    |> case do
      {:ok, py} -> {:ok, Enum.reverse(py)}
      error -> error
    end
  end

  defp transform_default_slots(_slots, _metadata), do: {:ok, []}

  # An `arg` node. The annotation is restored from `:annotation` metadata
  # (a MetaAST expression); without it every parameter annotation was dropped.
  defp build_arg(name, param_meta) when is_list(param_meta) do
    %{
      "_type" => "arg",
      "arg" => name,
      "annotation" => annotation_py(Keyword.get(param_meta, :annotation))
    }
  end

  defp annotation_py(nil), do: nil

  defp annotation_py(annotation) do
    case transform(annotation, %{}) do
      {:ok, py} -> py
      _ -> nil
    end
  end

  # Build function arguments (richer than lambda args).
  #
  # `:default` on a `:param` is the default-value expression; the AST keeps
  # defaults in a separate `defaults` list (positional) or `kw_defaults`
  # (keyword-only), aligned to the *end* of the corresponding name list.
  defp build_function_args(params, meta_posonly) when is_list(params) do
    {positional, kwonly, vararg, kwarg, defaults, kw_defaults} =
      Enum.reduce(params, {[], [], nil, nil, [], []}, fn param, acc ->
        {pos, kw, va, kwa, defs, kwdefs} = acc

        case param do
          {:param, param_meta, "**" <> arg_name} when is_list(param_meta) ->
            {pos, kw, va, build_arg(arg_name, param_meta), defs, kwdefs}

          # A bare `*` marks the start of keyword-only parameters. It is not a
          # parameter: Python's AST represents it by `vararg == nil` plus a
          # non-empty `kwonlyargs`. Emitting it as `arg: ""` produced
          # `def f(a, *)`, which is a syntax error.
          {:param, _param_meta, "*"} ->
            {pos, kw, va, kwa, defs, kwdefs}

          {:param, param_meta, "*" <> arg_name} when is_list(param_meta) ->
            {pos, kw, build_arg(arg_name, param_meta), kwa, defs, kwdefs}

          {:param, param_meta, name} when is_binary(name) ->
            arg = build_arg(name, param_meta)

            if Keyword.get(param_meta, :kind) == :keyword do
              {pos, kw ++ [arg], va, kwa, defs, kwdefs ++ [Keyword.get(param_meta, :default)]}
            else
              {pos ++ [arg], kw, va, kwa, defs ++ [Keyword.get(param_meta, :default)], kwdefs}
            end

          name when is_binary(name) ->
            {pos ++ [build_arg(name, [])], kw, va, kwa, defs ++ [nil], kwdefs}

          _ ->
            {pos ++ [build_arg("_", [])], kw, va, kwa, defs ++ [nil], kwdefs}
        end
      end)

    with {:ok, defaults_py} <- transform_defaults(defaults, %{}),
         {:ok, kw_defaults_py} <- transform_kw_defaults(kw_defaults, %{}) do
      # `:positional_only` records how many leading parameters sit before `/`.
      posonly_count = Keyword.get(meta_posonly, :positional_only, 0)
      {posonly, positional} = Enum.split(positional, posonly_count)

      {:ok,
       %{
         "_type" => "arguments",
         "args" => positional,
         "posonlyargs" => posonly,
         "kwonlyargs" => kwonly,
         "kw_defaults" => kw_defaults_py,
         "defaults" => defaults_py,
         "vararg" => vararg,
         "kwarg" => kwarg
       }}
    end
  end

  defp transform_exception_handlers(clauses, metadata) when is_list(clauses) do
    clauses
    |> Enum.reduce_while({:ok, []}, fn clause, {:ok, acc} ->
      case transform_exception_handler(clause, metadata) do
        {:ok, handler} -> {:cont, {:ok, [handler | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, handlers} -> {:ok, Enum.reverse(handlers)}
      error -> error
    end
  end

  # A handler is a `:match_arm` whose metadata carries `:exception_type` and
  # whose `:pattern` is the bound variable (or `nil` for a bare `except:`).
  # The legacy bare `{type, var, body}` tuple is still accepted so that
  # MetaAST produced by older versions reifies.
  defp transform_exception_handler({:match_arm, meta, [body]}, metadata) when is_list(meta) do
    with {:ok, type_py} <- build_exception_type(Keyword.get(meta, :exception_type, :error)),
         {:ok, name_py} <- extract_var_name(Keyword.get(meta, :pattern)),
         {:ok, body_py} <- transform_to_body(body, metadata) do
      {:ok,
       %{"_type" => "ExceptHandler", "type" => type_py, "name" => name_py, "body" => body_py}}
    end
  end

  defp transform_exception_handler({exception_type, var, body}, metadata) do
    with {:ok, type_py} <- build_exception_type(exception_type),
         {:ok, name_py} <- extract_var_name(var),
         {:ok, body_py} <- transform_to_body(body, metadata) do
      {:ok,
       %{"_type" => "ExceptHandler", "type" => type_py, "name" => name_py, "body" => body_py}}
    end
  end

  # A bare `except:` — no exception class at all.
  defp build_exception_type(nil), do: {:ok, nil}

  defp build_exception_type(:error) do
    {:ok, %{"_type" => "Name", "id" => "Exception", "ctx" => %{"_type" => "Load"}}}
  end

  # `ToMeta` carries the exception class verbatim (as an atom such as
  # `:ValueError`, or as a `:language_specific` node for a tuple of types or
  # a name that had no pre-existing atom).
  defp build_exception_type({:language_specific, _meta, native}), do: {:ok, native}

  defp build_exception_type(atom) when is_atom(atom) do
    {:ok, %{"_type" => "Name", "id" => Atom.to_string(atom), "ctx" => %{"_type" => "Load"}}}
  end

  defp build_exception_type(name) when is_binary(name) do
    {:ok, %{"_type" => "Name", "id" => name, "ctx" => %{"_type" => "Load"}}}
  end

  defp build_exception_type(_), do: build_exception_type(:error)
  defp extract_var_name(nil), do: {:ok, nil}
  defp extract_var_name({:variable, _meta, name}), do: {:ok, name}
  defp extract_var_name(_), do: {:ok, "e"}
end
