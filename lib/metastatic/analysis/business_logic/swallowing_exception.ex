defmodule Metastatic.Analysis.BusinessLogic.SwallowingException do
  @moduledoc """
  Detects exception handling that swallows exceptions without logging or re-raising.

  This analyzer identifies try/catch/rescue blocks that catch exceptions but don't
  log them or re-raise them, which hides errors and makes debugging difficult.

  ## Cross-Language Applicability

  This is a universal anti-pattern in all languages with exception handling:

  - **Python**: `try/except` that silently catches
  - **JavaScript**: `try/catch` without logging
  - **Elixir**: `try/rescue` without logging or re-raising
  - **Java/C#**: `try/catch` with empty catch block
  - **Ruby**: `begin/rescue` without handling
  - **Go**: Ignoring error returns (similar concept)

  ## Examples

  ### Bad (Python)

      try:
          risky_operation()
      except Exception:
          pass  # Silent failure!

  ### Good (Python)

      try:
          risky_operation()
      except Exception as e:
          logger.error(f"Operation failed: {e}")
          raise

  ### Bad (Elixir)

      try do
        risky_operation()
      rescue
        _ -> :error  # Exception hidden!
      end

  ### Good (Elixir)

      try do
        risky_operation()
      rescue
        e ->
          Logger.error("Operation failed", error: inspect(e))
          :error
      end

  ### Bad (JavaScript)

      try {
        riskyOperation();
      } catch (e) {
        return null;  // Exception swallowed
      }

  ### Good (JavaScript)

      try {
        riskyOperation();
      } catch (e) {
        console.error('Operation failed:', e);
        throw e;
      }

  ## Detection Strategy

  Checks exception_handling nodes for:
  1. Catch/rescue handlers that don't contain logging calls
  2. Catch/rescue handlers that don't re-raise the exception
  3. Empty catch blocks
  """

  @behaviour Metastatic.Analysis.Analyzer

  alias Metastatic.Analysis.Analyzer

  # Common logging function names across languages
  @logging_functions [
    :log,
    :error,
    :warn,
    :warning,
    :info,
    :debug,
    :print,
    :println,
    :console,
    :logger
  ]

  # Common re-raise function names
  @reraise_functions [:raise, :reraise, :throw]

  @impl true
  def info do
    %{
      name: :swallowing_exception,
      category: :correctness,
      description: "Detects exception handling without logging or re-raising",
      severity: :warning,
      explanation: """
      Swallowing exceptions without logging or re-raising them hides errors
      and makes debugging nearly impossible. Always ensure exceptions are
      properly handled by:

      - Logging the exception with sufficient context
      - Re-raising the exception if it cannot be handled
      - Providing meaningful error recovery
      - At minimum, logging before returning a fallback value
      """,
      configurable: false
    }
  end

  @impl true
  def analyze({:exception_handling, _try_block, catch_clauses, _finally_block} = node, _context)
      when is_list(catch_clauses) do
    # Check if any catch clause swallows exceptions
    # MetaAST catch clauses are 3-tuples: {exception_type, exception_var, handler_body}
    silent_catches =
      Enum.filter(catch_clauses, fn
        {_exception_type, _exception_var, handler_body} ->
          not has_logging_or_reraise?(handler_body)
      end)

    with [_ | _] <- silent_catches do
      [
        Analyzer.issue(
          analyzer: __MODULE__,
          category: :correctness,
          severity: :warning,
          message:
            "Exception handler swallows exceptions without logging or re-raising - this hides errors",
          node: node,
          metadata: %{silent_catch_count: length(silent_catches)}
        )
      ]
    end
  end

  def analyze(_node, _context), do: []

  # ----- Private Helpers -----

  # Check if a body contains logging or re-raising
  defp has_logging_or_reraise?(body) do
    has_logging?(body) or has_reraise?(body)
  end

  # Recursively check for logging function calls
  defp has_logging?({:block, statements}) when is_list(statements) do
    Enum.any?(statements, &has_logging?/1)
  end

  # Function call - check if it's a logging function
  defp has_logging?({:function_call, func_name, _args}) when is_atom(func_name) do
    func_name in @logging_functions or
      func_name
      |> Atom.to_string()
      |> String.contains?(["log", "error", "warn", "print", "console"])
  end

  # Check nested structures
  defp has_logging?(tuple) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.any?(&has_logging?/1)
  end

  defp has_logging?(list) when is_list(list) do
    Enum.any?(list, &has_logging?/1)
  end

  defp has_logging?(_), do: false

  # Recursively check for re-raise calls
  defp has_reraise?({:block, statements}) when is_list(statements) do
    Enum.any?(statements, &has_reraise?/1)
  end

  # Early return with error - check if it's a reraise
  defp has_reraise?({:early_return, {:function_call, func_name, _}})
       when func_name in @reraise_functions do
    true
  end

  # Function call - check if it's a reraise function
  defp has_reraise?({:function_call, func_name, _args}) when is_atom(func_name) do
    func_name in @reraise_functions
  end

  # Check nested structures
  defp has_reraise?(tuple) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.any?(&has_reraise?/1)
  end

  defp has_reraise?(list) when is_list(list) do
    Enum.any?(list, &has_reraise?/1)
  end

  defp has_reraise?(_), do: false
end
