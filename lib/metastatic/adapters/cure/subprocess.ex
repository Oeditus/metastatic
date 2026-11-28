defmodule Metastatic.Adapters.Cure.Subprocess do
  @moduledoc """
  Subprocess management for the Cure parser and unparser fallback.

  Handles communication with an external Cure CLI or parser binary when the
  in-process Cure compiler modules are unavailable.

  Temp-file handling is delegated to `Metastatic.Subprocess`.
  """

  alias Metastatic.Adapter.Bridge
  alias Metastatic.{Priv, Subprocess}

  @parser_bin "parsers/cure/bin/parser.exe"

  @doc """
  Parse Cure source code to AST using an external subprocess binary or the
  `cure` CLI executable.
  """
  @spec parse(String.t(), keyword()) :: {:ok, term()} | {:error, String.t()}
  def parse(source, opts \\ []) when is_binary(source) and is_list(opts) do
    with {:ok, {executable, args}} <- resolve("parse", opts),
         {:ok, output} <- run(executable, args, source, ".cure") do
      Bridge.decode(output)
    end
  end

  @doc """
  Unparse Cure AST back to source code using an external subprocess binary or
  the `cure` CLI executable.
  """
  @spec unparse(term(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def unparse(ast, opts \\ []) when is_list(opts) do
    with {:ok, json} <- Bridge.encode(ast),
         {:ok, {executable, args}} <- resolve("unparse", opts),
         {:ok, output} <- run(executable, args, json, ".json") do
      Bridge.decode(output)
    end
  end

  @doc """
  Returns `true` when a compiled Cure parser binary or `cure` CLI is available.
  """
  @spec available?(keyword()) :: boolean()
  def available?(opts \\ []) when is_list(opts) do
    match?({:ok, _}, resolve("parse", opts))
  end

  # Helpers

  defp resolve(mode, opts) do
    bin_full_path = Keyword.get_lazy(opts, :parser_bin, fn -> Priv.parser_path(@parser_bin) end)
    cure_cli = Keyword.get_lazy(opts, :cure_cli, fn -> Priv.find_executable("cure") end)

    cond do
      bin_full_path != nil and File.exists?(bin_full_path) ->
        {:ok, {bin_full_path, []}}

      cure_cli != nil and File.exists?(cure_cli) ->
        {:ok, {cure_cli, [mode, "--json"]}}

      true ->
        {:error,
         "Cure subprocess parser unavailable: no compiled parser at #{inspect(bin_full_path)} " <>
           "and no `cure` executable on PATH"}
    end
  end

  defp run(executable, args, input, ext) do
    Subprocess.run(executable, args, input, ext: ext, prefix: "metastatic_cure")
  end
end
