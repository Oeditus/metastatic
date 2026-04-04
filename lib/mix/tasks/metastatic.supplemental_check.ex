defmodule Mix.Tasks.Metastatic.SupplementalCheck do
  @moduledoc """
  Analyzes code to detect required supplemental modules.

  ## Usage

      mix metastatic.supplemental_check FILE [options]

  ## Options

    * `--format` - Output format: text (default), json, or detailed
    * `--language` - Source language (auto-detected if not specified)
    * `--target` - Target language for translation analysis

  ## Examples

      # Check what supplementals are needed for a file
      mix metastatic.supplemental_check my_file.ex

      # Check compatibility when translating to Python
      mix metastatic.supplemental_check my_file.ex --target python

      # JSON output
      mix metastatic.supplemental_check my_file.py --format json

      # Detailed report
      mix metastatic.supplemental_check my_file.ex --target python --format detailed

  ## Exit Codes

    * 0 - All required supplementals available (or none needed)
    * 1 - Missing supplementals detected
    * 2 - Error during analysis
  """

  @shortdoc "Detects required supplemental modules"

  use Mix.Task
  @dialyzer {:no_return, run: 1}
  @dialyzer {:no_return, analyze_file: 4}

  alias Metastatic.{Builder, CLI, Supplemental.Validator}

  @impl Mix.Task
  def run(args) do
    # Start the application to ensure registry is running
    Mix.Task.run("app.start")

    {opts, files, _invalid} =
      OptionParser.parse(args,
        strict: [format: :string, language: :string, target: :string],
        aliases: [f: :format, l: :language, t: :target]
      )

    format = parse_format(opts[:format])
    language = parse_language(opts[:language])
    target = parse_language(opts[:target])

    case files do
      [] ->
        Mix.shell().error("Error: No file specified")
        Mix.shell().info("Usage: mix metastatic.supplemental_check FILE [options]")
        exit({:shutdown, 2})

      [file | _] ->
        analyze_file(file, language, target, format)
    end
  end

  defp analyze_file(file, language, target, format) do
    unless File.exists?(file) do
      Mix.shell().error("Error: File not found: #{file}")
      exit({:shutdown, 2})
    end

    source = File.read!(file)
    lang = language || detect_language(file)

    case Builder.from_source(source, lang) do
      {:ok, document} ->
        if target do
          # Analyze compatibility with target language
          analyze_translation(document, lang, target, format)
        else
          # Just detect what supplementals are used
          analyze_constructs(document, format)
        end

      {:error, reason} ->
        Mix.shell().error("Parse error: #{inspect(reason)}")
        exit({:shutdown, 2})
    end
  end

  defp analyze_translation(document, source_lang, target_lang, format) do
    case Validator.analyze(document, target_lang) do
      {:ok, result} ->
        output = format_result(result, source_lang, target_lang, format, true)
        Mix.shell().info(output)
        exit({:shutdown, 0})

      {:error, result} ->
        output = format_result(result, source_lang, target_lang, format, false)
        Mix.shell().info(output)
        exit({:shutdown, 1})
    end
  end

  defp analyze_constructs(document, format) do
    required = Validator.detect_required_constructs(document.ast)

    result = %{
      required: required,
      count: length(required)
    }

    output = format_constructs(result, format)
    Mix.shell().info(output)
    exit({:shutdown, 0})
  end

  defp format_result(result, source_lang, target_lang, :json, _compatible?) do
    result
    |> Map.put(:source_language, source_lang)
    |> Map.put(:target_language, target_lang)
    |> Jason.encode!(pretty: true)
  end

  defp format_result(result, source_lang, target_lang, :detailed, compatible?) do
    lines = [
      "Supplemental Module Analysis",
      "============================",
      "",
      "Source Language: #{source_lang}",
      "Target Language: #{target_lang}",
      "",
      "Required Constructs: #{length(result.required)}",
      format_list(result.required, "  "),
      "",
      "Available Supplementals: #{length(result.available)}",
      format_list(result.available, "  "),
      ""
    ]

    lines =
      if compatible? do
        lines ++
          [
            "Status: ✓ Compatible",
            "All required supplementals are available for #{target_lang}."
          ]
      else
        lines ++
          [
            "Status: ✗ Incompatible",
            "",
            "Missing Supplementals: #{length(result.missing)}",
            format_list(result.missing, "  "),
            "",
            "Action Required:",
            "The following constructs require supplemental modules that are not available:",
            format_list(result.missing, "  - "),
            "",
            "To resolve:",
            "1. Install required supplemental libraries in the target language",
            "2. Verify supplemental modules are registered with Metastatic",
            "3. See SUPPLEMENTAL_MODULES.md for details"
          ]
      end

    Enum.join(lines, "\n")
  end

  defp format_result(result, _source_lang, target_lang, :text, compatible?) do
    if compatible? do
      "✓ All required supplementals available for #{target_lang}"
    else
      missing_list = Enum.join(result.missing, ", ")
      "✗ Missing supplementals for #{target_lang}: #{missing_list}"
    end
  end

  defp format_constructs(result, :json) do
    Jason.encode!(result, pretty: true)
  end

  defp format_constructs(result, :detailed) do
    lines = [
      "Supplemental Construct Detection",
      "=================================",
      "",
      "Required Constructs: #{result.count}"
    ]

    lines =
      if result.count > 0 do
        lines ++
          [
            format_list(result.required, "  "),
            "",
            "These constructs may require supplemental modules when",
            "translating to languages that don't support them natively."
          ]
      else
        lines ++
          [
            "",
            "No supplemental constructs detected.",
            "This code uses only core MetaAST constructs."
          ]
      end

    Enum.join(lines, "\n")
  end

  defp format_constructs(result, :text) do
    if result.count > 0 do
      construct_list = Enum.join(result.required, ", ")
      "Required constructs: #{construct_list}"
    else
      "No supplemental constructs detected"
    end
  end

  defp format_list([], _prefix), do: "  (none)"

  defp format_list(items, prefix) do
    Enum.map_join(items, "\n", &"#{prefix}#{&1}")
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

  defp parse_language(lang_str) do
    case CLI.parse_language(lang_str) do
      {:ok, lang} ->
        lang

      {:error, reason} ->
        Mix.shell().error(reason)
        exit({:shutdown, 2})
    end
  end

  defp detect_language(file) do
    case CLI.detect_language(file) do
      {:ok, lang} ->
        lang

      {:error, _} ->
        Mix.shell().error("Cannot detect language from extension: #{Path.extname(file)}")
        Mix.shell().info("Please specify --language option")
        exit({:shutdown, 2})
    end
  end
end
