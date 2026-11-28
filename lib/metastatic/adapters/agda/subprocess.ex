defmodule Metastatic.Adapters.Agda.Subprocess do
  @moduledoc """
  Manages subprocess communication with the Agda parser.

  Uses the compiled parser binary built from `priv/parsers/agda/`, or a
  `metastatic-agda-parser` on `PATH`, or compiles the bundled source with GHC
  on first use. Temp-file handling is delegated to `Metastatic.Subprocess`.
  """

  @behaviour Metastatic.Adapter.Bridge

  alias Metastatic.Adapter.Bridge
  alias Metastatic.Adapter.Bridge.Cache
  alias Metastatic.{Priv, Subprocess}

  @parser_rel_dir "parsers/agda"
  @bin_rel_path "parsers/agda/bin/parser"

  @doc """
  Parse Agda source code by invoking the Agda parser subprocess.

  Returns `{:ok, ast}` on success or `{:error, reason}` on failure.

  ## Examples

      iex> Metastatic.Adapters.Agda.Subprocess.parse("1 + 2")
      {:ok, %{"type" => "infix", ...}}

  """
  @impl true
  @spec parse(String.t()) :: {:ok, map()} | {:error, String.t()}
  def parse(source) when is_binary(source) do
    bin_path = Priv.parser_path(@bin_rel_path)
    parser_dir = Priv.parser_path(@parser_rel_dir)
    global_bin = Priv.find_executable("metastatic-agda-parser")
    ghc_bin = Priv.find_executable("ghc")

    cond do
      File.exists?(bin_path) ->
        run_parser(bin_path, source)

      global_bin != nil ->
        run_parser(global_bin, source)

      File.dir?(parser_dir) and ghc_bin != nil ->
        ensure_compiled_and_run(source, parser_dir, ghc_bin)

      true ->
        {:error,
         "Agda parser unavailable: no compiled parser, no `metastatic-agda-parser` on PATH, " <>
           "and no `ghc` to build priv/parsers/agda"}
    end
  end

  @doc """
  Returns `true` when a compiled Agda parser or `ghc` + bundled sources are available.
  """
  @spec available?() :: boolean()
  def available? do
    File.exists?(Priv.parser_path(@bin_rel_path)) or
      Priv.find_executable("metastatic-agda-parser") != nil or
      (File.dir?(Priv.parser_path(@parser_rel_dir)) and Priv.find_executable("ghc") != nil)
  end

  defp ensure_compiled_and_run(source, parser_dir, ghc) do
    parser_src = Path.join(parser_dir, "Parser.hs")

    with {:ok, bin_path} <-
           Cache.fetch_or_build(
             :agda,
             "metastatic-agda-parser",
             [ghc, File.read!(parser_src)],
             fn temporary ->
               case System.cmd(ghc, ["-O2", "Parser.hs", "-o", temporary],
                      cd: parser_dir,
                      env: Priv.subprocess_env(),
                      stderr_to_stdout: true
                    ) do
                 {_, 0} -> :ok
                 {error_output, _} -> {:error, "Failed to compile Agda parser: #{inspect(error_output)}"}
               end
             end
           ) do
      run_parser(bin_path, source)
    end
  end

  defp run_parser(executable, source) do
    with {:ok, output} <-
           Subprocess.run(executable, [], preprocess_literate(source),
             ext: ".agda",
             prefix: "metastatic_agda"
           ) do
      Bridge.decode(output)
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
