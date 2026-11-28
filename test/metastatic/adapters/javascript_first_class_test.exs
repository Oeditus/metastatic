defmodule Metastatic.Adapters.JavaScriptFirstClassTest do
  @moduledoc """
  Coverage for the constructs that make JavaScript a first-class source
  language: everything the Babel bridge can parse must abstract to a
  *conforming* MetaAST node rather than falling through to the
  `:language_specific` escape hatch.

  Each test asserts three things, in order of increasing strength:

    1. the construct parses,
    2. every node in the resulting MetaAST conforms to the M2 meta-model,
    3. no `:language_specific` node was emitted for it.

  The third assertion is the one that matters: the escape hatch is always
  available, so "it round-trips" alone would pass even when the adapter
  understands nothing. Asserting *no* escape hatch is what pins the construct
  to a real MetaAST type.
  """
  use ExUnit.Case, async: true

  @moduletag :javascript

  alias Metastatic.{Adapter, AST}
  alias Metastatic.Adapters.{JavaScript, TypeScript}

  # Abstracts `source` and returns the MetaAST, failing the test on any error.
  defp abstract!(source) do
    assert {:ok, native} = JavaScript.parse(source)
    assert {:ok, meta_ast, _metadata} = JavaScript.to_meta(native)
    meta_ast
  end

  # Collects the `:native_type` of every `:language_specific` node in `ast`.
  defp native_types(ast) do
    ast
    |> AST.prewalker()
    |> Enum.flat_map(fn
      {:language_specific, meta, _} -> [Keyword.get(meta, :native_type)]
      _ -> []
    end)
  end

  # Asserts the whole tree conforms and that `source` needs no escape hatch.
  defp assert_first_class(source) do
    ast = abstract!(source)

    refute Enum.any?(AST.prewalker(ast), &(not AST.conforms?(&1))),
           "MetaAST contains non-conforming nodes: #{inspect(ast, limit: 6)}"

    assert native_types(ast) == [],
           "expected no :language_specific nodes, got #{inspect(native_types(ast))}"

    ast
  end

  describe "dialect separation" do
    test "plain JavaScript rejects TypeScript-only syntax" do
      # Parsing every file with the TypeScript plugin made the JavaScript
      # adapter accept these, so a `.js` file with a stray annotation was
      # silently abstracted instead of reported.
      assert {:error, _} = JavaScript.parse("let x: number = 1;")
      assert {:error, _} = JavaScript.parse("interface I { a: number }")
      assert {:error, _} = JavaScript.parse("function f(a: string): void {}")
    end

    test "TypeScript accepts type syntax" do
      assert {:ok, _} = TypeScript.parse("let x: number = 1;")
      assert {:ok, _} = TypeScript.parse("interface I { a: number }")
    end

    test "both dialects accept a bare expression" do
      assert {:ok, _} = JavaScript.parse("1 + 2;")
      assert {:ok, _} = TypeScript.parse("1 + 2;")
    end

    test "both dialects accept ordinary JavaScript" do
      assert {:ok, _} = JavaScript.parse("const x = {a: 1};")
      assert {:ok, _} = TypeScript.parse("const x = {a: 1};")
    end
  end

  describe "async and generators" do
    test "await becomes an :async_operation" do
      ast = assert_first_class("async function f(u) { const r = await fetch(u); return r; }")

      assert [{:async_operation, meta, [_]}] =
               ast
               |> AST.prewalker()
               |> Enum.filter(&match?({:async_operation, _, _}, &1))

      assert Keyword.get(meta, :op_type) == :await
    end

    test "yield becomes a :yield node and yield* records delegation" do
      ast = assert_first_class("function* g() { yield 1; yield* other(); }")

      yields =
        ast
        |> AST.prewalker()
        |> Enum.filter(&match?({:yield, _, _}, &1))

      assert length(yields) == 2
      assert Enum.any?(yields, fn {:yield, meta, _} -> Keyword.get(meta, :delegate) end)
    end
  end

  describe "spread and rest" do
    test "spread arguments become :spread nodes in expression context" do
      ast = assert_first_class("f(...xs);")

      assert [{:spread, meta, _}] =
               ast
               |> AST.prewalker()
               |> Enum.filter(&match?({:spread, _, _}, &1))

      assert Keyword.get(meta, :context) == :expression
    end

    test "rest parameters become :param nodes with rest: true" do
      ast = assert_first_class("function f(...args) { return args; }")
      {:function_def, meta, _} = ast

      assert [{:param, param_meta, "args"}] = Keyword.get(meta, :params)
      assert Keyword.get(param_meta, :rest) == true
    end

    test "rest in a destructuring pattern uses pattern context" do
      ast = assert_first_class("const [x, ...r] = xs;")

      assert [{:spread, meta, _}] =
               ast
               |> AST.prewalker()
               |> Enum.filter(&match?({:spread, _, _}, &1))

      assert Keyword.get(meta, :context) == :pattern
    end
  end

  describe "parameters" do
    test "function parameters are :param nodes, not raw expressions" do
      ast = assert_first_class("function add(a, b) { return a + b; }")
      {:function_def, meta, _body} = ast

      assert [{:param, _, "a"}, {:param, _, "b"}] = Keyword.get(meta, :params)
      assert Keyword.get(meta, :arity) == 2
    end

    test "a default parameter carries its default expression" do
      ast = assert_first_class("function f(a = 1) { return a; }")
      {:function_def, meta, _} = ast

      assert [{:param, param_meta, "a"}] = Keyword.get(meta, :params)
      assert {:literal, lit_meta, 1} = Keyword.get(param_meta, :default)
      assert Keyword.get(lit_meta, :subtype) == :integer
    end

    test "a destructured parameter carries its pattern" do
      ast = assert_first_class("function f({a, b}) { return a; }")
      {:function_def, meta, _} = ast

      assert [{:param, param_meta, "_"}] = Keyword.get(meta, :params)
      assert {:map, coll_meta, _} = Keyword.get(param_meta, :pattern)
      assert Keyword.get(coll_meta, :pattern) == true
    end

    test "arrow functions carry params in metadata too" do
      ast = assert_first_class("const f = (x, y) => x + y;")

      assert [{:lambda, meta, _}] =
               ast
               |> AST.prewalker()
               |> Enum.filter(&match?({:lambda, _, _}, &1))

      assert length(Keyword.get(meta, :params)) == 2
    end
  end

  describe "destructuring and object literals" do
    test "object destructuring preserves the pattern marker" do
      ast = assert_first_class("const {a, b: c} = o;")

      assert [{:map, meta, _}] =
               ast
               |> AST.prewalker()
               |> Enum.filter(&match?({:map, _, _}, &1))

      assert Keyword.get(meta, :pattern) == true
    end

    test "shorthand properties are marked as shorthand" do
      ast = assert_first_class("const o = {a, b};")

      pairs =
        ast
        |> AST.prewalker()
        |> Enum.filter(&match?({:pair, _, _}, &1))

      assert length(pairs) == 2
      assert Enum.all?(pairs, fn {:pair, meta, _} -> Keyword.get(meta, :shorthand) end)
    end

    test "an object literal is not marked as a pattern" do
      ast = assert_first_class("const o = {a: 1};")
      {:assignment, _, [_, {:map, meta, _}]} = ast

      refute Keyword.get(meta, :pattern)
    end
  end

  describe "control flow" do
    test "switch becomes a :pattern_match with :switch style" do
      ast = assert_first_class("switch (x) { case 1: a(); break; default: b(); }")

      assert [{:pattern_match, meta, [_, arm1, arm2]}] =
               ast
               |> AST.prewalker()
               |> Enum.filter(&match?({:pattern_match, _, _}, &1))

      assert Keyword.get(meta, :style) == :switch
      assert {:match_arm, arm1_meta, _} = arm1
      assert Keyword.get(arm1_meta, :falls_through) == false
      assert {:match_arm, arm2_meta, _} = arm2
      assert Keyword.get(arm2_meta, :pattern) == :_
    end

    test "a fall-through case is recorded" do
      ast = assert_first_class("switch (x) { case 1: a(); case 2: b(); }")

      {:pattern_match, _, [_, arm1 | _]} =
        ast
        |> AST.prewalker()
        |> Enum.find(&match?({:pattern_match, _, _}, &1))

      assert {:match_arm, meta, _} = arm1
      assert Keyword.get(meta, :falls_through) == true
    end

    test "a labeled statement keeps its body as a child" do
      ast = assert_first_class("outer: for (;;) { break outer; }")

      assert [{:labeled, meta, [_]}] =
               ast
               |> AST.prewalker()
               |> Enum.filter(&match?({:labeled, _, _}, &1))

      assert Keyword.get(meta, :label) == "outer"
    end

    test "the comma operator becomes a :block with :sequence scope" do
      ast = assert_first_class("a, b, c;")

      assert [{:block, meta, exprs}] =
               ast
               |> AST.prewalker()
               |> Enum.filter(&match?({:block, _, _}, &1))

      assert Keyword.get(meta, :scope) == :sequence
      assert length(exprs) == 3
    end

    test "a C-style for loop tolerates absent header slots" do
      ast = assert_first_class("for (;;) {}")

      assert [{:loop, meta, _}] =
               Enum.filter(AST.prewalker(ast) |> Enum.to_list(), &match?({:loop, _, _}, &1))

      assert Keyword.get(meta, :loop_type) == :for
    end
  end

  describe "templates" do
    test "an interpolated template keeps its expressions traversable" do
      ast = assert_first_class("const s = `hi ${name}!`;")

      assert [{:literal, meta, [{:variable, _, "name"}]}] =
               ast
               |> AST.prewalker()
               |> Enum.filter(&match?({:literal, _, _}, &1))

      assert Keyword.get(meta, :subtype) == :template_string
      assert Keyword.get(meta, :quasis) == ["hi ", "!"]
    end

    test "a tagged template becomes a call carrying the template" do
      ast = assert_first_class("tag`hi ${x}`;")

      assert [{:function_call, meta, [_, {:literal, _, _}]}] =
               ast
               |> AST.prewalker()
               |> Enum.filter(&match?({:function_call, _, _}, &1))

      assert Keyword.get(meta, :tagged_template) == true
    end
  end

  describe "round-trip fidelity" do
    @round_trip_cases [
      {"await", "async function f(u) { const r = await fetch(u); return r; }"},
      {"spread", "f(...xs);"},
      {"rest parameter", "function f(...args) { return args; }"},
      {"default parameter", "function f(a = 1) { return a; }"},
      {"switch", "switch (x) { case 1: a(); break; default: b(); }"},
      {"generator", "function* g() { yield 1; }"},
      {"tagged template", "tag`hi ${x}`;"},
      {"interpolated template", "const s = `hi ${name}!`;"},
      {"labeled statement", "outer: for (;;) { break outer; }"},
      {"comma operator", "a, b;"},
      {"shorthand properties", "const o = {a, b};"},
      {"class with methods", "class A { constructor(x) { this.x = x; } m(y) { return y; } }"}
    ]

    for {label, source} <- @round_trip_cases do
      test "round-trips #{label}" do
        source = unquote(source)
        assert {:ok, generated} = Adapter.round_trip(JavaScript, source)

        # Compare semantics, not formatting: re-parse the generated source and
        # require it to abstract to the same canonical MetaAST.
        assert {:ok, native1} = JavaScript.parse(source)
        assert {:ok, meta1, _} = JavaScript.to_meta(native1)
        assert {:ok, native2} = JavaScript.parse(generated)
        assert {:ok, meta2, _} = JavaScript.to_meta(native2)

        assert AST.canonicalize(meta2) == AST.canonicalize(meta1)
      end
    end
  end

  describe "error handling" do
    test "a syntax error is reported, not raised" do
      assert {:error, reason} = JavaScript.parse("function f( {")
      assert is_binary(reason)
    end

    test "reifying an unsupported async operation returns an error" do
      assert {:error, _} =
               JavaScript.from_meta(
                 {:async_operation, [op_type: :async], [{:literal, [subtype: :integer], 1}]},
                 %{}
               )
    end
  end
end
