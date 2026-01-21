defmodule Metastatic.Supplemental.CompatibilityMatrix do
  @moduledoc """
  Provides a compatibility matrix showing which supplemental modules
  support which constructs for each language.

  This module helps developers understand cross-language support and
  identify gaps in supplemental coverage.

  ## Examples

      # Get full matrix
      matrix = CompatibilityMatrix.build()

      # Check if a construct is supported in a language
      CompatibilityMatrix.supported?(:actor_call, :python)
      # => true (via Pykka supplemental)

      # Get all languages supporting a construct
      CompatibilityMatrix.languages_for_construct(:actor_call)
      # => [:python]

      # Get all constructs supported in a language
      CompatibilityMatrix.constructs_for_language(:python)
      # => [:actor_call, :actor_cast, :spawn_actor, :async_await, ...]
  """

  alias Metastatic.Supplemental.Registry

  @type construct :: atom()
  @type language :: atom()
  @type matrix :: %{
          construct => %{language => [module_name :: atom()]}
        }

  @doc """
  Builds the full compatibility matrix from registered supplementals.

  Returns a nested map structure:
  - First level: construct name (e.g., :actor_call)
  - Second level: language (e.g., :python)
  - Value: list of modules providing support

  ## Examples

      iex> matrix = CompatibilityMatrix.build()
      iex> matrix[:actor_call][:python]
      [Metastatic.Supplemental.Python.Pykka]
  """
  @spec build() :: matrix()
  def build do
    Registry.list_all()
    |> Enum.reduce(%{}, fn {module, info}, acc ->
      # For each construct supported by this module
      Enum.reduce(info.constructs, acc, fn construct, acc2 ->
        # For the target language of this module
        lang = info.target_language

        # Add module to the list of providers for this construct+language
        acc2
        |> Map.put_new(construct, %{})
        |> update_in([construct], fn lang_map ->
          Map.update(lang_map, lang, [module], &[module | &1])
        end)
      end)
    end)
  end

  @doc """
  Checks if a construct is supported in a target language.

  ## Examples

      iex> CompatibilityMatrix.supported?(:actor_call, :python)
      true

      iex> CompatibilityMatrix.supported?(:actor_call, :go)
      false
  """
  @spec supported?(construct(), language()) :: boolean()
  def supported?(construct, language) do
    construct in Registry.available_constructs(language)
  end

  @doc """
  Lists all languages that support a given construct.

  ## Examples

      iex> CompatibilityMatrix.languages_for_construct(:actor_call)
      [:python]

      iex> CompatibilityMatrix.languages_for_construct(:unknown_construct)
      []
  """
  @spec languages_for_construct(construct()) :: [language()]
  def languages_for_construct(construct) do
    build()
    |> Map.get(construct, %{})
    |> Map.keys()
    |> Enum.sort()
  end

  @doc """
  Lists all constructs supported in a target language.

  ## Examples

      iex> constructs = CompatibilityMatrix.constructs_for_language(:python)
      iex> :actor_call in constructs
      true

      iex> CompatibilityMatrix.constructs_for_language(:unknown_language)
      []
  """
  @spec constructs_for_language(language()) :: [construct()]
  def constructs_for_language(language) do
    Registry.available_constructs(language)
    |> Enum.sort()
  end

  @doc """
  Gets supplemental modules providing a construct for a language.

  ## Examples

      iex> CompatibilityMatrix.providers_for(:actor_call, :python)
      [Metastatic.Supplemental.Python.Pykka]

      iex> CompatibilityMatrix.providers_for(:unknown, :python)
      []
  """
  @spec providers_for(construct(), language()) :: [module()]
  def providers_for(construct, language) do
    build()
    |> get_in([construct, language])
    |> Kernel.||([])
    |> Enum.sort()
  end

  @doc """
  Generates a text-based compatibility matrix table.

  Shows which constructs are supported in which languages.

  ## Options

    * `:format` - Output format `:text` (default) or `:markdown`

  ## Examples

      iex> table = CompatibilityMatrix.format_table()
      iex> is_binary(table)
      true
  """
  @spec format_table(keyword()) :: String.t()
  def format_table(opts \\ []) do
    format = Keyword.get(opts, :format, :text)
    matrix = build()

    # Get all unique constructs and languages
    constructs = matrix |> Map.keys() |> Enum.sort()
    languages = get_all_languages(matrix)

    case format do
      :markdown -> format_markdown_table(constructs, languages, matrix)
      :text -> format_text_table(constructs, languages, matrix)
    end
  end

  @doc """
  Generates a detailed report showing all supplementals and their support.

  ## Examples

      iex> report = CompatibilityMatrix.detailed_report()
      iex> is_binary(report)
      true
  """
  @spec detailed_report() :: String.t()
  def detailed_report do
    all_supplementals = Registry.list_all()

    lines = [
      "Supplemental Module Compatibility Report",
      "=========================================",
      ""
    ]

    lines =
      if map_size(all_supplementals) == 0 do
        lines ++ ["No supplemental modules registered."]
      else
        lines ++ format_supplementals_detail(all_supplementals)
      end

    Enum.join(lines, "\n")
  end

  # Private Functions

  defp get_all_languages(matrix) do
    matrix
    |> Map.values()
    |> Enum.flat_map(&Map.keys/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp format_markdown_table(constructs, languages, _matrix) do
    # Header
    header = "| Construct | " <> Enum.join(languages, " | ") <> " |"
    separator = "|" <> String.duplicate("---|", length(languages) + 1)

    # Rows
    rows =
      Enum.map(constructs, fn construct ->
        cells =
          Enum.map(languages, fn lang ->
            if supported?(construct, lang), do: "✓", else: "-"
          end)

        "| #{construct} | " <> Enum.join(cells, " | ") <> " |"
      end)

    Enum.join([header, separator] ++ rows, "\n")
  end

  defp format_text_table(constructs, languages, _matrix) do
    # Calculate column widths
    construct_width =
      constructs |> Enum.map(&String.length(to_string(&1))) |> Enum.max(default: 10)

    construct_width = max(construct_width, 10)

    lang_width = 8

    # Header
    header =
      String.pad_trailing("Construct", construct_width) <>
        "  " <>
        Enum.map_join(languages, "  ", fn lang ->
          String.pad_trailing(to_string(lang), lang_width)
        end)

    separator = String.duplicate("-", String.length(header))

    # Rows
    rows =
      Enum.map(constructs, fn construct ->
        cells =
          Enum.map(languages, fn lang ->
            marker = if supported?(construct, lang), do: "✓", else: "-"
            String.pad_trailing(marker, lang_width)
          end)

        String.pad_trailing(to_string(construct), construct_width) <>
          "  " <> Enum.join(cells, "  ")
      end)

    Enum.join([header, separator] ++ rows, "\n")
  end

  defp format_supplementals_detail(supplementals) do
    supplementals
    |> Enum.sort_by(fn {module, _} -> module end)
    |> Enum.flat_map(fn {module, info} ->
      [
        "Module: #{inspect(module)}",
        "  Target Language: #{info.target_language}",
        "  Constructs: #{Enum.join(info.constructs, ", ")}",
        "  Dependencies: #{format_dependencies(info.dependencies)}",
        ""
      ]
    end)
  end

  defp format_dependencies(deps) when map_size(deps) == 0, do: "(none)"

  defp format_dependencies(deps) do
    Enum.map_join(deps, ", ", fn {lib, version} -> "#{lib} #{version}" end)
  end
end
