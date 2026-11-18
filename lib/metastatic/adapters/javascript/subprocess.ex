defmodule Metastatic.Adapters.JavaScript.Subprocess do
  @moduledoc """
  Subprocess management for JavaScript/TypeScript parser and unparser.

  Handles communication with Node.js scripts via temporary files with JSON
  serialization, and installs `priv/parsers/javascript/node_modules` on demand
  when the Babel packages are missing.

  Temp-file handling, exit-code reporting and error formatting are delegated
  to `Metastatic.Subprocess`.
  """

  alias Metastatic.{Priv, Subprocess}

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
    with :ok <- available?(),
         {:ok, result} <- run_node_script(@parser_path, source, ".js"),
         {:ok, decoded} <- decode(result) do
      case decoded do
        %{"ok" => true, "ast" => ast} -> {:ok, ast}
        %{"ok" => false, "error" => error} -> {:error, Subprocess.format_error(error)}
        _ -> {:error, "Unexpected JavaScript parser output"}
      end
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
    with {:ok, json} <- encode(ast),
         :ok <- available?(),
         {:ok, result} <- run_node_script(@unparser_path, json, ".json"),
         {:ok, decoded} <- decode(result) do
      case decoded do
        %{"ok" => true, "source" => source} -> {:ok, source}
        %{"ok" => false, "error" => error} -> {:error, Subprocess.format_error(error)}
        _ -> {:error, "Unexpected JavaScript unparser output"}
      end
    end
  end

  # Private Functions

  defp available? do
    cond do
      not File.exists?(Priv.parser_path(@parser_path)) ->
        {:error, "JavaScript parser unavailable: #{@parser_path} is missing from the package"}

      Priv.find_executable("node") == nil ->
        {:error, "JavaScript parser unavailable: no `node` executable found"}

      true ->
        :ok
    end
  end

  defp run_node_script(script_path, input, ext) do
    script_full_path = Priv.parser_path(script_path)
    parser_dir = Path.dirname(script_full_path)

    with :ok <- ensure_node_modules(parser_dir) do
      Subprocess.run(Priv.find_executable("node"), [script_full_path], input,
        ext: ext,
        prefix: "metastatic_js",
        cd: parser_dir
      )
    end
  end

  defp encode(ast) do
    {:ok, Jason.encode!(ast)}
  rescue
    error -> {:error, "JSON encode failed: #{Exception.message(error)}"}
  end

  defp decode(result) do
    case Jason.decode(result) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, reason} -> {:error, "JSON decode failed: #{inspect(reason)}"}
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

    if npm_bin != nil and File.dir?(parser_dir) do
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
    else
      {:error, "npm executable not found and node_modules is missing"}
    end
  end
end
