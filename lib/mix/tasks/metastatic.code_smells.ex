defmodule Mix.Tasks.Metastatic.CodeSmells do
  @shortdoc "Detects code smells"

  @moduledoc """
  Detects code smells in a given source file.

  ## Usage

      mix metastatic.code_smells FILE [options]

  ## Options

    * `--format` - Output format: text (default) or json
    * `--language` - Source language: python, elixir, erlang, ruby, or haskell (auto-detected if not specified)

  ## Examples

      # Basic code smell detection
      mix metastatic.code_smells my_file.py

      # JSON output
      mix metastatic.code_smells my_file.ex --format json

      # Explicit language
      mix metastatic.code_smells my_file.rb --language ruby

  ## Detected Smells

    * Long functions (>20 statements)
    * Deep nesting (>4 levels)
    * High cyclomatic complexity (>10)
    * High cognitive complexity (>15)
    * Magic numbers (unexplained literals)
    * Complex conditionals (>3 boolean operators)

  ## Exit Codes

    * 0 - No smells detected
    * 1 - Code smells found
    * 2 - Error during analysis
  """

  use Mix.Task
  @dialyzer {:no_return, run: 1}

  alias Metastatic.Analysis.Smells
  alias Metastatic.Builder

  @impl Mix.Task
  def run(args) do
    {opts, files, _} = OptionParser.parse(args, strict: [format: :string, language: :string])

    case files do
      [] ->
        Mix.shell().error("Usage: mix metastatic.code_smells FILE")
        exit({:shutdown, 2})

      [file | _] ->
        analyze(file, opts[:language], opts[:format] || "text")
    end
  end

  defp analyze(file, language, format) do
    unless File.exists?(file),
      do:
        (
          Mix.shell().error("File not found")
          exit({:shutdown, 2})
        )

    source = File.read!(file)
    lang = language || detect_lang(file)

    case Builder.from_source(source, String.to_atom(lang)) do
      {:ok, doc} ->
        {:ok, result} = Smells.analyze(doc)

        output =
          if format == "json",
            do: Jason.encode!(Smells.Result.to_map(result), pretty: true),
            else: result.summary

        Mix.shell().info(output)
        exit({:shutdown, if(result.has_smells?, do: 1, else: 0)})

      {:error, reason} ->
        Mix.shell().error("Parse error: #{inspect(reason)}")
        exit({:shutdown, 2})
    end
  end

  defp detect_lang(file) do
    case Path.extname(file) do
      ".py" ->
        "python"

      ".ex" ->
        "elixir"

      ".exs" ->
        "elixir"

      ".erl" ->
        "erlang"

      ".rb" ->
        "ruby"

      ".hs" ->
        "haskell"

      _ ->
        Mix.shell().error("Cannot detect language")
        exit({:shutdown, 2})
    end
  end
end
