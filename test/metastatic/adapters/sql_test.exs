defmodule Metastatic.Adapters.SQLTest do
  use ExUnit.Case, async: true

  alias Metastatic.Adapters.Elixir, as: ElixirAdapter
  alias Metastatic.Adapters.Python
  alias Metastatic.Adapters.SQL
  alias Metastatic.{AST, Document, Validator}

  describe "parse/1 and parse/2" do
    test "parses standalone expressions" do
      assert {:ok, ast} = SQL.parse("1 + 2")
      assert is_map(ast)
      assert Map.has_key?(ast, "Expr")
    end

    test "parses SELECT queries" do
      assert {:ok, ast} = SQL.parse("SELECT id, name FROM users WHERE age > 18")
      assert is_list(ast)
      assert length(ast) == 1
    end

    test "parses with dialect options" do
      assert {:ok, _} = SQL.parse("SELECT * FROM users", dialect: :postgres)
      assert {:ok, _} = SQL.parse("SELECT * FROM users", dialect: :mysql)
      assert {:ok, _} = SQL.parse("SELECT * FROM users", dialect: :sqlite)
    end

    test "returns error on invalid syntax" do
      assert {:error, reason} = SQL.parse("SELECT FROM WHERE @@#$%")
      assert is_binary(reason)
      assert String.contains?(reason, "ParseError") or String.contains?(reason, "error")
    end
  end

  describe "to_meta/1" do
    test "transforms binary operations and literals" do
      {:ok, native} = SQL.parse("age > 18 AND active = true")
      assert {:ok, meta_ast, metadata} = SQL.to_meta(native)

      assert AST.conforms?(meta_ast)
      canonical = AST.canonicalize(meta_ast)
      assert {:binary_op, [category: :boolean, operator: :and], [left, right]} = canonical

      assert {:binary_op, [category: :comparison, operator: :>],
              [{:variable, _, "age"}, {:literal, [subtype: :integer], 18}]} = left

      assert {:binary_op, [category: :comparison, operator: :==],
              [{:variable, _, "active"}, {:literal, [subtype: :boolean], true}]} = right

      doc = Document.new(meta_ast, :sql, metadata, "age > 18 AND active = true")
      assert {:ok, val_meta} = Validator.validate(doc)
      assert val_meta.level == :core
    end

    test "transforms SELECT query with semantic op_kind" do
      sql = "SELECT id, name FROM users WHERE id = 1"
      {:ok, native} = SQL.parse(sql)
      assert {:ok, meta_ast, _metadata} = SQL.to_meta(native)

      assert AST.conforms?(meta_ast)
      assert {:function_call, meta, args} = meta_ast
      assert Keyword.get(meta, :name) == "SELECT"
      assert Keyword.get(meta, :table) == "users"

      op_kind = Keyword.get(meta, :op_kind)
      assert Keyword.get(op_kind, :domain) == :db
      assert Keyword.get(op_kind, :operation) == :query
      assert Keyword.get(op_kind, :target) == "users"
      assert Keyword.get(op_kind, :framework) == :sql

      assert length(args) >= 2
    end

    test "transforms SELECT with aggregation function" do
      sql = "SELECT COUNT(*) FROM orders"
      {:ok, native} = SQL.parse(sql)
      assert {:ok, meta_ast, _metadata} = SQL.to_meta(native)

      assert {:function_call, meta, _} = meta_ast
      op_kind = Keyword.get(meta, :op_kind)
      assert Keyword.get(op_kind, :operation) == :aggregate
      assert Keyword.get(op_kind, :target) == "orders"
    end

    test "transforms INSERT statement with :create op_kind" do
      sql = "INSERT INTO users (id, name) VALUES (1, 'Alice')"
      {:ok, native} = SQL.parse(sql)
      assert {:ok, meta_ast, _metadata} = SQL.to_meta(native)

      assert {:function_call, meta, _} = meta_ast
      op_kind = Keyword.get(meta, :op_kind)
      assert Keyword.get(op_kind, :operation) == :create
      assert Keyword.get(op_kind, :target) == "users"
    end

    test "transforms UPDATE statement with :update op_kind" do
      sql = "UPDATE users SET name = 'Bob' WHERE id = 1"
      {:ok, native} = SQL.parse(sql)
      assert {:ok, meta_ast, _metadata} = SQL.to_meta(native)

      assert {:function_call, meta, _} = meta_ast
      op_kind = Keyword.get(meta, :op_kind)
      assert Keyword.get(op_kind, :operation) == :update
      assert Keyword.get(op_kind, :target) == "users"
    end

    test "transforms DELETE statement with :delete op_kind" do
      sql = "DELETE FROM users WHERE id = 1"
      {:ok, native} = SQL.parse(sql)
      assert {:ok, meta_ast, _metadata} = SQL.to_meta(native)

      assert {:function_call, meta, _} = meta_ast
      op_kind = Keyword.get(meta, :op_kind)
      assert Keyword.get(op_kind, :operation) == :delete
      assert Keyword.get(op_kind, :target) == "users"
    end
  end

  describe "round-trip fidelity" do
    test "round-trips complex SELECT query" do
      sql = "SELECT id, name FROM users WHERE id = 1"
      assert {:ok, native1} = SQL.parse(sql)
      assert {:ok, meta_ast, metadata} = SQL.to_meta(native1)
      assert {:ok, native2} = SQL.from_meta(meta_ast, metadata)
      assert {:ok, unparsed} = SQL.unparse(native2)

      assert String.trim(unparsed) == sql
    end

    test "round-trips expression" do
      expr = "x + 10"
      assert {:ok, native1} = SQL.parse(expr)
      assert {:ok, meta_ast, metadata} = SQL.to_meta(native1)
      assert {:ok, native2} = SQL.from_meta(meta_ast, metadata)
      assert {:ok, unparsed} = SQL.unparse(native2)

      assert String.trim(unparsed) == expr
    end
  end

  describe "cross-language semantic equivalence" do
    test "SQL expression produces canonical MetaAST matching Python and Elixir" do
      sql_expr = "x + 5"
      py_expr = "x + 5"
      ex_expr = "x + 5"

      {:ok, sql_native} = SQL.parse(sql_expr)
      {:ok, sql_meta, _} = SQL.to_meta(sql_native)

      {:ok, py_native} = Python.parse(py_expr)
      {:ok, py_meta, _} = Python.to_meta(py_native)

      {:ok, ex_native} = ElixirAdapter.parse(ex_expr)
      {:ok, ex_meta, _} = ElixirAdapter.to_meta(ex_native)

      canonical_sql = AST.canonicalize(sql_meta)
      canonical_py = AST.canonicalize(py_meta)
      canonical_ex = AST.canonicalize(ex_meta)

      assert canonical_sql == canonical_py
      assert canonical_sql == canonical_ex
    end
  end
end
