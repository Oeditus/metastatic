defmodule Metastatic.Cache do
  @moduledoc """
  AST Caching layer for Metastatic.

  Caches the results of parsing and abstracting source code to MetaAST (M2).
  Uses a public ETS table for high-performance memory cache.
  """

  @table :metastatic_ast_cache

  @doc """
  Initialize the cache ETS table.
  Called automatically during application startup.
  """
  @spec init() :: :ok
  def init do
    if :ets.info(@table) == :undefined do
      :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    end

    :ok
  end

  @doc """
  Get cached abstraction result (MetaAST + Metadata) for a source code string and language.

  Returns `{:ok, meta_ast, metadata}` if found, or `{:error, :not_found}`.
  """
  @spec get(module(), String.t()) :: {:ok, term(), map()} | {:error, :not_found}
  def get(adapter, source) do
    # Ensure table exists
    init()
    hash = :erlang.md5(source)

    case :ets.lookup(@table, {adapter, hash}) do
      [{_, meta_ast, metadata}] -> {:ok, meta_ast, metadata}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Store abstraction result in cache.
  """
  @spec put(module(), String.t(), term(), map()) :: :ok
  def put(adapter, source, meta_ast, metadata) do
    # Ensure table exists
    init()
    hash = :erlang.md5(source)
    :ets.insert(@table, {{adapter, hash}, meta_ast, metadata})
    :ok
  end

  @doc """
  Clear all cached entries.
  """
  @spec clear() :: :ok
  def clear do
    if :ets.info(@table) != :undefined do
      :ets.delete_all_objects(@table)
    end

    :ok
  end
end
