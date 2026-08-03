defmodule Metastatic.Cache.ETS do
  @moduledoc """
  ETS implementation of `Metastatic.Cache`.

  Uses a public ETS table for high-performance memory caching.
  """

  @behaviour Metastatic.Cache

  @table :metastatic_ast_cache
  @max_entries 2_000

  @impl true
  @spec init() :: :ok
  def init do
    if :ets.info(@table) == :undefined do
      :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    end

    :ok
  end

  @impl true
  @spec get(module(), String.t()) :: {:ok, term(), map()} | {:error, :not_found}
  def get(adapter, source) do
    init()
    hash = :erlang.md5(source)

    case :ets.lookup(@table, {adapter, hash}) do
      [{_, meta_ast, metadata}] -> {:ok, meta_ast, metadata}
      [] -> {:error, :not_found}
    end
  end

  @impl true
  @spec put(module(), String.t(), term(), map()) :: :ok
  def put(adapter, source, meta_ast, metadata) do
    init()

    # Enforce max capacity ceiling to prevent OOM
    if :ets.info(@table, :size) >= @max_entries do
      :ets.delete_all_objects(@table)
    end

    hash = :erlang.md5(source)
    :ets.insert(@table, {{adapter, hash}, meta_ast, metadata})
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
end
