defmodule Metastatic.Adapters.Cure.Subprocess do
  @moduledoc """
  Subprocess management for the Cure parser and unparser fallback.

  Handles communication with an external Cure CLI or parser binary when the
  in-process Cure compiler modules are unavailable.

  Temp-file handling is delegated to `Metastatic.Subprocess`.
  """

  alias Metastatic.{Priv, Subprocess}

  @parser_bin "parsers/cure/bin/parser.exe"

  @doc """
  Parse Cure source code to AST using an external subprocess binary or the
  `cure` CLI executable.
  """
  @spec parse(String.t(), keyword()) :: {:ok, term()} | {:error, String.t()}
  def parse(source, opts \\ []) when is_binary(source) and is_list(opts) do
    with {:ok, {executable, args}} <- resolve(opts),
         {:ok, output} <- run(executable, args, source, ".cure") do
      decode_ast(output)
    end
  end

  @doc """
  Unparse Cure AST back to source code using an external subprocess binary or
  the `cure` CLI executable.
  """
  @spec unparse(term(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def unparse(ast, opts \\ []) when is_list(opts) do
    with {:ok, json} <- encode(ast),
         {:ok, {executable, args}} <- resolve(opts),
         {:ok, output} <- run(executable, args, json, ".json") do
      decode_source(output)
    end
  end

  # Helpers

  defp encode(ast) do
    {:ok, Jason.encode!(ast)}
  rescue
    error -> {:error, "JSON encode failed: #{Exception.message(error)}"}
  end

  defp resolve(opts) do
    bin_full_path = Keyword.get_lazy(opts, :parser_bin, fn -> Priv.parser_path(@parser_bin) end)
    cure_cli = Keyword.get_lazy(opts, :cure_cli, fn -> Priv.find_executable("cure") end)

    cond do
      bin_full_path != nil and File.exists?(bin_full_path) ->
        {:ok, {bin_full_path, []}}

      cure_cli != nil and File.exists?(cure_cli) ->
        {:ok, {cure_cli, ["parse", "--json"]}}

      true ->
        {:error,
         "Cure subprocess parser unavailable: no compiled parser at #{inspect(bin_full_path)} " <>
           "and no `cure` executable on PATH"}
    end
  end

  defp run(executable, args, input, ext) do
    Subprocess.run(executable, args, input, ext: ext, prefix: "metastatic_cure")
  end

  defp decode_ast(json_str) do
    case Jason.decode(json_str) do
      {:ok, %{"ok" => true, "ast" => ast}} -> {:ok, ast}
      {:ok, %{"ok" => false, "error" => err}} -> {:error, Subprocess.format_error(err)}
      {:ok, ast} -> {:ok, ast}
      {:error, reason} -> {:error, "JSON decode failed: #{inspect(reason)}"}
    end
  end

  defp decode_source(json_str) do
    case Jason.decode(json_str) do
      {:ok, %{"ok" => true, "source" => source}} -> {:ok, source}
      {:ok, %{"ok" => false, "error" => err}} -> {:error, Subprocess.format_error(err)}
      {:ok, source} when is_binary(source) -> {:ok, source}
      {:error, _} -> {:ok, String.trim(json_str)}
    end
  end
end
