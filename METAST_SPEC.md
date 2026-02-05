# MetaAST Format Specification

The MetaAST (Meta-level Abstract Syntax Tree) is a unified intermediate representation for programming language constructs, organized into three hierarchical layers.

## Uniform 3-Tuple Format

All MetaAST nodes use a uniform 3-element tuple structure:

```elixir
{type_atom, keyword_meta, children_or_value}
```

Where:
- `type_atom` - Node type (e.g., `:literal`, `:binary_op`, `:function_def`)
- `keyword_meta` - Keyword list with metadata (line, subtype, operator, etc.)
- `children_or_value` - Value for leaf nodes, list of children for composite nodes

## Meta-Modeling Hierarchy

MetaAST operates at the **M2 (meta-model)** level in a four-level hierarchy:

- **M3**: Elixir type system (`@type`, `@spec`) - defines what types CAN be
- **M2**: MetaAST (this specification) - defines what AST nodes CAN be
- **M1**: Language-specific ASTs (Python AST, JavaScript AST, Elixir AST) - what specific code IS
- **M0**: Runtime execution - what code DOES

Different M1 models (language ASTs) can be instances of the same M2 concept. For example:

```elixir
# M2 (meta-level representation, uniform 3-tuple format):
{:binary_op, [category: :arithmetic, operator: :+],
  [{:variable, [], "x"}, {:literal, [subtype: :integer], 5}]}

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
{:literal, [subtype: semantic_type], value}
```

**Semantic types**: `:integer`, `:float`, `:string`, `:boolean`, `:null`, `:symbol`, `:regex`

**Examples**:
```elixir
{:literal, [subtype: :integer], 42}
{:literal, [subtype: :string], "hello"}
{:literal, [subtype: :boolean], true}
{:literal, [subtype: :null], nil}
{:literal, [subtype: :symbol], :ok}
```

#### Variable
```elixir
{:variable, meta, name}
```
**Example**: `{:variable, [line: 1], "x"}`

#### List
```elixir
{:list, meta, elements_list}
```

Lists are ordered sequences of elements, fundamental data structures present in all programming languages.

**M1 instances**:
- Python: `ast.List`
- JavaScript: `Array`
- Elixir: list literal `[1, 2, 3]`
- Ruby: `Array`
- Erlang: list

**Examples**:
```elixir
{:list, [], []}
{:list, [], [{:literal, [subtype: :integer], 1}, {:literal, [subtype: :integer], 2}]}
{:list, [], [{:variable, [], "x"}, {:variable, [], "y"}]}
```

#### Map
```elixir
{:map, meta, pairs_list}
```

Maps are key-value mappings, fundamental data structures present in all modern programming languages. Each pair is a `:pair` node.

**M1 instances**:
- Python: `ast.Dict`
- JavaScript: `Object` literal
- Elixir: map `%{key => value}`
- Ruby: `Hash`
- Erlang: map

**Examples**:
```elixir
{:map, [], []}
{:map, [], [{:pair, [], [{:literal, [subtype: :string], "name"}, {:literal, [subtype: :string], "Alice"}]}]}
{:map, [], [{:pair, [], [{:variable, [], "key"}, {:variable, [], "value"}]}]}
```

#### Pair
```elixir
{:pair, meta, [key_ast, value_ast]}
```
Used within maps for key-value pairs.

#### Binary Operation
```elixir
{:binary_op, [category: category, operator: operator], [left_ast, right_ast]}
```

**Categories**: `:arithmetic`, `:comparison`, `:boolean`

**Examples**:
```elixir
{:binary_op, [category: :arithmetic, operator: :+], [{:variable, [], "x"}, {:literal, [subtype: :integer], 5}]}
{:binary_op, [category: :comparison, operator: :>], [{:variable, [], "age"}, {:literal, [subtype: :integer], 18}]}
{:binary_op, [category: :boolean, operator: :and], [condition1, condition2]}
```

#### Unary Operation
```elixir
{:unary_op, [category: category, operator: operator], [operand_ast]}
```

**Categories**: `:arithmetic`, `:boolean`

**Examples**:
```elixir
{:unary_op, [category: :arithmetic, operator: :-], [{:variable, [], "x"}]}
{:unary_op, [category: :boolean, operator: :not], [{:variable, [], "flag"}]}
```

