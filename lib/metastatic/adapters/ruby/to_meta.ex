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

  # Constant (e.g., StandardError, Array, Hash)
  def transform(%{"type" => "const", "children" => [namespace, name]}) do
    const_name = if is_atom(name), do: Atom.to_string(name), else: name

    qualified_name =
      if is_nil(namespace) do
        const_name
      else
        with {:ok, namespace_meta, _} <- transform(namespace) do
          "#{format_const(namespace_meta)}::#{const_name}"
        end
      end

    case qualified_name do
      {:ok, _, _} = result -> result
      name when is_binary(name) -> {:ok, {:literal, :constant, name}, %{}}
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
  # Operators can be either atoms or strings from JSON
  def transform(%{"type" => "send", "children" => [left, op, right]}) when not is_nil(right) do
    cond do
      is_arithmetic_op?(op) ->
        op_atom = normalize_op(op)

        with {:ok, left_meta, _} <- transform(left),
             {:ok, right_meta, _} <- transform(right) do
          {:ok, {:binary_op, :arithmetic, op_atom, left_meta, right_meta}, %{}}
        end

      is_comparison_op?(op) ->
        op_atom = normalize_op(op)

        with {:ok, left_meta, _} <- transform(left),
             {:ok, right_meta, _} <- transform(right) do
          {:ok, {:binary_op, :comparison, op_atom, left_meta, right_meta}, %{}}
        end

      true ->
        # Regular method call with receiver
        transform_method_call_with_receiver(left, op, right)
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

  # Unary operators - 3 children with nil as third: [operand, op, nil]
  def transform(%{"type" => "send", "children" => [operand, op, nil]}) do
    op_atom = normalize_op(op)

    cond do
      op_atom in [:-, :+] ->
        with {:ok, operand_meta, _} <- transform(operand) do
          {:ok, {:unary_op, :arithmetic, op_atom, operand_meta}, %{}}
        end

      op_atom == :! ->
        with {:ok, operand_meta, _} <- transform(operand) do
          {:ok, {:unary_op, :boolean, :not, operand_meta}, %{}}
        end

      true ->
        # Not actually a unary operator
        {:error, "Invalid unary operator: #{op}"}
    end
  end

  # Method call without arguments: 2 children [receiver, method]
  def transform(%{"type" => "send", "children" => [receiver, method]}) do
    method_str = if is_atom(method), do: Atom.to_string(method), else: method

    if is_nil(receiver) do
      # Local method call without args: hello
      {:ok, {:function_call, method_str, []}, %{call_type: :local}}
    else
      # Method call with receiver but no arguments: obj.method
      with {:ok, receiver_meta, _} <- transform(receiver) do
        qualified_name = "#{format_receiver(receiver_meta)}.#{method_str}"
        {:ok, {:function_call, qualified_name, []}, %{call_type: :instance}}
      end
    end
  end

  # Method Calls - M2.1 Core Layer

  # Method call without receiver (local method call)
  def transform(%{"type" => "send", "children" => [nil, method_name | args]}) do
    method_str = if is_atom(method_name), do: Atom.to_string(method_name), else: method_name

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

  # Local variable binding (without value, e.g., in rescue clauses)
  def transform(%{"type" => "lvasgn", "children" => [name]}) do
    var_name = if is_atom(name), do: Atom.to_string(name), else: name
    {:ok, {:variable, var_name}, %{scope: :local, binding: true}}
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

  # Loops - M2.2 Extended Layer

  # While loop: while condition do body end
  def transform(%{"type" => "while", "children" => [condition, body]}) do
    with {:ok, cond_meta, _} <- transform(condition),
         {:ok, body_meta, _} <- transform_or_nil(body) do
      {:ok, {:loop, :while, cond_meta, body_meta}, %{}}
    end
  end

  # Until loop: until condition do body end
  def transform(%{"type" => "until", "children" => [condition, body]}) do
    with {:ok, cond_meta, _} <- transform(condition),
         {:ok, body_meta, _} <- transform_or_nil(body) do
      # Until is equivalent to "while not condition"
      negated_cond = {:unary_op, :boolean, :not, cond_meta}
      {:ok, {:loop, :while, negated_cond, body_meta}, %{original_type: :until}}
    end
  end

  # For loop: for var in collection do body end
  def transform(%{"type" => "for", "children" => [var_asgn, collection, body]}) do
    with {:ok, var_meta, _} <- transform_iterator_variable(var_asgn),
         {:ok, collection_meta, _} <- transform(collection),
         {:ok, body_meta, _} <- transform_or_nil(body) do
      {:ok, {:loop, :for_each, var_meta, collection_meta, body_meta}, %{}}
    end
  end

  # Blocks with parameters and iterators - M2.2 Extended Layer

  # Block with receiver (iterator methods: each, map, select, reduce, etc.)
  # Structure: block [send [collection, method, ...args], args [param...], body]
  def transform(%{"type" => "block", "children" => [send_node, args_node, body]}) do
    case send_node do
      # Lambda: lambda { |x| body } or ->(x) { body }
      %{"type" => "send", "children" => [nil, "lambda"]} ->
        transform_lambda(args_node, body)

      # Iterator methods: [1,2,3].each { |x| ... }
      %{"type" => "send", "children" => [collection, method | method_args]} ->
        transform_iterator_method(collection, method, method_args, args_node, body)

      _ ->
        {:error, "Unsupported block construct: #{inspect(send_node)}"}
    end
  end

  # Pattern Matching - M2.2 Extended Layer

  # Case/when statement
  def transform(%{"type" => "case", "children" => children}) do
    [scrutinee | branches] = children
    {else_branch, when_branches} = extract_else_branch(branches)

    with {:ok, scrutinee_meta, _} <- transform(scrutinee),
         {:ok, branches_meta} <- transform_when_branches(when_branches),
         {:ok, else_meta, _} <- transform_or_nil(else_branch) do
      {:ok, {:pattern_match, scrutinee_meta, branches_meta, else_meta}, %{}}
    end
  end

  # Exception Handling - M2.2 Extended Layer

  # Begin/rescue/ensure block
  def transform(%{"type" => "kwbegin", "children" => [ensure_or_rescue]}) do
    transform(ensure_or_rescue)
  end

  # Ensure block (with or without rescue)
  def transform(%{"type" => "ensure", "children" => [try_body, ensure_body]}) do
    case try_body do
      %{"type" => "rescue"} ->
        # Has both rescue and ensure
        with {:ok, rescue_meta, rescue_metadata} <- transform(try_body),
             {:ok, ensure_meta, _} <- transform(ensure_body) do
          # Merge rescue handlers with ensure
          metadata = Map.put(rescue_metadata, :ensure, ensure_meta)
          {:ok, rescue_meta, metadata}
        end

      _ ->
        # Only ensure, no rescue
        with {:ok, try_meta, _} <- transform(try_body),
             {:ok, ensure_meta, _} <- transform(ensure_body) do
          {:ok, {:exception_handling, try_meta, [], nil}, %{ensure: ensure_meta}}
        end
    end
  end

  # Rescue block
  def transform(%{"type" => "rescue", "children" => children}) do
    [try_body | rescue_bodies] = children
    rescue_handlers = Enum.filter(rescue_bodies, &match?(%{"type" => "resbody"}, &1))
    else_body = Enum.find(rescue_bodies, fn node -> not match?(%{"type" => "resbody"}, node) end)

    with {:ok, try_meta, _} <- transform(try_body),
         {:ok, handlers_meta} <- transform_rescue_handlers(rescue_handlers),
         {:ok, else_meta, _} <- transform_or_nil(else_body) do
      {:ok, {:exception_handling, try_meta, handlers_meta, else_meta}, %{}}
    end
  end

  # M2.3 Native Layer - Ruby-specific constructs

  # Class definition
  def transform(%{"type" => "class", "children" => [name, superclass, body]} = ast) do
    with {:ok, name_meta, _} <- transform(name),
         {:ok, superclass_meta, _} <- transform_or_nil(superclass),
         {:ok, body_meta, _} <- transform_or_nil(body) do
      metadata = %{
        name: extract_constant_name(name_meta),
        superclass: superclass_meta,
        body: body_meta
      }

      {:ok, {:language_specific, :ruby, ast, :class_definition}, metadata}
    end
  end

  # Module definition
  def transform(%{"type" => "module", "children" => [name, body]} = ast) do
    with {:ok, name_meta, _} <- transform(name),
         {:ok, body_meta, _} <- transform_or_nil(body) do
      metadata = %{
        name: extract_constant_name(name_meta),
        body: body_meta
      }

      {:ok, {:language_specific, :ruby, ast, :module_definition}, metadata}
    end
  end

  # Method definition (def)
  def transform(%{"type" => "def", "children" => [name, args, body]} = ast) do
    method_name = if is_atom(name), do: Atom.to_string(name), else: name

    with {:ok, params} <- extract_method_params(args),
         {:ok, body_meta, _} <- transform_or_nil(body) do
      metadata = %{
        name: method_name,
        params: params,
        body: body_meta
      }

      {:ok, {:language_specific, :ruby, ast, :method_definition}, metadata}
    end
  end

  # Constant assignment (e.g., BAR = 42)
  def transform(%{"type" => "casgn", "children" => [namespace, name, value]} = ast) do
    const_name = if is_atom(name), do: Atom.to_string(name), else: name

    with {:ok, value_meta, _} <- transform(value) do
      metadata = %{
        name: const_name,
        namespace: namespace,
        value: value_meta
      }

      {:ok, {:language_specific, :ruby, ast, :constant_assignment}, metadata}
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

  defp format_const({:literal, :constant, name}), do: name
  defp format_const(_), do: "Unknown"

  # Operator normalization helpers
  defp normalize_op(op) when is_atom(op), do: op
  defp normalize_op(op) when is_binary(op), do: String.to_atom(op)

  defp is_arithmetic_op?(op) when is_atom(op) do
    op in [:+, :-, :*, :/, :%, :**] or op == :"<<" or op == :">>"
  end

  defp is_arithmetic_op?(op) when is_binary(op) do
    op in ["+", "-", "*", "/", "%", "**", "<<", ">>"]
  end

  defp is_comparison_op?(op) when is_atom(op) do
    op in [:==, :!=, :<, :>, :<=, :>=, :===, :eql?, :"<=>"]
  end

  defp is_comparison_op?(op) when is_binary(op) do
    op in ["==", "!=", "<", ">", "<=", ">=", "===", "eql?", "<=>"]
  end

  defp transform_method_call_with_receiver(receiver, method_name, arg) do
    method_str = if is_atom(method_name), do: Atom.to_string(method_name), else: method_name

    with {:ok, receiver_meta, _} <- transform(receiver),
         {:ok, arg_meta, _} <- transform(arg) do
      qualified_name = "#{format_receiver(receiver_meta)}.#{method_str}"
      {:ok, {:function_call, qualified_name, [arg_meta]}, %{call_type: :instance}}
    end
  end

  # M2.2 Extended Layer Helper Functions

  # Transform iterator variable (from lvasgn in for loops)
  defp transform_iterator_variable(%{"type" => "lvasgn", "children" => [name]}) do
    var_name = if is_atom(name), do: Atom.to_string(name), else: name
    {:ok, var_name, %{}}
  end

  defp transform_iterator_variable(other) do
    {:error, "Invalid iterator variable: #{inspect(other)}"}
  end

  # Transform lambda
  defp transform_lambda(args_node, body) do
    with {:ok, params} <- extract_lambda_params(args_node),
         {:ok, body_meta, _} <- transform(body) do
      {:ok, {:lambda, params, body_meta}, %{}}
    end
  end

  # Extract lambda parameters from args node
  defp extract_lambda_params(%{"type" => "args", "children" => args}) do
    params =
      Enum.map(args, fn
        %{"type" => "arg", "children" => [name]} when is_binary(name) -> name
        %{"type" => "arg", "children" => [name]} when is_atom(name) -> Atom.to_string(name)
        _ -> nil
      end)
      |> Enum.reject(&is_nil/1)

    {:ok, params}
  end

  defp extract_lambda_params(_), do: {:ok, []}

  # Transform iterator methods (map, each, select, reduce)
  defp transform_iterator_method(collection, method, method_args, args_node, body) do
    method_atom = normalize_op(method)

    case method_atom do
      m when m in [:each, :map, :select, :filter, :reject] ->
        transform_map_like_iterator(collection, m, args_node, body)

      :reduce ->
        transform_reduce_iterator(collection, method_args, args_node, body)

      _ ->
        # Not a recognized iterator, treat as generic block
        {:error, "Unrecognized iterator method: #{method}"}
    end
  end

  # Transform map-like iterators (each, map, select, filter)
  defp transform_map_like_iterator(collection, method, args_node, body) do
    with {:ok, collection_meta, _} <- transform(collection),
         {:ok, params} <- extract_lambda_params(args_node),
         {:ok, body_meta, _} <- transform(body) do
      lambda = {:lambda, params, body_meta}
      {:ok, {:collection_op, method, lambda, collection_meta}, %{}}
    end
  end

  # Transform reduce iterator
  defp transform_reduce_iterator(collection, method_args, args_node, body) do
    with {:ok, collection_meta, _} <- transform(collection),
         {:ok, initial_meta} <- extract_reduce_initial(method_args),
         {:ok, params} <- extract_lambda_params(args_node),
         {:ok, body_meta, _} <- transform(body) do
      lambda = {:lambda, params, body_meta}
      {:ok, {:collection_op, :reduce, lambda, collection_meta, initial_meta}, %{}}
    end
  end

  # Extract initial value from reduce method args
  defp extract_reduce_initial([initial | _]) do
    case transform(initial) do
      {:ok, meta, _} -> {:ok, meta}
      error -> error
    end
  end

  defp extract_reduce_initial([]), do: {:ok, nil}

  # Pattern matching helpers
  defp extract_else_branch(branches) do
    else_branch = Enum.find(branches, fn node -> not match?(%{"type" => "when"}, node) end)
    when_branches = Enum.filter(branches, &match?(%{"type" => "when"}, &1))
    {else_branch, when_branches}
  end

  defp transform_when_branches(when_branches) do
    when_branches
    |> Enum.reduce_while({:ok, []}, fn when_node, {:ok, acc} ->
      case transform_when_branch(when_node) do
        {:ok, branch_meta} -> {:cont, {:ok, [branch_meta | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, branches} -> {:ok, Enum.reverse(branches)}
      error -> error
    end
  end

  defp transform_when_branch(%{"type" => "when", "children" => [pattern | rest]}) do
    # Rest is either [body] or [] if body is nil
    body = List.first(rest)

    with {:ok, pattern_meta, _} <- transform(pattern),
         {:ok, body_meta, _} <- transform_or_nil(body) do
      {:ok, {pattern_meta, body_meta}}
    end
  end

  # Exception handling helpers
  defp transform_rescue_handlers(handlers) do
    handlers
    |> Enum.reduce_while({:ok, []}, fn handler, {:ok, acc} ->
      case transform_rescue_handler(handler) do
        {:ok, handler_meta} -> {:cont, {:ok, [handler_meta | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, handlers} -> {:ok, Enum.reverse(handlers)}
      error -> error
    end
  end

  defp transform_rescue_handler(%{
         "type" => "resbody",
         "children" => [exception_types, var_binding, body]
       }) do
    with {:ok, types_meta} <- transform_exception_types(exception_types),
         {:ok, var_meta, _} <- transform_or_nil(var_binding),
         {:ok, body_meta, _} <- transform(body) do
      {:ok, {types_meta, var_meta, body_meta}}
    end
  end

  defp transform_exception_types(%{"type" => "array", "children" => types}) do
    transform_list(types)
  end

  defp transform_exception_types(nil), do: {:ok, []}

  # M2.3 Native Layer Helpers

  defp extract_constant_name({:literal, :constant, name}), do: name
  defp extract_constant_name(_), do: "Unknown"

  defp extract_method_params(%{"type" => "args", "children" => args}) do
    params =
      Enum.map(args, fn
        %{"type" => "arg", "children" => [name]} when is_binary(name) -> name
        %{"type" => "arg", "children" => [name]} when is_atom(name) -> Atom.to_string(name)
        _ -> nil
      end)
      |> Enum.reject(&is_nil/1)

    {:ok, params}
  end

  defp extract_method_params(_), do: {:ok, []}
end
