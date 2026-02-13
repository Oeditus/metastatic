defmodule Metastatic.Semantic.EnricherTest do
  use ExUnit.Case, async: true

  alias Metastatic.Semantic.{Domains.Database, Enricher, OpKind, Patterns}

  # Ensure patterns are registered before tests
  setup_all do
    # Clear and re-register to ensure clean state
    Patterns.clear_all()
    Database.register_all()
    :ok
  end

  # Helper functions for creating AST nodes
  defp function_call(name, args), do: {:function_call, [name: name], args}
  defp variable(name), do: {:variable, [], name}
  defp literal(subtype, value), do: {:literal, [subtype: subtype], value}
  defp block(statements), do: {:block, [], statements}

  describe "enrich/2 - Elixir/Ecto patterns" do
    test "enriches Repo.get with target extraction" do
      node = function_call("Repo.get", [variable("User"), literal(:integer, 1)])
      enriched = Enricher.enrich(node, :elixir)

      op_kind = Keyword.get(elem(enriched, 1), :op_kind)
      assert op_kind != nil
      assert Keyword.get(op_kind, :domain) == :db
      assert Keyword.get(op_kind, :operation) == :retrieve
      assert Keyword.get(op_kind, :target) == "User"
      assert Keyword.get(op_kind, :framework) == :ecto
    end

    test "enriches Repo.get! with target extraction" do
      node = function_call("Repo.get!", [variable("Post"), literal(:integer, 42)])
      enriched = Enricher.enrich(node, :elixir)

      op_kind = Enricher.get_op_kind(enriched)
      assert Keyword.get(op_kind, :operation) == :retrieve
      assert Keyword.get(op_kind, :target) == "Post"
    end

    test "enriches Repo.all" do
      node = function_call("Repo.all", [variable("User")])
      enriched = Enricher.enrich(node, :elixir)

      op_kind = Enricher.get_op_kind(enriched)
      assert Keyword.get(op_kind, :operation) == :retrieve_all
      assert Keyword.get(op_kind, :target) == "User"
    end

    test "enriches Repo.insert" do
      node = function_call("Repo.insert", [variable("changeset")])
      enriched = Enricher.enrich(node, :elixir)

      op_kind = Enricher.get_op_kind(enriched)
      assert Keyword.get(op_kind, :operation) == :create
    end

    test "enriches Repo.update" do
      node = function_call("Repo.update", [variable("changeset")])
      enriched = Enricher.enrich(node, :elixir)

      op_kind = Enricher.get_op_kind(enriched)
      assert Keyword.get(op_kind, :operation) == :update
    end

    test "enriches Repo.delete" do
      node = function_call("Repo.delete", [variable("user")])
      enriched = Enricher.enrich(node, :elixir)

      op_kind = Enricher.get_op_kind(enriched)
      assert Keyword.get(op_kind, :operation) == :delete
    end

    test "enriches Repo.transaction" do
      node = function_call("Repo.transaction", [variable("fun")])
      enriched = Enricher.enrich(node, :elixir)

      op_kind = Enricher.get_op_kind(enriched)
      assert Keyword.get(op_kind, :operation) == :transaction
    end

    test "enriches Repo.preload" do
      node = function_call("Repo.preload", [variable("post"), literal(:symbol, :comments)])
      enriched = Enricher.enrich(node, :elixir)

      op_kind = Enricher.get_op_kind(enriched)
      assert Keyword.get(op_kind, :operation) == :preload
    end

    test "enriches custom Repo module (MyApp.Repo.get)" do
      node = function_call("MyApp.Repo.get", [variable("User"), literal(:integer, 1)])
      enriched = Enricher.enrich(node, :elixir)

      op_kind = Enricher.get_op_kind(enriched)
      assert Keyword.get(op_kind, :operation) == :retrieve
    end
  end

  describe "enrich/2 - Python/SQLAlchemy patterns" do
    test "enriches session.query" do
      node = function_call("session.query", [variable("User")])
      enriched = Enricher.enrich(node, :python)

      op_kind = Enricher.get_op_kind(enriched)
      assert Keyword.get(op_kind, :domain) == :db
      assert Keyword.get(op_kind, :operation) == :query
      assert Keyword.get(op_kind, :framework) == :sqlalchemy
    end

    test "enriches session.add" do
      node = function_call("session.add", [variable("user")])
      enriched = Enricher.enrich(node, :python)

      op_kind = Enricher.get_op_kind(enriched)
      assert Keyword.get(op_kind, :operation) == :create
    end

    test "enriches session.commit" do
      node = function_call("session.commit", [])
      enriched = Enricher.enrich(node, :python)

      op_kind = Enricher.get_op_kind(enriched)
      assert Keyword.get(op_kind, :operation) == :transaction
    end
  end

  describe "enrich/2 - Python/Django patterns" do
    test "enriches Model.objects.get pattern" do
      # Django: User.objects.get(id=1)
      node = function_call("User.objects.get", [variable("kwargs")])
      enriched = Enricher.enrich(node, :python)

      op_kind = Enricher.get_op_kind(enriched)
      assert Keyword.get(op_kind, :domain) == :db
      assert Keyword.get(op_kind, :operation) == :retrieve
      assert Keyword.get(op_kind, :framework) == :django
    end

    test "enriches Model.objects.filter pattern" do
      node = function_call("Post.objects.filter", [variable("kwargs")])
      enriched = Enricher.enrich(node, :python)

      op_kind = Enricher.get_op_kind(enriched)
      assert Keyword.get(op_kind, :operation) == :query
    end

    test "enriches Model.objects.all pattern" do
      node = function_call("Comment.objects.all", [])
      enriched = Enricher.enrich(node, :python)

      op_kind = Enricher.get_op_kind(enriched)
      assert Keyword.get(op_kind, :operation) == :retrieve_all
    end

    test "enriches Model.objects.create pattern" do
      node = function_call("User.objects.create", [variable("kwargs")])
      enriched = Enricher.enrich(node, :python)

      op_kind = Enricher.get_op_kind(enriched)
      assert Keyword.get(op_kind, :operation) == :create
    end
  end

  describe "enrich/2 - Ruby/ActiveRecord patterns" do
    test "enriches Model.find" do
      node = function_call("User.find", [literal(:integer, 1)])
      enriched = Enricher.enrich(node, :ruby)

      op_kind = Enricher.get_op_kind(enriched)
      assert Keyword.get(op_kind, :domain) == :db
      assert Keyword.get(op_kind, :operation) == :retrieve
      assert Keyword.get(op_kind, :framework) == :activerecord
    end

    test "enriches Model.where" do
      node = function_call("Post.where", [variable("conditions")])
      enriched = Enricher.enrich(node, :ruby)

      op_kind = Enricher.get_op_kind(enriched)
      assert Keyword.get(op_kind, :operation) == :query
    end

    test "enriches Model.create" do
      node = function_call("User.create", [variable("attrs")])
      enriched = Enricher.enrich(node, :ruby)

      op_kind = Enricher.get_op_kind(enriched)
      assert Keyword.get(op_kind, :operation) == :create
    end

    test "enriches Model.includes (preload)" do
      node = function_call("Post.includes", [literal(:symbol, :comments)])
      enriched = Enricher.enrich(node, :ruby)

      op_kind = Enricher.get_op_kind(enriched)
      assert Keyword.get(op_kind, :operation) == :preload
    end
  end

  describe "enrich/2 - JavaScript/Sequelize patterns" do
    test "enriches Model.findByPk" do
      node = function_call("User.findByPk", [literal(:integer, 1)])
      enriched = Enricher.enrich(node, :javascript)

      op_kind = Enricher.get_op_kind(enriched)
      assert Keyword.get(op_kind, :domain) == :db
      assert Keyword.get(op_kind, :operation) == :retrieve
      assert Keyword.get(op_kind, :framework) == :sequelize
    end

    test "enriches Model.findAll" do
      node = function_call("Post.findAll", [variable("options")])
      enriched = Enricher.enrich(node, :javascript)

      op_kind = Enricher.get_op_kind(enriched)
      assert Keyword.get(op_kind, :operation) == :retrieve_all
    end

    test "enriches Model.create" do
      node = function_call("User.create", [variable("data")])
      enriched = Enricher.enrich(node, :javascript)

      op_kind = Enricher.get_op_kind(enriched)
      assert Keyword.get(op_kind, :operation) == :create
    end

    test "enriches Model.destroy" do
      node = function_call("User.destroy", [variable("options")])
      enriched = Enricher.enrich(node, :javascript)

      op_kind = Enricher.get_op_kind(enriched)
      assert Keyword.get(op_kind, :operation) == :delete
    end
  end

  describe "enrich/2 - no match" do
    test "returns node unchanged for unknown function" do
      node = function_call("my_custom_function", [variable("arg")])
      enriched = Enricher.enrich(node, :elixir)

      assert enriched == node
      assert Enricher.get_op_kind(enriched) == nil
    end

    test "returns node unchanged for non-function_call nodes" do
      node = variable("x")
      enriched = Enricher.enrich(node, :elixir)

      assert enriched == node
    end
  end

  describe "enrich_tree/2" do
    test "enriches all function calls in a block" do
      ast =
        block([
          function_call("Repo.get", [variable("User"), literal(:integer, 1)]),
          function_call("Repo.all", [variable("Post")]),
          function_call("unknown_function", [])
        ])

      enriched = Enricher.enrich_tree(ast, :elixir)

      {:block, [], [call1, call2, call3]} = enriched

      assert Keyword.get(elem(call1, 1), :op_kind) != nil
      assert Keyword.get(elem(call2, 1), :op_kind) != nil
      assert Keyword.get(elem(call3, 1), :op_kind) == nil
    end

    test "enriches nested function calls" do
      # Repo.preload(Repo.get(User, 1), :posts)
      inner_call = function_call("Repo.get", [variable("User"), literal(:integer, 1)])

      ast = function_call("Repo.preload", [inner_call, literal(:symbol, :posts)])

      enriched = Enricher.enrich_tree(ast, :elixir)

      # Outer call should be enriched
      outer_op_kind = Enricher.get_op_kind(enriched)
      assert Keyword.get(outer_op_kind, :operation) == :preload

      # Inner call should also be enriched
      {:function_call, _, [inner_enriched | _]} = enriched
      inner_op_kind = Enricher.get_op_kind(inner_enriched)
      assert Keyword.get(inner_op_kind, :operation) == :retrieve
    end
  end

  describe "enriched?/1" do
    test "returns true for enriched nodes" do
      node = function_call("Repo.get", [variable("User"), literal(:integer, 1)])
      enriched = Enricher.enrich(node, :elixir)

      assert Enricher.enriched?(enriched)
    end

    test "returns false for non-enriched nodes" do
      node = function_call("unknown", [])
      assert not Enricher.enriched?(node)
    end
  end

  describe "OpKind helpers" do
    test "new/3 creates valid op_kind" do
      op_kind = OpKind.new(:db, :retrieve, target: "User", framework: :ecto)

      assert Keyword.get(op_kind, :domain) == :db
      assert Keyword.get(op_kind, :operation) == :retrieve
      assert Keyword.get(op_kind, :target) == "User"
      assert Keyword.get(op_kind, :framework) == :ecto
      assert Keyword.get(op_kind, :async) == false
    end

    test "valid?/1 validates op_kind" do
      assert OpKind.valid?(domain: :db, operation: :retrieve)
      assert not OpKind.valid?(domain: :invalid, operation: :foo)
      assert not OpKind.valid?("not a keyword list")
    end

    test "db?/1 checks database domain" do
      assert OpKind.db?(domain: :db, operation: :retrieve)
      assert not OpKind.db?(domain: :http, operation: :get)
    end

    test "read?/1 checks read operations" do
      assert OpKind.read?(domain: :db, operation: :retrieve)
      assert OpKind.read?(domain: :db, operation: :retrieve_all)
      assert OpKind.read?(domain: :db, operation: :query)
      assert not OpKind.read?(domain: :db, operation: :create)
    end

    test "write?/1 checks write operations" do
      assert OpKind.write?(domain: :db, operation: :create)
      assert OpKind.write?(domain: :db, operation: :update)
      assert OpKind.write?(domain: :db, operation: :delete)
      assert not OpKind.write?(domain: :db, operation: :retrieve)
    end
  end
end
