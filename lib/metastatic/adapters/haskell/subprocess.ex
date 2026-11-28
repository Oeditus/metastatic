defmodule Metastatic.Adapters.Haskell.Subprocess do
  @moduledoc """
  Manages subprocess communication with the Haskell parser.

  Uses the compiled parser binary built from `priv/parsers/haskell/`, or a
  `metastatic-haskell-parser` on `PATH`, or `stack exec parser`. Temp-file
  handling is delegated to `Metastatic.Subprocess`.
  """

  alias Metastatic.Adapter.Bridge
  alias Metastatic.{Priv, Subprocess}

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
        run_parser(bin_path, [], source, [])

      global_bin != nil ->
        run_parser(global_bin, [], source, [])

      File.dir?(parser_dir) and stack_bin != nil ->
        run_parser(stack_bin, ["exec", "parser", "--"], source, cd: parser_dir)

      true ->
        {:error,
         "Haskell parser unavailable: no compiled parser, no `metastatic-haskell-parser` " <>
           "on PATH, and no `stack` to build priv/parsers/haskell"}
    end
  end

  @doc """
  Returns `true` when a compiled Haskell parser or `stack` + bundled sources are available.
  """
  @spec available?() :: boolean()
  def available? do
    File.exists?(Priv.parser_path(@bin_rel_path)) or
      Priv.find_executable("metastatic-haskell-parser") != nil or
      (File.dir?(Priv.parser_path(@parser_rel_dir)) and Priv.find_executable("stack") != nil)
  end

  defp run_parser(executable, args, source, opts) do
    with {:ok, output} <-
           Subprocess.run(executable, args, source, [ext: ".hs", prefix: "metastatic_hs"] ++ opts) do
      Bridge.decode(output)
    end
  end
end
