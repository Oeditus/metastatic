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

  ## Layer Architecture (within M2)

  The three layers represent different granularities of meta-modeling:

  - **M2.1 (Core):** Universal concepts (ALL languages)
  - **M2.2 (Extended):** Common patterns (MOST languages)
  - **M2.3 (Native):** Language-specific escape hatches (embedded M1)

  ## Semantic Equivalence

  Different M1 models can be instances of the same M2 concept:

      # M2: Meta-model definition
      {:binary_op, :arithmetic, :+, left, right}

      # M1 instances (all equivalent at M2 level):
      Python:     BinOp(op=Add(), left=Name('x'), right=Num(5))
      JavaScript: BinaryExpression(operator: '+', left: Identifier('x'), right: Literal(5))
      Elixir:     {:+, [], [{:x, [], nil}, 5]}

  All three are INSTANCES of the same M2 concept, differing only in concrete syntax (M1).

  ## References

  - OMG Meta Object Facility (MOF) Specification
  - Eclipse Modeling Framework (EMF)
  - Abstract Syntax Theory
  """

  # ----- M2 Node Type Definition -----

  @typedoc """
  A MetaAST represents a programming language construct at the meta-level (M2).

  This is the union of all meta-types across the three layers.
  """
  # M2.1: Core layer - Universal programming concepts
  @type meta_ast ::
          literal()
          | variable()
          | binary_op()
          | unary_op()
          | function_call()
          | conditional()
          | early_return()
          | block()
          | assignment()
          | inline_match()
          # M2.2: Extended layer - Common patterns with variations
          | loop()
          | lambda()
          | collection_op()
          | pattern_match()
          | exception_handling()
          | async_operation()
          # M2.3: Native layer - M1 escape hatch
          | language_specific()

  # ----- M2.1: Core Layer - Universal Meta-Types -----
  # These represent concepts that exist in ALL programming languages

  @typedoc """
  M2 meta-type: Literal value.

  Represents constant values that appear in source code.

  ## M1 instances
  - Python: `ast.Constant`, `ast.Num`, `ast.Str`
  - JavaScript: `Literal`
  - Elixir: integer, string, atom literals

  ## Examples

      {:literal, :integer, 42}
      {:literal, :string, "hello"}
      {:literal, :boolean, true}
      {:literal, :null, nil}
  """
  @type literal :: {:literal, semantic_type(), value :: term()}

  @typedoc """
  Semantic type classification for literals.

  These categories exist across all languages, though syntax varies.
  """
  @type semantic_type ::
          :integer
          | :float
          | :string
          | :boolean
          | :null
          | :symbol
          | :regex
          | :collection

  @typedoc """
  M2 meta-type: Variable reference.

  Represents an identifier that refers to a value in scope.

  ## M1 instances
  - Python: `ast.Name`
  - JavaScript: `Identifier`
  - Elixir: `{:var, meta, context}`

  ## Examples

      {:variable, "x"}
      {:variable, "userName"}
  """
  @type variable :: {:variable, name :: String.t()}

  @typedoc """
  M2 meta-type: Binary operation.

  This is a meta-concept that abstracts over language-specific binary operations.

  ## M1 instances
  - Python: `ast.BinOp`
  - JavaScript: `BinaryExpression`
  - Elixir: `{:+, meta, [left, right]}`

  All three are INSTANCES of this M2 concept.

  ## Examples

      {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}}
      {:binary_op, :comparison, :>, {:variable, "age"}, {:literal, :integer, 18}}
      {:binary_op, :boolean, :and, condition1, condition2}
  """
  @type binary_op ::
          {:binary_op, :arithmetic | :comparison | :boolean, op :: atom(), left :: meta_ast(),
           right :: meta_ast()}

  @typedoc """
  M2 meta-type: Unary operation.

  Represents operations with a single operand.

  ## Examples

      {:unary_op, :arithmetic, :-, {:variable, "x"}}
      {:unary_op, :boolean, :not, {:variable, "flag"}}
  """
  @type unary_op ::
          {:unary_op, :arithmetic | :boolean, op :: atom(), operand :: meta_ast()}

  @typedoc """
  M2 meta-type: Function call.

  Represents invocation of a function or method.

  ## M1 instances
  - Python: `ast.Call`
  - JavaScript: `CallExpression`
  - Elixir: function application

  ## Examples

      {:function_call, "add", [{:variable, "x"}, {:variable, "y"}]}
      {:function_call, "max", [a, b]}
  """
  @type function_call :: {:function_call, name :: String.t(), args :: [meta_ast()]}

  @typedoc """
  M2 meta-type: Conditional expression.

  Represents if/else or ternary conditional logic.

  ## M1 instances
  - Python: `ast.If`, `ast.IfExp`
  - JavaScript: `IfStatement`, `ConditionalExpression`
  - Elixir: `if`, `cond`

  ## Examples

      {:conditional,
       {:binary_op, :comparison, :>, {:variable, "x"}, {:literal, :integer, 0}},
       {:literal, :string, "positive"},
       {:literal, :string, "non-positive"}}
  """
  @type conditional ::
          {:conditional, condition :: meta_ast(), then_branch :: meta_ast(),
           else_branch :: meta_ast() | nil}

  @typedoc """
  M2 meta-type: Early return.

  Represents control flow that exits early from a block.

  ## Examples

      {:early_return, {:variable, "result"}}
  """
  @type early_return :: {:early_return, value :: meta_ast()}

  @typedoc """
  M2 meta-type: Block of statements.

  Represents a sequence of statements/expressions.

  ## Examples

      {:block, [stmt1, stmt2, stmt3]}
  """
  @type block :: {:block, statements :: [meta_ast()]}

  @typedoc """
  M2 meta-type: Assignment (imperative binding/mutation).

  Represents imperative assignment in non-BEAM languages where `=` is a
  mutation/binding operator. The left side is a **target** that receives a value.

  ## Semantic Distinction from inline_match

  This type is for **imperative assignment** (Python, JavaScript, Ruby, etc.)
  where variables can be rebound/mutated. Contrast with `inline_match` which
  represents **declarative pattern matching** (Elixir, Erlang).

  ## M1 instances
  - Python: `ast.Assign`, `ast.AugAssign`, `ast.AnnAssign`
  - JavaScript: `AssignmentExpression`, `VariableDeclarator`
  - Ruby: assignment statements

  ## Examples

      # Simple assignment: x = 5
      {:assignment, {:variable, "x"}, {:literal, :integer, 5}}

      # Tuple unpacking: x, y = 1, 2
      {:assignment,
       {:tuple, [{:variable, "x"}, {:variable, "y"}]},
       {:tuple, [{:literal, :integer, 1}, {:literal, :integer, 2}]}}

      # Augmented assignment: x += 1 (desugared)
      {:assignment, {:variable, "x"},
       {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 1}}}
  """
  @type assignment :: {:assignment, target :: meta_ast(), value :: meta_ast()}

  @typedoc """
  M2 meta-type: Inline match (pattern matching).

  Represents inline pattern matching in BEAM languages where `=` is a
  **match operator**, not assignment. The left side is a **pattern** that
  must unify with the right side value.

  ## Semantic Distinction from assignment

  This type is for **declarative pattern matching** (Elixir, Erlang) where:
  - Elixir: Variables bind on first occurrence, rebind on subsequent use
  - Erlang: Single-assignment semantics, match fails if variable already bound to different value

  Contrast with `assignment` which represents imperative binding/mutation.

  ## M1 instances
  - Elixir: `=` operator in match context
  - Erlang: `=` operator (single-assignment)

  ## Examples

      # Simple match: x = 5 (Elixir/Erlang)
      {:inline_match, {:variable, "x"}, {:literal, :integer, 5}}

      # Tuple destructuring: {x, y} = {1, 2}
      {:inline_match,
       {:tuple, [{:variable, "x"}, {:variable, "y"}]},
       {:tuple, [{:literal, :integer, 1}, {:literal, :integer, 2}]}}

      # List pattern: [head | tail] = list
      {:inline_match,
       {:cons_pattern, {:variable, "head"}, {:variable, "tail"}},
       {:variable, "list"}}

      # Pin operator (Elixir): ^x = 5
      {:inline_match,
       {:pin, {:variable, "x"}},
       {:literal, :integer, 5}}
  """
  @type inline_match :: {:inline_match, pattern :: meta_ast(), value :: meta_ast()}

  # ----- M2.2: Extended Layer - Common Meta-Patterns -----
  # These represent concepts that exist in MOST languages, with variations

  @typedoc """
  M2 meta-type: Loop construct.

  Represents iterative execution patterns.

  ## M1 instances
  - Python: `ast.For`, `ast.While`
  - JavaScript: `ForStatement`, `WhileStatement`
  - Elixir: `Enum.each/2` (functional iteration)

  ## Examples

      {:loop, :while,
       {:binary_op, :comparison, :>, {:variable, "x"}, {:literal, :integer, 0}},
       {:block, [{:variable, "x"}]}}
  """
  @type loop ::
          {:loop, :while, condition :: meta_ast(), body :: meta_ast()}
          | {:loop, :for | :for_each, item :: meta_ast(), collection :: meta_ast(),
             body :: meta_ast()}

  @typedoc """
  M2 meta-type: Lambda/anonymous function.

  Represents function literals.

  ## M1 instances
  - Python: `ast.Lambda`
  - JavaScript: `ArrowFunctionExpression`, `FunctionExpression`
  - Elixir: `fn` expressions

  ## Examples

      {:lambda, ["x", "y"], [], {:binary_op, :arithmetic, :+, {:variable, "x"}, {:variable, "y"}}}
  """
  @type lambda ::
          {:lambda, params :: [String.t()], captures :: [String.t()], body :: meta_ast()}

  @typedoc """
  M2 meta-type: Collection operations.

  These represent functional transformations that exist across languages:

  ## M1 instances
  - Python: list comprehensions, `map()`, `filter()`
  - JavaScript: `Array.prototype.map/filter/reduce`
  - Elixir: `Enum.map/2`, `Enum.filter/2`, `Enum.reduce/3`

  All are instances of the same M2 concept.

  ## Examples

      {:collection_op, :map,
       {:lambda, ["x"], [], {:binary_op, :arithmetic, :*, {:variable, "x"}, {:literal, :integer, 2}}},
       {:variable, "numbers"}}
  """
  @type collection_op ::
          {:collection_op, :map | :filter, fn_or_pred :: meta_ast(), collection :: meta_ast()}
          | {:collection_op, :reduce, fn_or_pred :: meta_ast(), collection :: meta_ast(),
             initial :: meta_ast()}

  @typedoc """
  M2 meta-type: Pattern matching.

  Represents switch/case/match constructs.

  ## M1 instances
  - Python: `ast.Match` (3.10+)
  - JavaScript: `SwitchStatement`
  - Elixir: `case`, pattern matching in function heads

  ## Examples

      {:pattern_match, {:variable, "value"},
       [
         {{:literal, :integer, 0}, {:literal, :string, "zero"}},
         {{:literal, :integer, 1}, {:literal, :string, "one"}},
         {:_, {:literal, :string, "other"}}
       ]}
  """
  @type pattern_match ::
          {:pattern_match, scrutinee :: meta_ast(),
           arms :: [{pattern :: meta_ast(), body :: meta_ast()}]}

  @typedoc """
  M2 meta-type: Exception handling.

  Represents try/catch/finally constructs.

  ## Examples

      {:exception_handling,
       {:block, [{:function_call, "risky", []}]},
       [{:error, {:variable, "e"}, {:function_call, "handle", [{:variable, "e"}]}}],
       {:function_call, "cleanup", []}}
  """
  @type exception_handling ::
          {:exception_handling, try_block :: meta_ast(),
           rescue_clauses :: [{exception :: atom(), var :: meta_ast(), body :: meta_ast()}],
           finally_block :: meta_ast() | nil}

  @typedoc """
  M2 meta-type: Asynchronous operation.

  Represents async/await, promises, futures.

  ## M1 instances
  - Python: `async`/`await` with asyncio
  - JavaScript: `async`/`await` with Promises
  - Elixir: `Task.async`/`Task.await`

  ## Examples

      {:async_operation, :await,
       {:function_call, "fetch_data", [{:literal, :string, "url"}]}}
  """
  @type async_operation :: {:async_operation, :await | :async, operation :: meta_ast()}

  # ----- M2.3: Native Layer - M1 Escape Hatch -----
  # When M1 cannot be lifted to M2, preserve as-is with semantic hints

  @typedoc """
  M2 escape hatch: Language-specific construct.

  When an M1 construct cannot be abstracted to M2, we preserve the M1 AST
  directly with semantic hints.

  This allows:
  1. Round-trip fidelity (M1 → M2 → M1)
  2. Partial analysis at M2 level (using semantic info)
  3. Language-specific transformations when needed

  ## Examples

      {:language_specific, :python,
       %{construct: :list_comprehension, data: "[x for x in range(10)]"}}
  """
  @type language_specific :: {:language_specific, language :: atom(), native_info :: map()}

  # ----- M2 Conformance Validation -----

  @doc """
  Validate that a term conforms to the M2 meta-model.

  This performs M1 → M2 conformance checking, ensuring that
  the structure is a valid MetaAST.

  ## Examples

      iex> Metastatic.AST.conforms?({:literal, :integer, 42})
      true

      iex> Metastatic.AST.conforms?({:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}})
      true

      iex> Metastatic.AST.conforms?({:invalid_node, "data"})
      false
  """
  @spec conforms?(term()) :: boolean()
  def conforms?(ast) do
    case ast do
      # M2.1: Core
      {:literal, type, _value}
      when type in [:integer, :float, :string, :boolean, :null, :symbol, :regex, :collection] ->
        true

      {:variable, name} when is_binary(name) ->
        true

      :_ ->
        true

      {:binary_op, category, _op, left, right}
      when category in [:arithmetic, :comparison, :boolean] ->
        conforms?(left) and conforms?(right)

      {:unary_op, category, _op, operand} when category in [:arithmetic, :boolean] ->
        conforms?(operand)

      {:function_call, name, args} when is_binary(name) and is_list(args) ->
        Enum.all?(args, &conforms?/1)

      {:conditional, condition, then_branch, else_branch} ->
        conforms?(condition) and conforms?(then_branch) and
          (is_nil(else_branch) or conforms?(else_branch))

      {:early_return, value} ->
        conforms?(value)

      {:block, statements} when is_list(statements) ->
        Enum.all?(statements, &conforms?/1)

      {:assignment, target, value} ->
        conforms?(target) and conforms?(value)

      {:inline_match, pattern, value} ->
        conforms?(pattern) and conforms?(value)

      # Tuple (used in patterns and destructuring)
      {:tuple, elements} when is_list(elements) ->
        Enum.all?(elements, &conforms?/1)

      # M2.2: Extended
      {:loop, :while, condition, body} ->
        conforms?(condition) and conforms?(body)

      {:loop, kind, _item, collection, body} when kind in [:for, :for_each] ->
        conforms?(collection) and conforms?(body)

      {:lambda, params, captures, body}
      when is_list(params) and is_list(captures) ->
        conforms?(body)

      {:collection_op, kind, fn_or_pred, collection} when kind in [:map, :filter] ->
        conforms?(fn_or_pred) and conforms?(collection)

      {:collection_op, kind, fn_or_pred, collection, initial} when kind == :reduce ->
        conforms?(fn_or_pred) and conforms?(collection) and conforms?(initial)

      {:pattern_match, scrutinee, arms} when is_list(arms) ->
        conforms?(scrutinee) and
          Enum.all?(arms, fn
            {pattern, body} -> conforms?(pattern) and conforms?(body)
            _other -> false
          end)

      {:exception_handling, try_block, rescue_clauses, finally_block}
      when is_list(rescue_clauses) ->
        conforms?(try_block) and
          Enum.all?(rescue_clauses, fn {_ex, var, body} -> conforms?(var) and conforms?(body) end) and
          (is_nil(finally_block) or conforms?(finally_block))

      {:async_operation, kind, operation} when kind in [:await, :async] ->
        conforms?(operation)

      # M2.3: Native
      {:language_specific, language, native_info}
      when is_atom(language) and is_map(native_info) ->
        true

      _ ->
        false
    end
  end

  # ----- Helper Functions -----

  @doc """
  Extract all variables referenced in an AST.

  Useful for analyzing dependencies and scope.

  ## Examples

      iex> ast = {:binary_op, :arithmetic, :+, {:variable, "x"}, {:variable, "y"}}
      iex> Metastatic.AST.variables(ast)
      MapSet.new(["x", "y"])
  """
  @spec variables(meta_ast()) :: MapSet.t(String.t())
  def variables(ast) do
    collect_variables(ast, MapSet.new())
  end

  defp collect_variables({:variable, name}, acc), do: MapSet.put(acc, name)

  defp collect_variables({:binary_op, _, _, left, right}, acc) do
    acc = collect_variables(left, acc)
    collect_variables(right, acc)
  end

  defp collect_variables({:unary_op, _, _, operand}, acc) do
    collect_variables(operand, acc)
  end

  defp collect_variables({:function_call, _, args}, acc) do
    Enum.reduce(args, acc, fn arg, a -> collect_variables(arg, a) end)
  end

  defp collect_variables({:conditional, condition, then_branch, else_branch}, acc) do
    acc = collect_variables(condition, acc)
    acc = collect_variables(then_branch, acc)
    if else_branch, do: collect_variables(else_branch, acc), else: acc
  end

  defp collect_variables({:block, statements}, acc) do
    Enum.reduce(statements, acc, fn stmt, a -> collect_variables(stmt, a) end)
  end

  defp collect_variables({:assignment, target, value}, acc) do
    acc = collect_variables(target, acc)
    collect_variables(value, acc)
  end

  defp collect_variables({:inline_match, pattern, value}, acc) do
    acc = collect_variables(pattern, acc)
    collect_variables(value, acc)
  end

  defp collect_variables({:tuple, elements}, acc) do
    Enum.reduce(elements, acc, fn el, a -> collect_variables(el, a) end)
  end

  defp collect_variables({:loop, :while, condition, body}, acc) do
    acc = collect_variables(condition, acc)
    collect_variables(body, acc)
  end

  defp collect_variables({:loop, _, item, collection, body}, acc) do
    acc = collect_variables(item, acc)
    acc = collect_variables(collection, acc)
    collect_variables(body, acc)
  end

  defp collect_variables({:lambda, params, captures, body}, acc) do
    acc = Enum.reduce(params, acc, fn p, a -> MapSet.put(a, p) end)
    acc = Enum.reduce(captures, acc, fn c, a -> MapSet.put(a, c) end)
    collect_variables(body, acc)
  end

  defp collect_variables({:collection_op, _, fn_or_pred, collection}, acc) do
    acc = collect_variables(fn_or_pred, acc)
    collect_variables(collection, acc)
  end

  defp collect_variables({:collection_op, _, fn_or_pred, collection, initial}, acc) do
    acc = collect_variables(fn_or_pred, acc)
    acc = collect_variables(collection, acc)
    collect_variables(initial, acc)
  end

  defp collect_variables({:pattern_match, scrutinee, arms}, acc) do
    acc = collect_variables(scrutinee, acc)

    Enum.reduce(arms, acc, fn {pattern, body}, a ->
      a = collect_variables(pattern, a)
      collect_variables(body, a)
    end)
  end

  defp collect_variables({:exception_handling, try_block, rescue_clauses, finally_block}, acc) do
    acc = collect_variables(try_block, acc)

    acc =
      Enum.reduce(rescue_clauses, acc, fn {_, var, body}, a ->
        a = collect_variables(var, a)
        collect_variables(body, a)
      end)

    if finally_block, do: collect_variables(finally_block, acc), else: acc
  end

  defp collect_variables({:async_operation, _, operation}, acc) do
    collect_variables(operation, acc)
  end

  defp collect_variables({:early_return, value}, acc) do
    collect_variables(value, acc)
  end

  defp collect_variables(_, acc), do: acc
end
