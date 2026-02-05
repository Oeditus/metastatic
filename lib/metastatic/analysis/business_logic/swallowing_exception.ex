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
  # New 3-tuple format: {:exception_handling, meta, [try_block, match_arm1, match_arm2, ...]}
  # The catch clauses are match_arm nodes mixed in with the try_block
  def analyze({:exception_handling, _meta, children} = node, _context)
      when is_list(children) do
    # Extract match_arm nodes which represent catch/rescue clauses
    catch_clauses =
      Enum.filter(children, fn
        {:match_arm, _, _} -> true
        _ -> false
      end)

    # Check if any catch clause swallows exceptions
    silent_catches =
      Enum.filter(catch_clauses, fn
        {:match_arm, meta, body_list} ->
          # match_arm format: {:match_arm, [pattern: p], [body]}
          body = List.last(body_list) || Keyword.get(meta, :body)
          not has_logging_or_reraise?(body)

        _ ->
          false
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

  # Legacy 4-tuple format for backwards compat
  def analyze({:exception_handling, _try_block, catch_clauses, _finally_block} = node, _context)
      when is_list(catch_clauses) do
    silent_catches =
      Enum.filter(catch_clauses, fn
        {_exception_type, _exception_var, handler_body} ->
          not has_logging_or_reraise?(handler_body)

        _ ->
          false
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
  # New 3-tuple format: {:block, meta, statements}
  defp has_logging?({:block, _meta, statements}) when is_list(statements) do
    Enum.any?(statements, &has_logging?/1)
  end

  # Legacy format
  defp has_logging?({:block, statements}) when is_list(statements) do
    Enum.any?(statements, &has_logging?/1)
  end

  # New 3-tuple function_call: {:function_call, [name: name], args}
  defp has_logging?({:function_call, meta, _args}) when is_list(meta) do
    func_name = Keyword.get(meta, :name, "")
    logging_name?(func_name)
  end

  # Function call - check if it's a logging function
  defp has_logging?({:function_call, func_name, _args}) when is_atom(func_name) do
    logging_name?(func_name)
  end

  defp has_logging?({:function_call, func_name, _args}) when is_binary(func_name) do
    logging_name?(func_name)
  end

  defp logging_name?(func_name) when is_atom(func_name) do
    func_name in @logging_functions or
      func_name
      |> Atom.to_string()
      |> String.contains?(["log", "error", "warn", "print", "console"])
  end

  defp logging_name?(func_name) when is_binary(func_name) do
    func_lower = String.downcase(func_name)
    String.contains?(func_lower, ["log", "error", "warn", "print", "console"])
  end

  defp logging_name?(_), do: false

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
  # New 3-tuple format: {:block, meta, statements}
  defp has_reraise?({:block, _meta, statements}) when is_list(statements) do
    Enum.any?(statements, &has_reraise?/1)
  end

  # Legacy format
  defp has_reraise?({:block, statements}) when is_list(statements) do
    Enum.any?(statements, &has_reraise?/1)
  end

  # Early return with error - check if it's a reraise (new format)
  defp has_reraise?({:early_return, _meta, [{:function_call, call_meta, _}]}) do
    func_name = Keyword.get(call_meta, :name, "")
    reraise_name?(func_name)
  end

  # Early return with error - check if it's a reraise (legacy)
  defp has_reraise?({:early_return, {:function_call, func_name, _}})
       when func_name in @reraise_functions do
    true
  end

  # New 3-tuple function_call: {:function_call, [name: name], args}
  defp has_reraise?({:function_call, meta, _args}) when is_list(meta) do
    func_name = Keyword.get(meta, :name, "")
    reraise_name?(func_name)
  end

  # Function call - check if it's a reraise function
  defp has_reraise?({:function_call, func_name, _args}) when is_atom(func_name) do
    func_name in @reraise_functions
  end

  defp reraise_name?(func_name) when is_atom(func_name), do: func_name in @reraise_functions

  defp reraise_name?(func_name) when is_binary(func_name) do
    func_lower = String.downcase(func_name)
    Enum.any?(["raise", "reraise", "throw"], &String.contains?(func_lower, &1))
  end

  defp reraise_name?(_), do: false

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
