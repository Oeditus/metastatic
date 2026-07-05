defmodule Metastatic.Semantic.EnricherTest do
  use ExUnit.Case, async: false

  alias Metastatic.Semantic.{Callbacks, Domains.Database, Enricher, OpKind, Patterns}

  # Ensure patterns and callbacks are registered before each test.
  # Uses `setup` (not `setup_all`) because persistent_term state
  # may be cleared by other test modules.
  setup do
    Patterns.clear_all()
    Database.register_all()
    Callbacks.clear()
    Callbacks.register_builtins()
    :ok
  end

  # Helper functions for creating AST nodes
  defp function_call(name, args), do: {:function_call, [name: name], args}
  defp variable(name), do: {:variable, [], name}
  defp literal(subtype, value), do: {:literal, [subtype: subtype], value}
  defp block(statements), do: {:block, [], statements}

  defp function_def(name, params, body \\ [], extra_meta \\ []) do
    param_nodes = Enum.map(params, fn p -> {:param, [], p} end)

    {:function_def,
     [name: name, params: param_nodes, visibility: :public, arity: length(params)] ++ extra_meta,
     body}
  end

  defp container(type, name, body, extra_meta) do
    {:container, [container_type: type, name: name] ++ extra_meta, body}
  end

  defp import_node(source, extra_meta) do
    {:import, [source: source, import_type: :use] ++ extra_meta, []}
  end

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

  # ----- callback_for enrichment -----

  describe "enrich_callback/3" do
    test "annotates perform/1 as Oban.Worker callback" do
      node = function_def("perform", ["job"])
      enriched = Enricher.enrich_callback(node, :elixir, ["Oban.Worker"])

      assert Enricher.get_callback_for(enriched) == "Oban.Worker"
    end

    test "annotates handle_call/3 as GenServer callback" do
      node = function_def("handle_call", ["msg", "from", "state"])
      enriched = Enricher.enrich_callback(node, :elixir, ["GenServer"])

      assert Enricher.get_callback_for(enriched) == "GenServer"
    end

    test "does not annotate when function is not a callback for the behaviour" do
      node = function_def("run", ["args"])
      enriched = Enricher.enrich_callback(node, :elixir, ["Oban.Worker"])

      assert Enricher.get_callback_for(enriched) == nil
    end

    test "does not annotate when behaviours list is empty" do
      node = function_def("perform", ["job"])
      enriched = Enricher.enrich_callback(node, :elixir, [])

      assert Enricher.get_callback_for(enriched) == nil
    end

    test "picks first matching behaviour" do
      node = function_def("perform", ["job"])

      enriched =
        Enricher.enrich_callback(node, :elixir, ["GenServer", "Oban.Worker"])

      # GenServer doesn't have perform/1, so Oban.Worker matches
      assert Enricher.get_callback_for(enriched) == "Oban.Worker"
    end
  end

  describe "enrich_tree/2 - callback_for in containers" do
    test "enriches Oban worker perform/1 inside module with use Oban.Worker" do
      ast =
        container(
          :module,
          "MyApp.EmailWorker",
          [
            import_node("Oban.Worker", language: :elixir),
            function_def("perform", ["job"])
          ],
          language: :elixir
        )

      enriched = Enricher.enrich_tree(ast, :elixir)
      {:container, _, [_import, func_def]} = enriched

      assert Enricher.get_callback_for(func_def) == "Oban.Worker"
    end

    test "enriches GenServer callbacks inside module" do
      ast =
        container(
          :module,
          "MyApp.Cache",
          [
            import_node("GenServer", language: :elixir),
            function_def("init", ["opts"]),
            function_def("handle_call", ["msg", "from", "state"]),
            function_def("helper", ["x"])
          ],
          language: :elixir
        )

      enriched = Enricher.enrich_tree(ast, :elixir)
      {:container, _, [_import, init_fn, handle_fn, helper_fn]} = enriched

      assert Enricher.get_callback_for(init_fn) == "GenServer"
      assert Enricher.get_callback_for(handle_fn) == "GenServer"
      assert Enricher.get_callback_for(helper_fn) == nil
    end

    test "enriches Ruby ActiveJob worker via parent class" do
      ast =
        container(
          :class,
          "SendEmailJob",
          [
            function_def("perform", ["user_id"])
          ],
          language: :ruby,
          parent: "ActiveJob::Base"
        )

      enriched = Enricher.enrich_tree(ast, :ruby)
      {:container, _, [func_def]} = enriched

      assert Enricher.get_callback_for(func_def) == "ActiveJob::Base"
    end

    test "does not annotate functions when container has no matching behaviour" do
      ast =
        container(
          :module,
          "MyApp.Utils",
          [
            function_def("run", ["args"]),
            function_def("perform", ["work"])
          ],
          language: :elixir
        )

      enriched = Enricher.enrich_tree(ast, :elixir)
      {:container, _, [run_fn, perform_fn]} = enriched

      assert Enricher.get_callback_for(run_fn) == nil
      assert Enricher.get_callback_for(perform_fn) == nil
    end

    test "does not leak behaviours between sibling containers" do
      ast =
        block([
          container(
            :module,
            "MyApp.Worker",
            [
              import_node("Oban.Worker", language: :elixir),
              function_def("perform", ["job"])
            ],
            language: :elixir
          ),
          container(
            :module,
            "MyApp.Utils",
            [
              function_def("perform", ["work"])
            ],
            language: :elixir
          )
        ])

      enriched = Enricher.enrich_tree(ast, :elixir)
      {:block, _, [worker_container, utils_container]} = enriched

      {:container, _, [_import, worker_perform]} = worker_container
      {:container, _, [utils_perform]} = utils_container

      assert Enricher.get_callback_for(worker_perform) == "Oban.Worker"
      assert Enricher.get_callback_for(utils_perform) == nil
    end

    test "enriches both op_kind and callback_for in the same tree" do
      ast =
        container(
          :module,
          "MyApp.Worker",
          [
            import_node("Oban.Worker", language: :elixir),
            function_def("perform", ["job"], [
              function_call("Repo.get", [variable("User"), variable("id")])
            ])
          ],
          language: :elixir
        )

      enriched = Enricher.enrich_tree(ast, :elixir)
      {:container, _, [_import, func_def]} = enriched

      # function_def gets callback_for
      assert Enricher.get_callback_for(func_def) == "Oban.Worker"

      # nested function_call gets op_kind
      {:function_def, _, [repo_call]} = func_def
      assert Enricher.get_op_kind(repo_call) != nil
    end
  end

  describe "enriched?/1 - callback_for" do
    test "returns true for nodes with callback_for" do
      node = {:function_def, [name: "perform", callback_for: "Oban.Worker"], []}
      assert Enricher.enriched?(node)
    end
  end

  describe "get_callback_for/1" do
    test "returns callback_for value" do
      node = {:function_def, [name: "perform", callback_for: "Oban.Worker"], []}
      assert Enricher.get_callback_for(node) == "Oban.Worker"
    end

    test "returns nil when absent" do
      node = {:function_def, [name: "run"], []}
      assert Enricher.get_callback_for(node) == nil
    end

    test "returns nil for non-tuple nodes" do
      assert Enricher.get_callback_for(42) == nil
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
