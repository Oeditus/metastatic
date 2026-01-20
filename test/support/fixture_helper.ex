defmodule Metastatic.Test.FixtureHelper do
  @moduledoc """
  Helper utilities for loading and managing test fixtures.

  Provides structured access to test fixtures across different languages,
  with support for expected MetaAST outputs and validation.

  ## Directory Structure

      test/fixtures/
      ├── python/
      │   ├── simple_arithmetic.py
      │   ├── complex_function.py
      │   └── expected/
      │       ├── simple_arithmetic.exs
      │       └── complex_function.exs
      ├── javascript/
      │   └── ...
      └── elixir/
          └── ...

  ## Usage

      # Load all fixtures for a language
      fixtures = FixtureHelper.load_language(:python)

      # Load a specific fixture
      {:ok, fixture} = FixtureHelper.load_fixture(:python, "simple_arithmetic")

      # Get fixture path
      path = FixtureHelper.fixture_path(:python, "simple_arithmetic.py")
  """

  @fixtures_dir Path.join([__DIR__, "..", "fixtures"])

  @doc """
  Get the base fixtures directory path.
  """
  @spec fixtures_dir() :: String.t()
  def fixtures_dir, do: @fixtures_dir

  @doc """
  Get the fixtures directory for a specific language.

  ## Examples

      iex> FixtureHelper.language_dir(:python)
      "/path/to/test/fixtures/python"
  """
  @spec language_dir(atom()) :: String.t()
  def language_dir(language) do
    Path.join(@fixtures_dir, Atom.to_string(language))
  end

  @doc """
  Get the full path to a fixture file.

  ## Examples

      iex> FixtureHelper.fixture_path(:python, "test.py")
      "/path/to/test/fixtures/python/test.py"
  """
  @spec fixture_path(atom(), String.t()) :: String.t()
  def fixture_path(language, filename) do
    Path.join(language_dir(language), filename)
  end

  @doc """
  Load a specific fixture.

  Returns a map with:
  - `:name` - Fixture name (without extension)
  - `:source_file` - Full path to source file
  - `:source` - Source code content
  - `:expected_ast` - Expected MetaAST (if exists)
  - `:language` - Language atom

  ## Examples

      iex> {:ok, fixture} = FixtureHelper.load_fixture(:python, "simple_arithmetic")
      iex> fixture.name
      "simple_arithmetic"
      iex> is_binary(fixture.source)
      true
  """
  @spec load_fixture(atom(), String.t()) ::
          {:ok, map()} | {:error, :not_found | :invalid_fixture}
  def load_fixture(language, name) do
    dir = language_dir(language)
    extension = get_extension(language)

    source_file = Path.join(dir, name <> extension)

    if File.exists?(source_file) do
      source = File.read!(source_file)
      expected_ast = load_expected_ast(language, name)

      fixture = %{
        name: name,
        source_file: source_file,
        source: source,
        expected_ast: expected_ast,
        language: language
      }

      {:ok, fixture}
    else
      {:error, :not_found}
    end
  end

  @doc """
  Load all fixtures for a language.

  Returns a list of fixture maps.

  ## Examples

      iex> fixtures = FixtureHelper.load_language(:python)
      iex> is_list(fixtures)
      true
  """
  @spec load_language(atom()) :: [map()]
  def load_language(language) do
    dir = language_dir(language)

    if File.dir?(dir) do
      extension = get_extension(language)

      dir
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, extension))
      |> Enum.map(fn file ->
        name = Path.rootname(file)

        case load_fixture(language, name) do
          {:ok, fixture} -> fixture
          {:error, _} -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)
    else
      []
    end
  end

  @doc """
  Load all fixtures across all languages.

  Returns a map of language => list of fixtures.

  ## Examples

      iex> all = FixtureHelper.load_all()
      iex> is_map(all)
      true
  """
  @spec load_all() :: %{atom() => [map()]}
  def load_all do
    languages = [:python, :javascript, :elixir, :ruby, :go, :rust, :typescript]

    Enum.reduce(languages, %{}, fn lang, acc ->
      fixtures = load_language(lang)

      if fixtures != [] do
        Map.put(acc, lang, fixtures)
      else
        acc
      end
    end)
  end

  @doc """
  Create a fixture directory structure for a language.

  ## Examples

      iex> FixtureHelper.create_language_dir(:python)
      :ok
  """
  @spec create_language_dir(atom()) :: :ok
  def create_language_dir(language) do
    dir = language_dir(language)
    expected_dir = Path.join(dir, "expected")

    File.mkdir_p!(dir)
    File.mkdir_p!(expected_dir)

    :ok
  end

  @doc """
  Save a fixture file and optionally its expected AST.

  ## Examples

      iex> FixtureHelper.save_fixture(:python, "test", "x + 5")
      :ok

      iex> ast = {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}}
      iex> FixtureHelper.save_fixture(:python, "test", "x + 5", ast)
      :ok
  """
  @spec save_fixture(atom(), String.t(), String.t(), term() | nil) :: :ok
  def save_fixture(language, name, source, expected_ast \\ nil) do
    create_language_dir(language)

    extension = get_extension(language)
    source_file = fixture_path(language, name <> extension)

    File.write!(source_file, source)

    if expected_ast do
      save_expected_ast(language, name, expected_ast)
    end

    :ok
  end

  @doc """
  Validate that a fixture's expected AST matches actual parsing result.

  ## Examples

      iex> {:ok, fixture} = FixtureHelper.load_fixture(:python, "test")
      iex> FixtureHelper.validate_fixture(fixture, actual_ast)
      :ok
  """
  @spec validate_fixture(map(), term()) :: :ok | {:error, {:mismatch, term(), term()}}
  def validate_fixture(%{expected_ast: nil}, _actual_ast) do
    # No expected AST to compare
    :ok
  end

  def validate_fixture(%{expected_ast: expected}, actual_ast) do
    if expected == actual_ast do
      :ok
    else
      {:error, {:mismatch, expected, actual_ast}}
    end
  end

  @doc """
  Get statistics about available fixtures.

  ## Examples

      iex> stats = FixtureHelper.stats()
      iex> stats.total_fixtures
      42
  """
  @spec stats() :: map()
  def stats do
    all = load_all()

    %{
      total_languages: map_size(all),
      total_fixtures: all |> Map.values() |> List.flatten() |> length(),
      by_language:
        Enum.map(all, fn {lang, fixtures} ->
          {lang,
           %{
             count: length(fixtures),
             with_expected: Enum.count(fixtures, & &1.expected_ast)
           }}
        end)
        |> Enum.into(%{})
    }
  end

  # Private helpers

  defp get_extension(:python), do: ".py"
  defp get_extension(:javascript), do: ".js"
  defp get_extension(:typescript), do: ".ts"
  defp get_extension(:elixir), do: ".ex"
  defp get_extension(:ruby), do: ".rb"
  defp get_extension(:go), do: ".go"
  defp get_extension(:rust), do: ".rs"
  defp get_extension(_), do: ".txt"

  defp load_expected_ast(language, name) do
    expected_file = Path.join([language_dir(language), "expected", name <> ".exs"])

    if File.exists?(expected_file) do
      {ast, _bindings} = Code.eval_file(expected_file)
      ast
    else
      nil
    end
  end

  defp save_expected_ast(language, name, ast) do
    expected_dir = Path.join(language_dir(language), "expected")
    File.mkdir_p!(expected_dir)

    expected_file = Path.join(expected_dir, name <> ".exs")
    content = inspect(ast, pretty: true, limit: :infinity)
    File.write!(expected_file, content)
  end
end
