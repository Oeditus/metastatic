defmodule Metastatic.Adapters.Java.ToMeta do
  @moduledoc """
  Transform Java AST (M1) to MetaAST (M2).

  Implements the abstraction function α_Java that lifts the JDK tree API's
  representation (`com.sun.source.tree`, serialised to JSON by
  `priv/parsers/java/parser.java`) to the meta-level representation.

  ## Transformation Strategy

  Every node carries a `"kind"` naming its `Tree.Kind`; this module pattern
  matches on that field and emits MetaAST 3-tuples.

  ### M2.1 (Core Layer)

  - Literals: `INT_LITERAL`, `STRING_LITERAL`, ... -> `{:literal, ...}`
  - Variables: `IDENTIFIER` -> `{:variable, ...}`
  - Operators: `BINARY`, `UNARY`, `ASSIGNMENT` -> `{:binary_op, ...}`, ...
  - Calls: `METHOD_INVOCATION`, `NEW_CLASS` -> `{:function_call, ...}`
  - Control flow: `IF`, `RETURN`, `BLOCK` -> `{:conditional, ...}`, ...

  ### M2.2 (Extended Layer)

  - Loops: `FOR_LOOP`, `ENHANCED_FOR_LOOP`, `WHILE_LOOP`, `DO_WHILE_LOOP`
  - Lambdas: `LAMBDA_EXPRESSION`
  - Exceptions: `TRY`, `CATCH`, `THROW` -> `{:exception_handling, ...}`, ...

  ### M2.2s (Structural Layer)

  - Containers: `CLASS`, `INTERFACE`, `ENUM`, `RECORD` -> `{:container, ...}`
  - Functions: `METHOD` -> `{:function_def, ...}`
  - Imports: `IMPORT` -> `{:import, ...}`

  ### M2.3 (Native Layer)

  Constructs with no portable analogue (`synchronized`, `assert`, generics
  bounds, annotations on types, ...) are kept verbatim in
  `{:language_specific, [language: :java, ...], node}` so that `FromMeta` can
  restore them and nothing is silently lost.

  Java is a statement-oriented language, so the parser is *context sensitive*:
  an expression in statement position becomes an `EXPRESSION_STATEMENT` node,
  which is unwrapped. Method bodies are always `{:block, [], statements}` so
  that `MetaASTExtractor` finds the same shape it finds in other languages.
  """

  alias Metastatic.AST

  # Tree.Kind values that carry a literal value.
  @literal_kinds ~w(INT_LITERAL LONG_LITERAL FLOAT_LITERAL DOUBLE_LITERAL
                    BOOLEAN_LITERAL CHAR_LITERAL STRING_LITERAL NULL_LITERAL)

  @doc """
  Transform a Java AST (as produced by `Metastatic.Adapters.Java.parse/1`) to
  MetaAST.

  Returns `{:ok, meta_ast, metadata}` on success or `{:error, reason}`.

  ## Examples

      iex> transform(%{"kind" => "INT_LITERAL", "value" => 42})
      {:ok, {:literal, [subtype: :integer], 42}, %{}}

      iex> transform(%{"kind" => "IDENTIFIER", "name" => "x"})
      {:ok, {:variable, [scope: :local], "x"}, %{}}
  """
  @spec transform(map() | nil) :: {:ok, term(), map()} | {:error, String.t()}
  def transform(nil), do: {:ok, nil, %{}}

  # ----- Compilation unit -----

  def transform(%{"kind" => "COMPILATION_UNIT"} = node) do
    types = Map.get(node, "types", [])

    with {:ok, package_ast} <- transform_package(Map.get(node, "package")),
         {:ok, imports} <- transform_list(Map.get(node, "imports", [])),
         {:ok, type_asts} <- transform_list(types) do
      statements = Enum.reject([package_ast | imports] ++ type_asts, &is_nil/1)

      ast =
        case statements do
          [] -> {:block, [scope: :module], []}
          [single] -> single
          multiple -> {:block, [scope: :module], multiple}
        end

      {:ok, add_location(ast, node), %{}}
    end
  end

  def transform(node) when is_list(node) do
    with {:ok, statements} <- transform_list(node) do
      {:ok, statements, %{}}
    end
  end

  # ----- Imports and package -----

  def transform(%{"kind" => "IMPORT"} = node) do
    source = qualified_name(Map.get(node, "qualified"))
    static? = Map.get(node, "static", false)

    meta =
      [source: source, import_type: :java_import, language: :java] ++
        if(static?, do: [static: true], else: []) ++ location_meta(node)

    {:ok, {:import, meta, []}, %{}}
  end

  # ----- Containers: class / interface / enum / record -----

  def transform(%{"kind" => kind} = node) when kind in ["CLASS", "INTERFACE", "ENUM", "RECORD"] do
    name = Map.get(node, "name", "anonymous")

    with {:ok, members} <- transform_list(Map.get(node, "members", [])) do
      meta =
        [
          container_type: container_type(kind),
          name: name,
          module: name,
          language: :java,
          modifiers: Map.get(node, "modifiers", [])
        ] ++ extends_meta(node) ++ implements_meta(node) ++ location_meta(node)

      {:ok, {:container, meta, members}, %{}}
    end
  end

  # ----- Methods and constructors -----

  def transform(%{"kind" => "METHOD"} = node) do
    name = Map.get(node, "name", "anonymous")
    params = Map.get(node, "params", [])
    modifiers = Map.get(node, "modifiers", [])

    with {:ok, param_asts} <- transform_list(params),
         {:ok, body} <- transform_method_body(node) do
      meta =
        [
          name: name,
          params: param_asts,
          arity: length(param_asts),
          visibility: visibility(modifiers),
          language: :java,
          modifiers: modifiers,
          static: "static" in modifiers,
          constructor?: Map.get(node, "returnType") == nil
        ] ++ return_type_meta(node) ++ location_meta(node)

      {:ok, {:function_def, meta, body}, %{}}
    end
  end

  def transform(%{"kind" => "VARIABLE"} = node) do
    name = Map.get(node, "name", "_")
    modifiers = Map.get(node, "modifiers", [])

    with {:ok, init_ast} <- transform_or_nil(Map.get(node, "init")) do
      target = {:variable, [scope: :local, declaration: true], name}

      meta =
        [
          operator: :=,
          kind: declaration_kind(modifiers),
          language: :java,
          modifiers: modifiers
        ] ++ type_meta(node) ++ location_meta(node)

      {:ok, add_location({:assignment, meta, [target, init_ast]}, node), %{}}
    end
  end

  # ----- Blocks and statements -----

  def transform(%{"kind" => "BLOCK"} = node) do
    with {:ok, statements} <- transform_list(Map.get(node, "statements", [])) do
      {:ok, add_location({:block, [], statements}, node), %{}}
    end
  end

  def transform(%{"kind" => "EXPRESSION_STATEMENT", "expr" => expr}) do
    transform(expr)
  end

  def transform(%{"kind" => "RETURN"} = node) do
    with {:ok, value} <- transform_or_nil(Map.get(node, "expr")) do
      {:ok, add_location({:early_return, [kind: :return], [value]}, node), %{}}
    end
  end

  def transform(%{"kind" => "BREAK"} = node) do
    {:ok, add_location({:early_return, [kind: :break, label: Map.get(node, "label")], []}, node),
     %{}}
  end

  def transform(%{"kind" => "CONTINUE"} = node) do
    {:ok,
     add_location({:early_return, [kind: :continue, label: Map.get(node, "label")], []}, node),
     %{}}
  end

  def transform(%{"kind" => "EMPTY_STATEMENT"} = node) do
    {:ok, add_location({:block, [empty: true], []}, node), %{}}
  end

  # ----- Control flow -----

  def transform(%{"kind" => "IF"} = node) do
    with {:ok, cond_ast, _} <- transform(Map.get(node, "cond")),
         {:ok, then_ast, _} <- transform(Map.get(node, "then")),
         {:ok, else_ast} <- transform_or_nil(Map.get(node, "else")) do
      children = if else_ast, do: [cond_ast, then_ast, else_ast], else: [cond_ast, then_ast]
      {:ok, add_location({:conditional, [], children}, node), %{}}
    end
  end

  def transform(%{"kind" => "CONDITIONAL_EXPRESSION"} = node) do
    with {:ok, cond_ast, _} <- transform(Map.get(node, "cond")),
         {:ok, then_ast, _} <- transform(Map.get(node, "true")),
         {:ok, else_ast, _} <- transform(Map.get(node, "false")) do
      ast = {:conditional, [style: :ternary], [cond_ast, then_ast, else_ast]}
      {:ok, add_location(ast, node), %{}}
    end
  end

  def transform(%{"kind" => "WHILE_LOOP"} = node) do
    with {:ok, cond_ast, _} <- transform(Map.get(node, "cond")),
         {:ok, body_ast, _} <- transform(Map.get(node, "body")) do
      {:ok, add_location({:loop, [loop_type: :while], [cond_ast, body_ast]}, node), %{}}
    end
  end

  def transform(%{"kind" => "DO_WHILE_LOOP"} = node) do
    with {:ok, cond_ast, _} <- transform(Map.get(node, "cond")),
         {:ok, body_ast, _} <- transform(Map.get(node, "body")) do
      {:ok, add_location({:loop, [loop_type: :do_while], [cond_ast, body_ast]}, node), %{}}
    end
  end

  def transform(%{"kind" => "FOR_LOOP"} = node) do
    with {:ok, init} <- transform_list(Map.get(node, "init", [])),
         {:ok, cond_ast} <- transform_or_nil(Map.get(node, "cond")),
         {:ok, update} <- transform_list(Map.get(node, "update", [])),
         {:ok, body_ast, _} <- transform(Map.get(node, "body")) do
      ast =
        {:loop, [loop_type: :for], [init, cond_ast, update, body_ast]}

      {:ok, add_location(ast, node), %{}}
    end
  end

  def transform(%{"kind" => "ENHANCED_FOR_LOOP"} = node) do
    with {:ok, var_ast, _} <- transform(Map.get(node, "var")),
         {:ok, expr_ast, _} <- transform(Map.get(node, "expr")),
         {:ok, body_ast, _} <- transform(Map.get(node, "body")) do
      ast = {:loop, [loop_type: :for_each], [var_ast, expr_ast, body_ast]}
      {:ok, add_location(ast, node), %{}}
    end
  end

  def transform(%{"kind" => "SWITCH"} = node) do
    with {:ok, subject_ast, _} <- transform(Map.get(node, "expr")),
         {:ok, cases} <- transform_list(Map.get(node, "cases", [])) do
      {:ok, add_location({:pattern_match, [], [subject_ast | cases]}, node), %{}}
    end
  end

  def transform(%{"kind" => "CASE"} = node) do
    with {:ok, pattern_ast} <- transform_or_nil(Map.get(node, "expr")),
         {:ok, statements} <- transform_list(Map.get(node, "statements", [])) do
      body = {:block, [], statements}
      {:ok, add_location({:match_arm, [pattern: pattern_ast], [body]}, node), %{}}
    end
  end

  # ----- Exceptions -----

  def transform(%{"kind" => "TRY"} = node) do
    with {:ok, block_ast, _} <- transform(Map.get(node, "block")),
         {:ok, catches} <- transform_list(Map.get(node, "catches", [])),
         {:ok, finally_ast} <- transform_or_nil(Map.get(node, "finally")),
         {:ok, resources} <- transform_list(Map.get(node, "resources", [])) do
      meta = if resources == [], do: [], else: [resources: resources]
      ast = {:exception_handling, meta, [block_ast, catches, finally_ast]}
      {:ok, add_location(ast, node), %{}}
    end
  end

  def transform(%{"kind" => "CATCH"} = node) do
    with {:ok, param_ast, _} <- transform(Map.get(node, "param")),
         {:ok, block_ast, _} <- transform(Map.get(node, "block")) do
      {:ok, add_location({:rescue_clause, [], [param_ast, block_ast]}, node), %{}}
    end
  end

  def transform(%{"kind" => "THROW"} = node) do
    with {:ok, expr_ast, _} <- transform(Map.get(node, "expr")) do
      {:ok, add_location({:throw, [kind: :throw], [expr_ast]}, node), %{}}
    end
  end

  # ----- Expressions -----

  def transform(%{"kind" => "IDENTIFIER", "name" => name} = node) do
    {:ok, add_location({:variable, [scope: :local], name}, node), %{}}
  end

  def transform(%{"kind" => "MEMBER_SELECT"} = node) do
    with {:ok, receiver, _} <- transform(Map.get(node, "expr")) do
      attr = Map.get(node, "name", "unknown")
      {:ok, add_location({:attribute_access, [attribute: attr], [receiver]}, node), %{}}
    end
  end

  def transform(%{"kind" => kind} = node) when kind in @literal_kinds do
    subtype = literal_subtype(kind, Map.get(node, "value"))
    {:ok, add_location({:literal, [subtype: subtype], Map.get(node, "value")}, node), %{}}
  end

  def transform(%{"kind" => "BINARY"} = node) do
    with {:ok, left, _} <- transform(Map.get(node, "left")),
         {:ok, right, _} <- transform(Map.get(node, "right")) do
      {category, operator} = binary_operator(Map.get(node, "op"))
      ast = {:binary_op, [category: category, operator: operator], [left, right]}
      {:ok, add_location(ast, node), %{}}
    end
  end

  def transform(%{"kind" => "UNARY"} = node) do
    with {:ok, operand, _} <- transform(Map.get(node, "expr")) do
      {category, operator} = unary_operator(Map.get(node, "op"))
      ast = {:unary_op, [category: category, operator: operator], [operand]}
      {:ok, add_location(ast, node), %{}}
    end
  end

  def transform(%{"kind" => "ASSIGNMENT"} = node) do
    with {:ok, target, _} <- transform(Map.get(node, "var")),
         {:ok, value, _} <- transform(Map.get(node, "expr")) do
      {:ok, add_location({:assignment, [operator: :=], [target, value]}, node), %{}}
    end
  end

  def transform(%{"kind" => "PLUS_ASSIGNMENT"} = node) do
    transform_compound_assignment(node, :+)
  end

  def transform(%{"kind" => "MINUS_ASSIGNMENT"} = node) do
    transform_compound_assignment(node, :-)
  end

  def transform(%{"kind" => "MULTIPLY_ASSIGNMENT"} = node) do
    transform_compound_assignment(node, :*)
  end

  def transform(%{"kind" => "DIVIDE_ASSIGNMENT"} = node) do
    transform_compound_assignment(node, :/)
  end

  def transform(%{"kind" => "REMAINDER_ASSIGNMENT"} = node) do
    transform_compound_assignment(node, :rem)
  end

  def transform(%{"kind" => "METHOD_INVOCATION"} = node) do
    select = Map.get(node, "select")

    with {:ok, args} <- transform_list(Map.get(node, "args", [])) do
      {name, receiver_ast} = invocation_target(select)

      children = if receiver_ast, do: [receiver_ast | args], else: args

      meta =
        [name: name, language: :java] ++
          if(receiver_ast, do: [receiver: true], else: []) ++ location_meta(node)

      {:ok, add_location({:function_call, meta, children}, node), %{}}
    end
  end

  def transform(%{"kind" => "NEW_CLASS"} = node) do
    with {:ok, args} <- transform_list(Map.get(node, "args", [])),
         {:ok, class_body} <- transform_or_nil(Map.get(node, "classBody")) do
      name = qualified_name(Map.get(node, "identifier"))
      children = if class_body, do: args ++ [class_body], else: args

      meta =
        [name: name, constructor: true, language: :java] ++ location_meta(node)

      {:ok, add_location({:function_call, meta, children}, node), %{}}
    end
  end

  def transform(%{"kind" => "NEW_ARRAY"} = node) do
    with {:ok, elements} <- transform_list(Map.get(node, "initializers", [])) do
      {:ok, add_location({:list, [], elements}, node), %{}}
    end
  end

  def transform(%{"kind" => "ARRAY_ACCESS"} = node) do
    with {:ok, receiver, _} <- transform(Map.get(node, "expr")),
         {:ok, index, _} <- transform(Map.get(node, "index")) do
      ast = {:function_call, [name: "[]", language: :java], [receiver, index]}
      {:ok, add_location(ast, node), %{}}
    end
  end

  def transform(%{"kind" => "LAMBDA_EXPRESSION"} = node) do
    with {:ok, params} <- transform_list(Map.get(node, "params", [])),
         {:ok, body, _} <- transform(Map.get(node, "body")) do
      body_children = if is_list(body), do: body, else: [body]
      {:ok, add_location({:lambda, [params: params, captures: []], body_children}, node), %{}}
    end
  end

  def transform(%{"kind" => "PARENTHESIZED", "expr" => expr}) do
    transform(expr)
  end

  def transform(%{"kind" => "TYPE_CAST"} = node) do
    with {:ok, _expr_ast, _} <- transform(Map.get(node, "expr")) do
      meta = [language: :java, hint: :type_cast, type: type_name(Map.get(node, "type"))]
      {:ok, add_location({:language_specific, meta, node}, node), %{}}
    end
  end

  def transform(%{"kind" => "INSTANCE_OF"} = node) do
    with {:ok, _expr_ast, _} <- transform(Map.get(node, "expr")) do
      meta = [language: :java, hint: :instance_of, type: type_name(Map.get(node, "type"))]
      {:ok, add_location({:language_specific, meta, node}, node), %{}}
    end
  end

  # ----- Types -----

  def transform(%{"kind" => "PRIMITIVE_TYPE", "name" => name} = node) do
    {:ok, add_location({:type_annotation, [type: String.downcase(name)], []}, node), %{}}
  end

  def transform(%{"kind" => "PARAMETERIZED_TYPE"} = node) do
    meta = [type: type_name(Map.get(node, "type")), language: :java, generic: true]
    {:ok, add_location({:type_annotation, meta, []}, node), %{}}
  end

  def transform(%{"kind" => "ARRAY_TYPE"} = node) do
    meta = [type: type_name(node), language: :java, array: true]
    {:ok, add_location({:type_annotation, meta, []}, node), %{}}
  end

  # ----- Fallback -----

  def transform(%{"kind" => kind} = node) do
    meta = [language: :java, native_type: kind]
    {:ok, add_location({:language_specific, meta, node}, node), %{}}
  end

  def transform(other), do: {:ok, other, %{}}

  # ----- Private helpers -----

  defp transform_package(nil), do: {:ok, nil}

  defp transform_package(node) do
    name = qualified_name(node)

    {:ok,
     {:import, [source: name, import_type: :package, language: :java] ++ location_meta(node), []}}
  end

  defp transform_method_body(node) do
    case Map.get(node, "body") do
      nil ->
        {:ok, []}

      %{"kind" => "BLOCK"} = block ->
        with {:ok, {:block, _meta, statements}, _} <- transform(block) do
          {:ok, statements}
        end

      other ->
        with {:ok, ast, _} <- transform(other) do
          {:ok, [ast]}
        end
    end
  end

  defp transform_compound_assignment(node, operator) do
    with {:ok, target, _} <- transform(Map.get(node, "var")),
         {:ok, value, _} <- transform(Map.get(node, "expr")) do
      ast = {:augmented_assignment, [operator: operator], [target, value]}
      {:ok, add_location(ast, node), %{}}
    end
  end

  defp transform_list(nodes) when is_list(nodes) do
    nodes
    |> Enum.reduce_while({:ok, []}, fn node, {:ok, acc} ->
      case transform(node) do
        {:ok, ast, _meta} -> {:cont, {:ok, [ast | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, asts} -> {:ok, Enum.reverse(asts)}
      error -> error
    end
  end

  defp transform_list(_), do: {:ok, []}

  defp transform_or_nil(nil), do: {:ok, nil}

  defp transform_or_nil(node) do
    case transform(node) do
      {:ok, ast, _meta} -> {:ok, ast}
      error -> error
    end
  end

  # A method invocation's "select" is either a bare identifier (local call) or
  # a member select (receiver.method). The receiver is kept as the first child
  # so that call-graph extraction can resolve the target module.
  defp invocation_target(%{"kind" => "IDENTIFIER", "name" => name}), do: {name, nil}

  defp invocation_target(%{"kind" => "MEMBER_SELECT"} = select) do
    receiver = Map.get(select, "expr")
    name = Map.get(select, "name", "unknown")
    qualified = qualified_name(receiver)

    receiver_ast =
      case transform(receiver) do
        {:ok, ast, _} -> ast
        _ -> nil
      end

    if qualified == "" do
      {name, receiver_ast}
    else
      {"#{qualified}.#{name}", receiver_ast}
    end
  end

  defp invocation_target(_), do: {"unknown", nil}

  defp qualified_name(%{"kind" => "IDENTIFIER", "name" => name}), do: name

  defp qualified_name(%{"kind" => "MEMBER_SELECT"} = node) do
    case qualified_name(Map.get(node, "expr")) do
      "" -> Map.get(node, "name", "")
      prefix -> prefix <> "." <> Map.get(node, "name", "")
    end
  end

  defp qualified_name(name) when is_binary(name), do: name
  defp qualified_name(_), do: ""

  defp type_name(%{"kind" => "PRIMITIVE_TYPE", "name" => name}), do: String.downcase(name)
  defp type_name(%{"kind" => "PARAMETERIZED_TYPE"} = node), do: type_name(Map.get(node, "type"))

  defp type_name(%{"kind" => "ARRAY_TYPE"} = node),
    do: type_name(Map.get(node, "elemType")) <> "[]"

  defp type_name(%{"kind" => "IDENTIFIER", "name" => name}), do: name
  defp type_name(%{"kind" => "MEMBER_SELECT"} = node), do: qualified_name(node)
  defp type_name(_), do: "unknown"

  defp container_type("INTERFACE"), do: :interface
  defp container_type("ENUM"), do: :enum
  defp container_type("RECORD"), do: :struct
  defp container_type(_), do: :class

  defp declaration_kind(modifiers) do
    if "final" in modifiers do
      :const
    else
      :var
    end
  end

  defp visibility(modifiers) do
    cond do
      "private" in modifiers -> :private
      "protected" in modifiers -> :protected
      true -> :public
    end
  end

  defp extends_meta(%{"extends" => %{} = parent}) do
    [super_class: type_name(parent)]
  end

  defp extends_meta(_), do: []

  defp implements_meta(%{"implements" => [_ | _] = interfaces}) do
    [implements: Enum.map(interfaces, &type_name/1)]
  end

  defp implements_meta(_), do: []

  defp return_type_meta(%{"returnType" => %{} = type}) do
    [return_type: type_name(type), has_return_type: true]
  end

  defp return_type_meta(_), do: []

  defp type_meta(%{"type" => %{} = type}) do
    [declared_type: type_name(type)]
  end

  defp type_meta(_), do: []

  defp literal_subtype("INT_LITERAL", _value), do: :integer
  defp literal_subtype("LONG_LITERAL", _value), do: :integer
  defp literal_subtype("FLOAT_LITERAL", _value), do: :float
  defp literal_subtype("DOUBLE_LITERAL", _value), do: :float
  defp literal_subtype("BOOLEAN_LITERAL", _value), do: :boolean
  defp literal_subtype("CHAR_LITERAL", _value), do: :char
  defp literal_subtype("STRING_LITERAL", _value), do: :string
  defp literal_subtype("NULL_LITERAL", _value), do: :null
  defp literal_subtype(_kind, value) when is_binary(value), do: :string
  defp literal_subtype(_kind, value) when is_boolean(value), do: :boolean
  defp literal_subtype(_kind, value) when is_integer(value), do: :integer
  defp literal_subtype(_kind, value) when is_float(value), do: :float
  defp literal_subtype(_kind, nil), do: :null
  defp literal_subtype(_kind, _value), do: :string

  defp binary_operator(op) when op in ["PLUS", "+"], do: {:arithmetic, :+}
  defp binary_operator(op) when op in ["MINUS", "-"], do: {:arithmetic, :-}
  defp binary_operator(op) when op in ["MULTIPLY", "*"], do: {:arithmetic, :*}
  defp binary_operator(op) when op in ["DIVIDE", "/"], do: {:arithmetic, :/}
  defp binary_operator(op) when op in ["REMAINDER", "%"], do: {:arithmetic, :rem}
  defp binary_operator(op) when op in ["EQUAL_TO", "=="], do: {:comparison, :==}
  defp binary_operator(op) when op in ["NOT_EQUAL_TO", "!="], do: {:comparison, :!=}
  defp binary_operator(op) when op in ["LESS_THAN", "<"], do: {:comparison, :<}
  defp binary_operator(op) when op in ["LESS_THAN_EQUAL", "<="], do: {:comparison, :<=}
  defp binary_operator(op) when op in ["GREATER_THAN", ">"], do: {:comparison, :>}
  defp binary_operator(op) when op in ["GREATER_THAN_EQUAL", ">="], do: {:comparison, :>=}
  defp binary_operator(op) when op in ["CONDITIONAL_AND", "&&"], do: {:boolean, :and}
  defp binary_operator(op) when op in ["CONDITIONAL_OR", "||"], do: {:boolean, :or}
  defp binary_operator(op) when op in ["AND", "&"], do: {:bitwise, :band}
  defp binary_operator(op) when op in ["OR", "|"], do: {:bitwise, :bor}
  defp binary_operator(op) when op in ["XOR", "^"], do: {:bitwise, :bxor}
  defp binary_operator(op) when op in ["LEFT_SHIFT", "<<"], do: {:bitwise, :bsl}
  defp binary_operator(op) when op in ["RIGHT_SHIFT", ">>"], do: {:bitwise, :bsr}
  defp binary_operator(op) when op in ["UNSIGNED_RIGHT_SHIFT", ">>>"], do: {:bitwise, :bsr}
  defp binary_operator(op) when is_binary(op), do: {:custom, String.to_atom(op)}
  defp binary_operator(op), do: {:custom, op}

  defp unary_operator(op) when op in ["LOGICAL_COMPLEMENT", "!"], do: {:boolean, :not}
  defp unary_operator(op) when op in ["UNARY_MINUS", "-"], do: {:arithmetic, :-}
  defp unary_operator(op) when op in ["UNARY_PLUS", "+"], do: {:arithmetic, :+}

  defp unary_operator(op) when op in ["PREFIX_INCREMENT", "POSTFIX_INCREMENT", "++"],
    do: {:update, :++}

  defp unary_operator(op) when op in ["PREFIX_DECREMENT", "POSTFIX_DECREMENT", "--"],
    do: {:update, :--}

  defp unary_operator(op) when op in ["BITWISE_COMPLEMENT", "~"], do: {:bitwise, :bnot}
  defp unary_operator(op) when is_binary(op), do: {:custom, String.to_atom(op)}
  defp unary_operator(op), do: {:custom, op}

  defp location_meta(%{"pos" => %{"known" => true} = pos}) do
    [
      line: Map.get(pos, "line"),
      col: Map.get(pos, "col"),
      end_line: Map.get(pos, "end_line"),
      end_col: Map.get(pos, "end_col")
    ]
  end

  defp location_meta(_), do: []

  defp add_location(ast, %{"pos" => %{"known" => true} = pos}) do
    AST.with_location(ast, %{
      line: Map.get(pos, "line"),
      col: Map.get(pos, "col"),
      end_line: Map.get(pos, "end_line"),
      end_col: Map.get(pos, "end_col")
    })
  end

  defp add_location(ast, _node), do: ast
end
