defmodule Metastatic.Analysis.BusinessLogic.CallbackHell do
  @moduledoc """
  Detects deeply nested conditional statements (callback hell pattern).

  This analyzer identifies code with excessive nesting of conditionals which
  creates "callback hell" - code that is hard to read, maintain, and reason about.

  ## Cross-Language Applicability

  This pattern is universal and applies to all languages with conditionals:

  - **Python**: Nested if/else chains
  - **JavaScript**: Nested if/else or ternary operators
  - **Elixir**: Nested case statements
  - **Rust**: Nested match expressions
  - **Go**: Nested if/else statements

  ## Examples

  ### Bad (Elixir)

      case get_user(id) do
        {:ok, user} ->
          case get_account(user) do
            {:ok, account} ->
              case process(account) do
                {:ok, result} -> result
              end
          end
      end

  ### Good (Elixir)

      with {:ok, user} <- get_user(id),
           {:ok, account} <- get_account(user),
           {:ok, result} <- process(account) do
        result
      end

  ### Bad (Python)

      if user is not None:
          if user.active:
              if user.has_permission():
                  return True

  ### Good (Python)

      return (user is not None and
              user.active and
              user.has_permission())

  ## Configuration

  - `:max_nesting` - Maximum allowed nesting depth (default: 2)
  """

  @behaviour Metastatic.Analysis.Analyzer

  alias Metastatic.Analysis.Analyzer

  @impl true
  def info do
    %{
      name: :callback_hell,
      category: :readability,
      description: "Detects deeply nested conditional statements",
      severity: :warning,
      explanation: """
      Deeply nested conditional statements create "callback hell" - code that is
      difficult to read, understand, and maintain. Consider refactoring using:

      - Early returns / guard clauses
      - Flattening logic with boolean operators
      - Extracting nested logic into separate functions
      - Using language-specific control flow (e.g., with/monad chaining)
      """,
      configurable: true
    }
  end

  @impl true
  def run_before(context) do
    # Initialize configuration with default max_nesting
    max_nesting = Map.get(context.config, :max_nesting, 2)
    context = Map.put(context, :max_nesting, max_nesting)
    {:ok, context}
  end

  @impl true
  def analyze({:conditional, _meta, children} = node, context) when is_list(children) do
    max_nesting = Map.get(context, :max_nesting, 2)
    nesting_level = count_conditional_nesting(node)

    if nesting_level > max_nesting do
      [
        Analyzer.issue(
          analyzer: __MODULE__,
          category: :readability,
          severity: :warning,
          message:
            "#{nesting_level} levels of nested conditionals - consider refactoring for readability",
          node: node,
          metadata: %{nesting_level: nesting_level, max_allowed: max_nesting}
        )
      ]
    else
      []
    end
  end

  def analyze(_node, _context), do: []

  # ----- Private Helpers -----

  # Count nesting depth of conditionals - 3-tuple format
  defp count_conditional_nesting({:conditional, _meta, [_cond, then_branch, else_branch]}) do
    then_depth = count_nested_conditionals(then_branch)
    else_depth = count_nested_conditionals(else_branch)
    1 + max(then_depth, else_depth)
  end

  defp count_conditional_nesting(_), do: 0

  # Count nested conditionals in a branch - 3-tuple format
  defp count_nested_conditionals({:block, _meta, statements}) when is_list(statements) do
    statements
    |> Enum.map(&count_conditional_nesting/1)
    |> Enum.max(fn -> 0 end)
  end

  defp count_nested_conditionals({:conditional, _meta, _children} = node) do
    count_conditional_nesting(node)
  end

  defp count_nested_conditionals(_), do: 0
end
