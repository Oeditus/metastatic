defmodule Metastatic.Adapters.JavaScript.ToMeta do
  @moduledoc """
  Transform JavaScript/TypeScript Babel AST (M1) to MetaAST (M2).

  Converts serialized Babel AST JSON maps into standard MetaAST 3-element tuples:
      {type_atom, keyword_meta, children_or_value}

  Supports M2.1 Core, M2.2 Extended (classes, functions, loops, try/catch, ES modules),
  and M2.3 TypeScript type metadata preservation.
  """

  @doc """
  Transform Babel AST node/tree map to MetaAST tuple and metadata.

  Returns `{:ok, meta_ast, metadata}` on success or `{:error, reason}` on failure.
  """
  @spec transform(map() | list()) :: {:ok, term(), map()} | {:error, String.t()}
  def transform(nil), do: {:ok, nil, %{}}

  def transform(nodes) when is_list(nodes) do
    with {:ok, transformed} <- transform_list(nodes) do
      {:ok, transformed, %{}}
    end
  end

  def transform(%{"type" => "File", "program" => program} = node) do
    with {:ok, meta_ast, _} <- transform(program) do
      {:ok, add_location(meta_ast, node), %{}}
    end
  end

  def transform(%{"type" => "Program", "body" => body} = node) do
    with {:ok, statements} <- transform_list(body) do
      ast =
        case statements do
          [] -> {:block, [scope: :module], []}
          [single] -> single
          multiple -> {:block, [scope: :module], multiple}
        end

      {:ok, add_location(ast, node), %{}}
    end
  end

  # Unwrap ExpressionStatement
  def transform(%{"type" => "ExpressionStatement", "expression" => expr}) do
    transform(expr)
  end

  # Literals
  def transform(%{"type" => "NumericLiteral", "value" => val} = node) when is_integer(val) do
    {:ok, add_location({:literal, [subtype: :integer], val}, node), %{}}
  end

  def transform(%{"type" => "NumericLiteral", "value" => val} = node) when is_float(val) do
    {:ok, add_location({:literal, [subtype: :float], val}, node), %{}}
  end

  def transform(%{"type" => "StringLiteral", "value" => val} = node) do
    {:ok, add_location({:literal, [subtype: :string], val}, node), %{}}
  end

  def transform(%{"type" => "BooleanLiteral", "value" => val} = node) do
    {:ok, add_location({:literal, [subtype: :boolean], val}, node), %{}}
  end

  def transform(%{"type" => "NullLiteral"} = node) do
    {:ok, add_location({:literal, [subtype: :null], nil}, node), %{}}
  end

  def transform(%{"type" => "RegExpLiteral", "pattern" => pattern, "flags" => flags} = node) do
    {:ok, add_location({:literal, [subtype: :regex, flags: flags], pattern}, node), %{}}
  end

  def transform(%{"type" => "BigIntLiteral", "value" => val} = node) do
    val_int = String.to_integer(val)
    {:ok, add_location({:literal, [subtype: :integer, bigint: true], val_int}, node), %{}}
  end

  def transform(%{"type" => "TemplateLiteral", "quasis" => quasis, "expressions" => exprs} = node) do
    if Enum.empty?(exprs) do
      str_val = Enum.map_join(quasis, "", fn %{"value" => %{"raw" => raw}} -> raw end)
      {:ok, add_location({:literal, [subtype: :string], str_val}, node), %{}}
    else
      with {:ok, transformed_exprs} <- transform_list(exprs) do
        raw_parts = Enum.map(quasis, fn %{"value" => %{"raw" => raw}} -> raw end)
        meta = [subtype: :template_string, quasis: raw_parts]
        {:ok, add_location({:literal, meta, transformed_exprs}, node), %{}}
      end
    end
  end

  # Identifiers & Special Variables
  def transform(%{"type" => "Identifier", "name" => name} = node) do
    meta = [scope: :local] ++ extract_ts_type(node)
    {:ok, add_location({:variable, meta, name}, node), %{}}
  end

  def transform(%{"type" => "ThisExpression"} = node) do
    {:ok, add_location({:variable, [scope: :special], "this"}, node), %{}}
  end

  def transform(%{"type" => "Super"} = node) do
    {:ok, add_location({:variable, [scope: :special], "super"}, node), %{}}
  end

  # Member Expressions (e.g. obj.prop or obj[prop])
  def transform(
        %{
          "type" => "MemberExpression",
          "object" => object,
          "property" => property,
          "computed" => computed
        } = node
      ) do
    with {:ok, obj_ast, _} <- transform(object),
         {:ok, prop_ast, _} <- transform(property) do
      meta = [computed: computed]

      {:ok,
       add_location({:function_call, [name: "member_access"] ++ meta, [obj_ast, prop_ast]}, node),
       %{}}
    end
  end

  def transform(
        %{
          "type" => "OptionalMemberExpression",
          "object" => object,
          "property" => property,
          "computed" => computed
        } = node
      ) do
    with {:ok, obj_ast, _} <- transform(object),
         {:ok, prop_ast, _} <- transform(property) do
      meta = [computed: computed, optional: true]

      {:ok,
       add_location({:function_call, [name: "member_access"] ++ meta, [obj_ast, prop_ast]}, node),
       %{}}
    end
  end

  # Binary Expressions & Logical Expressions
  def transform(
        %{"type" => "BinaryExpression", "operator" => op, "left" => left, "right" => right} = node
      ) do
    with {:ok, left_ast, _} <- transform(left),
         {:ok, right_ast, _} <- transform(right) do
      {category, op_atom} = parse_binary_op(op)
      ast = {:binary_op, [category: category, operator: op_atom], [left_ast, right_ast]}
      {:ok, add_location(ast, node), %{}}
    end
  end

  def transform(
        %{"type" => "LogicalExpression", "operator" => op, "left" => left, "right" => right} =
          node
      ) do
    with {:ok, left_ast, _} <- transform(left),
         {:ok, right_ast, _} <- transform(right) do
      op_atom = parse_logical_op(op)
      ast = {:binary_op, [category: :boolean, operator: op_atom], [left_ast, right_ast]}
      {:ok, add_location(ast, node), %{}}
    end
  end

  # Unary & Update Expressions
  def transform(
        %{"type" => "UnaryExpression", "operator" => op, "argument" => arg, "prefix" => prefix} =
          node
      ) do
    with {:ok, arg_ast, _} <- transform(arg) do
      {category, op_atom} = parse_unary_op(op)
      ast = {:unary_op, [category: category, operator: op_atom, prefix: prefix], [arg_ast]}
      {:ok, add_location(ast, node), %{}}
    end
  end

  def transform(
        %{"type" => "UpdateExpression", "operator" => op, "argument" => arg, "prefix" => prefix} =
          node
      ) do
    with {:ok, arg_ast, _} <- transform(arg) do
      op_atom = String.to_atom(op)
      ast = {:unary_op, [category: :update, operator: op_atom, prefix: prefix], [arg_ast]}
      {:ok, add_location(ast, node), %{}}
    end
  end

  # Variable Declarations & Assignments
  def transform(
        %{"type" => "VariableDeclaration", "kind" => kind, "declarations" => decls} = node
      ) do
    with {:ok, transformed_decls} <- transform_declarators(decls, kind) do
      ast =
        case transformed_decls do
          [single] -> single
          multiple -> {:block, [scope: :var_declarations], multiple}
        end

      {:ok, add_location(ast, node), %{}}
    end
  end

  def transform(
        %{"type" => "AssignmentExpression", "operator" => op, "left" => left, "right" => right} =
          node
      ) do
    with {:ok, left_ast, _} <- transform(left),
         {:ok, right_ast, _} <- transform(right) do
      op_atom = parse_assignment_op(op)
      ast = {:assignment, [operator: op_atom], [left_ast, right_ast]}
      {:ok, add_location(ast, node), %{}}
    end
  end

  # Function Calls & New Expressions
  def transform(%{"type" => "CallExpression", "callee" => callee, "arguments" => args} = node) do
    with {:ok, callee_ast, _} <- transform(callee),
         {:ok, args_ast} <- transform_list(args) do
      callee_name = extract_callee_name(callee_ast)
      meta = [name: callee_name] ++ extract_ts_type(node)
      ast = {:function_call, meta, [callee_ast | args_ast]}
      {:ok, add_location(ast, node), %{}}
    end
  end

  def transform(
        %{"type" => "OptionalCallExpression", "callee" => callee, "arguments" => args} = node
      ) do
    with {:ok, callee_ast, _} <- transform(callee),
         {:ok, args_ast} <- transform_list(args) do
      callee_name = extract_callee_name(callee_ast)
      meta = [name: callee_name, optional: true] ++ extract_ts_type(node)
      ast = {:function_call, meta, [callee_ast | args_ast]}
      {:ok, add_location(ast, node), %{}}
    end
  end

  def transform(%{"type" => "NewExpression", "callee" => callee, "arguments" => args} = node) do
    with {:ok, callee_ast, _} <- transform(callee),
         {:ok, args_ast} <- transform_list(args) do
      callee_name = extract_callee_name(callee_ast)
      meta = [name: callee_name, constructor: true]
      ast = {:function_call, meta, [callee_ast | args_ast]}
      {:ok, add_location(ast, node), %{}}
    end
  end

  # Function Declarations, Expressions & Arrow Functions
  def transform(
        %{"type" => "FunctionDeclaration", "id" => id, "params" => params, "body" => body} = node
      ) do
    func_name = if id, do: id["name"], else: "anonymous"

    with {:ok, params_ast} <- transform_list(params),
         {:ok, body_ast, _} <- transform(body) do
      meta =
        [
          name: func_name,
          async: node["async"] || false,
          generator: node["generator"] || false,
          visibility: :public
        ] ++ extract_ts_type(node)

      ast = {:function_def, meta, [params_ast, body_ast]}
      {:ok, add_location(ast, node), %{}}
    end
  end

  def transform(
        %{"type" => "FunctionExpression", "id" => id, "params" => params, "body" => body} = node
      ) do
    func_name = if id, do: id["name"], else: nil

    with {:ok, params_ast} <- transform_list(params),
         {:ok, body_ast, _} <- transform(body) do
      meta =
        [
          name: func_name,
          async: node["async"] || false,
          generator: node["generator"] || false
        ] ++ extract_ts_type(node)

      ast = {:lambda, meta, [params_ast, body_ast]}
      {:ok, add_location(ast, node), %{}}
    end
  end

  def transform(%{"type" => "ArrowFunctionExpression", "params" => params, "body" => body} = node) do
    with {:ok, params_ast} <- transform_list(params),
         {:ok, body_ast, _} <- transform(body) do
      meta =
        [
          async: node["async"] || false,
          arrow: true
        ] ++ extract_ts_type(node)

      ast = {:lambda, meta, [params_ast, body_ast]}
      {:ok, add_location(ast, node), %{}}
    end
  end

  # Conditionals & Ternary
  def transform(
        %{"type" => "IfStatement", "test" => test, "consequent" => cons, "alternate" => alt} =
          node
      ) do
    with {:ok, test_ast, _} <- transform(test),
         {:ok, cons_ast, _} <- transform(cons),
         {:ok, alt_ast, _} <- if(alt, do: transform(alt), else: {:ok, nil, %{}}) do
      children = if alt_ast, do: [test_ast, cons_ast, alt_ast], else: [test_ast, cons_ast]
      ast = {:conditional, [], children}
      {:ok, add_location(ast, node), %{}}
    end
  end

  def transform(
        %{
          "type" => "ConditionalExpression",
          "test" => test,
          "consequent" => cons,
          "alternate" => alt
        } = node
      ) do
    with {:ok, test_ast, _} <- transform(test),
         {:ok, cons_ast, _} <- transform(cons),
         {:ok, alt_ast, _} <- transform(alt) do
      ast = {:conditional, [style: :ternary], [test_ast, cons_ast, alt_ast]}
      {:ok, add_location(ast, node), %{}}
    end
  end

  # Statements & Blocks
  def transform(%{"type" => "BlockStatement", "body" => body} = node) do
    with {:ok, statements} <- transform_list(body) do
      ast = {:block, [], statements}
      {:ok, add_location(ast, node), %{}}
    end
  end

  def transform(%{"type" => "ReturnStatement", "argument" => arg} = node) do
    with {:ok, arg_ast, _} <- if(arg, do: transform(arg), else: {:ok, nil, %{}}) do
      ast = {:return, [], if(arg_ast, do: [arg_ast], else: [])}
      {:ok, add_location(ast, node), %{}}
    end
  end

  def transform(%{"type" => "BreakStatement"} = node) do
    {:ok, add_location({:early_return, [kind: :break], []}, node), %{}}
  end

  def transform(%{"type" => "ContinueStatement"} = node) do
    {:ok, add_location({:early_return, [kind: :continue], []}, node), %{}}
  end

  # Loops
  def transform(%{"type" => "WhileStatement", "test" => test, "body" => body} = node) do
    with {:ok, test_ast, _} <- transform(test),
         {:ok, body_ast, _} <- transform(body) do
      ast = {:loop, [loop_type: :while], [test_ast, body_ast]}
      {:ok, add_location(ast, node), %{}}
    end
  end

  def transform(%{"type" => "DoWhileStatement", "test" => test, "body" => body} = node) do
    with {:ok, test_ast, _} <- transform(test),
         {:ok, body_ast, _} <- transform(body) do
      ast = {:loop, [loop_type: :do_while], [test_ast, body_ast]}
      {:ok, add_location(ast, node), %{}}
    end
  end

  def transform(
        %{
          "type" => "ForStatement",
          "init" => init,
          "test" => test,
          "update" => update,
          "body" => body
        } = node
      ) do
    with {:ok, init_ast, _} <- if(init, do: transform(init), else: {:ok, nil, %{}}),
         {:ok, test_ast, _} <- if(test, do: transform(test), else: {:ok, nil, %{}}),
         {:ok, update_ast, _} <- if(update, do: transform(update), else: {:ok, nil, %{}}),
         {:ok, body_ast, _} <- transform(body) do
      ast = {:loop, [loop_type: :for], [init_ast, test_ast, update_ast, body_ast]}
      {:ok, add_location(ast, node), %{}}
    end
  end

  def transform(
        %{"type" => "ForOfStatement", "left" => left, "right" => right, "body" => body} = node
      ) do
    with {:ok, left_ast, _} <- transform(left),
         {:ok, right_ast, _} <- transform(right),
         {:ok, body_ast, _} <- transform(body) do
      meta = [loop_type: :for_of, await: node["await"] || false]
      ast = {:loop, meta, [left_ast, right_ast, body_ast]}
      {:ok, add_location(ast, node), %{}}
    end
  end

  def transform(
        %{"type" => "ForInStatement", "left" => left, "right" => right, "body" => body} = node
      ) do
    with {:ok, left_ast, _} <- transform(left),
         {:ok, right_ast, _} <- transform(right),
         {:ok, body_ast, _} <- transform(body) do
      ast = {:loop, [loop_type: :for_in], [left_ast, right_ast, body_ast]}
      {:ok, add_location(ast, node), %{}}
    end
  end

  # Classes & Methods
  def transform(
        %{"type" => "ClassDeclaration", "id" => id, "superClass" => super_class, "body" => body} =
          node
      ) do
    class_name = if id, do: id["name"], else: "anonymous"

    with {:ok, super_ast, _} <- if(super_class, do: transform(super_class), else: {:ok, nil, %{}}),
         {:ok, members_ast, _} <- transform(body) do
      meta =
        [name: class_name, container_type: :class, super_class: super_ast] ++
          extract_ts_type(node)

      ast = {:container, meta, members_ast}
      {:ok, add_location(ast, node), %{}}
    end
  end

  def transform(%{"type" => "ClassBody", "body" => body}) do
    transform_list(body)
    |> case do
      {:ok, members} -> {:ok, members, %{}}
      err -> err
    end
  end

  def transform(
        %{"type" => "ClassMethod", "key" => key, "params" => params, "body" => body} = node
      ) do
    method_name = extract_key_name(key)
    kind = String.to_atom(node["kind"] || "method")

    with {:ok, params_ast} <- transform_list(params),
         {:ok, body_ast, _} <- transform(body) do
      meta =
        [
          name: method_name,
          kind: kind,
          static: node["static"] || false,
          async: node["async"] || false,
          visibility: if(String.starts_with?(method_name, "_"), do: :private, else: :public)
        ] ++ extract_ts_type(node)

      ast = {:function_def, meta, [params_ast, body_ast]}
      {:ok, add_location(ast, node), %{}}
    end
  end

  def transform(%{"type" => "ClassProperty", "key" => key, "value" => value} = node) do
    prop_name = extract_key_name(key)

    with {:ok, val_ast, _} <- if(value, do: transform(value), else: {:ok, nil, %{}}) do
      meta = [name: prop_name, static: node["static"] || false] ++ extract_ts_type(node)

      ast =
        {:assignment, [operator: :=, property: true] ++ meta,
         [{:variable, [scope: :local], prop_name}, val_ast]}

      {:ok, add_location(ast, node), %{}}
    end
  end

  # Exception Handling
  def transform(
        %{
          "type" => "TryStatement",
          "block" => block,
          "handler" => handler,
          "finalizer" => finalizer
        } = node
      ) do
    with {:ok, block_ast, _} <- transform(block),
         {:ok, handler_ast, _} <- if(handler, do: transform(handler), else: {:ok, nil, %{}}),
         {:ok, finalizer_ast, _} <- if(finalizer, do: transform(finalizer), else: {:ok, nil, %{}}) do
      ast = {:try_catch, [], [block_ast, handler_ast, finalizer_ast]}
      {:ok, add_location(ast, node), %{}}
    end
  end

  def transform(%{"type" => "CatchClause", "param" => param, "body" => body} = node) do
    with {:ok, param_ast, _} <- if(param, do: transform(param), else: {:ok, nil, %{}}),
         {:ok, body_ast, _} <- transform(body) do
      ast = {:rescue_clause, [], [param_ast, body_ast]}
      {:ok, add_location(ast, node), %{}}
    end
  end

  def transform(%{"type" => "ThrowStatement", "argument" => arg} = node) do
    with {:ok, arg_ast, _} <- transform(arg) do
      ast = {:throw, [], [arg_ast]}
      {:ok, add_location(ast, node), %{}}
    end
  end

  # ES Modules / Imports / Exports
  def transform(
        %{"type" => "ImportDeclaration", "specifiers" => specifiers, "source" => source} = node
      ) do
    source_val = source["value"]
    spec_names = Enum.map(specifiers, &extract_import_specifier/1)
    meta = [source: source_val, specifiers: spec_names, import_type: :es6_import]
    {:ok, add_location({:import, meta, []}, node), %{}}
  end

  def transform(
        %{"type" => "ExportNamedDeclaration", "declaration" => decl, "specifiers" => specifiers} =
          node
      ) do
    with {:ok, decl_ast, _} <- if(decl, do: transform(decl), else: {:ok, nil, %{}}) do
      meta = [export_type: :named, specifiers: Enum.map(specifiers, &extract_export_specifier/1)]
      children = if decl_ast, do: [decl_ast], else: []
      {:ok, add_location({:export, meta, children}, node), %{}}
    end
  end

  def transform(%{"type" => "ExportDefaultDeclaration", "declaration" => decl} = node) do
    with {:ok, decl_ast, _} <- transform(decl) do
      {:ok, add_location({:export, [export_type: :default], [decl_ast]}, node), %{}}
    end
  end

  # Objects & Arrays (Collections)
  def transform(%{"type" => "ArrayExpression", "elements" => elements} = node) do
    with {:ok, transformed_elements} <- transform_list(Enum.reject(elements, &is_nil/1)) do
      ast = {:collection, [subtype: :list], transformed_elements}
      {:ok, add_location(ast, node), %{}}
    end
  end

  def transform(%{"type" => "ObjectExpression", "properties" => properties} = node) do
    with {:ok, transformed_props} <- transform_list(properties) do
      ast = {:collection, [subtype: :map], transformed_props}
      {:ok, add_location(ast, node), %{}}
    end
  end

  def transform(%{"type" => "ObjectProperty", "key" => key, "value" => value} = node) do
    key_name = extract_key_name(key)

    with {:ok, val_ast, _} <- transform(value) do
      ast = {:pair, [key: key_name], [{:literal, [subtype: :string], key_name}, val_ast]}
      {:ok, add_location(ast, node), %{}}
    end
  end

  def transform(
        %{"type" => "ObjectMethod", "key" => key, "params" => params, "body" => body} = node
      ) do
    method_name = extract_key_name(key)

    with {:ok, params_ast} <- transform_list(params),
         {:ok, body_ast, _} <- transform(body) do
      meta = [
        name: method_name,
        async: node["async"] || false,
        generator: node["generator"] || false
      ]

      ast = {:function_def, meta, [params_ast, body_ast]}
      {:ok, add_location(ast, node), %{}}
    end
  end

  # TypeScript AST Nodes (Interfaces, Type Aliases, Enums)
  def transform(%{"type" => "TSInterfaceDeclaration", "id" => id} = node) do
    name = id["name"]
    meta = [ts_kind: :interface, name: name] ++ extract_ts_type(node)

    {:ok,
     add_location(
       {:language_specific, [language: :typescript, hint: :interface] ++ meta, node},
       node
     ), %{}}
  end

  def transform(%{"type" => "TSTypeAliasDeclaration", "id" => id} = node) do
    name = id["name"]
    meta = [ts_kind: :type_alias, name: name] ++ extract_ts_type(node)

    {:ok,
     add_location(
       {:language_specific, [language: :typescript, hint: :type_alias] ++ meta, node},
       node
     ), %{}}
  end

  def transform(%{"type" => "TSEnumDeclaration", "id" => id} = node) do
    name = id["name"]
    meta = [ts_kind: :enum, name: name]

    {:ok,
     add_location({:language_specific, [language: :typescript, hint: :enum] ++ meta, node}, node),
     %{}}
  end

  # Fallback for unhandled native nodes -> store in language_specific escape hatch
  def transform(%{"type" => type} = node) do
    meta = [language: :javascript, native_type: type]
    {:ok, add_location({:language_specific, meta, node}, node), %{}}
  end

  def transform(other), do: {:ok, other, %{}}

  # Private Helpers

  defp transform_list(nodes) when is_list(nodes) do
    results =
      Enum.reduce_while(nodes, {:ok, []}, fn node, {:ok, acc} ->
        case transform(node) do
          {:ok, meta_ast, _} -> {:cont, {:ok, [meta_ast | acc]}}
          {:error, _} = err -> {:halt, err}
        end
      end)

    case results do
      {:ok, list} -> {:ok, Enum.reverse(list)}
      err -> err
    end
  end

  defp transform_declarators(decls, kind) do
    kind_atom = String.to_atom(kind)

    results =
      Enum.map(decls, fn %{"id" => id, "init" => init} = decl ->
        with {:ok, target_ast, _} <- transform(id),
             {:ok, init_ast, _} <- if(init, do: transform(init), else: {:ok, nil, %{}}) do
          add_location(
            {:assignment, [operator: :=, kind: kind_atom], [target_ast, init_ast]},
            decl
          )
        end
      end)

    {:ok, results}
  end

  defp parse_binary_op("+"), do: {:arithmetic, :+}
  defp parse_binary_op("-"), do: {:arithmetic, :-}
  defp parse_binary_op("*"), do: {:arithmetic, :*}
  defp parse_binary_op("/"), do: {:arithmetic, :/}
  defp parse_binary_op("%"), do: {:arithmetic, :rem}
  defp parse_binary_op("**"), do: {:arithmetic, :pow}
  defp parse_binary_op("=="), do: {:comparison, :==}
  defp parse_binary_op("==="), do: {:comparison, :===}
  defp parse_binary_op("!="), do: {:comparison, :!=}
  defp parse_binary_op("!=="), do: {:comparison, :!==}
  defp parse_binary_op("<"), do: {:comparison, :<}
  defp parse_binary_op(">"), do: {:comparison, :>}
  defp parse_binary_op("<="), do: {:comparison, :<=}
  defp parse_binary_op(">="), do: {:comparison, :>=}
  defp parse_binary_op("<<"), do: {:bitwise, :bsl}
  defp parse_binary_op(">>"), do: {:bitwise, :bsr}
  defp parse_binary_op("&"), do: {:bitwise, :band}
  defp parse_binary_op("|"), do: {:bitwise, :bor}
  defp parse_binary_op("^"), do: {:bitwise, :bxor}
  defp parse_binary_op(op), do: {:custom, String.to_atom(op)}

  defp parse_logical_op("&&"), do: :and
  defp parse_logical_op("||"), do: :or
  defp parse_logical_op("??"), do: :nullish_coalesce
  defp parse_logical_op(op), do: String.to_atom(op)

  defp parse_unary_op("!"), do: {:boolean, :not}
  defp parse_unary_op("-"), do: {:arithmetic, :-}
  defp parse_unary_op("+"), do: {:arithmetic, :+}
  defp parse_unary_op("typeof"), do: {:type, :typeof}
  defp parse_unary_op("delete"), do: {:object, :delete}
  defp parse_unary_op(op), do: {:custom, String.to_atom(op)}

  defp parse_assignment_op("="), do: :=
  defp parse_assignment_op("+="), do: :"+="
  defp parse_assignment_op("-="), do: :"-="
  defp parse_assignment_op("*="), do: :"*="
  defp parse_assignment_op("/="), do: :"/="
  defp parse_assignment_op(op), do: String.to_atom(op)

  defp extract_callee_name({:variable, _, name}) when is_binary(name), do: name

  defp extract_callee_name({:function_call, meta, [obj, prop]}) do
    if meta[:name] == "member_access" do
      "#{extract_callee_name(obj)}.#{extract_callee_name(prop)}"
    else
      "call"
    end
  end

  defp extract_callee_name(_), do: "anonymous"

  defp extract_key_name(%{"name" => name}), do: name
  defp extract_key_name(%{"value" => value}), do: to_string(value)
  defp extract_key_name(_), do: "unknown"

  defp extract_import_specifier(%{"type" => "ImportDefaultSpecifier", "local" => local}) do
    {:default, local["name"]}
  end

  defp extract_import_specifier(%{"type" => "ImportNamespaceSpecifier", "local" => local}) do
    {:namespace, local["name"]}
  end

  defp extract_import_specifier(%{
         "type" => "ImportSpecifier",
         "imported" => imported,
         "local" => local
       }) do
    imported_name = extract_key_name(imported)
    {:named, imported_name, local["name"]}
  end

  defp extract_import_specifier(_), do: {:unknown, "unknown"}

  defp extract_export_specifier(%{"exported" => exported, "local" => local}) do
    {extract_key_name(local), extract_key_name(exported)}
  end

  defp extract_export_specifier(_), do: {"unknown", "unknown"}

  defp extract_ts_type(%{"typeAnnotation" => type_ann}) when is_map(type_ann) do
    [ts_type: true]
  end

  defp extract_ts_type(_), do: []

  defp add_location(tuple, %{"loc" => %{"start" => %{"line" => line, "column" => col}}})
       when is_tuple(tuple) do
    {type, meta, children} = tuple
    loc_meta = [line: line, col: col]
    {type, Keyword.merge(loc_meta, meta), children}
  end

  defp add_location(tuple, _), do: tuple
end
