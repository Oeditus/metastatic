defmodule Metastatic.Analysis.BusinessLogic.SensitiveDataExposure do
  @moduledoc """
  Detects exposure of sensitive information to unauthorized actors (CWE-200).

  This analyzer identifies code patterns where sensitive data such as passwords,
  tokens, secrets, or PII is logged, returned in responses, or otherwise exposed.

  ## Cross-Language Applicability

  Sensitive data exposure is a **universal security concern**:

  - **Elixir**: `Logger.info("User: \#{inspect(user)}")`  # May include password_hash
  - **Python**: `logging.info(f"Request: {request.__dict__}")`
  - **JavaScript**: `console.log("User data:", userData)`
  - **Ruby**: `Rails.logger.info(user.attributes)`
  - **Java**: `logger.info("User: " + user.toString())`
  - **C#**: `_logger.LogInformation($"User: {user}")`
  - **Go**: `log.Printf("User: %+v", user)`

  ## Problem

  When sensitive data is logged or exposed:
  - Passwords/tokens may be stored in plain text in logs
  - PII may be accessible to unauthorized personnel
  - Compliance violations (GDPR, HIPAA, PCI-DSS)
  - Credential leakage through error messages

  ## Detection Strategy

  Detects patterns where:
  1. Logging functions receive objects/maps that may contain sensitive fields
  2. Variables with sensitive names are logged
  3. Inspect/toString calls on user or credential objects
  4. Error responses include detailed internal information

  ## Examples

  ### Bad (Elixir)

      def create(conn, params) do
        Logger.info("Creating user with params: \#{inspect(params)}")
        # params may contain password!
      end

  ### Good (Elixir)

      def create(conn, params) do
        Logger.info("Creating user: \#{params["email"]}")
        # Only log non-sensitive fields
      end
  """

  @behaviour Metastatic.Analysis.Analyzer

  alias Metastatic.Analysis.Analyzer

  @logging_functions ~w[
    log info debug warn error warning notice
    Logger.info Logger.debug Logger.warn Logger.error
    IO.puts IO.inspect IO.write
    puts print println printf echo
    console.log console.warn console.error console.debug
    print_r var_dump
    Log.d Log.i Log.w Log.e
    logger.info logger.debug logger.warn logger.error
  ]

  @sensitive_field_patterns ~w[
    password passwd pwd secret token api_key
    apikey access_token refresh_token auth
    credential private_key secret_key
    ssn social_security credit_card card_number
    cvv cvc pin otp verification_code
    session_id csrf bearer jwt
    password_hash encrypted_password
  ]

  @sensitive_object_patterns ~w[
    user account credentials session
    auth authentication authorization
    payment billing card customer
    config secrets env environment
  ]

  @impl true
  def info do
    %{
      name: :sensitive_data_exposure,
      category: :security,
      description: "Detects exposure of sensitive information (CWE-200)",
      severity: :warning,
      explanation: """
      Sensitive data exposure occurs when secrets, credentials, or PII are logged,
      returned in error messages, or otherwise made accessible. This can lead to:
      - Credential theft from log files
      - Compliance violations (GDPR, HIPAA, PCI-DSS)
      - Privacy breaches
      - Account takeovers

      Always:
      - Filter sensitive fields before logging
      - Use structured logging with explicit field selection
      - Implement log redaction for sensitive patterns
      - Never include full objects in error responses
      """,
      configurable: true
    }
  end

  @impl true
  # Detect logging calls with potentially sensitive data
  def analyze({:function_call, meta, args} = node, context) when is_list(meta) do
    func_name = Keyword.get(meta, :name, "")

    if is_logging_function?(func_name) do
      check_logging_args(node, func_name, args, context)
    else
      []
    end
  end

  # Detect inspect/toString on sensitive objects
  def analyze({:function_call, meta, [arg]} = node, context) when is_list(meta) do
    func_name = Keyword.get(meta, :name, "")

    if func_name in ["inspect", "Kernel.inspect", "toString", "to_string", "__str__"] do
      if is_sensitive_object?(arg, context) do
        [
          Analyzer.issue(
            analyzer: __MODULE__,
            category: :security,
            severity: :warning,
            message:
              "Potential sensitive data exposure: '#{func_name}' on potentially sensitive object",
            node: node,
            metadata: %{
              cwe: 200,
              function: func_name,
              suggestion:
                "Select specific non-sensitive fields instead of inspecting entire object"
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

  defp check_logging_args(node, func_name, args, context) do
    issues =
      args
      |> Enum.flat_map(fn arg -> check_sensitive_in_arg(arg, context) end)
      |> Enum.uniq()

    case issues do
      [] ->
        []

      sensitive_items ->
        [
          Analyzer.issue(
            analyzer: __MODULE__,
            category: :security,
            severity: :warning,
            message:
              "Potential sensitive data in '#{func_name}': #{Enum.join(sensitive_items, ", ")}",
            node: node,
            metadata: %{
              cwe: 200,
              function: func_name,
              sensitive_items: sensitive_items,
              suggestion: "Filter sensitive fields before logging"
            }
          )
        ]
    end
  end

  defp check_sensitive_in_arg(arg, context) do
    case arg do
      {:variable, _meta, name} when is_binary(name) ->
        if is_sensitive_variable?(name), do: [name], else: []

      {:function_call, meta, inner_args} when is_list(meta) ->
        func_name = Keyword.get(meta, :name, "")

        cond do
          func_name in ["inspect", "Kernel.inspect"] ->
            Enum.flat_map(inner_args, &check_sensitive_in_arg(&1, context))

          String.contains?(func_name, ["struct", "map", "attributes"]) ->
            Enum.flat_map(inner_args, &check_sensitive_in_arg(&1, context))

          true ->
            []
        end

      {:attribute_access, _meta, children} when is_list(children) ->
        check_sensitive_attribute_chain(children)

      {:map, _meta, pairs} when is_list(pairs) ->
        pairs
        |> Enum.flat_map(fn
          {key, _val} when is_binary(key) ->
            if is_sensitive_field?(key), do: [key], else: []

          {{:literal, _, key}, _val} when is_binary(key) ->
            if is_sensitive_field?(key), do: [key], else: []

          _ ->
            []
        end)

      {:binary_op, _meta, [left, right]} ->
        check_sensitive_in_arg(left, context) ++ check_sensitive_in_arg(right, context)

      {:literal, meta, value} when is_list(meta) and is_binary(value) ->
        # Check for interpolation patterns with sensitive vars
        if contains_sensitive_interpolation?(value), do: ["interpolated sensitive data"], else: []

      _ ->
        []
    end
  end

  defp check_sensitive_attribute_chain(children) do
    children
    |> Enum.flat_map(fn
      {:literal, _, attr} when is_binary(attr) or is_atom(attr) ->
        attr_str = to_string(attr)
        if is_sensitive_field?(attr_str), do: [attr_str], else: []

      {:variable, _, name} when is_binary(name) ->
        if is_sensitive_variable?(name), do: [name], else: []

      _ ->
        []
    end)
  end

  defp is_logging_function?(func_name) when is_binary(func_name) do
    func_lower = String.downcase(func_name)

    Enum.any?(@logging_functions, fn pattern ->
      String.contains?(func_lower, String.downcase(pattern))
    end)
  end

  defp is_logging_function?(_), do: false

  defp is_sensitive_variable?(name) when is_binary(name) do
    name_lower = String.downcase(name)

    Enum.any?(@sensitive_field_patterns, &String.contains?(name_lower, &1)) or
      Enum.any?(@sensitive_object_patterns, &String.contains?(name_lower, &1))
  end

  defp is_sensitive_field?(name) when is_binary(name) or is_atom(name) do
    name_lower = name |> to_string() |> String.downcase()
    Enum.any?(@sensitive_field_patterns, &String.contains?(name_lower, &1))
  end

  defp is_sensitive_object?({:variable, _meta, name}, _context) when is_binary(name) do
    name_lower = String.downcase(name)
    Enum.any?(@sensitive_object_patterns, &String.contains?(name_lower, &1))
  end

  defp is_sensitive_object?({:attribute_access, _meta, children}, _context)
       when is_list(children) do
    Enum.any?(children, fn
      {:variable, _, name} when is_binary(name) ->
        name_lower = String.downcase(name)
        Enum.any?(@sensitive_object_patterns, &String.contains?(name_lower, &1))

      _ ->
        false
    end)
  end

  defp is_sensitive_object?(_, _), do: false

  defp contains_sensitive_interpolation?(value) when is_binary(value) do
    # Look for #{...} patterns with sensitive variable names
    value_lower = String.downcase(value)
    Enum.any?(@sensitive_field_patterns, &String.contains?(value_lower, &1))
  end
end
