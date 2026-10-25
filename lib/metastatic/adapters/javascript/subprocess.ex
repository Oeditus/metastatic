defmodule Metastatic.Adapters.JavaScript.Subprocess do
  @moduledoc """
  Subprocess management for JavaScript/TypeScript parser and unparser.

  Handles communication with Node.js scripts via temporary files/stdin with JSON serialization.
  Automatically ensures npm packages in `priv/parsers/javascript` are installed on demand when needed.
  """

  alias Metastatic.Priv

  @parser_path "parsers/javascript/parser.js"
  @unparser_path "parsers/javascript/unparser.js"

  @doc """
  Parse JS/TS source code to Babel AST JSON.

  ## Examples

      iex> Metastatic.Adapters.JavaScript.Subprocess.parse("const x = 5;")
      {:ok, %{"type" => "File", ...}}

      iex> Metastatic.Adapters.JavaScript.Subprocess.parse("const x =")
      {:error, "SyntaxError: ..."}
  """
  @spec parse(String.t()) :: {:ok, map()} | {:error, String.t()}
  def parse(source) when is_binary(source) do
    script_full_path = Priv.parser_path(@parser_path)

    if File.exists?(script_full_path) and Priv.find_executable("node") != nil do
      case run_node_script(@parser_path, source) do
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
          {:error, "Node process failed: #{inspect(reason)}"}
      end
    else
      {:error, "JavaScript parser unavailable"}
    end
  end

  @doc """
  Unparse Babel AST JSON back to JS/TS source code.

  ## Examples

      iex> ast = %{"type" => "File", ...}
      iex> Metastatic.Adapters.JavaScript.Subprocess.unparse(ast)
      {:ok, "const x = 5;"}
  """
  @spec unparse(map()) :: {:ok, String.t()} | {:error, String.t()}
  def unparse(ast) when is_map(ast) do
    case Jason.encode(ast) do
      {:ok, json} ->
        case run_node_script(@unparser_path, json) do
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
            {:error, "Node process failed: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, "JSON encode failed: #{inspect(reason)}"}
    end
  end

  # Private Functions

  defp run_node_script(script_path, input) do
    script_full_path = Priv.parser_path(script_path)
    parser_dir = Path.dirname(script_full_path)

    case ensure_node_modules(parser_dir) do
      :ok ->
        do_run_node_script(script_full_path, parser_dir, input)

      {:error, _} = err ->
        err
    end
  rescue
    e ->
      {:error, "Exception: #{Exception.message(e)}"}
  end

  defp do_run_node_script(script_full_path, parser_dir, input) do
    node_bin = Priv.find_executable("node") || "node"

    if File.exists?(script_full_path) do
      temp_path =
        Path.join(
          System.tmp_dir!(),
          "metastatic_js_#{System.unique_integer([:positive, :monotonic])}.txt"
        )

      File.write!(temp_path, input)

      try do
        case System.cmd(node_bin, [script_full_path, temp_path],
               cd: parser_dir,
               env: Priv.subprocess_env(),
               stderr_to_stdout: true
             ) do
          {output, 0} ->
            {:ok, output}

          {error_output, exit_code} ->
            {:error, "Exit code #{exit_code}: #{error_output}"}
        end
      after
        File.rm(temp_path)
      end
    else
      {:error, "JavaScript script not found: #{script_full_path}"}
    end
  end

  defp ensure_node_modules(parser_dir) do
    if node_modules_present?(parser_dir) do
      :ok
    else
      :global.trans({__MODULE__, :ensure_node_modules}, fn ->
        if node_modules_present?(parser_dir) do
          :ok
        else
          do_ensure_node_modules(parser_dir)
        end
      end)
    end
  end

  defp node_modules_present?(parser_dir) do
    local_babel = Path.join([parser_dir, "node_modules", "@babel", "parser"])
    home = System.user_home() || ""

    global_babel =
      Path.join([
        home,
        ".local",
        "share",
        "mise",
        "installs",
        "node",
        "latest",
        "lib",
        "node_modules",
        "@babel",
        "parser"
      ])

    File.exists?(local_babel) or File.exists?(global_babel)
  end

  defp do_ensure_node_modules(parser_dir) do
    npm_bin = Priv.find_executable("npm")

    cond do
      npm_bin != nil and File.dir?(parser_dir) ->
        lockfile = Path.join(parser_dir, "package-lock.json")

        cmd_args =
          if File.exists?(lockfile) do
            ["ci", "--no-audit", "--no-fund"]
          else
            ["install", "--no-audit", "--no-fund"]
          end

        case System.cmd(npm_bin, cmd_args,
               cd: parser_dir,
               env: Priv.subprocess_env(),
               stderr_to_stdout: true
             ) do
          {_, 0} ->
            :ok

          {error_output, exit_code} ->
            {:error, "npm install failed with exit code #{exit_code}: #{error_output}"}
        end

      true ->
        {:error, "npm executable not found and node_modules is missing"}
    end
  end

  defp format_error(%{"type" => type, "msg" => msg, "lineno" => line}) when not is_nil(line) do
    "#{type} at line #{line}: #{msg}"
  end

  defp format_error(%{"type" => type, "msg" => msg}) do
    "#{type}: #{msg}"
  end

  defp format_error(error) when is_binary(error) do
    error
  end

  defp format_error(error) do
    inspect(error)
  end
end
