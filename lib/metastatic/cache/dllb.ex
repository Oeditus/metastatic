defmodule Metastatic.Cache.DLLB do
  @moduledoc """
  `Dllb` database implementation of `Metastatic.Cache`.

  Caches MetaAST entries in a Dllb database instance if available.

  This backend is **opt-in**: it is only active when the optional `:dllb`
  dependency is present *and* `config :dllb, :enabled, true` is set. The
  default cache backend is `Metastatic.Cache.ETS`.

  ## Trust model

  Payloads are round-tripped with `:erlang.term_to_binary/2` and decoded with
  `:erlang.binary_to_term/2` using the `[:safe]` option. Decoding a payload
  that contains atoms not already present in the VM raises `ArgumentError`
  instead of creating them, so a tampered or foreign database cannot be used
  for atom exhaustion or remote code execution.
  """

  @behaviour Metastatic.Cache
  @compile {:no_warn_undefined, Dllb}

  # Bound on how long a cached entry is considered fresh. Bump this whenever
  # a parser/abstraction change makes previously cached MetaAST stale.
  @cache_version 1

  @impl true
  @spec init() :: :ok
  def init do
    :ok
  end

  @impl true
  @spec get(module(), String.t()) :: {:ok, term(), map()} | {:error, :not_found}
  def get(adapter, source) do
    if dllb_available?() do
      id = cache_id(adapter, source)
      query_str = "SELECT * FROM metastatic_cache:#{id}"

      try do
        case Dllb.query(query_str) do
          {:ok, %{data: [row | _]}} -> decode_dllb_row(row)
          _ -> {:error, :not_found}
        end
      rescue
        _ -> {:error, :not_found}
      catch
        _, _ -> {:error, :not_found}
      end
    else
      {:error, :not_found}
    end
  end

  @impl true
  @spec put(module(), String.t(), term(), map()) :: :ok
  def put(adapter, source, meta_ast, metadata) do
    if dllb_available?() do
      id = cache_id(adapter, source)
      bin = :erlang.term_to_binary({meta_ast, metadata}, [:compressed])
      b64 = Base.encode64(bin)

      # `id` is a lowercase hex digest and `b64` is base64, so neither can
      # contain a quote; the interpolation below is therefore injection-safe.
      query_str = "CREATE metastatic_cache:#{id} SET payload = '#{b64}' ON CONFLICT UPDATE"

      try do
        Dllb.query(query_str)
        :ok
      rescue
        _ -> :ok
      catch
        _, _ -> :ok
      end
    else
      :ok
    end
  end

  @impl true
  @spec clear() :: :ok
  def clear do
    if dllb_available?() do
      try do
        Dllb.query("DELETE metastatic_cache")
        :ok
      rescue
        _ -> :ok
      catch
        _, _ -> :ok
      end
    else
      :ok
    end
  end

  # -- Private Helpers --

  defp dllb_available? do
    if Code.ensure_loaded?(Dllb) and Application.get_env(:dllb, :enabled, false) do
      try do
        match?({:ok, %{}}, Dllb.query("SELECT * FROM _dllb_ping_"))
      rescue
        _ -> false
      catch
        _, _ -> false
      end
    else
      false
    end
  end

  defp cache_id(adapter, source) do
    # The cache version is part of the key so that a parser upgrade never
    # serves stale MetaAST produced by an older abstraction.
    payload = "v#{@cache_version}:#{inspect(adapter)}:#{source}"
    hash = :crypto.hash(:sha256, payload) |> Base.encode16(case: :lower)
    "ast_#{hash}"
  end

  defp decode_dllb_row(row) when is_map(row) do
    payload_b64 = Map.get(row, "payload") || Map.get(row, :payload)

    if payload_b64 && is_binary(payload_b64) do
      decode_payload(payload_b64)
    else
      {:error, :not_found}
    end
  end

  defp decode_dllb_row(_), do: {:error, :not_found}

  # Decode a base64 payload into `{meta_ast, metadata}`.
  #
  # `:erlang.binary_to_term/2` is called with `[:safe]`, which refuses to
  # create atoms that are not already in the VM. A payload that references
  # an unknown atom raises `ArgumentError`; we treat that (and any other
  # malformed payload) as a cache miss rather than propagating the crash.
  defp decode_payload(payload_b64) do
    case Base.decode64(payload_b64) do
      {:ok, bin} ->
        case :erlang.binary_to_term(bin, [:safe]) do
          {meta_ast, metadata} -> {:ok, meta_ast, metadata}
          _ -> {:error, :not_found}
        end

      :error ->
        {:error, :not_found}
    end
  rescue
    ArgumentError -> {:error, :not_found}
  end
end
