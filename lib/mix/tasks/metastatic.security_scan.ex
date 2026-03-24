defmodule Mix.Tasks.Metastatic.SecurityScan do
  @shortdoc "Scans for security vulnerabilities"

  @moduledoc """
  Scans source code for security vulnerabilities using pattern-based detection.

  ## Usage

      mix metastatic.security_scan FILE [options]

  ## Options

    * `--format` - Output format: text (default) or json
    * `--language` - Source language: python, elixir, erlang, ruby, or haskell (auto-detected if not specified)

  ## Examples

      # Scan for security issues
      mix metastatic.security_scan my_file.py

      # JSON output with CWE details
      mix metastatic.security_scan my_file.ex --format json

  ## Vulnerability Categories

    * Dangerous functions (eval, exec, pickle.loads)
    * Hardcoded secrets (passwords, API keys, tokens) - CWE-798
    * Weak cryptography (MD5, SHA1, DES)
    * Insecure protocols (HTTP for sensitive data)
    * SQL injection patterns - CWE-89
    * Command injection patterns - CWE-78

  ## Severity Levels

  Critical, High, Medium, Low

  ## Exit Codes

    * 0 - No vulnerabilities found
    * 1 - Vulnerabilities detected
    * 2 - Error during analysis
  """

  use Mix.Task
  @dialyzer {:no_return, run: 1}

  alias Metastatic.Analysis.Security
  alias Metastatic.Builder

  @impl Mix.Task
  def run(args) do
    {opts, files, _} = OptionParser.parse(args, strict: [format: :string, language: :string])

    case files do
      [] ->
        Mix.shell().error("Usage: mix metastatic.security_scan FILE")
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
        {:ok, result} = Security.analyze(doc)

        output =
          if format == "json",
            do: Jason.encode!(Security.Result.to_map(result), pretty: true),
            else: result.summary

        Mix.shell().info(output)
        exit({:shutdown, if(result.has_vulnerabilities?, do: 1, else: 0)})

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
