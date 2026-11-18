defmodule Metastatic.Adapters.SQL.Subprocess do
  @moduledoc """
  Subprocess management for the native `sqlparser-rs` parser and unparser.

  Handles communication with the compiled Rust CLI (`sql_parser`) via temporary
  files with JSON serialization.

  Hex packages include portable Rust sources and `Cargo.lock`, not a
  platform-specific executable. Install Rust/Cargo for the source fallback or
  provide `metastatic-sql-parser` on `PATH`. Prebuild the parser when deploying
  into a read-only release.

  Temp-file handling is delegated to `Metastatic.Subprocess`.
  """

  alias Metastatic.{Priv, Subprocess}

  @parser_bin "parsers/sql/bin/sql_parser"
  @release_bin "parsers/sql/target/release/metastatic-sql-parser"
  @cargo_rel_dir "parsers/sql"

  @doc """
  Parse SQL source code to AST JSON map using `sqlparser-rs`.

  Options:
  - `:dialect` - SQL dialect atom or string (e.g., `:generic`, `:postgres`, `:mysql`, `:sqlite`, `:ansi`)

  ## Scripts with unsupported statements

  When a script mixes statements the underlying parser understands with dialect
  constructs it does not model (for example PostgreSQL `ALTER DEFAULT
  PRIVILEGES` or `DO $$ ... $$` blocks), the supported statements are still
  returned. The skipped ones are reported in the `:unsupported` metadata field
  so callers can surface them instead of silently losing information.

  ## Examples

      iex> {:ok, [statement]} = Metastatic.Adapters.SQL.Subprocess.parse("SELECT 1")
      iex> is_map(statement)
      true

      iex> script = "GRANT SELECT ON t TO r; ALTER DEFAULT PRIVILEGES GRANT SELECT ON TABLES TO r;"
      iex> {:ok, [_ | _] = statements, %{unsupported: [_ | _]}} =
      ...>   Metastatic.Adapters.SQL.Subprocess.parse(script, dialect: :postgres)
      iex> length(statements)
      1
  """
  @spec parse(String.t(), keyword()) ::
          {:ok, term()} | {:ok, term(), map()} | {:error, String.t()}
  def parse(source, opts \\ []) when is_binary(source) do
    dialect = opts |> Keyword.get(:dialect, :generic) |> to_string()
    args = ["parse", "--dialect", dialect]

    with {:ok, output} <- run_sql_parser(args, source) do
      decode_parse_result(output)
    end
  end

  defp decode_parse_result(result) do
    case JSON.decode(result) do
      {:ok, %{"ok" => true, "ast" => ast} = decoded} ->
        case Map.get(decoded, "unsupported") do
          unsupported when is_list(unsupported) and unsupported != [] ->
            {:ok, ast, %{unsupported: unsupported}}

          _ ->
            {:ok, ast}
        end

      {:ok, %{"ok" => false, "error" => error}} ->
        {:error, format_error(error)}

      {:error, reason} ->
        {:error, "JSON decode failed: #{inspect(reason)}"}
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
    with {:ok, json} <- encode_ast(ast),
         {:ok, output} <- run_sql_parser(["unparse"], json) do
      case JSON.decode(output) do
        {:ok, %{"ok" => true, "source" => source}} -> {:ok, source}
        {:ok, %{"ok" => false, "error" => error}} -> {:error, format_error(error)}
        {:error, reason} -> {:error, "JSON decode failed: #{inspect(reason)}"}
      end
    end
  end

  # ----- Private Helpers -----

  defp encode_ast(ast) do
    {:ok, JSON.encode!(ast)}
  rescue
    error -> {:error, "JSON encode failed: #{Exception.message(error)}"}
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
          cargo_args = ["run", "--quiet", "--locked", "--manifest-path", manifest, "--"] ++ args
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
    case Subprocess.run(executable, args, input, ext: ".sql", prefix: "metastatic_sql") do
      {:ok, output} -> {:ok, output}
      {:error, reason} -> {:error, "SQL parser process failed: #{reason}"}
    end
  end

  defp format_error(%{"type" => type, "msg" => msg}), do: "#{type}: #{msg}"
  defp format_error(error) when is_binary(error), do: error
  defp format_error(error), do: inspect(error)
end
