defmodule Metastatic.Adapters.GoTest do
  use ExUnit.Case, async: true

  alias Metastatic.{Adapter, AST, Builder, Languages, Validator}
  alias Metastatic.Adapters.Go
  alias Metastatic.Adapters.Go.Subprocess

  @moduletag timeout: 120_000
  unless Subprocess.available?(), do: @moduletag(skip: "Go toolchain or prebuilt bridge required")

  doctest Go
  doctest Subprocess

  @expressions [
    "0",
    "42",
    "0xff",
    "0b1010",
    "0o755",
    "1_000_000",
    "18446744073709551616",
    "12345678901234567890123456789012345678901234567890",
    "3.14",
    "0x1.8p2",
    "1e1000",
    "2i",
    "'λ'",
    ~S("hello\nworld"),
    "`raw string`",
    ~S("\xff"),
    "true",
    "false",
    "nil",
    "x",
    "a + b * c",
    "(a + b) * c",
    "a - (b - c)",
    "a / (b * c)",
    "a && b || !c",
    "a &^ b",
    "a << 2",
    "-x",
    "^x",
    "&x",
    "*p",
    "<-ch",
    "f()",
    "f(1, 2)",
    "f(xs...)",
    "fmt.Println(x)",
    "factory().Method(x)",
    "table[key]",
    "xs[:]",
    "xs[1:]",
    "xs[:2]",
    "xs[1:2:3]",
    "x.(string)",
    "F[int, string](x)",
    "[]int{1, 2, 3}",
    "[...]int{1, 2}",
    "map[string]int{\"a\": 1}",
    "Point{X: 1, Y: 2}",
    "[][]int{{1}, {2}}",
    "func(x int) int { return x + 1 }"
  ]

  for {source, index} <- Enum.with_index(@expressions) do
    test "expression round-trip #{index}: #{source}" do
      source = unquote(source)
      assert {:ok, native} = Go.parse(source)
      assert {:ok, meta, metadata} = Go.to_meta(native)
      assert AST.conforms?(meta), inspect(meta)
      assert {:ok, reified} = Go.from_meta(meta, metadata)
      assert {:ok, output} = Go.unparse(reified)
      assert {:ok, reparsed} = Go.parse(output)
      assert {:ok, meta2, _} = Go.to_meta(reparsed)
      assert AST.canonicalize(meta2) == AST.canonicalize(meta)
    end
  end

  @fixtures Path.wildcard(Path.expand("../../fixtures/go/*.go", __DIR__))
  for fixture <- @fixtures do
    @external_resource fixture
    test "complete source round-trip: #{Path.basename(fixture)}" do
      source = File.read!(unquote(fixture))
      assert {:ok, document} = Builder.from_source(source, :go)
      assert AST.conforms?(document.ast)
      assert {:ok, _} = Validator.validate(document)
      assert {:ok, output} = Builder.to_source(document)
      assert {:ok, document2} = Builder.from_source(output, :go)
      assert AST.canonicalize(document2.ast) == AST.canonicalize(document.ast)
      assert {:ok, ^output} = Subprocess.format(output)
    end
  end

  test "registration and file detection work without hand-maintained registry entries" do
    assert {:ok, Go} = Languages.get_adapter(:go)
    assert {:ok, :go} = Languages.detect_language("main.go")
    assert {:ok, :go} = Languages.parse_language("go")
    assert [".go"] = Go.file_extensions()
  end

  test "bridge selftest exercises the binary actually in use" do
    assert {:ok, %{"status" => "ok"}} = Subprocess.selftest()
  end

  test "malformed source and malformed native nodes return errors" do
    for source <- ["", "package", "package p\nfunc f(", "1 +", "a b", "@@@"] do
      assert {:error, reason} = Go.parse(source)
      assert is_binary(reason)
    end

    for native <- [nil, [], %{}, %{"kind" => "Unknown"}, %{"kind" => "BinaryExpr"}] do
      assert {:error, reason} = Go.unparse(native)
      assert is_binary(reason)
    end
  end

  test "literal mutations propagate through a complete function and file" do
    source = "package sample\nfunc Add(x int) int { return x + 123 }\n"
    assert {:ok, document} = Builder.from_source(source, :go)

    changed =
      AST.prewalk(document.ast, fn
        {:literal, meta, 123} -> {:literal, meta, 456}
        node -> node
      end)

    assert {:ok, output} = Builder.to_source(%{document | ast: changed})
    assert output =~ "x + 456"
    refute output =~ "123"
    assert {:ok, _} = Go.parse(output)
  end

  test "function parameter and name edits are honored" do
    assert {:ok, document} =
             Builder.from_source("package p\nfunc Add(a, b int) int { return a + b }\n", :go)

    changed =
      AST.prewalk(document.ast, fn
        {:function_def, meta, body} ->
          {:function_def, Keyword.put(meta, :name, "Sum"), body}

        node ->
          node
      end)

    assert {:ok, output} = Builder.to_source(%{document | ast: changed})
    assert output =~ "func Sum(a, b int)"
    refute output =~ "func Add"
  end

  test "build constraints, compiler directives and comments survive literal edits" do
    source = """
    //go:build linux

    // Package sample contains a documented value.
    package sample

    // Answer is public.
    var Answer = 123 // keep this note

    //go:noinline
    func Value() int { return Answer }
    """

    assert {:ok, document} = Builder.from_source(source, :go)

    changed =
      AST.prewalk(document.ast, fn
        {:literal, meta, 123} -> {:literal, meta, 456}
        node -> node
      end)

    assert {:ok, output} = Builder.to_source(%{document | ast: changed})
    assert output =~ "//go:build linux\n\n"
    assert output =~ "// Package sample"
    assert output =~ "// Answer is public."
    assert output =~ "// keep this note"
    assert output =~ "//go:noinline\nfunc Value"
    assert output =~ "456"
    assert {:ok, _} = Go.parse(output)
  end

  test "fresh MetaAST expressions reify without Go preservation metadata" do
    ast =
      {:binary_op, [category: :arithmetic, operator: :*],
       [
         {:binary_op, [category: :arithmetic, operator: :+],
          [{:variable, [scope: :local], "x"}, {:literal, [subtype: :integer], 1}]},
         {:literal, [subtype: :integer], 2}
       ]}

    assert {:ok, native} = Go.from_meta(ast, %{})
    assert {:ok, source} = Go.unparse(native)
    assert source =~ "(x + 1)"
    assert {:ok, _} = Go.parse(source)
  end

  test "invalid UTF8 Go string bytes stay exact and can be edited" do
    assert {:ok, native} = Go.parse(~S("\xff\x00"))
    assert {:ok, {:literal, meta, <<255, 0>>}, metadata} = Go.to_meta(native)
    assert {:ok, edited} = Go.from_meta({:literal, meta, <<254, 0, 128>>}, metadata)
    assert {:ok, source} = Go.unparse(edited)
    assert {:ok, reparsed} = Go.parse(source)
    assert {:ok, {:literal, _, <<254, 0, 128>>}, _} = Go.to_meta(reparsed)
  end

  test "cgo preambles stay adjacent to import C" do
    source = """
    package p

    /*
    #include <stdlib.h>
    */
    import "C"

    var X = 1
    """

    assert {:ok, output} = Adapter.round_trip(Go, source)
    assert output =~ "#include <stdlib.h>"
    assert output =~ "*/\nimport \"C\""
  end

  test "ordinary expression comments survive mutation and repeated round trips" do
    assert {:ok, document} = Builder.from_source("/* left */ x + 123 // right\n", :go)

    changed =
      AST.prewalk(document.ast, fn
        {:literal, meta, 123} -> {:literal, meta, 456}
        node -> node
      end)

    assert {:ok, output} = Builder.to_source(%{document | ast: changed})
    assert output =~ "456"
    assert [_before, _after] = String.split(output, "/* left */")
    assert [_before, _after] = String.split(output, "// right")
    assert {:ok, output2} = Adapter.round_trip(Go, output)
    assert output2 == output
  end

  test "formatting empty input returns an explicit empty source payload" do
    assert {:ok, ""} = Subprocess.format("")
  end

  test "shadowed predeclared names remain variables without changing builtin literals" do
    source = """
    package p
    func F(true bool) bool { return true }
    func G() bool { return true }
    """

    assert {:ok, document} = Builder.from_source(source, :go)

    assert {:container, _,
            [
              {:function_def, first, [{:early_return, _, [{:variable, _, "true"}]}]},
              {:function_def, _, [{:early_return, _, [{:literal, _, true}]}]}
            ]} = document.ast

    assert [{:param, _, "true"}] = first[:params]
    assert {:ok, output} = Builder.to_source(document)
    assert output =~ "func F(true bool)"
  end

  test "a short declaration sees the builtin on its RHS and the binding afterwards" do
    source = "package p\nfunc F() { true := true; _ = true }\n"
    assert {:ok, document} = Builder.from_source(source, :go)

    assert {:container, _,
            [
              {:function_def, _,
               [
                 {:assignment, _, [{:variable, _, "true"}, {:literal, _, true}]},
                 {:assignment, _, [{:variable, _, "_"}, {:variable, _, "true"}]}
               ]}
            ]} = document.ast
  end

  test "parsed function parameters can be renamed and appended" do
    source = "package p\nfunc Add(a, b int) int { return a + b }\n"
    assert {:ok, document} = Builder.from_source(source, :go)

    changed =
      AST.prewalk(document.ast, fn
        {:function_def, meta, body} ->
          [first, second] = Keyword.fetch!(meta, :params)
          {:param, first_meta, _} = first
          third = {:param, Keyword.delete(first_meta, :go_group), "c"}
          params = [{:param, first_meta, "x"}, second, third]
          {:function_def, Keyword.put(meta, :params, params), body}

        node ->
          node
      end)

    assert {:ok, output} = Builder.to_source(%{document | ast: changed})
    assert output =~ "x"
    assert output =~ "c"
    assert {:ok, reparsed} = Go.parse(output)
    assert {:ok, meta, _} = Go.to_meta(reparsed)
    assert {:container, _, [{:function_def, function_meta, _}]} = meta
    assert [{:param, _, "x"}, {:param, _, "b"}, {:param, _, "c"}] = function_meta[:params]
  end

  test "reification rejects foreign native payloads rather than treating them as Go" do
    assert {:error, _} =
             Go.from_meta(
               {:language_specific, [language: :python], %{"_type" => "Pass"}},
               %{}
             )
  end

  test "concurrent parser calls share a valid cached build" do
    results =
      1..8
      |> Task.async_stream(fn n -> Go.parse(Integer.to_string(n)) end,
        max_concurrency: 8,
        timeout: 120_000
      )
      |> Enum.to_list()

    assert Enum.all?(results, &match?({:ok, {:ok, %{"kind" => "BasicLit"}}}, &1))
  end

  test "direct adapter pipeline agrees with Builder" do
    source = "package p\nfunc f() { println(1) }\n"
    assert {:ok, expected} = Adapter.round_trip(Go, source)
    assert {:ok, ^expected} = Builder.round_trip(source, :go)
  end
end
