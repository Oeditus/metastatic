defmodule Mix.Tasks.Metastatic.Translate do
  @shortdoc "Translate source code between languages"

  @moduledoc """
  Translate source code from one programming language to another using MetaAST.

  ## Usage

      mix metastatic.translate --from LANG --to LANG FILE [OPTIONS]
      mix metastatic.translate --from LANG --to LANG DIR --output OUT_DIR

  ## Arguments

  - `FILE` or `DIR` - Source file or directory to translate

  ## Options

  - `--from LANG` - Source language (python, elixir, erlang)
  - `--to LANG` - Target language (python, elixir, erlang)
  - `--output PATH` - Output file or directory (optional for single files)

  ## Examples

  Translate a single Python file to Elixir (auto-detects output path):

      mix metastatic.translate --from python --to elixir hello.py
      # Creates: hello.ex

  Translate with explicit output path:

      mix metastatic.translate --from python --to elixir hello.py --output lib/hello.ex

  Translate an entire directory:

      mix metastatic.translate --from python --to elixir src/ --output lib/

  Auto-detect source language from file extension:

      mix metastatic.translate --to elixir hello.py
      # Detects Python from .py extension

  ## Translation Process

  1. Parse source code to language-specific AST (M1)
  2. Transform to MetaAST (M2) - universal representation
  3. Transform MetaAST to target language AST (M1')
  4. Unparse to target language source code

  ## Limitations

  - Some language-specific constructs may not translate perfectly
  - Native layer (M2.3) constructs are preserved as language_specific nodes
  - Comments and formatting may not be preserved
  - Not all type annotations translate between languages
  """

  use Mix.Task

  alias Metastatic.CLI
  alias Metastatic.CLI.Translator

  @switches [
    from: :string,
    to: :string,
    output: :string
  ]

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, paths, _invalid} = OptionParser.parse(args, strict: @switches)

    case validate_args(opts, paths) do
      {:ok, from_lang, to_lang, source_path, output_path} ->
        translate(from_lang, to_lang, source_path, output_path)

      {:error, message} ->
        CLI.fatal(message)
    end
  end

  # Validation

  @spec validate_args(keyword(), [String.t()]) ::
          {:ok, atom(), atom(), String.t(), String.t() | nil} | {:error, String.t()}
  defp validate_args(opts, paths) do
    with {:ok, source_path} <- validate_source_path(paths),
         {:ok, from_lang} <- validate_from_language(opts, source_path),
         {:ok, to_lang} <- validate_to_language(opts),
         {:ok, output_path} <- validate_output_path(opts, paths) do
      {:ok, from_lang, to_lang, source_path, output_path}
    end
  end

  @spec validate_source_path([String.t()]) :: {:ok, String.t()} | {:error, String.t()}
  defp validate_source_path([]), do: {:error, "No source file or directory provided"}
  defp validate_source_path([path | _]), do: validate_path_exists(path)

  @spec validate_path_exists(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  defp validate_path_exists(path) do
    if File.exists?(path) do
      {:ok, path}
    else
      {:error, "Source path does not exist: #{path}"}
    end
  end

  @spec validate_from_language(keyword(), String.t()) :: {:ok, atom()} | {:error, String.t()}
  defp validate_from_language(opts, source_path) do
    case Keyword.get(opts, :from) do
      nil ->
        # Auto-detect from file extension
        case CLI.detect_language(source_path) do
          {:ok, lang} -> {:ok, lang}
          {:error, _} -> {:error, "Cannot detect source language. Use --from option"}
        end

      lang_str ->
        parse_language(lang_str, "from")
    end
  end

  @spec validate_to_language(keyword()) :: {:ok, atom()} | {:error, String.t()}
  defp validate_to_language(opts) do
    case Keyword.get(opts, :to) do
      nil -> {:error, "Missing required option: --to"}
      lang_str -> parse_language(lang_str, "to")
    end
  end

  @spec validate_output_path(keyword(), [String.t()]) ::
          {:ok, String.t() | nil} | {:error, String.t()}
  defp validate_output_path(opts, _paths) do
    case Keyword.get(opts, :output) do
      nil -> {:ok, nil}
      path -> {:ok, path}
    end
  end

  @spec parse_language(String.t(), String.t()) :: {:ok, atom()} | {:error, String.t()}
  defp parse_language(lang_str, opt_name) do
    case String.downcase(lang_str) do
      "python" ->
        {:ok, :python}

      "elixir" ->
        {:ok, :elixir}

      "erlang" ->
        {:ok, :erlang}

      _ ->
        {:error, "Invalid --#{opt_name} language: #{lang_str}. Supported: python, elixir, erlang"}
    end
  end

  # Translation

  @spec translate(atom(), atom(), String.t(), String.t() | nil) :: no_return()
  defp translate(from_lang, to_lang, source_path, output_path) do
    if same_language?(from_lang, to_lang) do
      CLI.fatal("Source and target languages are the same: #{from_lang}")
    end

    if File.dir?(source_path) do
      translate_directory(from_lang, to_lang, source_path, output_path)
    else
      translate_file(from_lang, to_lang, source_path, output_path)
    end
  end

  @spec translate_file(atom(), atom(), String.t(), String.t() | nil) :: no_return()
  defp translate_file(from_lang, to_lang, source_path, nil) do
    # Auto-generate output path
    Mix.shell().info(CLI.format_info("Translating #{source_path} (#{from_lang} → #{to_lang})"))

    case Translator.translate_with_auto_output(source_path, from_lang, to_lang) do
      {:ok, output_path} ->
        Mix.shell().info(CLI.format_success("Translated to #{output_path}"))
        exit({:shutdown, 0})

      {:error, reason} ->
        CLI.fatal(reason)
    end
  end

  defp translate_file(from_lang, to_lang, source_path, output_path) do
    # Explicit output path
    Mix.shell().info(
      CLI.format_info("Translating #{source_path} → #{output_path} (#{from_lang} → #{to_lang})")
    )

    case Translator.translate(source_path, from_lang, to_lang, output_path) do
      {:ok, ^output_path} ->
        Mix.shell().info(CLI.format_success("Translation complete"))
        exit({:shutdown, 0})

      {:error, reason} ->
        CLI.fatal(reason)
    end
  end

  @spec translate_directory(atom(), atom(), String.t(), String.t() | nil) :: no_return()
  defp translate_directory(_from_lang, _to_lang, _source_dir, nil) do
    CLI.fatal("Directory translation requires --output option")
  end

  defp translate_directory(from_lang, to_lang, source_dir, output_dir) do
    Mix.shell().info(
      CLI.format_info(
        "Translating directory #{source_dir} → #{output_dir} (#{from_lang} → #{to_lang})"
      )
    )

    case Translator.translate_directory(source_dir, from_lang, to_lang, output_dir) do
      {:ok, files} ->
        Mix.shell().info(CLI.format_success("Translated #{length(files)} files"))

        Enum.each(files, fn file ->
          Mix.shell().info("  → #{file}")
        end)

        exit({:shutdown, 0})

      {:error, reason} ->
        CLI.fatal(reason)
    end
  end

  @spec same_language?(atom(), atom()) :: boolean()
  defp same_language?(lang, lang), do: true
  defp same_language?(_, _), do: false
end
