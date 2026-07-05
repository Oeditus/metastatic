defmodule Metastatic.Adapters.Haskell.Subprocess do
  @moduledoc """
  Manages subprocess communication with the Haskell parser.

  Uses Stack to execute the parser binary built from `priv/parsers/haskell/`.
  """

  @parser_dir Path.expand("../../../../priv/parsers/haskell", __DIR__)

  @doc """
  Parse Haskell source code by invoking the Stack-based parser subprocess.

  Returns `{:ok, ast}` on success or `{:error, reason}` on failure.

  ## Examples

      iex> Metastatic.Adapters.Haskell.Subprocess.parse("1 + 2")
      {:ok, %{"type" => "infix", ...}}

  """
  @spec parse(String.t()) :: {:ok, map()} | {:error, String.t()}
  def parse(source) when is_binary(source) do
    parser_command =
      "cd #{@parser_dir} && printf %s \"#{escape_source(source)}\" | stack exec parser"

    case System.cmd("sh", ["-c", parser_command], stderr_to_stdout: true) do
      {output, 0} ->
        handle_parser_output(output)

      {error_output, _exit_code} ->
        {:error, "Haskell parser failed: #{inspect(error_output)}"}
    end
  end

  # Handle parser JSON output
  defp handle_parser_output(output) do
    case Jason.decode(output) do
      {:ok, %{"status" => "ok", "ast" => ast}} when not is_nil(ast) ->
        {:ok, ast}

      {:ok, %{"status" => "error", "errorMessage" => message}} ->
        {:error, "Parse error: #{message}"}

      {:ok, %{"status" => "ok", "ast" => nil}} ->
        {:error, "Parse error: empty AST returned"}

      {:error, _} = error ->
        {:error, "Failed to decode parser output: #{inspect(error)}"}
    end
  end

  # Escape source for shell command
  defp escape_source(source) do
    source
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("$", "\\$")
    |> String.replace("`", "\\`")
  end
end
