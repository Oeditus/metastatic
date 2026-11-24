defmodule Mix.Tasks.Metastatic.Package.Gleam do
  @moduledoc """
  Builds the Metastatic Hex package, optionally in the source-only Gleam
  configuration.

  ## Why a task rather than just `HEX_BUILD=1 mix hex.build`

  `HEX_BUILD=1` alone gets the file list right: it drops
  `priv/parsers/gleam/vendor` (the ~4.9 MB of vendored Gleam compiler crates)
  and the vendored `Cargo.toml`. What it cannot do is *replace* a file, because
  Hex's `:files` option accepts only paths and globs — there is no rename
  syntax.

  That replacement is required: `Cargo.toml` names the vendored crates by
  `path`, and Cargo resolves a `path` dependency's manifest even when the
  feature that enables it is off. A package shipping without `vendor/` but
  with the original manifest therefore fails with

      error: no matching package named `gleam-core` found
      location searched: vendor/compiler-core

  So this task swaps `Cargo.source-only.toml` in for `Cargo.toml` on disk,
  runs `mix hex.build`, and restores the original — including on failure.

  ## Usage

      # The full package (default): vendored crates, full MetaAST support.
      mix metastatic.package.gleam

      # The source-only package: no vendored crates, needs `gleam` on PATH.
      mix metastatic.package.gleam --source-only

      # Build a tarball instead of unpacking into a directory.
      mix metastatic.package.gleam --source-only --tarball

  ## Options

    * `--source-only` — produce the `HEX_BUILD=1` package: the bridge's own
      sources only, no `priv/parsers/gleam/vendor`. That build formats and
      unparses Gleam but cannot produce a MetaAST; see
      `Metastatic.Adapters.Gleam`.
    * `--tarball` — pass `--tarball` to `mix hex.build` instead of
      `--unpack`.
    * `--output PATH` — forwarded as `-o PATH`.
    * `--dry-run` — report what would be packaged without writing anything.

  ## Exit codes

    * 0 — the package was built
    * 1 — the build failed
    * 2 — usage error
  """

  @shortdoc "Builds the Hex package, optionally source-only for Gleam"

  use Mix.Task

  @gleam_dir "priv/parsers/gleam"
  @manifest Path.join(@gleam_dir, "Cargo.toml")
  @source_only_manifest Path.join(@gleam_dir, "Cargo.source-only.toml")
  @vendor_dir Path.join(@gleam_dir, "vendor")

  @impl Mix.Task
  def run(args) do
    if Metastatic.CLI.help_requested?(args),
      do: Metastatic.CLI.help(Mix.Tasks.Metastatic.Package.Gleam)

    {opts, _rest, invalid} =
      OptionParser.parse(args,
        strict: [source_only: :boolean, tarball: :boolean, output: :string, dry_run: :boolean],
        aliases: [o: :output]
      )

    if invalid != [] do
      usage_error("Unknown option(s): #{Enum.map_join(invalid, ", ", &elem(&1, 0))}")
    end

    source_only? = Keyword.get(opts, :source_only, false)

    if source_only? and not File.regular?(@source_only_manifest) do
      usage_error("""
      #{@source_only_manifest} is missing.

      The source-only build needs a manifest that does not reference the
      vendored crates; without it the unpacked package cannot be built.
      """)
    end

    if source_only? do
      report_source_only(source_only?, opts)
    else
      report_source_only(source_only?, opts)
    end

    if Keyword.get(opts, :dry_run, false) do
      Mix.shell().info("Dry run: nothing written.")
    else
      build(source_only?, opts)
    end
  end

  # ----- Building -----

  defp build(source_only?, opts) do
    if source_only? do
      with_swapped_manifest(fn -> hex_build(opts, source_only?) end)
    else
      hex_build(opts, source_only?)
    end
  end

  # Swaps the manifest, runs `fun`, and restores the original on every path.
  #
  # The restore is in an `after` block rather than a `with`/`rescue` pair so a
  # raise, a `System.halt`-free exit or a normal return all leave the working
  # tree exactly as it was found. A packaging task that can corrupt the
  # checkout on failure is worse than one that refuses to run.
  defp with_swapped_manifest(fun) do
    original = File.read!(@manifest)
    replacement = File.read!(@source_only_manifest)

    try do
      File.write!(@manifest, replacement)
      fun.()
    after
      File.write!(@manifest, original)
    end
  end

  defp hex_build(opts, source_only?) do
    # `HEX_BUILD=1` is what `mix.exs` reads to drop `vendor/` from `:files`.
    # It is set *only* for the source-only build: setting it unconditionally
    # made a plain `mix metastatic.package.gleam` produce a package with no
    # vendored crates, which is the opposite of what "full" means.
    if source_only? do
      System.put_env("HEX_BUILD", "1")
    else
      System.delete_env("HEX_BUILD")
    end

    args =
      if Keyword.get(opts, :tarball, false), do: ["--tarball"], else: ["--unpack"]

    args = args ++ output_args(opts)

    # `hex.build` lives in the Hex *archive*, which Mix loads for the CLI but
    # not necessarily for a task invoked programmatically. `Mix.Task.load_all/0`
    # only scans `Mix.paths()` code paths, so it does not reach an archive that
    # is not on the load path. Falling back to the `mix` executable keeps the
    # task working in both situations instead of failing on an environment
    # detail the caller cannot see.
    if hex_task_loaded?() do
      run_hex_task(args)
    else
      run_hex_cli(args, source_only?)
    end
  end

  defp hex_task_loaded? do
    Mix.Task.load_all()
    Mix.Task.get("hex.build") != nil
  end

  defp run_hex_task(args) do
    case Mix.Task.run("hex.build", args) do
      :ok ->
        :ok

      {:error, reason} ->
        Mix.shell().error("Package build failed: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  # Runs `mix hex.build` as a child process.
  #
  # `HEX_BUILD` is passed explicitly: the child reads `mix.exs` itself, and
  # `System.put_env/2` above only affects this VM.
  defp run_hex_cli(args, source_only?) do
    mix = System.find_executable("mix") || "mix"

    env =
      if source_only?,
        do: [{"HEX_BUILD", "1"}],
        else: [{"HEX_BUILD", nil}]

    case System.cmd(mix, ["hex.build" | args],
           env: env,
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        Mix.shell().info(String.trim_trailing(output))
        :ok

      {output, code} ->
        Mix.shell().error(String.trim_trailing(output))
        Mix.shell().error("Package build failed (exit #{code}).")
        exit({:shutdown, 1})
    end
  end

  defp output_args(opts) do
    case Keyword.get(opts, :output) do
      nil -> []
      path -> ["-o", path]
    end
  end

  # ----- Reporting -----

  defp report_source_only(source_only?, opts) do
    shell = Mix.shell()

    shell.info("Building the #{if source_only?, do: "source-only", else: "full"} package.")

    if source_only? do
      shell.info("""
        Gleam: bridge sources only (#{@vendor_dir} excluded, ~4.9 MB smaller).
        The resulting package needs `gleam` on PATH at runtime and can format
        and unparse Gleam, but cannot produce a MetaAST.
      """)
    else
      shell.info("""
        Gleam: vendored compiler crates included. Full MetaAST support, no
        `gleam` toolchain needed at runtime.
      """)
    end

    if Keyword.get(opts, :dry_run, false) do
      shell.info("Files: #{inspect(gleam_files(source_only?))}")
    end
  end

  defp gleam_files(source_only?) do
    manifest = if source_only?, do: @source_only_manifest, else: @manifest

    [manifest | Path.wildcard(Path.join(@gleam_dir, "src/*.rs"))]
    |> then(fn files ->
      if source_only?, do: files, else: files ++ [@vendor_dir]
    end)
  end

  defp usage_error(message) do
    Mix.shell().error(message)
    Mix.shell().info("Usage: mix metastatic.package.gleam [--source-only] [--tarball]")
    exit({:shutdown, 2})
  end
end
