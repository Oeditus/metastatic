defmodule Metastatic.Adapters.JavaScript.FromMeta do
  @moduledoc """
  Transform MetaAST (M2) to JavaScript/TypeScript Babel AST (M1).

  Reconstructs Babel AST JSON maps from MetaAST 3-element tuples and metadata.
  """

  @doc """
  Transform MetaAST tree to Babel AST map.

  Returns `{:ok, babel_ast_map}` on success or `{:error, reason}` on failure.
  """
  @spec transform(term(), map()) :: {:ok, map()} | {:error, String.t()}
  def transform(meta_ast, metadata \\ %{})

  def transform(nil, _metadata), do: {:ok, nil}

  def transform(meta_ast, _metadata) do
    with {:ok, body_node} <- to_babel(meta_ast) do
      # Wrap in Program / File AST if not already wrapped
      case body_node do
        %{"type" => "File"} ->
          {:ok, body_node}

        %{"type" => "Program"} ->
          {:ok, %{"type" => "File", "program" => body_node}}

        statement when is_map(statement) ->
          stmt = wrap_statement(statement)

          file = %{
            "type" => "File",
            "program" => %{
              "type" => "Program",
              "sourceType" => "module",
              "body" => [stmt]
            }
          }

          {:ok, file}
      end
    end
  end

  # Blocks & Modules
  defp to_babel({:block, _meta, statements}) when is_list(statements) do
    with {:ok, babel_stmts} <- to_babel_list(statements) do
      wrapped = Enum.map(babel_stmts, &wrap_statement/1)

      {:ok,
       %{
         "type" => "Program",
         "sourceType" => "module",
         "body" => wrapped
       }}
    end
  end

  # Literals
  defp to_babel({:literal, meta, val}) do
    subtype = meta[:subtype]

    node =
      case subtype do
        :integer ->
          %{"type" => "NumericLiteral", "value" => val}

        :float ->
          %{"type" => "NumericLiteral", "value" => val}

        :string ->
          %{"type" => "StringLiteral", "value" => to_string(val)}

        :boolean ->
          %{"type" => "BooleanLiteral", "value" => val}

        :null ->
          %{"type" => "NullLiteral"}

        :regex ->
          flags = meta[:flags] || ""
          %{"type" => "RegExpLiteral", "pattern" => val, "flags" => flags}

        _ ->
          cond do
            is_integer(val) -> %{"type" => "NumericLiteral", "value" => val}
            is_float(val) -> %{"type" => "NumericLiteral", "value" => val}
            is_binary(val) -> %{"type" => "StringLiteral", "value" => val}
            is_boolean(val) -> %{"type" => "BooleanLiteral", "value" => val}
            is_nil(val) -> %{"type" => "NullLiteral"}
            true -> %{"type" => "StringLiteral", "value" => inspect(val)}
          end
      end

    {:ok, node}
  end

  # Variables
  defp to_babel({:variable, meta, name}) do
    node =
      case meta[:scope] do
        :special when name == "this" -> %{"type" => "ThisExpression"}
        :special when name == "super" -> %{"type" => "Super"}
        _ -> %{"type" => "Identifier", "name" => name}
      end

    {:ok, node}
  end

  # Binary Operations
  defp to_babel({:binary_op, meta, [left, right]}) do
    with {:ok, left_babel} <- to_babel(left),
         {:ok, right_babel} <- to_babel(right) do
      category = meta[:category]
      operator = meta[:operator]

      node =
        if category == :boolean do
          %{
            "type" => "LogicalExpression",
            "operator" => unparse_logical_op(operator),
            "left" => left_babel,
            "right" => right_babel
          }
        else
          %{
            "type" => "BinaryExpression",
            "operator" => unparse_binary_op(operator),
            "left" => left_babel,
            "right" => right_babel
          }
        end

      {:ok, node}
    end
  end

  # Unary Operations
  defp to_babel({:unary_op, meta, [arg]}) do
    with {:ok, arg_babel} <- to_babel(arg) do
      category = meta[:category]
      operator = meta[:operator]
      prefix = Keyword.get(meta, :prefix, true)

      node =
        if category == :update do
          %{
            "type" => "UpdateExpression",
            "operator" => to_string(operator),
            "argument" => arg_babel,
            "prefix" => prefix
          }
        else
          %{
            "type" => "UnaryExpression",
            "operator" => unparse_unary_op(operator),
            "argument" => arg_babel,
            "prefix" => prefix
          }
        end

      {:ok, node}
    end
  end

  # Assignments
  defp to_babel({:assignment, meta, [target, val]}) do
    kind = meta[:kind]

    if kind in [:const, :let, :var] do
      with {:ok, target_babel} <- to_babel(target),
           {:ok, val_babel} <- if(val, do: to_babel(val), else: {:ok, nil}) do
        decl = %{
          "type" => "VariableDeclarator",
          "id" => target_babel,
          "init" => val_babel
        }

        {:ok,
         %{
           "type" => "VariableDeclaration",
           "kind" => to_string(kind),
           "declarations" => [decl]
         }}
      end
    else
      with {:ok, target_babel} <- to_babel(target),
           {:ok, val_babel} <- to_babel(val) do
        op = meta[:operator] || :=

        {:ok,
         %{
           "type" => "AssignmentExpression",
           "operator" => unparse_assignment_op(op),
           "left" => target_babel,
           "right" => val_babel
         }}
      end
    end
  end

  # Function Calls & Member Access
  defp to_babel({:function_call, meta, children}) do
    name = meta[:name]

    cond do
      name == "member_access" and match?([_, _], children) ->
        [obj, prop] = children
        computed = meta[:computed] || false

        with {:ok, obj_babel} <- to_babel(obj),
             {:ok, prop_babel} <- to_babel(prop) do
          type = if meta[:optional], do: "OptionalMemberExpression", else: "MemberExpression"

          {:ok,
           %{
             "type" => type,
             "object" => obj_babel,
             "property" => prop_babel,
             "computed" => computed
           }}
        end

      match?([_ | _], children) ->
        [callee | args] = children

        with {:ok, callee_babel} <- to_babel(callee),
             {:ok, args_babel} <- to_babel_list(args) do
          type =
            cond do
              meta[:constructor] -> "NewExpression"
              meta[:optional] -> "OptionalCallExpression"
              true -> "CallExpression"
            end

          {:ok,
           %{
             "type" => type,
             "callee" => callee_babel,
             "arguments" => args_babel
           }}
        end

      true ->
        {:error, "Invalid function call format"}
    end
  end

  # Function Definitions & Lambdas
  defp to_babel({:function_def, meta, [params, body]}) do
    name = meta[:name]

    with {:ok, params_babel} <- to_babel_list(params),
         {:ok, body_babel} <- to_babel_body(body) do
      if meta[:kind] in [:method, :constructor, :get, :set] do
        {:ok,
         %{
           "type" => "ClassMethod",
           "kind" => to_string(meta[:kind] || "method"),
           "key" => %{"type" => "Identifier", "name" => name || "method"},
           "static" => meta[:static] || false,
           "async" => meta[:async] || false,
           "params" => params_babel,
           "body" => body_babel
         }}
      else
        id_node =
          if name && name != "anonymous", do: %{"type" => "Identifier", "name" => name}, else: nil

        {:ok,
         %{
           "type" => "FunctionDeclaration",
           "id" => id_node,
           "async" => meta[:async] || false,
           "generator" => meta[:generator] || false,
           "params" => params_babel,
           "body" => body_babel
         }}
      end
    end
  end

  defp to_babel({:lambda, meta, [params, body]}) do
    with {:ok, params_babel} <- to_babel_list(params),
         {:ok, body_babel} <- to_babel_body(body) do
      if meta[:arrow] != false do
        {:ok,
         %{
           "type" => "ArrowFunctionExpression",
           "async" => meta[:async] || false,
           "params" => params_babel,
           "body" => body_babel
         }}
      else
        {:ok,
         %{
           "type" => "FunctionExpression",
           "async" => meta[:async] || false,
           "params" => params_babel,
           "body" => body_babel
         }}
      end
    end
  end

  # Conditionals
  defp to_babel({:conditional, meta, [test, cons | rest]}) do
    alt = Enum.at(rest, 0)

    with {:ok, test_babel} <- to_babel(test),
         {:ok, cons_babel} <- to_babel(cons),
         {:ok, alt_babel} <- if(alt, do: to_babel(alt), else: {:ok, nil}) do
      if meta[:style] == :ternary do
        {:ok,
         %{
           "type" => "ConditionalExpression",
           "test" => test_babel,
           "consequent" => cons_babel,
           "alternate" => alt_babel
         }}
      else
        {:ok,
         %{
           "type" => "IfStatement",
           "test" => test_babel,
           "consequent" => wrap_statement(cons_babel),
           "alternate" => if(alt_babel, do: wrap_statement(alt_babel), else: nil)
         }}
      end
    end
  end

  # Returns & Breaks
  defp to_babel({:return, _meta, []}) do
    {:ok, %{"type" => "ReturnStatement", "argument" => nil}}
  end

  defp to_babel({:return, _meta, [arg | _]}) do
    with {:ok, arg_babel} <- to_babel(arg),
         do: {:ok, %{"type" => "ReturnStatement", "argument" => arg_babel}}
  end

  defp to_babel({:early_return, meta, _}) do
    case meta[:kind] do
      :break -> {:ok, %{"type" => "BreakStatement"}}
      :continue -> {:ok, %{"type" => "ContinueStatement"}}
      _ -> {:ok, %{"type" => "ReturnStatement", "argument" => nil}}
    end
  end

  # Loops
  defp to_babel({:loop, meta, children}) do
    type = meta[:loop_type]

    case type do
      :while ->
        [test, body] = children

        with {:ok, test_b} <- to_babel(test),
             {:ok, body_b} <- to_babel_body(body) do
          {:ok, %{"type" => "WhileStatement", "test" => test_b, "body" => body_b}}
        end

      :do_while ->
        [test, body] = children

        with {:ok, test_b} <- to_babel(test),
             {:ok, body_b} <- to_babel_body(body) do
          {:ok, %{"type" => "DoWhileStatement", "test" => test_b, "body" => body_b}}
        end

      :for_of ->
        [left, right, body] = children

        with {:ok, left_b} <- to_babel(left),
             {:ok, right_b} <- to_babel(right),
             {:ok, body_b} <- to_babel_body(body) do
          {:ok,
           %{
             "type" => "ForOfStatement",
             "left" => left_b,
             "right" => right_b,
             "body" => body_b,
             "await" => meta[:await] || false
           }}
        end

      :for_in ->
        [left, right, body] = children

        with {:ok, left_b} <- to_babel(left),
             {:ok, right_b} <- to_babel(right),
             {:ok, body_b} <- to_babel_body(body) do
          {:ok,
           %{
             "type" => "ForInStatement",
             "left" => left_b,
             "right" => right_b,
             "body" => body_b
           }}
        end

      _ ->
        [init, test, update, body] = children

        with {:ok, init_b} <- if(init, do: to_babel(init), else: {:ok, nil}),
             {:ok, test_b} <- if(test, do: to_babel(test), else: {:ok, nil}),
             {:ok, update_b} <- if(update, do: to_babel(update), else: {:ok, nil}),
             {:ok, body_b} <- to_babel_body(body) do
          {:ok,
           %{
             "type" => "ForStatement",
             "init" => init_b,
             "test" => test_b,
             "update" => update_b,
             "body" => body_b
           }}
        end
    end
  end

  # Classes & Containers
  defp to_babel({:container, meta, members}) do
    name = meta[:name] || "anonymous"
    super_class = meta[:super_class]

    with {:ok, super_babel} <- if(super_class, do: to_babel(super_class), else: {:ok, nil}),
         {:ok, members_babel} <- to_babel_list(members) do
      {:ok,
       %{
         "type" => "ClassDeclaration",
         "id" => %{"type" => "Identifier", "name" => name},
         "superClass" => super_babel,
         "body" => %{
           "type" => "ClassBody",
           "body" => members_babel
         }
       }}
    end
  end

  # Exceptions
  defp to_babel({:try_catch, _meta, [block, handler, finalizer]}) do
    with {:ok, block_b} <- to_babel_body(block),
         {:ok, handler_b} <- if(handler, do: to_babel(handler), else: {:ok, nil}),
         {:ok, finalizer_b} <- if(finalizer, do: to_babel_body(finalizer), else: {:ok, nil}) do
      {:ok,
       %{
         "type" => "TryStatement",
         "block" => block_b,
         "handler" => handler_b,
         "finalizer" => finalizer_b
       }}
    end
  end

  defp to_babel({:rescue_clause, _meta, [param, body]}) do
    with {:ok, param_b} <- if(param, do: to_babel(param), else: {:ok, nil}),
         {:ok, body_b} <- to_babel_body(body) do
      {:ok,
       %{
         "type" => "CatchClause",
         "param" => param_b,
         "body" => body_b
       }}
    end
  end

  defp to_babel({:throw, _meta, [arg]}) do
    with {:ok, arg_b} <- to_babel(arg) do
      {:ok, %{"type" => "ThrowStatement", "argument" => arg_b}}
    end
  end

  # ES Modules / Imports / Exports
  defp to_babel({:import, meta, _}) do
    source = meta[:source] || ""
    specifiers = meta[:specifiers] || []

    spec_nodes =
      Enum.map(specifiers, fn
        {:default, name} ->
          %{
            "type" => "ImportDefaultSpecifier",
            "local" => %{"type" => "Identifier", "name" => name}
          }

        {:namespace, name} ->
          %{
            "type" => "ImportNamespaceSpecifier",
            "local" => %{"type" => "Identifier", "name" => name}
          }

        {:named, imported, local} ->
          %{
            "type" => "ImportSpecifier",
            "imported" => %{"type" => "Identifier", "name" => imported},
            "local" => %{"type" => "Identifier", "name" => local}
          }

        _ ->
          nil
      end)
      |> Enum.reject(&is_nil/1)

    {:ok,
     %{
       "type" => "ImportDeclaration",
       "specifiers" => spec_nodes,
       "source" => %{"type" => "StringLiteral", "value" => source}
     }}
  end

  defp to_babel({:export, meta, children}) do
    type = meta[:export_type] || :named

    if type == :default and match?([_ | _], children) do
      with {:ok, decl_b} <- to_babel(hd(children)) do
        {:ok, %{"type" => "ExportDefaultDeclaration", "declaration" => decl_b}}
      end
    else
      with {:ok, decls_b} <- to_babel_list(children) do
        decl = Enum.at(decls_b, 0)
        {:ok, %{"type" => "ExportNamedDeclaration", "declaration" => decl, "specifiers" => []}}
      end
    end
  end

  # Collections & Objects
  defp to_babel({:collection, meta, elements}) do
    with {:ok, babel_elements} <- to_babel_list(elements) do
      if meta[:subtype] == :map do
        {:ok, %{"type" => "ObjectExpression", "properties" => babel_elements}}
      else
        {:ok, %{"type" => "ArrayExpression", "elements" => babel_elements}}
      end
    end
  end

  defp to_babel({:pair, _meta, [{:literal, _, key}, val]}) do
    with {:ok, val_b} <- to_babel(val) do
      {:ok,
       %{
         "type" => "ObjectProperty",
         "key" => %{"type" => "Identifier", "name" => to_string(key)},
         "value" => val_b
       }}
    end
  end

  # Native & TypeScript fallback
  defp to_babel({:language_specific, _meta, native_ast}) when is_map(native_ast) do
    {:ok, native_ast}
  end

  defp to_babel(other) do
    {:ok, %{"type" => "Identifier", "name" => inspect(other)}}
  end

  # Private Helpers

  defp to_babel_list(nodes) when is_list(nodes) do
    results =
      Enum.reduce_while(nodes, {:ok, []}, fn node, {:ok, acc} ->
        case to_babel(node) do
          {:ok, babel_node} -> {:cont, {:ok, [babel_node | acc]}}
          {:error, _} = err -> {:halt, err}
        end
      end)

    case results do
      {:ok, list} -> {:ok, Enum.reverse(list)}
      err -> err
    end
  end

  defp to_babel_body({:block, _, stmts}) do
    with {:ok, babel_stmts} <- to_babel_list(stmts) do
      wrapped = Enum.map(babel_stmts, &wrap_statement/1)
      {:ok, %{"type" => "BlockStatement", "body" => wrapped}}
    end
  end

  defp to_babel_body(single_stmt) do
    with {:ok, babel_stmt} <- to_babel(single_stmt) do
      if babel_stmt["type"] == "BlockStatement" do
        {:ok, babel_stmt}
      else
        {:ok, %{"type" => "BlockStatement", "body" => [wrap_statement(babel_stmt)]}}
      end
    end
  end

  defp wrap_statement(node) when is_map(node) do
    type = node["type"]

    if String.ends_with?(type, "Statement") or String.ends_with?(type, "Declaration") or
         type in [
           "TryStatement",
           "IfStatement",
           "WhileStatement",
           "ForStatement",
           "ForOfStatement",
           "ForInStatement",
           "BlockStatement"
         ] do
      node
    else
      %{"type" => "ExpressionStatement", "expression" => node}
    end
  end

  defp unparse_binary_op(:+), do: "+"
  defp unparse_binary_op(:-), do: "-"
  defp unparse_binary_op(:*), do: "*"
  defp unparse_binary_op(:/), do: "/"
  defp unparse_binary_op(:rem), do: "%"
  defp unparse_binary_op(:pow), do: "**"
  defp unparse_binary_op(:==), do: "=="
  defp unparse_binary_op(:===), do: "==="
  defp unparse_binary_op(:!=), do: "!="
  defp unparse_binary_op(:!==), do: "!=="
  defp unparse_binary_op(:<), do: "<"
  defp unparse_binary_op(:>), do: ">"
  defp unparse_binary_op(:<=), do: "<="
  defp unparse_binary_op(:>=), do: ">="
  defp unparse_binary_op(:bsl), do: "<<"
  defp unparse_binary_op(:bsr), do: ">>"
  defp unparse_binary_op(:band), do: "&"
  defp unparse_binary_op(:bor), do: "|"
  defp unparse_binary_op(:bxor), do: "^"
  defp unparse_binary_op(op), do: to_string(op)

  defp unparse_logical_op(:and), do: "&&"
  defp unparse_logical_op(:or), do: "||"
  defp unparse_logical_op(:nullish_coalesce), do: "??"
  defp unparse_logical_op(op), do: to_string(op)

  defp unparse_unary_op(:not), do: "!"
  defp unparse_unary_op(:-), do: "-"
  defp unparse_unary_op(:+), do: "+"
  defp unparse_unary_op(:typeof), do: "typeof"
  defp unparse_unary_op(:delete), do: "delete"
  defp unparse_unary_op(op), do: to_string(op)

  defp unparse_assignment_op(:=), do: "="
  defp unparse_assignment_op(:"+="), do: "+="
  defp unparse_assignment_op(:"-="), do: "-="
  defp unparse_assignment_op(:"*="), do: "*="
  defp unparse_assignment_op(:"/="), do: "/="
  defp unparse_assignment_op(op), do: to_string(op)
end
