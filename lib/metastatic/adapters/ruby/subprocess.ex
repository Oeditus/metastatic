defmodule Metastatic.Adapters.Ruby.Subprocess do
  @moduledoc """
  Subprocess management for Ruby parser and unparser.

  Handles communication with Ruby scripts via stdin/stdout with JSON serialization.
  """

  @parser_path "priv/parsers/ruby/parser.rb"
  @unparser_path "priv/parsers/ruby/unparser.rb"

  @doc """
  Parse Ruby source code to AST JSON.

  ## Examples

      iex> Metastatic.Adapters.Ruby.Subprocess.parse("x = 42")
      {:ok, %{"type" => "lvasgn", "children" => [...]}}

      iex> Metastatic.Adapters.Ruby.Subprocess.parse("x = ")
      {:error, "SyntaxError: ..."}
  """
  @spec parse(String.t()) :: {:ok, map()} | {:error, String.t()}
  def parse(source) do
    case run_ruby_script(@parser_path, source) do
      {:ok, result} ->
        case Jason.decode(result) do
          {:ok, %{"status" => "ok", "ast" => nil}} ->
            {:error, "Parse error: syntax error"}

          {:ok, %{"status" => "ok", "ast" => ast}} ->
            {:ok, ast}

          {:ok, %{"status" => "error", "error" => error}} ->
            {:error, format_error(error)}

          {:error, reason} ->
            {:error, "JSON decode failed: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, "Ruby process failed: #{inspect(reason)}"}
    end
  end

  @doc """
  Unparse AST JSON back to Ruby source code.

  ## Examples

      iex> ast = %{"type" => "lvasgn", "children" => [...]}
      iex> Metastatic.Adapters.Ruby.Subprocess.unparse(ast)
      {:ok, "x = 42"}
  """
  @spec unparse(map()) :: {:ok, String.t()} | {:error, String.t()}
  def unparse(ast) do
    input = Jason.encode!(%{ast: ast})

    case run_ruby_script(@unparser_path, input) do
      {:ok, result} ->
        # Unparser outputs source directly, not JSON
        {:ok, String.trim(result)}

      {:error, reason} ->
        {:error, "Ruby unparse failed: #{inspect(reason)}"}
    end
  end

  # Private Functions

  defp run_ruby_script(script_path, input) do
    script_full_path = Path.join(File.cwd!(), script_path)
    script_dir = Path.dirname(script_full_path)

    # Check if script exists
    if File.exists?(script_full_path) do
      # Use printf to pipe input to bundle exec ruby
      # This avoids stdin: option issues with System.cmd
      command =
        "cd #{shell_escape(script_dir)} && printf '%s' #{shell_escape(input)} | bundle exec ruby #{Path.basename(script_full_path)} 2>&1"

      case System.cmd("sh", ["-c", command]) do
        {output, 0} ->
          # Filter out parser version warnings from output
          clean_output = filter_warnings(output)
          {:ok, clean_output}

        {error_output, exit_code} ->
          {:error, "Exit code #{exit_code}: #{error_output}"}
      end
    else
      {:error, "Ruby script not found: #{script_full_path}"}
    end
  rescue
    e ->
      {:error, "Exception: #{Exception.message(e)}"}
  end

  defp format_error(error) when is_binary(error) do
    "Parse error: #{error}"
  end

  defp format_error(%{"error" => error, "line" => line}) do
    "Parse error at line #{line}: #{error}"
  end

  defp format_error(error) do
    "Parse error: #{inspect(error)}"
  end

  defp shell_escape(string) do
    # Escape single quotes for shell
    escaped = String.replace(string, "'", "'\\''")
    "'#{escaped}'"
  end

  defp filter_warnings(output) do
    output
    |> String.split("\n")
    |> Enum.reject(fn line ->
      String.contains?(line, "parser/current is loading") or
        String.contains?(line, "Please see https://github.com/whitequark/parser")
    end)
    |> Enum.join("\n")
  end
end
