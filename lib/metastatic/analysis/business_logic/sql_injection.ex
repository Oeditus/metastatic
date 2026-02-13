defmodule Metastatic.Analysis.BusinessLogic.SQLInjection do
  @moduledoc """
  Detects potential SQL injection vulnerabilities (CWE-89).

  This analyzer identifies code patterns where user input or variables are
  concatenated or interpolated into SQL query strings, which can lead to
  SQL injection attacks.

  ## Cross-Language Applicability

  SQL injection is a **universal vulnerability** affecting all languages:

  - **Python**: `cursor.execute(f"SELECT * FROM users WHERE id = {user_id}")`
  - **JavaScript**: `` db.query(`SELECT * FROM users WHERE id = ${userId}`) ``
  - **Elixir**: `Repo.query("SELECT * FROM users WHERE id = " <> id)`
  - **Ruby**: `User.where("name = '\#{params[:name]}'")`
  - **PHP**: `$pdo->query("SELECT * FROM users WHERE id = $id")`
  - **Java**: `stmt.executeQuery("SELECT * FROM users WHERE id = " + userId)`
  - **C#**: `cmd.CommandText = "SELECT * FROM users WHERE id = " + userId`
  - **Go**: `db.Query("SELECT * FROM users WHERE id = " + userId)`

  ## Problem

  When SQL queries are built by concatenating user-controlled strings:
  - Attackers can inject malicious SQL code
  - Can lead to data theft, modification, or deletion
  - Can bypass authentication
  - Can execute administrative operations

  ## Detection Strategy

  Detects patterns where:
  1. SQL keywords (SELECT, INSERT, UPDATE, DELETE, etc.) appear in string literals
  2. Those strings are concatenated with variables or function results
  3. The result flows to database query functions

  ## Examples

  ### Bad (Elixir)

      def get_user(id) do
        Repo.query("SELECT * FROM users WHERE id = " <> id)
      end

  ### Good (Elixir)

      def get_user(id) do
        Repo.query("SELECT * FROM users WHERE id = $1", [id])
      end

  ### Bad (Python)

      def get_user(user_id):
          cursor.execute(f"SELECT * FROM users WHERE id = {user_id}")

  ### Good (Python)

      def get_user(user_id):
          cursor.execute("SELECT * FROM users WHERE id = %s", (user_id,))
  """

  @behaviour Metastatic.Analysis.Analyzer

  alias Metastatic.Analysis.Analyzer

  @sql_keywords ~w[SELECT INSERT UPDATE DELETE FROM WHERE JOIN DROP CREATE ALTER TRUNCATE EXEC EXECUTE]

  @query_functions ~w[
    query execute exec run sql raw_query
    execute_query execute_sql run_sql
    Repo.query Ecto.Adapters.SQL.query
    cursor.execute connection.execute
    db.query db.execute db.run
    executeQuery executeUpdate executeSql
    Query Raw RawSQL
  ]

  @impl true
  def info do
    %{
      name: :sql_injection,
      category: :security,
      description: "Detects potential SQL injection vulnerabilities (CWE-89)",
      severity: :error,
      explanation: """
      SQL injection occurs when user input is concatenated into SQL queries without
      proper sanitization or parameterization. This allows attackers to:
      - Extract sensitive data from the database
      - Modify or delete data
      - Bypass authentication
      - Execute administrative operations

      Always use parameterized queries or prepared statements instead of string
      concatenation for SQL queries.
      """,
      configurable: true
    }
  end

  @impl true
  # Detect binary operations that concatenate SQL strings
  # Pattern: "SELECT ... " <> variable or "SELECT ... " + variable
  def analyze({:binary_op, meta, [left, right]} = node, context) when is_list(meta) do
    operator = Keyword.get(meta, :operator)

    if operator in [:concat, :<>, :+, :||] do
      check_sql_concatenation(node, left, right, context)
    else
      []
    end
  end

  # Detect function calls to query functions with potentially unsafe arguments
  def analyze({:function_call, meta, args} = node, _context) when is_list(meta) do
    func_name = Keyword.get(meta, :name, "")

    if is_query_function?(func_name) and has_unsafe_sql_argument?(args) do
      [
        Analyzer.issue(
          analyzer: __MODULE__,
          category: :security,
          severity: :error,
          message: "Potential SQL injection: unsafe string passed to '#{func_name}'",
          node: node,
          metadata: %{
            cwe: 89,
            function: func_name,
            suggestion: "Use parameterized queries instead of string concatenation"
          }
        )
      ]
    else
      []
    end
  end

  # Detect string interpolation patterns that might contain SQL
  def analyze({:literal, meta, value} = node, context) when is_list(meta) and is_binary(value) do
    subtype = Keyword.get(meta, :subtype)

    if subtype == :string and contains_sql_keywords?(value) and has_interpolation_markers?(value) do
      # Check if we're in a query function context
      if in_query_context?(context) do
        [
          Analyzer.issue(
            analyzer: __MODULE__,
            category: :security,
            severity: :error,
            message: "Potential SQL injection: string interpolation in SQL query",
            node: node,
            metadata: %{
              cwe: 89,
              sql_preview: String.slice(value, 0, 50) <> "...",
              suggestion: "Use parameterized queries with placeholders ($1, ?, %s)"
            }
          )
        ]
      else
        []
      end
    else
      []
    end
  end

  def analyze(_node, _context), do: []

  # ----- Private Helpers -----

  defp check_sql_concatenation(node, left, right, _context) do
    left_sql? = contains_sql_literal?(left)
    right_sql? = contains_sql_literal?(right)
    left_var? = is_variable_or_call?(left)
    right_var? = is_variable_or_call?(right)

    cond do
      left_sql? and right_var? ->
        [create_sql_injection_issue(node, "SQL string concatenated with variable/expression")]

      right_sql? and left_var? ->
        [create_sql_injection_issue(node, "Variable/expression concatenated with SQL string")]

      true ->
        []
    end
  end

  defp create_sql_injection_issue(node, message) do
    Analyzer.issue(
      analyzer: __MODULE__,
      category: :security,
      severity: :error,
      message: "Potential SQL injection: #{message}",
      node: node,
      metadata: %{
        cwe: 89,
        suggestion: "Use parameterized queries instead of string concatenation"
      }
    )
  end

  defp contains_sql_literal?({:literal, meta, value}) when is_list(meta) and is_binary(value) do
    contains_sql_keywords?(value)
  end

  defp contains_sql_literal?({:binary_op, _meta, [left, right]}) do
    contains_sql_literal?(left) or contains_sql_literal?(right)
  end

  defp contains_sql_literal?(_), do: false

  defp contains_sql_keywords?(value) when is_binary(value) do
    upper = String.upcase(value)
    Enum.any?(@sql_keywords, &String.contains?(upper, &1))
  end

  defp is_variable_or_call?({:variable, _meta, _name}), do: true
  defp is_variable_or_call?({:function_call, _meta, _args}), do: true
  defp is_variable_or_call?({:attribute_access, _meta, _children}), do: true
  defp is_variable_or_call?(_), do: false

  defp is_query_function?(func_name) when is_binary(func_name) do
    func_lower = String.downcase(func_name)

    Enum.any?(@query_functions, fn pattern ->
      String.contains?(func_lower, String.downcase(pattern))
    end)
  end

  defp is_query_function?(_), do: false

  defp has_unsafe_sql_argument?(args) when is_list(args) do
    Enum.any?(args, fn arg ->
      case arg do
        {:binary_op, meta, _} when is_list(meta) ->
          operator = Keyword.get(meta, :operator)
          operator in [:concat, :<>, :+, :||]

        {:literal, meta, value} when is_list(meta) and is_binary(value) ->
          contains_sql_keywords?(value) and has_interpolation_markers?(value)

        _ ->
          false
      end
    end)
  end

  defp has_unsafe_sql_argument?(_), do: false

  defp has_interpolation_markers?(value) when is_binary(value) do
    # Check for various interpolation patterns
    # " +
    dquote_plus = <<34, 32, 43>>
    # " ||
    dquote_pipe = <<34, 32, 124, 124>>

    # JS template literals
    # Elixir/Ruby interpolation
    # Python f-strings
    # String concat hints
    String.contains?(value, "${") or
      String.contains?(value, ~S(#{)) or
      String.contains?(value, "{") or
      String.contains?(value, "' +") or
      String.contains?(value, dquote_plus) or
      String.contains?(value, "' ||") or
      String.contains?(value, dquote_pipe)
  end

  defp in_query_context?(context) do
    parent_stack = Map.get(context, :parent_stack, [])

    Enum.any?(parent_stack, fn parent ->
      case parent do
        {:function_call, meta, _} when is_list(meta) ->
          func_name = Keyword.get(meta, :name, "")
          is_query_function?(func_name)

        _ ->
          false
      end
    end)
  end
end
