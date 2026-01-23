defmodule Mix.Tasks.Metastatic.UnusedVars do
  @moduledoc """
  Detects unused variables in a given file.

  ## Usage

      mix metastatic.unused_vars FILE [options]

  ## Options

    * `--format` - Output format: text (default), json, or detailed
    * `--language` - Source language (auto-detected if not specified)
    * `--ignore-underscore` - Ignore variables starting with underscore (default: true)

  ## Examples

      mix metastatic.unused_vars my_file.py
      mix metastatic.unused_vars my_file.ex --format json

  ## Exit Codes

    * 0 - No unused variables
    * 1 - Unused variables detected
    * 2 - Error during analysis
  """

  @shortdoc "Detects unused variables"

  use Mix.Task

  alias Metastatic.Analysis.UnusedVariables
  alias Metastatic.Builder

  @impl Mix.Task
  def run(args) do
    {opts, files, _invalid} =
      OptionParser.parse(args,
        strict: [format: :string, language: :string, ignore_underscore: :boolean],
        aliases: [f: :format, l: :language]
      )

    format = parse_format(opts[:format])
    language = parse_language(opts[:language])
    ignore_underscore = Keyword.get(opts, :ignore_underscore, true)

    case files do
      [] ->
        Mix.shell().error("Error: No file specified")
        Mix.shell().info("Usage: mix metastatic.unused_vars FILE [options]")
        exit({:shutdown, 2})

      [file | _] ->
        analyze_file(file, language, format, ignore_underscore)
    end
  end

  defp analyze_file(file, language, format, ignore_underscore) do
    unless File.exists?(file) do
      Mix.shell().error("Error: File not found: #{file}")
      exit({:shutdown, 2})
    end

    source = File.read!(file)
    lang = language || detect_language(file)

    case Builder.from_source(source, lang) do
      {:ok, document} ->
        case UnusedVariables.analyze(document, ignore_underscore: ignore_underscore) do
          {:ok, result} ->
            output = format_output(result, format)
            Mix.shell().info(output)

            if result.has_unused? do
              exit({:shutdown, 1})
            else
              exit({:shutdown, 0})
            end
        end

      {:error, reason} ->
        Mix.shell().error("Parse error: #{inspect(reason)}")
        exit({:shutdown, 2})
    end
  end

  defp format_output(result, :json) do
    Jason.encode!(UnusedVariables.Result.to_map(result), pretty: true)
  end

  defp format_output(result, :detailed) do
    summary = result.summary <> "\n\n"

    details =
      Enum.map_join(result.unused_variables, "\n", fn var ->
        """
        Variable: #{var.name}
        Category: #{var.category}
        Suggestion: #{var.suggestion}
        ---
        """
      end)

    summary <> details
  end

  defp format_output(result, :text) do
    result.summary
  end

  defp parse_format(nil), do: :text
  defp parse_format("text"), do: :text
  defp parse_format("json"), do: :json
  defp parse_format("detailed"), do: :detailed

  defp parse_format(other) do
    Mix.shell().error("Unknown format: #{other}")
    exit({:shutdown, 2})
  end

  defp parse_language(nil), do: nil
  defp parse_language("python"), do: :python
  defp parse_language("elixir"), do: :elixir
  defp parse_language("erlang"), do: :erlang
  defp parse_language("ruby"), do: :ruby
  defp parse_language("haskell"), do: :haskell

  defp parse_language(other) do
    Mix.shell().error("Unknown language: #{other}")
    exit({:shutdown, 2})
  end

  defp detect_language(file) do
    case Path.extname(file) do
      ".py" ->
        :python

      ".ex" ->
        :elixir

      ".exs" ->
        :elixir

      ".erl" ->
        :erlang

      ".hrl" ->
        :erlang

      ".rb" ->
        :ruby

      ".hs" ->
        :haskell

      other ->
        Mix.shell().error("Cannot detect language from extension: #{other}")
        exit({:shutdown, 2})
    end
  end
end
