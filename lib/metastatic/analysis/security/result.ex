defmodule Metastatic.Analysis.Security.Result do
  @moduledoc """
  Result structure for security vulnerability detection.

  Contains information about detected security vulnerabilities,
  their severity, and remediation recommendations.

  ## Fields

  - `:has_vulnerabilities?` - Boolean indicating if vulnerabilities were found
  - `:vulnerabilities` - List of detected vulnerability details
  - `:summary` - Human-readable summary of findings
  - `:total_vulnerabilities` - Count of detected vulnerabilities
  - `:by_severity` - Map of counts by severity
  - `:by_category` - Map of counts by vulnerability category

  ## Vulnerability Categories

  - `:injection` - SQL injection, command injection, XSS
  - `:unsafe_deserialization` - pickle.loads, eval, exec
  - `:hardcoded_secret` - Passwords, API keys in code
  - `:weak_crypto` - MD5, SHA1, weak random
  - `:path_traversal` - Unchecked file paths
  - `:insecure_protocol` - HTTP instead of HTTPS

  ## Examples

      iex> result = Metastatic.Analysis.Security.Result.new([])
      iex> result.has_vulnerabilities?
      false

      iex> vulns = [%{category: :injection, severity: :critical, description: "test"}]
      iex> result = Metastatic.Analysis.Security.Result.new(vulns)
      iex> result.has_vulnerabilities?
      true
  """

  @type vulnerability :: %{
          category: category(),
          severity: severity(),
          description: String.t(),
          recommendation: String.t(),
          cwe: integer() | nil,
          context: term()
        }

  @type category ::
          :injection
          | :unsafe_deserialization
          | :hardcoded_secret
          | :weak_crypto
          | :path_traversal
          | :insecure_protocol

  @type severity :: :critical | :high | :medium | :low

  @type t :: %__MODULE__{
          has_vulnerabilities?: boolean(),
          vulnerabilities: [vulnerability()],
          summary: String.t(),
          total_vulnerabilities: non_neg_integer(),
          by_severity: %{severity() => non_neg_integer()},
          by_category: %{category() => non_neg_integer()}
        }

  defstruct has_vulnerabilities?: false,
            vulnerabilities: [],
            summary: "",
            total_vulnerabilities: 0,
            by_severity: %{},
            by_category: %{}

  @doc """
  Creates a new result from a list of vulnerabilities.

  ## Examples

      iex> Metastatic.Analysis.Security.Result.new([])
      %Metastatic.Analysis.Security.Result{has_vulnerabilities?: false, summary: "No security vulnerabilities detected"}

      iex> vulns = [%{category: :injection, severity: :critical, description: "test", recommendation: "fix", cwe: nil, context: nil}]
      iex> result = Metastatic.Analysis.Security.Result.new(vulns)
      iex> result.has_vulnerabilities?
      true
  """
  @spec new([vulnerability()]) :: t()
  def new(vulnerabilities) when is_list(vulnerabilities) do
    has_vulnerabilities? = length(vulnerabilities) > 0
    by_severity = count_by_severity(vulnerabilities)
    by_category = count_by_category(vulnerabilities)

    %__MODULE__{
      has_vulnerabilities?: has_vulnerabilities?,
      vulnerabilities: vulnerabilities,
      summary: build_summary(vulnerabilities, by_severity),
      total_vulnerabilities: length(vulnerabilities),
      by_severity: by_severity,
      by_category: by_category
    }
  end

  @doc """
  Creates a result with no vulnerabilities.

  ## Examples

      iex> result = Metastatic.Analysis.Security.Result.no_vulnerabilities()
      iex> result.has_vulnerabilities?
      false
  """
  @spec no_vulnerabilities() :: t()
  def no_vulnerabilities do
    new([])
  end

  @doc """
  Converts result to JSON-compatible map.

  ## Examples

      iex> result = Metastatic.Analysis.Security.Result.new([])
      iex> map = Metastatic.Analysis.Security.Result.to_map(result)
      iex> is_map(map)
      true
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = result) do
    %{
      has_vulnerabilities: result.has_vulnerabilities?,
      summary: result.summary,
      total_vulnerabilities: result.total_vulnerabilities,
      by_severity: result.by_severity,
      by_category: result.by_category,
      vulnerabilities: result.vulnerabilities
    }
  end

  # Private helpers

  defp count_by_severity(vulns) do
    Enum.reduce(vulns, %{}, fn %{severity: sev}, acc ->
      Map.update(acc, sev, 1, &(&1 + 1))
    end)
  end

  defp count_by_category(vulns) do
    Enum.reduce(vulns, %{}, fn %{category: cat}, acc ->
      Map.update(acc, cat, 1, &(&1 + 1))
    end)
  end

  defp build_summary([], _by_severity) do
    "No security vulnerabilities detected"
  end

  defp build_summary(vulns, by_severity) do
    total = length(vulns)

    severity_summary =
      by_severity
      |> Enum.sort_by(fn {sev, _} -> severity_order(sev) end, :desc)
      |> Enum.map(fn {sev, count} ->
        "#{count} #{sev}"
      end)
      |> Enum.join(", ")

    "Found #{total} security vulnerability(ies): #{severity_summary}"
  end

  defp severity_order(:critical), do: 4
  defp severity_order(:high), do: 3
  defp severity_order(:medium), do: 2
  defp severity_order(:low), do: 1
end
