defmodule Metastatic.Analysis.BusinessLogic.ImproperInputValidation do
  @moduledoc """
  Detects improper input validation patterns (CWE-20).

  This analyzer identifies code patterns where user input is used in sensitive
  operations without apparent validation or sanitization.

  ## Cross-Language Applicability

  Input validation is a **universal security requirement**:

  - **Elixir**: Using `params` directly without changeset validation
  - **Python**: Using `request.args` without validation
  - **JavaScript**: Using `req.body` without schema validation
  - **Ruby**: Using `params` without strong parameters
  - **Java**: Using request parameters without Bean Validation
  - **C#**: Using model binding without DataAnnotations

  ## Problem

  When input is not validated:
  - Type confusion vulnerabilities
  - Buffer overflows (in some languages)
  - Logic flaws from unexpected values
  - Injection attacks (SQL, command, etc.)
  - Denial of service through malformed input

  ## Detection Strategy

  Detects patterns where:
  1. User input is used directly in operations
  2. No validation function calls are apparent
  3. No schema/changeset validation is used
  4. Input flows to sensitive operations
  """

  @behaviour Metastatic.Analysis.Analyzer

  alias Metastatic.Analysis.Analyzer

  @user_input_sources ~w[
    params request args query body
    input form data payload
    get post put patch
  ]

  @validation_functions ~w[
    validate valid? changeset cast
    schema validate_required validate_format
    validate_length validate_inclusion
    sanitize clean filter escape
    permit strong_parameters
    Bean Validator DataAnnotation
    Joi Yup zod
  ]

  @sensitive_operations ~w[
    query execute run eval
    send call request
    write save insert update delete
    open read file path
    create new build
  ]

  @impl true
  def info do
    %{
      name: :improper_input_validation,
      category: :security,
      description: "Detects user input used without validation (CWE-20)",
      severity: :warning,
      explanation: """
      Improper input validation occurs when user-supplied data is used in operations
      without checking its format, type, length, or content. This can lead to:
      - Injection attacks (SQL, command, XSS)
      - Type confusion and logic errors
      - Denial of service
      - Data corruption

      Always validate input:
      - Use schema validation (Ecto changesets, JSON Schema, etc.)
      - Validate type, format, length, and range
      - Use allowlists over denylists
      - Sanitize before use in sensitive operations
      """,
      configurable: true
    }
  end

  @impl true
  # Detect function definitions that use input without validation
  def analyze({:function_def, meta, body} = node, context) when is_list(meta) do
    func_name = Keyword.get(meta, :name, "")
    params = Keyword.get(meta, :params, [])

    if has_input_params?(params) do
      body_list = if is_list(body), do: body, else: [body]

      has_validation? = has_input_validation?(body_list)
      has_sensitive_use? = has_sensitive_input_use?(body_list, context)

      if has_sensitive_use? and not has_validation? do
        [
          Analyzer.issue(
            analyzer: __MODULE__,
            category: :security,
            severity: :warning,
            message:
              "Improper input validation: '#{func_name}' uses input in sensitive operations without validation",
            node: node,
            metadata: %{
              cwe: 20,
              function: func_name,
              suggestion:
                "Add input validation using changesets, schemas, or validation functions"
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

  # Detect direct use of user input in sensitive function calls
  def analyze({:function_call, meta, args} = node, context) when is_list(meta) do
    func_name = Keyword.get(meta, :name, "")

    if is_sensitive_operation?(func_name) and
         has_direct_input_argument?(args, context) and
         not in_validation_context?(context) do
      [
        Analyzer.issue(
          analyzer: __MODULE__,
          category: :security,
          severity: :warning,
          message:
            "Potential improper input validation: user input passed directly to '#{func_name}'",
          node: node,
          metadata: %{
            cwe: 20,
            function: func_name,
            suggestion: "Validate and sanitize input before passing to this function"
          }
        )
      ]
    else
      []
    end
  end

  def analyze(_node, _context), do: []

  # ----- Private Helpers -----

  defp has_input_params?(params) when is_list(params) do
    Enum.any?(params, fn
      {:param, _, name} when is_binary(name) ->
        name_lower = String.downcase(name)
        Enum.any?(@user_input_sources, &String.contains?(name_lower, &1))

      _ ->
        false
    end)
  end

  defp has_input_params?(_), do: false

  defp has_input_validation?(body) when is_list(body) do
    Enum.any?(body, &contains_validation?/1)
  end

  defp contains_validation?(node) do
    case node do
      {:function_call, meta, _args} when is_list(meta) ->
        func_name = Keyword.get(meta, :name, "")
        is_validation_function?(func_name)

      {:pipe, _meta, stages} when is_list(stages) ->
        Enum.any?(stages, &contains_validation?/1)

      {:block, _meta, statements} when is_list(statements) ->
        Enum.any?(statements, &contains_validation?/1)

      {:conditional, _meta, [condition | _branches]} ->
        is_type_check?(condition) or contains_validation?(condition)

      {:case, _meta, _} ->
        # Case statements often indicate pattern matching validation
        true

      {:with, _meta, _} ->
        # With statements often used for validation chains
        true

      tuple when is_tuple(tuple) ->
        tuple |> Tuple.to_list() |> Enum.any?(&contains_validation?/1)

      list when is_list(list) ->
        Enum.any?(list, &contains_validation?/1)

      _ ->
        false
    end
  end

  defp is_validation_function?(func_name) when is_binary(func_name) do
    func_lower = String.downcase(func_name)

    Enum.any?(@validation_functions, fn pattern ->
      String.contains?(func_lower, String.downcase(pattern))
    end)
  end

  defp is_validation_function?(_), do: false

  defp is_type_check?(node) do
    case node do
      {:function_call, meta, _args} when is_list(meta) ->
        func_name = Keyword.get(meta, :name, "")
        func_lower = String.downcase(func_name)

        String.contains?(func_lower, "is_") or
          String.contains?(func_lower, "type") or
          String.contains?(func_lower, "match")

      _ ->
        false
    end
  end

  defp has_sensitive_input_use?(body, context) when is_list(body) do
    Enum.any?(body, &contains_sensitive_input_use?(&1, context))
  end

  defp contains_sensitive_input_use?(node, context) do
    case node do
      {:function_call, meta, args} when is_list(meta) ->
        func_name = Keyword.get(meta, :name, "")

        is_sensitive_operation?(func_name) and
          has_direct_input_argument?(args, context)

      {:pipe, _meta, stages} when is_list(stages) ->
        Enum.any?(stages, &contains_sensitive_input_use?(&1, context))

      {:block, _meta, statements} when is_list(statements) ->
        Enum.any?(statements, &contains_sensitive_input_use?(&1, context))

      tuple when is_tuple(tuple) ->
        tuple
        |> Tuple.to_list()
        |> Enum.any?(&contains_sensitive_input_use?(&1, context))

      list when is_list(list) ->
        Enum.any?(list, &contains_sensitive_input_use?(&1, context))

      _ ->
        false
    end
  end

  defp is_sensitive_operation?(func_name) when is_binary(func_name) do
    func_lower = String.downcase(func_name)
    Enum.any?(@sensitive_operations, &String.contains?(func_lower, &1))
  end

  defp is_sensitive_operation?(_), do: false

  defp has_direct_input_argument?(args, _context) when is_list(args) do
    Enum.any?(args, fn arg ->
      case arg do
        {:variable, _meta, name} when is_binary(name) ->
          name_lower = String.downcase(name)
          Enum.any?(@user_input_sources, &String.contains?(name_lower, &1))

        {:map_access, _meta, _} ->
          true

        {:attribute_access, _meta, children} when is_list(children) ->
          Enum.any?(children, fn
            {:variable, _, name} when is_binary(name) ->
              name_lower = String.downcase(name)
              Enum.any?(@user_input_sources, &String.contains?(name_lower, &1))

            _ ->
              false
          end)

        _ ->
          false
      end
    end)
  end

  defp has_direct_input_argument?(_, _), do: false

  defp in_validation_context?(context) do
    parent_stack = Map.get(context, :parent_stack, [])
    Enum.any?(parent_stack, &contains_validation?/1)
  end
end
