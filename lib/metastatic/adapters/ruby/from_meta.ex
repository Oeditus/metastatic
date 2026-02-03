defmodule Metastatic.Adapters.Ruby.FromMeta do
  @moduledoc """
  Transform MetaAST (M2) back to Ruby AST (M1).

  This module implements the reification function ρ_Ruby that converts
  meta-level representations back to Ruby-specific AST structures.

  ## Coverage

  M2.1 Core Layer: Fully supported
  M2.2 Extended Layer: Partial support (loops, basic iterators)
  M2.3 Native Layer: Direct passthrough (preserves original AST)
  """

  @doc """
  Transform MetaAST back to Ruby AST.

  Returns `{:ok, ruby_ast}` on success or `{:error, reason}` on failure.
  """
  @spec transform(term(), map()) :: {:ok, term()} | {:error, String.t()}

  # M2.1 Core Layer - Literals

  def transform({:literal, :integer, value}, _metadata) do
    {:ok, %{"type" => "int", "children" => [value]}}
  end

  def transform({:literal, :float, value}, _metadata) do
    {:ok, %{"type" => "float", "children" => [value]}}
  end

  def transform({:literal, :string, value}, _metadata) do
    {:ok, %{"type" => "str", "children" => [value]}}
  end

  def transform({:literal, :symbol, value}, _metadata) do
    {:ok, %{"type" => "sym", "children" => [value]}}
  end

  def transform({:literal, :boolean, true}, _metadata) do
    {:ok, %{"type" => "true", "children" => []}}
  end

  def transform({:literal, :boolean, false}, _metadata) do
    {:ok, %{"type" => "false", "children" => []}}
  end

  def transform({:literal, :null, nil}, _metadata) do
    {:ok, %{"type" => "nil", "children" => []}}
  end

  def transform({:literal, :collection, elements}, %{collection_type: :array}) do
    with {:ok, elements_ast} <- transform_list(elements) do
      {:ok, %{"type" => "array", "children" => elements_ast}}
    end
  end

  def transform({:literal, :constant, name}, _metadata) do
    {:ok, %{"type" => "const", "children" => [nil, name]}}
  end

  # M2.1 Core Layer - Variables

  def transform({:variable, name}, %{scope: :local}) do
    {:ok, %{"type" => "lvar", "children" => [name]}}
  end

  def transform({:variable, name}, %{scope: :instance}) do
    {:ok, %{"type" => "ivar", "children" => [name]}}
  end

  def transform({:variable, name}, %{scope: :class}) do
    {:ok, %{"type" => "cvar", "children" => [name]}}
  end

  def transform({:variable, name}, %{scope: :global}) do
    {:ok, %{"type" => "gvar", "children" => [name]}}
  end

  def transform({:variable, name}, _metadata) do
    # Default to local variable
    {:ok, %{"type" => "lvar", "children" => [name]}}
  end

  # M2.1 Core Layer - Binary Operations

  def transform({:binary_op, :arithmetic, op, left, right}, _metadata) do
    with {:ok, left_ast} <- transform(left, %{}),
         {:ok, right_ast} <- transform(right, %{}) do
      {:ok, %{"type" => "send", "children" => [left_ast, op, right_ast]}}
    end
  end

  def transform({:binary_op, :comparison, op, left, right}, _metadata) do
    with {:ok, left_ast} <- transform(left, %{}),
         {:ok, right_ast} <- transform(right, %{}) do
      {:ok, %{"type" => "send", "children" => [left_ast, op, right_ast]}}
    end
  end

  def transform({:binary_op, :boolean, :and, left, right}, _metadata) do
    with {:ok, left_ast} <- transform(left, %{}),
         {:ok, right_ast} <- transform(right, %{}) do
      {:ok, %{"type" => "and", "children" => [left_ast, right_ast]}}
    end
  end

  def transform({:binary_op, :boolean, :or, left, right}, _metadata) do
    with {:ok, left_ast} <- transform(left, %{}),
         {:ok, right_ast} <- transform(right, %{}) do
      {:ok, %{"type" => "or", "children" => [left_ast, right_ast]}}
    end
  end

  # M2.1 Core Layer - Unary Operations

  def transform({:unary_op, :arithmetic, op, operand}, _metadata) do
    with {:ok, operand_ast} <- transform(operand, %{}) do
      {:ok, %{"type" => "send", "children" => [operand_ast, op, nil]}}
    end
  end

  def transform({:unary_op, :boolean, :not, operand}, _metadata) do
    with {:ok, operand_ast} <- transform(operand, %{}) do
      {:ok, %{"type" => "send", "children" => [operand_ast, :!, nil]}}
    end
  end

  # M2.1 Core Layer - Function Calls

  def transform({:function_call, name, args}, %{call_type: :local}) do
    with {:ok, args_ast} <- transform_list(args) do
      {:ok, %{"type" => "send", "children" => [nil, String.to_atom(name) | args_ast]}}
    end
  end

  def transform({:function_call, name, args}, _metadata) do
    # Default to local call
    with {:ok, args_ast} <- transform_list(args) do
      {:ok, %{"type" => "send", "children" => [nil, String.to_atom(name) | args_ast]}}
    end
  end

  # M2.1 Core Layer - Conditionals

  def transform({:conditional, condition, then_branch, else_branch}, _metadata) do
    with {:ok, cond_ast} <- transform(condition, %{}),
         {:ok, then_ast} <- transform_or_nil(then_branch),
         {:ok, else_ast} <- transform_or_nil(else_branch) do
      {:ok, %{"type" => "if", "children" => [cond_ast, then_ast, else_ast]}}
    end
  end

  # M2.1 Core Layer - Assignment

  def transform({:assignment, {:variable, name}, value}, %{scope: :local}) do
    with {:ok, value_ast} <- transform(value, %{}) do
      {:ok, %{"type" => "lvasgn", "children" => [name, value_ast]}}
    end
  end

  def transform({:assignment, {:variable, name}, value}, %{scope: :instance}) do
    with {:ok, value_ast} <- transform(value, %{}) do
      {:ok, %{"type" => "ivasgn", "children" => [name, value_ast]}}
    end
  end

  def transform({:assignment, {:variable, name}, value}, _metadata) do
    # Default to local
    with {:ok, value_ast} <- transform(value, %{}) do
      {:ok, %{"type" => "lvasgn", "children" => [name, value_ast]}}
    end
  end

  # M2.1 Core Layer - Blocks

  def transform({:block, statements}, _metadata) do
    with {:ok, statements_ast} <- transform_list(statements) do
      {:ok, %{"type" => "begin", "children" => statements_ast}}
    end
  end

  # M2.2 Extended Layer - Loops (basic support)

  def transform({:loop, :while, condition, body}, _metadata) do
    with {:ok, cond_ast} <- transform(condition, %{}),
         {:ok, body_ast} <- transform_or_nil(body) do
      {:ok, %{"type" => "while", "children" => [cond_ast, body_ast]}}
    end
  end

  # M2.2s Structural Layer - Container support

  def transform({:container, :class, name, parent, _type_params, _implements, body}, _metadata) do
    with {:ok, name_ast} <- build_const_ast(name),
         {:ok, parent_ast} <- build_const_ast_or_nil(parent),
         {:ok, body_ast} <- transform_or_nil(body) do
      {:ok, %{"type" => "class", "children" => [name_ast, parent_ast, body_ast]}}
    end
  end

  def transform(
        {:container, :class, name, parent, _type_params, _implements, body, _loc},
        metadata
      ) do
    # Handle version with location metadata
    transform({:container, :class, name, parent, [], [], body}, metadata)
  end

  def transform(
        {:container, :module, name, _parent, _type_params, _implements, body},
        _metadata
      ) do
    with {:ok, name_ast} <- build_const_ast(name),
         {:ok, body_ast} <- transform_or_nil(body) do
      {:ok, %{"type" => "module", "children" => [name_ast, body_ast]}}
    end
  end

  def transform(
        {:container, :module, name, _parent, _type_params, _implements, body, _loc},
        metadata
      ) do
    # Handle version with location metadata
    transform({:container, :module, name, nil, [], [], body}, metadata)
  end

  # M2.2s Structural Layer - Function definition support

  # Handle class methods (self.method_name) - MUST come before generic function_def
  def transform(
        {:function_def, "self." <> method_name, params, _ret_type, _opts, body},
        _metadata
      ) do
    args_ast = build_args_ast(params)
    self_ast = %{"type" => "self", "children" => []}

    with {:ok, body_ast} <- transform_or_nil(body) do
      {:ok, %{"type" => "defs", "children" => [self_ast, method_name, args_ast, body_ast]}}
    end
  end

  def transform(
        {:function_def, "self." <> method_name, params, _ret_type, _opts, body, _loc},
        metadata
      ) do
    # Handle version with location metadata
    transform({:function_def, "self." <> method_name, params, nil, %{}, body}, metadata)
  end

  # Generic function definition (regular methods)
  def transform({:function_def, name, params, _ret_type, _opts, body}, _metadata) do
    args_ast = build_args_ast(params)

    with {:ok, body_ast} <- transform_or_nil(body) do
      {:ok, %{"type" => "def", "children" => [name, args_ast, body_ast]}}
    end
  end

  def transform({:function_def, name, params, _ret_type, _opts, body, _loc}, metadata) do
    # Handle version with location metadata
    transform({:function_def, name, params, nil, %{}, body}, metadata)
  end

  # M2.2s Structural Layer - Attribute access

  def transform({:attribute_access, receiver, attribute}, _metadata) do
    with {:ok, receiver_ast} <- transform(receiver, %{}) do
      # Convert to Ruby send node (method call without args)
      {:ok, %{"type" => "send", "children" => [receiver_ast, String.to_atom(attribute)]}}
    end
  end

  def transform({:attribute_access, receiver, attribute, _loc}, metadata) do
    # Handle version with location metadata
    transform({:attribute_access, receiver, attribute}, metadata)
  end

  # M2.2s Structural Layer - Augmented assignment

  def transform({:augmented_assignment, _category, op, target, value}, _metadata) do
    with {:ok, target_ast} <- transform(target, %{}),
         {:ok, value_ast} <- transform(value, %{}) do
      {:ok, %{"type" => "op_asgn", "children" => [target_ast, op, value_ast]}}
    end
  end

  def transform({:augmented_assignment, _category, op, target, value, _loc}, metadata) do
    # Handle version with location metadata
    transform({:augmented_assignment, :arithmetic, op, target, value}, metadata)
  end

  # M2.3 Native Layer - Passthrough

  def transform({:language_specific, :ruby, original_ast, _construct_type}, _metadata) do
    {:ok, original_ast}
  end

  # Nil passthrough
  def transform(nil, _metadata), do: {:ok, nil}

  # Catch-all
  def transform(unsupported, _metadata) do
    {:error, "Unsupported MetaAST construct for Ruby reification: #{inspect(unsupported)}"}
  end

  # Helper Functions

  defp transform_list(items) when is_list(items) do
    items
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
      case transform(item, %{}) do
        {:ok, ast} -> {:cont, {:ok, [ast | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, items_ast} -> {:ok, Enum.reverse(items_ast)}
      error -> error
    end
  end

  defp transform_or_nil(nil), do: {:ok, nil}
  defp transform_or_nil(value), do: transform(value, %{})

  # Helper to build constant AST node
  defp build_const_ast(name) when is_binary(name) do
    {:ok, %{"type" => "const", "children" => [nil, name]}}
  end

  defp build_const_ast_or_nil(nil), do: {:ok, nil}
  defp build_const_ast_or_nil(name), do: build_const_ast(name)

  # Helper to build args AST for method definitions
  defp build_args_ast(params) when is_list(params) do
    children =
      Enum.map(params, fn
        param when is_binary(param) ->
          %{"type" => "arg", "children" => [param]}

        {:pattern, _meta} ->
          # Pattern parameters - simplified for now
          %{"type" => "arg", "children" => ["_pattern"]}

        {:default, name, _default_val} ->
          # Default parameters - simplified for now
          %{"type" => "arg", "children" => [name]}
      end)

    %{"type" => "args", "children" => children}
  end
end
