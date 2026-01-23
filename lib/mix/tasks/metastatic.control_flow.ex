defmodule Mix.Tasks.Metastatic.ControlFlow do
  @shortdoc "Generates control flow graph"
  use Mix.Task

  alias Metastatic.Analysis.ControlFlow
  alias Metastatic.Builder

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
