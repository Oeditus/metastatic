defmodule Metastatic.Cache.ETS do
  @moduledoc """
  ETS implementation of `Metastatic.Cache`.

  Uses a public ETS table for high-performance in-memory caching.

  ## Eviction

  When the table reaches `@max_entries`, the **oldest** `@evict_batch`
  entries (by insertion timestamp) are removed in one pass. This avoids the
  historical cliff where the entire table was wiped at once, which caused a
  latency spike and a cold-cache thundering herd.

  ## Versioning

  Cache keys include a version tag. Bump `@cache_version` whenever a parser
  or abstraction change makes previously cached MetaAST stale; old entries
  then simply miss and are re-populated.
  """

  @behaviour Metastatic.Cache

  @table :metastatic_ast_cache
  @max_entries 2_000
  @evict_batch 200
  @cache_version 1

  @impl true
  @spec init() :: :ok
  def init do
    if :ets.info(@table) == :undefined do
      # `:ordered_set` keyed by `{adapter, hash}`; the insertion timestamp
      # lives in the value tuple so eviction can sort by age.
      :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    end

    :ok
  end

  @impl true
  @spec get(module(), String.t()) :: {:ok, term(), map()} | {:error, :not_found}
  def get(adapter, source) do
    init()
    key = cache_key(adapter, source)

    case :ets.lookup(@table, key) do
      [{^key, _inserted_at, meta_ast, metadata}] -> {:ok, meta_ast, metadata}
      [] -> {:error, :not_found}
    end
  end

  @impl true
  @spec put(module(), String.t(), term(), map()) :: :ok
  def put(adapter, source, meta_ast, metadata) do
    init()
    evict_if_needed()

    key = cache_key(adapter, source)
    :ets.insert(@table, {key, System.monotonic_time(), meta_ast, metadata})
    :ok
  end

  @impl true
  @spec clear() :: :ok
  def clear do
    if :ets.info(@table) != :undefined do
      :ets.delete_all_objects(@table)
    end

    :ok
  end

  # -- Private Helpers --

  defp cache_key(adapter, source) do
    hash = :erlang.md5(source)
    {adapter, @cache_version, hash}
  end

  # Evict the oldest `@evict_batch` entries once the table is full.
  # `:ets.info(@table, :size)` is O(1); the sort is bounded by the table size
  # and only runs at the eviction boundary.
  defp evict_if_needed do
    if :ets.info(@table, :size) >= @max_entries do
      @table
      |> :ets.tab2list()
      |> Enum.sort_by(fn {_key, inserted_at, _ast, _meta} -> inserted_at end)
      |> Enum.take(@evict_batch)
      |> Enum.each(fn {key, _ts, _ast, _meta} -> :ets.delete(@table, key) end)
    end

    :ok
  end
end
