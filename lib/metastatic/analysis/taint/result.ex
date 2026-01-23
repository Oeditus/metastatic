defmodule Metastatic.Analysis.Taint.Result do
  @moduledoc """
  Result structure for taint analysis.

  Contains information about taint flows from sources to sinks,
  identifying potential security issues from untrusted data.

  ## Fields

  - `:has_taint_flows?` - Boolean indicating if taint flows were found
  - `:taint_flows` - List of detected taint flow paths
  - `:summary` - Human-readable summary of findings
  - `:total_flows` - Count of taint flows
  - `:by_risk` - Map of counts by risk level

  ## Examples

      iex> result = Metastatic.Analysis.Taint.Result.new([])
      iex> result.has_taint_flows?
      false

      iex> flows = [%{source: "input", sink: "eval", risk: :critical}]
      iex> result = Metastatic.Analysis.Taint.Result.new(flows)
      iex> result.has_taint_flows?
      true
  """

  @type taint_flow :: %{
          source: String.t(),
          sink: String.t(),
          risk: risk_level(),
          path: [String.t()],
          recommendation: String.t()
        }

  @type risk_level :: :critical | :high | :medium | :low

  @type t :: %__MODULE__{
          has_taint_flows?: boolean(),
          taint_flows: [taint_flow()],
          summary: String.t(),
          total_flows: non_neg_integer(),
          by_risk: %{risk_level() => non_neg_integer()}
        }

  defstruct has_taint_flows?: false,
            taint_flows: [],
            summary: "",
            total_flows: 0,
            by_risk: %{}

  @doc """
  Creates a new result from a list of taint flows.

  ## Examples

      iex> Metastatic.Analysis.Taint.Result.new([])
      %Metastatic.Analysis.Taint.Result{has_taint_flows?: false, summary: "No taint flows detected"}

      iex> flows = [%{source: "input", sink: "eval", risk: :critical, path: [], recommendation: "sanitize"}]
      iex> result = Metastatic.Analysis.Taint.Result.new(flows)
      iex> result.has_taint_flows?
      true
  """
  @spec new([taint_flow()]) :: t()
  def new(taint_flows) when is_list(taint_flows) do
    has_taint_flows? = length(taint_flows) > 0
    by_risk = count_by_risk(taint_flows)

    %__MODULE__{
      has_taint_flows?: has_taint_flows?,
      taint_flows: taint_flows,
      summary: build_summary(taint_flows, by_risk),
      total_flows: length(taint_flows),
      by_risk: by_risk
    }
  end

  @doc """
  Creates a result with no taint flows.

  ## Examples

      iex> result = Metastatic.Analysis.Taint.Result.no_taint()
      iex> result.has_taint_flows?
      false
  """
  @spec no_taint() :: t()
  def no_taint do
    new([])
  end

  @doc """
  Converts result to JSON-compatible map.

  ## Examples

      iex> result = Metastatic.Analysis.Taint.Result.new([])
      iex> map = Metastatic.Analysis.Taint.Result.to_map(result)
      iex> is_map(map)
      true
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = result) do
    %{
      has_taint_flows: result.has_taint_flows?,
      summary: result.summary,
      total_flows: result.total_flows,
      by_risk: result.by_risk,
      taint_flows: result.taint_flows
    }
  end

  # Private helpers

  defp count_by_risk(flows) do
    Enum.reduce(flows, %{}, fn %{risk: risk}, acc ->
      Map.update(acc, risk, 1, &(&1 + 1))
    end)
  end

  defp build_summary([], _by_risk) do
    "No taint flows detected"
  end

  defp build_summary(flows, by_risk) do
    total = length(flows)

    risk_summary =
      by_risk
      |> Enum.sort_by(fn {risk, _} -> risk_order(risk) end, :desc)
      |> Enum.map(fn {risk, count} ->
        "#{count} #{risk}"
      end)
      |> Enum.join(", ")

    "Found #{total} taint flow(s): #{risk_summary}"
  end

  defp risk_order(:critical), do: 4
  defp risk_order(:high), do: 3
  defp risk_order(:medium), do: 2
  defp risk_order(:low), do: 1
end
