defmodule Metastatic.Adapters.Ruby.ToMeta do
  @moduledoc """
  Transform Ruby AST (M1) to MetaAST (M2).

  This module implements the abstraction function α_Ruby that lifts
  Ruby-specific AST structures to the meta-level representation.

  ## Transformation Strategy

  The transformation follows a pattern-matching approach, handling each
  Ruby AST construct (from parser gem) and mapping it to the appropriate MetaAST node type.

  ### M2.1 (Core Layer)

  - Literals: integers, floats, strings, booleans, nil, symbols
  - Variables: local, instance, class, global
  - Binary operators: arithmetic, comparison, boolean
  - Unary operators: negation, logical not
  - Method calls
  - Conditionals: if/elsif/else, unless, ternary
  - Blocks: sequential expressions
  - Assignment: local variable assignment

  ### M2.2 (Extended Layer)

  - Loops: while, until, for
  - Iterators: each, map, select, reduce
  - Blocks & Procs: blocks, lambdas, procs
  - Pattern matching: case/when (classic), case/in (Ruby 3+)
  - Exception handling: begin/rescue/ensure

  ### M2.3 (Native Layer)

  - Class definitions
  - Module definitions
  - Method definitions
  - String interpolation
  - Regular expressions
  - Metaprogramming constructs
  """

  @doc """
  Transform Ruby AST to MetaAST.

  Returns `{:ok, meta_ast, metadata}` on success or `{:error, reason}` on failure.

  ## Examples

      iex> transform(%{"type" => "int", "children" => [42]})
      {:ok, {:literal, :integer, 42}, %{}}

      iex> transform(%{"type" => "lvar", "children" => ["x"]})
      {:ok, {:variable, "x"}, %{}}
  """
  @spec transform(term()) :: {:ok, term(), map()} | {:error, String.t()}

  # Literals - M2.1 Core Layer

  # Integer literal
  def transform(%{"type" => "int", "children" => [value]}) when is_integer(value) do
    {:ok, {:literal, :integer, value}, %{}}
  end

  # Float literal
  def transform(%{"type" => "float", "children" => [value]}) when is_float(value) do
    {:ok, {:literal, :float, value}, %{}}
  end

  # String literal
  def transform(%{"type" => "str", "children" => [value]}) when is_binary(value) do
    {:ok, {:literal, :string, value}, %{}}
  end

  # Symbol literal
  def transform(%{"type" => "sym", "children" => [value]})
      when is_atom(value) or is_binary(value) do
    symbol = if is_binary(value), do: String.to_atom(value), else: value
    {:ok, {:literal, :symbol, symbol}, %{}}
  end

  # Boolean literals
  def transform(%{"type" => "true", "children" => []}) do
    {:ok, {:literal, :boolean, true}, %{}}
  end

  def transform(%{"type" => "false", "children" => []}) do
    {:ok, {:literal, :boolean, false}, %{}}
  end

  # Nil literal
  def transform(%{"type" => "nil", "children" => []}) do
    {:ok, {:literal, :null, nil}, %{}}
  end

  # Handle bare nil (used in unary operators)
  def transform(nil) do
    {:ok, nil, %{}}
  end

  # Array literal
  def transform(%{"type" => "array", "children" => elements}) do
    with {:ok, elements_meta} <- transform_list(elements) do
      {:ok, {:literal, :collection, elements_meta}, %{collection_type: :array}}
    end
  end

  # Hash literal
  def transform(%{"type" => "hash", "children" => pairs}) do
    with {:ok, pairs_meta} <- transform_hash_pairs(pairs) do
      {:ok, {:literal, :collection, pairs_meta}, %{collection_type: :hash}}
    end
  end

  # Variables - M2.1 Core Layer

  # Local variable
  def transform(%{"type" => "lvar", "children" => [name]})
      when is_binary(name) or is_atom(name) do
    var_name = if is_atom(name), do: Atom.to_string(name), else: name
    {:ok, {:variable, var_name}, %{scope: :local}}
  end

  # Instance variable (@var)
  def transform(%{"type" => "ivar", "children" => [name]})
      when is_binary(name) or is_atom(name) do
    var_name = if is_atom(name), do: Atom.to_string(name), else: name
    {:ok, {:variable, var_name}, %{scope: :instance}}
  end

  # Class variable (@@var)
  def transform(%{"type" => "cvar", "children" => [name]})
      when is_binary(name) or is_atom(name) do
    var_name = if is_atom(name), do: Atom.to_string(name), else: name
    {:ok, {:variable, var_name}, %{scope: :class}}
  end

  # Global variable ($var)
  def transform(%{"type" => "gvar", "children" => [name]})
      when is_binary(name) or is_atom(name) do
    var_name = if is_atom(name), do: Atom.to_string(name), else: name
    {:ok, {:variable, var_name}, %{scope: :global}}
  end

  # Binary Operations - M2.1 Core Layer
  # In Ruby, most binary operators are implemented as method calls (send nodes)

  # Arithmetic operators: +, -, *, /, %, **
  def transform(%{"type" => "send", "children" => [left, op, right]})
      when op in [:+, :-, :*, :/, :%, :**, :"<<", :">>"] do
    with {:ok, left_meta, _} <- transform(left),
         {:ok, right_meta, _} <- transform(right) do
      {:ok, {:binary_op, :arithmetic, op, left_meta, right_meta}, %{}}
    end
  end

  # Comparison operators: ==, !=, <, >, <=, >=, <=>, ===
  def transform(%{"type" => "send", "children" => [left, op, right]})
      when op in [:==, :!=, :<, :>, :<=, :>=, :===, :eql?] or op == :"<=>" do
    with {:ok, left_meta, _} <- transform(left),
         {:ok, right_meta, _} <- transform(right) do
      {:ok, {:binary_op, :comparison, op, left_meta, right_meta}, %{}}
    end
  end

  # Boolean operators: &&, ||, and, or
  def transform(%{"type" => "and", "children" => [left, right]}) do
    with {:ok, left_meta, _} <- transform(left),
         {:ok, right_meta, _} <- transform(right) do
      {:ok, {:binary_op, :boolean, :and, left_meta, right_meta}, %{}}
    end
  end

  def transform(%{"type" => "or", "children" => [left, right]}) do
    with {:ok, left_meta, _} <- transform(left),
         {:ok, right_meta, _} <- transform(right) do
      {:ok, {:binary_op, :boolean, :or, left_meta, right_meta}, %{}}
    end
  end

  # Unary Operations - M2.1 Core Layer

  # Unary minus
  def transform(%{"type" => "send", "children" => [operand, :-, nil]}) do
    with {:ok, operand_meta, _} <- transform(operand) do
      {:ok, {:unary_op, :arithmetic, :-, operand_meta}, %{}}
    end
  end

  # Unary plus
  def transform(%{"type" => "send", "children" => [operand, :+, nil]}) do
    with {:ok, operand_meta, _} <- transform(operand) do
      {:ok, {:unary_op, :arithmetic, :+, operand_meta}, %{}}
    end
  end

  # Logical NOT: !expr, not expr
  def transform(%{"type" => "send", "children" => [operand, :!, nil]}) do
    with {:ok, operand_meta, _} <- transform(operand) do
      {:ok, {:unary_op, :boolean, :not, operand_meta}, %{}}
    end
  end

  # Method Calls - M2.1 Core Layer

  # Method call without receiver (local method call)
  def transform(%{"type" => "send", "children" => [nil, method_name | args]})
      when is_atom(method_name) do
    method_str = Atom.to_string(method_name)

    with {:ok, args_meta} <- transform_list(args) do
      {:ok, {:function_call, method_str, args_meta}, %{call_type: :local}}
    end
  end

  # Method call with receiver
  def transform(%{"type" => "send", "children" => [receiver, method_name | args]})
      when not is_nil(receiver) and is_atom(method_name) do
    with {:ok, receiver_meta, _} <- transform(receiver),
         {:ok, args_meta} <- transform_list(args) do
      # For now, represent as "receiver.method" format
      # In future, might want to preserve receiver as separate field
      method_str = "#{format_receiver(receiver_meta)}.#{method_name}"
      {:ok, {:function_call, method_str, args_meta}, %{call_type: :instance}}
    end
  end

  # Conditionals - M2.1 Core Layer

  # if/elsif/else
  def transform(%{"type" => "if", "children" => [condition, then_branch, else_branch]}) do
    with {:ok, cond_meta, _} <- transform(condition),
         {:ok, then_meta, _} <- transform_or_nil(then_branch),
         {:ok, else_meta, _} <- transform_or_nil(else_branch) do
      {:ok, {:conditional, cond_meta, then_meta, else_meta}, %{}}
    end
  end

  # Ternary operator (also parsed as if)
  # Note: Ruby's parser treats ternary the same as if

  # Assignment - M2.1 Core Layer

  # Local variable assignment
  def transform(%{"type" => "lvasgn", "children" => [name, value]}) do
    var_name = if is_atom(name), do: Atom.to_string(name), else: name

    with {:ok, value_meta, _} <- transform(value) do
      {:ok, {:assignment, {:variable, var_name}, value_meta}, %{scope: :local}}
    end
  end

  # Instance variable assignment
  def transform(%{"type" => "ivasgn", "children" => [name, value]}) do
    var_name = if is_atom(name), do: Atom.to_string(name), else: name

    with {:ok, value_meta, _} <- transform(value) do
      {:ok, {:assignment, {:variable, var_name}, value_meta}, %{scope: :instance}}
    end
  end

  # Blocks - M2.1 Core Layer

  # Begin block (sequential statements)
  def transform(%{"type" => "begin", "children" => statements}) when is_list(statements) do
    with {:ok, statements_meta} <- transform_list(statements) do
      {:ok, {:block, statements_meta}, %{}}
    end
  end

  # Catch-all for unsupported constructs
  def transform(unsupported) do
    {:error, "Unsupported Ruby AST construct: #{inspect(unsupported)}"}
  end

  # Helper Functions

  defp transform_list(items) when is_list(items) do
    items
    |> Enum.reject(&is_nil/1)
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

  defp transform_hash_pairs(pairs) when is_list(pairs) do
    pairs
    |> Enum.reduce_while({:ok, []}, fn pair, {:ok, acc} ->
      case transform_hash_pair(pair) do
        {:ok, pair_meta} -> {:cont, {:ok, [pair_meta | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, pairs} -> {:ok, Enum.reverse(pairs)}
      error -> error
    end
  end

  defp transform_hash_pair(%{"type" => "pair", "children" => [key, value]}) do
    with {:ok, key_meta, _} <- transform(key),
         {:ok, value_meta, _} <- transform(value) do
      {:ok, {:tuple, [key_meta, value_meta]}}
    end
  end

  defp transform_hash_pair(other) do
    {:error, "Invalid hash pair: #{inspect(other)}"}
  end

  defp format_receiver({:variable, name}), do: name
  defp format_receiver(_), do: "obj"
end
