defmodule Metastatic.Adapters.Python.Subprocess do
  @moduledoc """
  Subprocess management for Python parser and unparser.

  Handles communication with Python scripts via stdin/stdout with JSON serialization.
  """

  @parser_path "priv/parsers/python/parser.py"
  @unparser_path "priv/parsers/python/unparser.py"

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

  defp run_python_script(script_path, input) do
    script_full_path = Path.join(File.cwd!(), script_path)

    # Check if script exists
    if File.exists?(script_full_path) do
      # Use printf to pipe input to python3
      # This avoids stdin: option which doesn't exist in System.cmd
      case System.cmd("sh", [
             "-c",
             "printf '%s' #{shell_escape(input)} | python3 #{script_full_path}"
           ]) do
        {output, 0} ->
          {:ok, output}

        {error_output, exit_code} ->
          {:error, "Exit code #{exit_code}: #{error_output}"}
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

  defp shell_escape(string) do
    # Escape single quotes for shell
    escaped = String.replace(string, "'", "'\\''")
    "'#{escaped}'"
  end
end
