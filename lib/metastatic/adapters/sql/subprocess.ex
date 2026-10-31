defmodule Metastatic.Adapters.SQL.Subprocess do
  @moduledoc """
  Subprocess management for the native `sqlparser-rs` parser and unparser.

  Handles communication with the compiled Rust CLI (`sql_parser`) via stdin/stdout
  with JSON serialization.
  """

  alias Metastatic.Priv

  @parser_bin "parsers/sql/bin/sql_parser"
  @release_bin "parsers/sql/target/release/metastatic-sql-parser"
  @cargo_rel_dir "parsers/sql"

  @doc """
  Parse SQL source code to AST JSON map using `sqlparser-rs`.

  Options:
  - `:dialect` - SQL dialect atom or string (e.g., `:generic`, `:postgres`, `:mysql`, `:sqlite`, `:ansi`)
  """
  @spec parse(String.t(), keyword()) :: {:ok, term()} | {:error, String.t()}
  def parse(source, opts \\ []) when is_binary(source) do
    dialect = opts |> Keyword.get(:dialect, :generic) |> to_string()
    args = ["parse", "--dialect", dialect]

    case run_sql_parser(args, source) do
      {:ok, result} ->
        case Jason.decode(result) do
          {:ok, %{"ok" => true, "ast" => ast}} ->
            {:ok, ast}

          {:ok, %{"ok" => false, "error" => error}} ->
            {:error, format_error(error)}

          {:error, reason} ->
            {:error, "JSON decode failed: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, "SQL parser process failed: #{inspect(reason)}"}
    end
  end

  @doc """
  Unparse AST JSON map or list back to SQL source code using `sqlparser-rs`.
  """
  @spec unparse(term()) :: {:ok, String.t()} | {:error, String.t()}
  def unparse(ast) do
    case Jason.encode(ast) do
      {:ok, json} ->
        args = ["unparse"]

        case run_sql_parser(args, json) do
          {:ok, result} ->
            case Jason.decode(result) do
              {:ok, %{"ok" => true, "source" => source}} ->
                {:ok, source}

              {:ok, %{"ok" => false, "error" => error}} ->
                {:error, format_error(error)}

              {:error, reason} ->
                {:error, "JSON decode failed: #{inspect(reason)}"}
            end

          {:error, reason} ->
            {:error, "SQL unparser process failed: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, "JSON encode failed: #{inspect(reason)}"}
    end
  end

  # ----- Private Helpers -----

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

        if File.dir?(cargo_dir) do
          cargo_args =
            ["run", "--quiet", "--manifest-path", Path.join(cargo_dir, "Cargo.toml"), "--"] ++
              args

          execute_cmd(cargo_bin, cargo_args, input)
        else
          {:error, "SQL parser binary and cargo project unavailable"}
        end

      true ->
        {:error, "SQL parser binary unavailable"}
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
