defmodule Metastatic.Adapters.Go.FromMeta do
  import Kernel, except: [node: 1]

  @moduledoc """
  Reifies MetaAST into the Go bridge's tagged JSON contract.

  Every child is rebuilt recursively. Only unchanged primitive literal spelling
  is restored from preservation metadata; an original file is never replayed.
  """

  @operators %{
    :+ => "+",
    :- => "-",
    :* => "*",
    :/ => "/",
    :rem => "%",
    :== => "==",
    :!= => "!=",
    :< => "<",
    :> => ">",
    :<= => "<=",
    :>= => ">=",
    :and => "&&",
    :or => "||",
    :not => "!",
    :band => "&",
    :bor => "|",
    :bxor => "^",
    :bnot => "^",
    :band_not => "&^",
    :bsl => "<<",
    :bsr => ">>"
  }

  @doc """
  Converts MetaAST to a Go M1 node, returning errors for unsupported syntax.

      iex> {:ok, node} = Metastatic.Adapters.Go.FromMeta.transform({:variable, [], "x"})
      iex> node["kind"]
      "Ident"
  """
  @spec transform(Metastatic.AST.meta_ast(), map()) :: {:ok, map()} | {:error, String.t()}
  def transform(ast, metadata \\ %{}) do
    _ = metadata

    if Metastatic.AST.conforms?(ast) do
      try do
        {:ok, convert(ast)}
      rescue
        error in [ArgumentError, FunctionClauseError, MatchError] ->
          {:error, "Invalid MetaAST for Go: #{Exception.message(error)}"}
      catch
        {:go_reification, reason} -> {:error, reason}
      end
    else
      {:error, "Cannot reify a non-conforming MetaAST as Go"}
    end
  end

  defp convert({type, meta, value}) do
    base = meta[:original_go] || node(default_kind(type, meta))
    base = recursive_field(base, "type_node", meta[:go_type])
    base = recursive_field(base, "pattern", meta[:go_pattern])
    reify(type, meta, value, base)
  end

  defp reify(:variable, _, name, base),
    do: base |> kind("Ident") |> Map.put("name", to_string(name))

  defp reify(:literal, meta, value, base) do
    case meta[:subtype] do
      :null ->
        base |> kind("Ident") |> Map.put("name", "nil")

      :boolean ->
        base |> kind("Ident") |> Map.put("name", to_string(value))

      :bytes when is_binary(value) ->
        if meta[:go_kind] == "BasicLit" and meta[:go_baseline] === value do
          base
        else
          base
          |> kind("BasicLit")
          |> Map.put("value_type", "string")
          |> Map.put("value", "")
          |> drop_lexical()
          |> extra("value_bytes_base64", Base.encode64(value))
        end

      subtype when subtype in [:integer, :float, :string, :char] ->
        literal_type = %{integer: "int", float: "float", string: "string", char: "char"}[subtype]

        if meta[:go_kind] == "BasicLit" and meta[:go_baseline] === value and
             base["value_type"] == literal_type do
          base
        else
          base
          |> kind("BasicLit")
          |> Map.put("value_type", literal_type)
          |> Map.put("value", value)
          |> drop_lexical()
        end

      _ ->
        fail("Unsupported Go literal subtype: #{inspect(meta[:subtype])}")
    end
  end

  defp reify(type, meta, children, base) when type in [:binary_op, :unary_op] do
    base
    |> kind(if(type == :binary_op, do: "BinaryExpr", else: "UnaryExpr"))
    |> Map.put("name", operator(meta[:operator]))
    |> put_children(children)
  end

  defp reify(:attribute_access, meta, children, base),
    do:
      base |> kind("SelectorExpr") |> Map.put("name", meta[:attribute]) |> put_children(children)

  defp reify(:function_call, meta, args, base) do
    if meta[:go_index] do
      base |> kind("IndexExpr") |> put_children(args)
    else
      callee =
        if meta[:go_callee] && meta[:name] == meta[:go_call_name],
          do: convert(meta[:go_callee]),
          else: callee(meta[:name])

      base
      |> kind("CallExpr")
      |> Map.put("variadic", meta[:variadic] || false)
      |> Map.put("children", [callee | Enum.map(args, &convert/1)])
    end
  end

  defp reify(:pair, _, children, base), do: base |> kind("KeyValueExpr") |> put_children(children)

  defp reify(type, _meta, children, base) when type in [:list, :map] do
    if base["type_node"] do
      base |> kind("CompositeLit") |> put_children(children)
    else
      fail("Go #{type} literal requires a Go type annotation")
    end
  end

  defp reify(:container, meta, children, base) do
    case {meta[:go_kind], meta[:container_type]} do
      {"File", _} ->
        file(base, meta, children)

      {nil, :module} ->
        file(base, meta, children)

      {"CompositeLit", _} ->
        base =
          if meta[:name] != (base["value_type"] || "") do
            base
            |> Map.put("type_node", callee(meta[:name]))
            |> Map.put("value_type", meta[:name])
          else
            base
          end

        put_children(base, children)

      {_, :struct} ->
        base |> kind("StructType") |> put_children(children)

      {_, :interface} ->
        base |> kind("InterfaceType") |> put_children(children)

      _ ->
        fail("Unsupported Go container: #{inspect(meta[:container_type])}")
    end
  end

  defp reify(type, meta, body, base) when type in [:function_def, :lambda] do
    params = parameter_fields(meta[:params] || [])
    others = Enum.map(meta[:go_signature] || [], &convert/1)

    {before_params, after_params} =
      Enum.split_with(others, &(get_in(&1, ["extra", "role"]) in ["Receiver", "TypeParam"]))

    signature = before_params ++ params ++ after_params

    if type == :function_def do
      base
      |> kind("FuncDecl")
      |> Map.put("name", meta[:name])
      |> extra("has_body", body != [] or get_in(base, ["extra", "has_body"]) != false)
      |> Map.put("children", signature ++ Enum.map(body, &convert/1))
    else
      function_type =
        case meta[:go_function_type] do
          {_, type_meta, _} -> type_meta[:original_go] || node("FuncType")
          _ -> node("FuncType")
        end
        |> Map.put("children", signature)

      base
      |> kind("FuncLit")
      |> Map.put("children", [function_type, node("BlockStmt") |> put_children(body)])
    end
  end

  defp reify(:property, meta, types, base) do
    names = Enum.map(meta[:go_names] || [], &convert/1)

    names =
      case names do
        [first | rest] -> [Map.put(first, "name", meta[:name]) | rest]
        [] -> []
      end

    base
    |> kind("Field")
    |> Map.put("name", meta[:name])
    |> Map.put("children", names)
    |> Map.delete("type_node")
    |> maybe_type(types)
  end

  defp reify(:type_annotation, meta, types, base) do
    if meta[:annotation_type] == :type and is_binary(meta[:name]) do
      base
      |> kind("TypeSpec")
      |> Map.put("name", meta[:name])
      |> put_children(meta[:go_type_params] || [])
      |> Map.delete("type_node")
      |> maybe_type(types)
    else
      fail("Go supports named type declarations, not this type annotation")
    end
  end

  defp reify(:import, meta, [], base) do
    base
    |> kind("ImportSpec")
    |> Map.put("name", meta[:source])
    |> extra("alias", meta[:alias])
  end

  defp reify(:block, meta, children, base) do
    allowed = [
      "ImportDecl",
      "VarDecl",
      "ConstDecl",
      "TypeDecl",
      "DeclStmt",
      "BlockStmt",
      "CaseBody",
      "EmptyStmt",
      "ParenExpr"
    ]

    kind = if meta[:go_kind] in allowed, do: meta[:go_kind], else: "BlockStmt"
    base |> kind(kind) |> put_children(children)
  end

  defp reify(:assignment, meta, [left, right], base) do
    names = sequence(left)
    values = sequence(right)

    if meta[:declaration] do
      base
      |> kind("ValueSpec")
      |> Map.put("mutable", meta[:mutable] || false)
      |> Map.put("name", first_name(names))
      |> extra("name_count", length(names))
      |> put_children(names ++ values)
    else
      base
      |> kind("AssignStmt")
      |> Map.put("name", meta[:go_token] || "=")
      |> Map.put("mutable", meta[:go_token] == ":=")
      |> extra("lhs_count", length(names))
      |> assign_children(names, values)
    end
  end

  defp reify(:augmented_assignment, meta, [left, right], base) do
    if meta[:go_increment] && match?({:literal, _, 1}, right) && meta[:operator] in [:+, :-] do
      base
      |> kind("IncDecStmt")
      |> Map.put("name", if(meta[:operator] == :+, do: "++", else: "--"))
      |> put_children([left])
    else
      base
      |> kind("AssignStmt")
      |> Map.put("name", operator(meta[:operator]) <> "=")
      |> extra("lhs_count", 1)
      |> assign_children([left], [right])
    end
  end

  defp reify(:conditional, meta, [condition, body, alternative], base) do
    children = Enum.reject([meta[:go_init], condition, body, alternative], &is_nil/1)

    base
    |> kind("IfStmt")
    |> extra("has_init", not is_nil(meta[:go_init]))
    |> extra("has_else", not is_nil(alternative))
    |> put_children(children)
  end

  defp reify(:loop, meta, children, base) do
    case {meta[:loop_type], children} do
      {:infinite, [body]} ->
        base
        |> kind("ForStmt")
        |> Map.put("children", [node("Absent"), node("Absent"), node("Absent"), convert(body)])

      {:while, [condition, body]} ->
        base
        |> kind("ForStmt")
        |> Map.put("children", [node("Absent"), convert(condition), node("Absent"), convert(body)])

      {:for, [init, condition, post, body]} ->
        base
        |> kind("ForStmt")
        |> Map.put(
          "children",
          Enum.map([init, condition, post], fn
            nil -> node("Absent")
            ast -> convert(ast)
          end) ++ [convert(body)]
        )

      {:for_each, [binding, collection, body]} ->
        names = sequence(binding)
        if length(names) > 2, do: fail("Go range accepts at most two bindings")
        base = Map.delete(base, "pattern")
        base = if names == [], do: base, else: Map.put(base, "pattern", convert(hd(names)))
        values = Enum.drop(names, 1)

        base
        |> kind("RangeStmt")
        |> Map.put("mutable", meta[:mutable] || false)
        |> extra("has_value", values != [])
        |> put_children(values ++ [collection, body])

      _ ->
        fail("Unsupported Go loop shape")
    end
  end

  defp reify(type, meta, children, base) when type in [:early_return, :return] do
    if meta[:kind] in [:break, :continue] do
      base
      |> kind("BranchStmt")
      |> Map.put("name", to_string(meta[:kind]))
      |> extra("label", meta[:label])
    else
      values =
        case children do
          [] -> []
          [value] -> sequence(value)
        end

      base |> kind("ReturnStmt") |> put_children(values)
    end
  end

  defp reify(:labeled, meta, children, base),
    do: base |> kind("LabeledStmt") |> Map.put("name", meta[:label]) |> put_children(children)

  defp reify(:async_operation, meta, children, base) do
    if meta[:op_type] == :async,
      do: base |> kind("GoStmt") |> put_children(children),
      else: fail("Unsupported Go async operation")
  end

  defp reify(:pattern_match, meta, [subject | arms], base) do
    if meta[:go_kind] == "SwitchStmt" do
      children = Enum.reject([meta[:go_init]], &is_nil/1)
      has_tag = meta[:go_has_tag] || not match?({:literal, [subtype: :boolean], true}, subject)
      children = if has_tag, do: children ++ [subject], else: children

      base
      |> kind("SwitchStmt")
      |> extra("has_tag", has_tag)
      |> extra("has_init", not is_nil(meta[:go_init]))
      |> put_children(children ++ arms)
    else
      fail("Only Go switch pattern matching is supported")
    end
  end

  defp reify(:match_arm, meta, body, base) do
    patterns = if meta[:pattern] == :_, do: [], else: sequence(meta[:pattern])

    base
    |> kind("CaseClause")
    |> put_children(patterns)
    |> extra("default", meta[:pattern] == :_)
    |> Map.put("pattern", node("CaseBody") |> put_children(body))
  end

  defp reify(:language_specific, meta, children, base) when is_list(children) do
    if meta[:language] == :go && is_binary(meta[:go_kind]) && is_map(meta[:original_go]),
      do: put_children(base, children),
      else: fail("Native payload is not a preserved Go node")
  end

  defp reify(type, _, _, _), do: fail("Unsupported MetaAST node for Go: #{inspect(type)}")

  defp parameter_fields(params) do
    params
    |> Enum.chunk_by(fn {:param, meta, _} ->
      {meta[:go_group], meta[:type], meta[:kind], meta[:go_unnamed]}
    end)
    |> Enum.flat_map(fn group ->
      if match?([{:param, meta, _} | _] when is_list(meta), group) do
        [{:param, first_meta, _} | _] = group

        if first_meta[:go_group] == nil,
          do: Enum.map(group, &parameter_field([&1])),
          else: [parameter_field(group)]
      else
        fail("Expected Go function parameters")
      end
    end)
  end

  defp parameter_field([{:param, meta, _} | _] = params) do
    if Enum.any?(params, fn {:param, parameter_meta, _} -> parameter_meta[:default] != nil end),
      do: fail("Go parameters cannot have default values")

    base =
      case meta[:go_field] do
        {:property, field_meta, _} -> field_meta[:original_go] || node("Field")
        _ -> node("Field") |> extra("role", "Param")
      end

    type = meta[:type] || fail("Go parameter requires a type")
    type_node = convert(type)

    type_node =
      case {meta[:kind], type_node} do
        {:variadic, %{"kind" => "Ellipsis"}} -> type_node
        {:variadic, _} -> node("Ellipsis") |> Map.put("children", [type_node])
        {_, %{"kind" => "Ellipsis", "children" => [element]}} -> element
        _ -> type_node
      end

    names =
      if meta[:go_unnamed],
        do: [],
        else:
          Enum.map(params, fn {:param, _, name} ->
            node("Ident") |> Map.put("name", to_string(name))
          end)

    base
    |> Map.put("children", names)
    |> Map.put("type_node", type_node)
    |> Map.put("name", if(names == [], do: base["name"] || "", else: hd(names)["name"]))
    |> Map.put("variadic", meta[:kind] == :variadic)
  end

  defp file(base, meta, children) do
    declarations = Enum.map(children, &convert/1)

    imports =
      Enum.flat_map(declarations, fn
        %{"kind" => "ImportDecl"} = declaration -> declaration["children"] || []
        %{"kind" => "ImportSpec"} = spec -> [spec]
        _ -> []
      end)

    declarations =
      Enum.map(declarations, fn
        %{"kind" => "ImportSpec"} = spec -> node("ImportDecl") |> Map.put("children", [spec])
        declaration -> declaration
      end)

    base
    |> kind("File")
    |> Map.put("package", meta[:name])
    |> Map.put("children", declarations)
    |> Map.put("imports", imports)
  end

  defp assign_children(base, names, values) do
    base = base |> Map.delete("pattern") |> put_children(names ++ values)
    if match?([_], names), do: Map.put(base, "pattern", convert(hd(names))), else: base
  end

  defp sequence({:tuple, meta, elements} = ast) do
    if meta[:go_sequence], do: elements, else: [ast]
  end

  defp sequence(ast), do: [ast]

  defp first_name([{:variable, _, name} | _]), do: name
  defp first_name(_), do: ""
  defp maybe_type(base, []), do: base
  defp maybe_type(base, [type]), do: Map.put(base, "type_node", convert(type))
  defp maybe_type(_, _), do: fail("Go field requires exactly one type")

  defp recursive_field(base, _, nil), do: base
  defp recursive_field(base, key, ast), do: Map.put(base, key, convert(ast))
  defp put_children(base, children), do: Map.put(base, "children", Enum.map(children, &convert/1))
  defp kind(base, kind), do: Map.put(base, "kind", kind)

  defp node(kind),
    do: %{"kind" => kind, "span" => %{"line" => 0, "col" => 0, "end_line" => 0, "end_col" => 0}}

  defp extra(base, key, nil), do: Map.update(base, "extra", %{}, &Map.delete(&1, key))

  defp extra(base, key, value),
    do: Map.update(base, "extra", %{key => value}, &Map.put(&1, key, value))

  defp drop_lexical(base),
    do:
      Map.update(
        base,
        "extra",
        %{},
        &Map.drop(&1, ["raw", "original_value", "value_bytes_base64"])
      )

  defp callee(name) when is_binary(name) do
    case String.split(name, ".") do
      [first | rest] when first != "" ->
        Enum.reduce(rest, node("Ident") |> Map.put("name", first), fn selector, receiver ->
          node("SelectorExpr") |> Map.put("name", selector) |> Map.put("children", [receiver])
        end)

      _ ->
        fail("Invalid Go function name")
    end
  end

  defp operator(operator),
    do: @operators[operator] || fail("Unsupported Go operator: #{inspect(operator)}")

  defp default_kind(:variable, _), do: "Ident"
  defp default_kind(:literal, _), do: "BasicLit"
  defp default_kind(:block, _), do: "BlockStmt"
  defp default_kind(_, meta), do: meta[:go_kind] || "Unknown"
  defp fail(reason), do: throw({:go_reification, reason})
end
