defmodule Metastatic.Adapters.Rust.Subprocess do
  @moduledoc """
  Subprocess management for the native Rust parser and unparser.

  Handles communication with the compiled Rust CLI
  (`metastatic-rust-parser`) via temporary files with JSON serialization.

  Hex packages include portable Rust sources and `Cargo.lock`, not a
  platform-specific executable. Install Rust/Cargo for the source fallback or
  provide `metastatic-rust-parser` on `PATH`. Prebuild the parser when deploying
  into a read-only release.

  ## Protocol

  The bridge reads its input from a file path given as its last argument and
  writes a single JSON object to stdout:

      {"ok": true, "ast": {...}}     # parse
      {"ok": true, "source": "..."}  # unparse / fmt
      {"ok": false, "error": {"type": "...", "msg": "...", "line": 12}}

  The bridge never reads stdin, so a missing path fails fast instead of
  blocking on a pipe that will never close.

  Temp-file handling is delegated to `Metastatic.Subprocess`.
  """

  alias Metastatic.Adapter.Bridge
  alias Metastatic.{Priv, Subprocess}

  @parser_bin "parsers/rust/bin/metastatic-rust-parser"
  @release_bin "parsers/rust/target/release/metastatic-rust-parser"
  @cargo_rel_dir "parsers/rust"

  @doc """
  Parse Rust source code to an AST JSON map.

  ## Examples

      iex> {:ok, ast} = Metastatic.Adapters.Rust.Subprocess.parse("fn main() {}")
      iex> ast["kind"]
      "File"

      iex> {:error, "SyntaxError" <> _} = Metastatic.Adapters.Rust.Subprocess.parse("fn broken( {")
  """
  @spec parse(String.t()) :: {:ok, map()} | {:error, String.t()}
  def parse(source) when is_binary(source) do
    with {:ok, output} <- run_parser(["parse"], source, ".rs") do
      Bridge.decode(output)
    end
  end

  @doc """
  Unparse an AST JSON map back to Rust source code.

  ## Examples

      iex> {:ok, ast} = Metastatic.Adapters.Rust.Subprocess.parse("fn main() {}")
      iex> {:ok, source} = Metastatic.Adapters.Rust.Subprocess.unparse(ast)
      iex> String.contains?(source, "fn main()")
      true
  """
  @spec unparse(term()) :: {:ok, String.t()} | {:error, String.t()}
  def unparse(ast) do
    with {:ok, json} <- Bridge.encode(ast),
         {:ok, output} <- run_parser(["unparse"], json, ".json") do
      Bridge.decode(output)
    end
  end

  @doc """
  Normalise Rust source formatting without changing its semantics.

  Uses `prettyplease`, so the output is rustfmt-style but not byte-identical to
  what `rustfmt` itself would produce.

  ## Examples

      iex> {:ok, source} = Metastatic.Adapters.Rust.Subprocess.format("fn  main( ){let x=1;}")
      iex> String.contains?(source, "fn main()")
      true
  """
  @spec format(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def format(source) when is_binary(source) do
    format(source, [])
  end

  @doc """
  Formats `source` with an explicit backend.

  ## Options

    * `:backend` — `:prettyplease` (default, rustfmt-style normalisation) or
      `:ra` (byte-exact lossless round-trip via `ra_ap_syntax`). The `:ra`
      backend requires a bridge built with `--features ra`; when it is not
      available the bridge falls back to `:prettyplease` and reports
      `lossless: false` in its metadata rather than failing.

  ## Examples

      iex> {:ok, source} = Metastatic.Adapters.Rust.Subprocess.format("fn  main( ){}", backend: :ra)
      iex> source
      "fn  main( ){}"
  """
  @spec format(String.t(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def format(source, opts) when is_binary(source) and is_list(opts) do
    args =
      case Keyword.get(opts, :backend, :prettyplease) do
        :ra -> ["fmt", "--backend", "ra"]
        _ -> ["fmt"]
      end

    with {:ok, output} <- run_parser(args, source, ".rs") do
      Bridge.decode(output)
    end
  end

  @doc """
  Runs the bridge's built-in self-test.

  Verifies, on the exact binary that is about to be used, that source spans are
  populated and that the AST survives a full parse → JSON → reify → print →
  re-parse cycle. Useful in CI and from diagnostics.

  ## Examples

      iex> {:ok, report} = Metastatic.Adapters.Rust.Subprocess.selftest()
      iex> report["status"]
      "ok"
  """
  @spec selftest() :: {:ok, map()} | {:error, String.t()}
  def selftest do
    # `selftest` ignores its input, but a path is still passed so the bridge
    # never has to treat "no argument" as a special case.
    with {:ok, output} <- run_parser(["selftest"], "", ".txt") do
      Bridge.decode(output)
    end
  end

  @doc """
  Returns the path of the parser executable that will be used, or `nil`.

  Useful for diagnostics and for tests that need to skip when no toolchain is
  installed. Unlike `run_parser/3` this does not build anything: the `cargo`
  fallback is reported as the `cargo` path itself.
  """
  @spec parser_executable() :: String.t() | nil
  def parser_executable do
    bin_path = Priv.parser_path(@parser_bin)
    release_path = Priv.parser_path(@release_bin)

    cond do
      File.exists?(bin_path) -> bin_path
      File.exists?(release_path) -> release_path
      true -> Priv.find_executable("metastatic-rust-parser")
    end
  end

  @doc """
  Returns `true` when Rust parsing is available in this environment.

  Checks for a prebuilt binary, a local release build, or a `cargo` that can
  build the bundled sources. Returns `false` rather than raising.
  """
  @spec available?() :: boolean()
  def available? do
    parser_executable() != nil or cargo_runnable?()
  end

  # ----- Private Helpers -----

  defp run_parser(args, input, ext) do
    bin_path = Priv.parser_path(@parser_bin)
    release_path = Priv.parser_path(@release_bin)
    global_bin = Priv.find_executable("metastatic-rust-parser")
    cargo_bin = Priv.find_executable("cargo")

    cond do
      File.exists?(bin_path) ->
        execute_cmd(bin_path, args, input, ext)

      File.exists?(release_path) ->
        execute_cmd(release_path, args, input, ext)

      global_bin != nil ->
        execute_cmd(global_bin, args, input, ext)

      cargo_bin != nil ->
        cargo_dir = Priv.parser_path(@cargo_rel_dir)
        manifest = Path.join(cargo_dir, "Cargo.toml")

        if File.regular?(manifest) do
          cargo_args = ["run", "--quiet", "--locked", "--manifest-path", manifest, "--"] ++ args
          execute_cmd(cargo_bin, cargo_args, input, ext)
        else
          {:error,
           "Rust parser binary and Cargo.toml are missing from the installed Metastatic package " <>
             "(expected #{manifest}). Upgrade or reinstall a package containing priv/parsers/rust, " <>
             "or install metastatic-rust-parser on PATH."}
        end

      true ->
        {:error,
         "Rust parser executable unavailable. Install metastatic-rust-parser on PATH, or install " <>
           "Rust/Cargo to build the parser sources included in priv/parsers/rust. " <>
           "For a read-only release, build and install the parser before deployment."}
    end
  end

  defp execute_cmd(executable, args, input, ext) do
    case Subprocess.run(executable, args, input, ext: ext, prefix: "metastatic_rust") do
      {:ok, output} -> {:ok, output}
      {:error, reason} -> {:error, "Rust parser process failed: #{reason}"}
    end
  end

  defp cargo_runnable? do
    case Priv.find_executable("cargo") do
      nil ->
        false

      _cargo ->
        manifest = Path.join(Priv.parser_path(@cargo_rel_dir), "Cargo.toml")
        File.regular?(manifest)
    end
  end
end
