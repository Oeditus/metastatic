# MetaAST Format Specification

The MetaAST (Meta-level Abstract Syntax Tree) is a unified intermediate representation for programming language constructs, organized into three hierarchical layers.

## Meta-Modeling Hierarchy

MetaAST operates at the **M2 (meta-model)** level in a four-level hierarchy:

- **M3**: Elixir type system (`@type`, `@spec`) - defines what types CAN be
- **M2**: MetaAST (this specification) - defines what AST nodes CAN be
- **M1**: Language-specific ASTs (Python AST, JavaScript AST, Elixir AST) - what specific code IS
- **M0**: Runtime execution - what code DOES

Different M1 models (language ASTs) can be instances of the same M2 concept. For example:

```elixir
# M2 (meta-level representation):
{:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}}

# M1 instances (language-specific):
Python:     BinOp(op=Add(), left=Name('x'), right=Num(5))
JavaScript: BinaryExpression(operator: '+', left: Identifier('x'), right: Literal(5))
Elixir:     {:+, [], [{:x, [], nil}, 5]}
```

All three M1 representations map to the identical M2 MetaAST, enabling cross-language semantic equivalence.

## Three-Layer Architecture

### M2.1: Core Layer
**Universal concepts present in ALL languages**

Always normalized to common representation without hints.

#### Literal
```elixir
{:literal, semantic_type, value}
```

**Semantic types**: `:integer`, `:float`, `:string`, `:boolean`, `:null`, `:symbol`, `:regex`, `:collection`

**Examples**:
```elixir
{:literal, :integer, 42}
{:literal, :string, "hello"}
{:literal, :boolean, true}
{:literal, :null, nil}
```

#### Variable
```elixir
{:variable, name}
```
**Example**: `{:variable, "x"}`

#### Binary Operation
```elixir
{:binary_op, category, operator, left_ast, right_ast}
```

**Categories**: `:arithmetic`, `:comparison`, `:boolean`

**Examples**:
```elixir
{:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}}
{:binary_op, :comparison, :>, {:variable, "age"}, {:literal, :integer, 18}}
{:binary_op, :boolean, :and, condition1, condition2}
```

#### Unary Operation
```elixir
{:unary_op, category, operator, operand_ast}
```

**Categories**: `:arithmetic`, `:boolean`

**Examples**:
```elixir
{:unary_op, :arithmetic, :-, {:variable, "x"}}
{:unary_op, :boolean, :not, {:variable, "flag"}}
```

#### Function Call
```elixir
{:function_call, name, args_list}
```

**Example**: 
```elixir
{:function_call, "add", [{:variable, "x"}, {:variable, "y"}]}
```

#### Conditional
```elixir
{:conditional, condition_ast, then_ast, else_ast_or_nil}
```

**Example**:
```elixir
{:conditional,
 {:binary_op, :comparison, :>, {:variable, "x"}, {:literal, :integer, 0}},
 {:literal, :string, "positive"},
 {:literal, :string, "non-positive"}}
```

#### Early Return
```elixir
{:early_return, value_ast}
```

#### Block
```elixir
{:block, statements_list}
```

#### Assignment
**For imperative languages (Python, JavaScript, Ruby)**

```elixir
{:assignment, target_ast, value_ast}
```

Represents imperative binding/mutation where `=` is an assignment operator.

**Examples**:
```elixir
# x = 5
{:assignment, {:variable, "x"}, {:literal, :integer, 5}}

# x, y = 1, 2 (tuple unpacking)
{:assignment,
 {:tuple, [{:variable, "x"}, {:variable, "y"}]},
 {:tuple, [{:literal, :integer, 1}, {:literal, :integer, 2}]}}
```

#### Inline Match
**For declarative languages (Elixir, Erlang)**

```elixir
{:inline_match, pattern_ast, value_ast}
```

Represents pattern matching where `=` is a match operator. The left side is a pattern that must unify with the right side.

