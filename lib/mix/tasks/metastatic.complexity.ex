defmodule Mix.Tasks.Metastatic.Complexity do
  @moduledoc """
  Analyzes code complexity for a given file.

  ## Usage

      mix metastatic.complexity FILE [options]

  ## Options

    * `--format` - Output format: text (default), json, or detailed
    * `--language` - Source language: python, elixir, or erlang (auto-detected if not specified)
    * `--max-cyclomatic` - Cyclomatic complexity threshold (default: 10)
    * `--max-cognitive` - Cognitive complexity threshold (default: 15)
    * `--max-nesting` - Nesting depth threshold (default: 3)

  ## Examples

      # Basic complexity analysis
      mix metastatic.complexity my_file.py

      # JSON output
      mix metastatic.complexity my_file.py --format json

      # Detailed report
      mix metastatic.complexity my_file.ex --format detailed

      # Custom thresholds
      mix metastatic.complexity my_file.erl --max-cyclomatic 15 --max-cognitive 20

  ## Exit Codes

    * 0 - All metrics within thresholds
    * 1 - Warnings (exceeded thresholds)
    * 2 - Error during analysis
  """

  @shortdoc "Analyzes code complexity"

  use Mix.Task

  alias Metastatic.Analysis.Complexity
  alias Metastatic.Analysis.Complexity.Formatter
  alias Metastatic.Builder

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, files, _invalid} =
      OptionParser.parse(args,
        strict: [
          format: :string,
          language: :string,
          max_cyclomatic: :integer,
          max_cognitive: :integer,
          max_nesting: :integer
        ],
        aliases: [f: :format, l: :language]
      )

    format = parse_format(opts[:format])
    language = parse_language(opts[:language])
    thresholds = build_thresholds(opts)

    case files do
      [] ->
        Mix.shell().error("Error: No file specified")
        Mix.shell().info("Usage: mix metastatic.complexity FILE [options]")
        exit({:shutdown, 2})

      [file | _] ->
        analyze_file(file, language, format, thresholds)
    end
  end

  defp analyze_file(file, language, format, thresholds) do
    unless File.exists?(file) do
      Mix.shell().error("Error: File not found: #{file}")
      exit({:shutdown, 2})
    end

    source = File.read!(file)
    lang = language || detect_language(file)

    case Builder.from_source(source, lang) do
      {:ok, document} ->
        # Check if this is a module-level analysis
        if is_module_file?(document) do
          Mix.shell().info("Note: Analyzing entire module (includes all nested functions).\n")
        end

        case Complexity.analyze(document, thresholds: thresholds) do
          {:ok, result} ->
            output = Formatter.format(result, format)
            Mix.shell().info(output)

            # Exit with appropriate code
            exit_code = if Enum.empty?(result.warnings), do: 0, else: 1

            exit({:shutdown, exit_code})

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

  defp build_thresholds(opts) do
    thresholds = %{}

    thresholds =
      if max_cyc = opts[:max_cyclomatic] do
        Map.put(thresholds, :cyclomatic_warning, max_cyc)
      else
        thresholds
      end

    thresholds =
      if max_cog = opts[:max_cognitive] do
        Map.put(thresholds, :cognitive_warning, max_cog)
      else
        thresholds
      end

    thresholds =
      if max_nest = opts[:max_nesting] do
        Map.put(thresholds, :nesting_warning, max_nest)
      else
        thresholds
      end

    thresholds
  end

  defp is_module_file?(%{ast: {:language_specific, _, _, :module_definition}}), do: true
  defp is_module_file?(_), do: false
end
