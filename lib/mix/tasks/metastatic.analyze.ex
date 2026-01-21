defmodule Mix.Tasks.Metastatic.Analyze do
  @shortdoc "Analyze MetaAST metrics and validate conformance"

  @moduledoc """
  Analyze MetaAST structure and provide detailed metrics.

  ## Usage

      mix metastatic.analyze FILE [OPTIONS]

  ## Arguments

  - `FILE` - Source file to analyze

  ## Options

  - `--validate MODE` - Validation mode (strict, standard, permissive) [default: standard]
  - `--language LANG` - Source language (optional, auto-detected from extension)

  ## Examples

  Analyze a Python file with standard validation:

      mix metastatic.analyze hello.py

  Use strict validation (no language_specific nodes allowed):

      mix metastatic.analyze hello.py --validate strict

  Use permissive validation (allow all constructs):

      mix metastatic.analyze hello.py --validate permissive

  ## Metrics Reported

  - **Language** - Source language
  - **Layer** - Deepest layer used (core, extended, native)
  - **Depth** - Maximum AST depth
  - **Node Count** - Total number of AST nodes
  - **Variable Count** - Number of unique variables
  - **Validation** - Conformance status and warnings

  ## Validation Modes

  - **strict** - No language_specific nodes allowed, must be pure M2
  - **standard** - Allow language_specific but warn (default)
  - **permissive** - Allow all constructs without warnings
  """

  use Mix.Task

  alias Metastatic.{Builder, CLI, Validator}
  alias Metastatic.CLI.Inspector

  @switches [
    validate: :string,
    language: :string
  ]

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, paths, _invalid} = OptionParser.parse(args, strict: @switches)

    case validate_args(opts, paths) do
      {:ok, file_path, options} ->
        analyze_file(file_path, options)

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
         {:ok, validation_mode} <- validate_mode(opts) do
      options = [
        language: language,
        validation_mode: validation_mode
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

  @spec validate_mode(keyword()) :: {:ok, atom()} | {:error, String.t()}
  defp validate_mode(opts) do
    case Keyword.get(opts, :validate, "standard") do
      "strict" ->
        {:ok, :strict}

      "standard" ->
        {:ok, :standard}

      "permissive" ->
        {:ok, :permissive}

      invalid ->
        {:error, "Invalid validation mode: #{invalid}. Supported: strict, standard, permissive"}
    end
  end

  # Analysis

  @spec analyze_file(String.t(), keyword()) :: no_return()
  defp analyze_file(file_path, options) do
    language = Keyword.fetch!(options, :language)
    validation_mode = Keyword.fetch!(options, :validation_mode)

    with {:ok, source} <- CLI.read_file(file_path),
         {:ok, doc} <- Builder.from_source(source, language),
         {:ok, inspection} <- Inspector.inspect_document(doc),
         {:ok, validation} <- Validator.validate(doc, mode: validation_mode) do
      show_analysis(file_path, inspection, validation)
      exit({:shutdown, 0})
    else
      {:error, reason} ->
        CLI.fatal("Analysis failed: #{inspect(reason)}")
    end
  end

  @spec show_analysis(String.t(), map(), map()) :: :ok
  defp show_analysis(file_path, inspection, validation) do
    Mix.shell().info(CLI.format_info("File: #{file_path}"))
    Mix.shell().info("")

    # Metrics section
    Mix.shell().info("Metrics:")
    Mix.shell().info("  Layer: #{inspection.layer}")
    Mix.shell().info("  Depth: #{inspection.depth}")
    Mix.shell().info("  Nodes: #{inspection.node_count}")
    Mix.shell().info("  Variables: #{MapSet.size(inspection.variables)}")
    Mix.shell().info("")

    # Validation section
    Mix.shell().info("Validation:")
    Mix.shell().info("  Level: #{validation.level}")
    Mix.shell().info("  Native Constructs: #{validation.native_constructs}")

    if Enum.empty?(validation.warnings) do
      Mix.shell().info(CLI.format_success("  No warnings"))
    else
      Mix.shell().info("  Warnings:")

      Enum.each(validation.warnings, fn warning ->
        Mix.shell().info("    - #{warning}")
      end)
    end

    Mix.shell().info("")

    # Summary
    if validation.level == :core do
      Mix.shell().info(CLI.format_success("Pure M2.1 (Core) - fully portable"))
    else
      if validation.level == :extended do
        Mix.shell().info(CLI.format_success("M2.2 (Extended) - widely portable"))
      else
        Mix.shell().info(CLI.format_info("M2.3 (Native) - contains language-specific constructs"))
      end
    end

    # Variable list if not too many
    if MapSet.size(inspection.variables) > 0 && MapSet.size(inspection.variables) <= 20 do
      Mix.shell().info("")
      Mix.shell().info("Variables:")

      inspection.variables
      |> Enum.sort()
      |> Enum.each(fn var ->
        Mix.shell().info("  #{var}")
      end)
    end
  end
end
