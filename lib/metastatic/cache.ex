defmodule Metastatic.Cache do
  @moduledoc """
  AST Caching behaviour and dispatcher for Metastatic.

  Caches the results of parsing and abstracting source code to MetaAST (M2).

  ## Backends

  The backend is selected with `config :metastatic, :cache, backend`:

  - `:ets` (default) — `Metastatic.Cache.ETS`, in-memory, always available.
  - `:dllb` — `Metastatic.Cache.DLLB`, opt-in; requires the host application
    to provide the `Dllb` module and set `config :dllb, :enabled, true`.
  - any module implementing the `Metastatic.Cache` behaviour.

  The default is deliberately `:ets` rather than environment sniffing: a
  library should not silently change behaviour based on what happens to be
  loaded in the host VM.
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

      # Legacy capitalisation alias.
      Metastatic.Cache.Dllb ->
        Metastatic.Cache.DLLB

      mod when is_atom(mod) ->
        mod

      other ->
        raise ArgumentError,
              "Invalid cache configuration: #{inspect(other)}. Expected :ets, :dllb, or a module"
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
