defmodule Metastatic.CacheTest do
  use ExUnit.Case, async: false

  alias Metastatic.Adapters.Elixir, as: ElixirAdapter
  alias Metastatic.Cache

  defmodule CustomCache do
    @behaviour Metastatic.Cache

    @impl true
    def init, do: :ok

    @impl true
    def get(_adapter, _source), do: {:ok, :custom_ast, %{custom: true}}

    @impl true
    def put(_adapter, _source, _ast, _meta), do: :ok

    @impl true
    def clear, do: :ok
  end

  setup do
    on_exit(fn ->
      Application.delete_env(:metastatic, :cache)
      Application.delete_env(:dllb, :enabled)
      Cache.clear()
    end)

    Cache.clear()
    :ok
  end

  test "defaults to ETS implementation" do
    assert Cache.impl() == Metastatic.Cache.ETS
  end

  test "config option :metastatic, :cache configures backend" do
    Application.put_env(:metastatic, :cache, :ets)
    assert Cache.impl() == Metastatic.Cache.ETS

    Application.put_env(:metastatic, :cache, :dllb)
    assert Cache.impl() == Metastatic.Cache.DLLB

    Application.put_env(:metastatic, :cache, Metastatic.Cache.ETS)
    assert Cache.impl() == Metastatic.Cache.ETS

    Application.put_env(:metastatic, :cache, Metastatic.Cache.DLLB)
    assert Cache.impl() == Metastatic.Cache.DLLB

    Application.put_env(:metastatic, :cache, Metastatic.Cache.Dllb)
    assert Cache.impl() == Metastatic.Cache.DLLB
  end

  test "custom cache implementation works via configuration" do
    Application.put_env(:metastatic, :cache, CustomCache)
    assert Cache.impl() == CustomCache

    source = "custom_test_source"
    assert Cache.init() == :ok
    assert Cache.get(ElixirAdapter, source) == {:ok, :custom_ast, %{custom: true}}
    assert Cache.put(ElixirAdapter, source, :ast, %{}) == :ok
    assert Cache.clear() == :ok
  end

  test "raises ArgumentError on invalid cache configuration" do
    Application.put_env(:metastatic, :cache, 123)

    assert_raise ArgumentError, ~r/Invalid cache configuration/, fn ->
      Cache.impl()
    end
  end

  test "stores and retrieves AST and metadata using default ETS cache" do
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

  test "ETS capacity eviction resets cache when max capacity reached" do
    # Artificially insert max capacity entries to trigger flush
    for i <- 1..2_001 do
      Metastatic.Cache.ETS.put(ElixirAdapter, "source_#{i}", {:node, [], []}, %{})
    end

    # After capacity flush, old entry from first batch should be deleted
    assert Metastatic.Cache.ETS.get(ElixirAdapter, "source_1") == {:error, :not_found}
    # Newest entry remains inserted after flush
    assert Metastatic.Cache.ETS.get(ElixirAdapter, "source_2001") == {:ok, {:node, [], []}, %{}}
  end

  test "DLLB backend returns :not_found / :ok gracefully when Dllb is disabled" do
    Application.put_env(:metastatic, :cache, :dllb)
    Application.put_env(:dllb, :enabled, false)
    source = "cache_test_dllb_source"

    assert Cache.impl() == Metastatic.Cache.DLLB
    assert Cache.init() == :ok
    assert Cache.get(ElixirAdapter, source) == {:error, :not_found}
    assert Cache.put(ElixirAdapter, source, {:dummy}, %{}) == :ok
    assert Cache.clear() == :ok
  end

  test "DLLB backend handles connection errors gracefully when Dllb is enabled but unreachable" do
    Application.put_env(:metastatic, :cache, :dllb)
    Application.put_env(:dllb, :enabled, true)
    source = "cache_test_dllb_enabled_source"

    assert Cache.impl() == Metastatic.Cache.DLLB
    assert Cache.get(ElixirAdapter, source) == {:error, :not_found}
    assert Cache.put(ElixirAdapter, source, {:dummy}, %{}) == :ok
    assert Cache.clear() == :ok
  end
end
