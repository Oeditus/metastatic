defmodule Metastatic.Adapters.March.Subprocess do
  @moduledoc """
  Subprocess management for the native OCaml March parser and unparser.

  Handles communication with OCaml binaries via temporary files with JSON
  serialization. Temp-file handling is delegated to `Metastatic.Subprocess`.
  """

  alias Metastatic.{Priv, Subprocess}

  @parser_bin "parsers/march/_build/default/bin/parser.exe"
  @unparser_bin "parsers/march/_build/default/bin/unparser.exe"
  @parser_rel_dir "parsers/march"

  @doc """
  Parse March source code to AST JSON map using the native OCaml parser.
  """
  @spec parse(String.t()) :: {:ok, map()} | {:error, String.t()}
  def parse(source) when is_binary(source) do
    with {:ok, output} <- run(source, @parser_bin, "metastatic-march-parser", "parser") do
      extract_ast(output)
    end
  end

  @doc """
  Unparse AST JSON map back to March source code using the native OCaml unparser.
  """
  @spec unparse(map()) :: {:ok, String.t()} | {:error, String.t()}
  def unparse(ast) when is_map(ast) do
    with {:ok, json} <- encode(ast),
         {:ok, output} <- run(json, @unparser_bin, "metastatic-march-unparser", "unparser") do
      extract_source(output)
    end
  end

  # Helpers

  defp encode(ast) do
    {:ok, Jason.encode!(ast)}
  rescue
    error -> {:error, "JSON encode failed: #{Exception.message(error)}"}
  end

  defp run(input, bin_rel_path, global_name, dune_target) do
    bin_full_path = Priv.parser_path(bin_rel_path)
    global_bin = Priv.find_executable(global_name)
    dune_bin = Priv.find_executable("dune")

    cond do
      File.exists?(bin_full_path) ->
        Subprocess.run(bin_full_path, [], input, ext: ".march", prefix: "metastatic_march")

      global_bin != nil ->
        Subprocess.run(global_bin, [], input, ext: ".march", prefix: "metastatic_march")

      dune_bin != nil ->
        Subprocess.run(
          dune_bin,
          ["exec", dune_target, "--"],
          input,
          ext: ".march",
          prefix: "metastatic_march",
          cd: Priv.parser_path(@parser_rel_dir)
        )

      true ->
        {:error,
         "March OCaml #{dune_target} unavailable: no compiled binary, no `#{global_name}` " <>
           "on PATH, and no `dune`"}
    end
  end

  defp extract_ast(json_str) do
    case Jason.decode(json_str) do
      {:ok, %{"ok" => true, "ast" => ast}} -> {:ok, ast}
      {:ok, %{"ok" => false, "error" => err}} -> {:error, Subprocess.format_error(err)}
      {:error, reason} -> {:error, "JSON decode failed: #{inspect(reason)}"}
    end
  end

  defp extract_source(json_str) do
    case Jason.decode(json_str) do
      {:ok, %{"ok" => true, "source" => source}} -> {:ok, source}
      {:ok, %{"ok" => false, "error" => err}} -> {:error, Subprocess.format_error(err)}
      {:error, reason} -> {:error, "JSON decode failed: #{inspect(reason)}"}
    end
  end
end
