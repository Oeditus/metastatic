defmodule Metastatic.Adapters.Agda.Subprocess do
  @moduledoc """
  Manages subprocess communication with the Agda parser.

  Uses the compiled parser binary built from `priv/parsers/agda/`.
  """

  @parser_dir Path.expand("../../../../priv/parsers/agda", __DIR__)
  @bin_path Path.expand("../../../../priv/parsers/agda/bin/parser", __DIR__)

  @doc """
  Parse Agda source code by invoking the Agda parser subprocess.

  Returns `{:ok, ast}` on success or `{:error, reason}` on failure.

  ## Examples

      iex> Metastatic.Adapters.Agda.Subprocess.parse("1 + 2")
      {:ok, %{"type" => "infix", ...}}

  """
  @spec parse(String.t()) :: {:ok, map()} | {:error, String.t()}
  def parse(source) when is_binary(source) do
    cond do
      File.exists?(@bin_path) ->
        run_cmd(@bin_path, [], source)

      File.dir?(@parser_dir) and
          (System.find_executable("ghc") != nil or File.exists?("/usr/bin/ghc")) ->
        ensure_compiled_and_run(source)

      true ->
        {:error, "Agda parser unavailable"}
    end
  end

  defp ensure_compiled_and_run(source) do
    ghc = System.find_executable("ghc") || "/usr/bin/ghc"
    File.mkdir_p!(Path.dirname(@bin_path))

    case System.cmd(ghc, ["-O2", "Parser.hs", "-o", @bin_path],
           cd: @parser_dir,
           stderr_to_stdout: true
         ) do
      {_, 0} ->
        run_cmd(@bin_path, [], source)

      {error_output, _} ->
        {:error, "Failed to compile Agda parser: #{inspect(error_output)}"}
    end
  end

  defp run_cmd(executable, args, source, opts \\ []) do
    temp_path =
      Path.join(
        System.tmp_dir!(),
        "metastatic_agda_#{System.unique_integer([:positive, :monotonic])}.agda"
      )

    File.write!(temp_path, source)

    try do
      cmd_args = args ++ [temp_path]

      case System.cmd(executable, cmd_args, Keyword.merge([stderr_to_stdout: true], opts)) do
        {output, 0} ->
          handle_parser_output(output)

        {error_output, _exit_code} ->
          {:error, "Agda parser failed: #{inspect(error_output)}"}
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
