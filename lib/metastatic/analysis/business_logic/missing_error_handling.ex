defmodule Metastatic.Analysis.BusinessLogic.MissingErrorHandling do
  @moduledoc """
  Detects pattern matching on success cases without error handling.

  This analyzer identifies code that pattern matches on a success value (typically
  a tuple or enum variant) without handling the potential error case, which can
  lead to runtime crashes.

  ## Cross-Language Applicability

  This pattern applies to languages with pattern matching and Result/Option types:

  - **Elixir**: Matching `{:ok, value}` without handling `{:error, reason}`
  - **Rust**: Unwrapping `Result<T, E>` with `.unwrap()` or matching only `Ok(v)`
  - **OCaml/F#**: Matching only `Some(v)` without handling `None`
  - **Scala**: Pattern matching on `Success` without `Failure`
  - **Haskell**: Pattern matching on `Right` without `Left`

  ## Examples

  ### Bad (Elixir)

      {:ok, user} = Accounts.get_user(id)  # Will crash if error returned

  ### Good (Elixir)

      case Accounts.get_user(id) do
        {:ok, user} -> user
        {:error, reason} -> handle_error(reason)
      end

      # Or with pattern
      with {:ok, user} <- Accounts.get_user(id) do
        user
      end

  ### Bad (Rust)

      let user = get_user(id).unwrap();  // Panics on error

  ### Good (Rust)

      let user = match get_user(id) {
          Ok(u) => u,
          Err(e) => handle_error(e),
      };

  ## Detection Strategy

  Detects pattern matching nodes where:
  1. The pattern is a success variant (e.g., tuple with `:ok` atom, or similar markers)
  2. No corresponding error handling pattern exists in the same scope
  """

  @behaviour Metastatic.Analysis.Analyzer

  alias Metastatic.Analysis.Analyzer

  # Common success markers across languages
  @success_markers [:ok, :some, :right, :success]

  @impl true
  def info do
    %{
      name: :missing_error_handling,
      category: :correctness,
      description: "Detects pattern matching on success without error handling",
      severity: :warning,
      explanation: """
      Pattern matching directly on success cases without handling errors can
      lead to runtime crashes. Always handle both success and error cases, or
      use safe unwrapping mechanisms provided by your language.

      Consider using:
      - Explicit case/match with all branches
      - Safe unwrapping (e.g., `unwrap_or`, `match`, `with`)
      - Result/Option combinators (map, and_then, etc.)
      """,
      configurable: false
    }
  end

  @impl true
  # New 3-tuple format: {:pattern_match, meta, [scrutinee | match_arms]}
  def analyze({:pattern_match, meta, [pattern | _rest]} = node, _context) when is_list(meta) do
    if success_pattern_without_error?(pattern) do
      [
        Analyzer.issue(
          analyzer: __MODULE__,
          category: :correctness,
          severity: :warning,
          message: "Pattern match on success case without error handling can cause crashes",
          node: node,
          metadata: %{pattern: pattern}
        )
      ]
    else
      []
    end
  end

  # Legacy format for backwards compatibility
  def analyze({:pattern_match, pattern, _value} = node, _context) do
    if success_pattern_without_error?(pattern) do
      [
        Analyzer.issue(
          analyzer: __MODULE__,
          category: :correctness,
          severity: :warning,
          message: "Pattern match on success case without error handling can cause crashes",
          node: node,
          metadata: %{pattern: pattern}
        )
      ]
    else
      []
    end
  end

  def analyze(_node, _context), do: []

  # ----- Private Helpers -----

  # Check if pattern is a success pattern without error handling
  # This looks for patterns like {:ok, value} or similar success markers
  defp success_pattern_without_error?(pattern) do
    case pattern do
      # Tuple pattern with success marker: {:ok, value}
      {:list, [marker | _]} when is_tuple(marker) ->
        case marker do
          {:literal, :atom, atom} when atom in @success_markers -> true
          _ -> false
        end

      # Map pattern with success marker
      {:map, fields} when is_list(fields) ->
        Enum.any?(fields, fn
          {{:literal, :atom, key}, _value} when key in @success_markers -> true
          _ -> false
        end)

      _ ->
        false
    end
  end
end
