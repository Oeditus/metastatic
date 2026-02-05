defmodule Metastatic.Analysis.Coupling do
  @moduledoc """
  Coupling analysis for containers (modules/classes).

  Measures dependencies between containers. Low coupling is desirable for maintainability.

  ## Coupling Types

  - **Afferent Coupling (Ca)**: Number of containers that depend on this container
  - **Efferent Coupling (Ce)**: Number of containers this container depends on
  - **Instability (I)**: Ce / (Ca + Ce) - ranges from 0 (stable) to 1 (unstable)

  ## Assessment

  - Low coupling (Ce < 5): Excellent - easy to test and maintain
  - Moderate coupling (5 <= Ce < 10): Good - acceptable dependencies
  - High coupling (10 <= Ce < 20): Fair - consider refactoring
  - Very high coupling (Ce >= 20): Poor - difficult to maintain

  ## Examples

      # Low coupling - no external dependencies
      ast = {:container, [container_type: :class, name: "Calculator"], [
        {:function_def, [name: "add", params: ["x", "y"], visibility: :public], [
         {:binary_op, [category: :arithmetic, operator: :+], [{:variable, [], "x"}, {:variable, [], "y"}]}]}
      ]}

      doc = Document.new(ast, :python)
      {:ok, result} = Coupling.analyze(doc)
      result.efferent_coupling  # => 0
      result.assessment         # => :excellent
  """

  alias Metastatic.Document

  @type result :: %{
          container_name: String.t() | nil,
          efferent_coupling: non_neg_integer(),
          dependencies: [String.t()],
          instability: float(),
          assessment: :excellent | :good | :fair | :poor,
          warnings: [String.t()],
          recommendations: [String.t()]
        }

  use Metastatic.Document.Analyzer,
    doc: """
    Analyzes coupling in a document.

    Accepts either a `Metastatic.Document` struct or a `{language, native_ast}` tuple.
    """

  @impl Metastatic.Document.Analyzer
  def handle_analyze(%Document{ast: ast}, _opts \\ []) do
    with {:ok, _type, name, members} <- extract_container(ast),
         do: {:ok, analyze_coupling(name, members)}
  end

  # 3-tuple format
  defp extract_container({:container, meta, [members]}) when is_list(meta) do
    type = Keyword.get(meta, :container_type, :class)
    name = Keyword.get(meta, :name, "anonymous")
    members_list = if is_list(members), do: members, else: [members]
    {:ok, type, name, members_list}
  end

  defp extract_container(_), do: {:error, "AST does not contain a container"}

  defp analyze_coupling(name, members) do
    # Extract dependencies (external types/modules referenced)
    dependencies = extract_dependencies(members) |> Enum.uniq() |> Enum.sort()
    efferent = length(dependencies)

    # Calculate instability (assuming Ca=0 since we don't have cross-file analysis yet)
    instability = if efferent > 0, do: 1.0, else: 0.0

    {assessment, warnings, recommendations} = assess_coupling(efferent)

    %{
      container_name: name,
      efferent_coupling: efferent,
      dependencies: dependencies,
      instability: instability,
      assessment: assessment,
      warnings: warnings,
      recommendations: recommendations
    }
  end

  defp extract_dependencies(members) do
    members
    |> Enum.flat_map(&extract_deps_from_member/1)
    |> Enum.uniq()
  end

  # 3-tuple format
  defp extract_deps_from_member({:function_def, meta, [body]}) when is_list(meta),
    do: extract_deps_from_ast(body)

  defp extract_deps_from_member({:property, meta, [getter, setter]}) when is_list(meta) do
    extract_deps_from_ast(getter) ++ extract_deps_from_ast(setter)
  end

  defp extract_deps_from_member(_), do: []

  defp extract_deps_from_ast(nil), do: []

  defp extract_deps_from_ast(ast) do
    case ast do
      # Function calls to external modules (Module.function pattern) - 3-tuple
      {:attribute_access, _meta, [{:variable, _, module}, _func]}
      when module not in ["self", "this", "@"] ->
        [module]

      # Function call - 3-tuple
      {:function_call, meta, args} when is_list(meta) and is_list(args) ->
        name = Keyword.get(meta, :name, "")
        # Check if it's a qualified call (e.g., "Math.sqrt")
        deps =
          if is_binary(name) and String.contains?(name, ".") do
            [name |> String.split(".") |> hd()]
          else
            []
          end

        deps ++ Enum.flat_map(args, &extract_deps_from_ast/1)

      # Binary op - 3-tuple
      {:binary_op, _meta, [left, right]} ->
        extract_deps_from_ast(left) ++ extract_deps_from_ast(right)

      # Conditional - 3-tuple
      {:conditional, _meta, [cond_expr, then_br, else_br]} ->
        extract_deps_from_ast(cond_expr) ++
          extract_deps_from_ast(then_br) ++
          extract_deps_from_ast(else_br)

      # Block - 3-tuple
      {:block, _meta, stmts} when is_list(stmts) ->
        Enum.flat_map(stmts, &extract_deps_from_ast/1)

      # Assignment - 3-tuple
      {:assignment, _meta, [_target, value]} ->
        extract_deps_from_ast(value)

      # Augmented assignment - 3-tuple
      {:augmented_assignment, _meta, [_target, value]} ->
        extract_deps_from_ast(value)

      # Loop - 3-tuple
      {:loop, meta, children} when is_list(meta) and is_list(children) ->
        Enum.flat_map(children, &extract_deps_from_ast/1)

      _ ->
        []
    end
  end

  defp assess_coupling(efferent) do
    {assessment, warnings, recommendations} =
      cond do
        efferent < 5 ->
          {:excellent, [], ["Low coupling - excellent for maintainability and testing"]}

        efferent < 10 ->
          {:good, [],
           [
             "Moderate coupling - acceptable but monitor growth",
             "Consider dependency injection for better testability"
           ]}

        efferent < 20 ->
          {:fair,
           ["High coupling (#{efferent} dependencies) - may be difficult to test and maintain"],
           [
             "Refactor to reduce dependencies",
             "Use interfaces/protocols to decouple from concrete implementations",
             "Consider the Dependency Inversion Principle"
           ]}

        true ->
          {:poor,
           [
             "Very high coupling (#{efferent} dependencies) - serious maintainability issue",
             "Changes to dependencies will likely require changes to this container"
           ],
           [
             "Major refactoring recommended",
             "Split container into smaller, focused units",
             "Introduce abstractions to reduce direct dependencies",
             "Apply SOLID principles, especially Single Responsibility"
           ]}
      end

    {assessment, warnings, recommendations}
  end
end
