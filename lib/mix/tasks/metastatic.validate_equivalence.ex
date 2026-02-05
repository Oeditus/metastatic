defmodule Mix.Tasks.Metastatic.ValidateEquivalence do
  @shortdoc "Validate semantic equivalence between two files"

  @moduledoc """
  Validate that two source files have semantically equivalent MetaAST representations.

  This demonstrates cross-language semantic equivalence - showing that code in
  different languages can represent the same abstract computation at the M2 level.

  ## Usage

      mix metastatic.validate-equivalence FILE1 FILE2 [OPTIONS]

  ## Arguments

  - `FILE1` - First source file
  - `FILE2` - Second source file

  ## Options

  - `--lang1 LANG` - Language of first file (optional, auto-detected)
  - `--lang2 LANG` - Language of second file (optional, auto-detected)
  - `--verbose` - Show detailed comparison

  ## Examples

  Compare Python and Elixir implementations:

      mix metastatic.validate-equivalence hello.py hello.ex

  Compare with explicit language specification:

      mix metastatic.validate-equivalence file1.txt file2.txt --lang1 python --lang2 elixir

  Show detailed differences:

      mix metastatic.validate-equivalence hello.py hello.ex --verbose

  ## Equivalence Checking

  Two files are considered semantically equivalent if their MetaAST representations
  are identical. This means:

  - Same structure and operations
  - Same variable names
  - Same literal values
  - Same control flow

  Differences allowed:
  - Comments and documentation
  - Whitespace and formatting
  - Language-specific syntax sugar
  - Type annotations (when not semantically meaningful)

  ## Exit Codes

  - 0 - Files are semantically equivalent
  - 1 - Files are not equivalent or error occurred
  """

  use Mix.Task

  alias Metastatic.{Builder, CLI}

  @switches [
    lang1: :string,
    lang2: :string,
    verbose: :boolean
  ]

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, paths, _invalid} = OptionParser.parse(args, strict: @switches)

    case validate_args(opts, paths) do
      {:ok, file1, file2, options} ->
        validate_equivalence(file1, file2, options)

      {:error, message} ->
        CLI.fatal(message)
    end
  end

  # Validation

  @spec validate_args(keyword(), [String.t()]) ::
          {:ok, String.t(), String.t(), keyword()} | {:error, String.t()}
  defp validate_args(opts, paths) do
    with {:ok, file1, file2} <- validate_file_paths(paths),
         {:ok, lang1} <- validate_language(opts, :lang1, file1),
         {:ok, lang2} <- validate_language(opts, :lang2, file2) do
      options = [
        lang1: lang1,
        lang2: lang2,
        verbose: Keyword.get(opts, :verbose, false)
      ]

      {:ok, file1, file2, options}
    end
  end

  @spec validate_file_paths([String.t()]) :: {:ok, String.t(), String.t()} | {:error, String.t()}
  defp validate_file_paths(paths) when length(paths) < 2 do
    {:error, "Two files required for equivalence checking"}
  end

  defp validate_file_paths([file1, file2 | _]) do
    cond do
      !File.exists?(file1) ->
        {:error, "First file does not exist: #{file1}"}

      !File.exists?(file2) ->
        {:error, "Second file does not exist: #{file2}"}

      File.dir?(file1) ->
        {:error, "First path is a directory: #{file1}"}

      File.dir?(file2) ->
        {:error, "Second path is a directory: #{file2}"}

      true ->
        {:ok, file1, file2}
    end
  end

  @spec validate_language(keyword(), atom(), String.t()) :: {:ok, atom()} | {:error, String.t()}
  defp validate_language(opts, opt_key, file_path) do
    case Keyword.get(opts, opt_key) do
      nil ->
        case CLI.detect_language(file_path) do
          {:ok, lang} ->
            {:ok, lang}

          {:error, _} ->
            {:error, "Cannot detect language for #{file_path}. Use --#{opt_key} option"}
        end

      lang_str ->
        case String.downcase(lang_str) do
          "python" ->
            {:ok, :python}

          "elixir" ->
            {:ok, :elixir}

          "erlang" ->
            {:ok, :erlang}

          _ ->
            {:error,
             "Invalid language for #{opt_key}: #{lang_str}. Supported: python, elixir, erlang"}
        end
    end
  end

  # AST equivalence (ignoring location metadata)
  # For 3-tuple format: {type, meta_keyword_list, children_or_value}
  # We strip location-related keys from the metadata keyword list

  @location_keys ~w[line end_line col end_col column end_column original_meta]a

  @spec ast_equivalent?(term(), term()) :: boolean()
  defp ast_equivalent?(ast1, ast2) do
    strip_locations(ast1) == strip_locations(ast2)
  end

  # Strip location metadata from AST nodes for comparison
  # Handle 3-tuple format: {type, meta, children}
  defp strip_locations({type, meta, children}) when is_atom(type) and is_list(meta) do
    stripped_meta = strip_location_keys(meta)
    stripped_children = strip_locations(children)
    {type, stripped_meta, stripped_children}
  end

  defp strip_locations(ast) when is_tuple(ast) do
    tuple_map_elements(ast, &strip_locations/1)
  end

  defp strip_locations(list) when is_list(list) do
    Enum.map(list, &strip_locations/1)
  end

  defp strip_locations(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {k, strip_locations(v)} end)
  end

  defp strip_locations(other), do: other

  # Strip location keys from metadata keyword list
  defp strip_location_keys(meta) when is_list(meta) do
    meta
    |> Keyword.drop(@location_keys)
    |> Enum.map(fn {k, v} -> {k, strip_locations(v)} end)
  end

  # Helper to map over tuple elements
  defp tuple_map_elements(tuple, fun) do
    tuple
    |> Tuple.to_list()
    |> Enum.map(fun)
    |> List.to_tuple()
  end

  # Equivalence validation

  @spec validate_equivalence(String.t(), String.t(), keyword()) :: no_return()
  defp validate_equivalence(file1, file2, options) do
    lang1 = Keyword.fetch!(options, :lang1)
    lang2 = Keyword.fetch!(options, :lang2)
    verbose = Keyword.fetch!(options, :verbose)

    Mix.shell().info(CLI.format_info("Comparing:"))
    Mix.shell().info("  File 1: #{file1} (#{lang1})")
    Mix.shell().info("  File 2: #{file2} (#{lang2})")
    Mix.shell().info("")

    with {:ok, source1} <- CLI.read_file(file1),
         {:ok, source2} <- CLI.read_file(file2),
         {:ok, doc1} <- Builder.from_source(source1, lang1),
         {:ok, doc2} <- Builder.from_source(source2, lang2) do
      if ast_equivalent?(doc1.ast, doc2.ast) do
        Mix.shell().info(CLI.format_success("Semantically equivalent"))

        if verbose do
          show_details(doc1, doc2)
        end

        exit({:shutdown, 0})
      else
        Mix.shell().error(CLI.format_error("Not semantically equivalent"))

        if verbose do
          show_differences(doc1, doc2)
        else
          Mix.shell().info("")
          Mix.shell().info("Run with --verbose to see detailed differences")
        end

        exit({:shutdown, 1})
      end
    else
      {:error, reason} ->
        CLI.fatal("Comparison failed: #{inspect(reason)}")
    end
  end

  @spec show_details(Metastatic.Document.t(), Metastatic.Document.t()) :: :ok
  defp show_details(doc1, doc2) do
    Mix.shell().info("")
    Mix.shell().info("Details:")
    Mix.shell().info("  Variables:")

    vars1 = Metastatic.AST.variables(doc1.ast)
    vars2 = Metastatic.AST.variables(doc2.ast)

    all_vars = MapSet.union(vars1, vars2) |> Enum.sort()

    Enum.each(all_vars, fn var ->
      Mix.shell().info("    #{var}")
    end)

    Mix.shell().info("")
    Mix.shell().info("  MetaAST structure: identical")
  end

  @spec show_differences(Metastatic.Document.t(), Metastatic.Document.t()) :: :ok
  defp show_differences(doc1, doc2) do
    Mix.shell().info("")
    Mix.shell().info("Differences:")
    Mix.shell().info("")

    # Show AST representations
    Mix.shell().info("File 1 MetaAST:")
    Mix.shell().info("  #{inspect(doc1.ast, pretty: true, width: 80)}")
    Mix.shell().info("")

    Mix.shell().info("File 2 MetaAST:")
    Mix.shell().info("  #{inspect(doc2.ast, pretty: true, width: 80)}")
    Mix.shell().info("")

    # Show variable differences
    vars1 = Metastatic.AST.variables(doc1.ast)
    vars2 = Metastatic.AST.variables(doc2.ast)

    only_in_1 = MapSet.difference(vars1, vars2)
    only_in_2 = MapSet.difference(vars2, vars1)

    if MapSet.size(only_in_1) > 0 do
      Mix.shell().info("Variables only in file 1:")

      Enum.each(only_in_1, fn var ->
        Mix.shell().info("  #{var}")
      end)

      Mix.shell().info("")
    end

    if MapSet.size(only_in_2) > 0 do
      Mix.shell().info("Variables only in file 2:")

      Enum.each(only_in_2, fn var ->
        Mix.shell().info("  #{var}")
      end)

      Mix.shell().info("")
    end
  end
end
