defmodule Metastatic.Adapters.Java.Subprocess do
  @moduledoc """
  Subprocess management for the Java parser and unparser.

  Java is parsed through the JDK's own tree API (`com.sun.source.tree`), which
  ships with every JDK -- so the bridge needs no third-party dependency, only a
  `java` executable. The bridge lives in `priv/parsers/java/parser.java` and is
  run through the single-file source launcher (`java parser.java <mode> <file>`),
  the same strategy the SQL adapter uses for its Rust bridge.

  ## Protocol

  The bridge reads its input from a file path given as `argv[1]` and writes a
  single JSON object to stdout:

      {"ok": true, "ast": {...}}     # parse
      {"ok": true, "source": "..."}  # unparse
      {"ok": false, "error": {"type": "...", "msg": "...", "line": 12}}

  ## Toolchain resolution

  1. `JAVA_HOME/bin/java` (when `JAVA_HOME` is set)
  2. A working `java` on `PATH` (including configured `mise` shims)
  3. Installed `mise` JDKs, when the shim has no version configured

  Every failure mode -- missing bridge, missing JDK, non-zero exit -- is
  reported as `{:error, reason}`; nothing raises and nothing hangs.
  """

  alias Metastatic.Priv

  @parser_path "parsers/java/parser.java"

  @doc """
  Parse Java source code to a JSON-serialisable AST map.

  ## Examples

      iex> {:ok, ast} = Metastatic.Adapters.Java.Subprocess.parse("class A {}")
      iex> ast["kind"]
      "COMPILATION_UNIT"

      iex> Metastatic.Adapters.Java.Subprocess.parse("class {")
      {:error, "SyntaxError at line 1: ..."}
  """
  @spec parse(String.t()) :: {:ok, map()} | {:error, String.t()}
  def parse(source) when is_binary(source) do
    with :ok <- bridge_available?(),
         {:ok, output} <- run_bridge("parse", source),
         {:ok, decoded} <- decode(output) do
      case decoded do
        %{"ok" => true, "ast" => ast} -> {:ok, ast}
        %{"ok" => false, "error" => error} -> {:error, format_error(error)}
        _ -> {:error, "Unexpected Java parser output"}
      end
    end
  end

  @doc """
  Unparse a Java AST map back to source code.

  ## Examples

      iex> {:ok, ast} = Metastatic.Adapters.Java.Subprocess.parse("class A {}")
      iex> {:ok, source} = Metastatic.Adapters.Java.Subprocess.unparse(ast)
      iex> String.contains?(source, "class A")
      true
  """
  @spec unparse(map()) :: {:ok, String.t()} | {:error, String.t()}
  def unparse(ast) when is_map(ast) do
    with :ok <- bridge_available?(),
         {:ok, json} <- encode(ast),
         {:ok, output} <- run_bridge("unparse", json),
         {:ok, decoded} <- decode(output) do
      case decoded do
        %{"ok" => true, "source" => source} -> {:ok, source}
        %{"ok" => false, "error" => error} -> {:error, format_error(error)}
        _ -> {:error, "Unexpected Java unparser output"}
      end
    end
  end

  @doc """
  Returns the path of the `java` executable the bridge will use, or `nil`.

  Useful for diagnostics (`mix ragex.doctor`, the `scip_status` tool) and for
  tests that need to skip when no JDK is installed.
  """
  @spec java_executable() :: String.t() | nil
  def java_executable do
    java_home = System.get_env("JAVA_HOME")
    home = System.get_env("HOME") || System.user_home() || ""

    candidates =
      [
        java_home && Path.join([java_home, "bin", "java"]),
        System.find_executable("java")
      ] ++ Path.wildcard(Path.join([home, ".local/share/mise/installs/java", "*", "bin/java"]))

    candidates
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.find(&working_java?/1)
  end

  defp working_java?(path) do
    File.regular?(path) and
      match?({_output, 0}, System.cmd(path, ["-version"], stderr_to_stdout: true))
  rescue
    _error -> false
  end

  @doc """
  Returns the resolved path of the bridge source file, or `nil` when the
  Metastatic package does not ship it.
  """
  @spec bridge_path() :: String.t() | nil
  def bridge_path do
    path = Priv.parser_path(@parser_path)
    if File.regular?(path), do: path, else: nil
  end

  # Private

  defp bridge_available? do
    cond do
      bridge_path() == nil ->
        {:error, "Java parser bridge (#{@parser_path}) is missing from the Metastatic package"}

      java_executable() == nil ->
        {:error, "Java parser unavailable: no `java` executable found (install a JDK 11+)"}

      true ->
        :ok
    end
  end

  defp encode(ast) do
    {:ok, JSON.encode!(ast)}
  rescue
    error -> {:error, "JSON encode failed: #{Exception.message(error)}"}
  end

  defp decode(output) do
    case JSON.decode(output) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, reason} -> {:error, "JSON decode failed: #{inspect(reason)}"}
    end
  end

  defp run_bridge(mode, input) do
    java = java_executable()
    script = bridge_path()
    ext = if mode == "parse", do: ".java", else: ".json"

    temp_path =
      Path.join(
        System.tmp_dir!(),
        "metastatic_java_#{System.unique_integer([:positive, :monotonic])}#{ext}"
      )

    File.write!(temp_path, input)

    try do
      args = [script, mode, temp_path]

      case System.cmd(java, args,
             env: Priv.subprocess_env(),
             stderr_to_stdout: true,
             cd: System.tmp_dir!()
           ) do
        {output, 0} ->
          {:ok, output}

        {error_output, exit_code} ->
          {:error,
           "Java bridge exited with code #{exit_code}: #{String.slice(error_output, 0, 500)}"}
      end
    after
      File.rm(temp_path)
    end
  rescue
    e -> {:error, "Exception running Java bridge: #{Exception.message(e)}"}
  end

  defp format_error(%{"type" => type, "msg" => msg, "line" => line}) when is_integer(line) do
    "#{type} at line #{line}: #{msg}"
  end

  defp format_error(%{"type" => type, "msg" => msg}), do: "#{type}: #{msg}"
  defp format_error(error) when is_binary(error), do: error
  defp format_error(error), do: inspect(error)
end
