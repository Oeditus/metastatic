defmodule Metastatic.Adapters.Haskell.Subprocess do
  @moduledoc """
  Manages subprocess communication with the Haskell parser.

  Uses Stack to execute the parser binary built from `priv/parsers/haskell/`.
  """

  alias Metastatic.Priv

  @parser_rel_dir "parsers/haskell"
  @bin_rel_path "parsers/haskell/bin/parser"

  @doc """
  Parse Haskell source code by invoking the parser binary or Stack subprocess.

  Returns `{:ok, ast}` on success or `{:error, reason}` on failure.

  ## Examples

      iex> Metastatic.Adapters.Haskell.Subprocess.parse("1 + 2")
      {:ok, %{"type" => "infix", ...}}

  """
  @spec parse(String.t()) :: {:ok, map()} | {:error, String.t()}
  def parse(source) when is_binary(source) do
    bin_path = Priv.parser_path(@bin_rel_path)
    parser_dir = Priv.parser_path(@parser_rel_dir)
    global_bin = Priv.find_executable("metastatic-haskell-parser")
    stack_bin = Priv.find_executable("stack")

    cond do
      File.exists?(bin_path) ->
        run_cmd(bin_path, [], source)

      global_bin != nil ->
        run_cmd(global_bin, [], source)

      File.dir?(parser_dir) and stack_bin != nil ->
        run_cmd(stack_bin, ["exec", "parser", "--"], source, cd: parser_dir)

      true ->
        {:error, "Haskell parser unavailable"}
    end
  end

  defp run_cmd(executable, args, source, opts \\ []) do
    temp_path =
      Path.join(
        System.tmp_dir!(),
        "metastatic_hs_#{System.unique_integer([:positive, :monotonic])}.txt"
      )

    File.write!(temp_path, source)

    try do
      cmd_args = args ++ [temp_path]
      default_opts = [stderr_to_stdout: true, env: Priv.subprocess_env()]

      case System.cmd(executable, cmd_args, Keyword.merge(default_opts, opts)) do
        {output, 0} ->
          handle_parser_output(output)

        {error_output, _exit_code} ->
          {:error, "Haskell parser failed: #{inspect(error_output)}"}
      end
    after
      File.rm(temp_path)
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
end
