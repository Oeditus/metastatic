defmodule Metastatic.Adapters.Cure.Subprocess do
  @moduledoc """
  Subprocess management for Cure parser and unparser fallback.

  Handles communication with external Cure CLI or parser binaries when in-process
  Cure compiler modules are unavailable.
  """

  @parser_bin "priv/parsers/cure/bin/parser.exe"

  @doc """
  Parse Cure source code to AST using external subprocess binary or `cure` CLI executable.
  """
  @spec parse(String.t(), keyword()) :: {:ok, term()} | {:error, String.t()}
  def parse(source, opts \\ []) when is_binary(source) and is_list(opts) do
    bin_full_path = Keyword.get(opts, :parser_bin, Path.join(File.cwd!(), @parser_bin))
    cure_cli = Keyword.get_lazy(opts, :cure_cli, fn -> System.find_executable("cure") end)

    cond do
      bin_full_path != nil and File.exists?(bin_full_path) ->
        run_binary(bin_full_path, source)

      cure_cli != nil and File.exists?(cure_cli) ->
        run_cure_cli(cure_cli, source)

      true ->
        {:error, "Cure subprocess parser unavailable"}
    end
  end

  @doc """
  Unparse Cure AST back to source code using external subprocess binary or `cure` CLI executable.
  """
  @spec unparse(term(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def unparse(ast, opts \\ []) when is_list(opts) do
    case Jason.encode(ast) do
      {:ok, json} ->
        bin_full_path = Keyword.get(opts, :parser_bin, Path.join(File.cwd!(), @parser_bin))
        cure_cli = Keyword.get_lazy(opts, :cure_cli, fn -> System.find_executable("cure") end)

        cond do
          bin_full_path != nil and File.exists?(bin_full_path) ->
            run_binary_unparse(bin_full_path, json)

          cure_cli != nil and File.exists?(cure_cli) ->
            run_cure_cli_unparse(cure_cli, json)

          true ->
            {:error, "Cure subprocess unparser unavailable"}
        end

      {:error, reason} ->
        {:error, "JSON encode failed: #{inspect(reason)}"}
    end
  end

  # Helpers

  defp run_binary(bin_path, input) do
    temp_path =
      Path.join(
        System.tmp_dir!(),
        "metastatic_cure_#{System.unique_integer([:positive, :monotonic])}.cure"
      )

    File.write!(temp_path, input)

    try do
      case System.cmd(bin_path, [temp_path], stderr_to_stdout: true) do
        {output, 0} -> decode_ast(output)
        {output, _code} -> {:error, output}
      end
    after
      File.rm(temp_path)
    end
  end

  defp run_cure_cli(cli_path, input) do
    temp_path =
      Path.join(
        System.tmp_dir!(),
        "metastatic_cure_#{System.unique_integer([:positive, :monotonic])}.cure"
      )

    File.write!(temp_path, input)

    try do
      case System.cmd(cli_path, ["parse", "--json", temp_path], stderr_to_stdout: true) do
        {output, 0} -> decode_ast(output)
        {output, _code} -> {:error, output}
      end
    after
      File.rm(temp_path)
    end
  end

  defp run_binary_unparse(bin_path, json) do
    temp_path =
      Path.join(
        System.tmp_dir!(),
        "metastatic_cure_ast_#{System.unique_integer([:positive, :monotonic])}.json"
      )

    File.write!(temp_path, json)

    try do
      case System.cmd(bin_path, ["--unparse", temp_path], stderr_to_stdout: true) do
        {output, 0} -> decode_source(output)
        {output, _code} -> {:error, output}
      end
    after
      File.rm(temp_path)
    end
  end

  defp run_cure_cli_unparse(cli_path, json) do
    temp_path =
      Path.join(
        System.tmp_dir!(),
        "metastatic_cure_ast_#{System.unique_integer([:positive, :monotonic])}.json"
      )

    File.write!(temp_path, json)

    try do
      case System.cmd(cli_path, ["unparse", "--json", temp_path], stderr_to_stdout: true) do
        {output, 0} -> decode_source(output)
        {output, _code} -> {:error, output}
      end
    after
      File.rm(temp_path)
    end
  end

  defp decode_ast(json_str) do
    case Jason.decode(json_str) do
      {:ok, %{"ok" => true, "ast" => ast}} -> {:ok, ast}
      {:ok, %{"ok" => false, "error" => err}} -> {:error, inspect(err)}
      {:ok, ast} -> {:ok, ast}
      {:error, reason} -> {:error, "JSON decode failed: #{inspect(reason)}"}
    end
  end

  defp decode_source(json_str) do
    case Jason.decode(json_str) do
      {:ok, %{"ok" => true, "source" => source}} -> {:ok, source}
      {:ok, %{"ok" => false, "error" => err}} -> {:error, inspect(err)}
      {:ok, source} when is_binary(source) -> {:ok, source}
      {:error, _} -> {:ok, String.trim(json_str)}
    end
  end
end
