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
  #
  # A bare `:block` at the top of a reification is a module body. A block with
  # `scope: :sequence` is the comma operator and is handled by the clause near
  # the collections section, which must therefore be matched first.
  defp to_babel({:block, meta, statements}) when is_list(statements) do
    if meta[:scope] == :sequence do
      to_babel_sequence(statements)
    else
      to_babel_program(statements)
    end
  end

  # Literals
  #
  # A template string with interpolations is handled by the list clause below,
  # so it is excluded here. A template with no interpolations is a plain
  # string and falls through to the `:string` branch of the generic clause.
  defp to_babel({:literal, meta, val}) when not is_list(val) do
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

  # A template literal with interpolations: `quasis` holds the literal
  # fragments (n + 1 of them for n expressions) and the children are the
  # expressions.
  defp to_babel({:literal, meta, exprs}) when is_list(exprs) do
    if meta[:subtype] == :template_string do
      with {:ok, exprs_b} <- to_babel_list(exprs) do
        quasis = meta[:quasis] || []

        quasi_nodes =
          quasis
          |> pad_quasis(length(exprs) + 1)
          |> Enum.map(fn raw -> template_element(raw) end)

        {:ok,
         %{
           "type" => "TemplateLiteral",
           "quasis" => quasi_nodes,
           "expressions" => exprs_b
         }}
      end
    else
      {:error, "Unsupported list-valued literal: #{inspect(meta[:subtype])}"}
    end
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
      # A tagged template (`tag`a ${b}``) is a call whose argument is the
      # template literal, but Babel spells it as its own node.
      meta[:tagged_template] == true and match?([_, _], children) ->
        [tag, quasi] = children

        with {:ok, tag_b} <- to_babel(tag),
             {:ok, quasi_b} <- to_babel(quasi) do
          {:ok, %{"type" => "TaggedTemplateExpression", "tag" => tag_b, "quasi" => quasi_b}}
        end

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
  defp to_babel({:function_def, meta, body}) do
    name = meta[:name]

    with {:ok, params_babel} <- to_babel_list(meta[:params] || []),
         {:ok, body_babel} <- to_babel_body_from(body) do
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

  defp to_babel({:lambda, meta, body}) do
    with {:ok, params_babel} <- to_babel_list(meta[:params] || []),
         {:ok, body_babel} <- to_babel_body_from(body) do
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
    pattern? = meta[:pattern] == true
    map? = meta[:subtype] == :map

    with {:ok, babel_elements} <- to_babel_list(elements) do
      cond do
        pattern? and map? ->
          {:ok, %{"type" => "ObjectPattern", "properties" => babel_elements}}

        pattern? ->
          {:ok, %{"type" => "ArrayPattern", "elements" => babel_elements}}

        map? ->
          {:ok, %{"type" => "ObjectExpression", "properties" => babel_elements}}

        true ->
          {:ok, %{"type" => "ArrayExpression", "elements" => babel_elements}}
      end
    end
  end

  defp to_babel({:pair, meta, [{:literal, _, key}, val]}) do
    with {:ok, val_b} <- to_babel(val) do
      key_name = to_string(key)
      shorthand? = meta[:shorthand] == true

      # A shorthand property (`{a}`) has one node serving as both key and
      # value; a renamed one (`{a: b}`) has two distinct identifiers.
      value_node =
        if shorthand? and match?(%{"type" => "Identifier"}, val_b),
          do: %{"type" => "Identifier", "name" => key_name},
          else: val_b

      {:ok,
       %{
         "type" => "ObjectProperty",
         "key" => %{"type" => "Identifier", "name" => key_name},
         "value" => value_node,
         "shorthand" => shorthand?
       }}
    end
  end

  # Spread / rest splice. `:expression` is an argument or array element;
  # `:pattern` is a binding rest (`function f(...xs)`, `const [...xs] = ys`).
  defp to_babel({:spread, meta, [inner]}) do
    with {:ok, inner_b} <- to_babel(inner) do
      type = if meta[:context] == :pattern, do: "RestElement", else: "SpreadElement"
      {:ok, %{"type" => type, "argument" => inner_b}}
    end
  end

  # A function parameter. The third element is the binding name; `:pattern`
  # holds a destructuring pattern, `:default` the default expression and
  # `:rest` marks a rest parameter. These compose: `...{a} = {}` is a rest
  # parameter whose binding is a pattern with a default.
  defp to_babel({:param, meta, name}) do
    with {:ok, binding} <- param_binding(meta, name),
         {:ok, binding} <- maybe_rest(meta, binding) do
      maybe_default(meta, binding)
    end
  end

  # `await expr`
  defp to_babel({:async_operation, meta, [operation]}) do
    with {:ok, op_b} <- to_babel(operation) do
      case meta[:op_type] do
        :await -> {:ok, %{"type" => "AwaitExpression", "argument" => op_b}}
        _ -> {:error, "Unsupported async operation for JavaScript: #{inspect(meta[:op_type])}"}
      end
    end
  end

  # `yield expr` / `yield* expr`
  defp to_babel({:yield, meta, children}) do
    case children do
      [] ->
        {:ok,
         %{"type" => "YieldExpression", "argument" => nil, "delegate" => meta[:delegate] || false}}

      [arg] ->
        with {:ok, arg_b} <- to_babel(arg) do
          {:ok,
           %{
             "type" => "YieldExpression",
             "argument" => arg_b,
             "delegate" => meta[:delegate] || false
           }}
        end
    end
  end

  # `switch` -- reified from a `:pattern_match` carrying `style: :switch`.
  defp to_babel({:pattern_match, meta, [subject | arms]}) do
    if meta[:style] == :switch do
      with {:ok, subject_b} <- to_babel(subject),
           {:ok, cases} <- to_babel_switch_cases(arms) do
        {:ok, %{"type" => "SwitchStatement", "discriminant" => subject_b, "cases" => cases}}
      end
    else
      {:error, "JavaScript has no general pattern match; only switch is supported"}
    end
  end

  defp to_babel({:labeled, meta, [body]}) do
    with {:ok, body_b} <- to_babel(body) do
      {:ok,
       %{
         "type" => "LabeledStatement",
         "label" => %{"type" => "Identifier", "name" => meta[:label]},
         "body" => wrap_statement(body_b)
       }}
    end
  end

  defp to_babel({:language_specific, _meta, native_ast}) when is_map(native_ast) do
    {:ok, native_ast}
  end

  defp to_babel(other) do
    {:ok, %{"type" => "Identifier", "name" => inspect(other)}}
  end

  # Private Helpers

  defp param_binding(meta, name) do
    case {Keyword.get(meta, :pattern), name} do
      {nil, name} when is_binary(name) -> {:ok, %{"type" => "Identifier", "name" => name}}
      {nil, _} -> {:error, "A :param needs a binary name or a :pattern"}
      {pattern, _} -> to_babel(pattern)
    end
  end

  defp maybe_rest(meta, binding) do
    if meta[:rest],
      do: {:ok, %{"type" => "RestElement", "argument" => binding}},
      else: {:ok, binding}
  end

  defp maybe_default(meta, binding) do
    case Keyword.get(meta, :default) do
      nil ->
        {:ok, binding}

      default ->
        with {:ok, default_b} <- to_babel(default) do
          {:ok, %{"type" => "AssignmentPattern", "left" => binding, "right" => default_b}}
        end
    end
  end

  defp pad_quasis(quasis, count) do
    quasis ++ List.duplicate("", max(count - length(quasis), 0))
  end

  defp template_element(raw) do
    %{
      "type" => "TemplateElement",
      "value" => %{"raw" => raw, "cooked" => raw},
      "tail" => false
    }
  end

  defp to_babel_program(statements) when is_list(statements) do
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

  defp to_babel_sequence(exprs) do
    with {:ok, exprs_b} <- to_babel_list(exprs) do
      {:ok, %{"type" => "SequenceExpression", "expressions" => exprs_b}}
    end
  end

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

  # Reify `:match_arm` nodes back into Babel `SwitchCase` nodes. A `:_`
  # wildcard pattern is the `default` clause, which Babel spells as `test: nil`.
  defp to_babel_switch_cases(arms) when is_list(arms) do
    results =
      Enum.reduce_while(arms, {:ok, []}, fn
        {:match_arm, meta, body}, {:ok, acc} ->
          with {:ok, test_b} <- switch_case_test(Keyword.get(meta, :pattern)),
               {:ok, body_b} <- to_babel_list(body) do
            wrapped = Enum.map(body_b, &wrap_statement/1)

            {:cont,
             {:ok, [%{"type" => "SwitchCase", "test" => test_b, "consequent" => wrapped} | acc]}}
          else
            {:error, _} = err -> {:halt, err}
          end

        other, _acc ->
          {:halt, {:error, "Expected :match_arm in a switch, got: #{inspect(other)}"}}
      end)

    case results do
      {:ok, cases} -> {:ok, Enum.reverse(cases)}
      err -> err
    end
  end

  defp switch_case_test(:_), do: {:ok, nil}
  defp switch_case_test(nil), do: {:ok, nil}
  defp switch_case_test(pattern), do: to_babel(pattern)
  # A function body is a single-element list holding the body node
  # (`:block` or an expression for concise arrow bodies).
  defp to_babel_body_from([single]), do: to_babel_body(single)
  defp to_babel_body_from([]), do: {:ok, %{"type" => "BlockStatement", "body" => []}}
  defp to_babel_body_from(other), do: to_babel_body(other)

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
