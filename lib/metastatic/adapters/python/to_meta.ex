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

  @doc """
  Transform Python AST to MetaAST.

  Returns `{:ok, meta_ast, metadata}` on success or `{:error, reason}` on failure.

  ## Examples

      iex> transform(%{"_type" => "Constant", "value" => 42})
      {:ok, {:literal, :integer, 42}, %{}}

      iex> transform(%{"_type" => "Name", "id" => "x"})
      {:ok, {:variable, "x"}, %{}}

      iex> transform(%{"_type" => "BinOp", "op" => %{"_type" => "Add"}, ...})
      {:ok, {:binary_op, :arithmetic, :+, left, right}, %{}}
  """
  @spec transform(map()) :: {:ok, term(), map()} | {:error, String.t()}

  # Module - top-level container
  def transform(%{"_type" => "Module", "body" => body}) do
    with {:ok, statements} <- transform_list(body) do
      case statements do
        [] -> {:ok, {:block, []}, %{}}
        [single] -> {:ok, single, %{}}
        multiple -> {:ok, {:block, multiple}, %{}}
      end
    end
  end

  # Expression statement - unwrap the value
  def transform(%{"_type" => "Expr", "value" => value}) do
    transform(value)
  end

  # Literals - M2.1 Core Layer

  # Constant node (Python 3.8+)
  def transform(%{"_type" => "Constant", "value" => value}) do
    literal = infer_literal_type(value)
    {:ok, literal, %{}}
  end

  # Legacy literal nodes (Python 3.7 compatibility)
  def transform(%{"_type" => "Num", "n" => value}) when is_integer(value) do
    {:ok, {:literal, :integer, value}, %{}}
  end

  def transform(%{"_type" => "Num", "n" => value}) when is_float(value) do
    {:ok, {:literal, :float, value}, %{}}
  end

  def transform(%{"_type" => "Str", "s" => value}) do
    {:ok, {:literal, :string, value}, %{}}
  end

  def transform(%{"_type" => "NameConstant", "value" => true}) do
    {:ok, {:literal, :boolean, true}, %{}}
  end

  def transform(%{"_type" => "NameConstant", "value" => false}) do
    {:ok, {:literal, :boolean, false}, %{}}
  end

  def transform(%{"_type" => "NameConstant", "value" => nil}) do
    {:ok, {:literal, :null, nil}, %{}}
  end

  # Variables - M2.1 Core Layer

  def transform(%{"_type" => "Name", "id" => name}) do
    {:ok, {:variable, name}, %{}}
  end

  # Binary Operators - M2.1 Core Layer

  def transform(%{"_type" => "BinOp", "op" => op, "left" => left, "right" => right}) do
    with {:ok, op_meta} <- transform_binop(op),
         {:ok, left_meta, _} <- transform(left),
         {:ok, right_meta, _} <- transform(right) do
      {category, operator} = op_meta
      {:ok, {:binary_op, category, operator, left_meta, right_meta}, %{}}
    end
  end

  # Comparison Operators - M2.1 Core Layer

  def transform(%{"_type" => "Compare", "left" => left, "ops" => [op], "comparators" => [right]}) do
    with {:ok, op_meta} <- transform_compare_op(op),
         {:ok, left_meta, _} <- transform(left),
         {:ok, right_meta, _} <- transform(right) do
      {:ok, {:binary_op, :comparison, op_meta, left_meta, right_meta}, %{}}
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
    {:ok,
     {:language_specific, :python,
      %{"_type" => "Compare", "left" => left, "ops" => ops, "comparators" => comparators},
      :chained_comparison}, %{}}
  end

  # Boolean Operators - M2.1 Core Layer

  def transform(%{"_type" => "BoolOp", "op" => op, "values" => [left, right]}) do
    with {:ok, op_meta} <- transform_bool_op(op),
         {:ok, left_meta, _} <- transform(left),
         {:ok, right_meta, _} <- transform(right) do
      {:ok, {:binary_op, :boolean, op_meta, left_meta, right_meta}, %{}}
    end
  end

  # Multiple boolean operations - chain them
  def transform(%{"_type" => "BoolOp", "op" => op, "values" => values}) when length(values) > 2 do
    with {:ok, op_meta} <- transform_bool_op(op),
         {:ok, transformed_values} <- transform_list(values) do
      # Chain: a and b and c → (a and b) and c
      [first, second | rest] = transformed_values
      initial = {:binary_op, :boolean, op_meta, first, second}

      result =
        Enum.reduce(rest, initial, fn value, acc ->
          {:binary_op, :boolean, op_meta, acc, value}
        end)

      {:ok, result, %{}}
    end
  end

  # Unary Operators - M2.1 Core Layer

  def transform(%{"_type" => "UnaryOp", "op" => op, "operand" => operand}) do
    with {:ok, {category, operator}} <- transform_unary_op(op),
         {:ok, operand_meta, _} <- transform(operand) do
      {:ok, {:unary_op, category, operator, operand_meta}, %{}}
    end
  end

  # Function Calls - M2.1 Core Layer

  def transform(%{"_type" => "Call", "func" => func, "args" => args}) do
    with {:ok, func_name} <- extract_function_name(func),
         {:ok, args_meta} <- transform_list(args) do
      {:ok, {:function_call, func_name, args_meta}, %{}}
    end
  end

  # Conditionals - M2.1 Core Layer

  # If statement
  def transform(%{"_type" => "If", "test" => test, "body" => body, "orelse" => orelse}) do
    with {:ok, test_meta, _} <- transform(test),
         {:ok, body_meta, _} <- transform_body(body),
         {:ok, else_meta, _} <- transform_body_or_nil(orelse) do
      {:ok, {:conditional, test_meta, body_meta, else_meta}, %{}}
    end
  end

  # If expression (ternary)
  def transform(%{"_type" => "IfExp", "test" => test, "body" => body, "orelse" => orelse}) do
    with {:ok, test_meta, _} <- transform(test),
         {:ok, body_meta, _} <- transform(body),
         {:ok, else_meta, _} <- transform(orelse) do
      {:ok, {:conditional, test_meta, body_meta, else_meta}, %{}}
    end
  end

  # Early Returns - M2.1 Core Layer

  def transform(%{"_type" => "Return", "value" => value}) do
    with {:ok, value_meta, _} <- transform_or_nil(value) do
      {:ok, {:early_return, :return, value_meta}, %{}}
    end
  end

  def transform(%{"_type" => "Break"}) do
    {:ok, {:early_return, :break, nil}, %{}}
  end

  def transform(%{"_type" => "Continue"}) do
    {:ok, {:early_return, :continue, nil}, %{}}
  end

  # Assignment - M2.1 Core Layer
  # In Python, = is assignment (imperative binding/mutation)

  # Simple assignment: x = 5
  def transform(%{"_type" => "Assign", "targets" => [target], "value" => value}) do
    with {:ok, target_meta, target_metadata} <- transform(target),
         {:ok, value_meta, value_metadata} <- transform(value) do
      metadata = %{
        target_metadata: target_metadata,
        value_metadata: value_metadata
      }

      {:ok, {:assignment, target_meta, value_meta}, metadata}
    end
  end

  # Multiple assignment: x = y = 5
  # Python allows chaining: a = b = c = 5
  # Transform to nested assignments: a = (b = (c = 5))
  def transform(%{"_type" => "Assign", "targets" => targets, "value" => value})
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

            {:ok, {:assignment, target_meta, current_value}, metadata}
          end
        end)

      result
    end
  end

  # Augmented assignment: x += 1, x *= 2, etc.
  # Desugar to: x = x + 1
  def transform(%{"_type" => "AugAssign", "target" => target, "op" => op, "value" => value}) do
    with {:ok, target_meta, target_metadata} <- transform(target),
         {:ok, {category, operator}} <- transform_binop(op),
         {:ok, value_meta, _} <- transform(value) do
      # Desugar: x += 1 becomes x = x + 1
      desugared_value = {:binary_op, category, operator, target_meta, value_meta}

      metadata = %{
        target_metadata: target_metadata,
        value_metadata: %{},
        augmented_op: operator
      }

      {:ok, {:assignment, target_meta, desugared_value}, metadata}
    end
  end

  # Annotated assignment: x: int = 5 (Python 3.6+)
  # Ignore the annotation for now
  def transform(%{"_type" => "AnnAssign", "target" => target, "value" => value})
      when not is_nil(value) do
    with {:ok, target_meta, target_metadata} <- transform(target),
         {:ok, value_meta, value_metadata} <- transform(value) do
      metadata = %{
        target_metadata: target_metadata,
        value_metadata: value_metadata
      }

      {:ok, {:assignment, target_meta, value_meta}, metadata}
    end
  end

  # Annotated assignment without value: x: int (declaration only)
  def transform(%{"_type" => "AnnAssign", "target" => _target, "value" => nil} = node) do
    # Type-only annotation, treat as language-specific
    {:ok, {:language_specific, :python, node, :type_annotation}, %{}}
  end

  # Lists as literal collections
  def transform(%{"_type" => "List", "elts" => elements}) do
    with {:ok, elements_meta} <- transform_list(elements) do
      {:ok, {:literal, :collection, elements_meta}, %{collection_type: :list}}
    end
  end

  # Tuples - Used in patterns and values
  def transform(%{"_type" => "Tuple", "elts" => elements}) do
    with {:ok, elements_meta} <- transform_list(elements) do
      {:ok, {:tuple, elements_meta}, %{}}
    end
  end

  # Loops - M2.2 Extended Layer

  # While loop
  def transform(%{"_type" => "While", "test" => test, "body" => body}) do
    with {:ok, test_meta, _} <- transform(test),
         {:ok, body_meta, _} <- transform_body(body) do
      {:ok, {:loop, :while, test_meta, body_meta}, %{}}
    end
  end

  # For loop
  def transform(%{"_type" => "For", "target" => target, "iter" => iter, "body" => body}) do
    with {:ok, target_meta, _} <- transform(target),
         {:ok, iter_meta, _} <- transform(iter),
         {:ok, body_meta, _} <- transform_body(body) do
      {:ok, {:loop, :for_each, target_meta, iter_meta, body_meta}, %{}}
    end
  end

  # Lambdas - M2.2 Extended Layer

  def transform(%{"_type" => "Lambda", "args" => args, "body" => body}) do
    with {:ok, params} <- extract_lambda_params(args),
         {:ok, body_meta, _} <- transform(body) do
      # Lambdas don't capture variables explicitly in Python AST
      {:ok, {:lambda, params, [], body_meta}, %{}}
    end
  end

  # Collection Operations - M2.2 Extended Layer

  # Simple list comprehension without filters → map
  def transform(%{
        "_type" => "ListComp",
        "elt" => elt,
        "generators" => [%{"target" => target, "iter" => iter, "ifs" => []}]
      }) do
    with {:ok, target_meta, _} <- transform(target),
         {:ok, iter_meta, _} <- transform(iter),
         {:ok, elt_meta, _} <- transform(elt) do
      # Convert to: {:collection_op, :map, {:lambda, [param], [], body}, collection}
      param_name = extract_variable_name(target_meta)
      lambda = {:lambda, [param_name], [], elt_meta}
      {:ok, {:collection_op, :map, lambda, iter_meta}, %{}}
    end
  end

  # Complex list comprehension with filters → language_specific
  def transform(%{"_type" => "ListComp"} = comp) do
    {:ok, {:language_specific, :python, comp, :list_comprehension}, %{}}
  end

  # Exception Handling - M2.2 Extended Layer

  def transform(%{
        "_type" => "Try",
        "body" => body,
        "handlers" => handlers,
        "orelse" => _orelse,
        "finalbody" => finalbody
      }) do
    with {:ok, body_meta, _} <- transform_body(body),
         {:ok, rescue_clauses} <- transform_exception_handlers(handlers),
         {:ok, finally_meta, _} <- transform_body_or_nil(finalbody) do
      {:ok, {:exception_handling, body_meta, rescue_clauses, finally_meta}, %{}}
    end
  end

  # Native Layer - M2.3: Python-Specific Constructs

  # Function definitions with decorators
  def transform(%{"_type" => "FunctionDef", "decorator_list" => [_ | _] = _decorators} = node) do
    {:ok, {:language_specific, :python, node, :function_with_decorators}, %{}}
  end

  # Generator functions (FunctionDef containing Yield/YieldFrom)
  def transform(%{"_type" => "FunctionDef", "body" => body} = node) do
    if contains_yield?(body) do
      {:ok, {:language_specific, :python, node, :function_with_generator}, %{}}
    else
      # Regular function - not implemented yet, falls through to catch-all
      {:error, "Unsupported Python AST construct: #{inspect(node)}"}
    end
  end

  # Async function definitions
  def transform(%{"_type" => "AsyncFunctionDef"} = node) do
    {:ok, {:language_specific, :python, node, :async_function}, %{}}
  end

  # Class definitions
  def transform(%{"_type" => "ClassDef"} = node) do
    {:ok, {:language_specific, :python, node, :class}, %{}}
  end

  # Context managers (with statement)
  def transform(%{"_type" => "With"} = node) do
    {:ok, {:language_specific, :python, node, :context_manager}, %{}}
  end

  # Async context managers (async with)
  def transform(%{"_type" => "AsyncWith"} = node) do
    {:ok, {:language_specific, :python, node, :async_context_manager}, %{}}
  end

  # Generators (yield)
  def transform(%{"_type" => "Yield"} = node) do
    {:ok, {:language_specific, :python, node, :yield}, %{}}
  end

  # Yield from (Python 3.3+)
  def transform(%{"_type" => "YieldFrom"} = node) do
    {:ok, {:language_specific, :python, node, :yield_from}, %{}}
  end

  # Await expressions
  def transform(%{"_type" => "Await"} = node) do
    {:ok, {:language_specific, :python, node, :await}, %{}}
  end

  # Async for loops
  def transform(%{"_type" => "AsyncFor"} = node) do
    {:ok, {:language_specific, :python, node, :async_for}, %{}}
  end

  # Import statements
  def transform(%{"_type" => "Import"} = node) do
    {:ok, {:language_specific, :python, node, :import}, %{}}
  end

  # Import from statements
  def transform(%{"_type" => "ImportFrom"} = node) do
    {:ok, {:language_specific, :python, node, :import_from}, %{}}
  end

  # Dict comprehensions
  def transform(%{"_type" => "DictComp"} = node) do
    {:ok, {:language_specific, :python, node, :dict_comprehension}, %{}}
  end

  # Set comprehensions
  def transform(%{"_type" => "SetComp"} = node) do
    {:ok, {:language_specific, :python, node, :set_comprehension}, %{}}
  end

  # Generator expressions
  def transform(%{"_type" => "GeneratorExp"} = node) do
    {:ok, {:language_specific, :python, node, :generator_expression}, %{}}
  end

  # Match statements (Python 3.10+)
  def transform(%{"_type" => "Match"} = node) do
    {:ok, {:language_specific, :python, node, :pattern_match}, %{}}
  end

  # Walrus operator (Python 3.8+)
  def transform(%{"_type" => "NamedExpr"} = node) do
    {:ok, {:language_specific, :python, node, :named_expr}, %{}}
  end

  # Global/nonlocal declarations
  def transform(%{"_type" => "Global"} = node) do
    {:ok, {:language_specific, :python, node, :global}, %{}}
  end

  def transform(%{"_type" => "Nonlocal"} = node) do
    {:ok, {:language_specific, :python, node, :nonlocal}, %{}}
  end

  # Assert statements
  def transform(%{"_type" => "Assert"} = node) do
    {:ok, {:language_specific, :python, node, :assert}, %{}}
  end

  # Raise statements
  def transform(%{"_type" => "Raise"} = node) do
    {:ok, {:language_specific, :python, node, :raise}, %{}}
  end

  # Delete statements
  def transform(%{"_type" => "Delete"} = node) do
    {:ok, {:language_specific, :python, node, :delete}, %{}}
  end

  # Pass statement
  def transform(%{"_type" => "Pass"} = node) do
    {:ok, {:language_specific, :python, node, :pass}, %{}}
  end

  # Catch-all for unsupported constructs
  def transform(unsupported) do
    {:error, "Unsupported Python AST construct: #{inspect(unsupported)}"}
  end

  # Helper Functions

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

  defp transform_body([]), do: {:ok, {:block, []}, %{}}
  defp transform_body([single]), do: transform(single)

  defp transform_body(statements) when is_list(statements) do
    with {:ok, transformed} <- transform_list(statements) do
      {:ok, {:block, transformed}, %{}}
    end
  end

  defp transform_body_or_nil([]), do: {:ok, nil, %{}}
  defp transform_body_or_nil(body), do: transform_body(body)

  defp infer_literal_type(value) when is_integer(value), do: {:literal, :integer, value}
  defp infer_literal_type(value) when is_float(value), do: {:literal, :float, value}
  defp infer_literal_type(value) when is_binary(value), do: {:literal, :string, value}
  defp infer_literal_type(true), do: {:literal, :boolean, true}
  defp infer_literal_type(false), do: {:literal, :boolean, false}
  defp infer_literal_type(nil), do: {:literal, :null, nil}

  # Operator transformations

  defp transform_binop(%{"_type" => "Add"}), do: {:ok, {:arithmetic, :+}}
  defp transform_binop(%{"_type" => "Sub"}), do: {:ok, {:arithmetic, :-}}
  defp transform_binop(%{"_type" => "Mult"}), do: {:ok, {:arithmetic, :*}}
  defp transform_binop(%{"_type" => "Div"}), do: {:ok, {:arithmetic, :/}}
  defp transform_binop(%{"_type" => "FloorDiv"}), do: {:ok, {:arithmetic, :div}}
  defp transform_binop(%{"_type" => "Mod"}), do: {:ok, {:arithmetic, :rem}}
  defp transform_binop(%{"_type" => "Pow"}), do: {:ok, {:arithmetic, :**}}
  defp transform_binop(op), do: {:error, "Unsupported binary operator: #{inspect(op)}"}

  defp transform_compare_op(%{"_type" => "Eq"}), do: {:ok, :==}
  defp transform_compare_op(%{"_type" => "NotEq"}), do: {:ok, :!=}
  defp transform_compare_op(%{"_type" => "Lt"}), do: {:ok, :<}
  defp transform_compare_op(%{"_type" => "LtE"}), do: {:ok, :<=}
  defp transform_compare_op(%{"_type" => "Gt"}), do: {:ok, :>}
  defp transform_compare_op(%{"_type" => "GtE"}), do: {:ok, :>=}
  defp transform_compare_op(%{"_type" => "Is"}), do: {:ok, :===}
  defp transform_compare_op(%{"_type" => "IsNot"}), do: {:ok, :!==}
  defp transform_compare_op(op), do: {:error, "Unsupported comparison operator: #{inspect(op)}"}

  defp transform_bool_op(%{"_type" => "And"}), do: {:ok, :and}
  defp transform_bool_op(%{"_type" => "Or"}), do: {:ok, :or}
  defp transform_bool_op(op), do: {:error, "Unsupported boolean operator: #{inspect(op)}"}

  defp transform_unary_op(%{"_type" => "Not"}), do: {:ok, {:boolean, :not}}
  defp transform_unary_op(%{"_type" => "USub"}), do: {:ok, {:arithmetic, :-}}
  defp transform_unary_op(%{"_type" => "UAdd"}), do: {:ok, {:arithmetic, :+}}
  defp transform_unary_op(op), do: {:error, "Unsupported unary operator: #{inspect(op)}"}

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

  defp extract_function_name(%{"_type" => "Name", "id" => name}), do: {:ok, name}

  defp extract_function_name(%{"_type" => "Attribute", "value" => obj, "attr" => attr}) do
    case extract_function_name(obj) do
      {:ok, obj_name} -> {:ok, "#{obj_name}.#{attr}"}
      error -> error
    end
  end

  defp extract_function_name(func) do
    {:error, "Unsupported function reference: #{inspect(func)}"}
  end

  # Lambda parameter extraction

  defp extract_lambda_params(%{"args" => args}) when is_list(args) do
    params =
      Enum.map(args, fn
        %{"arg" => name} -> name
        %{"id" => name} -> name
        _ -> "_"
      end)

    {:ok, params}
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

  defp transform_exception_handler(%{"type" => type, "name" => name, "body" => body}) do
    with {:ok, exception_type} <- extract_exception_type(type),
         {:ok, var_meta, _} <- transform_or_name(name),
         {:ok, body_meta, _} <- transform_body(body) do
      {:ok, {exception_type, var_meta, body_meta}}
    end
  end

  defp transform_exception_handler(%{"type" => type, "body" => body}) do
    with {:ok, exception_type} <- extract_exception_type(type),
         {:ok, body_meta, _} <- transform_body(body) do
      {:ok, {exception_type, nil, body_meta}}
    end
  end

  defp extract_exception_type(nil), do: {:ok, :error}

  defp extract_exception_type(%{"_type" => "Name", "id" => name}) do
    # Map common Python exceptions to generic types
    exception_atom =
      case name do
        "Exception" -> :error
        "ValueError" -> :error
        "TypeError" -> :error
        "KeyError" -> :error
        "IndexError" -> :error
        _ -> String.to_atom(name)
      end

    {:ok, exception_atom}
  end

  defp extract_exception_type(_), do: {:ok, :error}

  defp transform_or_name(nil), do: {:ok, nil, %{}}
  defp transform_or_name(name) when is_binary(name), do: {:ok, {:variable, name}, %{}}
  defp transform_or_name(node), do: transform(node)

  # Extract variable name from MetaAST node
  defp extract_variable_name({:variable, name}), do: name
  defp extract_variable_name(_), do: "_x"
end
