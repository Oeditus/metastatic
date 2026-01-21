defmodule Mix.Tasks.Metastatic.PurityCheck do
  @moduledoc """
  Analyzes code purity for a given file.

  ## Usage

      mix metastatic.purity_check FILE [options]

  ## Options

    * `--format` - Output format: text (default), json, or detailed
    * `--language` - Source language: python, elixir, or erlang (auto-detected if not specified)

  ## Examples

      # Basic purity check
      mix metastatic.purity_check my_file.py

      # JSON output
      mix metastatic.purity_check my_file.py --format json

      # Detailed report
      mix metastatic.purity_check my_file.ex --format detailed

  ## Exit Codes

    * 0 - Pure (no side effects)
    * 1 - Impure (has side effects)
    * 2 - Error during analysis
  """

  @shortdoc "Analyzes code purity"

  use Mix.Task

  alias Metastatic.Analysis.Purity
  alias Metastatic.Analysis.Purity.Formatter
  alias Metastatic.Builder

  @impl Mix.Task
  def run(args) do
    {opts, files, _invalid} =
      OptionParser.parse(args,
        strict: [format: :string, language: :string],
        aliases: [f: :format, l: :language]
      )

    format = parse_format(opts[:format])
    language = parse_language(opts[:language])

    case files do
      [] ->
        Mix.shell().error("Error: No file specified")
        Mix.shell().info("Usage: mix metastatic.purity_check FILE [options]")
        exit({:shutdown, 2})

      [file | _] ->
        analyze_file(file, language, format)
    end
  end

  defp analyze_file(file, language, format) do
    unless File.exists?(file) do
      Mix.shell().error("Error: File not found: #{file}")
      exit({:shutdown, 2})
    end

    source = File.read!(file)
    lang = language || detect_language(file)

    case Builder.from_source(source, lang) do
      {:ok, document} ->
        case Purity.analyze(document) do
          {:ok, result} ->
            output = Formatter.format(result, format)
            Mix.shell().info(output)

            # Exit with appropriate code
            if result.pure? do
              exit({:shutdown, 0})
            else
              exit({:shutdown, 1})
            end

            # {:error, reason} ->
            #   Mix.shell().error("Analysis error: #{inspect(reason)}")
            #   exit({:shutdown, 2})
        end

      {:error, reason} ->
        Mix.shell().error("Parse error: #{inspect(reason)}")
        exit({:shutdown, 2})
    end
  end

  defp parse_format(nil), do: :text
  defp parse_format("text"), do: :text
  defp parse_format("json"), do: :json
  defp parse_format("detailed"), do: :detailed

  defp parse_format(other) do
    Mix.shell().error("Unknown format: #{other}")
    Mix.shell().info("Valid formats: text, json, detailed")
    exit({:shutdown, 2})
  end

  defp parse_language(nil), do: nil
  defp parse_language("python"), do: :python
  defp parse_language("elixir"), do: :elixir
  defp parse_language("erlang"), do: :erlang

  defp parse_language(other) do
    Mix.shell().error("Unknown language: #{other}")
    Mix.shell().info("Valid languages: python, elixir, erlang")
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

      other ->
        Mix.shell().error("Cannot detect language from extension: #{other}")
        Mix.shell().info("Please specify --language option")
        exit({:shutdown, 2})
    end
  end
end
