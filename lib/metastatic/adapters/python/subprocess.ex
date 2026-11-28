defmodule Metastatic.Adapters.Python.Subprocess do
  @moduledoc """
  Subprocess management for Python parser and unparser.

  Handles communication with Python scripts via temporary files with JSON
  serialization. Temp-file handling, exit-code reporting and error formatting
  are delegated to `Metastatic.Subprocess`.
  """

  alias Metastatic.Adapter.Bridge
  alias Metastatic.{Priv, Subprocess}

  @parser_path "parsers/python/parser.py"
  @unparser_path "parsers/python/unparser.py"

  @doc """
  Parse Python source code to AST JSON.

  ## Examples

      iex> Metastatic.Adapters.Python.Subprocess.parse("x + 5")
      {:ok, %{"_type" => "Module", "body" => [...]}}

      iex> Metastatic.Adapters.Python.Subprocess.parse("x +")
      {:error, "SyntaxError: ..."}
  """
  @spec parse(String.t()) :: {:ok, map()} | {:error, String.t()}
  def parse(source) do
    with :ok <- check_available(),
         {:ok, result} <- run_script(@parser_path, source, ".py") do
      Bridge.decode(result)
    end
  end

  @doc """
  Unparse AST JSON back to Python source code.

  ## Examples

      iex> ast = %{"_type" => "Module", "body" => [...]}
      iex> Metastatic.Adapters.Python.Subprocess.unparse(ast)
      {:ok, "x + 5"}
  """
  @spec unparse(map()) :: {:ok, String.t()} | {:error, String.t()}
  def unparse(ast) do
    with {:ok, json} <- Bridge.encode(ast),
         :ok <- check_available(),
         {:ok, result} <- run_script(@unparser_path, json, ".json") do
      Bridge.decode(result)
    end
  end

  @doc """
  Returns `true` when the Python parser script and runtime are available.
  """
  @spec available?() :: boolean()
  def available?, do: check_available() == :ok

  # Private Functions

  defp check_available do
    cond do
      not File.exists?(Priv.parser_path(@parser_path)) ->
        {:error, "Python parser unavailable: #{@parser_path} is missing from the package"}

      python_bin() == nil ->
        {:error, "Python parser unavailable: no `python3` or `python` executable found"}

      true ->
        :ok
    end
  end

  defp python_bin do
    Priv.find_executable("python3") || Priv.find_executable("python")
  end

  defp run_script(script_path, input, ext) do
    script_full_path = Priv.parser_path(script_path)

    if File.exists?(script_full_path) do
      Subprocess.run(python_bin(), [script_full_path], input, ext: ext, prefix: "metastatic_py")
    else
      {:error, "Python script not found: #{script_full_path}"}
    end
  end
end
