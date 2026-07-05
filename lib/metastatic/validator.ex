defmodule Metastatic.Validator do
  @moduledoc """
  Conformance validation for MetaAST.

  This module provides formal M1 -> M2 conformance checking and validation
  of MetaAST structures according to the theoretical foundations.

  ## New 3-Tuple Format

  All MetaAST nodes are uniform 3-element tuples:

      {type_atom, keyword_meta, children_or_value}

  ## Conformance Rules (Definition 8 from THEORETICAL_FOUNDATIONS.md)

  A term `t` in M1 conforms to M2 if it can be represented by M2 meta-types
  without loss of essential semantic information. Validation checks:

  1. **Structural conformance** - AST structure matches M2 type definitions
  2. **Type safety** - All type tags are valid M2 types
  3. **Semantic preservation** - Required semantic information is present
  4. **Native escape hatches** - M2.3 used only when necessary

  ## Validation Decision Tree

  ```mermaid
  flowchart TD
      Input["Input: Document / AST"] --> Structure{"Structure valid?<br/>AST.conforms?"}
      Structure -->|No| Err1["error: invalid_structure"]
      Structure -->|Yes| Analyze["Single-pass analysis<br/>collect metrics"]
      Analyze --> Level{"Classify level"}
      Level -->|"has :language_specific"| Native[":native"]
      Level -->|"has extended types"| Extended[":extended"]
      Level -->|"core types only"| Core[":core"]
      Native --> Mode{"Check mode"}
      Extended --> Mode
      Core --> Mode
      Mode -->|":strict + native > 0"| Err2["error: native_constructs_not_allowed"]
      Mode -->|"depth > max"| Err3["error: max_depth_exceeded"]
      Mode -->|"vars > max"| Err4["error: too_many_variables"]
      Mode -->|"all ok"| OK["{:ok, metadata}"]
  ```

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

  # AST analysis - single-pass traversal collecting all metrics at once.
  # Previous implementation used 7+ separate traversals; this collects
  # level, native count, variables, depth, and node count in one pass.

  # Extended layer types (M2.2 + M2.2s)
  @extended_types [
    # M2.2: Extended (most languages)
    :loop,
    :lambda,
    :collection_op,
    :pattern_match,
    :match_arm,
    :exception_handling,
    :async_operation,
    :yield,
    :comprehension,
    :generator,
    :filter,
    :pipe,
    :pin,
    :assert_type,
    # M2.2s: Structural/Organizational layer
    :container,
    :function_def,
    :param,
    :attribute_access,
    :augmented_assignment,
    :property,
    :import,
    :type_annotation,
    :decorator,
    :record_update,
    :child_spec
  ]

  # Native layer types (M2.3)
  @native_types [:language_specific]

  defp analyze_ast(ast) do
    initial_acc = %{
      native_count: 0,
      has_extended: false,
      variables: MapSet.new(),
      current_depth: 0,
      max_depth: 0,
      node_count: 0
    }

    {_ast, acc} = AST.traverse(ast, initial_acc, &analyze_pre/2, &analyze_post/2)

    level =
      cond do
        acc.native_count > 0 -> :native
        acc.has_extended -> :extended
        true -> :core
      end

    warnings = build_warnings(acc)

    meta = %{
      level: level,
      native_constructs: acc.native_count,
      warnings: warnings,
      variables: acc.variables,
      depth: acc.max_depth,
      node_count: acc.node_count
    }

    {:ok, meta}
  end

  # Pre: entering a node - track depth, count nodes, classify type, collect variables
  defp analyze_pre({type, meta, _children} = node, acc)
       when is_atom(type) and is_list(meta) do
    new_depth = acc.current_depth + 1

    acc =
      acc
      |> Map.update!(:current_depth, fn _ -> new_depth end)
      |> Map.update!(:max_depth, &max(&1, new_depth))
      |> Map.update!(:node_count, &(&1 + 1))

    # Classify node type
    acc =
      cond do
        type in @native_types -> Map.update!(acc, :native_count, &(&1 + 1))
        type in @extended_types -> Map.put(acc, :has_extended, true)
        true -> acc
      end

    # Collect variables
    acc =
      if type == :variable and is_binary(elem(node, 2)) do
        Map.update!(acc, :variables, &MapSet.put(&1, elem(node, 2)))
      else
        acc
      end

    {node, acc}
  end

  defp analyze_pre(node, acc), do: {node, acc}

  # Post: leaving a node - decrement depth
  defp analyze_post({type, meta, _children} = node, acc)
       when is_atom(type) and is_list(meta) do
    {node, Map.update!(acc, :current_depth, &max(0, &1 - 1))}
  end

  defp analyze_post(node, acc), do: {node, acc}

  # Build warnings from accumulated metrics
  defp build_warnings(acc) do
    warnings = []

    warnings =
      if acc.native_count > 0 do
        [{:native_constructs_present, acc.native_count} | warnings]
      else
        warnings
      end

    warnings =
      if acc.max_depth > 100 do
        [{:deep_nesting, acc.max_depth} | warnings]
      else
        warnings
      end

    warnings =
      if acc.node_count > 1000 do
        [{:large_ast, acc.node_count} | warnings]
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
end
