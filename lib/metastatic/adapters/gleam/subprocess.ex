defmodule Metastatic.Adapters.Gleam.Subprocess do
  @moduledoc """
  Runs the `metastatic-gleam-parser` bridge.

  Gleam has no parser on the BEAM, so this adapter shells out to a small Rust
  CLI built from `priv/parsers/gleam/`. That bridge links against the **Gleam
  compiler's own** `gleam-core` parser and `gleam-format` printer — both
  vendored under `priv/parsers/gleam/vendor/` — so what this adapter sees is
  exactly what `gleam build` sees, including syntax the bridge itself does not
  model.

  ## Two builds

  The bridge has two compile-time configurations, and `build/0` reports which
  one is in use:

    * `:vendored` — the default. Links the Gleam compiler's own parser and
      printer, vendored under `priv/parsers/gleam/vendor/`. Full MetaAST
      fidelity, no `gleam` toolchain at runtime, ~4.9 MB in the package.
    * `:external_gleam` — what `HEX_BUILD=1` ships. No vendored crates: it
      shells out to `gleam format --stdin` for `format`/`unparse` and reports
      that `parse` is unsupported. The package drops ~4.9 MB and needs `gleam`
      on `PATH`.

  `parse/1` on an `:external_gleam` bridge returns a clear
  `{:error, reason}` rather than a wrong tree, so a caller can detect the
  configuration instead of silently getting an incomplete MetaAST.

  ## Resolution order

  `executable/0` looks for, in order:

    1. `priv/parsers/gleam/bin/metastatic-gleam-parser` — a prebuilt binary,
       which is what a read-only release should ship;
    2. `priv/parsers/gleam/target/release/metastatic-gleam-parser` — a local
       `cargo build --release`;
    3. `metastatic-gleam-parser` on `PATH`;
    4. `cargo`, which builds the bundled sources on demand.

  Step 4 builds **once** into the user's cache directory, keyed by a digest of
  the sources, the cargo executable, the target architecture *and the selected
  feature set*, so the two builds never share a cache entry and editing a
  source file invalidates the cache automatically. Concurrent callers serialise
  on the first build. A failed build is never installed as a working
  executable.

  ## Protocol

  The bridge reads its input from the file path given as its last argument and
  writes one JSON object to stdout:

      {"ok": true,  "ast": {...}}
      {"ok": true,  "source": "..."}
      {"ok": false, "error": {"type": "ParseError", "msg": "...", "line": 3}}

  That is the canonical shape `Metastatic.Adapter.Bridge.decode/1` already
  accepts, so no bespoke decoder lives here.

  ## Failure modes

  A missing Rust toolchain, a failed build, a crashing child and a malformed
  response all come back as `{:error, reason}`. Nothing raises.
  """

  alias Metastatic.Adapter.Bridge
  alias Metastatic.{Priv, Subprocess}

  @binary "metastatic-gleam-parser"
  @source_dir "parsers/gleam"

  # The feature set each build is compiled with. `:vendored` is Cargo's default
  # feature set (so the flag list is empty); `:external_gleam` turns the default
  # off and selects the one feature that replaces it.
  @feature_args %{
    vendored: [],
    external_gleam: ["--no-default-features", "--features", "external-gleam"]
  }

  @doc """
  Parses Gleam source into the bridge's M1 JSON.

  ## Examples

      iex> {:ok, ast} = Metastatic.Adapters.Gleam.Subprocess.parse("pub fn main() { 1 }")
      iex> ast["kind"]
      "Module"
  """
  @spec parse(String.t()) :: {:ok, map()} | {:error, String.t()}
  def parse(source) when is_binary(source), do: run("parse", source, ".gleam")

  @doc """
  Renders M1 JSON back to formatted Gleam source.

  ## Examples

      iex> {:ok, ast} = Metastatic.Adapters.Gleam.Subprocess.parse("pub fn main() { 1 }")
      iex> {:ok, source} = Metastatic.Adapters.Gleam.Subprocess.unparse(ast)
      iex> String.contains?(source, "pub fn main()")
      true
  """
  @spec unparse(term()) :: {:ok, String.t()} | {:error, String.t()}
  def unparse(ast) do
    with {:ok, json} <- Bridge.encode(ast), do: run("unparse", json, ".json")
  end

  @doc """
  Normalises Gleam source with `gleam format`'s own printer.

  ## Examples

      iex> {:ok, source} = Metastatic.Adapters.Gleam.Subprocess.format("pub fn  main( ){1}")
      iex> String.contains?(source, "pub fn main()")
      true
  """
  @spec format(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def format(source) when is_binary(source), do: run("format", source, ".gleam")

  @doc """
  Runs the bridge's built-in self-test.

  Verifies, on the exact binary that is about to be used, that spans are
  populated, that the AST survives parse → JSON → reify → print → re-parse, and
  that the printer is reachable. Useful in CI and from diagnostics.

  ## Examples

      iex> {:ok, report} = Metastatic.Adapters.Gleam.Subprocess.selftest()
      iex> report["status"]
      "ok"
  """
  @spec selftest() :: {:ok, map()} | {:error, String.t()}
  def selftest do
    # `selftest` ignores its input, but a path is still passed so the bridge
    # never has to treat "no argument" as a special case.
    run("selftest", "", ".txt")
  end

  @doc """
  Returns `true` when a prebuilt bridge or a usable Rust toolchain is present.

  Does not build anything, and does not guarantee that the installed toolchain
  works — use `selftest/0` for that.

  ## Examples

      iex> is_boolean(Metastatic.Adapters.Gleam.Subprocess.available?())
      true
  """
  @spec available?() :: boolean()
  def available?, do: prebuilt() != nil or (cargo() != nil and sources_present?())

  @doc """
  Returns which bridge build this package ships.

  `:vendored` is the full build (the default); `:external_gleam` is the
  `HEX_BUILD=1` build, which has no vendored compiler crates and therefore no
  `parse`. Decided at compile time by the presence of
  `priv/parsers/gleam/vendor/Cargo.toml` in the package, so a caller can branch
  before attempting a parse rather than after it fails.

  ## Examples

      iex> Metastatic.Adapters.Gleam.Subprocess.build() in [:vendored, :external_gleam]
      true
  """
  @spec build() :: :vendored | :external_gleam
  def build do
    if vendored?(), do: :vendored, else: :external_gleam
  end

  @doc """
  Returns `true` when this package ships the vendored compiler crates.

  ## Examples

      iex> is_boolean(Metastatic.Adapters.Gleam.Subprocess.vendored?())
      true
  """
  @spec vendored?() :: boolean()
  def vendored? do
    File.regular?(Path.join(source_dir(), "vendor/Cargo.toml"))
  end

  @doc """
  Returns the path of the bridge executable that will be used, or `nil`.

  Nothing is built here: when only `cargo` is available, the `cargo` path is
  returned. Use `available?/0` when the question is "can I parse?" rather than
  "which executable?".

  ## Examples

      iex> path = Metastatic.Adapters.Gleam.Subprocess.executable()
      iex> is_binary(path) or is_nil(path)
      true
  """
  @spec executable() :: String.t() | nil
  def executable do
    case prebuilt() do
      nil -> cargo()
      path -> path
    end
  end

  # ----- Private -----

  defp run(mode, input, extension) do
    with {:ok, executable} <- resolve(),
         {:ok, output} <-
           Subprocess.run(executable, [mode], input,
             ext: extension,
             prefix: "metastatic_gleam"
           ) do
      Bridge.decode(output)
    end
  rescue
    error -> {:error, "Gleam parser unavailable: #{Exception.message(error)}"}
  end

  # A prebuilt binary wins; otherwise the sources are built into the cache.
  defp resolve do
    case prebuilt() do
      nil -> build_bridge()
      path -> {:ok, path}
    end
  end

  defp prebuilt do
    bundled = Priv.parser_path("#{@source_dir}/bin/#{@binary}")
    release = Priv.parser_path("#{@source_dir}/target/release/#{@binary}")

    cond do
      executable_file?(bundled) -> bundled
      executable_file?(release) -> release
      path = Priv.find_executable(@binary) -> path
      true -> nil
    end
  end

  defp cargo, do: Priv.find_executable("cargo")
  defp source_dir, do: Priv.parser_path(@source_dir)

  # The manifest plus the bridge's own modules. `vendor/` is *not* required:
  # the `external-gleam` build ships without it by design, and requiring it
  # here would make that build report "sources are missing" instead of working.
  # `build/0` is what distinguishes the two.
  defp sources_present? do
    dir = source_dir()

    File.regular?(Path.join(dir, "Cargo.toml")) and
      File.regular?(Path.join(dir, "src/main.rs"))
  end

  defp build_bridge do
    cond do
      cargo() == nil ->
        {:error,
         "Gleam parser unavailable: install Rust/Cargo to build the bundled parser, " <>
           "or put #{@binary} on PATH, or build it before deploying to a read-only release"}

      not sources_present?() ->
        {:error,
         "Gleam parser sources are missing from #{source_dir()}; " <>
           "reinstall Metastatic with priv/parsers/gleam included"}

      true ->
        build_cached(cargo(), source_dir())
    end
  end

  defp build_cached(cargo, directory) do
    # The feature set is part of the key: the two builds produce different
    # binaries from the same sources, so sharing a cache entry would make
    # whichever ran first win.
    digest =
      :crypto.hash(
        :sha256,
        [
          cargo,
          :erlang.system_info(:system_architecture),
          inspect(build()),
          source_digest(directory)
        ]
      )
      |> Base.encode16(case: :lower)

    cache = :filename.basedir(:user_cache, "metastatic") |> to_string()
    destination = Path.join([cache, "gleam", digest, @binary])

    # The resource identifies the build; the requester must identify this
    # process so different callers cannot enter the first-build section
    # together.
    :global.trans({{__MODULE__, destination}, self()}, fn ->
      if executable_file?(destination) do
        {:ok, destination}
      else
        compile_bridge(cargo, directory, destination)
      end
    end)
  end

  # A digest over the bridge's own sources and the vendored manifest.
  #
  # Hashing all of `vendor/` would mean reading ~5 MB on every call; the
  # vendored crates only change when `vendor.sh` runs, and that also rewrites
  # `vendor/Cargo.toml`, so the manifest is a faithful proxy for "the vendored
  # tree changed".
  defp source_digest(directory) do
    files =
      ["Cargo.toml", "vendor/Cargo.toml", "Cargo.lock"] ++
        Path.wildcard(Path.join(directory, "src/*.rs"))

    files
    |> Enum.map(fn relative ->
      path = Path.join(directory, relative)

      case File.read(path) do
        {:ok, contents} -> [relative, 0, contents, 0]
        {:error, _} -> [relative, 0]
      end
    end)
    |> Enum.sort()
  end

  defp compile_bridge(cargo, directory, destination) do
    # Cargo always writes to `<target-dir>/release/<bin>`, so the build runs in
    # a scratch target directory next to the destination and the artefact is
    # copied out. Copying rather than moving keeps the scratch directory
    # disposable on every path, and a half-written binary never appears at
    # `destination` — the cache hit path only ever sees a complete file.
    scratch =
      destination <> ".build-" <> Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)

    try do
      case File.mkdir_p(scratch) do
        :ok ->
          do_compile_bridge(cargo, directory, scratch, destination)

        {:error, reason} ->
          {:error, "Cannot create Gleam parser cache: #{inspect(reason)}"}
      end
    after
      File.rm_rf(scratch)
    end
  end

  defp do_compile_bridge(cargo, directory, scratch, destination) do
    args = ["build", "--release", "--locked", "--bin", @binary] ++ @feature_args[build()]

    case System.cmd(cargo, args,
           cd: directory,
           env: Priv.subprocess_env([{"CARGO_TARGET_DIR", scratch}]),
           stderr_to_stdout: true
         ) do
      {_, 0} ->
        install(Path.join([scratch, "release", @binary]), destination)

      {output, code} ->
        {:error, "Gleam parser build failed (exit #{code}): #{String.trim(output)}"}
    end
  end

  defp install(built, destination) do
    case File.cp(built, destination) do
      :ok ->
        case File.chmod(destination, 0o755) do
          :ok -> {:ok, destination}
          {:error, reason} -> {:error, "Cannot make Gleam parser executable: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, "Cannot install Gleam parser cache: #{inspect(reason)}"}
    end
  end

  defp executable_file?(path) do
    case File.stat(path) do
      {:ok, %{type: :regular, mode: mode}} -> Bitwise.band(mode, 0o111) != 0
      _ -> false
    end
  end
end
