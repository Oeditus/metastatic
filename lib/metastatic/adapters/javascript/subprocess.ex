defmodule Metastatic.Adapters.JavaScript.Subprocess do
  @moduledoc """
  Subprocess management for JavaScript/TypeScript parser and unparser.

  Handles communication with Node.js scripts via temporary files with JSON
  serialization, and installs `priv/parsers/javascript/node_modules` on demand
  when the Babel packages are missing.

  Temp-file handling, exit-code reporting and error formatting are delegated
  to `Metastatic.Subprocess`.
  """

  alias Metastatic.Adapter.Bridge
  alias Metastatic.{Priv, Subprocess}

  @parser_path "parsers/javascript/parser.js"
  @unparser_path "parsers/javascript/unparser.js"

  @doc """
  Parse JavaScript or TypeScript source to Babel AST JSON.

  `dialect` selects the Babel plugin set and therefore the grammar:

    * `:javascript` (default) — JSX plus the standard ECMAScript proposals,
      with no type syntax. `let x: number = 1` is a syntax error.
    * `:typescript` — the `typescript` plugin, which accepts type syntax and
      reserves identifiers JavaScript allows.

  Both dialects accept a bare expression (`1 + 2`), which is wrapped in a
  synthetic `Program` so the shape stays uniform across adapters.

  ## Examples

      iex> Metastatic.Adapters.JavaScript.Subprocess.parse("const x = 5;")
      {:ok, %{"type" => "File", ...}}

      iex> Metastatic.Adapters.JavaScript.Subprocess.parse("const x =")
      {:error, "SyntaxError: ..."}

      iex> {:error, _} = Metastatic.Adapters.JavaScript.Subprocess.parse("let x: number = 1;")
      iex> {:ok, _} = Metastatic.Adapters.JavaScript.Subprocess.parse("let x: number = 1;", :typescript)
  """
  @spec parse(String.t(), :javascript | :typescript) :: {:ok, map()} | {:error, String.t()}
  def parse(source, dialect \\ :javascript) when is_binary(source) do
    with :ok <- check_available(),
         {:ok, result} <- run_node_script(@parser_path, source, ".js", dialect_args(dialect)) do
      Bridge.decode(result)
    end
  end

  # Babel rejects `typescript` + `flow` together, and the TypeScript plugin
  # reserves identifiers (`yield`, `await`, `<T>`) that plain JavaScript
  # accepts. The dialect therefore has to be chosen per adapter rather than
  # baked into the bridge.

  @doc """
  Unparse Babel AST JSON back to JS/TS source code.

  ## Examples

      iex> ast = %{"type" => "File", ...}
      iex> Metastatic.Adapters.JavaScript.Subprocess.unparse(ast)
      {:ok, "const x = 5;"}
  """
  @spec unparse(map()) :: {:ok, String.t()} | {:error, String.t()}
  def unparse(ast) when is_map(ast) do
    with {:ok, json} <- Bridge.encode(ast),
         :ok <- check_available(),
         {:ok, result} <- run_node_script(@unparser_path, json, ".json", []) do
      Bridge.decode(result)
    end
  end

  @doc """
  Returns `true` when the Node.js runtime and JavaScript parser script are available.
  """
  @spec available?() :: boolean()
  def available?, do: check_available() == :ok

  # Private Functions

  defp check_available do
    cond do
      not File.exists?(Priv.parser_path(@parser_path)) ->
        {:error, "JavaScript parser unavailable: #{@parser_path} is missing from the package"}

      Priv.find_executable("node") == nil ->
        {:error, "JavaScript parser unavailable: no `node` executable found"}

      true ->
        :ok
    end
  end

  defp dialect_args(:typescript), do: ["--dialect=typescript"]
  defp dialect_args(_), do: ["--dialect=javascript"]

  defp run_node_script(script_path, input, ext, args) do
    script_full_path = Priv.parser_path(script_path)
    parser_dir = Path.dirname(script_full_path)

    with :ok <- ensure_node_modules(parser_dir) do
      Subprocess.run(Priv.find_executable("node"), [script_full_path | args], input,
        ext: ext,
        prefix: "metastatic_js",
        cd: parser_dir
      )
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