#### Function Call
```elixir
{:function_call, [name: name], args_list}
```

**Example**: 
```elixir
{:function_call, [name: "add"], [{:variable, [], "x"}, {:variable, [], "y"}]}
```

#### Conditional
```elixir
{:conditional, meta, [condition_ast, then_ast, else_ast_or_nil]}
```

**Example**:
```elixir
{:conditional, [],
 [
   {:binary_op, [category: :comparison, operator: :>], [{:variable, [], "x"}, {:literal, [subtype: :integer], 0}]},
   {:literal, [subtype: :string], "positive"},
   {:literal, [subtype: :string], "non-positive"}
 ]}
```

#### Early Return
```elixir
{:early_return, meta, [value_ast]}
```

#### Block
```elixir
{:block, meta, statements_list}
```

#### Assignment
**For imperative languages (Python, JavaScript, Ruby)**

```elixir
{:assignment, meta, [target_ast, value_ast]}
```

Represents imperative binding/mutation where `=` is an assignment operator.

**Examples**:
```elixir
# x = 5
{:assignment, [], [{:variable, [], "x"}, {:literal, [subtype: :integer], 5}]}

# x, y = 1, 2 (tuple unpacking)
{:assignment, [],
 [
   {:tuple, [], [{:variable, [], "x"}, {:variable, [], "y"}]},
   {:tuple, [], [{:literal, [subtype: :integer], 1}, {:literal, [subtype: :integer], 2}]}
 ]}
```

#### Inline Match
**For declarative languages (Elixir, Erlang)**

```elixir
{:inline_match, meta, [pattern_ast, value_ast]}
```

Represents pattern matching where `=` is a match operator. The left side is a pattern that must unify with the right side.

**Examples**:
```elixir
# x = 5 (Elixir/Erlang)
{:inline_match, [], [{:variable, [], "x"}, {:literal, [subtype: :integer], 5}]}

# {x, y} = {1, 2}
{:inline_match, [],
 [
   {:tuple, [], [{:variable, [], "x"}, {:variable, [], "y"}]},
   {:tuple, [], [{:literal, [subtype: :integer], 1}, {:literal, [subtype: :integer], 2}]}
 ]}
```

#### Wildcard Pattern
```elixir
:_
```
Represents a catch-all pattern in pattern matching.

#### Tuple
```elixir
{:tuple, meta, elements_list}
```
Used in patterns and destructuring.

### M2.2: Extended Layer
**Common patterns present in MOST languages**

Normalized with optional hints to preserve language-specific nuances.

#### Loop
```elixir
# While loop
{:loop, [loop_type: :while], [condition_ast, body_ast]}

# For/foreach loop
{:loop, [loop_type: :for | :for_each], [iterator_ast, collection_ast, body_ast]}
```

**Examples**:
```elixir
{:loop, [loop_type: :while],
 [
   {:binary_op, [category: :comparison, operator: :>], [{:variable, [], "x"}, {:literal, [subtype: :integer], 0}]},
   {:block, [], [{:variable, [], "x"}]}
 ]}

{:loop, [loop_type: :for], [{:variable, [], "item"}, {:variable, [], "items"}, body_ast]}
```

#### Lambda
```elixir
{:lambda, [params: params_list, captures: captures_list], body_list}
```

Params are `:param` nodes (see M2.2s Structural Layer).

**Example**:
```elixir
{:lambda, [params: [{:param, [], "x"}, {:param, [], "y"}], captures: []],
 [{:binary_op, [category: :arithmetic, operator: :+], [{:variable, [], "x"}, {:variable, [], "y"}]}]}
```

#### Collection Operations
```elixir
# Map/filter
{:collection_op, [op_type: :map | :filter], [function_ast, collection_ast]}

# Reduce
{:collection_op, [op_type: :reduce], [function_ast, collection_ast, initial_ast]}
```

**Example**:
```elixir
{:collection_op, [op_type: :map],
 [
   {:lambda, [params: [{:param, [], "x"}], captures: []],
    [{:binary_op, [category: :arithmetic, operator: :*], [{:variable, [], "x"}, {:literal, [subtype: :integer], 2}]}]},
   {:variable, [], "numbers"}
 ]}
```

#### Pattern Match
```elixir
{:pattern_match, meta, [scrutinee_ast | arms_list]}
```

