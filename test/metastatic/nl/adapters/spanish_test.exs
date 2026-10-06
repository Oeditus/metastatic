defmodule Metastatic.NL.Adapters.SpanishTest do
  use ExUnit.Case, async: true
  alias Metastatic.Adapter
  alias Metastatic.NL.Adapters.Spanish
  alias Metastatic.NL.AST
  alias Metastatic.NL.Lint.Rules.AvoidPassiveVoice
  alias Metastatic.NL.Lint.Runner

  describe "adapter behaviour conformance" do
    test "implements Metastatic.Adapter behaviour" do
      assert Adapter.valid_adapter?(Spanish)
      assert Adapter.valid_adapter?(Metastatic.Adapters.Spanish)
      assert ".es.md" in Spanish.file_extensions()
    end
  end

  describe "spanish parsing and cross-lingual rule execution" do
    test "parses Spanish sentence into NL-MetaAST" do
      text = "El servidor procesa las peticiones rápidamente."
      assert {:ok, cst} = Spanish.parse(text)
      assert {:ok, doc, meta} = Spanish.to_meta(cst)

      assert meta.language == :es
      assert AST.conforms?(doc)
      assert length(AST.sentences(doc)) == 1

      words = AST.words(doc)
      assert "servidor" in words
      assert "procesa" in words
    end

    test "cross-lingual passive voice linting on Spanish prose" do
      text = "La migración fue ejecutada por el operador."
      assert {:ok, cst} = Spanish.parse(text)
      assert {:ok, doc, _} = Spanish.to_meta(cst)

      [clause] = AST.clauses(doc)
      assert AST.get_meta(clause, :voice) == :passive

      # Execute English/Universal rule AvoidPassiveVoice on Spanish AST!
      issues = Runner.lint(doc, rules: [AvoidPassiveVoice])
      assert length(issues) == 1
      [issue] = issues
      assert issue.rule == :avoid_passive_voice
      assert issue.message =~ "La migración fue ejecutada por el operador"
      assert issue.suggestion =~ "operador"
    end
  end
end
