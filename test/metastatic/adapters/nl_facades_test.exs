defmodule Metastatic.Adapters.NLFacadesTest do
  @moduledoc """
  Tests for the thin `Metastatic.Adapters.English` and `Metastatic.Adapters.Spanish`
  facades that forward to the `Metastatic.NL.Adapters.*` implementations.

  These exist so the NL adapters are reachable through the same
  `Metastatic.Adapter` surface as the programming-language adapters.
  """

  use ExUnit.Case, async: true

  alias Metastatic.{Adapter, Adapters.English, Adapters.Spanish}

  describe "English facade" do
    test "implements the Adapter behaviour" do
      assert Adapter.valid_adapter?(English)
    end

    test "exposes prose file extensions" do
      assert English.file_extensions() == [".md", ".markdown", ".txt", ".rst"]
    end

    test "parses and abstracts a sentence to NL-MetaAST" do
      {:ok, cst} = English.parse("The quick brown fox jumps.")
      {:ok, meta_ast, _metadata} = English.to_meta(cst)

      assert is_tuple(meta_ast)
      assert elem(meta_ast, 0) in [:document, :sentence, :paragraph, :section]
    end

    test "round-trips through from_meta and unparse" do
      {:ok, cst} = English.parse("Hello world.")
      {:ok, meta_ast, metadata} = English.to_meta(cst)
      {:ok, native} = English.from_meta(meta_ast, metadata)
      {:ok, source} = English.unparse(native)

      assert is_binary(source)
    end
  end

  describe "Spanish facade" do
    test "implements the Adapter behaviour" do
      assert Adapter.valid_adapter?(Spanish)
    end

    test "exposes Spanish prose file extensions" do
      assert Spanish.file_extensions() == [".es.md", ".es.txt"]
    end

    test "parses and abstracts a sentence to NL-MetaAST" do
      {:ok, cst} = Spanish.parse("El rápido zorro marrón salta.")
      {:ok, meta_ast, _metadata} = Spanish.to_meta(cst)

      assert is_tuple(meta_ast)
    end

    test "round-trips through from_meta and unparse" do
      {:ok, cst} = Spanish.parse("Hola mundo.")
      {:ok, meta_ast, metadata} = Spanish.to_meta(cst)
      {:ok, native} = Spanish.from_meta(meta_ast, metadata)
      {:ok, source} = Spanish.unparse(native)

      assert is_binary(source)
    end
  end
end
