defmodule Mix.Tasks.Metastatic.ControlFlow do
  @shortdoc "Generates control flow graph"

  @moduledoc """
  Generates a control flow graph (CFG) for a given source file.

  ## Usage

      mix metastatic.control_flow FILE [options]

  ## Options

    * `--format` - Output format: json (default), dot, or d3
    * `--language` - Source language: python, elixir, erlang, ruby, or haskell (auto-detected if not specified)
    * `--output` - Write output to file instead of stdout

  ## Examples

      # Generate CFG in DOT format (for Graphviz)
      mix metastatic.control_flow my_file.py --format dot

      # Generate D3.js JSON for interactive visualization
      mix metastatic.control_flow my_file.ex --format d3 --output cfg.json

      # JSON output (default)
      mix metastatic.control_flow my_file.rb

  ## Output Formats

    * `json` - Full CFG as JSON map (default)
    * `dot` - DOT format for Graphviz rendering
    * `d3` - D3.js JSON for web visualization

  ## Exit Codes

    * 0 - Success
    * 2 - Error during analysis
  """

  use Mix.Task
  @dialyzer {:no_return, run: 1}

  alias Metastatic.Analysis.ControlFlow
  alias Metastatic.Builder

  @impl Mix.Task
  def run(args) do
    {opts, files, _} =
      OptionParser.parse(args, strict: [format: :string, language: :string, output: :string])

    case files do
      [] ->
        Mix.shell().error("Usage: mix metastatic.control_flow FILE [--format dot|d3|json]")
        exit({:shutdown, 2})

      [file | _] ->
        analyze(file, opts)
    end
  end

  defp analyze(file, opts) do
    unless File.exists?(file),
      do:
        (
          Mix.shell().error("File not found")
          exit({:shutdown, 2})
        )

    source = File.read!(file)
    lang = opts[:language] || detect_lang(file)
    format = opts[:format] || "json"

    case Builder.from_source(source, String.to_atom(lang)) do
      {:ok, doc} ->
        {:ok, result} = ControlFlow.analyze(doc)

        output =
          case format do
            "dot" -> ControlFlow.Result.to_dot(result)
            "d3" -> Jason.encode!(ControlFlow.Result.to_d3_json(result), pretty: true)
            _ -> Jason.encode!(ControlFlow.Result.to_map(result), pretty: true)
          end

        if opts[:output] do
          File.write!(opts[:output], output)
          Mix.shell().info("CFG written to #{opts[:output]}")
        else
          Mix.shell().info(output)
        end

        exit({:shutdown, 0})

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
