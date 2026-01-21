defmodule Mix.Tasks.Metastatic.Inspect do
  @shortdoc "Inspect MetaAST structure of source code"

  @moduledoc """
  Inspect the MetaAST structure of source code files.

  ## Usage

      mix metastatic.inspect FILE [OPTIONS]

  ## Arguments

  - `FILE` - Source file to inspect

  ## Options

  - `--format FORMAT` - Output format (tree, json, plain) [default: tree]
  - `--layer LAYER` - Filter by layer (core, extended, native, all) [default: all]
  - `--variables` - Show only variables
  - `--language LANG` - Source language (optional, auto-detected from extension)

  ## Examples

  Inspect a Python file (tree format):

      mix metastatic.inspect hello.py

  Show MetaAST in JSON format:

      mix metastatic.inspect hello.py --format json

  Filter to show only core layer nodes:

      mix metastatic.inspect hello.py --layer core

  Extract only variables:

      mix metastatic.inspect hello.py --variables

  ## Output Formats

  - **tree** (default) - Human-readable tree structure with indentation
  - **json** - Machine-readable JSON for programmatic processing
  - **plain** - Simple text representation

  ## Layer Filtering

  - **core** - Universal constructs (literals, variables, operators, etc.)
  - **extended** - Common patterns (loops, lambdas, collections)
  - **native** - Language-specific constructs
  - **all** - Show everything (default)
  """

  use Mix.Task

  alias Metastatic.{Builder, CLI}
  alias Metastatic.CLI.{Formatter, Inspector}

  @switches [
    format: :string,
    layer: :string,
    variables: :boolean,
    language: :string
  ]

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, paths, _invalid} = OptionParser.parse(args, strict: @switches)

    case validate_args(opts, paths) do
      {:ok, file_path, options} ->
        inspect_file(file_path, options)

      {:error, message} ->
        CLI.fatal(message)
    end
  end

  # Validation

  @spec validate_args(keyword(), [String.t()]) ::
          {:ok, String.t(), keyword()} | {:error, String.t()}
  defp validate_args(opts, paths) do
    with {:ok, file_path} <- validate_file_path(paths),
         {:ok, language} <- validate_language(opts, file_path),
         {:ok, format} <- validate_format(opts),
         {:ok, layer} <- validate_layer(opts) do
      options = [
        language: language,
        format: format,
        layer: layer,
        variables_only: Keyword.get(opts, :variables, false)
      ]

      {:ok, file_path, options}
    end
  end

  @spec validate_file_path([String.t()]) :: {:ok, String.t()} | {:error, String.t()}
  defp validate_file_path([]), do: {:error, "No source file provided"}

  defp validate_file_path([path | _]) do
    if File.exists?(path) && !File.dir?(path) do
      {:ok, path}
    else
      {:error, "File does not exist or is a directory: #{path}"}
    end
  end

  @spec validate_language(keyword(), String.t()) :: {:ok, atom()} | {:error, String.t()}
  defp validate_language(opts, file_path) do
    case Keyword.get(opts, :language) do
      nil ->
        case CLI.detect_language(file_path) do
          {:ok, lang} -> {:ok, lang}
          {:error, _} -> {:error, "Cannot detect language. Use --language option"}
        end

      lang_str ->
        case String.downcase(lang_str) do
          "python" -> {:ok, :python}
          "elixir" -> {:ok, :elixir}
          "erlang" -> {:ok, :erlang}
          _ -> {:error, "Invalid language: #{lang_str}. Supported: python, elixir, erlang"}
        end
    end
  end

  @spec validate_format(keyword()) :: {:ok, atom()} | {:error, String.t()}
  defp validate_format(opts) do
    case Keyword.get(opts, :format, "tree") do
      "tree" -> {:ok, :tree}
      "json" -> {:ok, :json}
      "plain" -> {:ok, :plain}
      invalid -> {:error, "Invalid format: #{invalid}. Supported: tree, json, plain"}
    end
  end

  @spec validate_layer(keyword()) :: {:ok, atom()} | {:error, String.t()}
  defp validate_layer(opts) do
    case Keyword.get(opts, :layer, "all") do
      "all" -> {:ok, :all}
      "core" -> {:ok, :core}
      "extended" -> {:ok, :extended}
      "native" -> {:ok, :native}
      invalid -> {:error, "Invalid layer: #{invalid}. Supported: all, core, extended, native"}
    end
  end

  # Inspection

  @spec inspect_file(String.t(), keyword()) :: no_return()
  defp inspect_file(file_path, options) do
    language = Keyword.fetch!(options, :language)
    format = Keyword.fetch!(options, :format)
    layer = Keyword.fetch!(options, :layer)
    variables_only = Keyword.fetch!(options, :variables_only)

    with {:ok, source} <- CLI.read_file(file_path),
         {:ok, doc} <- Builder.from_source(source, language) do
      if variables_only do
        show_variables(doc)
      else
        show_ast(doc, format, layer)
      end

      exit({:shutdown, 0})
    else
      {:error, reason} ->
        CLI.fatal("Failed to inspect file: #{inspect(reason)}")
    end
  end

  @spec show_variables(Metastatic.Document.t()) :: :ok
  defp show_variables(doc) do
    {:ok, variables} = Inspector.extract_variables(doc)

    if MapSet.size(variables) == 0 do
      Mix.shell().info("No variables found")
    else
      Mix.shell().info("Variables:")

      variables
      |> Enum.sort()
      |> Enum.each(fn var ->
        Mix.shell().info("  #{var}")
      end)
    end
  end

  @spec show_ast(Metastatic.Document.t(), atom(), atom()) :: :ok
  defp show_ast(doc, format, layer) do
    {:ok, result} = Inspector.inspect_document(doc, layer: layer)

    Mix.shell().info(CLI.format_info("Language: #{doc.language}"))
    Mix.shell().info(CLI.format_info("Layer: #{result.layer}"))
    Mix.shell().info(CLI.format_info("Depth: #{result.depth}"))
    Mix.shell().info(CLI.format_info("Nodes: #{result.node_count}"))
    Mix.shell().info(CLI.format_info("Variables: #{MapSet.size(result.variables)}"))
    Mix.shell().info("")

    if layer != :all do
      Mix.shell().info("Filtered AST (#{layer} layer):")
    else
      Mix.shell().info("MetaAST:")
    end

    output = Formatter.format(result.ast, format)
    Mix.shell().info(output)
  end
end
