defmodule Metastatic.Adapters.Ruby.Subprocess do
  @moduledoc """
  Subprocess management for Ruby parser and unparser.

  Handles communication with Ruby scripts via temporary files with JSON
  serialization. Temp-file handling and exit-code reporting are delegated to
  `Metastatic.Subprocess`.
  """

  @behaviour Metastatic.Adapter.Bridge

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
      {:error, "SyntaxError at line 1: ..."}
  """
  @impl true
  @spec parse(String.t()) :: {:ok, map()} | {:error, String.t()}
  def parse(source) do
    with :ok <- check_available(),
         {:ok, result} <- run_ruby_script(@parser_path, source, ".rb") do
      Bridge.decode(result)
    end
  end

  @doc """
  Unparse AST JSON back to Ruby source code.

  ## Examples

      iex> ast = %{"type" => "lvasgn", "children" => [...]}
      iex> Metastatic.Adapters.Ruby.Subprocess.unparse(ast)
      {:ok, "x = 42"}
  """
  @impl true
  @spec unparse(map()) :: {:ok, String.t()} | {:error, String.t()}
  def unparse(ast) do
    with {:ok, json} <- Bridge.encode(ast),
         :ok <- check_available(),
         {:ok, result} <- run_ruby_script(@unparser_path, json, ".json"),
         {:ok, source} <- Bridge.decode(result) do
      {:ok, String.trim(source)}
    end
  end

  @doc """
  Returns `true` when the Ruby parser script and runtime are available.
  """
  @spec available?() :: boolean()
  def available?, do: check_available() == :ok

  # Private Functions

  defp check_available do
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
