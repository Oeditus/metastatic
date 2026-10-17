defmodule Metastatic.Adapters.March.Subprocess do
  @moduledoc """
  Subprocess management for native OCaml March parser and unparser.

  Handles communication with OCaml binaries via stdin/stdout with JSON serialization.
  """

  alias Metastatic.Priv

  @parser_bin "parsers/march/_build/default/bin/parser.exe"
  @unparser_bin "parsers/march/_build/default/bin/unparser.exe"
  @parser_rel_dir "parsers/march"

  @doc """
  Parse March source code to AST JSON map using native OCaml parser.
  """
  @spec parse(String.t()) :: {:ok, map()} | {:error, String.t()}
  def parse(source) when is_binary(source) do
    bin_full_path = Priv.parser_path(@parser_bin)
    global_bin = Priv.find_executable("metastatic-march-parser")
    dune_bin = Priv.find_executable("dune")

    cond do
      File.exists?(bin_full_path) ->
        run_binary(bin_full_path, source, &extract_ast/1)

      global_bin != nil ->
        run_binary(global_bin, source, &extract_ast/1)

      dune_bin != nil ->
        parser_dir = Priv.parser_path(@parser_rel_dir)
        run_dune_cmd(dune_bin, parser_dir, ["exec", "parser"], source, &extract_ast/1)

      true ->
        {:error, "March OCaml parser binary unavailable"}
    end
  end

  @doc """
  Unparse AST JSON map back to March source code using native OCaml unparser.
  """
  @spec unparse(map()) :: {:ok, String.t()} | {:error, String.t()}
  def unparse(ast) when is_map(ast) do
    case Jason.encode(ast) do
      {:ok, json} ->
        bin_full_path = Priv.parser_path(@unparser_bin)
        global_bin = Priv.find_executable("metastatic-march-unparser")
        dune_bin = Priv.find_executable("dune")

        cond do
          File.exists?(bin_full_path) ->
            run_binary(bin_full_path, json, &extract_source/1)

          global_bin != nil ->
            run_binary(global_bin, json, &extract_source/1)

          dune_bin != nil ->
            parser_dir = Priv.parser_path(@parser_rel_dir)
            run_dune_cmd(dune_bin, parser_dir, ["exec", "unparser"], json, &extract_source/1)

          true ->
            {:error, "March OCaml unparser binary unavailable"}
        end

      {:error, reason} ->
        {:error, "JSON encode failed: #{inspect(reason)}"}
    end
  end

  # Helpers

  defp run_binary(bin_path, input, decoder) do
    temp_path =
      Path.join(
        System.tmp_dir!(),
        "metastatic_march_#{System.unique_integer([:positive, :monotonic])}.txt"
      )

    File.write!(temp_path, input)

    try do
      case System.cmd(bin_path, [temp_path],
             env: Priv.subprocess_env(),
             stderr_to_stdout: true
           ) do
        {output, 0} -> decoder.(output)
        {output, _code} -> {:error, output}
      end
    after
      File.rm(temp_path)
    end
  end

  defp run_dune_cmd(dune_bin, dir, args, input, decoder) do
    temp_path =
      Path.join(
        System.tmp_dir!(),
        "metastatic_march_#{System.unique_integer([:positive, :monotonic])}.txt"
      )

    File.write!(temp_path, input)

    try do
      case System.cmd(dune_bin, args ++ ["--", temp_path],
             cd: dir,
             env: Priv.subprocess_env(),
             stderr_to_stdout: true
           ) do
        {output, 0} -> decoder.(output)
        {output, _code} -> {:error, output}
      end
    after
      File.rm(temp_path)
    end
  end

  defp extract_ast(json_str) do
    case Jason.decode(json_str) do
      {:ok, %{"ok" => true, "ast" => ast}} -> {:ok, ast}
      {:ok, %{"ok" => false, "error" => err}} -> {:error, inspect(err)}
      {:error, reason} -> {:error, "JSON decode failed: #{inspect(reason)}"}
    end
  end

  defp extract_source(json_str) do
    case Jason.decode(json_str) do
      {:ok, %{"ok" => true, "source" => source}} -> {:ok, source}
      {:ok, %{"ok" => false, "error" => err}} -> {:error, inspect(err)}
      {:error, reason} -> {:error, "JSON decode failed: #{inspect(reason)}"}
    end
  end
end
