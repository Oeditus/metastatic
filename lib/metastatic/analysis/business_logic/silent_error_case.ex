defmodule Metastatic.Analysis.BusinessLogic.SilentErrorCase do
  @moduledoc """
  Detects conditional statements that only handle the success case.

  This analyzer identifies conditionals where only the success/truthy branch is
  handled without a corresponding error/falsy branch or catch-all, potentially
  leading to silent failures.

  ## Cross-Language Applicability

  This is a universal pattern that applies to all languages with conditionals:

  - **Python**: `if` without `else` when handling error-prone operations
  - **JavaScript**: `if` without `else` when handling promises/results
  - **Elixir**: `case` with only `{:ok, _}` branch
  - **Rust**: `match` with only `Ok(_)` branch
  - **Go**: Checking only success case without error handling

  ## Examples

  ### Bad (Elixir)

      case Accounts.get_user(id) do
        {:ok, user} -> user
      end
      # What happens if error is returned?

  ### Good (Elixir)

      case Accounts.get_user(id) do
        {:ok, user} -> user
        {:error, _} -> nil
      end

  ### Bad (Python)

      result = get_user(id)
      if result.success:
          return result.value
      # What if not success?

  ### Good (Python)

      result = get_user(id)
      if result.success:
          return result.value
      else:
          return None

  ### Bad (Rust)

      match get_user(id) {
          Ok(user) => user,
      }  // Compile error - non-exhaustive match

  ### Good (Rust)

      match get_user(id) {
          Ok(user) => user,
          Err(e) => handle_error(e),
      }

  ## Detection Strategy

  Checks for:
  1. Conditionals with only a "then" branch (no "else")
  2. Pattern matching with only success patterns and no catch-all
  3. Missing error handling paths in multi-branch conditionals
  """

  @behaviour Metastatic.Analysis.Analyzer

  alias Metastatic.Analysis.Analyzer

  @impl true
  def info do
    %{
      name: :silent_error_case,
      category: :correctness,
      description: "Detects conditionals that only handle the success case",
      severity: :warning,
      explanation: """
      Conditional statements that only handle success cases without providing
      error handling or catch-all branches can lead to silent failures and
      unexpected behavior.

      Always provide:
      - An else branch for if statements handling error-prone operations
      - Error/catch-all branches in pattern matching
      - Explicit handling of all possible outcomes
      """,
      configurable: false
    }
  end

  @impl true
  def analyze({:conditional, condition, _then_branch, else_branch} = node, _context) do
    # Check if condition looks like it's checking a success case
    # and there's no else branch to handle the error case
    if success_condition?(condition) and missing_else_branch?(else_branch) do
      [
        Analyzer.issue(
          analyzer: __MODULE__,
          category: :correctness,
          severity: :warning,
          message: "Conditional only handles success case without error or catch-all branch",
          node: node,
          metadata: %{condition: condition}
        )
      ]
    else
      []
    end
  end

  def analyze(_node, _context), do: []

  # ----- Private Helpers -----

  # Check if condition appears to be checking for a success case
  defp success_condition?(condition) do
    case condition do
      # Pattern match against success tuple
      {:pattern_match, pattern, _value} ->
        has_success_marker?(pattern)

      # Binary op checking equality with success marker
      {:binary_op, :comparison, :==, _left, {:literal, :atom, atom}}
      when atom in [:ok, :some, :right, :success] ->
        true

      _ ->
        false
    end
  end

  # Check if pattern contains success markers like :ok, :some, etc.
  defp has_success_marker?(pattern) do
    case pattern do
      {:list, [marker | _]} when is_tuple(marker) ->
        case marker do
          {:literal, :atom, atom} when atom in [:ok, :some, :right, :success] -> true
          _ -> false
        end

      {:map, fields} when is_list(fields) ->
        Enum.any?(fields, fn
          {{:literal, :atom, key}, _value} when key in [:ok, :some, :right, :success] ->
            true

          _ ->
            false
        end)

      _ ->
        false
    end
  end

  # Check if else branch is missing or empty
  defp missing_else_branch?(else_branch) do
    case else_branch do
      nil -> true
      {:block, []} -> true
      _ -> false
    end
  end
end
