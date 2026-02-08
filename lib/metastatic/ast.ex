defmodule Metastatic.AST do
  @moduledoc """
  M2: Meta-Model for Programming Language Abstract Syntax.

  This module defines the meta-types that all language ASTs (M1 level) must
  conform to. Think of this as the "UML" for programming language ASTs.

  ## Meta-Modeling Hierarchy

  - **M3:** Elixir type system (`@type`, `@spec`)
  - **M2:** This module (MetaAST) - defines what AST nodes CAN be
  - **M1:** Python AST, JavaScript AST, Elixir AST - what specific code IS
  - **M0:** Runtime execution - what code DOES

  ## Node Structure

  All MetaAST nodes are uniform 3-element tuples:

      {type_atom, keyword_meta, children_or_value}

  Where:
  - `type_atom` - Node type (e.g., `:literal`, `:container`, `:function_def`)
  - `keyword_meta` - Keyword list containing metadata (line, column, subtype, etc.)
  - `children_or_value` - Either a value (for leaf nodes) or list of child nodes

  ## Third Element Semantics

  The third element varies by node type:
  - **Leaf nodes** (literal, variable): The actual value (`42`, `"x"`)
  - **Composite nodes** (binary_op, function_call): List of child AST nodes
  - **Container nodes** (container, function_def): List of body statements

  ## Examples

      # Literal integer
      {:literal, [subtype: :integer, line: 10], 42}

      # Variable
      {:variable, [line: 5], "x"}

      # Binary operation
      {:binary_op, [category: :arithmetic, operator: :+],
       [{:variable, [], "x"}, {:literal, [subtype: :integer], 5}]}

      # Map with pairs
      {:map, [],
       [{:pair, [], [{:literal, [subtype: :symbol], :name},
                     {:literal, [subtype: :string], "Alice"}]}]}

  ## Traversal

  Use `traverse/4` for walking and transforming ASTs:

      AST.traverse(ast, acc, &pre/2, &post/2)

  This mirrors `Macro.traverse/4` from Elixir's standard library.
  """

  # ----- Type Definitions -----

  @typedoc """
  A MetaAST node is a 3-tuple: {type, metadata, children_or_value}.

  The type atom identifies the node kind.
  The metadata is a keyword list with location, subtype, and other info.
  The third element is either a value (leaf nodes) or list of children.
  """
  @type meta_ast :: {atom(), keyword(), term()}

  @typedoc """
  Node type atoms for M2.1 Core Layer - universal concepts.
  """
  @type core_type ::
          :literal
          | :variable
          | :list
          | :map
          | :pair
          | :tuple
          | :binary_op
          | :unary_op
          | :function_call
          | :conditional
          | :early_return
          | :block
          | :assignment
          | :inline_match

  @typedoc """
  Node type atoms for M2.2 Extended Layer - common patterns.
  """
  @type extended_type ::
          :loop
          | :lambda
          | :collection_op
          | :pattern_match
          | :match_arm
          | :exception_handling
          | :async_operation

  @typedoc """
  Node type atoms for M2.2s Structural Layer - organizational constructs.
  """
  @type structural_type ::
          :container
          | :function_def
          | :param
          | :attribute_access
          | :augmented_assignment
          | :property

  @typedoc """
  Node type atoms for M2.3 Native Layer - language-specific escape hatch.
  """
  @type native_type :: :language_specific

  @typedoc """
  All valid node type atoms.
  """
  @type node_type :: core_type() | extended_type() | structural_type() | native_type()

  @typedoc """
  Semantic subtype for literals.
  """
  @type literal_subtype ::
          :integer
          | :float
          | :string
          | :boolean
          | :null
          | :symbol
          | :regex

  @typedoc """
  Category for binary/unary operators.
  """
  @type operator_category :: :arithmetic | :comparison | :boolean

  @typedoc """
  Container type classification.
  """
  @type container_type :: :module | :class | :namespace

  @typedoc """
  Visibility modifier.
  """
  @type visibility :: :public | :private | :protected

  # ----- Node Type Sets for Validation -----

  @core_types [
    :literal,
    :variable,
    :list,
    :map,
    :pair,
    :tuple,
    :binary_op,
    :unary_op,
    :function_call,
    :conditional,
    :early_return,
    :block,
    :assignment,
    :inline_match
  ]

  @extended_types [
    :loop,
    :lambda,
    :collection_op,
    :pattern_match,
    :match_arm,
    :exception_handling,
    :async_operation
  ]

  @structural_types [
    :container,
    :function_def,
    :param,
    :attribute_access,
    :augmented_assignment,
    :property
  ]

  @native_types [:language_specific]

  @all_types @core_types ++ @extended_types ++ @structural_types ++ @native_types

  @literal_subtypes [:integer, :float, :string, :boolean, :null, :symbol, :regex]

  @operator_categories [:arithmetic, :comparison, :boolean]

  @container_types [:module, :class, :namespace]

  # ----- Accessors -----

  @doc """
  Extract the node type from a MetaAST node.

  ## Examples

      iex> Metastatic.AST.type({:literal, [subtype: :integer], 42})
      :literal

      iex> left = {:variable, [], "x"}
      iex> right = {:literal, [subtype: :integer], 5}
      iex> Metastatic.AST.type({:binary_op, [operator: :+], [left, right]})
      :binary_op
  """
  @spec type(meta_ast()) :: atom()
  def type({type, _meta, _children}) when is_atom(type), do: type

  @doc """
  Extract the metadata keyword list from a MetaAST node.

  ## Examples

      iex> Metastatic.AST.meta({:literal, [subtype: :integer, line: 10], 42})
      [subtype: :integer, line: 10]

      iex> Metastatic.AST.meta({:variable, [], "x"})
      []
  """
  @spec meta(meta_ast()) :: keyword()
  def meta({_type, meta, _children}) when is_list(meta), do: meta

  @doc """
  Extract the children or value from a MetaAST node.

  For leaf nodes (literal, variable), returns the value.
  For composite nodes, returns the list of children.

  ## Examples

      iex> Metastatic.AST.children({:literal, [subtype: :integer], 42})
      42

      iex> left = {:variable, [], "x"}
      iex> right = {:literal, [subtype: :integer], 5}
      iex> Metastatic.AST.children({:binary_op, [operator: :+], [left, right]})
      [{:variable, [], "x"}, {:literal, [subtype: :integer], 5}]
  """
  @spec children(meta_ast()) :: term()
  def children({_type, _meta, children}), do: children

  @doc """
  Get a specific metadata value by key.

  ## Examples

      iex> ast = {:literal, [subtype: :integer, line: 10], 42}
      iex> Metastatic.AST.get_meta(ast, :line)
      10

      iex> ast = {:variable, [], "x"}
      iex> Metastatic.AST.get_meta(ast, :line)
      nil

      iex> ast = {:variable, [], "x"}
      iex> Metastatic.AST.get_meta(ast, :line, 0)
      0
  """
  @spec get_meta(meta_ast(), atom(), term()) :: term()
  def get_meta({_type, meta, _children}, key, default \\ nil) when is_atom(key) do
    Keyword.get(meta, key, default)
  end

  @doc """
  Put a metadata value by key.

  ## Examples

      iex> ast = {:literal, [subtype: :integer], 42}
      iex> Metastatic.AST.put_meta(ast, :line, 10)
      {:literal, [line: 10, subtype: :integer], 42}

      iex> ast = {:variable, [line: 5], "x"}
      iex> Metastatic.AST.put_meta(ast, :line, 10)
      {:variable, [line: 10], "x"}
  """
  @spec put_meta(meta_ast(), atom(), term()) :: meta_ast()
  def put_meta({type, meta, children}, key, value) when is_atom(key) do
    {type, Keyword.put(meta, key, value), children}
  end

  @doc """
  Update multiple metadata keys at once.

  ## Examples

      iex> ast = {:literal, [subtype: :integer], 42}
      iex> Metastatic.AST.update_meta(ast, line: 10, col: 5)
      {:literal, [subtype: :integer, line: 10, col: 5], 42}
  """
  @spec update_meta(meta_ast(), keyword()) :: meta_ast()
  def update_meta({type, meta, children}, updates) when is_list(updates) do
    {type, Keyword.merge(meta, updates), children}
  end

  @doc """
  Update the children/value of a node.

  ## Examples

      iex> old_left = {:variable, [], "x"}
      iex> old_right = {:literal, [subtype: :integer], 5}
      iex> ast = {:binary_op, [operator: :+], [old_left, old_right]}
      iex> new_left = {:variable, [], "y"}
      iex> new_right = {:literal, [subtype: :integer], 10}
      iex> Metastatic.AST.update_children(ast, [new_left, new_right])
      {:binary_op, [operator: :+], [{:variable, [], "y"}, {:literal, [subtype: :integer], 10}]}
  """
  @spec update_children(meta_ast(), term()) :: meta_ast()
  def update_children({type, meta, _children}, new_children) do
    {type, meta, new_children}
  end

  # ----- Traversal -----

  @doc """
  Traverse a MetaAST, applying pre and post functions.

  This mirrors `Macro.traverse/4` from Elixir's standard library.

  - `pre` is called before visiting children, receives `{ast, acc}`, returns `{ast, acc}`
  - `post` is called after visiting children, receives `{ast, acc}`, returns `{ast, acc}`

  The traversal visits children based on the node type:
  - Leaf nodes (literal, variable): No children to visit
  - Composite nodes: Visits each child in the list
  - Non-AST values: Passed through unchanged

  ## Examples

      # Count all nodes
      {_ast, count} = AST.traverse(ast, 0, fn node, acc -> {node, acc + 1} end, fn node, acc -> {node, acc} end)

      # Collect all variable names
      {_ast, vars} = AST.traverse(ast, [], fn
        {:variable, _, name} = node, acc -> {node, [name | acc]}
        node, acc -> {node, acc}
      end, fn node, acc -> {node, acc} end)

      # Transform all integers by doubling them
      {new_ast, _} = AST.traverse(ast, nil, fn node, acc -> {node, acc} end, fn
        {:literal, meta, value} = node, acc ->
          if Keyword.get(meta, :subtype) == :integer do
            {{:literal, meta, value * 2}, acc}
          else
            {node, acc}
          end
        node, acc -> {node, acc}
      end)
  """
  @spec traverse(meta_ast() | term(), acc, pre_fun, post_fun) :: {meta_ast() | term(), acc}
        when acc: term(),
             pre_fun: (meta_ast() | term(), acc -> {meta_ast() | term(), acc}),
             post_fun: (meta_ast() | term(), acc -> {meta_ast() | term(), acc})
  def traverse(ast, acc, pre, post) when is_function(pre, 2) and is_function(post, 2) do
    do_traverse(ast, acc, pre, post)
  end

  # Main traversal for MetaAST nodes
  defp do_traverse({type, meta, _children} = ast, acc, pre, post)
       when is_atom(type) and is_list(meta) do
    # Apply pre function
    {ast, acc} = pre.(ast, acc)

    # Destructure again in case pre modified the node
    {type, meta, children} = ast

    # Traverse children based on node type
    {new_children, acc} = traverse_children(type, children, acc, pre, post)

    # Reconstruct node with traversed children
    new_ast = {type, meta, new_children}

    # Apply post function
    post.(new_ast, acc)
  end

  # Pass through non-AST values (literals like integers, strings, atoms, nil)
  defp do_traverse(other, acc, pre, post) do
    {other, acc} = pre.(other, acc)
    post.(other, acc)
  end

  # Traverse children based on node type
  # Leaf nodes - value is not traversable
  defp traverse_children(type, value, acc, _pre, _post)
       when type in [:literal, :variable] do
    {value, acc}
  end

  # Nodes with list of children
  defp traverse_children(_type, children, acc, pre, post) when is_list(children) do
    {new_children, acc} =
      Enum.map_reduce(children, acc, fn child, acc ->
        do_traverse(child, acc, pre, post)
      end)

    {new_children, acc}
  end

  # Fallback for any other value
  defp traverse_children(_type, value, acc, _pre, _post) do
    {value, acc}
  end

  @doc """
  Traverse a MetaAST with only a pre function (post is identity).

  ## Examples

      {new_ast, acc} = AST.prewalk(ast, [], fn node, acc -> {node, acc} end)
  """
  @spec prewalk(meta_ast() | term(), acc, (meta_ast() | term(), acc -> {meta_ast() | term(), acc})) ::
          {meta_ast() | term(), acc}
        when acc: term()
  def prewalk(ast, acc, fun) when is_function(fun, 2) do
    traverse(ast, acc, fun, fn node, acc -> {node, acc} end)
  end

  @doc """
  Traverse a MetaAST with only a post function (pre is identity).

  ## Examples

      {new_ast, acc} = AST.postwalk(ast, [], fn node, acc -> {node, acc} end)
  """
  @spec postwalk(meta_ast() | term(), acc, (meta_ast() | term(), acc ->
                                              {meta_ast() | term(), acc})) ::
          {meta_ast() | term(), acc}
        when acc: term()
  def postwalk(ast, acc, fun) when is_function(fun, 2) do
    traverse(ast, acc, fn node, acc -> {node, acc} end, fun)
  end

  # ----- Conformance Validation -----

  @doc """
  Validate that a term conforms to the M2 meta-model.

  Checks that the structure is a valid 3-tuple MetaAST node
  with proper type, metadata, and children.

  ## Examples

      iex> Metastatic.AST.conforms?({:literal, [subtype: :integer], 42})
      true

      iex> Metastatic.AST.conforms?({:binary_op, [category: :arithmetic, operator: :+],
      ...>   [{:variable, [], "x"}, {:literal, [subtype: :integer], 5}]})
      true

      iex> Metastatic.AST.conforms?({:invalid_node, "data"})
      false

      iex> Metastatic.AST.conforms?("not a tuple")
      false
  """
  @spec conforms?(term()) :: boolean()
  def conforms?(ast) do
    case ast do
      {type, meta, children} when is_atom(type) and is_list(meta) ->
        type in @all_types and valid_node?(type, meta, children)

      # Special case: wildcard pattern
      :_ ->
        true

      _ ->
        false
    end
  end

  # Validate specific node types
  defp valid_node?(:literal, meta, value) do
    subtype = Keyword.get(meta, :subtype)
    subtype in @literal_subtypes and valid_literal_value?(subtype, value)
  end

  defp valid_node?(:variable, _meta, name) do
    is_binary(name)
  end

  defp valid_node?(:list, _meta, elements) do
    is_list(elements) and Enum.all?(elements, &conforms?/1)
  end

  defp valid_node?(:map, _meta, pairs) do
    is_list(pairs) and Enum.all?(pairs, &conforms?/1)
  end

  defp valid_node?(:pair, _meta, [key, value]) do
    conforms?(key) and conforms?(value)
  end

  defp valid_node?(:pair, _meta, _), do: false

  defp valid_node?(:tuple, _meta, elements) do
    is_list(elements) and Enum.all?(elements, &conforms?/1)
  end

  defp valid_node?(:binary_op, meta, [left, right]) do
    category = Keyword.get(meta, :category)
    operator = Keyword.get(meta, :operator)

    category in @operator_categories and is_atom(operator) and
      conforms?(left) and conforms?(right)
  end

  defp valid_node?(:binary_op, _meta, _), do: false

  defp valid_node?(:unary_op, meta, [operand]) do
    category = Keyword.get(meta, :category)
    operator = Keyword.get(meta, :operator)
    category in @operator_categories and is_atom(operator) and conforms?(operand)
  end

  defp valid_node?(:unary_op, _meta, _), do: false

  defp valid_node?(:function_call, meta, args) do
    name = Keyword.get(meta, :name)
    is_binary(name) and is_list(args) and Enum.all?(args, &conforms?/1)
  end

  defp valid_node?(:conditional, _meta, [condition, then_branch, else_branch]) do
    conforms?(condition) and conforms?(then_branch) and
      (is_nil(else_branch) or conforms?(else_branch))
  end

  defp valid_node?(:conditional, _meta, _), do: false

  defp valid_node?(:early_return, _meta, [value]) do
    conforms?(value)
  end

  defp valid_node?(:early_return, _meta, []), do: true
  defp valid_node?(:early_return, _meta, _), do: false

  defp valid_node?(:block, _meta, statements) do
    is_list(statements) and Enum.all?(statements, &conforms?/1)
  end

  defp valid_node?(:assignment, _meta, [target, value]) do
    conforms?(target) and conforms?(value)
  end

  defp valid_node?(:assignment, _meta, _), do: false

  defp valid_node?(:inline_match, _meta, [pattern, value]) do
    conforms?(pattern) and conforms?(value)
  end

  defp valid_node?(:inline_match, _meta, _), do: false

  # M2.2 Extended types
  defp valid_node?(:loop, meta, children) do
    loop_type = Keyword.get(meta, :loop_type)

    case {loop_type, children} do
      {:while, [condition, body]} ->
        conforms?(condition) and conforms?(body)

      {t, [iterator, collection, body]} when t in [:for, :for_each] ->
        conforms?(iterator) and conforms?(collection) and conforms?(body)

      _ ->
        false
    end
  end

  defp valid_node?(:lambda, meta, body) do
    params = Keyword.get(meta, :params, [])
    is_list(params) and valid_params?(params) and is_list(body) and Enum.all?(body, &conforms?/1)
  end

  defp valid_node?(:collection_op, meta, children) do
    op_type = Keyword.get(meta, :op_type)

    case {op_type, children} do
      {t, [func, collection]} when t in [:map, :filter] ->
        conforms?(func) and conforms?(collection)

      {:reduce, [func, collection, initial]} ->
        conforms?(func) and conforms?(collection) and conforms?(initial)

      _ ->
        false
    end
  end

  defp valid_node?(:pattern_match, _meta, [scrutinee, arms]) when is_list(arms) do
    conforms?(scrutinee) and valid_pattern_arms?(arms)
  end

  defp valid_node?(:pattern_match, _meta, _), do: false

  defp valid_node?(:match_arm, meta, body) do
    pattern = Keyword.get(meta, :pattern)

    (is_nil(pattern) or conforms?(pattern)) and
      is_list(body) and Enum.all?(body, &conforms?/1)
  end

  defp valid_node?(:exception_handling, _meta, [try_block, handlers, finally]) do
    conforms?(try_block) and
      valid_exception_handlers?(handlers) and
      (is_nil(finally) or conforms?(finally))
  end

  defp valid_node?(:exception_handling, _meta, _), do: false

  defp valid_node?(:async_operation, meta, [operation]) do
    op_type = Keyword.get(meta, :op_type)
    op_type in [:await, :async] and conforms?(operation)
  end

  defp valid_node?(:async_operation, _meta, _), do: false

  # M2.2s Structural types
  defp valid_node?(:container, meta, body) do
    container_type = Keyword.get(meta, :container_type)
    name = Keyword.get(meta, :name)

    container_type in @container_types and is_binary(name) and
      is_list(body) and Enum.all?(body, &conforms?/1)
  end

  defp valid_node?(:function_def, meta, body) do
    name = Keyword.get(meta, :name)
    params = Keyword.get(meta, :params, [])

    is_binary(name) and is_list(params) and valid_params?(params) and
      is_list(body) and Enum.all?(body, &conforms?/1)
  end

  # Param node: {:param, [pattern: pattern, default: default], name}
  defp valid_node?(:param, meta, name) when is_binary(name) do
    pattern = Keyword.get(meta, :pattern)
    default = Keyword.get(meta, :default)

    (is_nil(pattern) or conforms?(pattern)) and
      (is_nil(default) or conforms?(default))
  end

  defp valid_node?(:param, _meta, _), do: false

  defp valid_node?(:attribute_access, meta, [receiver]) do
    attribute = Keyword.get(meta, :attribute)
    is_binary(attribute) and conforms?(receiver)
  end

  defp valid_node?(:attribute_access, _meta, _), do: false

  defp valid_node?(:augmented_assignment, meta, [target, value]) do
    operator = Keyword.get(meta, :operator)
    is_atom(operator) and conforms?(target) and conforms?(value)
  end

  defp valid_node?(:augmented_assignment, _meta, _), do: false

  defp valid_node?(:property, meta, children) do
    name = Keyword.get(meta, :name)

    is_binary(name) and is_list(children) and
      Enum.all?(children, fn
        nil -> true
        child -> conforms?(child)
      end)
  end

  # M2.3 Native type
  defp valid_node?(:language_specific, meta, _native_ast) do
    language = Keyword.get(meta, :language)
    is_atom(language)
  end

  defp valid_pattern_arms?(arms) when is_list(arms) do
    Enum.all?(arms, fn
      {pattern, body} -> (conforms?(pattern) or pattern == :_) and conforms?(body)
      arm -> conforms?(arm)
    end)
  end

  defp valid_exception_handlers?(handlers) when is_list(handlers) do
    # Exception handlers should be :match_arm nodes
    Enum.all?(handlers, &conforms?/1)
  end

  # Validate params list in function definitions and lambdas
  defp valid_params?(params) when is_list(params) do
    Enum.all?(params, fn
      {:param, meta, name} when is_list(meta) and is_binary(name) ->
        pattern = Keyword.get(meta, :pattern)
        default = Keyword.get(meta, :default)

        (is_nil(pattern) or conforms?(pattern)) and
          (is_nil(default) or conforms?(default))

      # Also accept simple string params for backward compatibility during transition
      name when is_binary(name) ->
        true

      _ ->
        false
    end)
  end

  defp valid_params?(_), do: false

  # Validate literal values match their subtype
  defp valid_literal_value?(:integer, value), do: is_integer(value)
  defp valid_literal_value?(:float, value), do: is_float(value)
  defp valid_literal_value?(:string, value), do: is_binary(value)
  defp valid_literal_value?(:boolean, value), do: is_boolean(value)
  defp valid_literal_value?(:null, value), do: is_nil(value)
  defp valid_literal_value?(:symbol, value), do: is_atom(value)
  defp valid_literal_value?(:regex, _value), do: true

  # ----- Variable Extraction -----

  @doc """
  Extract all variable names referenced in an AST.

  Uses traverse/4 internally to collect all variable nodes.

  ## Examples

      iex> ast = {:binary_op, [category: :arithmetic, operator: :+],
      ...>   [{:variable, [], "x"}, {:variable, [], "y"}]}
      iex> Metastatic.AST.variables(ast)
      MapSet.new(["x", "y"])

      iex> ast = {:literal, [subtype: :integer], 42}
      iex> Metastatic.AST.variables(ast)
      MapSet.new([])
  """
  @spec variables(meta_ast()) :: MapSet.t(String.t())
  def variables(ast) do
    {_ast, vars} =
      traverse(
        ast,
        MapSet.new(),
        fn
          {:variable, _meta, name} = node, acc when is_binary(name) ->
            {node, MapSet.put(acc, name)}

          node, acc ->
            {node, acc}
        end,
        fn node, acc -> {node, acc} end
      )

    vars
  end

  # ----- Location Helpers -----

  @doc """
  Extract location information from a MetaAST node.

  Returns a map with :line, :col, :end_line, :end_col if present in metadata.

  ## Examples

      iex> ast = {:literal, [subtype: :integer, line: 10, col: 5], 42}
      iex> Metastatic.AST.location(ast)
      %{line: 10, col: 5}

      iex> ast = {:variable, [], "x"}
      iex> Metastatic.AST.location(ast)
      nil
  """
  @spec location(meta_ast()) :: map() | nil
  def location({_type, meta, _children}) when is_list(meta) do
    loc_keys = [:line, :col, :end_line, :end_col]

    loc =
      meta
      |> Keyword.take(loc_keys)
      |> Map.new()

    if map_size(loc) > 0, do: loc, else: nil
  end

  def location(_), do: nil

  @doc """
  Extract all metadata from a MetaAST node as a keyword list.

  Returns the full metadata including location, M1 context (module, function, arity, etc.),
  and node-specific metadata (subtype, operator, etc.).

  ## Examples

      iex> ast = {:literal, [subtype: :integer, line: 10], 42}
      iex> Metastatic.AST.metadata(ast)
      [subtype: :integer, line: 10]

      iex> ast = {:variable, [line: 5, module: "MyApp", function: "create"], "x"}
      iex> Metastatic.AST.metadata(ast)
      [line: 5, module: "MyApp", function: "create"]

      iex> ast = {:variable, [], "x"}
      iex> Metastatic.AST.metadata(ast)
      []
  """
  @spec metadata(meta_ast()) :: keyword()
  def metadata({_type, meta, _children}) when is_list(meta), do: meta
  def metadata(_), do: []

  @doc """
  Attach location information to a MetaAST node.

  ## Examples

      iex> ast = {:literal, [subtype: :integer], 42}
      iex> Metastatic.AST.with_location(ast, %{line: 10, col: 5})
      {:literal, [subtype: :integer, line: 10, col: 5], 42}

      iex> ast = {:variable, [], "x"}
      iex> Metastatic.AST.with_location(ast, nil)
      {:variable, [], "x"}
  """
  @spec with_location(meta_ast(), map() | nil) :: meta_ast()
  def with_location(ast, nil), do: ast

  def with_location({type, meta, children}, loc) when is_map(loc) do
    loc_updates = Enum.filter(loc, fn {k, _v} -> k in [:line, :col, :end_line, :end_col] end)
    {type, Keyword.merge(meta, loc_updates), children}
  end

  @doc """
  Merge context metadata into a node's metadata.

  Used for attaching M1-level context like module name, function name, etc.
  Note: Order of merged keys is not guaranteed due to map iteration order.

  ## Examples

      iex> ast = {:variable, [line: 10], "x"}
      iex> context = %{module: "MyApp"}
      iex> {:variable, meta, "x"} = Metastatic.AST.with_context(ast, context)
      iex> Keyword.get(meta, :module)
      "MyApp"
      iex> Keyword.get(meta, :line)
      10
  """
  @spec with_context(meta_ast(), map()) :: meta_ast()
  def with_context({type, meta, children}, context) when is_map(context) do
    context_updates = Enum.to_list(context)
    {type, Keyword.merge(meta, context_updates), children}
  end

  def with_context(ast, _), do: ast

  # ----- Metadata Extractors -----

  @doc """
  Extract module name from node metadata.

  ## Examples

      iex> ast = {:variable, [module: "MyApp.Controller"], "x"}
      iex> Metastatic.AST.node_module(ast)
      "MyApp.Controller"
  """
  @spec node_module(meta_ast()) :: String.t() | nil
  def node_module(ast), do: get_meta(ast, :module)

  @doc """
  Extract function name from node metadata.
  """
  @spec node_function(meta_ast()) :: String.t() | nil
  def node_function(ast), do: get_meta(ast, :function)

  @doc """
  Extract arity from node metadata.
  """
  @spec node_arity(meta_ast()) :: non_neg_integer() | nil
  def node_arity(ast), do: get_meta(ast, :arity)

  @doc """
  Extract file path from node metadata.
  """
  @spec node_file(meta_ast()) :: String.t() | nil
  def node_file(ast), do: get_meta(ast, :file)

  @doc """
  Extract container name from node metadata.
  """
  @spec node_container(meta_ast()) :: String.t() | nil
  def node_container(ast), do: get_meta(ast, :container)

  @doc """
  Extract visibility from node metadata.
  """
  @spec node_visibility(meta_ast()) :: visibility() | nil
  def node_visibility(ast), do: get_meta(ast, :visibility)

  # ----- Structural Helpers -----

  @doc """
  Check if a node is a leaf node (no children to traverse).

  ## Examples

      iex> Metastatic.AST.leaf?({:literal, [subtype: :integer], 42})
      true

      iex> Metastatic.AST.leaf?({:variable, [], "x"})
      true

      iex> left = {:variable, [], "x"}
      iex> right = {:literal, [subtype: :integer], 5}
      iex> Metastatic.AST.leaf?({:binary_op, [], [left, right]})
      false
  """
  @spec leaf?(meta_ast()) :: boolean()
  def leaf?({type, _meta, _children}) when type in [:literal, :variable], do: true
  def leaf?(_), do: false

  @doc """
  Get the layer classification for a node type.

  Returns :core, :extended, :structural, or :native.

  ## Examples

      iex> Metastatic.AST.layer(:literal)
      :core

      iex> Metastatic.AST.layer(:lambda)
      :extended

      iex> Metastatic.AST.layer(:container)
      :structural

      iex> Metastatic.AST.layer(:language_specific)
      :native
  """
  @spec layer(atom()) :: :core | :extended | :structural | :native | :unknown
  def layer(type) when type in @core_types, do: :core
  def layer(type) when type in @extended_types, do: :extended
  def layer(type) when type in @structural_types, do: :structural
  def layer(type) when type in @native_types, do: :native
  def layer(_), do: :unknown

  @doc """
  Extract the name from a container node.

  ## Examples

      iex> ast = {:container, [container_type: :module, name: "MyApp.Math"], []}
      iex> Metastatic.AST.container_name(ast)
      "MyApp.Math"
  """
  @spec container_name(meta_ast()) :: String.t() | nil
  def container_name({:container, meta, _body}), do: Keyword.get(meta, :name)
  def container_name(_), do: nil

  @doc """
  Extract the name from a function_def node.

  ## Examples

      iex> body = {:binary_op, [operator: :+], [{:variable, [], "x"}, {:variable, [], "y"}]}
      iex> ast = {:function_def, [name: "add", params: ["x", "y"]], [body]}
      iex> Metastatic.AST.function_name(ast)
      "add"
  """
  @spec function_name(meta_ast()) :: String.t() | nil
  def function_name({:function_def, meta, _body}), do: Keyword.get(meta, :name)
  def function_name(_), do: nil

  @doc """
  Get the visibility of a function_def node.

  ## Examples

      iex> body = {:binary_op, [operator: :+], [{:variable, [], "x"}, {:variable, [], "y"}]}
      iex> ast = {:function_def, [name: "add", visibility: :public], [body]}
      iex> Metastatic.AST.function_visibility(ast)
      :public
  """
  @spec function_visibility(meta_ast()) :: visibility()
  def function_visibility({:function_def, meta, _body}) do
    Keyword.get(meta, :visibility, :public)
  end

  def function_visibility(_), do: :public

  @doc """
  Check if a container has state (classes typically have state).

  ## Examples

      iex> ast = {:container, [container_type: :class, name: "Counter"], []}
      iex> Metastatic.AST.has_state?(ast)
      true

      iex> ast = {:container, [container_type: :module, name: "Math"], []}
      iex> Metastatic.AST.has_state?(ast)
      false
  """
  @spec has_state?(meta_ast()) :: boolean()
  def has_state?({:container, meta, _body}) do
    Keyword.get(meta, :container_type) == :class
  end

  def has_state?(_), do: false

  # ----- Builder Helpers -----

  @doc """
  Create a literal node.

  ## Examples

      iex> Metastatic.AST.literal(:integer, 42)
      {:literal, [subtype: :integer], 42}

      iex> Metastatic.AST.literal(:string, "hello", line: 5)
      {:literal, [subtype: :string, line: 5], "hello"}
  """
  @spec literal(literal_subtype(), term(), keyword()) :: meta_ast()
  def literal(subtype, value, extra_meta \\ []) when subtype in @literal_subtypes do
    {:literal, Keyword.merge([subtype: subtype], extra_meta), value}
  end

  @doc """
  Create a variable node.

  ## Examples

      iex> Metastatic.AST.variable("x")
      {:variable, [], "x"}

      iex> Metastatic.AST.variable("count", line: 10)
      {:variable, [line: 10], "count"}
  """
  @spec variable(String.t(), keyword()) :: meta_ast()
  def variable(name, meta \\ []) when is_binary(name) do
    {:variable, meta, name}
  end

  @doc """
  Create a binary operation node.

  ## Examples

      iex> left = {:variable, [], "x"}
      iex> right = {:literal, [subtype: :integer], 5}
      iex> Metastatic.AST.binary_op(:arithmetic, :+, left, right)
      {:binary_op, [category: :arithmetic, operator: :+], [{:variable, [], "x"}, {:literal, [subtype: :integer], 5}]}
  """
  @spec binary_op(operator_category(), atom(), meta_ast(), meta_ast(), keyword()) :: meta_ast()
  def binary_op(category, operator, left, right, extra_meta \\ [])
      when category in @operator_categories and is_atom(operator) do
    meta = Keyword.merge([category: category, operator: operator], extra_meta)
    {:binary_op, meta, [left, right]}
  end

  @doc """
  Create a function call node.

  ## Examples

      iex> args = [{:variable, [], "x"}, {:literal, [subtype: :integer], 5}]
      iex> Metastatic.AST.function_call("add", args)
      {:function_call, [name: "add"], [{:variable, [], "x"}, {:literal, [subtype: :integer], 5}]}
  """
  @spec function_call(String.t(), [meta_ast()], keyword()) :: meta_ast()
  def function_call(name, args, extra_meta \\ []) when is_binary(name) and is_list(args) do
    meta = Keyword.merge([name: name], extra_meta)
    {:function_call, meta, args}
  end

  @doc """
  Create a block node.

  ## Examples

      iex> stmts = [{:variable, [], "x"}, {:literal, [subtype: :integer], 42}]
      iex> Metastatic.AST.block(stmts)
      {:block, [], [{:variable, [], "x"}, {:literal, [subtype: :integer], 42}]}
  """
  @spec block([meta_ast()], keyword()) :: meta_ast()
  def block(statements, meta \\ []) when is_list(statements) do
    {:block, meta, statements}
  end

  @doc """
  Create a map node with pairs.

  ## Examples

      iex> pairs = [Metastatic.AST.pair(
      ...>   {:literal, [subtype: :symbol], :name},
      ...>   {:literal, [subtype: :string], "Alice"})]
      iex> Metastatic.AST.map_node(pairs)
      {:map, [], [{:pair, [], [{:literal, [subtype: :symbol], :name}, {:literal, [subtype: :string], "Alice"}]}]}
  """
  @spec map_node([meta_ast()], keyword()) :: meta_ast()
  def map_node(pairs, meta \\ []) when is_list(pairs) do
    {:map, meta, pairs}
  end

  @doc """
  Create a key-value pair node for maps.

  ## Examples

      iex> key = {:literal, [subtype: :symbol], :name}
      iex> value = {:literal, [subtype: :string], "Alice"}
      iex> Metastatic.AST.pair(key, value)
      {:pair, [], [{:literal, [subtype: :symbol], :name}, {:literal, [subtype: :string], "Alice"}]}
  """
  @spec pair(meta_ast(), meta_ast(), keyword()) :: meta_ast()
  def pair(key, value, meta \\ []) do
    {:pair, meta, [key, value]}
  end

  @doc """
  Create an inline match node.

  ## Examples

      iex> pattern = {:variable, [], "x"}
      iex> value = {:literal, [subtype: :integer], 42}
      iex> Metastatic.AST.inline_match(pattern, value)
      {:inline_match, [], [{:variable, [], "x"}, {:literal, [subtype: :integer], 42}]}
  """
  @spec inline_match(meta_ast(), meta_ast(), keyword()) :: meta_ast()
  def inline_match(pattern, value, meta \\ []) do
    {:inline_match, meta, [pattern, value]}
  end

  @doc """
  Create a container node.

  ## Examples

      iex> func_def1 = {:function_def, [name: "add", params: ["x", "y"]], []}
      iex> func_def2 = {:function_def, [name: "sub", params: ["x", "y"]], []}
      iex> Metastatic.AST.container(:module, "MyApp.Math", [func_def1, func_def2])
      {:container, [container_type: :module, name: "MyApp.Math"], [{:function_def, [name: "add", params: ["x", "y"]], []}, {:function_def, [name: "sub", params: ["x", "y"]], []}]}
  """
  @spec container(container_type(), String.t(), [meta_ast()], keyword()) :: meta_ast()
  def container(type, name, body, extra_meta \\ [])
      when type in @container_types and is_binary(name) and is_list(body) do
    meta = Keyword.merge([container_type: type, name: name], extra_meta)
    {:container, meta, body}
  end

  @doc """
  Create a function definition node.

  ## Examples

      iex> body = [{:binary_op, [category: :arithmetic, operator: :+],
      ...>   [{:variable, [], "x"}, {:variable, [], "y"}]}]
      iex> Metastatic.AST.function_def("add", ["x", "y"], body)
      {:function_def, [name: "add", params: ["x", "y"]], [{:binary_op, [category: :arithmetic, operator: :+], [{:variable, [], "x"}, {:variable, [], "y"}]}]}
  """
  @spec function_def(String.t(), [term()], [meta_ast()], keyword()) :: meta_ast()
  def function_def(name, params, body, extra_meta \\ [])
      when is_binary(name) and is_list(params) and is_list(body) do
    meta = Keyword.merge([name: name, params: params], extra_meta)
    {:function_def, meta, body}
  end
end
