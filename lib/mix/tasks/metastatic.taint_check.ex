defmodule Mix.Tasks.Metastatic.TaintCheck do
  @shortdoc "Performs taint analysis"

  @moduledoc """
  Performs taint analysis to track data flow from untrusted sources to sensitive
  operations.

  ## Usage

      mix metastatic.taint_check FILE [options]

  ## Options

    * `--format` - Output format: text (default) or json
    * `--language` - Source language: python, elixir, erlang, ruby, or haskell (auto-detected if not specified)

  ## Examples

      # Check for taint vulnerabilities
      mix metastatic.taint_check my_file.py

      # JSON output
      mix metastatic.taint_check my_file.ex --format json

  ## Detected Vulnerabilities

    * Code injection (eval, exec with untrusted input)
    * Command injection (system, shell commands with user data)
    * SQL injection patterns
    * Path traversal vulnerabilities

  ## Exit Codes

    * 0 - No taint flows detected
    * 1 - Taint vulnerabilities found
    * 2 - Error during analysis
  """

  use Mix.Task
  @dialyzer {:no_return, run: 1}

  alias Metastatic.Analysis.Taint
  alias Metastatic.Builder

  @impl Mix.Task
  def run(args) do
    {opts, files, _} = OptionParser.parse(args, strict: [format: :string, language: :string])

    case files do
      [] ->
        Mix.shell().error("Usage: mix metastatic.taint_check FILE")
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
        {:ok, result} = Taint.analyze(doc)

        output =
          if format == "json",
            do: Jason.encode!(Taint.Result.to_map(result), pretty: true),
            else: result.summary

        Mix.shell().info(output)
        exit({:shutdown, if(result.has_taint_flows?, do: 1, else: 0)})

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
