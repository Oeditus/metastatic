defmodule Metastatic.CacheTest do
  use ExUnit.Case, async: true

  alias Metastatic.Adapters.Elixir, as: ElixirAdapter
  alias Metastatic.Cache

  setup do
    Cache.clear()
    :ok
  end

  test "stores and retrieves AST and metadata" do
    source = "cache_test_unique_source_x_plus_5"

    meta_ast =
      {:binary_op, [category: :arithmetic, operator: :+],
       [{:variable, [], "x"}, {:literal, [subtype: :integer], 5}]}

    metadata = %{language: :elixir}

    assert Cache.get(ElixirAdapter, source) == {:error, :not_found}

    assert Cache.put(ElixirAdapter, source, meta_ast, metadata) == :ok
    assert Cache.get(ElixirAdapter, source) == {:ok, meta_ast, metadata}
  end

  test "different adapter or source returns not found" do
    source = "cache_test_unique_source_x_plus_5"

    meta_ast =
      {:binary_op, [category: :arithmetic, operator: :+],
       [{:variable, [], "x"}, {:literal, [subtype: :integer], 5}]}

    metadata = %{language: :elixir}

    Cache.put(ElixirAdapter, source, meta_ast, metadata)

    # Different source
    assert Cache.get(ElixirAdapter, "x + 6") == {:error, :not_found}

    # Different adapter
    assert Cache.get(Metastatic.Adapters.Python, source) == {:error, :not_found}
  end

  test "clearing the cache removes all entries" do
    source = "cache_test_unique_source_x_plus_5"

    meta_ast =
      {:binary_op, [category: :arithmetic, operator: :+],
       [{:variable, [], "x"}, {:literal, [subtype: :integer], 5}]}

    metadata = %{language: :elixir}

    Cache.put(ElixirAdapter, source, meta_ast, metadata)
    assert Cache.get(ElixirAdapter, source) == {:ok, meta_ast, metadata}

    Cache.clear()
    assert Cache.get(ElixirAdapter, source) == {:error, :not_found}
  end
end
