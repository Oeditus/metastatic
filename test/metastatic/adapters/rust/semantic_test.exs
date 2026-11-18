defmodule Metastatic.Adapters.Rust.SemanticTest do
  @moduledoc """
  Phase 5 coverage: Rust `op_kind` enrichment.

  `Metastatic.Adapter.enrich/3` is called at the end of `ToMeta.transform/1`,
  so every Rust call is matched against the pattern tables registered in
  `Metastatic.Semantic.Domains.*`. These tests assert that the tables exist and
  that representative calls are classified into the right domain.
  """
  use ExUnit.Case, async: true

  alias Metastatic.Adapters.Rust
  alias Metastatic.Semantic.{OpKind, Patterns}

  defp op_kinds(source) do
    {:ok, native} = Rust.parse(source)
    {:ok, meta_ast, _metadata} = Rust.to_meta(native)

    {_ast, kinds} =
      Metastatic.AST.traverse(
        meta_ast,
        [],
        fn node, acc ->
          case node do
            {:function_call, meta, _args} ->
              case Keyword.get(meta, :op_kind) do
                nil -> {node, acc}
                op_kind -> {node, [op_kind | acc]}
              end

            _ ->
              {node, acc}
          end
        end,
        fn node, acc -> {node, acc} end
      )

    Enum.reverse(kinds)
  end

  describe "pattern registration" do
    test "every domain has Rust patterns" do
      for domain <- OpKind.domains() do
        assert Patterns.get_patterns(domain, :rust) != [],
               "expected Rust patterns for domain #{inspect(domain)}"
      end
    end
  end

  describe "domain classification" do
    @cases [
      {"db", "fn f() { sqlx::query(\"SELECT 1\"); }", :db},
      {"http", "fn f() { reqwest::get(\"https://x\"); }", :http},
      {"cache", "fn f() { redis::get(\"k\"); }", :cache},
      {"file", "fn f() { std::fs::read(\"p\"); }", :file},
      {"auth", "fn f() { jsonwebtoken::encode(); }", :auth},
      {"queue", "fn f() { lapin::basic_publish(); }", :queue},
      {"external_api", "fn f() { stripe::create(); }", :external_api}
    ]

    for {label, source, domain} <- @cases do
      test "#{label} calls are classified as #{inspect(domain)}" do
        source = unquote(source)
        domain = unquote(domain)

        kinds = op_kinds(source)
        assert kinds != [], "expected at least one enriched call in #{inspect(source)}"

        assert Enum.any?(kinds, fn kind -> OpKind.domain(kind) == domain end),
               "expected domain #{inspect(domain)}, got #{inspect(kinds)}"
      end
    end
  end

  describe "operation and framework metadata" do
    test "sqlx::query is a query operation" do
      [kind | _] = op_kinds("fn f() { sqlx::query(\"SELECT 1\"); }")
      assert OpKind.operation(kind) == :query
      assert Keyword.get(kind, :framework) == :sqlx
    end

    test "reqwest::get extracts the URL as the target" do
      [kind | _] = op_kinds("fn f() { reqwest::get(\"https://example.com\"); }")
      assert OpKind.operation(kind) == :get
      assert OpKind.target(kind) == "https://example.com"
    end

    test "std::fs::write is a write operation" do
      [kind | _] = op_kinds(~s|fn f() { std::fs::write("p", b"x"); }|)
      assert OpKind.operation(kind) == :write
      assert OpKind.write?(kind) or OpKind.operation(kind) == :write
    end

    test "jsonwebtoken::encode generates a token" do
      [kind | _] = op_kinds("fn f() { jsonwebtoken::encode(); }")
      assert OpKind.operation(kind) == :generate_token
    end
  end

  describe "OpKind framework atoms" do
    test "every Rust framework atom is accepted by OpKind.valid?/1" do
      frameworks = [
        :sqlx,
        :diesel,
        :sea_orm,
        :reqwest,
        :hyper,
        :redis_rs,
        :moka,
        :lapin,
        :jsonwebtoken,
        :argon2
      ]

      for framework <- frameworks do
        op_kind = OpKind.new(:db, :query, framework: framework)
        assert OpKind.valid?(op_kind)
      end
    end
  end

  describe "non-matching calls" do
    test "an unknown function is not enriched" do
      assert op_kinds("fn f() { my_helper(); }") == []
    end
  end
end
