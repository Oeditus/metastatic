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

  # M2.1 Core Layer - Literals (New 3-tuple format)

  def transform({:literal, meta, value}, _metadata) when is_list(meta) do
    subtype = Keyword.get(meta, :subtype)

    case subtype do
      :integer -> {:ok, %{"type" => "int", "children" => [value]}}
      :float -> {:ok, %{"type" => "float", "children" => [value]}}
      :string -> {:ok, %{"type" => "str", "children" => [value]}}
      :symbol -> {:ok, %{"type" => "sym", "children" => [value]}}
      :boolean when value == true -> {:ok, %{"type" => "true", "children" => []}}
      :boolean when value == false -> {:ok, %{"type" => "false", "children" => []}}
      :null -> {:ok, %{"type" => "nil", "children" => []}}
      :constant -> {:ok, %{"type" => "const", "children" => [nil, value]}}
      _ -> {:error, "Unknown literal subtype: #{subtype}"}
    end
  end

  # Lists (New 3-tuple format)
  def transform({:list, meta, elements}, _metadata) when is_list(meta) do
    with {:ok, elements_ast} <- transform_list(elements) do
      {:ok, %{"type" => "array", "children" => elements_ast}}
    end
  end

  # Maps (New 3-tuple format)
  def transform({:map, meta, pairs}, _metadata) when is_list(meta) do
    with {:ok, pairs_ast} <- transform_hash_pairs(pairs) do
      {:ok, %{"type" => "hash", "children" => pairs_ast}}
    end
  end

  # Pairs (New 3-tuple format)
  def transform({:pair, meta, [key, value]}, _metadata) when is_list(meta) do
    with {:ok, key_ast} <- transform(key, %{}),
         {:ok, value_ast} <- transform(value, %{}) do
      {:ok, %{"type" => "pair", "children" => [key_ast, value_ast]}}
    end
  end

  # M2.1 Core Layer - Variables (New 3-tuple format)

  def transform({:variable, meta, name}, _metadata) when is_list(meta) do
    scope = Keyword.get(meta, :scope, :local)

    case scope do
      :local -> {:ok, %{"type" => "lvar", "children" => [name]}}
      :instance -> {:ok, %{"type" => "ivar", "children" => [name]}}
      :class -> {:ok, %{"type" => "cvar", "children" => [name]}}
      :global -> {:ok, %{"type" => "gvar", "children" => [name]}}
      :special when name == "self" -> {:ok, %{"type" => "self", "children" => []}}
      _ -> {:ok, %{"type" => "lvar", "children" => [name]}}
    end
  end

  # M2.1 Core Layer - Binary Operations (New 3-tuple format)

  def transform({:binary_op, meta, [left, right]}, _metadata) when is_list(meta) do
    category = Keyword.get(meta, :category)
    op = Keyword.get(meta, :operator)

    with {:ok, left_ast} <- transform(left, %{}),
         {:ok, right_ast} <- transform(right, %{}) do
      case category do
        :arithmetic -> {:ok, %{"type" => "send", "children" => [left_ast, op, right_ast]}}
        :comparison -> {:ok, %{"type" => "send", "children" => [left_ast, op, right_ast]}}
        :boolean when op == :and -> {:ok, %{"type" => "and", "children" => [left_ast, right_ast]}}
        :boolean when op == :or -> {:ok, %{"type" => "or", "children" => [left_ast, right_ast]}}
      end
    end
  end

  # M2.1 Core Layer - Unary Operations (New 3-tuple format)

  def transform({:unary_op, meta, [operand]}, _metadata) when is_list(meta) do
    category = Keyword.get(meta, :category)
    op = Keyword.get(meta, :operator)

    with {:ok, operand_ast} <- transform(operand, %{}) do
      case {category, op} do
        {:arithmetic, _} -> {:ok, %{"type" => "send", "children" => [operand_ast, op, nil]}}
        {:boolean, :not} -> {:ok, %{"type" => "send", "children" => [operand_ast, :!, nil]}}
      end
    end
  end

  # M2.1 Core Layer - Function Calls (New 3-tuple format)

  def transform({:function_call, meta, args}, _metadata) when is_list(meta) do
    name = Keyword.get(meta, :name)

    with {:ok, args_ast} <- transform_list(args) do
      {:ok, %{"type" => "send", "children" => [nil, String.to_atom(name) | args_ast]}}
    end
  end

  # M2.1 Core Layer - Conditionals (New 3-tuple format)

  def transform({:conditional, meta, [condition, then_branch, else_branch]}, _metadata)
      when is_list(meta) do
    with {:ok, cond_ast} <- transform(condition, %{}),
         {:ok, then_ast} <- transform_or_nil(then_branch),
         {:ok, else_ast} <- transform_or_nil(else_branch) do
      {:ok, %{"type" => "if", "children" => [cond_ast, then_ast, else_ast]}}
    end
  end

  # M2.1 Core Layer - Assignment (New 3-tuple format)

  def transform({:assignment, meta, [target, value]}, _metadata) when is_list(meta) do
    scope = Keyword.get(meta, :scope, :local)

    # Extract variable name from target
    name =
      case target do
        {:variable, _, n} -> n
        n when is_binary(n) -> n
      end

    with {:ok, value_ast} <- transform(value, %{}) do
      case scope do
        :local -> {:ok, %{"type" => "lvasgn", "children" => [name, value_ast]}}
        :instance -> {:ok, %{"type" => "ivasgn", "children" => [name, value_ast]}}
        :class -> {:ok, %{"type" => "cvasgn", "children" => [name, value_ast]}}
        :global -> {:ok, %{"type" => "gvasgn", "children" => [name, value_ast]}}
        _ -> {:ok, %{"type" => "lvasgn", "children" => [name, value_ast]}}
      end
    end
  end

  # M2.1 Core Layer - Blocks (New 3-tuple format)

  def transform({:block, meta, statements}, _metadata) when is_list(meta) do
    with {:ok, statements_ast} <- transform_list(statements) do
      {:ok, %{"type" => "begin", "children" => statements_ast}}
    end
  end

  # M2.2 Extended Layer - Loops (New 3-tuple format)

  def transform({:loop, meta, children}, _metadata) when is_list(meta) do
    loop_type = Keyword.get(meta, :loop_type)

    case {loop_type, children} do
      {:while, [condition, body]} ->
        with {:ok, cond_ast} <- transform(condition, %{}),
             {:ok, body_ast} <- transform_or_nil(body) do
          {:ok, %{"type" => "while", "children" => [cond_ast, body_ast]}}
        end

      {:for_each, [var, collection, body]} ->
        with {:ok, collection_ast} <- transform(collection, %{}),
             {:ok, body_ast} <- transform_or_nil(body) do
          var_ast = %{"type" => "lvasgn", "children" => [var]}
          {:ok, %{"type" => "for", "children" => [var_ast, collection_ast, body_ast]}}
        end
    end
  end

  # M2.2s Structural Layer - Container support (New 3-tuple format)

  def transform({:container, meta, [body]}, _metadata) when is_list(meta) do
    container_type = Keyword.get(meta, :container_type)
    name = Keyword.get(meta, :name)
    parent = Keyword.get(meta, :parent)

    with {:ok, name_ast} <- build_const_ast(name),
         {:ok, body_ast} <- transform_or_nil(body) do
      case container_type do
        :class ->
          {:ok, parent_ast} = build_const_ast_or_nil(parent)
          {:ok, %{"type" => "class", "children" => [name_ast, parent_ast, body_ast]}}

        :module ->
          {:ok, %{"type" => "module", "children" => [name_ast, body_ast]}}
      end
    end
  end

  # Handle container with location (4-tuple)
  def transform({:container, meta, [body], _loc}, metadata) when is_list(meta) do
    transform({:container, meta, [body]}, metadata)
  end

  # M2.2s Structural Layer - Function definition support (New 3-tuple format)

  def transform({:function_def, meta, [body]}, _metadata) when is_list(meta) do
    name = Keyword.get(meta, :name)
    params = Keyword.get(meta, :params, [])

    args_ast = build_args_ast(params)

    with {:ok, body_ast} <- transform_or_nil(body) do
      # Check if it's a class method (self.method_name)
      if String.starts_with?(name, "self.") do
        method_name = String.replace_prefix(name, "self.", "")
        self_ast = %{"type" => "self", "children" => []}
        {:ok, %{"type" => "defs", "children" => [self_ast, method_name, args_ast, body_ast]}}
      else
        {:ok, %{"type" => "def", "children" => [name, args_ast, body_ast]}}
      end
    end
  end

  # Handle function_def with location (4-tuple)
  def transform({:function_def, meta, [body], _loc}, metadata) when is_list(meta) do
    transform({:function_def, meta, [body]}, metadata)
  end

  # M2.2s Structural Layer - Attribute access (New 3-tuple format)

  def transform({:attribute_access, meta, [receiver]}, _metadata) when is_list(meta) do
    attribute = Keyword.get(meta, :attribute)

    with {:ok, receiver_ast} <- transform(receiver, %{}) do
      {:ok, %{"type" => "send", "children" => [receiver_ast, String.to_atom(attribute)]}}
    end
  end

  # M2.2s Structural Layer - Augmented assignment (New 3-tuple format)

  def transform({:augmented_assignment, meta, [target, value]}, _metadata) when is_list(meta) do
    op = Keyword.get(meta, :operator)

    with {:ok, target_ast} <- transform(target, %{}),
         {:ok, value_ast} <- transform(value, %{}) do
      {:ok, %{"type" => "op_asgn", "children" => [target_ast, op, value_ast]}}
    end
  end

  # M2.1 Core Layer - Early return (New 3-tuple format)

  def transform({:early_return, meta, [value]}, _metadata) when is_list(meta) do
    with {:ok, value_ast} <- transform_or_nil(value) do
      if is_nil(value_ast) do
        {:ok, %{"type" => "return", "children" => []}}
      else
        {:ok, %{"type" => "return", "children" => [value_ast]}}
      end
    end
  end

  # M2.1 Core Layer - Tuple (for multiple return values)

  def transform({:tuple, meta, elements}, _metadata) when is_list(meta) do
    with {:ok, elements_ast} <- transform_list(elements) do
      {:ok, %{"type" => "array", "children" => elements_ast}}
    end
  end

  # M2.2 Extended Layer - Lambda with proc kind

  def transform({:lambda, meta, [body]}, _metadata) when is_list(meta) do
    params = Keyword.get(meta, :params, [])
    kind = Keyword.get(meta, :kind, :lambda)

    args_ast = build_args_ast(params)

    with {:ok, body_ast} <- transform_or_nil(body) do
      case kind do
        :proc ->
          # Rebuild as proc { |params| body }
          {:ok,
           %{
             "type" => "block",
             "children" => [
               %{"type" => "send", "children" => [nil, "proc"]},
               args_ast,
               body_ast
             ]
           }}

        _ ->
          # Regular lambda
          {:ok,
           %{
             "type" => "block",
             "children" => [
               %{"type" => "send", "children" => [nil, "lambda"]},
               args_ast,
               body_ast
             ]
           }}
      end
    end
  end

  # M2.2 Extended Layer - Collection operations

  def transform({:collection_op, meta, [lambda, collection | rest]}, _metadata)
      when is_list(meta) do
    op_type = Keyword.get(meta, :op_type)

    with {:ok, lambda_ast} <- transform(lambda, %{}),
         {:ok, collection_ast} <- transform_or_nil(collection) do
      case op_type do
        :times ->
          # N.times { |i| body }
          {:ok,
           %{
             "type" => "block",
             "children" => [
               %{"type" => "send", "children" => [collection_ast, :times]},
               lambda_ast["children"] |> Enum.at(1),
               lambda_ast["children"] |> Enum.at(2)
             ]
           }}

        :reduce when rest != [] ->
          [initial | _] = rest
          {:ok, initial_ast} = transform_or_nil(initial)

          {:ok,
           %{
             "type" => "block",
             "children" => [
               %{"type" => "send", "children" => [collection_ast, :reduce, initial_ast]},
               lambda_ast["children"] |> Enum.at(1),
               lambda_ast["children"] |> Enum.at(2)
             ]
           }}

        op ->
          {:ok,
           %{
             "type" => "block",
             "children" => [
               %{"type" => "send", "children" => [collection_ast, op]},
               lambda_ast["children"] |> Enum.at(1),
               lambda_ast["children"] |> Enum.at(2)
             ]
           }}
      end
    end
  end

  # Literal ranges

  def transform({:literal, meta, {start_val, end_val}}, _metadata) when is_list(meta) do
    subtype = Keyword.get(meta, :subtype)
    inclusive = Keyword.get(meta, :inclusive, true)

    case subtype do
      :range ->
        with {:ok, start_ast} <- transform(start_val, %{}),
             {:ok, end_ast} <- transform(end_val, %{}) do
          type = if inclusive, do: "irange", else: "erange"
          {:ok, %{"type" => type, "children" => [start_ast, end_ast]}}
        end

      _ ->
        {:error, "Unknown tuple literal subtype: #{subtype}"}
    end
  end

  # M2.3 Native Layer - Passthrough (New 3-tuple format)

  def transform({:language_specific, meta, original_ast}, _metadata) when is_list(meta) do
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

  defp transform_hash_pairs(pairs) when is_list(pairs) do
    pairs
    |> Enum.reduce_while({:ok, []}, fn pair, {:ok, acc} ->
      case transform(pair, %{}) do
        {:ok, ast} -> {:cont, {:ok, [ast | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, pairs_ast} -> {:ok, Enum.reverse(pairs_ast)}
      error -> error
    end
  end

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
        {:param, meta, name} when is_binary(name) ->
          # New 3-tuple format: {:param, [pattern: pattern, default: default], name}
          pattern = Keyword.get(meta, :pattern)
          default = Keyword.get(meta, :default)

          cond do
            pattern != nil ->
              %{"type" => "arg", "children" => ["_pattern"]}

            default != nil ->
              %{"type" => "optarg", "children" => [name]}

            true ->
              %{"type" => "arg", "children" => [name]}
          end

        param when is_binary(param) ->
          %{"type" => "arg", "children" => [param]}

        {:pattern, _meta} ->
          # Legacy pattern parameters
          %{"type" => "arg", "children" => ["_pattern"]}

        {:default, name, _default_val} ->
          # Legacy default parameters
          %{"type" => "arg", "children" => [name]}
      end)

    %{"type" => "args", "children" => children}
  end
end
