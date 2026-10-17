defmodule Metastatic.Adapters.Python.Subprocess do
  @moduledoc """
  Subprocess management for Python parser and unparser.

  Handles communication with Python scripts via stdin/stdout with JSON serialization.
  """

  alias Metastatic.Priv

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
    script_full_path = Priv.parser_path(@parser_path)

    if File.exists?(script_full_path) and python_bin() != nil do
      case run_python_script(@parser_path, source) do
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
          {:error, "Python process failed: #{inspect(reason)}"}
      end
    else
      {:error, "Python parser unavailable"}
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
    case Jason.encode(ast) do
      {:ok, json} ->
        case run_python_script(@unparser_path, json) do
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
            {:error, "Python process failed: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, "JSON encode failed: #{inspect(reason)}"}
    end
  end

  # Private Functions

  defp python_bin do
    Priv.find_executable("python3") || Priv.find_executable("python")
  end

  defp run_python_script(script_path, input) do
    script_full_path = Priv.parser_path(script_path)
    py_bin = python_bin() || "python3"

    if File.exists?(script_full_path) do
      temp_path =
        Path.join(
          System.tmp_dir!(),
          "metastatic_py_#{System.unique_integer([:positive, :monotonic])}.txt"
        )

      File.write!(temp_path, input)

      try do
        case System.cmd(py_bin, [script_full_path, temp_path],
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
      {:error, "Python script not found: #{script_full_path}"}
    end
  rescue
    e ->
      {:error, "Exception: #{Exception.message(e)}"}
  end

  defp format_error(%{"type" => type, "msg" => msg, "lineno" => line}) do
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
