defmodule Metastatic.Adapters.SQL.Subprocess do
  @moduledoc """
  Subprocess management for the native `sqlparser-rs` parser and unparser.

  Handles communication with the compiled Rust CLI (`sql_parser`) via stdin/stdout
  with JSON serialization.

  Hex packages include portable Rust sources and `Cargo.lock`, not a
  platform-specific executable. Install Rust/Cargo for the source fallback or
  provide `metastatic-sql-parser` on `PATH`. Prebuild the parser when deploying
  into a read-only release.
  """

  alias Metastatic.Priv

  @parser_bin "parsers/sql/bin/sql_parser"
  @release_bin "parsers/sql/target/release/metastatic-sql-parser"
  @cargo_rel_dir "parsers/sql"

  @doc """
  Parse SQL source code to AST JSON map using `sqlparser-rs`.

  Options:
  - `:dialect` - SQL dialect atom or string (e.g., `:generic`, `:postgres`, `:mysql`, `:sqlite`, `:ansi`)

  ## Examples

      iex> {:ok, [statement]} = Metastatic.Adapters.SQL.Subprocess.parse("SELECT 1")
      iex> is_map(statement)
      true
  """
  @spec parse(String.t(), keyword()) :: {:ok, term()} | {:error, String.t()}
  def parse(source, opts \\ []) when is_binary(source) do
    dialect = opts |> Keyword.get(:dialect, :generic) |> to_string()
    args = ["parse", "--dialect", dialect]

    case run_sql_parser(args, source) do
      {:ok, result} ->
        case JSON.decode(result) do
          {:ok, %{"ok" => true, "ast" => ast}} ->
            {:ok, ast}

          {:ok, %{"ok" => false, "error" => error}} ->
            {:error, format_error(error)}

          {:error, reason} ->
            {:error, "JSON decode failed: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, "SQL parser process failed: #{reason}"}
    end
  end

  @doc """
  Unparse AST JSON map or list back to SQL source code using `sqlparser-rs`.

  ## Examples

      iex> {:ok, ast} = Metastatic.Adapters.SQL.Subprocess.parse("SELECT 1")
      iex> Metastatic.Adapters.SQL.Subprocess.unparse(ast)
      {:ok, "SELECT 1"}
  """
  @spec unparse(term()) :: {:ok, String.t()} | {:error, String.t()}
  def unparse(ast) do
    case encode_ast(ast) do
      {:ok, json} ->
        args = ["unparse"]

        case run_sql_parser(args, json) do
          {:ok, result} ->
            case JSON.decode(result) do
              {:ok, %{"ok" => true, "source" => source}} ->
                {:ok, source}

              {:ok, %{"ok" => false, "error" => error}} ->
                {:error, format_error(error)}

              {:error, reason} ->
                {:error, "JSON decode failed: #{inspect(reason)}"}
            end

          {:error, reason} ->
            {:error, "SQL unparser process failed: #{reason}"}
        end

      {:error, reason} ->
        {:error, "JSON encode failed: #{inspect(reason)}"}
    end
  end

  # ----- Private Helpers -----

  defp encode_ast(ast) do
    {:ok, JSON.encode!(ast)}
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp run_sql_parser(args, input) do
    bin_path = Priv.parser_path(@parser_bin)
    release_path = Priv.parser_path(@release_bin)
    global_bin = Priv.find_executable("metastatic-sql-parser")
    cargo_bin = Priv.find_executable("cargo")

    cond do
      File.exists?(bin_path) ->
        execute_cmd(bin_path, args, input)

      File.exists?(release_path) ->
        execute_cmd(release_path, args, input)

      global_bin != nil ->
        execute_cmd(global_bin, args, input)

      cargo_bin != nil ->
        cargo_dir = Priv.parser_path(@cargo_rel_dir)

        manifest = Path.join(cargo_dir, "Cargo.toml")

        if File.regular?(manifest) do
          cargo_args =
            ["run", "--quiet", "--locked", "--manifest-path", manifest, "--"] ++
              args

          execute_cmd(cargo_bin, cargo_args, input)
        else
          {:error,
           "SQL parser binary and Cargo.toml are missing from the installed Metastatic package " <>
             "(expected #{manifest}). Upgrade or reinstall a package containing priv/parsers/sql, " <>
             "or install metastatic-sql-parser on PATH."}
        end

      true ->
        {:error,
         "SQL parser executable unavailable. Install metastatic-sql-parser on PATH, or install " <>
           "Rust/Cargo to build the parser sources included in priv/parsers/sql. " <>
           "For a read-only release, build and install the parser before deployment."}
    end
  end

  defp execute_cmd(executable, args, input) do
    temp_path =
      Path.join(
        System.tmp_dir!(),
        "metastatic_sql_#{System.unique_integer([:positive, :monotonic])}.tmp"
      )

    File.write!(temp_path, input)

    try do
      cmd_args = args ++ [temp_path]
      opts = [stderr_to_stdout: true, env: Priv.subprocess_env()]

      case System.cmd(executable, cmd_args, opts) do
        {output, 0} ->
          {:ok, output}

        {error_output, exit_code} ->
          {:error, "Exit code #{exit_code}: #{error_output}"}
      end
    after
      File.rm(temp_path)
    end
  rescue
    e ->
      {:error, "Exception running SQL parser: #{Exception.message(e)}"}
  end

  defp format_error(%{"type" => type, "msg" => msg}) do
    "#{type}: #{msg}"
  end

  defp format_error(error) when is_binary(error), do: error
  defp format_error(error), do: inspect(error)
end
