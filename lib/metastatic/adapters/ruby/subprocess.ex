defmodule Metastatic.Adapters.Ruby.Subprocess do
  @moduledoc """
  Subprocess management for Ruby parser and unparser.

  Handles communication with Ruby scripts via temporary files with JSON
  serialization. Temp-file handling and exit-code reporting are delegated to
  `Metastatic.Subprocess`.
  """

  alias Metastatic.Adapter.Bridge
  alias Metastatic.{Priv, Subprocess}

  @parser_path "parsers/ruby/parser.rb"
  @unparser_path "parsers/ruby/unparser.rb"

  @doc """
  Parse Ruby source code to AST JSON.

  ## Examples

      iex> Metastatic.Adapters.Ruby.Subprocess.parse("x = 42")
      {:ok, %{"type" => "lvasgn", "children" => [...]}}

      iex> Metastatic.Adapters.Ruby.Subprocess.parse("x = ")
      {:error, "Parse error: ..."}
  """
  @spec parse(String.t()) :: {:ok, map()} | {:error, String.t()}
  def parse(source) do
    with :ok <- available?(),
         {:ok, result} <- run_ruby_script(@parser_path, source, ".rb") do
      decode_parse(result)
    end
  end

  # The Ruby bridge reports a *syntax error* as `{"status": "ok", "ast": null}`
  # rather than an error envelope, so that shape is translated here before
  # `Bridge.decode/1` sees it. Every other shape (including the legacy
  # `status` envelope) is handled by the shared decoder.
  defp decode_parse(result) do
    case Jason.decode(result) do
      {:ok, %{"status" => "ok", "ast" => nil}} -> {:error, "Parse error: syntax error"}
      _ -> Bridge.decode(result)
    end
  end

  @doc """
  Unparse AST JSON back to Ruby source code.

  ## Examples

      iex> ast = %{"type" => "lvasgn", "children" => [...]}
      iex> Metastatic.Adapters.Ruby.Subprocess.unparse(ast)
      {:ok, "x = 42"}
  """
  @spec unparse(map()) :: {:ok, String.t()} | {:error, String.t()}
  def unparse(ast) do
    # The Ruby unparser expects the AST *wrapped* as `{"ast": ...}`, unlike
    # the other bridges which take the bare AST. `Bridge.encode/1` encodes the
    # value as given, so the wrapper is applied here.
    with {:ok, json} <- Bridge.encode(%{ast: ast}),
         :ok <- available?(),
         {:ok, result} <- run_ruby_script(@unparser_path, json, ".json") do
      # The unparser emits source directly, not JSON.
      {:ok, String.trim(result)}
    end
  end

  # Private Functions

  defp available? do
    cond do
      not File.exists?(Priv.parser_path(@parser_path)) ->
        {:error, "Ruby parser unavailable: #{@parser_path} is missing from the package"}

      ruby_bin() == nil and Priv.find_executable("bundle") == nil ->
        {:error, "Ruby parser unavailable: no `ruby` or `bundle` executable found"}

      true ->
        :ok
    end
  end

  defp ruby_bin, do: Priv.find_executable("ruby")

  defp run_ruby_script(script_path, input, ext) do
    script_full_path = Priv.parser_path(script_path)
    script_dir = Path.dirname(script_full_path)

    case Subprocess.run(ruby_bin(), [script_full_path], input,
           ext: ext,
           prefix: "metastatic_rb",
           cd: script_dir
         ) do
      {:ok, result} ->
        {:ok, filter_warnings(result)}

      {:error, reason} ->
        # `bundle exec` is the fallback when the parser gem is only available
        # through a Gemfile.
        if Priv.find_executable("bundle") != nil and String.contains?(reason, "LoadError") do
          run_bundle_exec(script_path, input, ext)
        else
          {:error, reason}
        end
    end
  end

  defp run_bundle_exec(script_path, input, ext) do
    script_full_path = Priv.parser_path(script_path)
    script_dir = Path.dirname(script_full_path)

    case Subprocess.run(
           Priv.find_executable("bundle"),
           ["exec", "ruby", Path.basename(script_full_path)],
           input,
           ext: ext,
           prefix: "metastatic_rb",
           cd: script_dir
         ) do
      {:ok, output} -> {:ok, filter_warnings(output)}
      {:error, _} = error -> error
    end
  end

  defp filter_warnings(output) do
    output
    |> String.split("\n")
    |> Enum.reject(fn line ->
      String.contains?(line, "parser/current is loading") or
        String.contains?(line, "Please see https://github.com/whitequark/parser")
    end)
    |> Enum.join("\n")
  end
end