Where each arm is a `:match_arm` node.

**Example**:
```elixir
{:pattern_match, [], 
 [
   {:variable, [], "value"},
   {:match_arm, [pattern: {:literal, [subtype: :integer], 0}], [{:literal, [subtype: :string], "zero"}]},
   {:match_arm, [pattern: {:literal, [subtype: :integer], 1}], [{:literal, [subtype: :string], "one"}]},
   {:match_arm, [pattern: :_], [{:literal, [subtype: :string], "other"}]}
 ]}
```

#### Match Arm
```elixir
{:match_arm, [pattern: pattern_ast, guard: guard_ast_or_nil], body_list}
```

#### Exception Handling
```elixir
{:exception_handling, meta, [try_block_ast, handlers_list, finally_block_ast_or_nil]}
```

Where handlers are `:match_arm` nodes.

**Example**:
```elixir
{:exception_handling, [],
 [
   {:block, [], [{:function_call, [name: "risky"], []}]},
   [{:match_arm, [pattern: {:variable, [], "e"}],
     [{:function_call, [name: "handle"], [{:variable, [], "e"}]}]}],
   {:function_call, [name: "cleanup"], []}
 ]}
```

#### Async Operation
```elixir
{:async_operation, [op_type: :await | :async], [operation_ast]}
```

### M2.2s: Structural/Organizational Layer
**Top-level constructs for organizing code**

#### Container
**For modules, classes, namespaces**

```elixir
{:container, [container_type: type, name: name, ...], body_list}
```

**Container types**: `:module`, `:class`, `:namespace`

**Metadata fields** (in keyword list):
- `:container_type` - atom (`:module`, `:class`, `:namespace`)
- `:name` - string (container name)
- `:module` - string (M1 context: module name)
- `:language` - atom (`:python`, `:elixir`, `:ruby`, etc.)
- `:line` - integer (source location)

**Examples**:
```elixir
# Python class
{:container, [container_type: :class, name: "Calculator", language: :python, line: 1],
 [function_def1, function_def2]}

# Elixir module
{:container, [container_type: :module, name: "MyApp.Math", module: "MyApp.Math", language: :elixir, line: 1],
 [function_def1, function_def2]}
```

#### Function Definition
```elixir
{:function_def, [name: name, params: params_list, visibility: visibility, ...], body_list}
```

**Metadata fields** (in keyword list):
- `:name` - string (function name)
- `:params` - list of `:param` nodes
- `:visibility` - `:public`, `:private`, `:protected`
- `:arity` - integer
- `:guards` - guard clause as MetaAST (optional)
- `:function` - string (M1 context: function name)
- `:language` - atom (source language)
- `:line` - integer (source location)

**Examples**:
```elixir
# def add(x, y), do: x + y
{:function_def, [name: "add", params: [{:param, [], "x"}, {:param, [], "y"}], visibility: :public, arity: 2],
 [{:binary_op, [category: :arithmetic, operator: :+], [{:variable, [], "x"}, {:variable, [], "y"}]}]}

# def positive?(x) when x > 0
{:function_def, 
 [name: "positive?", params: [{:param, [], "x"}], visibility: :public, arity: 1,
  guards: {:binary_op, [category: :comparison, operator: :>], [{:variable, [], "x"}, {:literal, [subtype: :integer], 0}]}],
 [{:literal, [subtype: :boolean], true}]}
```

#### Parameter
**Function parameter with optional pattern/default**

```elixir
{:param, [pattern: pattern_ast_or_nil, default: default_ast_or_nil], name}
```

**Metadata fields** (in keyword list):
- `:pattern` - pattern MetaAST for destructuring (optional)
- `:default` - default value MetaAST (optional)

**Examples**:
```elixir
# Simple parameter
{:param, [], "x"}

# Parameter with default value
{:param, [default: {:literal, [subtype: :string], "World"}], "name"}

# Parameter with pattern (destructuring)
{:param, [pattern: {:tuple, [], [{:variable, [], "a"}, {:variable, [], "b"}]}], "pair"}
```

#### Attribute Access
```elixir
{:attribute_access, [attribute: attribute_name], [receiver_ast]}
```

**Examples**:
```elixir
# obj.value
{:attribute_access, [attribute: "value"], [{:variable, [], "obj"}]}

# user.address.street (chained)
{:attribute_access, [attribute: "street"],
 [{:attribute_access, [attribute: "address"], [{:variable, [], "user"}]}]}
```

