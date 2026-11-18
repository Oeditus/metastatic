defmodule MyLisp.PluginTest do
  @moduledoc """
  Acceptance test for the third-party plug-in architecture.

  This project is a *separate Mix application* that depends on Metastatic. It
  adds the `:lisp` language without editing Metastatic's source. If any of
  these tests fail, the "3rd-party plugins can be added without compiling them
  into metastatic" claim is false.
  """

  use ExUnit.Case, async: false

  alias Metastatic.{Adapter, Builder, Languages}

  describe "registration" do
    test "the plug-in is registered at application boot" do
      assert Languages.supported?(:lisp)
      assert {:ok, MyLisp.Adapters.Lisp} = Languages.get_adapter(:lisp)
    end

    test "its extensions are detected" do
      assert {:ok, :lisp} = Languages.detect_language("program.lisp")
      assert {:ok, :lisp} = Languages.detect_language("program.lsp")
      assert ".lisp" in Languages.supported_extensions()
    end

    test "its flags come from the `use` options" do
      assert Languages.experimental?(:lisp)
      refute Languages.documentation?(:lisp)
    end

    test "it appears alongside the built-ins" do
      languages = Languages.supported_languages()

      assert :lisp in languages
      assert :python in languages
      assert :elixir in languages
    end

    test "the built-ins are untouched" do
      assert {:ok, Metastatic.Adapters.Python} = Languages.get_adapter(:python)
      assert {:ok, :python} = Languages.detect_language("x.py")
    end

    test "the adapter satisfies the Metastatic.Adapter contract" do
      assert Adapter.valid_adapter?(MyLisp.Adapters.Lisp)
      assert MyLisp.Adapters.Lisp.file_extensions() == [".lisp", ".lsp"]
    end
  end

  describe "parsing and abstraction" do
    test "an integer literal" do
      assert {:ok, {:literal, [subtype: :integer], 42}} = Metastatic.quote("42", :lisp)
    end

    test "a symbol becomes a variable" do
      assert {:ok, {:variable, [], "foo"}} = Metastatic.quote("foo", :lisp)
    end

    test "arithmetic maps to the portable :binary_op node" do
      assert {:ok, {:binary_op, [category: :arithmetic, operator: :+], [left, right]}} =
               Metastatic.quote("(+ 1 2)", :lisp)

      assert left == {:literal, [subtype: :integer], 1}
      assert right == {:literal, [subtype: :integer], 2}
    end

    test "nested arithmetic" do
      assert {:ok, {:binary_op, meta, [_one, inner]}} =
               Metastatic.quote("(+ 1 (* 2 3))", :lisp)

      assert Keyword.get(meta, :operator) == :+
      assert {:binary_op, inner_meta, _inner_children} = inner
      assert Keyword.get(inner_meta, :operator) == :*
    end

    test "a function call" do
      assert {:ok, {:function_call, [name: "print"], [_arg]}} =
               Metastatic.quote("(print 1)", :lisp)
    end

    test "a conditional" do
      assert {:ok, {:conditional, [], [_c, _t, _e]}} =
               Metastatic.quote("(if 1 2 3)", :lisp)
    end

    test "invalid syntax returns an error, never raises" do
      assert {:error, _reason} = Metastatic.quote("(+ 1", :lisp)
      assert {:error, _reason} = Metastatic.quote(")", :lisp)
    end
  end

  describe "reification" do
    test "MetaAST renders back to Lisp" do
      ast = {:binary_op, [category: :arithmetic, operator: :+],
             [{:literal, [subtype: :integer], 1}, {:literal, [subtype: :integer], 2}]}

      assert {:ok, "(+ 1 2)"} = Metastatic.unquote(ast, :lisp)
    end

    test "round-trips through the Builder" do
      assert {:ok, "(+ 1 2)"} = Builder.round_trip("(+ 1 2)", :lisp)
    end

    test "from_file/2 auto-detects the extension" do
      path = Path.join(System.tmp_dir!(), "lisp_demo_#{System.unique_integer([:positive])}.lisp")
      File.write!(path, "(+ 10 20)")
      on_exit(fn -> File.rm(path) end)

      assert {:ok, doc} = Builder.from_file(path)
      assert doc.language == :lisp
      assert {:binary_op, meta, _children} = doc.ast
      assert Keyword.get(meta, :operator) == :+
    end
  end

  describe "cross-language translation" do
    test "Lisp MetaAST reifies as Elixir" do
      {:ok, doc} = Builder.from_source("(+ 1 2)", :lisp)

      assert {:ok, elixir_source} = Builder.to_source(doc, :elixir)
      assert elixir_source == "1 + 2"
    end

    test "Lisp MetaAST reifies as Python" do
      {:ok, doc} = Builder.from_source("(* 3 4)", :lisp)

      assert {:ok, python_source} = Builder.to_source(doc, :python)
      assert python_source == "3 * 4"
    end

    test "equivalence holds across the languages" do
      {:ok, lisp} = Builder.from_source("(+ 1 2)", :lisp)
      {:ok, elixir} = Builder.from_source("1 + 2", :elixir)

      assert Metastatic.Document.equivalent?(lisp, elixir)
    end
  end

  describe "semantic enrichment" do
    test "the host pattern provider was registered" do
      # Registered by `Metastatic.Semantic.ensure_registered/0` from
      # `config :metastatic, :semantic, pattern_providers:`.
      refute Metastatic.Semantic.Patterns.get_patterns(:db, :lisp) == []
    end

    test "a known call is annotated with op_kind" do
      {:ok, doc} = Builder.from_source("(db-find User)", :lisp)

      assert {:function_call, meta, _args} = doc.ast
      op_kind = Keyword.get(meta, :op_kind)

      assert op_kind[:domain] == :db
      assert op_kind[:operation] == :retrieve
      assert op_kind[:framework] == :lisp_db
    end

    test "an unknown call is left unannotated" do
      {:ok, doc} = Builder.from_source("(unknown-fn 1)", :lisp)

      assert {:function_call, meta, _} = doc.ast
      assert Keyword.get(meta, :op_kind) == nil
    end

    test "enrichment recovers after a clear_all/0" do
      Metastatic.Semantic.Patterns.clear_all()
      on_exit(fn -> Metastatic.Semantic.ensure_registered() end)

      # `Adapter.abstract/3` re-registers when the tables are empty, so the
      # next parse still annotates rather than silently degrading.
      {:ok, doc} = Builder.from_source("(db-find User)", :lisp)
      assert {:function_call, meta, _} = doc.ast
      assert Keyword.get(meta, :op_kind)[:operation] == :retrieve
    end

    test "a host provider is re-registered even when built-ins are present" do
      # The narrow guarantee: the lazy path must not *wipe* a caller's custom
      # patterns, but the configured host provider is re-applied because
      # `Patterns.register/3` is idempotent. Both must coexist.
      Metastatic.Semantic.Patterns.clear_all()
      on_exit(fn -> Metastatic.Semantic.ensure_registered() end)

      Metastatic.Semantic.Patterns.register(:db, :lisp, [
        {"only-this", %{operation: :retrieve, framework: :narrow, extract_target: :none}}
      ])

      {:ok, _doc} = Builder.from_source("(db-find User)", :lisp)

      patterns = Metastatic.Semantic.Patterns.get_patterns(:db, :lisp)

      assert Enum.any?(patterns, fn {name, _} -> name == "only-this" end)
      assert Enum.any?(patterns, fn {name, _} -> name == "db-find" end)
    end
  end

  describe "demo/0" do
    test "runs end to end" do
      results = MyLisp.demo()

      assert results.languages.registered
      assert results.languages.detected == {:ok, :lisp}
      assert results.round_trip.rendered == "(+ 1 (* 2 3))"
      assert results.enriched.op_kind[:operation] == :retrieve
      assert results.cross_language.elixir == "1 + 2"
    end
  end
end
