defmodule Mix.Tasks.Metastatic.DetectDuplicates do
  @moduledoc """
  Detects code duplication across source files using the unified MetaAST representation.

  Parses source files through the appropriate language adapter, abstracts them to
  MetaAST, and then detects structural code clones (Type I-III) across the
  resulting documents. Cross-language detection works out of the box.

  ## Workflow

  ```mermaid
  flowchart TD
      Input["Input: files or --dir"] --> Discover["Discover files<br/>filter by extension"]
      Discover --> Parse["Parse each file"]
      Parse --> Detect{"Language<br/>detection"}
      Detect --> Adapter["Select adapter<br/>Python/Elixir/Ruby/..."]
      Adapter --> M2["Source -> M1 -> M2<br/>Builder.from_source"]
      M2 --> Docs["List of Documents"]
      Docs --> Dup["Duplication.detect_in_list<br/>Type I-III clone detection"]
      Dup --> Groups["Duplicate groups"]
      Groups --> Report["Reporter.format_groups<br/>text / json / detailed"]
      Report --> Output["stdout or --output file"]
  ```

  ## Usage

      mix metastatic.detect_duplicates FILE1 FILE2 [OPTIONS]
      mix metastatic.detect_duplicates --dir PATH [OPTIONS]

  ## Options

    * `--format FORMAT` - Output format: text (default), json, or detailed
    * `--threshold FLOAT` - Similarity threshold for Type III detection (default: 0.8)
    * `--output PATH` - Write output to file instead of stdout
    * `--cross-language` - Enable cross-language detection (default: true)
    * `--dir PATH` - Scan all supported files in directory recursively
    * `--help` - Display this help message

  ## Supported Languages

  Language is auto-detected from file extension.
  See `Metastatic.Languages` for the current list of supported languages
  and file extensions.

  ## Examples

      # Detect duplicates between two files
      mix metastatic.detect_duplicates lib/foo.ex lib/bar.ex

      # Cross-language detection
      mix metastatic.detect_duplicates lib/foo.ex src/foo.py

      # Scan entire directory
      mix metastatic.detect_duplicates --dir lib/

      # Output as JSON with custom threshold
      mix metastatic.detect_duplicates lib/foo.ex lib/bar.ex --format json --threshold 0.85

      # Save detailed report to file
      mix metastatic.detect_duplicates --dir lib/ --format detailed --output report.txt

  ## Programmatic API

      alias Metastatic.{Document, Analysis.Duplication}

      doc1 = Document.new(ast1, :elixir)
      doc2 = Document.new(ast2, :python)

      {:ok, result} = Duplication.detect(doc1, doc2)
      {:ok, groups} = Duplication.detect_in_list([doc1, doc2, doc3])
  """

  @shortdoc "Detects code duplication across source files"

  use Mix.Task
  @dialyzer {:no_return, [run: 1, scan_directory: 2]}

  alias Metastatic.Analysis.Duplication
  alias Metastatic.Analysis.Duplication.Reporter
  alias Metastatic.{Builder, Languages}

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

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

  defp scan_directory(dir_path, opts) do
    unless File.dir?(dir_path) do
      Mix.shell().error("Error: Not a directory: #{dir_path}")
      exit({:shutdown, 2})
    end

    files =
      dir_path
      |> Path.join("**/*")
      |> Path.wildcard()
      |> Enum.filter(
        &(Path.extname(&1) in Languages.supported_extensions() and not File.dir?(&1))
      )
      |> Enum.sort()

    unless match?([_, _ | _], files) do
      Mix.shell().info(
        "Found #{length(files)} supported file(s) in #{dir_path} - need at least 2"
      )

      exit({:shutdown, 0})
    end

    Mix.shell().info("Scanning #{length(files)} files in #{dir_path}...")
    detect_in_files(files, opts)
  end

  defp detect_in_files(files, opts) do
    format = String.to_atom(opts[:format] || "text")
    threshold = opts[:threshold] || 0.8
    detect_opts = [threshold: threshold]

    documents = load_documents(files)

    if length(documents) < 2 do
      Mix.shell().error("Could not parse enough files for comparison")
      exit({:shutdown, 2})
    end

    Mix.shell().info("Comparing #{length(documents)} document(s)...")

    {:ok, groups} = Duplication.detect_in_list(documents, detect_opts)

    output = Reporter.format_groups(groups, format)

    write_output(output, opts[:output])

    case groups do
      [] -> exit({:shutdown, 0})
      _ -> exit({:shutdown, 1})
    end
  end

  defp load_documents(files) do
    files
    |> Enum.flat_map(fn file ->
      case detect_language(file) do
        {:ok, lang} ->
          case File.read(file) do
            {:ok, source} ->
              case Builder.from_source(source, lang) do
                {:ok, doc} ->
                  [{file, lang, doc}]

                {:error, reason} ->
                  Mix.shell().info("Skipping #{file}: #{inspect(reason)}")
                  []
              end

            {:error, reason} ->
              Mix.shell().info("Cannot read #{file}: #{inspect(reason)}")
              []
          end

        :unsupported ->
          []
      end
    end)
    |> Enum.map(fn {_file, _lang, doc} -> doc end)
  end

  defp write_output(output, nil) do
    Mix.shell().info(output)
  end

  defp write_output(output, path) do
    File.write!(path, output)
    Mix.shell().info("Report written to: #{path}")
  end

  defp detect_language(file) do
    case Languages.detect_language(file) do
      {:ok, lang} -> {:ok, lang}
      {:error, _} -> :unsupported
    end
  end
end
