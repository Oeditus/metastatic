defmodule Metastatic.Adapters.March.Subprocess do
  @moduledoc """
  Subprocess management for native OCaml March parser and unparser.

  Handles communication with OCaml binaries via stdin/stdout with JSON serialization.
  """

  @parser_bin "priv/parsers/march/_build/default/bin/parser.exe"
  @unparser_bin "priv/parsers/march/_build/default/bin/unparser.exe"

  @doc """
  Parse March source code to AST JSON map using native OCaml parser.
  """
  @spec parse(String.t()) :: {:ok, map()} | {:error, String.t()}
  def parse(source) when is_binary(source) do
    bin_full_path = Path.join(File.cwd!(), @parser_bin)

    cond do
      File.exists?(bin_full_path) ->
        run_binary(bin_full_path, source, &extract_ast/1)

      System.find_executable("dune") != nil ->
        parser_dir = Path.join(File.cwd!(), "priv/parsers/march")
        run_dune_cmd(parser_dir, ["exec", "parser"], source, &extract_ast/1)

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
        bin_full_path = Path.join(File.cwd!(), @unparser_bin)

        cond do
          File.exists?(bin_full_path) ->
            run_binary(bin_full_path, json, &extract_source/1)

          System.find_executable("dune") != nil ->
            parser_dir = Path.join(File.cwd!(), "priv/parsers/march")
            run_dune_cmd(parser_dir, ["exec", "unparser"], json, &extract_source/1)

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
      case System.cmd(bin_path, [temp_path], stderr_to_stdout: true) do
        {output, 0} -> decoder.(output)
        {output, _code} -> {:error, output}
      end
    after
      File.rm(temp_path)
    end
  end

  defp run_dune_cmd(dir, args, input, decoder) do
    temp_path =
      Path.join(
        System.tmp_dir!(),
        "metastatic_march_#{System.unique_integer([:positive, :monotonic])}.txt"
      )

    File.write!(temp_path, input)

    try do
      case System.cmd("dune", args ++ ["--", temp_path], cd: dir, stderr_to_stdout: true) do
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
