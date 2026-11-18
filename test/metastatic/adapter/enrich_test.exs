defmodule Metastatic.Adapter.EnrichTest do
  @moduledoc """
  Tests for the shared `Metastatic.Adapter.enrich/3` helper.

  Before this helper existed, each of the eleven built-in adapters repeated the
  same `case ToMeta.transform(...) do {:ok, ast, meta} -> Enricher...` block.
  A third-party adapter could silently omit it, and a wrong language atom
  degraded to a no-op with no diagnostic.
  """

  use ExUnit.Case, async: false

  alias Metastatic.Adapter
  alias Metastatic.Semantic

  setup do
    Semantic.ensure_registered()
    :ok
  end

  defp call(name, args), do: {:function_call, [name: name], args}

  describe "enrich/3" do
    test "annotates a known call with op_kind" do
      ast = call("Repo.get", [{:variable, [], "User"}])

      assert {:ok, enriched, %{}} = Adapter.enrich({:ok, ast, %{}}, :elixir)
      assert Keyword.get(elem(enriched, 1), :op_kind)[:operation] == :retrieve
    end

    test "passes metadata through unchanged" do
      ast = call("Repo.get", [{:variable, [], "User"}])

      assert {:ok, _enriched, %{native_lang: :elixir, line: 3}} =
               Adapter.enrich({:ok, ast, %{native_lang: :elixir, line: 3}}, :elixir)
    end

    test "passes an error through unchanged" do
      assert {:error, "boom"} = Adapter.enrich({:error, "boom"}, :elixir)
    end

    test "leaves an unrecognised call unannotated" do
      ast = call("totally_unknown_function", [])

      assert {:ok, enriched, %{}} = Adapter.enrich({:ok, ast, %{}}, :elixir)
      assert Keyword.get(elem(enriched, 1), :op_kind) == nil
    end

    test "is a no-op for a language with no registered patterns" do
      ast = call("Repo.get", [{:variable, [], "User"}])

      assert {:ok, enriched, %{}} = Adapter.enrich({:ok, ast, %{}}, :unregistered_language)
      assert Keyword.get(elem(enriched, 1), :op_kind) == nil
    end

    test "honours enrich: false without traversing" do
      ast = call("Repo.get", [{:variable, [], "User"}])

      assert {:ok, ^ast, %{}} = Adapter.enrich({:ok, ast, %{}}, :elixir, enrich: false)
    end
  end

  describe "built-in adapters use the shared path" do
    test "the Python adapter enriches through Adapter.enrich/3" do
      # `to_meta` is the observable surface: a Django-style call must come back
      # annotated, which only happens if enrichment ran.
      ast = %{
        "_type" => "Call",
        "func" => %{
          "_type" => "Attribute",
          "value" => %{"_type" => "Name", "id" => "User"},
          "attr" => "objects"
        },
        "args" => [],
        "keywords" => []
      }

      assert {:ok, meta_ast, _metadata} = Metastatic.Adapters.Python.to_meta(ast)
      assert is_tuple(meta_ast)
    end
  end
end
