defmodule Metastatic.Adapters.Go.ToMeta do
  @moduledoc """
  Abstracts the Go bridge's tagged JSON nodes into conforming MetaAST.

  Native details are kept in per-node skeletons, never as a replayable whole
  file. Recursive fields remain MetaAST so edits survive reification.
  """

  @operators %{
    "+" => {:arithmetic, :+},
    "-" => {:arithmetic, :-},
    "*" => {:arithmetic, :*},
    "/" => {:arithmetic, :/},
    "%" => {:arithmetic, :rem},
    "==" => {:comparison, :==},
    "!=" => {:comparison, :!=},
    "<" => {:comparison, :<},
    ">" => {:comparison, :>},
    "<=" => {:comparison, :<=},
    ">=" => {:comparison, :>=},
    "&&" => {:boolean, :and},
    "||" => {:boolean, :or},
    "!" => {:boolean, :not},
    "&" => {:bitwise, :band},
    "|" => {:bitwise, :bor},
    "^" => {:bitwise, :bxor},
    "&^" => {:bitwise, :band_not},
    "<<" => {:bitwise, :bsl},
    ">>" => {:bitwise, :bsr}
  }

  @doc """
  Converts a tagged Go M1 node to MetaAST.

      iex> {:ok, {:variable, _, "x"}, %{}} =
      ...>   Metastatic.Adapters.Go.ToMeta.transform(%{"kind" => "Ident", "name" => "x"})
  """
  @spec transform(map()) :: {:ok, Metastatic.AST.meta_ast(), map()} | {:error, String.t()}
  def transform(%{"kind" => _} = node) do
    {:ok, convert(node), %{}}
  rescue
    error in [ArgumentError, FunctionClauseError, MatchError] ->
      {:error, "Invalid Go AST: #{Exception.message(error)}"}
  catch
    {:go_transform, reason} -> {:error, reason}
  end

  def transform(_), do: {:error, "Expected a tagged Go AST node"}

  defp convert(%{"kind" => kind} = node) do
    validate_wire_node(node)

    children =
      node
      |> Map.get("children", [])
      |> Enum.with_index(fn child, index ->
        if binding_child?(node, index), do: convert_binding(child), else: convert(child)
      end)

    meta =
      [
        go_kind: kind,
        original_go: Map.drop(node, ["children", "type_node", "pattern", "imports"])
      ]
      |> optional(:go_type, if(kind not in ["Field", "TypeSpec"], do: node["type_node"]))
      |> optional(
        :go_pattern,
        if(kind not in ["AssignStmt", "RangeStmt", "CaseClause"], do: node["pattern"])
      )
      |> location(node["span"])

    {type, attributes, value} = abstract(kind, node, children)
    meta = Keyword.merge(meta, attributes)

    meta =
      if type in [:container, :function_def, :import, :language_specific],
        do: Keyword.put_new(meta, :language, :go),
        else: meta

    meta = if type == :literal, do: Keyword.put(meta, :go_baseline, value), else: meta
    {type, meta, value}
  end

  defp convert(_), do: fail("Invalid child in Go AST")

  defp abstract("File", node, children) do
    {:container,
     [
       container_type: :module,
       name: node["package"] || "main",
       module: node["package"] || "main"
     ], children}
  end

  defp abstract("Ident", %{"name" => name, "extra" => %{"bound" => true}}, _),
    do: {:variable, [scope: :local], name}

  defp abstract("Ident", %{"name" => "nil"}, _), do: {:literal, [subtype: :null], nil}
  defp abstract("Ident", %{"name" => "true"}, _), do: {:literal, [subtype: :boolean], true}
  defp abstract("Ident", %{"name" => "false"}, _), do: {:literal, [subtype: :boolean], false}
  defp abstract("Ident", node, _), do: {:variable, [scope: :local], node["name"] || "_"}

  defp abstract("BasicLit", node, _) do
    bytes = get_in(node, ["extra", "value_bytes_base64"])

    if node["value_type"] == "string" and is_binary(bytes) do
      case Base.decode64(bytes) do
        {:ok, value} -> {:literal, [subtype: :bytes], value}
        :error -> fail("Invalid base64 Go string literal")
      end
    else
      basic_literal(node)
    end
  end

  defp abstract("BinaryExpr", node, [left, right]) do
    {category, operator} = operator(node["name"])
    {:binary_op, [category: category, operator: operator], [left, right]}
  end

  defp abstract("UnaryExpr", %{"name" => name}, [child]) when name in ["!", "-", "+", "^"] do
    {category, operator} = if name == "^", do: {:bitwise, :bnot}, else: operator(name)
    {:unary_op, [category: category, operator: operator], [child]}
  end

  defp abstract("SelectorExpr", node, children),
    do: {:attribute_access, [attribute: node["name"] || ""], children}

  defp abstract("CallExpr", node, [callee | arguments]) do
    {:function_call,
     [
       name: call_name(callee),
       go_callee: callee,
       go_call_name: call_name(callee),
       variadic: node["variadic"] || false
     ], arguments}
  end

  defp abstract("KeyValueExpr", _, children), do: {:pair, [], children}

  defp abstract("IndexExpr", _, children),
    do: {:function_call, [name: "[]", go_index: true], children}

  defp abstract("CompositeLit", node, children) do
    case node["type_node"] do
      %{"kind" => "ArrayType"} -> {:list, [], children}
      %{"kind" => "MapType"} -> {:map, [], children}
      _ -> {:container, [container_type: :struct, name: node["value_type"] || ""], children}
    end
  end

  defp abstract(kind, node, children) when kind in ["FuncDecl", "FuncLit"] do
    {signature, body} =
      if kind == "FuncDecl" do
        Enum.split_while(children, &(elem(&1, 1)[:go_kind] == "Field"))
      else
        case children do
          [{:language_specific, _, fields}, {:block, _, statements}] -> {fields, statements}
          _ -> fail("Invalid Go function literal")
        end
      end

    {parameter_fields, other_fields} =
      Enum.split_with(
        signature,
        &(get_in(elem(&1, 1)[:original_go], ["extra", "role"]) == "Param")
      )

    params =
      parameter_fields
      |> Enum.with_index()
      |> Enum.flat_map(fn {field, group} -> parameters(field, group) end)

    attributes = [
      params: params,
      arity: length(params),
      go_signature: other_fields,
      go_function_type:
        if(kind == "FuncLit",
          do: {:language_specific, Keyword.take(elem(hd(children), 1), [:original_go]), []},
          else: nil
        )
    ]

    if kind == "FuncDecl" do
      name = node["name"] || ""

      {:function_def, attributes ++ [name: name, function: name, visibility: visibility(name)],
       body}
    else
      {:lambda, attributes, body}
    end
  end

  defp abstract("Field", node, children) do
    {:property, [name: node["name"] || "", go_names: children],
     if(node["type_node"], do: [convert(node["type_node"])], else: [])}
  end

  defp abstract(kind, _, children) when kind in ["StructType", "InterfaceType"] do
    {:container,
     [container_type: if(kind == "StructType", do: :struct, else: :interface), name: ""],
     children}
  end

  defp abstract("TypeSpec", node, children) do
    {:type_annotation,
     [annotation_type: :type, name: node["name"] || "", go_type_params: children],
     if(node["type_node"], do: [convert(node["type_node"])], else: [])}
  end

  defp abstract("ImportSpec", node, _) do
    {:import, [source: node["name"] || "", alias: get_in(node, ["extra", "alias"])], []}
  end

  defp abstract(kind, _, children)
       when kind in [
              "ImportDecl",
              "VarDecl",
              "ConstDecl",
              "TypeDecl",
              "DeclStmt",
              "BlockStmt",
              "CaseBody",
              "EmptyStmt",
              "ParenExpr"
            ] do
    {:block, [], children}
  end

  defp abstract("ValueSpec", node, children) do
    count = get_in(node, ["extra", "name_count"]) || infer_names(node)
    {names, values} = Enum.split(children, count)

    {:assignment,
     [declaration: true, mutable: Map.get(node, "mutable", false), go_names_count: count],
     [pack(names), pack(values)]}
  end

  defp abstract("AssignStmt", node, children) do
    count = get_in(node, ["extra", "lhs_count"]) || if(node["pattern"], do: 1, else: 0)
    if count < 1, do: fail("AssignStmt requires extra.lhs_count for multiple targets")
    {left, right} = Enum.split(children, count)
    token = node["name"] || "="

    if token in ["=", ":="] do
      {:assignment, [operator: :=, go_token: token, go_names_count: count],
       [pack(left), pack(right)]}
    else
      base = String.trim_trailing(token, "=")
      {category, operator} = operator(base)

      {:augmented_assignment, [category: category, operator: operator, go_token: token],
       [pack(left), pack(right)]}
    end
  end

  defp abstract("IncDecStmt", node, [target]) do
    {:augmented_assignment,
     [
       category: :arithmetic,
       operator: if(node["name"] == "++", do: :+, else: :-),
       go_increment: true
     ], [target, {:literal, [subtype: :integer], 1}]}
  end

  defp abstract("ReturnStmt", _, []), do: {:early_return, [], []}
  defp abstract("ReturnStmt", _, children), do: {:early_return, [], [pack(children)]}

  defp abstract("IfStmt", node, children) do
    {init, rest} =
      if get_in(node, ["extra", "has_init"]) do
        {hd(children), tl(children)}
      else
        {nil, children}
      end

    case rest do
      [condition, body | tail] ->
        {:conditional, [go_init: init], [condition, body, List.first(tail)]}

      _ ->
        fail("Invalid IfStmt child boundaries")
    end
  end

  defp abstract("ForStmt", _, [init, condition, post, body]) do
    absent? = fn {_, meta, _} -> meta[:go_kind] == "Absent" end

    cond do
      absent?.(init) and absent?.(condition) and absent?.(post) ->
        {:loop, [loop_type: :infinite], [body]}

      absent?.(init) and absent?.(post) ->
        {:loop, [loop_type: :while], [condition, body]}

      true ->
        {:loop, [loop_type: :for], [init, condition, post, body]}
    end
  end

  defp abstract("RangeStmt", node, children) do
    {value, collection, body} =
      case children do
        [value, collection, body] -> {value, collection, body}
        [collection, body] -> {nil, collection, body}
        _ -> fail("Invalid RangeStmt")
      end

    names =
      Enum.reject([if(node["pattern"], do: convert_binding(node["pattern"])), value], &is_nil/1)

    {:loop, [loop_type: :for_each, go_range: true, mutable: node["mutable"] || false],
     [pack(names), collection, body]}
  end

  defp abstract("BranchStmt", %{"name" => name} = node, _)
       when name in ["break", "continue"] do
    {:early_return,
     [
       kind: if(name == "break", do: :break, else: :continue),
       label: get_in(node, ["extra", "label"])
     ], []}
  end

  defp abstract("LabeledStmt", node, children),
    do: {:labeled, [label: node["name"] || ""], children}

  defp abstract("GoStmt", _, children), do: {:async_operation, [op_type: :async], children}

  defp abstract("SwitchStmt", node, children) do
    {init, children} =
      if get_in(node, ["extra", "has_init"]),
        do: {hd(children), tl(children)},
        else: {nil, children}

    {subject, arms} =
      if get_in(node, ["extra", "has_tag"]),
        do: {hd(children), tl(children)},
        else: {{:literal, [subtype: :boolean], true}, children}

    {:pattern_match, [go_init: init, go_has_tag: get_in(node, ["extra", "has_tag"]) || false],
     [subject | arms]}
  end

  defp abstract("CaseClause", node, children) do
    pattern = if get_in(node, ["extra", "default"]), do: :_, else: pack(children)
    body = if node["pattern"], do: elem(convert(node["pattern"]), 2), else: []
    {:match_arm, [pattern: pattern], body}
  end

  defp abstract(_kind, _, children), do: {:language_specific, [], children}

  defp basic_literal(node) do
    case {node["value_type"], node["value"]} do
      {"int", value} -> {:literal, [subtype: :integer], integer(value || 0)}
      {"float", value} when is_number(value) -> {:literal, [subtype: :float], value / 1}
      {"string", value} -> {:literal, [subtype: :string], value || ""}
      {"char", value} -> {:literal, [subtype: :char], value || ""}
      _ -> {:language_specific, [hint: :go_literal], []}
    end
  end

  defp parameters({:property, meta, types}, group) do
    names = meta[:go_names] || []

    names = if names == [], do: [{:variable, [], meta[:name] || "_"}], else: names

    Enum.with_index(names, fn {:variable, _, name}, index ->
      {:param,
       [
         go_field: {:property, meta, []},
         go_group: group,
         go_name_index: index,
         go_unnamed: meta[:go_names] == [],
         type: List.first(types),
         kind: if(meta[:original_go]["variadic"], do: :variadic, else: :positional)
       ], name}
    end)
  end

  defp pack([single]), do: single
  defp pack(nodes), do: {:tuple, [go_sequence: true], nodes}

  defp convert_binding(%{"kind" => "Ident", "name" => name} = node) do
    {_, meta, _} = convert(node)
    {:variable, Keyword.drop(meta, [:subtype, :go_baseline]), name}
  end

  defp convert_binding(node), do: convert(node)

  defp binding_child?(%{"kind" => "Field"}, _index), do: true

  defp binding_child?(%{"kind" => "ValueSpec"} = node, index),
    do: index < (get_in(node, ["extra", "name_count"]) || 1)

  defp binding_child?(%{"kind" => "AssignStmt"} = node, index),
    do: index < (get_in(node, ["extra", "lhs_count"]) || if(node["pattern"], do: 1, else: 0))

  defp binding_child?(%{"kind" => "RangeStmt"} = node, index),
    do: index == 0 and get_in(node, ["extra", "has_value"]) == true

  defp binding_child?(_node, _index), do: false

  defp infer_names(%{"children" => [%{"kind" => "Ident"} | _]}), do: 1
  defp infer_names(_), do: fail("ValueSpec requires extra.names_count")

  defp optional(meta, _key, nil), do: meta
  defp optional(meta, key, value), do: Keyword.put(meta, key, convert(value))

  defp location(meta, span) when is_map(span) do
    Enum.reduce(
      [{"line", :line}, {"col", :col}, {"end_line", :end_line}, {"end_col", :end_col}],
      meta,
      fn {wire_key, meta_key}, acc ->
        case span[wire_key] do
          value when is_integer(value) -> Keyword.put(acc, meta_key, value)
          _ -> acc
        end
      end
    )
  end

  defp location(meta, _), do: meta

  defp operator(token) do
    case @operators[token] do
      nil -> fail("Unsupported Go operator #{inspect(token)}")
      operator -> operator
    end
  end

  defp integer(value) when is_integer(value), do: value

  defp integer(value) when is_binary(value) do
    text = String.replace(value, "_", "")

    {digits, base} =
      case text do
        "0x" <> digits -> {digits, 16}
        "0X" <> digits -> {digits, 16}
        "0b" <> digits -> {digits, 2}
        "0B" <> digits -> {digits, 2}
        "0o" <> digits -> {digits, 8}
        "0O" <> digits -> {digits, 8}
        "0" <> digits when digits != "" -> {digits, 8}
        _ -> {text, 10}
      end

    case Integer.parse(digits, base) do
      {number, ""} -> number
      _ -> fail("Invalid Go integer literal")
    end
  end

  defp call_name({:variable, _, name}), do: name

  defp call_name({:attribute_access, meta, [receiver]}),
    do: call_name(receiver) <> "." <> meta[:attribute]

  defp call_name(_), do: "<expression>"

  defp visibility(name) do
    if Regex.match?(~r/^\p{Lu}/u, name), do: :public, else: :private
  end

  defp validate_wire_node(node) do
    unless is_binary(node["kind"]), do: fail("Go AST kind must be a string")

    for {key, predicate} <- [
          {"children", &is_list/1},
          {"extra", &is_map/1},
          {"span", &is_map/1},
          {"type_node", &is_map/1},
          {"pattern", &is_map/1},
          {"imports", &is_list/1}
        ] do
      if Map.has_key?(node, key) and not predicate.(node[key]),
        do: fail("Go AST #{key} has an invalid value")
    end

    if Map.has_key?(node, "imports") and
         not Enum.all?(node["imports"], &match?(%{"kind" => kind} when is_binary(kind), &1)),
       do: fail("Go AST imports must contain tagged nodes")
  end

  defp fail(reason), do: throw({:go_transform, reason})
end
