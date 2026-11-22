defmodule Metastatic.Adapters.GoTransformTest do
  import Kernel, except: [node: 1]

  use ExUnit.Case, async: true

  alias Metastatic.Adapters.Go.{FromMeta, ToMeta}
  alias Metastatic.AST

  doctest ToMeta
  doctest FromMeta

  test "primitive literals conform and keep unchanged lexical spellings" do
    for {subtype, value, raw} <- [
          {"int", 255, "0xff"},
          {"float", 1.5, "0x1.8p0"},
          {"string", "hello", "`hello`"},
          {"char", "λ", "'λ'"}
        ] do
      original =
        node("BasicLit", [], %{
          "value_type" => subtype,
          "value" => value,
          "extra" => %{"raw" => raw, "original_value" => value}
        })

      meta = abstract(original)
      expected = Map.delete(original, "children")
      assert {:ok, ^expected} = FromMeta.transform(meta)
    end

    for name <- ["nil", "true", "false", "x"] do
      assert {:ok, %{"name" => ^name}} = FromMeta.transform(abstract(ident(name)))
    end
  end

  test "parameter kind mutations split groups and remove variadic ellipsis" do
    {:function_def, meta, body} =
      abstract(node("FuncDecl", [field(["a", "b"], "int", "Param")], %{"name" => "f"}))

    [first, {:param, second_meta, second_name}] = meta[:params]
    params = [first, {:param, Keyword.put(second_meta, :kind, :variadic), second_name}]

    assert {:ok, result} =
             FromMeta.transform({:function_def, Keyword.put(meta, :params, params), body})

    assert [first_field, second_field] = result["children"]
    assert first_field["type_node"]["kind"] == "Ident"
    assert second_field["type_node"]["kind"] == "Ellipsis"

    {:function_def, variadic_meta, []} = abstract(result)
    [first_param, {:param, last_meta, name}] = variadic_meta[:params]
    params = [first_param, {:param, Keyword.put(last_meta, :kind, :positional), name}]

    assert {:ok, plain} =
             FromMeta.transform({:function_def, Keyword.put(variadic_meta, :params, params), []})

    assert [_, last_field] = plain["children"]
    assert last_field["type_node"]["kind"] == "Ident"
    refute last_field["variadic"]
  end

  test "binding names can shadow Go predeclared literals" do
    for name <- ["true", "false", "nil"] do
      input = node("FuncDecl", [field([name], "bool", "Param")], %{"name" => "shadow"})
      assert {:function_def, meta, []} = ast = abstract(input)
      assert [{:param, _, ^name}] = meta[:params]

      assert {:ok, %{"children" => [%{"children" => [%{"name" => ^name}]}]}} =
               FromMeta.transform(ast)

      for {kind, count_key} <- [{"AssignStmt", "lhs_count"}, {"ValueSpec", "name_count"}] do
        input =
          node(kind, [ident(name), literal(1)], %{
            "name" => if(kind == "AssignStmt", do: ":=", else: name),
            "extra" => %{count_key => 1}
          })

        assert {:assignment, _, [{:variable, _, ^name}, _]} = abstract(input)
      end

      range =
        node("RangeStmt", [ident(name), ident("xs"), node("BlockStmt")], %{
          "pattern" => ident(name),
          "extra" => %{"has_value" => true}
        })

      assert {:loop, _, [{:tuple, _, [{:variable, _, ^name}, {:variable, _, ^name}]}, _, _]} =
               abstract(range)
    end
  end

  test "bridge-resolved identifiers override predeclared literal interpretation" do
    for name <- ["true", "false", "nil"] do
      input = ident(name) |> Map.put("extra", %{"bound" => true})
      assert {:variable, _, ^name} = ast = abstract(input)
      assert {:ok, %{"kind" => "Ident", "name" => ^name}} = FromMeta.transform(ast)
    end
  end

  test "nested type abstraction has linear preservation size" do
    nested =
      Enum.reduce(1..20, ident("int"), fn _, child ->
        node("StructType", [
          node("Field", [ident("Value")], %{
            "name" => "Value",
            "extra" => %{"role" => "StructField"},
            "type_node" => child
          })
        ])
      end)

    ast = abstract(nested)
    assert :erlang.external_size(ast) < 100_000
    assert {:ok, _} = FromMeta.transform(ast)
  end

  test "Unicode uppercase names are exported and source spans retain standard keys" do
    for name <- ["Écho", "Ωmega", "Hello"] do
      {:function_def, meta, []} =
        abstract(
          node("FuncDecl", [], %{
            "name" => name,
            "span" => %{"line" => 2, "col" => 3, "end_line" => 4, "end_col" => 5}
          })
        )

      assert meta[:visibility] == :public

      assert Keyword.take(meta, [:line, :col, :end_line, :end_col]) |> Map.new() ==
               %{line: 2, col: 3, end_line: 4, end_col: 5}
    end
  end

  test "malformed recursive wire fields return structured errors" do
    for malformed <- [
          %{"kind" => "BlockStmt", "children" => nil},
          %{"kind" => "BlockStmt", "children" => "invalid"},
          %{"kind" => "BlockStmt", "children" => [nil]},
          %{"kind" => "BlockStmt", "extra" => []},
          %{"kind" => "Field", "type_node" => "int"},
          %{"kind" => "Field", "type_node" => %{}},
          %{"kind" => "RangeStmt", "pattern" => []},
          %{"kind" => "File", "imports" => [nil]},
          %{"kind" => nil}
        ] do
      assert {:error, reason} = ToMeta.transform(malformed)
      assert is_binary(reason)
    end
  end

  test "non UTF8 Go strings have byte-accurate semantic values and safe reification" do
    original =
      node("BasicLit", [], %{
        "value_type" => "string",
        "value" => "�",
        "extra" => %{"raw" => "\"\\xff\"", "value_bytes_base64" => "/w=="}
      })

    assert {:literal, meta, <<255>>} = abstract(original)
    assert meta[:subtype] == :bytes
    assert {:ok, unchanged} = FromMeta.transform({:literal, meta, <<255>>})
    assert unchanged["extra"]["raw"] == "\"\\xff\""
    assert {:ok, edited} = FromMeta.transform({:literal, meta, <<254, 0, 255>>})
    assert edited["value"] == ""
    assert Base.decode64!(edited["extra"]["value_bytes_base64"]) == <<254, 0, 255>>
    refute Map.has_key?(edited["extra"], "raw")
    assert {:ok, _} = FromMeta.transform({:literal, [subtype: :bytes], <<255>>})
  end

  test "large and old-style Go integers are conforming numeric literals" do
    for {value, expected} <- [
          {"0xffffffffffffffffffffffffffff", 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF},
          {"0777", 511},
          {"0b1010", 10},
          {"1_000", 1000}
        ] do
      assert {:literal, _, ^expected} =
               abstract(node("BasicLit", [], %{"value_type" => "int", "value" => value}))
    end
  end

  test "changed literals discard stale raw spelling but retain comments" do
    original =
      node("BasicLit", [], %{
        "value_type" => "int",
        "value" => 15,
        "extra" => %{"raw" => "0xf", "original_value" => 15, "before_comments" => ["// value"]}
      })

    {:literal, meta, _} = abstract(original)
    assert {:ok, changed} = FromMeta.transform({:literal, meta, 16})
    assert changed["value"] == 16
    refute Map.has_key?(changed["extra"], "raw")
    assert changed["extra"]["before_comments"] == ["// value"]
  end

  test "operators, selectors, calls and indexing use universal nodes" do
    expression =
      node(
        "BinaryExpr",
        [
          node("CallExpr", [
            node("SelectorExpr", [ident("fmt")], %{"name" => "Println"}),
            literal(1)
          ]),
          node("IndexExpr", [ident("xs"), literal(0)])
        ],
        %{"name" => "+"}
      )

    assert {:binary_op, _, [{:function_call, _, [_]}, {:function_call, _, [_, _]}]} =
             abstract(expression)

    assert {:ok, result} = FromMeta.transform(abstract(expression))
    assert result["name"] == "+"
    assert [call, index] = result["children"]
    assert [selector, _] = call["children"]
    assert selector["name"] == "Println"
    assert index["kind"] == "IndexExpr"
  end

  test "changed call names and argument values are reified" do
    {:function_call, meta, [{:literal, arg_meta, _}]} =
      abstract(node("CallExpr", [ident("before"), literal(1)]))

    edited = {:function_call, Keyword.put(meta, :name, "after"), [{:literal, arg_meta, 2}]}
    assert {:ok, %{"children" => [callee, argument]}} = FromMeta.transform(edited)
    assert callee["name"] == "after"
    assert argument["value"] == 2
  end

  test "files and functions never replay original bodies after edits" do
    original =
      node(
        "File",
        [
          node(
            "FuncDecl",
            [
              field(["a", "b"], "int", "Param"),
              field([], "int", "Result"),
              node("ReturnStmt", [node("BinaryExpr", [ident("a"), ident("b")], %{"name" => "+"})])
            ],
            %{"name" => "Sum", "extra" => %{"has_body" => true}}
          )
        ],
        %{"package" => "example", "extra" => %{"before_comments" => ["// package"]}}
      )

    {:container, file_meta, [{:function_def, function_meta, _}]} = abstract(original)
    assert [{:param, _, "a"}, {:param, _, "b"}] = function_meta[:params]
    assert function_meta[:arity] == 2
    assert function_meta[:visibility] == :public
    refute Map.has_key?(file_meta[:original_go], "children")

    edited =
      {:container, Keyword.put(file_meta, :name, "changed"),
       [
         {:function_def, Keyword.put(function_meta, :name, "Changed"),
          [{:early_return, [], [{:literal, [subtype: :integer], 42}]}]}
       ]}

    assert {:ok, result} = FromMeta.transform(edited)
    assert result["package"] == "changed"
    assert [function] = result["children"]
    assert function["name"] == "Changed"
    assert [params, _, return] = function["children"]
    assert [%{"name" => "a"}, %{"name" => "b"}] = params["children"]
    assert [%{"value" => 42}] = return["children"]
  end

  test "parameter renames and type edits update grouped field nodes" do
    {:function_def, meta, body} =
      abstract(node("FuncDecl", [field(["a", "b"], "int", "Param")], %{"name" => "f"}))

    [{:param, first_meta, _}, {:param, second_meta, _}] = meta[:params]

    params = [
      {:param, first_meta, "left"},
      {:param, Keyword.put(second_meta, :type, {:variable, [], "string"}), "right"}
    ]

    assert {:ok, result} =
             FromMeta.transform({:function_def, Keyword.put(meta, :params, params), body})

    assert [first, second] = result["children"]
    assert first["type_node"]["name"] == "int"
    assert second["type_node"]["name"] == "string"
    assert [%{"name" => "left"}] = first["children"]
    assert [%{"name" => "right"}] = second["children"]
  end

  test "functions retain receivers, generic fields, results, variadic and unnamed params" do
    receiver = field(["self"], "T", "Receiver")
    type_param = field(["T"], "any", "TypeParam")

    variadic =
      field(["rest"], "string", "Param")
      |> Map.put("type_node", node("Ellipsis", [ident("string")]))
      |> Map.put("variadic", true)

    function =
      node(
        "FuncDecl",
        [
          receiver,
          type_param,
          field([], "int", "Param"),
          variadic,
          field(["result"], "error", "Result")
        ],
        %{"name" => "f", "extra" => %{"has_body" => false}}
      )

    assert {:function_def, meta, []} = ast = abstract(function)
    assert [{:param, _, "int"}, {:param, variadic_meta, "rest"}] = meta[:params]
    assert variadic_meta[:kind] == :variadic
    assert {:ok, result} = FromMeta.transform(ast)
    assert [recv, generic, unnamed, rest, output] = result["children"]
    assert recv["extra"]["role"] == "Receiver"
    assert generic["extra"]["role"] == "TypeParam"
    assert unnamed["children"] == []
    assert rest["variadic"]
    assert output["extra"]["role"] == "Result"
    assert result["extra"]["has_body"] == false
  end

  test "lambdas expose their parameters and edited body" do
    lambda =
      node("FuncLit", [
        node("FuncType", [field(["x"], "int", "Param")]),
        node("BlockStmt", [node("ReturnStmt", [ident("x")])])
      ])

    assert {:lambda, meta, [_]} = abstract(lambda)
    assert {:ok, result} = FromMeta.transform({:lambda, meta, [node_return(7)]})
    assert [signature, body] = result["children"]
    assert [%{"kind" => "Field"}] = signature["children"]
    assert [%{"children" => [%{"value" => 7}]}] = body["children"]
  end

  test "multiple assignment and declaration boundaries remain explicit" do
    for kind <- ["AssignStmt", "ValueSpec"] do
      extra = if kind == "AssignStmt", do: %{"lhs_count" => 2}, else: %{"name_count" => 2}

      input =
        node(kind, [ident("a"), ident("b"), literal(1), literal(2)], %{
          "name" => if(kind == "AssignStmt", do: ":=", else: "a"),
          "extra" => extra
        })

      assert {:assignment, meta, [{:tuple, _, [_, _]}, {:tuple, _, [_, _]}]} =
               ast = abstract(input)

      assert meta[:go_names_count] == 2
      assert {:ok, result} = FromMeta.transform(ast)

      assert [%{"name" => "a"}, %{"name" => "b"}, %{"value" => 1}, %{"value" => 2}] =
               result["children"]
    end
  end

  test "typed declarations without initializer remain valid and preserve types" do
    original =
      node("ValueSpec", [ident("x"), ident("y")], %{
        "name" => "x",
        "mutable" => true,
        "type_node" => ident("int"),
        "extra" => %{"name_count" => 2}
      })

    assert {:ok, result} = FromMeta.transform(abstract(original))
    assert result["type_node"]["name"] == "int"
    assert [_, _] = result["children"]
  end

  test "imports are derived from edited declaration children, not duplicate file imports" do
    input =
      node("File", [node("ImportDecl", [node("ImportSpec", [], %{"name" => "fmt"})])], %{
        "package" => "p",
        "imports" => [node("ImportSpec", [], %{"name" => "stale"})]
      })

    {:container, file_meta, [{:block, block_meta, [{:import, import_meta, []}]}]} =
      abstract(input)

    edited =
      {:container, file_meta,
       [{:block, block_meta, [{:import, Keyword.put(import_meta, :source, "io"), []}]}]}

    assert {:ok, result} = FromMeta.transform(edited)
    assert [%{"name" => "io"}] = result["imports"]
  end

  test "conditionals retain init slots and conform with no else" do
    input =
      node(
        "IfStmt",
        [
          node("AssignStmt", [ident("x"), literal(1)], %{
            "name" => ":=",
            "extra" => %{"lhs_count" => 1}
          }),
          ident("ok"),
          node("BlockStmt")
        ],
        %{"extra" => %{"has_init" => true}}
      )

    assert {:conditional, meta, [condition, body, nil]} = abstract(input)
    edited = {:conditional, meta, [condition, body, {:block, [], [node_return(2)]}]}
    assert {:ok, result} = FromMeta.transform(edited)
    assert result["extra"]["has_init"]
    assert result["extra"]["has_else"]
    assert [_, _, _, _] = result["children"]
  end

  test "all for loop forms and range bindings conform and reify" do
    absent = node("Absent")

    for header <- [
          [absent, absent, absent],
          [absent, ident("ok"), absent],
          [ident("init"), ident("ok"), node("IncDecStmt", [ident("i")], %{"name" => "++"})]
        ] do
      input = node("ForStmt", header ++ [node("BlockStmt")])
      assert {:loop, _, _} = ast = abstract(input)
      assert {:ok, result} = FromMeta.transform(ast)
      assert [_, _, _, _] = result["children"]
    end

    for {pattern, values} <- [{nil, []}, {ident("key"), []}, {ident("key"), [ident("value")]}] do
      input =
        node("RangeStmt", values ++ [ident("items"), node("BlockStmt")], %{
          "mutable" => true,
          "extra" => %{"has_value" => values != []}
        })

      input = if pattern, do: Map.put(input, "pattern", pattern), else: input
      assert {:loop, _, [_, _, _]} = ast = abstract(input)
      assert {:ok, result} = FromMeta.transform(ast)
      assert result["extra"]["has_value"] == (values != [])
      assert result["mutable"]
    end
  end

  test "switches and cases use pattern match and match arm nodes" do
    arm =
      node("CaseClause", [literal(1), literal(2)], %{
        "pattern" => node("CaseBody", [node("ReturnStmt")])
      })

    default =
      node("CaseClause", [], %{"extra" => %{"default" => true}, "pattern" => node("CaseBody")})

    input = node("SwitchStmt", [ident("x"), arm, default], %{"extra" => %{"has_tag" => true}})

    assert {:pattern_match, _, [_, {:match_arm, _, [_]}, {:match_arm, _, []}]} =
             ast = abstract(input)

    assert {:ok, result} = FromMeta.transform(ast)
    assert [_, %{"children" => [_, _]}, %{"extra" => %{"default" => true}}] = result["children"]
  end

  test "structs, interfaces and type aliases expose universal containers" do
    for {kind, expected} <- [{"StructType", :struct}, {"InterfaceType", :interface}] do
      input =
        node("TypeSpec", [], %{
          "name" => "Thing",
          "extra" => %{"alias" => true},
          "type_node" => node(kind, [field(["Value"], "int", "StructField")])
        })

      assert {:type_annotation, _, [{:container, meta, [{:property, _, [_]}]}]} =
               ast = abstract(input)

      assert meta[:container_type] == expected
      assert {:ok, result} = FromMeta.transform(ast)
      assert result["extra"]["alias"]
      assert result["type_node"]["kind"] == kind
    end
  end

  test "typed collections preserve their Go types while exposing element edits" do
    for {type, expected} <- [
          {node("ArrayType", [node("Absent"), ident("int")]), :list},
          {node("MapType", [ident("string"), ident("int")]), :map}
        ] do
      input = node("CompositeLit", [literal(1)], %{"type_node" => type})
      assert {^expected, meta, [_]} = abstract(input)

      assert {:ok, result} =
               FromMeta.transform({expected, meta, [{:literal, [subtype: :integer], 9}]})

      assert [%{"value" => 9}] = result["children"]
      assert result["type_node"]["kind"] == type["kind"]
    end
  end

  test "Go-specific fallback recursively reifies edited payload children and type slots" do
    input = node("SendStmt", [ident("ch"), literal(1)], %{"extra" => %{"custom" => true}})
    assert {:language_specific, meta, [channel, {:literal, literal_meta, _}]} = abstract(input)

    assert {:ok, result} =
             FromMeta.transform(
               {:language_specific, meta, [channel, {:literal, literal_meta, 3}]}
             )

    assert [%{"name" => "ch"}, %{"value" => 3}] = result["children"]
    assert result["extra"]["custom"]
    refute Map.has_key?(meta[:original_go], "children")
  end

  test "return tuples and branch labels are retained" do
    assert {:early_return, _, [{:tuple, _, [_, _]}]} =
             ast =
             abstract(node("ReturnStmt", [literal(1), ident("err")]))

    assert {:ok, %{"children" => [_, _]}} = FromMeta.transform(ast)

    for name <- ["break", "continue"] do
      ast = abstract(node("BranchStmt", [], %{"name" => name, "extra" => %{"label" => "outer"}}))
      assert {:ok, result} = FromMeta.transform(ast)
      assert result["name"] == name
      assert result["extra"]["label"] == "outer"
    end
  end

  test "unsupported and malformed reifications return errors rather than fabricated nodes" do
    for ast <- [
          {:throw, [], []},
          {:literal, [subtype: :regex], "x"},
          {:list, [], []},
          {:language_specific, [language: :python], %{"type" => "Pass"}},
          {:binary_op, [category: :arithmetic, operator: :pow],
           [literal_meta(1), literal_meta(2)]},
          {:lambda, [params: [{:param, [], "untyped"}]], []},
          {:binary_op, [], []}
        ] do
      assert {:error, reason} = FromMeta.transform(ast)
      assert is_binary(reason)
    end

    assert {:error, _} = ToMeta.transform(%{})
    assert {:error, _} = ToMeta.transform(node("AssignStmt", [ident("x")]))
  end

  defp abstract(input) do
    assert {:ok, ast, %{}} = ToMeta.transform(input)
    assert AST.conforms?(ast), "nonconforming Go abstraction: #{inspect(ast)}"
    ast
  end

  defp node(kind, children \\ [], attributes \\ %{}),
    do: Map.merge(%{"kind" => kind, "children" => children}, attributes)

  defp ident(name), do: node("Ident", [], %{"name" => name})
  defp literal(value), do: node("BasicLit", [], %{"value_type" => "int", "value" => value})
  defp literal_meta(value), do: {:literal, [subtype: :integer], value}
  defp node_return(value), do: {:early_return, [], [literal_meta(value)]}

  defp field(names, type, role),
    do:
      node("Field", Enum.map(names, &ident/1), %{
        "name" => List.first(names) || type,
        "type_node" => ident(type),
        "extra" => %{"role" => role}
      })
end
