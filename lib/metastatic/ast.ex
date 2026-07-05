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

  ```mermaid
  graph LR
      subgraph "3-Tuple Structure"
          A["type_atom"] --- B["keyword_meta"] --- C["children_or_value"]
      end
      A -->|identifies| D["Node kind"]
      B -->|contains| E["Metadata"]
      C -->|holds| F["Value or children"]
  ```

  ## Third Element Semantics

  The third element varies by node type:
  - **Leaf nodes** (literal, variable): The actual value (`42`, `"x"`)
  - **Composite nodes** (binary_op, function_call): List of child AST nodes
  - **Container nodes** (container, function_def): List of body statements

  ```mermaid
  graph TD
      subgraph "Leaf Nodes"
          L1["{:literal, [subtype: :integer], 42}"]
          L2["{:variable, [], 'x'}"]
      end
      subgraph "Composite Nodes"
          C1["{:binary_op, [operator: :+], [left, right]}"]
          C2["{:function_call, [name: 'foo'], [arg1, arg2]}"]
      end
      subgraph "Container Nodes"
          S1["{:container, [name: 'MyModule'], [body...]}"]
          S2["{:function_def, [name: 'greet'], [body...]}"]
      end
  ```

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

  ## Semantic Enrichment (op_kind)

  Function call nodes may include semantic metadata via the `op_kind` key.
  This metadata is added during M1 -> M2 transformation by the semantic
  enricher, which detects known patterns (e.g., database operations).

  When present, `op_kind` is a keyword list with:
  - `:domain` - Semantic domain (e.g., `:db`, `:http`, `:cache`)
  - `:operation` - Operation type within the domain (e.g., `:retrieve`, `:create`)
  - `:target` - Optional target entity (e.g., `"User"`, `"orders"`)
  - `:async` - Whether the operation is asynchronous
  - `:framework` - Source framework (e.g., `:ecto`, `:sqlalchemy`)

  Example:

      {:function_call,
       [name: "Repo.get", op_kind: [domain: :db, operation: :retrieve, target: "User"]],
       [{:variable, [], "User"}, {:variable, [], "id"}]}

  Analyzers can use `op_kind` for precise semantic detection instead of heuristics.
  See `Metastatic.Semantic.OpKind` for the full type specification.

  ## Import Semantics

  The `:import` MetaAST type unifies all dependency/module-loading directives
  across languages. The `import_type` metadata key preserves the original
  language-specific semantics:

  **Elixir:**
  - `import_type: :import` -- brings functions into scope (`import MyModule`)
  - `import_type: :use` -- invokes `__using__/1` macro (`use GenServer`)
  - `import_type: :require` -- ensures module is compiled for macros (`require Logger`)
  - `import_type: :alias` -- creates a short name (`alias MyApp.Repo`)

  **Python:** `import_type: :import` for both `import` and `from...import`
  **Ruby:** `import_type: :require` for `require`, `:include` for `include`
  **Haskell:** `import_type: :import` for `import` declarations
  **Erlang:** `import_type: :import` for `-import` attributes

  All share the common structure:

      {:import, [source: "ModuleName", import_type: :import, language: :elixir], []}

  Adapters producing `:import` nodes MUST include `:source` (the module/package
  name as a string) and `:import_type` (the original directive atom). The
  `:language` key enables round-trip reconstruction of the original directive.

  ## Traversal

  Use `traverse/4` for walking and transforming ASTs:

      AST.traverse(ast, acc, &pre/2, &post/2)

  This mirrors `Macro.traverse/4` from Elixir's standard library.

  ## Dependently-Typed / Proof Extensions (Cure v0.18.0 / v0.19.0)

  Three MetaAST additions were back-ported from Cure v0.18.0 -- v0.19.0.
  They live at the M2.2 Extended and M2.2s Structural layers so that any
  language with the same semantics can reuse the shapes.

  - **`:pin`** -- pattern-position pin operator `^x`. Shape
    `{:pin, meta, [inner]}`. `inner` is the value to be pin-matched; it
    is most commonly a `:variable` node but may be any expression. In
    pattern position it constrains the subject to equal the referenced
    value rather than rebinding the name.
  - **`:assert_type`** -- compile-time type assertion `assert_type expr : T`.
    Shape `{:assert_type, meta, [expr, type_ast]}`. Lowered by the host
    language's type checker; erased by the code generator so it has zero
    runtime cost.
  - **`container_type: :proof`** -- new value of the `:container`
    metadata key. Shape `{:container, [container_type: :proof, name: ...],
    body}`. Structurally identical to `:module`, but every binding is
    expected to elaborate to an equality / refinement witness.

  ## Record / FSM Extensions (Cure v0.7.0 / v0.15.0)

  Two further MetaAST additions were back-ported from earlier Cure
  releases that the meta-model previously lacked:

  - **`:record_update`** (Cure v0.15.0) -- functional record update
    `Name{base | field: val, ...}`. Shape
    `{:record_update, [name: "Name", ...], [base | field_pairs]}`. The
    first child is the expression supplying the original record; the
    remaining children are `:pair` nodes describing the per-field
    overrides.
  - **`container_type: :fsm`** (Cure v0.7.0) -- finite state machine
    container `fsm Name with Payload`. Shape
    `{:container, [container_type: :fsm, name: ...], body}`. Carries
    optional FSM-only metadata keys such as `:payload`,
    `:terminal_states`, `:invariants`, `:verify`, `:timer`,
    `:on_transition`, `:on_enter`, `:on_exit`, `:on_failure`,
    `:on_timer`. Body elements are typically transition `:function_call`
    nodes carrying `:from`, `:event`, `:to`, and `:event_kind` metadata.

  ## Actor / Supervisor / App Extensions (Cure v0.25.0 / v0.26.0)

  Three container_type values were back-ported from Cure v0.25.0 and
  v0.26.0 into the meta-model:

  - **`container_type: :actor`** (Cure v0.25.0) -- typed GenServer-backed
    process `actor Name [with InitExpr]`. Carries optional lifecycle
    callback metadata keys: `:on_start`, `:on_message`, `:on_stop` (each a
    list of `:match_arm` nodes). Optional `:init` metadata holds the initial
    payload expression. Body is `[]`; all content is hoisted onto the
    container meta by the parser.

  - **`container_type: :supervisor`** (Cure v0.25.0) -- OTP supervisor
    `sup Name`. Carries optional `:strategy`, `:intensity`, `:period`
    metadata (MetaAST literal nodes). Body is a list of `:child_spec` nodes,
    one per child declared in the `children` block.

  - **`container_type: :app`** (Cure v0.26.0) -- OTP Application container
    `app Name`. Carries optional metadata: `:vsn`, `:description`, `:root`,
    `:applications`, `:included_applications`, `:env`, `:registered` (all
    MetaAST nodes), plus `:on_start`, `:on_stop` callback clause lists and
    `:on_phase` entries (each `[{phase_atom, [match_arm]}]`). Body is `[]`;
    all declarative content is hoisted onto the container meta.

  A companion structural node `:child_spec` is also added:

  - **`:child_spec`** -- a single supervisor child declaration `Module as id
    [(opts)]`. Shape `{:child_spec, meta, []}` where meta carries:
      * `:module` (binary) -- the child module path (dotted string);
      * `:id` (binary) -- the local child identifier;
      * `:kind` (`:worker` | `:supervisor`) -- whether the child is a plain
        worker or a nested supervisor;
      * `:restart`, `:shutdown`, etc. -- OTP child-spec options as MetaAST
        literal nodes.
    The body is always `[]`.

  ## Bitstring / Comment Extensions (Cure v0.20.0)

  Two M2.1 Core additions were back-ported from Cure v0.20.0 -- "The
  Shape of Things":

  - **`:bin_segment`** -- a single element of a bitstring literal /
    pattern such as `<<x::utf8, rest::binary>>`. Shape
    `{:bin_segment, meta, [value]}`. Accepted meta keys mirror Elixir's
    bitstring specifier grammar:
      * `:type` -- one of `:integer`, `:float`, `:bits`, `:bitstring`,
        `:bytes`, `:binary`, `:utf8`, `:utf16`, `:utf32`, `:any`;
      * `:signedness` -- `:signed` or `:unsigned`;
      * `:endianness` -- `:big`, `:little`, or `:native`;
      * `:size` -- a MetaAST node (typically `:literal` integer or
        `:variable`);
      * `:unit` -- integer `1..256`.
  - **`:literal` with `subtype: :bytes`** now accepts two payload
    shapes: the historical `binary()` value, or a list of
    `:bin_segment` children representing the segment grammar. Walkers
    and path utilities treat the segment-list payload as composite so
    that analyzers can traverse into each segment value.
  - **`:comment`** -- a trivia node representing a source comment.
    Shape `{:comment, meta, text}`. `:comment_kind` metadata is one of
    `:line` (default, plain `#` or `//`), `:doc` (Elixir `@doc` / Cure
    `##`), or `:block` (C-style). Analyzers and code generators skip
    comments; formatters and documentation tooling use them to
    round-trip source faithfully.
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
          | :throw
          | :block
          | :assignment
          | :inline_match
          | :range
          | :string_interpolation
          | :bin_segment
          | :comment

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
          | :yield
          | :comprehension
          | :generator
          | :filter
          | :pipe
          | :pin
          | :assert_type

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
          | :import
          | :type_annotation
          | :decorator
          | :record_update
          | :child_spec

  @typedoc """
  Clause entry for grouped multi-clause function definitions.

  Used in the `clauses:` metadata of `:function_def` nodes when multiple
  function clauses (same name/arity) are grouped together.

  Fields:
  - `:params` - Parameter list for this clause
  - `:guard` - Guard expression (optional)
  - `:body` - List of body statements
  """
  @type function_clause :: %{
          params: [meta_ast()],
          guard: meta_ast() | nil,
          body: [meta_ast()]
        }

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
          | :char
          | :bytes

  @typedoc """
  Category for binary/unary operators.
  """
  @type operator_category :: :arithmetic | :comparison | :boolean | :bitwise | :range | :string

  @typedoc """
  Container type classification.

  `:proof` is emitted by Cure v0.19.0+ for `proof Name.Path` containers;
  structurally identical to `:module`, semantically a proposition-level
  namespace.

  `:fsm` is emitted by Cure for `fsm Name with Payload` containers; the
  body is a list of transition `:function_call` nodes (carrying `:from`,
  `:event`, `:to`, `:event_kind` metadata), and FSM-only metadata such
  as `:payload`, `:terminal_states`, `:invariants`, `:verify`, `:timer`,
  `:on_transition`, `:on_enter`, `:on_exit`, `:on_failure`, `:on_timer`
  is carried on the container's own `meta`.

  `:actor` is emitted by Cure v0.25.0+ for `actor Name [with InitExpr]`
  containers. Lifecycle callbacks (`:on_start`, `:on_message`, `:on_stop`)
  are stored as keyword list entries on `meta`; the body is always `[]`.
  Optional `:init` metadata carries the initial state expression.

  `:supervisor` is emitted by Cure v0.25.0+ for `sup Name` containers.
  Supervision settings (`:strategy`, `:intensity`, `:period`) are stored
  on `meta`; the body is a list of `:child_spec` nodes.

  `:app` is emitted by Cure v0.26.0+ for `app Name` containers. All
  declarative content (`:vsn`, `:description`, `:root`, `:applications`,
  `:included_applications`, `:env`, `:registered`, `:on_start`, `:on_stop`,
  `:on_phase`) is stored on `meta`; the body is always `[]`.
  """
  @type container_type ::
          :module
          | :class
          | :namespace
          | :interface
          | :trait
          | :protocol
          | :enum
          | :struct
          | :proof
          | :fsm
          | :actor
          | :supervisor
          | :app

  @typedoc """
  Visibility modifier.
  """
  @type visibility :: :public | :private | :protected

  @typedoc """
  Parameter kind for `:param` nodes.

  Classifies the parameter's calling convention:
  - `:positional` - Regular positional argument (`x` in `def f(x)`)
  - `:keyword` - Keyword-only argument (Python: after `*`; JS/TS named params)
  - `:variadic` - Variadic positional argument (`*args` in Python, `...rest` in JS)
  - `:keyword_variadic` - Variadic keyword argument (`**kwargs` in Python)

  If not set, `:positional` is assumed.
  """
  @type param_kind :: :positional | :keyword | :variadic | :keyword_variadic

  @typedoc """
  Import type classification for `:import` nodes.

  Preserves the original language directive so that from_meta can reconstruct
  the correct syntax. Each language maps its dependency-loading constructs
  to one of these atoms.
  """
  @type import_type :: :import | :use | :require | :alias | :include | :from | :module | :export

  @typedoc """
  Scope classification for variable nodes.

  Used in the `scope` metadata key of `:variable` nodes to distinguish
  between different binding contexts:

  - `:local` - Regular local variables (e.g., `x` in Elixir, `x` in Python)
  - `:module_attribute` - Module-level attributes (e.g., `@attr` in Elixir)
  - `:global` - Global/top-level variables (e.g., `global x` in Python)
  - `:instance` - Instance variables (e.g., `@x` in Ruby, `self.x` in Python)
  - `:class` - Class-level variables (e.g., `@@x` in Ruby)

  Example:

      {:variable, [scope: :local, line: 5], "x"}
      {:variable, [scope: :module_attribute], "@moduledoc"}
  """
  @type variable_scope :: :local | :module_attribute | :global | :instance | :class

  @typedoc """
  Semantic domain for op_kind metadata.
  Domains categorize operations by their high-level purpose.
  """
  @type semantic_domain :: :db | :http | :cache | :queue | :file | :external

  @typedoc """
  Database operation types for op_kind metadata.
  """
  @type db_operation ::
          :retrieve
          | :retrieve_all
          | :query
          | :create
          | :update
          | :delete
          | :transaction
          | :preload
          | :aggregate

  @typedoc """
  Semantic operation kind metadata added to function_call nodes.
  Provides precise semantic information about what a function does.

  Fields:
  - `:domain` - High-level semantic category (required)
  - `:operation` - Specific operation within the domain (required)
  - `:target` - Target entity or resource (optional)
  - `:async` - Whether the operation is asynchronous (optional)
  - `:framework` - Source framework that provides this operation (optional)

  Example: `[domain: :db, operation: :retrieve, target: "User", framework: :ecto]`
  """
  @type op_kind :: [
          domain: semantic_domain(),
          operation: atom(),
          target: String.t() | nil,
          async: boolean(),
          framework: atom() | nil
        ]

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
    :throw,
    :block,
    :assignment,
    :inline_match,
    :range,
    :string_interpolation,
    :bin_segment,
    :comment
  ]

  @extended_types [
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
    :assert_type
  ]

  @structural_types [
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

  @native_types [:language_specific]

  @all_types @core_types ++ @extended_types ++ @structural_types ++ @native_types

  @literal_subtypes [:integer, :float, :string, :boolean, :null, :symbol, :regex, :char, :bytes]

  @operator_categories [:arithmetic, :comparison, :boolean, :bitwise, :range, :string]

  @container_types [
    :module,
    :class,
    :namespace,
    :interface,
    :trait,
    :protocol,
    :enum,
    :struct,
    :proof,
    :fsm,
    :actor,
    :supervisor,
    :app
  ]

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
  # :literal nodes with a bin_segment list payload (Cure v0.20.0+) are
  # treated as composite so analyzers and transformers can walk into the
  # embedded expressions. Raw binary/atom/numeric payloads stay leaf.
  defp traverse_children(:literal, value, acc, pre, post)
       when is_list(value) do
    if Enum.all?(value, &match?({:bin_segment, _, _}, &1)) do
      Enum.map_reduce(value, acc, fn child, acc ->
        do_traverse(child, acc, pre, post)
      end)
    else
      {value, acc}
    end
  end

  # Leaf nodes - value is not traversable
  defp traverse_children(type, value, acc, _pre, _post)
       when type in [:literal, :variable, :comment] do
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
  Performs a depth-first, pre-order traversal of the MetaAST.

  Returns a new AST where each node is the result of invoking `fun`
  on each corresponding node. This is the transform-only variant
  (no accumulator), mirroring `Macro.prewalk/2`.

  ## Examples

      iex> ast = {:binary_op, [category: :arithmetic, operator: :+],
      ...>   [{:literal, [subtype: :integer], 1}, {:literal, [subtype: :integer], 2}]}
      iex> Metastatic.AST.prewalk(ast, fn
      ...>   {:literal, meta, value} when is_integer(value) -> {:literal, meta, value * 10}
      ...>   node -> node
      ...> end)
      {:binary_op, [category: :arithmetic, operator: :+],
        [{:literal, [subtype: :integer], 10}, {:literal, [subtype: :integer], 20}]}
  """
  @spec prewalk(meta_ast() | term(), (meta_ast() | term() -> meta_ast() | term())) ::
          meta_ast() | term()
  def prewalk(ast, fun) when is_function(fun, 1) do
    {new_ast, _} =
      traverse(ast, nil, fn node, nil -> {fun.(node), nil} end, fn node, acc -> {node, acc} end)

    new_ast
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

  @doc """
  Performs a depth-first, post-order traversal of the MetaAST.

  Returns a new AST where each node is the result of invoking `fun`
  on each corresponding node. This is the transform-only variant
  (no accumulator), mirroring `Macro.postwalk/2`.

  ## Examples

      iex> ast = {:binary_op, [category: :arithmetic, operator: :+],
      ...>   [{:literal, [subtype: :integer], 1}, {:literal, [subtype: :integer], 2}]}
      iex> Metastatic.AST.postwalk(ast, fn
      ...>   {:literal, meta, value} when is_integer(value) -> {:literal, meta, value * 10}
      ...>   node -> node
      ...> end)
      {:binary_op, [category: :arithmetic, operator: :+],
        [{:literal, [subtype: :integer], 10}, {:literal, [subtype: :integer], 20}]}
  """
  @spec postwalk(meta_ast() | term(), (meta_ast() | term() -> meta_ast() | term())) ::
          meta_ast() | term()
  def postwalk(ast, fun) when is_function(fun, 1) do
    {new_ast, _} =
      traverse(ast, nil, fn node, acc -> {node, acc} end, fn node, nil -> {fun.(node), nil} end)

    new_ast
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

  # Throw/raise: {:throw, [kind: :raise], [exception_expr]}
  defp valid_node?(:throw, _meta, [value]) do
    is_nil(value) or conforms?(value)
  end

  defp valid_node?(:throw, _meta, []), do: true
  defp valid_node?(:throw, _meta, _), do: false

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

  # Range: {start, stop} with optional step in meta
  defp valid_node?(:range, meta, [start, stop]) do
    step = Keyword.get(meta, :step)

    conforms?(start) and conforms?(stop) and
      (is_nil(step) or conforms?(step))
  end

  defp valid_node?(:range, _meta, _), do: false

  # String interpolation: list of literal string and expression parts
  defp valid_node?(:string_interpolation, _meta, parts) do
    is_list(parts) and Enum.all?(parts, &conforms?/1)
  end

  # Bitstring segment (Cure v0.20.0+). The children list has exactly one
  # entry -- the value expression. All specifier information lives in
  # metadata (:type, :signedness, :endianness, :size, :unit).
  @bin_segment_types [
    :integer,
    :float,
    :bits,
    :bitstring,
    :bytes,
    :binary,
    :utf8,
    :utf16,
    :utf32,
    :any
  ]
  @bin_segment_signedness [:signed, :unsigned]
  @bin_segment_endianness [:big, :little, :native]

  defp valid_node?(:bin_segment, meta, [value]) do
    type = Keyword.get(meta, :type)
    sign = Keyword.get(meta, :signedness)
    endian = Keyword.get(meta, :endianness)
    size = Keyword.get(meta, :size)
    unit = Keyword.get(meta, :unit)

    conforms?(value) and
      (is_nil(type) or type in @bin_segment_types) and
      (is_nil(sign) or sign in @bin_segment_signedness) and
      (is_nil(endian) or endian in @bin_segment_endianness) and
      (is_nil(size) or conforms?(size)) and
      (is_nil(unit) or is_integer(unit))
  end

  defp valid_node?(:bin_segment, _meta, _), do: false

  # Trivia comment node (Cure v0.20.0+). The value is the comment text;
  # `:comment_kind` metadata distinguishes `:line` (plain `#`) from `:doc`
  # (`##` / `###`). Comments are trivia: analyzers and code generators
  # skip them, but formatters and documentation tools need them back.
  @comment_kinds [:line, :doc, :block]

  defp valid_node?(:comment, meta, text) when is_binary(text) do
    kind = Keyword.get(meta, :comment_kind, :line)
    kind in @comment_kinds
  end

  defp valid_node?(:comment, _meta, _), do: false

  # M2.2 Extended types
  defp valid_node?(:loop, meta, children) do
    loop_type = Keyword.get(meta, :loop_type)

    case {loop_type, children} do
      {:while, [condition, body]} ->
        conforms?(condition) and conforms?(body)

      {t, [iterator, collection, body]} when t in [:for, :for_each] ->
        conforms?(iterator) and conforms?(collection) and conforms?(body)

      {:do_while, [condition, body]} ->
        conforms?(condition) and conforms?(body)

      {:infinite, [body]} ->
        conforms?(body)

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

  defp valid_node?(:pattern_match, _meta, [scrutinee | arms]) when is_list(arms) do
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
    op_type in [:await, :async, :async_def] and conforms?(operation)
  end

  defp valid_node?(:async_operation, _meta, _), do: false

  # Yield: {:yield, [kind: :yield], [value]} or {:yield, [kind: :yield_from], [iterable]}
  defp valid_node?(:yield, _meta, [value]) do
    is_nil(value) or conforms?(value)
  end

  defp valid_node?(:yield, _meta, []), do: true
  defp valid_node?(:yield, _meta, _), do: false

  # Comprehension: body + generators/filters
  defp valid_node?(:comprehension, _meta, [body | generators_and_filters])
       when is_list(generators_and_filters) do
    conforms?(body) and Enum.all?(generators_and_filters, &conforms?/1)
  end

  defp valid_node?(:comprehension, _meta, _), do: false

  # Generator: iterates variable over collection
  defp valid_node?(:generator, _meta, [variable, collection]) do
    conforms?(variable) and conforms?(collection)
  end

  defp valid_node?(:generator, _meta, _), do: false

  # Filter: condition guard in comprehension
  defp valid_node?(:filter, _meta, [condition]) do
    conforms?(condition)
  end

  defp valid_node?(:filter, _meta, _), do: false

  # Pin: {:pin, meta, [inner]} -- pattern-position pin operator (Cure v0.18.0+).
  # `inner` is typically a `:variable`, but the shape accepts any conforming
  # MetaAST node so that fallback paths (e.g. pinning a call result) are valid.
  defp valid_node?(:pin, _meta, [inner]) do
    conforms?(inner)
  end

  defp valid_node?(:pin, _meta, _), do: false

  # Assert-type: {:assert_type, meta, [expr, type_ast]} -- compile-time type
  # assertion (Cure v0.19.0+). The type checker verifies `expr : type_ast`;
  # the code generator erases the wrapper.
  defp valid_node?(:assert_type, _meta, [expr, type_ast]) do
    conforms?(expr) and conforms?(type_ast)
  end

  defp valid_node?(:assert_type, _meta, _), do: false

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

  # Param node: {:param, [kind: :positional, pattern: pattern, default: default], name}
  @param_kinds [:positional, :keyword, :variadic, :keyword_variadic]

  defp valid_node?(:param, meta, name) when is_binary(name) do
    pattern = Keyword.get(meta, :pattern)
    default = Keyword.get(meta, :default)
    kind = Keyword.get(meta, :kind, :positional)

    kind in @param_kinds and
      (is_nil(pattern) or conforms?(pattern)) and
      (is_nil(default) or conforms?(default))
  end

  defp valid_node?(:param, _meta, _), do: false

  # Pipe node: {:pipe, [operator: :|>], [left, right]}
  # Preserves pipe operator structure instead of desugaring to function calls.
  defp valid_node?(:pipe, meta, [left, right]) do
    operator = Keyword.get(meta, :operator, :|>)
    is_atom(operator) and conforms?(left) and conforms?(right)
  end

  defp valid_node?(:pipe, _meta, _), do: false

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

  defp valid_node?(:import, meta, []) do
    source = Keyword.get(meta, :source)
    names = Keyword.get(meta, :names)

    is_binary(source) and
      (is_nil(names) or (is_list(names) and Enum.all?(names, &is_binary/1)))
  end

  defp valid_node?(:import, _meta, _), do: false

  # Type annotation: target + type expression
  defp valid_node?(:type_annotation, meta, children) do
    annotation_type = Keyword.get(meta, :annotation_type)

    annotation_type in [:spec, :type, :hint, :callback] and
      is_list(children) and Enum.all?(children, &conforms?/1)
  end

  # Decorator: {:decorator, [name: "staticmethod"], [args]}
  defp valid_node?(:decorator, meta, args) do
    name = Keyword.get(meta, :name)
    is_binary(name) and is_list(args) and Enum.all?(args, &conforms?/1)
  end

  # Record update: {:record_update, [name: "Name", ...], [base | field_pairs]}
  # (Cure v0.15.0+). The first child supplies the original record value;
  # the remaining children are typically `:pair` nodes describing the
  # per-field overrides. The list must be non-empty (the base is required).
  defp valid_node?(:record_update, meta, [base | field_pairs] = children) do
    name = Keyword.get(meta, :name)

    is_binary(name) and is_list(children) and
      conforms?(base) and Enum.all?(field_pairs, &conforms?/1)
  end

  defp valid_node?(:record_update, _meta, _), do: false

  # Child spec: {:child_spec, meta, []} -- a supervisor child entry.
  # (Cure v0.25.0+). Meta must have a non-empty `:module` string (the
  # module path) and a non-empty `:id` string. `:kind` must be `:worker`
  # or `:supervisor` (defaults to `:worker`). Body is always empty.
  defp valid_node?(:child_spec, meta, []) do
    module = Keyword.get(meta, :module)
    id = Keyword.get(meta, :id)
    kind = Keyword.get(meta, :kind, :worker)

    is_binary(module) and module != "" and
      is_binary(id) and id != "" and
      kind in [:worker, :supervisor]
  end

  defp valid_node?(:child_spec, _meta, _), do: false

  # M2.3 Native type
  defp valid_node?(:language_specific, meta, _native_ast) do
    language = Keyword.get(meta, :language)
    is_atom(language)
  end

  defp valid_pattern_arms?(arms) when is_list(arms) do
    Enum.all?(arms, fn
      {:match_arm, _, _} = arm -> conforms?(arm)
      _ -> false
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

      _ ->
        false
    end)
  end

  # Validate literal values match their subtype
  defp valid_literal_value?(:integer, value), do: is_integer(value)
  defp valid_literal_value?(:float, value), do: is_float(value)
  defp valid_literal_value?(:string, value), do: is_binary(value)
  defp valid_literal_value?(:boolean, value), do: is_boolean(value)
  defp valid_literal_value?(:null, value), do: is_nil(value)
  defp valid_literal_value?(:symbol, value), do: is_atom(value)
  defp valid_literal_value?(:regex, _value), do: true
  defp valid_literal_value?(:char, value), do: is_binary(value) or is_integer(value)

  # `:bytes` accepts two shapes (Cure v0.20.0+):
  #   * a raw `binary()` -- the legacy payload for languages that do not
  #     expose bitstring segment grammar (or that serialise the bytes for
  #     a downstream target);
  #   * a list of `:bin_segment` MetaAST nodes -- the Elixir-style
  #     `<<seg1, seg2, ...>>` grammar. Every child must itself conform.
  defp valid_literal_value?(:bytes, value) when is_binary(value), do: true

  defp valid_literal_value?(:bytes, value) when is_list(value) do
    Enum.all?(value, fn
      {:bin_segment, _, _} = seg -> conforms?(seg)
      _ -> false
    end)
  end

  defp valid_literal_value?(:bytes, _value), do: false

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
  def leaf?({type, _meta, _children}) when type in [:literal, :variable, :comment], do: true
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
      iex> ast = {:function_def, [name: "add", params: [{:param, [], "x"}, {:param, [], "y"}]], [body]}
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

      iex> func_def1 = {:function_def, [name: "add", params: [{:param, [], "x"}, {:param, [], "y"}]], []}
      iex> func_def2 = {:function_def, [name: "sub", params: [{:param, [], "x"}, {:param, [], "y"}]], []}
      iex> Metastatic.AST.container(:module, "MyApp.Math", [func_def1, func_def2])
      {:container, [container_type: :module, name: "MyApp.Math"], [{:function_def, [name: "add", params: [{:param, [], "x"}, {:param, [], "y"}]], []}, {:function_def, [name: "sub", params: [{:param, [], "x"}, {:param, [], "y"}]], []}]}
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
      {:function_def, [name: "add", params: [{:param, [], "x"}, {:param, [], "y"}]], [{:binary_op, [category: :arithmetic, operator: :+], [{:variable, [], "x"}, {:variable, [], "y"}]}]}
  """
  @spec function_def(String.t(), [term()], [meta_ast()], keyword()) :: meta_ast()
  def function_def(name, params, body, extra_meta \\ [])
      when is_binary(name) and is_list(params) and is_list(body) do
    normalized_params = Enum.map(params, &normalize_param/1)
    meta = Keyword.merge([name: name, params: normalized_params], extra_meta)
    {:function_def, meta, body}
  end

  defp normalize_param({:param, _, _} = param), do: param
  defp normalize_param(name) when is_binary(name), do: {:param, [], name}

  # ----- New Type Builder Helpers -----

  @doc """
  Create a range node.

  ## Examples

      iex> start = {:literal, [subtype: :integer], 1}
      iex> stop = {:literal, [subtype: :integer], 10}
      iex> Metastatic.AST.range(start, stop)
      {:range, [], [{:literal, [subtype: :integer], 1}, {:literal, [subtype: :integer], 10}]}

      iex> start = {:literal, [subtype: :integer], 1}
      iex> stop = {:literal, [subtype: :integer], 10}
      iex> step = {:literal, [subtype: :integer], 2}
      iex> Metastatic.AST.range(start, stop, step: step)
      {:range, [step: {:literal, [subtype: :integer], 2}], [{:literal, [subtype: :integer], 1}, {:literal, [subtype: :integer], 10}]}
  """
  @spec range(meta_ast(), meta_ast(), keyword()) :: meta_ast()
  def range(start, stop, meta \\ []) do
    {:range, meta, [start, stop]}
  end

  @doc """
  Create a string interpolation node.

  ## Examples

      iex> parts = [{:literal, [subtype: :string], "Hello, "}, {:variable, [], "name"}, {:literal, [subtype: :string], "!"}]
      iex> Metastatic.AST.string_interpolation(parts)
      {:string_interpolation, [], [{:literal, [subtype: :string], "Hello, "}, {:variable, [], "name"}, {:literal, [subtype: :string], "!"}]}
  """
  @spec string_interpolation([meta_ast()], keyword()) :: meta_ast()
  def string_interpolation(parts, meta \\ []) when is_list(parts) do
    {:string_interpolation, meta, parts}
  end

  @doc """
  Create a comprehension node.

  ## Examples

      iex> body = {:binary_op, [category: :arithmetic, operator: :*], [{:variable, [], "x"}, {:variable, [], "x"}]}
      iex> gen = {:generator, [], [{:variable, [], "x"}, {:function_call, [name: "range"], [{:literal, [subtype: :integer], 10}]}]}
      iex> Metastatic.AST.comprehension(body, [gen])
      {:comprehension, [], [{:binary_op, [category: :arithmetic, operator: :*], [{:variable, [], "x"}, {:variable, [], "x"}]}, {:generator, [], [{:variable, [], "x"}, {:function_call, [name: "range"], [{:literal, [subtype: :integer], 10}]}]}]}
  """
  @spec comprehension(meta_ast(), [meta_ast()], keyword()) :: meta_ast()
  def comprehension(body, generators_and_filters, meta \\ [])
      when is_list(generators_and_filters) do
    {:comprehension, meta, [body | generators_and_filters]}
  end

  @doc """
  Create a generator node.

  ## Examples

      iex> var = {:variable, [], "x"}
      iex> coll = {:function_call, [name: "range"], [{:literal, [subtype: :integer], 10}]}
      iex> Metastatic.AST.generator(var, coll)
      {:generator, [], [{:variable, [], "x"}, {:function_call, [name: "range"], [{:literal, [subtype: :integer], 10}]}]}
  """
  @spec generator(meta_ast(), meta_ast(), keyword()) :: meta_ast()
  def generator(variable, collection, meta \\ []) do
    {:generator, meta, [variable, collection]}
  end

  @doc """
  Create a filter node.

  ## Examples

      iex> condition = {:binary_op, [category: :comparison, operator: :>], [{:variable, [], "x"}, {:literal, [subtype: :integer], 0}]}
      iex> Metastatic.AST.filter(condition)
      {:filter, [], [{:binary_op, [category: :comparison, operator: :>], [{:variable, [], "x"}, {:literal, [subtype: :integer], 0}]}]}
  """
  @spec filter(meta_ast(), keyword()) :: meta_ast()
  def filter(condition, meta \\ []) do
    {:filter, meta, [condition]}
  end

  @doc """
  Create a pipe node.

  Preserves the pipe operator (`|>`, `->`, etc.) as a first-class node
  rather than desugaring it into a function call. Useful for languages
  where the pipe has distinct syntactic or semantic meaning.

  ## Parameters

  - `left` - Left-hand side of the pipe
  - `right` - Right-hand side (function to pipe into)
  - `meta` - Optional metadata (default: `[operator: :|>]`)

  ## Examples

      iex> left = {:variable, [], "x"}
      iex> right = {:function_call, [name: "inspect"], []}
      iex> Metastatic.AST.pipe(left, right)
      {:pipe, [operator: :|>], [{:variable, [], "x"}, {:function_call, [name: "inspect"], []}]}
  """
  @spec pipe(meta_ast(), meta_ast(), keyword()) :: meta_ast()
  def pipe(left, right, meta \\ [operator: :|>]) do
    {:pipe, meta, [left, right]}
  end

  @doc """
  Create a throw/raise node.

  ## Examples

      iex> exception = {:function_call, [name: "ValueError"], [{:literal, [subtype: :string], "bad value"}]}
      iex> Metastatic.AST.throw_node(:raise, exception)
      {:throw, [kind: :raise], [{:function_call, [name: "ValueError"], [{:literal, [subtype: :string], "bad value"}]}]}
  """
  @spec throw_node(atom(), meta_ast() | nil, keyword()) :: meta_ast()
  def throw_node(kind \\ :raise, value \\ nil, extra_meta \\ []) do
    meta = Keyword.merge([kind: kind], extra_meta)
    children = if is_nil(value), do: [], else: [value]
    {:throw, meta, children}
  end

  @doc """
  Create a yield node.

  ## Examples

      iex> value = {:literal, [subtype: :integer], 42}
      iex> Metastatic.AST.yield_node(:yield, value)
      {:yield, [kind: :yield], [{:literal, [subtype: :integer], 42}]}
  """
  @spec yield_node(atom(), meta_ast() | nil, keyword()) :: meta_ast()
  def yield_node(kind \\ :yield, value \\ nil, extra_meta \\ []) do
    meta = Keyword.merge([kind: kind], extra_meta)
    children = if is_nil(value), do: [], else: [value]
    {:yield, meta, children}
  end

  @doc """
  Create a decorator node.

  ## Examples

      iex> Metastatic.AST.decorator("staticmethod")
      {:decorator, [name: "staticmethod"], []}

      iex> Metastatic.AST.decorator("app.route", [{:literal, [subtype: :string], "/api"}])
      {:decorator, [name: "app.route"], [{:literal, [subtype: :string], "/api"}]}
  """
  @spec decorator(String.t(), [meta_ast()], keyword()) :: meta_ast()
  def decorator(name, args \\ [], extra_meta \\ []) when is_binary(name) and is_list(args) do
    meta = Keyword.merge([name: name], extra_meta)
    {:decorator, meta, args}
  end

  @doc """
  Create a type annotation node.

  ## Examples

      iex> target = {:function_call, [name: "add"], []}
      iex> type_expr = {:literal, [subtype: :string], "integer() :: integer() -> integer()"}
      iex> Metastatic.AST.type_annotation(:spec, target, type_expr)
      {:type_annotation, [annotation_type: :spec], [{:function_call, [name: "add"], []}, {:literal, [subtype: :string], "integer() :: integer() -> integer()"}]}
  """
  @spec type_annotation(atom(), meta_ast(), meta_ast(), keyword()) :: meta_ast()
  def type_annotation(annotation_type, target, type_expr, extra_meta \\ [])
      when annotation_type in [:spec, :type, :hint, :callback] do
    meta = Keyword.merge([annotation_type: annotation_type], extra_meta)
    {:type_annotation, meta, [target, type_expr]}
  end

  @doc """
  Create a bitstring segment node (Cure v0.20.0+).

  Segments appear as children of `{:literal, [subtype: :bytes], [...]}`
  nodes and mirror Elixir's `<<value::type-size(n)-unit(u)-sign-endian>>`
  grammar. The `value` is a conforming MetaAST node; the accepted meta
  keys are `:type`, `:signedness`, `:endianness`, `:size` (AST node)
  and `:unit` (integer).

  ## Examples

      iex> v = {:variable, [], "x"}
      iex> Metastatic.AST.bin_segment(v, type: :utf8)
      {:bin_segment, [type: :utf8], [{:variable, [], "x"}]}

      iex> v = {:variable, [], "rest"}
      iex> Metastatic.AST.bin_segment(v, type: :binary)
      {:bin_segment, [type: :binary], [{:variable, [], "rest"}]}
  """
  @spec bin_segment(meta_ast(), keyword()) :: meta_ast()
  def bin_segment(value, meta \\ []) when is_list(meta) do
    {:bin_segment, meta, [value]}
  end

  @doc """
  Create a trivia comment node (Cure v0.20.0+).

  Comments are trivia: analyzers and code generators skip them, but
  formatters and documentation tooling need them back. `kind` is one
  of `:line` (plain `#` or `//`), `:doc` (Elixir `@doc` / Cure `##`)
  or `:block` (C-style `/* ... */`).

  ## Examples

      iex> Metastatic.AST.comment("TODO: revisit")
      {:comment, [comment_kind: :line], "TODO: revisit"}

      iex> Metastatic.AST.comment("Public API entry point", :doc, line: 5)
      {:comment, [comment_kind: :doc, line: 5], "Public API entry point"}
  """
  @spec comment(String.t(), atom(), keyword()) :: meta_ast()
  def comment(text, kind \\ :line, extra_meta \\ [])
      when is_binary(text) and kind in [:line, :doc, :block] do
    meta = Keyword.merge([comment_kind: kind], extra_meta)
    {:comment, meta, text}
  end

  @doc "Builds a `:unary_op` node."
  @spec unary_op(atom(), atom(), meta_ast(), keyword()) :: meta_ast()
  def unary_op(category, operator, operand, extra_meta \\ []) do
    {:unary_op, [category: category, operator: operator] ++ extra_meta, [operand]}
  end

  @doc "Builds a `:list` node."
  @spec list_node([meta_ast()], keyword()) :: meta_ast()
  def list_node(elements, meta \\ []) when is_list(elements) do
    {:list, meta, elements}
  end

  @doc "Builds a `:tuple` node."
  @spec tuple_node([meta_ast()], keyword()) :: meta_ast()
  def tuple_node(elements, meta \\ []) when is_list(elements) do
    {:tuple, meta, elements}
  end

  @doc "Builds a `:conditional` node."
  @spec conditional(atom(), meta_ast(), [meta_ast()], keyword()) :: meta_ast()
  def conditional(kind, condition, branches, extra_meta \\ [])
      when is_atom(kind) and is_list(branches) do
    {:conditional, [kind: kind] ++ extra_meta, [condition | branches]}
  end

  @doc "Builds an `:assignment` node."
  @spec assignment(meta_ast(), meta_ast(), keyword()) :: meta_ast()
  def assignment(target, value, meta \\ []) do
    {:assignment, meta, [target, value]}
  end

  @doc "Builds an `:early_return` node."
  @spec early_return(meta_ast() | nil, keyword()) :: meta_ast()
  def early_return(value \\ nil, meta \\ []) do
    {:early_return, meta, if(value, do: [value], else: [])}
  end

  @doc "Builds a `:loop` node."
  @spec loop_node(atom(), meta_ast() | nil, [meta_ast()], keyword()) :: meta_ast()
  def loop_node(kind, condition, body, extra_meta \\ [])
      when is_atom(kind) and is_list(body) do
    children = if condition, do: [condition | body], else: body
    {:loop, [kind: kind] ++ extra_meta, children}
  end

  @doc "Builds a `:lambda` node."
  @spec lambda([meta_ast()], [meta_ast()], keyword()) :: meta_ast()
  def lambda(params, body, meta \\ []) when is_list(params) and is_list(body) do
    {:lambda, meta, params ++ body}
  end

  @doc "Builds a `:collection_op` node."
  @spec collection_op(atom(), meta_ast(), [meta_ast()], keyword()) :: meta_ast()
  def collection_op(operation, collection, args, extra_meta \\ [])
      when is_atom(operation) and is_list(args) do
    {:collection_op, [operation: operation] ++ extra_meta, [collection | args]}
  end

  @doc "Builds a `:pattern_match` node."
  @spec pattern_match(meta_ast(), [meta_ast()], keyword()) :: meta_ast()
  def pattern_match(subject, arms, meta \\ []) when is_list(arms) do
    {:pattern_match, meta, [subject | arms]}
  end

  @doc "Builds a `:match_arm` node."
  @spec match_arm(meta_ast(), meta_ast() | nil, [meta_ast()], keyword()) :: meta_ast()
  def match_arm(pattern, guard, body, extra_meta \\ []) when is_list(body) do
    children = if guard, do: [pattern, guard | body], else: [pattern | body]
    {:match_arm, [has_guard: not is_nil(guard)] ++ extra_meta, children}
  end

  @doc "Builds an `:exception_handling` node."
  @spec exception_handling(atom(), [meta_ast()], keyword()) :: meta_ast()
  def exception_handling(kind, clauses, extra_meta \\ [])
      when is_atom(kind) and is_list(clauses) do
    {:exception_handling, [kind: kind] ++ extra_meta, clauses}
  end

  @doc "Builds an `:async_operation` node."
  @spec async_operation(atom(), [meta_ast()], keyword()) :: meta_ast()
  def async_operation(kind, children, extra_meta \\ [])
      when is_atom(kind) and is_list(children) do
    {:async_operation, [kind: kind] ++ extra_meta, children}
  end

  @doc "Builds a `:param` node."
  @spec param_node(String.t(), keyword()) :: meta_ast()
  def param_node(name, extra_meta \\ []) when is_binary(name) do
    {:param, [name: name] ++ extra_meta, name}
  end

  @doc "Builds an `:attribute_access` node."
  @spec attribute_access(meta_ast(), String.t(), keyword()) :: meta_ast()
  def attribute_access(object, attribute, extra_meta \\ []) when is_binary(attribute) do
    {:attribute_access, [attribute: attribute] ++ extra_meta, [object]}
  end

  @doc "Builds an `:augmented_assignment` node."
  @spec augmented_assignment(atom(), meta_ast(), meta_ast(), keyword()) :: meta_ast()
  def augmented_assignment(operator, target, value, extra_meta \\ []) when is_atom(operator) do
    {:augmented_assignment, [operator: operator] ++ extra_meta, [target, value]}
  end

  @doc "Builds a `:property` node."
  @spec property_node(String.t(), meta_ast() | nil, keyword()) :: meta_ast()
  def property_node(name, value \\ nil, extra_meta \\ []) when is_binary(name) do
    children = if value, do: [value], else: []
    {:property, [name: name] ++ extra_meta, children}
  end

  @doc "Builds an `:import` node."
  @spec import_node(String.t(), atom(), keyword()) :: meta_ast()
  def import_node(source, import_type, extra_meta \\ [])
      when is_binary(source) and is_atom(import_type) do
    {:import, [source: source, import_type: import_type] ++ extra_meta, []}
  end

  @doc "Builds a `:record_update` node."
  @spec record_update(meta_ast(), [meta_ast()], keyword()) :: meta_ast()
  def record_update(record, updates, meta \\ []) when is_list(updates) do
    {:record_update, meta, [record | updates]}
  end

  @doc "Builds a `:child_spec` node."
  @spec child_spec_node(meta_ast(), keyword()) :: meta_ast()
  def child_spec_node(spec, extra_meta \\ []) do
    {:child_spec, extra_meta, [spec]}
  end

  @doc "Builds a `:language_specific` node."
  @spec language_specific(atom(), term(), keyword()) :: meta_ast()
  def language_specific(language, value, extra_meta \\ []) when is_atom(language) do
    {:language_specific, [language: language] ++ extra_meta, value}
  end

  @doc "Builds a `:pin` node."
  @spec pin_node(meta_ast(), keyword()) :: meta_ast()
  def pin_node(expression, meta \\ []) do
    {:pin, meta, [expression]}
  end

  @doc "Builds an `:assert_type` node."
  @spec assert_type(atom(), meta_ast(), meta_ast(), keyword()) :: meta_ast()
  def assert_type(kind, expression, type_expr, extra_meta \\ []) when is_atom(kind) do
    {:assert_type, [kind: kind] ++ extra_meta, [expression, type_expr]}
  end

  # ----- Enumerable Walkers -----

  @doc """
  Returns an enumerable that traverses the MetaAST in depth-first, pre-order.

  Mirrors `Macro.prewalker/1`. The returned enumerable lazily yields each node
  before its children.

  ## Examples

      iex> ast = {:binary_op, [category: :arithmetic, operator: :+],
      ...>   [{:literal, [subtype: :integer], 1}, {:literal, [subtype: :integer], 2}]}
      iex> ast |> Metastatic.AST.prewalker() |> Enum.map(&Metastatic.AST.type/1)
      [:binary_op, :literal, :literal]
  """
  @spec prewalker(meta_ast()) :: Enumerable.t()
  def prewalker(ast) do
    Stream.unfold([ast], fn
      [] -> nil
      [node | rest] -> {node, child_nodes(node) ++ rest}
    end)
  end

  @doc """
  Returns an enumerable that traverses the MetaAST in depth-first, post-order.

  Mirrors `Macro.postwalker/1`. The returned enumerable lazily yields each node
  after its children.

  ## Examples

      iex> ast = {:binary_op, [category: :arithmetic, operator: :+],
      ...>   [{:literal, [subtype: :integer], 1}, {:literal, [subtype: :integer], 2}]}
      iex> ast |> Metastatic.AST.postwalker() |> Enum.map(&Metastatic.AST.type/1)
      [:literal, :literal, :binary_op]
  """
  @spec postwalker(meta_ast()) :: Enumerable.t()
  def postwalker(ast) do
    Stream.resource(
      fn -> [{ast, false}] end,
      fn
        [] ->
          {:halt, []}

        [{node, true} | rest] ->
          {[node], rest}

        [{node, false} | rest] ->
          children = child_nodes(node)
          expanded = Enum.map(children, &{&1, false}) ++ [{node, true}]
          {[], expanded ++ rest}
      end,
      fn _ -> :ok end
    )
  end

  # Extracts child MetaAST nodes from a node (skips leaf values).
  # A `:literal` with a bin_segment list payload (Cure v0.20.0+) is an
  # exception: it is structurally a leaf but semantically composite, so
  # we surface the bin_segment children for walker/path traversals.
  defp child_nodes({:literal, _meta, value}) when is_list(value) do
    if Enum.all?(value, &match?({:bin_segment, _, _}, &1)), do: value, else: []
  end

  defp child_nodes({type, _meta, children})
       when is_atom(type) and type in [:literal, :variable, :comment] do
    # Leaf nodes have no traversable children
    _ = children
    []
  end

  defp child_nodes({type, _meta, children})
       when is_atom(type) and is_list(children) do
    Enum.filter(children, &meta_ast_node?/1)
  end

  defp child_nodes(_), do: []

  defp meta_ast_node?({type, meta, _children}) when is_atom(type) and is_list(meta), do: true
  defp meta_ast_node?(_), do: false

  # ----- Path -----

  @doc """
  Returns the path to the node in `ast` for which `fun` returns a truthy value.

  The path is a list, starting with the node for which `fun` returns a truthy
  value, followed by all of its parents up to the root. Returns `nil` if no
  node matches.

  Mirrors `Macro.path/2`.

  ## Examples

      iex> ast = {:binary_op, [category: :arithmetic, operator: :+],
      ...>   [{:variable, [], "x"}, {:literal, [subtype: :integer], 42}]}
      iex> path = Metastatic.AST.path(ast, fn
      ...>   {:literal, _, 42} -> true
      ...>   _ -> false
      ...> end)
      iex> Enum.map(path, &Metastatic.AST.type/1)
      [:literal, :binary_op]

      iex> ast = {:literal, [subtype: :integer], 1}
      iex> Metastatic.AST.path(ast, fn {:variable, _, _} -> true; _ -> false end)
      nil
  """
  @spec path(meta_ast(), (meta_ast() -> as_boolean(term()))) :: [meta_ast()] | nil
  def path(ast, fun) when is_function(fun, 1) do
    do_path(ast, fun)
  end

  defp do_path({type, meta, _children} = node, fun) when is_atom(type) and is_list(meta) do
    if fun.(node) do
      [node]
    else
      children = child_nodes(node)

      Enum.find_value(children, fn child ->
        case do_path(child, fun) do
          nil -> nil
          path -> path ++ [node]
        end
      end)
    end
  end

  defp do_path(_other, _fun), do: nil

  # ----- Pipe Utilities -----

  @doc """
  Breaks a pipe chain into a flat list of `{ast, position}` tuples.

  Each tuple contains the piped expression and the argument position
  (0-indexed) where it was injected. For the leftmost expression (the
  initial value), position is `0`.

  Mirrors `Macro.unpipe/1`.

  ## Examples

      iex> inner_pipe = {:pipe, [operator: :|>], [
      ...>   {:variable, [], "x"},
      ...>   {:function_call, [name: "foo"], []}
      ...> ]}
      iex> outer_pipe = {:pipe, [operator: :|>], [
      ...>   inner_pipe,
      ...>   {:function_call, [name: "bar"], []}
      ...> ]}
      iex> Metastatic.AST.unpipe(outer_pipe)
      ...>   |> Enum.map(fn {node, pos} -> {Metastatic.AST.type(node), pos} end)
      [variable: 0, function_call: 0, function_call: 0]
  """
  @spec unpipe(meta_ast()) :: [{meta_ast(), non_neg_integer()}]
  def unpipe({:pipe, _meta, [left, right]}) do
    unpipe(left) ++ [{right, 0}]
  end

  def unpipe(other) do
    [{other, 0}]
  end

  @doc """
  Pipes `expr` into the `call_args` at the given `position`.

  Inserts `expr` as an argument into a function call node at the
  specified 0-indexed position. If `call_args` is a `:function_call`
  node, the expression is injected into its argument list.

  Mirrors `Macro.pipe/3`.

  ## Examples

      iex> expr = {:variable, [], "x"}
      iex> call = {:function_call, [name: "foo"], [{:literal, [subtype: :integer], 1}]}
      iex> Metastatic.AST.pipe_into(expr, call, 0)
      {:function_call, [name: "foo"], [{:variable, [], "x"}, {:literal, [subtype: :integer], 1}]}
  """
  @spec pipe_into(meta_ast(), meta_ast(), non_neg_integer()) :: meta_ast()
  def pipe_into(expr, {:function_call, meta, args}, position) when is_list(args) do
    {before, after_} = Enum.split(args, position)
    {:function_call, meta, before ++ [expr | after_]}
  end

  # ----- Call Decomposition -----

  @doc """
  Decomposes a function call into its name and argument list.

  Returns `{name, args}` for `:function_call` nodes, or `:error` for
  any other node type.

  For dotted calls like `"Repo.get"`, returns the full dotted name as
  a string. Use `String.split(name, ".")` to separate receiver and method.

  Mirrors `Macro.decompose_call/1`.

  ## Examples

      iex> call = {:function_call, [name: "add"], [{:variable, [], "x"}, {:variable, [], "y"}]}
      iex> Metastatic.AST.decompose_call(call)
      {"add", [{:variable, [], "x"}, {:variable, [], "y"}]}

      iex> Metastatic.AST.decompose_call({:literal, [subtype: :integer], 42})
      :error
  """
  @spec decompose_call(meta_ast()) :: {String.t(), [meta_ast()]} | :error
  def decompose_call({:function_call, meta, args}) when is_list(meta) and is_list(args) do
    {Keyword.get(meta, :name, ""), args}
  end

  def decompose_call(_), do: :error

  # ----- String Representation -----

  @doc """
  Converts a MetaAST node to a human-readable string representation.

  Produces a compact notation that conveys the structure without
  reproducing full Elixir tuple syntax. Useful for debugging and
  logging.

  Mirrors `Macro.to_string/1`.

  ## Examples

      iex> Metastatic.AST.to_string({:literal, [subtype: :integer], 42})
      "42"

      iex> Metastatic.AST.to_string({:variable, [], "x"})
      "x"

      iex> ast = {:binary_op, [category: :arithmetic, operator: :+],
      ...>   [{:variable, [], "x"}, {:literal, [subtype: :integer], 5}]}
      iex> Metastatic.AST.to_string(ast)
      "x + 5"

      iex> ast = {:function_call, [name: "foo"], [{:variable, [], "x"}, {:literal, [subtype: :integer], 1}]}
      iex> Metastatic.AST.to_string(ast)
      "foo(x, 1)"

      iex> ast = {:list, [], [{:literal, [subtype: :integer], 1}, {:literal, [subtype: :integer], 2}]}
      iex> Metastatic.AST.to_string(ast)
      "[1, 2]"
  """
  @spec to_string(meta_ast()) :: String.t()
  def to_string(ast) do
    do_to_string(ast)
  end

  defp do_to_string({:literal, meta, value}) do
    case Keyword.get(meta, :subtype) do
      :string -> "\"#{value}\""
      :symbol -> ":#{value}"
      :null -> "nil"
      :boolean -> Kernel.to_string(value)
      :regex -> "~r/#{value}/"
      :bytes when is_list(value) -> "<<#{Enum.map_join(value, ", ", &do_to_string/1)}>>"
      _ -> Kernel.to_string(value)
    end
  end

  defp do_to_string({:bin_segment, meta, [value]}) do
    specifiers =
      [
        Keyword.get(meta, :type),
        Keyword.get(meta, :signedness),
        Keyword.get(meta, :endianness)
      ]
      |> Enum.filter(& &1)
      |> Enum.map(&Kernel.to_string/1)

    specifiers =
      case Keyword.get(meta, :size) do
        nil -> specifiers
        size -> specifiers ++ ["size(#{do_to_string(size)})"]
      end

    specifiers =
      case Keyword.get(meta, :unit) do
        nil -> specifiers
        unit when is_integer(unit) -> specifiers ++ ["unit(#{unit})"]
      end

    case specifiers do
      [] -> do_to_string(value)
      chain -> "#{do_to_string(value)}::#{Enum.join(chain, "-")}"
    end
  end

  defp do_to_string({:comment, meta, text}) when is_binary(text) do
    case Keyword.get(meta, :comment_kind, :line) do
      :doc -> "## #{text}"
      :block -> "/* #{text} */"
      _ -> "# #{text}"
    end
  end

  defp do_to_string({:variable, _meta, name}), do: name

  defp do_to_string({:binary_op, meta, [left, right]}) do
    op = Keyword.get(meta, :operator, :op)
    "#{do_to_string(left)} #{op} #{do_to_string(right)}"
  end

  defp do_to_string({:unary_op, meta, [operand]}) do
    op = Keyword.get(meta, :operator, :op)
    "#{op}#{do_to_string(operand)}"
  end

  defp do_to_string({:function_call, meta, args}) do
    name = Keyword.get(meta, :name, "?")
    args_str = Enum.map_join(args, ", ", &do_to_string/1)
    "#{name}(#{args_str})"
  end

  defp do_to_string({:list, _meta, elements}) do
    inner = Enum.map_join(elements, ", ", &do_to_string/1)
    "[#{inner}]"
  end

  defp do_to_string({:tuple, _meta, elements}) do
    inner = Enum.map_join(elements, ", ", &do_to_string/1)
    "{#{inner}}"
  end

  defp do_to_string({:map, _meta, pairs}) do
    inner = Enum.map_join(pairs, ", ", &do_to_string/1)
    "%{#{inner}}"
  end

  defp do_to_string({:pair, _meta, [key, value]}) do
    "#{do_to_string(key)} => #{do_to_string(value)}"
  end

  defp do_to_string({:assignment, _meta, [target, value]}) do
    "#{do_to_string(target)} = #{do_to_string(value)}"
  end

  defp do_to_string({:block, _meta, statements}) do
    Enum.map_join(statements, "\n", &do_to_string/1)
  end

  defp do_to_string({:conditional, _meta, [condition, then_branch, nil]}) do
    "if #{do_to_string(condition)} do #{do_to_string(then_branch)} end"
  end

  defp do_to_string({:conditional, _meta, [condition, then_branch, else_branch]}) do
    "if #{do_to_string(condition)} do #{do_to_string(then_branch)} else #{do_to_string(else_branch)} end"
  end

  defp do_to_string({:pipe, _meta, [left, right]}) do
    "#{do_to_string(left)} |> #{do_to_string(right)}"
  end

  defp do_to_string({:container, meta, body}) do
    name = Keyword.get(meta, :name, "?")
    ct = Keyword.get(meta, :container_type, :module)
    inner = Enum.map_join(body, "; ", &do_to_string/1)
    "#{ct} #{name} do #{inner} end"
  end

  defp do_to_string({:function_def, meta, body}) do
    name = Keyword.get(meta, :name, "?")
    params = Keyword.get(meta, :params, [])
    params_str = Enum.map_join(params, ", ", &do_to_string/1)
    body_str = Enum.map_join(body, "; ", &do_to_string/1)
    "def #{name}(#{params_str}) do #{body_str} end"
  end

  defp do_to_string({:param, _meta, name}), do: name

  defp do_to_string({:lambda, meta, body}) do
    params = Keyword.get(meta, :params, [])
    params_str = Enum.map_join(params, ", ", &do_to_string/1)
    body_str = Enum.map_join(body, "; ", &do_to_string/1)
    "fn #{params_str} -> #{body_str} end"
  end

  defp do_to_string({:early_return, _meta, []}), do: "return"
  defp do_to_string({:early_return, _meta, [value]}), do: "return #{do_to_string(value)}"

  defp do_to_string({:attribute_access, meta, [receiver]}) do
    attr = Keyword.get(meta, :attribute, "?")
    "#{do_to_string(receiver)}.#{attr}"
  end

  defp do_to_string({:range, _meta, [start, stop]}) do
    "#{do_to_string(start)}..#{do_to_string(stop)}"
  end

  defp do_to_string({:import, meta, []}) do
    source = Keyword.get(meta, :source, "?")
    "import #{source}"
  end

  defp do_to_string({:string_interpolation, _meta, parts}) do
    inner =
      Enum.map_join(parts, fn
        {:literal, meta, value} ->
          if Keyword.get(meta, :subtype) == :string,
            do: value,
            else: "\#{#{do_to_string({:literal, meta, value})}}"

        other ->
          "\#{#{do_to_string(other)}}"
      end)

    "\"#{inner}\""
  end

  # Fallback for any node type not specifically handled
  defp do_to_string({type, _meta, children}) when is_atom(type) and is_list(children) do
    inner = Enum.map_join(children, ", ", &do_to_string/1)
    "#{type}(#{inner})"
  end

  defp do_to_string({type, _meta, value}) when is_atom(type) do
    "#{type}(#{inspect(value)})"
  end

  defp do_to_string(other), do: inspect(other)

  # ----- Predicates -----

  @doc """
  Returns `true` if the given MetaAST represents a literal value.

  A node is considered literal if it is a `:literal` node, or a composite
  node (`:list`, `:tuple`, `:map`, `:pair`) whose children are all literals.

  Mirrors `Macro.quoted_literal?/1`.

  ## Examples

      iex> Metastatic.AST.literal?({:literal, [subtype: :integer], 42})
      true

      iex> Metastatic.AST.literal?({:list, [], [{:literal, [subtype: :integer], 1}, {:literal, [subtype: :integer], 2}]})
      true

      iex> Metastatic.AST.literal?({:variable, [], "x"})
      false

      iex> Metastatic.AST.literal?({:list, [], [{:variable, [], "x"}]})
      false
  """
  @spec literal?(meta_ast()) :: boolean()
  def literal?({:literal, _meta, _value}), do: true

  def literal?({type, _meta, children})
      when type in [:list, :tuple, :map] and is_list(children) do
    Enum.all?(children, &literal?/1)
  end

  def literal?({:pair, _meta, [key, value]}), do: literal?(key) and literal?(value)
  def literal?(_), do: false

  @doc """
  Returns `true` if the node is a binary or unary operator.

  ## Examples

      iex> Metastatic.AST.operator?({:binary_op, [category: :arithmetic, operator: :+], [{:variable, [], "x"}, {:literal, [subtype: :integer], 1}]})
      true

      iex> Metastatic.AST.operator?({:unary_op, [category: :arithmetic, operator: :-], [{:variable, [], "x"}]})
      true

      iex> Metastatic.AST.operator?({:literal, [subtype: :integer], 42})
      false
  """
  @spec operator?(meta_ast()) :: boolean()
  def operator?({type, _meta, _children}) when type in [:binary_op, :unary_op], do: true
  def operator?(_), do: false

  # ----- Validation -----

  @doc """
  Validates that the given term is a valid MetaAST node.

  Returns `:ok` if valid, or `{:error, reason}` with a description of
  the first encountered problem. Unlike `conforms?/1` which returns a
  boolean, this provides diagnostic information.

  Mirrors `Macro.validate/1`.

  ## Examples

      iex> Metastatic.AST.validate({:literal, [subtype: :integer], 42})
      :ok

      iex> Metastatic.AST.validate({:literal, [subtype: :integer], "not_an_int"})
      {:error, {:invalid_node, {:literal, [subtype: :integer], "not_an_int"}}}

      iex> Metastatic.AST.validate("not an ast")
      {:error, {:not_an_ast_node, "not an ast"}}
  """
  @spec validate(term()) :: :ok | {:error, term()}
  def validate(ast) do
    do_validate(ast)
  end

  defp do_validate({type, meta, _children} = node) when is_atom(type) and is_list(meta) do
    if conforms?(node) do
      :ok
    else
      # Try to find the specific child that fails
      case find_invalid_child(node) do
        nil -> {:error, {:invalid_node, node}}
        child_error -> child_error
      end
    end
  end

  defp do_validate(other), do: {:error, {:not_an_ast_node, other}}

  defp find_invalid_child({type, _meta, children})
       when type in [:literal, :variable] do
    _ = children
    nil
  end

  defp find_invalid_child({_type, _meta, children}) when is_list(children) do
    Enum.find_value(children, fn child ->
      case child do
        {t, m, _} when is_atom(t) and is_list(m) ->
          if conforms?(child), do: nil, else: {:error, {:invalid_node, child}}

        _ ->
          nil
      end
    end)
  end

  defp find_invalid_child(_), do: nil

  # ----- Unique Variables -----

  @doc """
  Generates a unique variable MetaAST node.

  Each call produces a variable with a unique name based on the given
  prefix and a monotonically increasing counter. Useful for code
  transformations that need to introduce fresh bindings.

  Mirrors `Macro.unique_var/2`.

  ## Examples

      iex> {:variable, _, name1} = Metastatic.AST.unique_var("tmp")
      iex> {:variable, _, name2} = Metastatic.AST.unique_var("tmp")
      iex> name1 != name2
      true

      iex> {:variable, _, name} = Metastatic.AST.unique_var("arg")
      iex> String.starts_with?(name, "arg_")
      true
  """
  @spec unique_var(String.t(), keyword()) :: meta_ast()
  def unique_var(prefix, meta \\ []) when is_binary(prefix) do
    counter = :erlang.unique_integer([:positive, :monotonic])
    {:variable, meta, "#{prefix}_#{counter}"}
  end
end
