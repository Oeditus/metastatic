defmodule Metastatic.Analysis.Duplication.Reporter do
  @moduledoc """
  Reporting and formatting for code duplication detection results.

  Provides multiple output formats:
  - Text format (human-readable)
  - JSON format (machine-readable)
  - Detailed format (comprehensive analysis)

  ## Usage

      alias Metastatic.Analysis.Duplication.{Result, Reporter}

      # Format a single result
      Reporter.format(result, :text)
      Reporter.format(result, :json)
      Reporter.format(result, :detailed)

      # Format clone groups
      Reporter.format_groups(groups, :text)

  ## Examples

      iex> result = Metastatic.Analysis.Duplication.Result.exact_clone()
      iex> text = Metastatic.Analysis.Duplication.Reporter.format(result, :text)
      iex> String.contains?(text, "Type I")
      true
  """

  alias Metastatic.Analysis.Duplication.Result

  @type format :: :text | :json | :detailed

  @doc """
  Formats a duplication detection result in the specified format.

  ## Formats

  - `:text` - Human-readable text format
  - `:json` - JSON format for programmatic processing
  - `:detailed` - Comprehensive text format with all metadata

  ## Examples

      iex> result = Metastatic.Analysis.Duplication.Result.exact_clone()
      iex> text = Metastatic.Analysis.Duplication.Reporter.format(result, :text)
      iex> is_binary(text)
      true

      iex> result = Metastatic.Analysis.Duplication.Result.no_duplicate()
      iex> text = Metastatic.Analysis.Duplication.Reporter.format(result, :text)
      iex> String.contains?(text, "No duplicate")
      true
  """
  @spec format(Result.t(), format()) :: String.t()
  def format(%Result{} = result, format_type \\ :text) do
    case format_type do
      :text -> format_text(result)
      :json -> format_json(result)
      :detailed -> format_detailed(result)
    end
  end

  @doc """
  Formats multiple clone groups in the specified format.

  ## Examples

      iex> groups = []
      iex> text = Metastatic.Analysis.Duplication.Reporter.format_groups(groups, :text)
      iex> String.contains?(text, "No clone groups")
      true
  """
  @spec format_groups([map()], format()) :: String.t()
  def format_groups(groups, format_type \\ :text) when is_list(groups) do
    case format_type do
      :text -> format_groups_text(groups)
      :json -> format_groups_json(groups)
      :detailed -> format_groups_detailed(groups)
    end
  end

  # Private functions

  # Text format for single result
  defp format_text(%Result{duplicate?: false}) do
    "No duplicate detected"
  end

  defp format_text(%Result{duplicate?: true} = result) do
    clone_type_str = format_clone_type(result.clone_type)
    similarity_str = format_similarity(result.similarity_score)

    """
    Duplicate detected: #{clone_type_str}
    Similarity score: #{similarity_str}
    #{format_locations(result.locations)}
    """
    |> String.trim()
  end

  # JSON format for single result
  defp format_json(%Result{} = result) do
    data = %{
      duplicate: result.duplicate?,
      clone_type: result.clone_type,
      similarity_score: result.similarity_score,
      locations: result.locations,
      fingerprints: result.fingerprints,
      metrics: result.metrics
    }

    Jason.encode!(data, pretty: true)
  end

  # Detailed format for single result
  defp format_detailed(%Result{duplicate?: false}) do
    "No duplicate detected"
  end

  defp format_detailed(%Result{duplicate?: true} = result) do
    clone_type_str = format_clone_type(result.clone_type)
    similarity_str = format_similarity(result.similarity_score)

    sections = [
      "Duplicate Detection Result",
      "=" |> String.duplicate(50),
      "",
      "Clone Type: #{clone_type_str}",
      "Similarity: #{similarity_str}",
      "",
      "Locations:",
      format_locations_detailed(result.locations),
      "",
      "Fingerprints:",
      format_fingerprints(result.fingerprints),
      "",
      "Metrics:",
      format_metrics(result.metrics)
    ]

    Enum.join(sections, "\n")
  end

  # Text format for clone groups
  defp format_groups_text([]) do
    "No clone groups found"
  end

  defp format_groups_text(groups) do
    header = """
    Found #{length(groups)} clone group(s)
    #{"=" |> String.duplicate(50)}
    """

    group_strs =
      groups
      |> Enum.with_index(1)
      |> Enum.map(fn {group, idx} ->
        format_group_text(group, idx)
      end)

    [header | group_strs]
    |> Enum.join("\n\n")
  end

  defp format_group_text(group, idx) do
    clone_type_str = format_clone_type(group.clone_type)

    """
    Clone Group #{idx}
    Type: #{clone_type_str}
    Size: #{group.size} documents
    Locations:
    #{format_group_locations(group.locations)}
    """
    |> String.trim()
  end

  # JSON format for clone groups
  defp format_groups_json(groups) do
    data = %{
      clone_groups: groups,
      total_groups: length(groups),
      total_clones: Enum.sum(Enum.map(groups, & &1.size))
    }

    Jason.encode!(data, pretty: true)
  end

  # Detailed format for clone groups
  defp format_groups_detailed([]) do
    "No clone groups found"
  end

  defp format_groups_detailed(groups) do
    header = """
    Clone Group Analysis
    #{"=" |> String.duplicate(50)}

    Total Groups: #{length(groups)}
    Total Clones: #{Enum.sum(Enum.map(groups, & &1.size))}

    """

    group_strs =
      groups
      |> Enum.with_index(1)
      |> Enum.map(fn {group, idx} ->
        format_group_detailed(group, idx)
      end)

    [header | group_strs]
    |> Enum.join("\n\n")
  end

  defp format_group_detailed(group, idx) do
    clone_type_str = format_clone_type(group.clone_type)

    """
    Clone Group #{idx}
    #{"-" |> String.duplicate(50)}
    Clone Type: #{clone_type_str}
    Group Size: #{group.size} documents

    Locations:
    #{format_group_locations_detailed(group.locations)}
    """
    |> String.trim()
  end

  # Helper formatters

  defp format_clone_type(:type_i), do: "Type I (Exact Clone)"
  defp format_clone_type(:type_ii), do: "Type II (Renamed Clone)"
  defp format_clone_type(:type_iii), do: "Type III (Near-Miss Clone)"
  defp format_clone_type(:type_iv), do: "Type IV (Semantic Clone)"
  defp format_clone_type(nil), do: "Unknown"
  defp format_clone_type(other), do: "#{other}"

  defp format_similarity(nil), do: "N/A"
  defp format_similarity(score) when is_float(score), do: "#{Float.round(score, 2)}"
  defp format_similarity(score), do: "#{score}"

  defp format_locations([]), do: "No location information"

  defp format_locations(locations) when is_list(locations) do
    locations
    |> Enum.with_index(1)
    |> Enum.map(fn {loc, idx} ->
      "  [#{idx}] #{format_single_location(loc)}"
    end)
    |> Enum.join("\n")
  end

  defp format_locations(_), do: "Invalid location information"

  defp format_locations_detailed([]), do: "  No location information"

  defp format_locations_detailed(locations) when is_list(locations) do
    locations
    |> Enum.with_index(1)
    |> Enum.map(fn {loc, idx} ->
      file = loc[:file] || "unknown"
      start_line = loc[:start_line] || "?"
      end_line = loc[:end_line] || "?"
      language = loc[:language] || "unknown"

      """
        [#{idx}] File: #{file}
             Lines: #{start_line}-#{end_line}
             Language: #{language}
      """
      |> String.trim()
    end)
    |> Enum.join("\n")
  end

  defp format_locations_detailed(_), do: "  Invalid location information"

  defp format_single_location(loc) when is_map(loc) do
    file = loc[:file] || "unknown"
    start_line = loc[:start_line] || "?"
    end_line = loc[:end_line] || "?"
    language = loc[:language] || "unknown"

    "#{file}:#{start_line}-#{end_line} (#{language})"
  end

  defp format_single_location(_), do: "invalid location"

  defp format_group_locations([]), do: "  No locations"

  defp format_group_locations(locations) when is_list(locations) do
    locations
    |> Enum.map(fn loc ->
      "  - #{format_single_location(loc)}"
    end)
    |> Enum.join("\n")
  end

  defp format_group_locations(_), do: "  Invalid locations"

  defp format_group_locations_detailed([]), do: "  No locations"

  defp format_group_locations_detailed(locations) when is_list(locations) do
    locations
    |> Enum.with_index(1)
    |> Enum.map(fn {loc, idx} ->
      file = loc[:file] || "unknown"
      start_line = loc[:start_line] || "?"
      end_line = loc[:end_line] || "?"
      language = loc[:language] || "unknown"

      "  [#{idx}] #{file}:#{start_line}-#{end_line} (#{language})"
    end)
    |> Enum.join("\n")
  end

  defp format_group_locations_detailed(_), do: "  Invalid locations"

  defp format_fingerprints(nil), do: "  No fingerprints"

  defp format_fingerprints(fps) when is_map(fps) do
    [
      "  Exact: #{String.slice(fps[:exact] || "N/A", 0..15)}...",
      "  Normalized: #{String.slice(fps[:normalized] || "N/A", 0..15)}..."
    ]
    |> Enum.join("\n")
  end

  defp format_fingerprints(_), do: "  Invalid fingerprints"

  defp format_metrics(nil), do: "  No metrics"

  defp format_metrics(metrics) when is_map(metrics) do
    [
      "  Size: #{metrics[:size] || "N/A"} nodes",
      "  Variables: #{metrics[:variables] || "N/A"}",
      "  Complexity: #{metrics[:complexity] || "N/A"}"
    ]
    |> Enum.join("\n")
  end

  defp format_metrics(_), do: "  Invalid metrics"
end
