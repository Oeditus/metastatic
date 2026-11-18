defmodule Metastatic.Adapters.Rust.ExtendedTest do
  @moduledoc """
  Phase 3 coverage: the M2.2 Extended layer for Rust.

  Each test parses a construct, abstracts it, and asserts the MetaAST shape the
  mapping table in `RUST_IMPL.md` §4 promises. These are the nodes that make
  Rust comparable to Python/JavaScript/Elixir rather than merely parseable.
  """
  use ExUnit.Case, async: true

  alias Metastatic.Adapters.Rust
  alias Metastatic.AST

  defp meta!(source) do
    {:ok, native} = Rust.parse(source)
    {:ok, meta_ast, _metadata} = Rust.to_meta(native)
    meta_ast
  end

  defp find(ast, type) do
    {_ast, found} =
      AST.traverse(
        ast,
        [],
        fn node, acc ->
          case node do
            {^type, _meta, _children} -> {node, [node | acc]}
            _ -> {node, acc}
          end
        end,
        fn node, acc -> {node, acc} end
      )

    Enum.reverse(found)
  end

  describe "loops" do
    test "while becomes :loop with loop_type :while" do
      ast = meta!("fn f() { while x < 1 { } }")

      assert [{:loop, meta, [_condition, _body]}] = find(ast, :loop)
      assert Keyword.get(meta, :loop_type) == :while
    end

    test "for becomes :loop with loop_type :for" do
      ast = meta!("fn f() { for i in v { } }")

      assert [{:loop, meta, [_pattern, _collection, _body]}] = find(ast, :loop)
      assert Keyword.get(meta, :loop_type) == :for
    end

    test "bare loop becomes :loop with loop_type :infinite" do
      ast = meta!("fn f() { loop { } }")

      assert [{:loop, meta, [_body]}] = find(ast, :loop)
      assert Keyword.get(meta, :loop_type) == :infinite
    end
  end

  describe "match" do
    test "match becomes :pattern_match with :match_arm children" do
      ast = meta!("fn f(x: i32) { match x { 0 => 1, _ => 2 } }")

      assert [{:pattern_match, _meta, [_scrutinee | arms]}] = find(ast, :pattern_match)
      assert length(arms) == 2
      assert Enum.all?(arms, &match?({:match_arm, _, _}, &1))
    end
  end

  describe "closures" do
    test "a closure becomes :lambda" do
      ast = meta!("fn f() { let g = |x| x + 1; }")

      assert [{:lambda, _meta, _body}] = find(ast, :lambda)
    end
  end

  describe "async and try" do
    test "await becomes :async_operation with op_type :await" do
      ast = meta!("fn f() { let x = g().await; }")

      assert [{:async_operation, meta, _}] = find(ast, :async_operation)
      assert Keyword.get(meta, :op_type) == :await
    end

    test "an async block becomes :async_operation with op_type :async" do
      ast = meta!("fn f() { let x = async { 1 }; }")

      assert [{:async_operation, meta, _}] = find(ast, :async_operation)
      assert Keyword.get(meta, :op_type) == :async
    end

    test "`?` becomes :exception_handling" do
      ast = meta!("fn f() { let x = g()?; }")

      assert [{:exception_handling, _meta, _}] = find(ast, :exception_handling)
    end
  end

  describe "references and let-chains" do
    test "`&mut x` is a unary op carrying mutability" do
      ast = meta!("fn f() { let i = &mut v; }")

      assert [{:unary_op, meta, _}] = find(ast, :unary_op)
      assert Keyword.get(meta, :operator) == :ref
      assert Keyword.get(meta, :mutable) == true
    end

    test "`if let` becomes :inline_match" do
      ast = meta!("fn f(v: Vec<i32>) { if let Some(n) = v.first() { } }")

      assert [{:inline_match, _meta, [_pattern, _value]}] = find(ast, :inline_match)
    end
  end

  describe "iterator chains" do
    test "a map/filter/fold chain stays a function_call tree" do
      ast = meta!("fn f(v: Vec<i32>) { v.iter().map(|x| x * 2).collect(); }")

      calls = find(ast, :function_call)
      names = Enum.map(calls, fn {:function_call, meta, _} -> Keyword.get(meta, :name) end)

      assert "map" in names
      assert "collect" in names
    end
  end

  describe "round-trip fidelity" do
    @extended_sources [
      "fn f() { let x = async { 1 }; }",
      "fn f(v: Vec<i32>) { let i = &mut v; }",
      "fn f(v: Vec<i32>) { while let Some(x) = v.pop() { } }",
      "fn f() { let g = |x: i32| x + 1; }",
      "fn f(x: i32) { match x { 0 => 1, _ => 2 } }",
      "fn f() { let x = g()?; }"
    ]

    for source <- @extended_sources do
      test "round-trips #{inspect(source)}" do
        source = unquote(source)

        assert {:ok, native} = Rust.parse(source)
        assert {:ok, meta_ast, metadata} = Rust.to_meta(native)
        assert AST.conforms?(meta_ast)
        assert {:ok, reified} = Rust.from_meta(meta_ast, metadata)
        assert {:ok, printed} = Rust.unparse(reified)
        assert String.trim(printed) != ""
      end
    end
  end
end