#### Augmented Assignment
**Preserves compound operators in non-desugared form**

```elixir
{:augmented_assignment, [operator: operator], [target_ast, value_ast]}
```

**Examples**:
```elixir
# x += 5
{:augmented_assignment, [operator: :+], [{:variable, [], "x"}, {:literal, [subtype: :integer], 5}]}

# count *= 2
{:augmented_assignment, [operator: :*], [{:variable, [], "count"}, {:literal, [subtype: :integer], 2}]}
```

#### Property
**For getter/setter properties**

```elixir
{:property, [name: name], [getter_or_nil, setter_or_nil]}
```

**Metadata fields** (in keyword list):
- `:name` - property name

**Example**:
```elixir
# Ruby attr_reader (read-only)
{:property, [name: "name"],
 [{:function_def, [name: "name", params: [], visibility: :public], [{:variable, [], "@name"}]},
  nil]}
```

### M2.3: Native Layer
**Language-specific escape hatches**

When M1 constructs cannot be abstracted to M2, they're preserved directly with semantic hints.

```elixir
{:language_specific, [language: language_atom, hint: hint_atom], native_ast}
```

**Metadata fields** (in keyword list):
- `:language` - source language atom (`:python`, `:elixir`, etc.)
- `:hint` - semantic hint atom (`:comprehension`, `:pipe`, `:with`, etc.)

**Examples**:
```elixir
# Python list comprehension
{:language_specific, [language: :python, hint: :list_comprehension],
 %{construct: :list_comprehension, data: "[x for x in range(10)]"}}

# Elixir pipe operator
{:language_specific, [language: :elixir, hint: :pipe],
 {:|>, [], [left_ast, right_ast]}}

# Elixir with expression
{:language_specific, [language: :elixir, hint: :with],
 {:with, [], args}}
```

## Helper Functions

The `Metastatic.AST` module provides utility functions:

```elixir
# Conformance validation
AST.conforms?(ast)  # => true | false
AST.conforms?({:list, [], [{:variable, [], "x"}]})  # => true
AST.conforms?({:map, [], [{:pair, [], [{:literal, [subtype: :string], "k"}, {:variable, [], "v"}]}]})  # => true

# Variable extraction
AST.variables(ast)  # => MapSet.new(["x", "y"])
AST.variables({:list, [], [{:variable, [], "a"}, {:variable, [], "b"}]})  # => MapSet.new(["a", "b"])

# Type and metadata extraction
AST.type(ast)       # => :binary_op
AST.meta(ast)       # => [category: :arithmetic, operator: :+]
AST.children(ast)   # => [left, right]

# Location helpers
AST.location(ast)   # => %{line: 10, col: 5}
AST.with_location(ast, %{line: 10})  # => ast with location metadata

# Context helpers (M1 metadata)
AST.with_context(node, %{module: "MyApp", function: "create", arity: 2})
AST.node_module(node)      # => "MyApp"
AST.node_function(node)    # => "create"
AST.node_arity(node)       # => 2
AST.node_visibility(node)  # => :public
```

## Semantic Equivalence Principle

Different language ASTs that represent the same semantic concept produce identical MetaAST:

```
Python:     x + 5
JavaScript: x + 5
Elixir:     x + 5

All produce M2:
{:binary_op, [category: :arithmetic, operator: :+],
  [{:variable, [], "x"}, {:literal, [subtype: :integer], 5}]}
```

This enables:
- Universal transformations at M2 level
- Cross-language analysis tools
- Language-agnostic mutation testing
- Semantic equivalence validation

## Node Type Summary

### M2.1 Core Types
`:literal`, `:variable`, `:list`, `:map`, `:pair`, `:tuple`, `:binary_op`, `:unary_op`, `:function_call`, `:conditional`, `:early_return`, `:block`, `:assignment`, `:inline_match`

### M2.2 Extended Types
`:loop`, `:lambda`, `:collection_op`, `:pattern_match`, `:match_arm`, `:exception_handling`, `:async_operation`

### M2.2s Structural Types
`:container`, `:function_def`, `:param`, `:attribute_access`, `:augmented_assignment`, `:property`

### M2.3 Native Types
`:language_specific`
