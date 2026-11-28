defmodule Metastatic.Adapter.Bridge.Cache do
  @moduledoc """
  Shared user-cache build helper for compiled parser bridges.

  Compiled bridges (Go, Agda, and source fallbacks for Rust/SQL/Haskell/March)
  should never write build artefacts into `priv/` (which may be read-only in a
  release or Hex dependency) and should not recompile on every parse.

  This module builds an executable once into
  `:filename.basedir(:user_cache, "metastatic")`, keyed by a SHA-256 digest of
  the toolchain, target architecture, and source contents:

  1. concurrent first builds are serialised with `:global.trans/2`,
  2. the build writes to a unique sibling temp path,
  3. the finished binary is installed atomically with `File.rename/2`,
  4. failed builds never leave a partial binary behind.
  """

  @doc """
  Returns a cached executable for `language`/`binary_name`, building it once
  via `build_fn.(temp_path)` when absent.

  `key_inputs` is iodata (typically `[toolchain_path, arch, source_contents]`)
  hashed with SHA-256 to derive the cache directory.

  `build_fn` receives a temporary output path and must return `:ok` on success
  or `{:error, reason}` on failure.
  """
  @spec fetch_or_build(atom(), String.t(), iodata(), (Path.t() -> :ok | {:error, String.t()})) ::
          {:ok, Path.t()} | {:error, String.t()}
  def fetch_or_build(language, binary_name, key_inputs, build_fn)
      when is_atom(language) and is_binary(binary_name) and is_function(build_fn, 1) do
    digest =
      :crypto.hash(:sha256, [:erlang.system_info(:system_architecture), key_inputs])
      |> Base.encode16(case: :lower)

    cache_dir = :filename.basedir(:user_cache, "metastatic") |> to_string()
    destination = Path.join([cache_dir, to_string(language), digest, binary_name])

    :global.trans({{__MODULE__, destination}, self()}, fn ->
      if executable_file?(destination) do
        {:ok, destination}
      else
        compile_to_cache(destination, build_fn)
      end
    end)
  end

  @doc """
  Returns `true` when `path` is an existing regular file with any execute bit set.
  """
  @spec executable_file?(Path.t()) :: boolean()
  def executable_file?(path) when is_binary(path) do
    case File.stat(path) do
      {:ok, %{type: :regular, mode: mode}} -> Bitwise.band(mode, 0o111) != 0
      _ -> false
    end
  end

  defp compile_to_cache(destination, build_fn) do
    suffix = Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)
    temporary = destination <> "." <> suffix

    case File.mkdir_p(Path.dirname(destination)) do
      :ok ->
        do_compile(temporary, destination, build_fn)

      {:error, reason} ->
        {:error, "Cannot create parser cache directory: #{inspect(reason)}"}
    end
  end

  defp do_compile(temporary, destination, build_fn) do
    case build_fn.(temporary) do
      :ok ->
        case File.rename(temporary, destination) do
          :ok -> {:ok, destination}
          {:error, reason} -> {:error, "Cannot install cached parser binary: #{inspect(reason)}"}
        end

      {:error, _reason} = error ->
        error
    end
  after
    File.rm(temporary)
  end
end
