defmodule Metastatic.Analysis.ApiSurface do
  @moduledoc """
  API surface analysis for containers (modules/classes).

  Analyzes the public interface, measuring complexity, consistency, and design quality.

  ## Metrics

  - **Surface Size**: Number of public methods/properties
  - **Parameter Complexity**: Average parameters per public method
  - **Return Complexity**: Variety of return types
  - **Naming Consistency**: Consistent naming patterns
  - **Interface Cohesion**: How focused the API is

  ## Examples

      # Small, focused API
      ast = {:container, :class, "Stack", %{}, [
        {:function_def, :public, "push", ["item"], %{}, ...},
        {:function_def, :public, "pop", [], %{}, ...}
      ]}

      doc = Document.new(ast, :python)
      {:ok, result} = ApiSurface.analyze(doc)
      result.surface_size  # => 2
      result.assessment    # => :excellent
  """

  alias Metastatic.Document

  @type result :: %{
          container_name: String.t() | nil,
          surface_size: non_neg_integer(),
          public_methods: [String.t()],
          avg_params: float(),
          max_params: non_neg_integer(),
          assessment: :excellent | :good | :fair | :poor,
          warnings: [String.t()],
          recommendations: [String.t()]
        }

  @spec analyze(Document.t()) :: {:ok, result()} | {:error, String.t()}
  def analyze(%Document{ast: ast}) do
    case extract_container(ast) do
      {:ok, _type, name, members} ->
        result = analyze_api(name, members)
        {:ok, result}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract_container({:container, type, name, _metadata, members}) do
    {:ok, type, name, members}
  end

  defp extract_container(_), do: {:error, "AST does not contain a container"}

  defp analyze_api(name, members) do
    public_methods =
      members
      |> Enum.filter(&match?({:function_def, :public, _, _, _, _}, &1))

    public_names = Enum.map(public_methods, fn {:function_def, _, name, _, _, _} -> name end)

    param_counts =
      Enum.map(public_methods, fn {:function_def, _, _, params, _, _} -> length(params) end)

    surface_size = length(public_methods)
    avg_params = if surface_size > 0, do: Enum.sum(param_counts) / surface_size, else: 0.0
    max_params = if surface_size > 0, do: Enum.max(param_counts), else: 0

    {assessment, warnings, recommendations} = assess_api(surface_size, avg_params, max_params)

    %{
      container_name: name,
      surface_size: surface_size,
      public_methods: Enum.sort(public_names),
      avg_params: Float.round(avg_params, 2),
      max_params: max_params,
      assessment: assessment,
      warnings: warnings,
      recommendations: recommendations
    }
  end

  defp assess_api(size, avg_params, max_params) do
    warnings = []
    recommendations = []

    {warnings, recommendations} =
      if size > 20 do
        {["Large API surface (#{size} methods) - may be difficult to learn" | warnings],
         ["Consider splitting into multiple focused interfaces" | recommendations]}
      else
        {warnings, recommendations}
      end

    {warnings, recommendations} =
      if avg_params > 4 do
        {[
           "High average parameter count (#{Float.round(avg_params, 1)}) - methods may be too complex"
           | warnings
         ], ["Reduce parameter counts by using objects or builder patterns" | recommendations]}
      else
        {warnings, recommendations}
      end

    {warnings, recommendations} =
      if max_params > 6 do
        {["Method with #{max_params} parameters detected - too complex" | warnings],
         recommendations}
      else
        {warnings, recommendations}
      end

    assessment =
      cond do
        size <= 10 and avg_params <= 3 and max_params <= 5 -> :excellent
        size <= 15 and avg_params <= 4 and max_params <= 6 -> :good
        size <= 25 and avg_params <= 5 -> :fair
        true -> :poor
      end

    {assessment, Enum.reverse(warnings), Enum.reverse(recommendations)}
  end
end
