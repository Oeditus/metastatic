defmodule Metastatic.Analysis.BusinessLogic.DirectStructUpdate do
  @moduledoc """
  Detects direct object/struct updates bypassing validation.

  Universal pattern: updating structured data without validation functions.

  Applies to: Pydantic, Rails validations, ASP.NET validators, Ecto changesets, etc.
  """

  @behaviour Metastatic.Analysis.Analyzer
  alias Metastatic.Analysis.Analyzer

  @impl true
  def info do
    %{
      name: :direct_struct_update,
      category: :correctness,
      description: "Detects object updates without validation",
      severity: :warning,
      explanation: "Use validation functions (changesets, validators) for data integrity",
      configurable: false
    }
  end

  @impl true
  def analyze({:map, _meta, _fields} = node, _context) do
    # Map update - could be struct update bypassing validation
    # This is a simplified detection; real implementation would check context
    [
      Analyzer.issue(
        analyzer: __MODULE__,
        category: :correctness,
        severity: :info,
        message: "Consider using validation (changeset/validator) for struct updates",
        node: node,
        metadata: %{suggestion: "Use validation functions"}
      )
    ]
  end

  def analyze(_node, _context), do: []
end
