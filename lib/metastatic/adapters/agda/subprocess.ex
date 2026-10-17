defmodule Metastatic.Adapters.Agda.Subprocess do
  @moduledoc """
  Manages subprocess communication with the Agda parser.

  Uses the compiled parser binary built from `priv/parsers/agda/`.
  """

  alias Metastatic.Priv

  @parser_rel_dir "parsers/agda"
  @bin_rel_path "parsers/agda/bin/parser"

  @doc """
  Parse Agda source code by invoking the Agda parser subprocess.

  Returns `{:ok, ast}` on success or `{:error, reason}` on failure.

  ## Examples

      iex> Metastatic.Adapters.Agda.Subprocess.parse("1 + 2")
      {:ok, %{"type" => "infix", ...}}

  """
  @spec parse(String.t()) :: {:ok, map()} | {:error, String.t()}
  def parse(source) when is_binary(source) do
    bin_path = Priv.parser_path(@bin_rel_path)
    parser_dir = Priv.parser_path(@parser_rel_dir)
    global_bin = Priv.find_executable("metastatic-agda-parser")
    ghc_bin = Priv.find_executable("ghc")

    cond do
      File.exists?(bin_path) ->
        run_cmd(bin_path, [], source)

      global_bin != nil ->
        run_cmd(global_bin, [], source)

      File.dir?(parser_dir) and ghc_bin != nil ->
        ensure_compiled_and_run(source, parser_dir, bin_path, ghc_bin)

      true ->
        {:error, "Agda parser unavailable"}
    end
  end

  defp ensure_compiled_and_run(source, parser_dir, bin_path, ghc) do
    File.mkdir_p!(Path.dirname(bin_path))

    case System.cmd(ghc, ["-O2", "Parser.hs", "-o", bin_path],
           cd: parser_dir,
           env: Priv.subprocess_env(),
           stderr_to_stdout: true
         ) do
      {_, 0} ->
        run_cmd(bin_path, [], source)

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

    File.write!(temp_path, preprocess_literate(source))

    try do
      cmd_args = args ++ [temp_path]
      default_opts = [stderr_to_stdout: true, env: Priv.subprocess_env()]

      case System.cmd(executable, cmd_args, Keyword.merge(default_opts, opts)) do
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

  defp preprocess_literate(source) do
    if String.contains?(source, "\\begin{code}") do
      {lines, _in_code} =
        source
        |> String.split("\n")
        |> Enum.map_reduce(false, fn line, in_code ->
          trimmed = String.trim(line)

          cond do
            trimmed == "\\begin{code}" -> {"", true}
            trimmed == "\\end{code}" -> {"", false}
            in_code -> {line, true}
            true -> {"", false}
          end
        end)

      Enum.join(lines, "\n")
    else
      source
    end
  end
end
