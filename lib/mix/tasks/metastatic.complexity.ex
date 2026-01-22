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
    * `--lines` - Analyze specific line range (e.g., "10-50") - extracted code must be valid
    * `--function` - Analyze specific function by name (first clause only for multi-clause functions)

  ## Examples

      # Basic complexity analysis
      mix metastatic.complexity my_file.py

      # JSON output
      mix metastatic.complexity my_file.py --format json

      # Detailed report
      mix metastatic.complexity my_file.ex --format detailed

      # Custom thresholds
      mix metastatic.complexity my_file.erl --max-cyclomatic 15 --max-cognitive 20

      # Analyze specific line range
      mix metastatic.complexity my_file.py --lines 10-50

      # Analyze specific function (first clause only for multi-clause functions)
      mix metastatic.complexity my_file.ex --function complex

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
          max_nesting: :integer,
          lines: :string,
          function: :string
        ],
        aliases: [f: :format, l: :language]
      )

    format = parse_format(opts[:format])
    language = parse_language(opts[:language])
    thresholds = build_thresholds(opts)
    scope = parse_scope(opts)

    case files do
      [] ->
        Mix.shell().error("Error: No file specified")
        Mix.shell().info("Usage: mix metastatic.complexity FILE [options]")
        exit({:shutdown, 2})

      [file | _] ->
        analyze_file(file, language, format, thresholds, scope)
    end
  end

  defp analyze_file(file, language, format, thresholds, scope) do
    unless File.exists?(file) do
      Mix.shell().error("Error: File not found: #{file}")
      exit({:shutdown, 2})
    end

    source = File.read!(file)
    lang = language || detect_language(file)

    # Extract subset of source if scope is specified
    {source, scope_info} = extract_scope(source, scope, lang)

    case Builder.from_source(source, lang) do
      {:ok, document} ->
        # If function scope, extract specific function for analysis
        {analysis_doc, display_info} =
          case {scope, scope_info} do
            {{:function, func_name}, :extract_function} ->
              extract_and_prepare_function(document, func_name)

            _ ->
              display_scope_info(document, scope, scope_info)
              {document, nil}
          end

        case Complexity.analyze(analysis_doc, thresholds: thresholds) do
          {:ok, result} ->
            if display_info, do: Mix.shell().info(display_info <> "\n")
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

  defp module_file?(%{ast: {:language_specific, _, _, :module_definition}}), do: true
  defp module_file?(%{ast: {:language_specific, _, _, :module_definition, _}}), do: true
  defp module_file?(_), do: false

  defp parse_scope(opts) do
    cond do
      opts[:function] -> {:function, opts[:function]}
      opts[:lines] -> {:lines, parse_line_range(opts[:lines])}
      true -> :full
    end
  end

  defp parse_line_range(str) do
    case String.split(str, "-") do
      [start_str, end_str] ->
        with {start_line, ""} <- Integer.parse(start_str),
             {end_line, ""} <- Integer.parse(end_str) do
          {start_line, end_line}
        else
          _ ->
            Mix.shell().error("Invalid line range: #{str}")
            Mix.shell().info("Expected format: START-END (e.g., 10-50)")
            exit({:shutdown, 2})
        end

      _ ->
        Mix.shell().error("Invalid line range: #{str}")
        Mix.shell().info("Expected format: START-END (e.g., 10-50)")
        exit({:shutdown, 2})
    end
  end

  defp extract_scope(source, :full, _lang), do: {source, nil}

  defp extract_scope(source, {:lines, {start_line, end_line}}, _lang) do
    lines = String.split(source, "\n")
    total_lines = length(lines)

    cond do
      start_line < 1 or end_line > total_lines ->
        Mix.shell().error(
          "Line range #{start_line}-#{end_line} out of bounds (file has #{total_lines} lines)"
        )

        exit({:shutdown, 2})

      start_line > end_line ->
        Mix.shell().error("Invalid line range: start (#{start_line}) > end (#{end_line})")
        exit({:shutdown, 2})

      true ->
        extracted =
          lines
          |> Enum.slice((start_line - 1)..(end_line - 1))
          |> Enum.join("\n")

        {extracted, "lines #{start_line}-#{end_line}"}
    end
  end

  defp extract_scope(source, {:function, _func_name}, _lang) do
    # For function scope, return full source with special marker
    # We'll handle extraction after parsing
    {source, :extract_function}
  end

  defp extract_and_prepare_function(document, func_name) do
    body = get_module_body(document.ast, document.metadata)

    case find_function_in_body(body, func_name) do
      {:ok, func_ast} ->
        # Create a new document with just the function body
        func_doc = Metastatic.Document.new(func_ast, document.language)
        info = "Note: Analyzing function '#{func_name}'"
        {func_doc, info}

      :not_found ->
        Mix.shell().error("Function '#{func_name}' not found in source")
        exit({:shutdown, 2})
    end
  end

  defp get_module_body({:language_specific, _, _, :module_definition, metadata}, _doc_metadata)
       when is_map(metadata) do
    Map.get(metadata, :body)
  end

  defp get_module_body({:language_specific, _, _, :module_definition}, metadata) do
    Map.get(metadata, :body)
  end

  defp get_module_body(_ast, _metadata), do: nil

  defp find_function_in_body({:block, statements}, func_name) when is_list(statements) do
    Enum.find_value(statements, :not_found, fn
      {:language_specific, _, _, :function_definition, metadata} ->
        if Map.get(metadata, :function_name) == func_name do
          {:ok, Map.get(metadata, :body)}
        else
          nil
        end

      _ ->
        nil
    end)
  end

  defp find_function_in_body(_body, _func_name), do: :not_found

  defp display_scope_info(_document, :full, nil) do
    # No special message for full file analysis
    :ok
  end

  defp display_scope_info(_document, _scope, scope_info) when is_binary(scope_info) do
    Mix.shell().info("Note: Analyzing #{scope_info}.\n")
  end

  defp display_scope_info(document, :full, nil) do
    if module_file?(document) do
      Mix.shell().info("Note: Analyzing entire module (includes all nested functions).\n")
    end
  end
end
