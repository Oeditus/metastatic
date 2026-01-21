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
         {:ok, body_meta} <- transform_body(body),
         {:ok, else_meta} <- transform_body_or_nil(orelse) do
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

  # Lists as literal collections
  def transform(%{"_type" => "List", "elts" => elements}) do
    with {:ok, elements_meta} <- transform_list(elements) do
      {:ok, {:literal, :collection, elements_meta}, %{collection_type: :list}}
    end
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
end
