defmodule Mix.Tasks.Metastatic.DetectDuplicates do
  @moduledoc """
  Detects code duplication across MetaAST documents.

  This task analyzes one or more files for code duplication, supporting
  cross-language detection when files are parsed to MetaAST.

  ## Usage

      mix metastatic.detect_duplicates FILE1 FILE2 [OPTIONS]
      mix metastatic.detect_duplicates --dir PATH [OPTIONS]

  ## Options

    * `--format FORMAT` - Output format: text (default), json, or detailed
    * `--threshold FLOAT` - Similarity threshold for Type III detection (default: 0.8)
    * `--output PATH` - Write output to file instead of stdout
    * `--cross-language` - Enable cross-language detection (default: true)
    * `--dir PATH` - Scan all files in directory recursively
    * `--help` - Display this help message

  ## Examples

      # Detect duplicates between two files
      mix metastatic.detect_duplicates lib/foo.ex lib/bar.ex

      # Scan entire directory
      mix metastatic.detect_duplicates --dir lib/

      # Output as JSON with custom threshold
      mix metastatic.detect_duplicates lib/foo.ex lib/bar.ex --format json --threshold 0.85

      # Save detailed report to file
      mix metastatic.detect_duplicates --dir lib/ --format detailed --output report.txt

  ## Note

  This task currently works with MetaAST documents. Language adapter support
  (to parse real source files) will be added in future phases.

  For now, you can use this task programmatically via the API:

      alias Metastatic.{Document, Analysis.Duplication}
      
      # Create documents
      doc1 = Document.new(ast1, :elixir)
      doc2 = Document.new(ast2, :python)
      
      # Detect duplicates
      {:ok, result} = Duplication.detect(doc1, doc2)
      
      # Or detect across multiple documents
      {:ok, groups} = Duplication.detect_in_list([doc1, doc2, doc3])
  """

  @shortdoc "Detects code duplication across MetaAST documents"

  use Mix.Task

  # alias Metastatic.Analysis.Duplication
  alias Metastatic.Analysis.Duplication.Reporter

  @impl Mix.Task
  def run(args) do
    {opts, files, _} =
      OptionParser.parse(args,
        strict: [
          format: :string,
          threshold: :float,
          output: :string,
          cross_language: :boolean,
          dir: :string,
          help: :boolean
        ],
        aliases: [
          f: :format,
          t: :threshold,
          o: :output,
          d: :dir,
          h: :help
        ]
      )

    cond do
      opts[:help] ->
        show_help()

      opts[:dir] ->
        scan_directory(opts[:dir], opts)

      length(files) >= 2 ->
        detect_in_files(files, opts)

      length(files) == 1 ->
        Mix.shell().error("Error: Need at least 2 files to compare")
        Mix.shell().info("Use --dir to scan a directory, or provide multiple files")
        exit({:shutdown, 1})

      true ->
        show_help()
    end
  end

  defp show_help do
    Mix.shell().info(@moduledoc)
  end

  defp scan_directory(dir_path, _opts) do
    Mix.shell().info("Scanning directory: #{dir_path}")

    Mix.shell().info(
      "Note: Directory scanning with real files requires language adapters (Phase 2+)"
    )

    Mix.shell().info("This feature will be available once language adapters are implemented.")
    Mix.shell().info("")
    Mix.shell().info("For now, use the API directly with MetaAST documents:")
    Mix.shell().info("  Duplication.detect_in_list([doc1, doc2, ...])")
  end

  defp detect_in_files(files, opts) do
    Mix.shell().info("Detecting duplicates in files:")
    Enum.each(files, &Mix.shell().info("  - #{&1}"))
    Mix.shell().info("")
    Mix.shell().info("Note: File parsing requires language adapters (Phase 2+)")
    Mix.shell().info("This feature will be available once language adapters are implemented.")
    Mix.shell().info("")
    Mix.shell().info("For now, use the API directly with MetaAST documents:")
    Mix.shell().info("  doc1 = Document.new(ast1, :elixir)")
    Mix.shell().info("  doc2 = Document.new(ast2, :python)")
    Mix.shell().info("  {:ok, result} = Duplication.detect(doc1, doc2)")
    Mix.shell().info("  Reporter.format(result, :#{opts[:format] || "text"})")
  end

  # Helper to format and output results (will be used when adapters are available)
  # defp output_result(result, opts) do
  #   format = String.to_atom(opts[:format] || "text")
  #   output = Reporter.format(result, format)
  #
  #   case opts[:output] do
  #     nil ->
  #       Mix.shell().info(output)
  #
  #     path ->
  #       File.write!(path, output)
  #       Mix.shell().info("Report written to: #{path}")
  #   end
  # end
  #
  # # Helper to format and output clone groups (will be used when adapters are available)
  # defp output_groups(groups, opts) do
  #   format = String.to_atom(opts[:format] || "text")
  #   output = Reporter.format_groups(groups, format)
  #
  #   case opts[:output] do
  #     nil ->
  #       Mix.shell().info(output)
  #
  #     path ->
  #       File.write!(path, output)
  #       Mix.shell().info("Report written to: #{path}")
  #   end
  # end
end
