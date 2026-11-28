defmodule Metastatic.Adapters.Go.Subprocess do
  @moduledoc """
  Runs the dependency-free Go parser bridge.

  Resolution prefers `priv/parsers/go/bin/metastatic-go-parser`, then
  `metastatic-go-parser` on PATH. Otherwise the bundled Go sources are built
  once in the user's cache directory. The cache key includes source contents,
  executable path and architecture; source edits invalidate it automatically.
  Concurrent callers serialize the first build, and a failed build is never
  installed as a working executable.
  """

  @behaviour Metastatic.Adapter.Bridge

  alias Metastatic.Adapter.Bridge
  alias Metastatic.Adapter.Bridge.Cache
  alias Metastatic.{Priv, Subprocess}

  @binary "metastatic-go-parser"
  @source_dir "parsers/go"

  @doc """
  Parses Go source into an M1 map.

  ## Examples

      iex> {:ok, ast} = Metastatic.Adapters.Go.Subprocess.parse("42")
      iex> ast["kind"]
      "BasicLit"
  """
  @impl true
  @spec parse(String.t()) :: {:ok, map()} | {:error, String.t()}
  def parse(source) when is_binary(source), do: run("parse", source, ".go")

  @doc """
  Prints a native Go AST.

  ## Examples

      iex> {:ok, ast} = Metastatic.Adapters.Go.Subprocess.parse("42")
      iex> Metastatic.Adapters.Go.Subprocess.unparse(ast)
      {:ok, "42"}
  """
  @impl true
  @spec unparse(term()) :: {:ok, String.t()} | {:error, String.t()}
  def unparse(ast) do
    with {:ok, json} <- Bridge.encode(ast), do: run("unparse", json, ".json")
  end

  @doc """
  Formats Go source with `go/format`.

  ## Examples

      iex> Metastatic.Adapters.Go.Subprocess.format("package p\\nvar x=1\\n")
      {:ok, "package p\\n\\nvar x = 1\\n"}
  """
  @spec format(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def format(source) when is_binary(source), do: run("fmt", source, ".go")

  @doc """
  Runs the bridge's native parse/print self-test.

  ## Examples

      iex> {:ok, report} = Metastatic.Adapters.Go.Subprocess.selftest()
      iex> report["status"]
      "ok"
  """
  @spec selftest() :: {:ok, map()} | {:error, String.t()}
  def selftest, do: run("selftest", "", ".txt")

  @doc """
  Checks whether a prebuilt bridge or the Go toolchain and sources are present.

  Does not build anything or guarantee that the installed toolchain works.

  ## Examples

      iex> is_boolean(Metastatic.Adapters.Go.Subprocess.available?())
      true
  """
  @spec available?() :: boolean()
  def available?, do: prebuilt() != nil or (go_executable() != nil and sources_present?())

  defp run(mode, input, extension) do
    with {:ok, executable} <- executable(),
         {:ok, output} <-
           Subprocess.run(executable, [mode], input,
             ext: extension,
             prefix: "metastatic_go"
           ) do
      Bridge.decode(output)
    end
  rescue
    error -> {:error, "Go parser unavailable: #{Exception.message(error)}"}
  end

  defp executable do
    case prebuilt() do
      nil -> build_bridge()
      path -> {:ok, path}
    end
  end

  defp prebuilt do
    bundled = Priv.parser_path("#{@source_dir}/bin/#{@binary}")
    if Cache.executable_file?(bundled), do: bundled, else: Priv.find_executable(@binary)
  end

  defp go_executable, do: Priv.find_executable("go")
  defp source_dir, do: Priv.parser_path(@source_dir)

  defp sources_present? do
    Enum.all?(["go.mod", "main.go", "ast.go", "to_json.go"], fn name ->
      File.regular?(Path.join(source_dir(), name))
    end)
  end

  defp build_bridge do
    cond do
      go_executable() == nil ->
        {:error, "Go parser unavailable: install Go 1.21 or newer, or put #{@binary} on PATH"}

      not sources_present?() ->
        {:error, "Go parser sources are missing from #{source_dir()}; reinstall Metastatic"}

      true ->
        build_cached(go_executable(), source_dir())
    end
  end

  defp build_cached(go, directory) do
    sources =
      [Path.join(directory, "go.mod") | Path.wildcard(Path.join(directory, "*.go"))]
      |> Enum.reject(&String.ends_with?(&1, "_test.go"))
      |> Enum.sort()
      |> Enum.map(fn path -> [Path.basename(path), 0, File.read!(path), 0] end)

    Cache.fetch_or_build(:go, @binary, [go, sources], fn temporary ->
      case System.cmd(go, ["build", "-trimpath", "-o", temporary, "."],
             cd: directory,
             env: Priv.subprocess_env([{"GOWORK", "off"}]),
             stderr_to_stdout: true
           ) do
        {_, 0} ->
          :ok

        {output, code} ->
          {:error, "Go parser build failed (exit #{code}): #{String.trim(output)}"}
      end
    end)
  end
end