**Examples**:
```elixir
# x = 5 (Elixir/Erlang)
{:inline_match, {:variable, "x"}, {:literal, :integer, 5}}

# {x, y} = {1, 2}
{:inline_match,
 {:tuple, [{:variable, "x"}, {:variable, "y"}]},
 {:tuple, [{:literal, :integer, 1}, {:literal, :integer, 2}]}}

# [head | tail] = list
{:inline_match,
 {:cons_pattern, {:variable, "head"}, {:variable, "tail"}},
 {:variable, "list"}}
```

#### Wildcard Pattern
```elixir
:_
```
Represents a catch-all pattern in pattern matching.

#### Tuple
```elixir
{:tuple, elements_list}
```
Used in patterns and destructuring.

### M2.2: Extended Layer
**Common patterns present in MOST languages**

Normalized with optional hints to preserve language-specific nuances.

#### Loop
```elixir
# While loop (4-tuple)
{:loop, :while, condition_ast, body_ast}

# For/foreach loop (5-tuple)
{:loop, :for | :for_each, iterator_ast, collection_ast, body_ast}
```

**Examples**:
```elixir
{:loop, :while,
 {:binary_op, :comparison, :>, {:variable, "x"}, {:literal, :integer, 0}},
 {:block, [{:variable, "x"}]}}

{:loop, :for, {:variable, "item"}, {:variable, "items"}, body_ast}
```

#### Lambda
```elixir
{:lambda, params_list, captures_list, body_ast}
```

**Example**:
```elixir
{:lambda, ["x", "y"], [], 
 {:binary_op, :arithmetic, :+, {:variable, "x"}, {:variable, "y"}}}
```

#### Collection Operations
```elixir
# Map/filter (4-tuple)
{:collection_op, :map | :filter, function_ast, collection_ast}

# Reduce (5-tuple)
{:collection_op, :reduce, function_ast, collection_ast, initial_ast}
```

**Example**:
```elixir
{:collection_op, :map,
 {:lambda, ["x"], [], {:binary_op, :arithmetic, :*, {:variable, "x"}, {:literal, :integer, 2}}},
 {:variable, "numbers"}}
```

#### Pattern Match
```elixir
{:pattern_match, scrutinee_ast, arms_list}
```

Where each arm is `{pattern_ast, body_ast}`.

**Example**:
```elixir
{:pattern_match, {:variable, "value"},
 [
   {{:literal, :integer, 0}, {:literal, :string, "zero"}},
   {{:literal, :integer, 1}, {:literal, :string, "one"}},
   {:_, {:literal, :string, "other"}}
 ]}
```

#### Exception Handling
```elixir
{:exception_handling, try_block_ast, rescue_clauses_list, finally_block_ast_or_nil}
```

Where each rescue clause is `{exception_atom, var_ast, body_ast}`.

#### Async Operation
```elixir
{:async_operation, :await | :async, operation_ast}
```

### M2.2s: Structural/Organizational Layer
**Top-level constructs for organizing code**

#### Container
**For modules, classes, namespaces**

```elixir
{:container, container_type, name, metadata, members_list}
```

**Container types**: `:module`, `:class`, `:namespace`

**Metadata fields**:
- `:source_language` - atom (`:python`, `:elixir`, `:ruby`, etc.)
- `:has_state` - boolean (mutable state management)
- `:visibility` - `%{public: [{name, arity}], private: [...], protected: [...]}`
- `:superclass` - string (direct superclass name or nil)
- `:organizational_model` - `:oop` or `:fp`
- `:original_ast` - M1 AST for round-trip fidelity
- `:decorators` - list of decorator MetaAST nodes
- `:type_params` - list of generic type parameters
- `:module_attributes` - module-level attributes
- `:constructor` - constructor function reference
- `:is_nested` - boolean

**Examples**:
```elixir
# Python class
{:container, :class, "Calculator",
 %{source_language: :python,
   has_state: true,
   visibility: %{public: [{"add", 2}], private: [{"_validate", 1}]},
   superclass: "BaseCalculator",
   organizational_model: :oop},
 [function_def1, function_def2]}

# Elixir module
{:container, :module, "MyApp.Math",
 %{source_language: :elixir,
   has_state: false,
   organizational_model: :fp},
 [function_def1, function_def2]}
```

#### Function Definition
```elixir
{:function_def, visibility, name, params_list, metadata, body_ast}
```

