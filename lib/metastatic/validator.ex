defmodule Metastatic.Validator do
  @moduledoc """
  Conformance validation for MetaAST.

  This module provides formal M1 → M2 conformance checking and validation
  of MetaAST structures according to the theoretical foundations.

  ## New 3-Tuple Format

  All MetaAST nodes are uniform 3-element tuples:

      {type_atom, keyword_meta, children_or_value}

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
        ast: {:binary_op, [category: :arithmetic, operator: :+],
              [{:variable, [], "x"}, {:literal, [subtype: :integer], 5}]},
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

      iex> doc = %Metastatic.Document{ast: {:literal, [subtype: :integer], 42}, language: :python, metadata: %{}}
      iex> {:ok, meta} = Metastatic.Validator.validate(doc)
      iex> meta.level
      :core

      iex> invalid_doc = %Metastatic.Document{ast: {:invalid_type, [], "oops"}, language: :python, metadata: %{}}
      iex> Metastatic.Validator.validate(invalid_doc)
      {:error, {:invalid_structure, {:invalid_type, [], "oops"}}}
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

      iex> doc = %Metastatic.Document{ast: {:literal, [subtype: :integer], 42}, language: :python, metadata: %{}}
      iex> Metastatic.Validator.valid?(doc)
      true

      iex> invalid_doc = %Metastatic.Document{ast: {:bad, [], "ast"}, language: :python, metadata: %{}}
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

      iex> {:ok, meta} = Metastatic.Validator.validate_ast({:literal, [subtype: :integer], 42})
      iex> meta.level
      :core

      iex> Metastatic.Validator.validate_ast({:invalid, [], "nope"})
      {:error, {:invalid_structure, {:invalid, [], "nope"}}}
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

  # Extended layer types (M2.2 + M2.2s)
  @extended_types [
    :loop,
    :lambda,
    :collection_op,
    :pattern_match,
    :match_arm,
    :exception_handling,
    :async_operation,
    # M2.2s: Structural/Organizational layer
    :container,
    :function_def,
    :attribute_access,
    :augmented_assignment,
    :property
  ]

  # Native layer types (M2.3)
  @native_types [:language_specific]

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
    {_ast, found} =
      AST.traverse(ast, false, fn node, acc -> {node, acc} end, fn
        {type, _meta, _children}, _acc when type in @extended_types -> {nil, true}
        node, acc -> {node, acc}
      end)

    found
  end

  # Count M2.3 native constructs

  defp count_native(ast) do
    {_ast, count} =
      AST.traverse(ast, 0, fn node, acc -> {node, acc} end, fn
        {type, _meta, _children}, acc when type in @native_types -> {nil, acc + 1}
        node, acc -> {node, acc}
      end)

    count
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

  # AST traversal utilities using the new 3-tuple format

  # Calculate depth using AST.traverse
  # Tracks {current_depth, max_depth_seen} during traversal
  defp calculate_depth(ast) do
    {_ast, {_current, max_depth}} =
      AST.traverse(ast, {0, 0}, &depth_pre/2, &depth_post/2)

    max_depth
  end

  # Pre: increment current depth when entering a node
  defp depth_pre({type, meta, _children} = node, {current, max_depth})
       when is_atom(type) and is_list(meta) do
    new_current = current + 1
    {node, {new_current, max(max_depth, new_current)}}
  end

  defp depth_pre(node, acc), do: {node, acc}

  # Post: decrement current depth when leaving a node
  defp depth_post({type, meta, _children} = node, {current, max_depth})
       when is_atom(type) and is_list(meta) do
    {node, {max(0, current - 1), max_depth}}
  end

  defp depth_post(node, acc), do: {node, acc}

  # Count nodes using AST.traverse
  defp count_nodes(ast) do
    {_ast, count} =
      AST.traverse(ast, 0, fn node, acc -> {node, acc} end, fn
        {type, meta, _children}, acc when is_atom(type) and is_list(meta) ->
          {nil, acc + 1}

        node, acc ->
          {node, acc}
      end)

    count
  end
end
