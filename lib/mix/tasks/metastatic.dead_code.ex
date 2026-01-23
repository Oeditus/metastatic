defmodule Mix.Tasks.Metastatic.DeadCode do
  @moduledoc """
  Detects dead code in a given file.

  ## Usage

      mix metastatic.dead_code FILE [options]

  ## Options

    * `--format` - Output format: text (default), json, or detailed
    * `--language` - Source language (auto-detected if not specified)
    * `--min-confidence` - Minimum confidence level: low (default), medium, or high

  ## Examples

      # Basic dead code check
      mix metastatic.dead_code my_file.py

      # JSON output
      mix metastatic.dead_code my_file.py --format json

      # Only high confidence results
      mix metastatic.dead_code my_file.ex --min-confidence high

  ## Exit Codes

    * 0 - No dead code found
    * 1 - Dead code detected
    * 2 - Error during analysis
  """

  @shortdoc "Detects dead code"

  use Mix.Task

  alias Metastatic.Analysis.DeadCode
  alias Metastatic.Builder

  @impl Mix.Task
  def run(args) do
    {opts, files, _invalid} =
      OptionParser.parse(args,
        strict: [format: :string, language: :string, min_confidence: :string],
        aliases: [f: :format, l: :language]
      )

    format = parse_format(opts[:format])
    language = parse_language(opts[:language])
    min_confidence = parse_confidence(opts[:min_confidence])

    case files do
      [] ->
        Mix.shell().error("Error: No file specified")
        Mix.shell().info("Usage: mix metastatic.dead_code FILE [options]")
        exit({:shutdown, 2})

      [file | _] ->
        analyze_file(file, language, format, min_confidence)
    end
  end

  defp analyze_file(file, language, format, min_confidence) do
    unless File.exists?(file) do
      Mix.shell().error("Error: File not found: #{file}")
      exit({:shutdown, 2})
    end

    source = File.read!(file)
    lang = language || detect_language(file)

    case Builder.from_source(source, lang) do
      {:ok, document} ->
        case DeadCode.analyze(document, min_confidence: min_confidence) do
          {:ok, result} ->
            output = format_output(result, format)
            Mix.shell().info(output)

            if result.has_dead_code? do
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
    Jason.encode!(DeadCode.Result.to_map(result), pretty: true)
  end

  defp format_output(result, :detailed) do
    summary = result.summary <> "\n\n"

    details =
      result.dead_locations
      |> Enum.map(fn loc ->
        """
        Type: #{loc.type}
        Confidence: #{loc.confidence}
        Reason: #{loc.reason}
        Suggestion: #{loc.suggestion}
        ---
        """
      end)
      |> Enum.join("\n")

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
    Mix.shell().info("Valid formats: text, json, detailed")
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
    Mix.shell().info("Valid languages: python, elixir, erlang, ruby, haskell")
    exit({:shutdown, 2})
  end

  defp parse_confidence(nil), do: :low
  defp parse_confidence("low"), do: :low
  defp parse_confidence("medium"), do: :medium
  defp parse_confidence("high"), do: :high

  defp parse_confidence(other) do
    Mix.shell().error("Unknown confidence level: #{other}")
    Mix.shell().info("Valid levels: low, medium, high")
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
        Mix.shell().info("Please specify --language option")
        exit({:shutdown, 2})
    end
  end
end
