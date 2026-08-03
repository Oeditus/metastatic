defmodule Metastatic.Cache do
  @moduledoc """
  AST Caching behaviour and dispatcher for Metastatic.

  Caches the results of parsing and abstracting source code to MetaAST (M2).
  Supports multiple backends (ETS, DLLB), configured via `:metastatic, :cache`.

  Default backend is `:ets`.
  """

  @callback init() :: :ok
  @callback get(adapter :: module(), source :: String.t()) ::
              {:ok, term(), map()} | {:error, :not_found}
  @callback put(adapter :: module(), source :: String.t(), meta_ast :: term(), metadata :: map()) ::
              :ok
  @callback clear() :: :ok

  @doc """
  Return the configured cache implementation module.

  Options for `:metastatic, :cache` are:
  - `:ets` (default) -> `Metastatic.Cache.ETS`
  - `:dllb` -> `Metastatic.Cache.DLLB`
  - A module implementing `Metastatic.Cache`
  """
  @spec impl() :: module()
  def impl do
    case Application.get_env(:metastatic, :cache, :ets) do
      :ets ->
        Metastatic.Cache.ETS

      :dllb ->
        Metastatic.Cache.DLLB

      Metastatic.Cache.ETS ->
        Metastatic.Cache.ETS

      Metastatic.Cache.DLLB ->
        Metastatic.Cache.DLLB

      Metastatic.Cache.Dllb ->
        Metastatic.Cache.DLLB

      mod when is_atom(mod) ->
        mod

      other ->
        raise ArgumentError,
              "Invalid cache configuration: #{inspect(other)}. Expected :ets or :dllb"
    end
  end

  @doc """
  Initialize the active cache backend.
  Called automatically during application startup.
  """
  @spec init() :: :ok
  def init do
    impl().init()
  end

  @doc """
  Get cached abstraction result (MetaAST + Metadata) for a source code string and language.
  """
  @spec get(module(), String.t()) :: {:ok, term(), map()} | {:error, :not_found}
  def get(adapter, source) do
    impl().get(adapter, source)
  end

  @doc """
  Store abstraction result in cache.
  """
  @spec put(module(), String.t(), term(), map()) :: :ok
  def put(adapter, source, meta_ast, metadata) do
    impl().put(adapter, source, meta_ast, metadata)
  end

  @doc """
  Clear all cached entries from the active cache backend.
  """
  @spec clear() :: :ok
  def clear do
    impl().clear()
  end
end
