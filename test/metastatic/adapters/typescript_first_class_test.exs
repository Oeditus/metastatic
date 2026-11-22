defmodule Metastatic.Adapters.TypeScriptFirstClassTest do
  @moduledoc """
  Coverage for TypeScript as a first-class language: type syntax must parse
  under the TypeScript dialect, abstract to a conforming MetaAST, and survive a
  round-trip.

  TypeScript-only declarations (`interface`, `type`, `enum`) have no
  cross-language analogue, so they are expected to be preserved as
  `:language_specific` nodes — that is the *correct* outcome, not a gap. What
  is asserted here is that they conform and round-trip losslessly, and that
  ordinary code shared with JavaScript needs no escape hatch at all.
  """
  use ExUnit.Case, async: true

  @moduletag :typescript

  alias Metastatic.{Adapter, AST}
  alias Metastatic.Adapters.TypeScript

  defp abstract!(source) do
    assert {:ok, native} = TypeScript.parse(source)
    assert {:ok, meta_ast, _metadata} = TypeScript.to_meta(native)
    meta_ast
  end

  defp assert_conforming(ast) do
    bad = ast |> AST.prewalker() |> Enum.reject(&AST.conforms?/1)
    assert bad == [], "non-conforming nodes: #{inspect(bad, limit: 4)}"
    ast
  end

  # Canonicalises the MetaAST and additionally removes the source offsets that
  # Babel embeds in a `:language_specific` native node. Those offsets change
  # whenever the printer re-emits the source, so they cannot take part in a
  # semantic comparison. Native nodes may sit anywhere — including inside
  # metadata such as a `:param`'s `:pattern` — so the whole term is walked.
  defp strip_positions(ast) do
    ast
    |> strip_native_positions()
    |> AST.canonicalize()
  end

  @position_keys ["loc", "start", "end"]

  defp strip_native_positions(value) when is_map(value) do
    value
    |> Map.drop(@position_keys)
    |> Map.new(fn {k, v} -> {k, strip_native_positions(v)} end)
  end

  defp strip_native_positions(value) when is_list(value) do
    Enum.map(value, &strip_native_positions/1)
  end

  defp strip_native_positions({type, meta, children})
       when is_atom(type) and is_list(meta) do
    {type, strip_native_positions(meta), strip_native_positions(children)}
  end

  defp strip_native_positions({key, value}) when is_atom(key) do
    {key, strip_native_positions(value)}
  end

  defp strip_native_positions(value), do: value

  describe "dialect" do
    test "type annotations parse" do
      assert {:ok, _} = TypeScript.parse("let x: number = 1;")
      assert {:ok, _} = TypeScript.parse("function f(a: string): void {}")
    end

    test "type-only declarations parse" do
      assert {:ok, _} = TypeScript.parse("interface I { a: number }")
      assert {:ok, _} = TypeScript.parse("type T = string | number;")
      assert {:ok, _} = TypeScript.parse("enum E { A, B }")
    end

    test "a bare expression parses" do
      assert {:ok, _} = TypeScript.parse("1 + 2;")
    end
  end

  describe "abstraction" do
    test "an interface is preserved as a TypeScript-specific node" do
      ast = abstract!("interface User { id: number; }")

      assert {:language_specific, meta, _native} = ast
      assert Keyword.get(meta, :language) == :typescript
      assert Keyword.get(meta, :hint) == :interface
      assert Keyword.get(meta, :ts_kind) == :interface
      assert Keyword.get(meta, :name) == "User"
    end

    test "a type alias is preserved as a TypeScript-specific node" do
      ast = abstract!("type ID = string | number;")

      assert {:language_specific, meta, _} = ast
      assert Keyword.get(meta, :hint) == :type_alias
      assert Keyword.get(meta, :name) == "ID"
    end

    test "an enum is preserved as a TypeScript-specific node" do
      ast = abstract!("enum Color { Red, Green }")

      assert {:language_specific, meta, _} = ast
      assert Keyword.get(meta, :hint) == :enum
      assert Keyword.get(meta, :name) == "Color"
    end

    test "a typed function abstracts to a normal :function_def" do
      ast =
        assert_conforming(
          abstract!("function add(a: number, b: number): number { return a + b; }")
        )

      assert {:function_def, meta, [_body]} = ast
      assert Keyword.get(meta, :name) == "add"
      assert Keyword.get(meta, :arity) == 2
      assert [{:param, _, "a"}, {:param, _, "b"}] = Keyword.get(meta, :params)
    end

    test "a generic function abstracts without an escape hatch" do
      ast = assert_conforming(abstract!("function id<T>(x: T): T { return x; }"))

      escape_hatches =
        ast
        |> AST.prewalker()
        |> Enum.filter(&match?({:language_specific, _, _}, &1))

      assert escape_hatches == []
    end

    test "TypeScript constructs all conform" do
      for source <- [
            "interface I { a: number }",
            "type T = string | number;",
            "enum E { A }",
            "class A implements I { private x: number = 1; }",
            "const y = x as string;",
            "function f(a: string): number { return 1; }"
          ] do
        assert_conforming(abstract!(source))
      end
    end
  end

  describe "round-trip fidelity" do
    @cases [
      {"interface", "interface User { id: number; name: string; }"},
      {"type alias", "type ID = string | number;"},
      {"enum", "enum Color { Red, Green }"},
      {"typed function", "function add(a: number, b: number): number { return a + b; }"},
      {"generic function", "function id<T>(x: T): T { return x; }"},
      {"async await", "async function f(u: string) { const r = await fetch(u); return r; }"},
      {"class", "class A { constructor(private x: number) {} }"}
    ]

    for {label, source} <- @cases do
      test "round-trips #{label}" do
        source = unquote(source)
        assert {:ok, generated} = Adapter.round_trip(TypeScript, source)

        # TypeScript-only declarations are preserved as `:language_specific`
        # nodes whose value is the raw Babel node, including source offsets.
        # Those offsets legitimately change when the printer re-emits the
        # source, so the comparison is on the *re-parsed* shape with offsets
        # and locations removed rather than on the raw native map.
        assert strip_positions(abstract!(source)) == strip_positions(abstract!(generated))
      end
    end
  end

  describe "error handling" do
    test "a syntax error is reported, not raised" do
      assert {:error, reason} = TypeScript.parse("function f( {")
      assert is_binary(reason)
    end
  end
end