**Visibility**: `:public`, `:private`, `:protected`

**Parameter types**:
- Simple: `"x"` (string)
- Pattern: `{:pattern, meta_ast}`
- Default: `{:default, "name", default_value_ast}`

**Metadata fields**:
- `:guards` - guard clause as MetaAST
- `:arity` - integer
- `:return_type` - type annotation
- `:decorators` - list of decorator nodes
- `:is_async` - boolean
- `:is_static` - boolean
- `:is_abstract` - boolean
- `:specs` - function specifications
- `:doc` - documentation string
- `:original_ast` - M1 AST

**Examples**:
```elixir
# def add(x, y), do: x + y
{:function_def, :public, "add", ["x", "y"],
 %{arity: 2},
 {:binary_op, :arithmetic, :+, {:variable, "x"}, {:variable, "y"}}}

# def positive?(x) when x > 0
{:function_def, :public, "positive?", ["x"],
 %{arity: 1, guards: {:binary_op, :comparison, :>, {:variable, "x"}, {:literal, :integer, 0}}},
 {:literal, :boolean, true}}

# With default parameter
{:function_def, :public, "greet", [{:default, "name", {:literal, :string, "World"}}],
 %{arity: 1},
 {:function_call, "puts", [{:literal, :string, "Hello"}]}}
```

#### Attribute Access
```elixir
{:attribute_access, receiver_ast, attribute_name}
```

**Examples**:
```elixir
# obj.value
{:attribute_access, {:variable, "obj"}, "value"}

# user.address.street (chained)
{:attribute_access,
 {:attribute_access, {:variable, "user"}, "address"},
 "street"}
```

#### Augmented Assignment
**Preserves compound operators in non-desugared form**

```elixir
{:augmented_assignment, operator, target_ast, value_ast}
```

**Examples**:
```elixir
# x += 5
{:augmented_assignment, :+, {:variable, "x"}, {:literal, :integer, 5}}

# count *= 2
{:augmented_assignment, :*, {:variable, "count"}, {:literal, :integer, 2}}
```

#### Property
**For getter/setter properties**

```elixir
{:property, name, getter_function_def_or_nil, setter_function_def_or_nil, metadata}
```

**Metadata fields**:
- `:original_ast` - M1 AST
- `:is_read_only` - boolean
- `:is_write_only` - boolean
- `:backing_field` - backing field name

**Example**:
```elixir
# Ruby attr_reader (read-only)
{:property, "name",
 {:function_def, :public, "name", [], %{}, {:variable, "@name"}},
 nil,
 %{is_read_only: true}}
```

### M2.3: Native Layer
**Language-specific escape hatches**

When M1 constructs cannot be abstracted to M2, they're preserved directly with semantic hints.

```elixir
# 5-tuple with embedded metadata (preferred)
{:language_specific, language_atom, native_info_map, hint_atom, metadata_map}

# 4-tuple without embedded metadata
{:language_specific, language_atom, native_info_map, hint_atom}

# 3-tuple (legacy format)
{:language_specific, language_atom, native_info_map}
```

**Example**:
```elixir
{:language_specific, :python,
 %{construct: :list_comprehension, data: "[x for x in range(10)]"},
 :functional_transform,
 %{}}
```

## Helper Functions

The `Metastatic.AST` module provides utility functions:

```elixir
# Conformance validation
AST.conforms?(ast)  # => true | false

# Variable extraction
AST.variables(ast)  # => MapSet.new(["x", "y"])

# Container queries
AST.container_name(container_ast)  # => "MyApp.Math"
AST.has_state?(container_ast)      # => true | false

# Function queries
AST.function_name(function_def_ast)       # => "add"
AST.function_visibility(function_def_ast) # => :public
```

## Semantic Equivalence Principle

Different language ASTs that represent the same semantic concept produce identical MetaAST:

```
Python:     x + 5      →  M2: {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}}
JavaScript: x + 5      →  M2: {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}}
Elixir:     x + 5      →  M2: {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}}
```

This enables:
- Universal transformations at M2 level
- Cross-language analysis tools
- Language-agnostic mutation testing
- Semantic equivalence validation
