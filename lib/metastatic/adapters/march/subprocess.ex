defmodule Metastatic.Adapters.March.Subprocess do
  @moduledoc """
  Subprocess management for the native OCaml March parser and unparser.

  Handles communication with OCaml binaries via temporary files with JSON
  serialization. Temp-file handling is delegated to `Metastatic.Subprocess`.
  """

  @behaviour Metastatic.Adapter.Bridge

  alias Metastatic.Adapter.Bridge
  alias Metastatic.{Priv, Subprocess}

  @parser_bin "parsers/march/_build/default/bin/parser.exe"
  @unparser_bin "parsers/march/_build/default/bin/unparser.exe"
  @parser_rel_dir "parsers/march"

  @doc """
  Parse March source code to AST JSON map using the native OCaml parser.
  """
  @impl true
  @spec parse(String.t()) :: {:ok, map()} | {:error, String.t()}
  def parse(source) when is_binary(source) do
    with {:ok, output} <- run(source, @parser_bin, "metastatic-march-parser", "parser", ".march") do
      Bridge.decode(output)
    end
  end

  @doc """
  Unparse AST JSON map back to March source code using the native OCaml unparser.
  """
  @impl true
  @spec unparse(map()) :: {:ok, String.t()} | {:error, String.t()}
  def unparse(ast) when is_map(ast) do
    with {:ok, json} <- Bridge.encode(ast),
         {:ok, output} <-
           run(json, @unparser_bin, "metastatic-march-unparser", "unparser", ".json") do
      Bridge.decode(output)
    end
  end

  @doc """
  Returns `true` when compiled March binaries or `dune` are available.
  """
  @spec available?() :: boolean()
  def available? do
    File.exists?(Priv.parser_path(@parser_bin)) or
      Priv.find_executable("metastatic-march-parser") != nil or
      Priv.find_executable("dune") != nil
  end

  # Helpers

  defp run(input, bin_rel_path, global_name, dune_target, ext) do
    bin_full_path = Priv.parser_path(bin_rel_path)
    global_bin = Priv.find_executable(global_name)
    dune_bin = Priv.find_executable("dune")

    cond do
      File.exists?(bin_full_path) ->
        Subprocess.run(bin_full_path, [], input, ext: ext, prefix: "metastatic_march")

      global_bin != nil ->
        Subprocess.run(global_bin, [], input, ext: ext, prefix: "metastatic_march")

      dune_bin != nil ->
        Subprocess.run(
          dune_bin,
          ["exec", dune_target, "--"],
          input,
          ext: ext,
          prefix: "metastatic_march",
          cd: Priv.parser_path(@parser_rel_dir)
        )

      true ->
        {:error,
         "March OCaml #{dune_target} unavailable: no compiled binary, no `#{global_name}` " <>
           "on PATH, and no `dune`"}
    end
  end
end
