defmodule Metastatic.Validator do
  @moduledoc """
  Conformance validation for MetaAST.

  This module provides formal M1 → M2 conformance checking and validation
  of MetaAST structures according to the theoretical foundations.

  ## Conformance Rules (Definition 8 from THEORETICAL_FOUNDATIONS.md)

  A term `t ∈ M1` conforms to M2 if it can be represented by M2 meta-types
  without loss of essential semantic information. Validation checks:

  1. **Structural conformance** - AST structure matches M2 type definitions
  2. **Type safety** - All type tags are valid M2 types
  3. **Semantic preservation** - Required semantic information is present
  4. **Native escape hatches** - M2.3 used only when necessary

  ## Validation Levels

  - **Strict** - No M2.3 native constructs allowed (M2.1 + M2.2 + M2.2s only)
  - **Standard** - M2.3 allowed but discouraged
  - **Permissive** - All M2 levels accepted

  Note: M2.2s (Structural/Organizational layer) is part of the extended layer
  and includes container, function_def, attribute_access, augmented_assignment,
  and property types.

  ## Usage

      # Validate a MetaAST document
      alias Metastatic.Validator

      doc = %Metastatic.Document{
        ast: {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}},
        language: :python,
        metadata: %{}
      }

      Validator.validate(doc)
      # => {:ok, %{level: :core, native_constructs: 0, warnings: []}}

      # Strict validation (reject native constructs)
      Validator.validate(doc, mode: :strict)
      # => {:ok, %{...}} or {:error, :native_constructs_not_allowed}

  ## Validation Result

  Returns:
  - `{:ok, metadata}` - Valid MetaAST with validation metadata
  - `{:error, reason}` - Invalid structure

  Metadata includes:
  - `:level` - Highest M2 level used (`:core`, `:extended`, `:native`)
  - `:native_constructs` - Count of M2.3 language_specific nodes
  - `:warnings` - List of validation warnings
  - `:variables` - Set of all variables referenced
  - `:depth` - Maximum AST depth
  """

  alias Metastatic.{AST, Document}

  @type validation_mode :: :strict | :standard | :permissive
  @type validation_result :: {:ok, map()} | {:error, term()}

  @doc """
  Validate a MetaAST document.

  ## Options

  - `:mode` - Validation mode (`:strict`, `:standard`, `:permissive`)
  - `:max_depth` - Maximum allowed AST depth (default: 1000)
  - `:max_variables` - Maximum unique variables (default: 10000)

  ## Examples

      iex> doc = %Metastatic.Document{ast: {:literal, :integer, 42}, language: :python, metadata: %{}}
      iex> {:ok, meta} = Metastatic.Validator.validate(doc)
      iex> meta.level
      :core

      iex> invalid_doc = %Metastatic.Document{ast: {:invalid_type, "oops"}, language: :python, metadata: %{}}
      iex> Metastatic.Validator.validate(invalid_doc)
      {:error, {:invalid_structure, {:invalid_type, "oops"}}}
  """
  @spec validate(Document.t(), keyword()) :: validation_result()
  def validate(%Document{} = document, opts \\ []) do
    mode = Keyword.get(opts, :mode, :standard)
    max_depth = Keyword.get(opts, :max_depth, 1000)
    max_variables = Keyword.get(opts, :max_variables, 10_000)

    with {:ok, _} <- validate_structure(document.ast),
         {:ok, meta} <- analyze_ast(document.ast),
         :ok <- check_constraints(meta, mode, max_depth, max_variables) do
      {:ok, meta}
    end
  end

  @doc """
  Quick validation check - returns boolean.

  ## Examples

      iex> doc = %Metastatic.Document{ast: {:literal, :integer, 42}, language: :python, metadata: %{}}
      iex> Metastatic.Validator.valid?(doc)
      true

      iex> invalid_doc = %Metastatic.Document{ast: {:bad, "ast"}, language: :python, metadata: %{}}
      iex> Metastatic.Validator.valid?(invalid_doc)
      false
  """
  @spec valid?(Document.t(), keyword()) :: boolean()
  def valid?(%Document{} = document, opts \\ []) do
    case validate(document, opts) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Validate just the AST structure (without Document wrapper).

  ## Examples

      iex> {:ok, meta} = Metastatic.Validator.validate_ast({:literal, :integer, 42})
      iex> meta.level
      :core

      iex> Metastatic.Validator.validate_ast({:invalid, "nope"})
      {:error, {:invalid_structure, {:invalid, "nope"}}}
  """
  @spec validate_ast(AST.meta_ast(), keyword()) :: validation_result()
  def validate_ast(ast, opts \\ []) do
    mode = Keyword.get(opts, :mode, :standard)
    max_depth = Keyword.get(opts, :max_depth, 1000)
    max_variables = Keyword.get(opts, :max_variables, 10_000)

    with {:ok, _} <- validate_structure(ast),
         {:ok, meta} <- analyze_ast(ast),
         :ok <- check_constraints(meta, mode, max_depth, max_variables) do
      {:ok, meta}
    end
  end

  # Structural validation

  defp validate_structure(ast) do
    if AST.conforms?(ast) do
      {:ok, ast}
    else
      {:error, {:invalid_structure, ast}}
    end
  end

  # AST analysis

  defp analyze_ast(ast) do
    meta = %{
      level: determine_level(ast),
      native_constructs: count_native(ast),
      warnings: generate_warnings(ast),
      variables: AST.variables(ast),
      depth: calculate_depth(ast),
      node_count: count_nodes(ast)
    }

    {:ok, meta}
  end

  # Determine highest M2 level used

  defp determine_level(ast) do
    cond do
      has_native?(ast) -> :native
      has_extended?(ast) -> :extended
      true -> :core
    end
  end

  defp has_native?(ast) do
    count_native(ast) > 0
  end

  defp has_extended?(ast) do
    walk_ast(ast, false, fn
      # M2.2: Extended layer - Common patterns with variations
      {:loop, _, _, _}, _acc -> true
      {:lambda, _, _, _}, _acc -> true
      {:collection_op, _, _, _}, _acc -> true
      {:pattern_match, _, _}, _acc -> true
      {:exception_handling, _, _, _}, _acc -> true
      {:async_operation, _, _}, _acc -> true
      # M2.2s: Structural/Organizational layer
      {:container, _, _, _, _}, _acc -> true
      {:function_def, _, _, _, _, _}, _acc -> true
      {:attribute_access, _, _}, _acc -> true
      {:augmented_assignment, _, _, _}, _acc -> true
      {:property, _, _, _, _}, _acc -> true
      # M2.1 Core: list and map are NOT extended
      # {:list, _}, _acc -> false
      # {:map, _}, _acc -> false
      _node, acc -> acc
    end)
  end

  # Count M2.3 native constructs

  defp count_native(ast) do
    walk_ast(ast, 0, fn
      {:language_specific, _, _}, acc -> acc + 1
      _node, acc -> acc
    end)
  end

  # Generate validation warnings

  defp generate_warnings(ast) do
    warnings = []

    warnings =
      if has_native?(ast) do
        [{:native_constructs_present, count_native(ast)} | warnings]
      else
        warnings
      end

    warnings =
      if calculate_depth(ast) > 100 do
        [{:deep_nesting, calculate_depth(ast)} | warnings]
      else
        warnings
      end

    warnings =
      if count_nodes(ast) > 1000 do
        [{:large_ast, count_nodes(ast)} | warnings]
      else
        warnings
      end

    Enum.reverse(warnings)
  end

  # Check validation constraints

  defp check_constraints(meta, mode, max_depth, max_variables) do
    with :ok <- check_mode(meta, mode),
         :ok <- check_depth(meta.depth, max_depth) do
      check_variables(meta.variables, max_variables)
    end
  end

  defp check_mode(meta, :strict) do
    if meta.native_constructs > 0 do
      {:error, :native_constructs_not_allowed}
    else
      :ok
    end
  end

  defp check_mode(_meta, _mode), do: :ok

  defp check_depth(depth, max_depth) do
    if depth > max_depth do
      {:error, {:max_depth_exceeded, depth, max_depth}}
    else
      :ok
    end
  end

  defp check_variables(variables, max_variables) do
    count = MapSet.size(variables)

    if count > max_variables do
      {:error, {:too_many_variables, count, max_variables}}
    else
      :ok
    end
  end

  # AST traversal utilities

  defp calculate_depth(ast, current_depth \\ 0)

  defp calculate_depth({type, _} = ast, current_depth)
       when type in [:literal, :variable] do
    max(current_depth + 1, depth_of_children(ast, current_depth + 1))
  end

  defp calculate_depth(ast, current_depth) when is_tuple(ast) do
    max(current_depth + 1, depth_of_children(ast, current_depth + 1))
  end

  defp calculate_depth(_ast, current_depth), do: current_depth

  defp depth_of_children(ast, current_depth) when is_tuple(ast) do
    ast
    |> Tuple.to_list()
    |> Enum.reduce(current_depth, fn
      child, max_depth when is_tuple(child) ->
        max(max_depth, calculate_depth(child, current_depth))

      child, max_depth when is_list(child) ->
        child_depths =
          Enum.map(child, fn item ->
            if is_tuple(item), do: calculate_depth(item, current_depth), else: current_depth
          end)

        max(max_depth, Enum.max(child_depths ++ [current_depth]))

      _other, max_depth ->
        max_depth
    end)
  end

  defp depth_of_children(_ast, current_depth), do: current_depth

  defp count_nodes(ast) do
    walk_ast(ast, 0, fn _node, acc -> acc + 1 end)
  end

  defp walk_ast(ast, acc, fun) when is_tuple(ast) do
    acc = fun.(ast, acc)

    ast
    |> Tuple.to_list()
    |> Enum.reduce(acc, fn
      child, acc when is_tuple(child) -> walk_ast(child, acc, fun)
      children, acc when is_list(children) -> walk_ast_list(children, acc, fun)
      _other, acc -> acc
    end)
  end

  defp walk_ast(ast, acc, fun) when is_list(ast) do
    walk_ast_list(ast, acc, fun)
  end

  defp walk_ast(_ast, acc, _fun), do: acc

  defp walk_ast_list(list, acc, fun) do
    Enum.reduce(list, acc, fn
      item, acc when is_tuple(item) -> walk_ast(item, acc, fun)
      item, acc when is_list(item) -> walk_ast_list(item, acc, fun)
      _other, acc -> acc
    end)
  end
end
