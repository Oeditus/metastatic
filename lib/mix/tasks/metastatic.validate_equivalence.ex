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
  @dialyzer {:no_return, run: 1}
  @dialyzer :no_opaque

  alias Metastatic.{AST, Builder, CLI}

  @switches [
    lang1: :string,
    lang2: :string,
    verbose: :boolean,
    alpha: :boolean
  ]

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    if Metastatic.CLI.help_requested?(args),
      do: Metastatic.CLI.help(Mix.Tasks.Metastatic.ValidateEquivalence)

    {opts, paths, _invalid} = OptionParser.parse(args, strict: @switches)

    case validate_args(opts, paths) do
      {:ok, file1, file2, options} ->
        validate_equivalence(file1, file2, options)

      {:error, message} ->
        CLI.fatal(message, 2)
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
        verbose: Keyword.get(opts, :verbose, false),
        alpha: Keyword.get(opts, :alpha, false)
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
        case CLI.parse_language(lang_str) do
          {:ok, lang} ->
            {:ok, lang}

          _ ->
            {:error,
             "Invalid language for #{opt_key}: #{lang_str}. Supported: #{Metastatic.Languages.supported_languages_string()}"}
        end
    end
  end

  # AST equivalence.
  #
  # Delegates to `Metastatic.AST.canonicalize/1`, the single source of truth
  # for "semantically equivalent" used by `Document.equivalent?/2` and the
  # cross-language conformance suite. A hand-rolled metadata strip used to
  # keep `:original_meta`, `:origin`, `:desugar` and other adapter bookkeeping,
  # so two files the library itself considers equivalent were reported as
  # different.

  @spec ast_equivalent?(term(), term(), keyword()) :: boolean()
  defp ast_equivalent?(ast1, ast2, options) do
    alpha? = Keyword.get(options, :alpha, false)

    canonical1 = ast1 |> AST.canonicalize() |> maybe_alpha(alpha?)
    canonical2 = ast2 |> AST.canonicalize() |> maybe_alpha(alpha?)

    canonical1 == canonical2
  end

  # `--alpha` renames variables to `v_0`, `v_1`, ... in first-appearance order,
  # so two files that differ only in variable names compare equal.
  defp maybe_alpha(ast, false), do: ast
  defp maybe_alpha(ast, true), do: ast |> alpha_rename_vars(%{}) |> elem(0)

  defp alpha_rename_vars(list, acc) when is_list(list) do
    Enum.map_reduce(list, acc, &alpha_rename_vars/2)
  end

  defp alpha_rename_vars({:variable, meta, name}, acc) when is_binary(name) do
    {canonical_name, new_acc} = get_or_create_var(name, acc)
    {{:variable, meta, canonical_name}, new_acc}
  end

  defp alpha_rename_vars({:param, meta, name}, acc) when is_binary(name) do
    {canonical_name, new_acc} = get_or_create_var(name, acc)
    {{:param, meta, canonical_name}, new_acc}
  end

  defp alpha_rename_vars({:function_def, meta, body}, acc) when is_list(meta) do
    params = Keyword.get(meta, :params, [])
    {new_params, acc2} = alpha_rename_vars(params, acc)
    {new_body, acc3} = alpha_rename_vars(body, acc2)
    {{:function_def, Keyword.put(meta, :params, new_params), new_body}, acc3}
  end

  defp alpha_rename_vars({:lambda, meta, body}, acc) when is_list(meta) do
    params = Keyword.get(meta, :params, [])
    {new_params, acc2} = alpha_rename_vars(params, acc)
    {new_body, acc3} = alpha_rename_vars(body, acc2)
    {{:lambda, Keyword.put(meta, :params, new_params), new_body}, acc3}
  end

  defp alpha_rename_vars({type, meta, children}, acc) when is_atom(type) and is_list(meta) do
    {new_children, new_acc} = alpha_rename_vars(children, acc)
    {{type, meta, new_children}, new_acc}
  end

  defp alpha_rename_vars(map, acc) when is_map(map) do
    {list, acc_out} =
      Enum.map_reduce(map, acc, fn {k, v}, acc_in ->
        {new_v, acc_next} = alpha_rename_vars(v, acc_in)
        {{k, new_v}, acc_next}
      end)

    {Map.new(list), acc_out}
  end

  defp alpha_rename_vars(tuple, acc) when is_tuple(tuple) do
    {list, acc_out} = tuple |> Tuple.to_list() |> alpha_rename_vars(acc)
    {List.to_tuple(list), acc_out}
  end

  defp alpha_rename_vars(other, acc), do: {other, acc}

  defp get_or_create_var(name, acc) do
    case Map.fetch(acc, name) do
      {:ok, canonical} ->
        {canonical, acc}

      :error ->
        canonical = "v_#{map_size(acc)}"
        {canonical, Map.put(acc, name, canonical)}
    end
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
      if ast_equivalent?(doc1.ast, doc2.ast, options) do
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
        CLI.fatal("Comparison failed: #{CLI.format_reason(reason)}")
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
