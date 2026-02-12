defmodule Metastatic.Analysis.BusinessLogic.TOCTOU do
  @moduledoc """
  Detects Time-of-Check-Time-of-Use (TOCTOU) race condition vulnerabilities.

  TOCTOU vulnerabilities occur when there is a time gap between checking a
  condition and using the result of that check, allowing the state to change
  between the check and use phases. This is a common source of security
  vulnerabilities and bugs, especially in file operations and resource access.

  ## Cross-Language Applicability

  This is a universal vulnerability pattern that applies to all languages:

  - **Python**: `os.path.exists()` followed by `open()`
  - **JavaScript/Node.js**: `fs.existsSync()` followed by `fs.readFileSync()`
  - **Elixir**: `File.exists?()` followed by `File.read()`
  - **Go**: `os.Stat()` followed by `os.Open()`
  - **Java**: `file.exists()` followed by `new FileInputStream(file)`
  - **Rust**: `path.exists()` followed by `File::open()`
  - **Ruby**: `File.exist?()` followed by `File.open()`
  - **C**: `access()` followed by `open()`

  ## CWE Reference

  - **CWE-367**: Time-of-check Time-of-use (TOCTOU) Race Condition

  ## Examples

  ### Bad (Python)

      if os.path.exists(file_path):
          # Attacker could delete/replace file here
          with open(file_path) as f:
              data = f.read()

  ### Good (Python)

      try:
          with open(file_path) as f:
              data = f.read()
      except FileNotFoundError:
          handle_missing_file()

  ### Bad (Elixir)

      if File.exists?(path) do
        # Race condition window
        {:ok, content} = File.read(path)
      end

  ### Good (Elixir)

      case File.read(path) do
        {:ok, content} -> process(content)
        {:error, :enoent} -> handle_missing()
      end

  ### Bad (JavaScript)

      if (fs.existsSync(path)) {
          // Race condition window
          const data = fs.readFileSync(path);
      }

  ### Good (JavaScript)

      try {
          const data = fs.readFileSync(path);
      } catch (err) {
          if (err.code === 'ENOENT') handleMissing();
      }

  ## Detection Strategy

  Detects patterns where:
  1. A check function (exists, can_access, is_valid, etc.) is called in a condition
  2. A corresponding use function (read, write, open, delete, etc.) appears in the same block
  3. The same resource (variable, path) is referenced in both operations

  The analyzer looks for:
  - File existence checks followed by file operations
  - Permission checks followed by privileged operations
  - Resource availability checks followed by resource use
  - Null/presence checks with operations between check and use
  """

  @behaviour Metastatic.Analysis.Analyzer

  alias Metastatic.Analysis.Analyzer

  # Check functions that verify resource state
  @check_functions %{
    # File existence/access checks
    file_check: [
      "exists?",
      "File.exists?",
      "file_exists?",
      "path.exists",
      "os.path.exists",
      "os.path.isfile",
      "os.path.isdir",
      "existsSync",
      "fs.existsSync",
      "File.exist?",
      "File.exists?",
      "file.exists",
      "Path.exists",
      "File::exists",
      "access",
      "stat",
      "os.Stat",
      "fs.stat",
      "fs.statSync"
    ],
    # Permission/access checks
    permission_check: [
      "can_access?",
      "has_permission?",
      "is_authorized?",
      "check_permission",
      "check_access",
      "verify_access",
      "is_writable?",
      "is_readable?",
      "File.readable?",
      "File.writable?",
      "os.access"
    ],
    # Resource availability checks
    resource_check: [
      "is_available?",
      "resource_exists?",
      "connection_alive?",
      "is_connected?",
      "socket.connected?",
      "is_open?",
      "is_valid?"
    ]
  }

  # Use functions that operate on the checked resource
  @use_functions %{
    file_check: [
      "read",
      "read!",
      "File.read",
      "File.read!",
      "File.write",
      "File.write!",
      "File.rm",
      "File.rm!",
      "File.open",
      "open",
      "readFile",
      "readFileSync",
      "fs.readFile",
      "fs.readFileSync",
      "fs.writeFile",
      "fs.writeFileSync",
      "File.open",
      "File::open",
      "os.Open",
      "os.Remove",
      "unlink",
      "os.unlink",
      "delete",
      "File.delete"
    ],
    permission_check: [
      "execute",
      "perform",
      "do_action",
      "run",
      "invoke",
      "call",
      "apply"
    ],
    resource_check: [
      "use",
      "consume",
      "send",
      "receive",
      "write",
      "read",
      "execute"
    ]
  }

  @impl true
  def info do
    %{
      name: :toctou,
      category: :security,
      description: "Detects Time-of-Check-Time-of-Use (TOCTOU) race condition vulnerabilities",
      severity: :warning,
      explanation: """
      TOCTOU (Time-of-Check-Time-of-Use) vulnerabilities occur when the state of
      a resource can change between checking it and using it. This creates a race
      condition that attackers can exploit.

      Common patterns:
      - Checking if a file exists, then reading it (file could be deleted/replaced)
      - Checking permissions, then performing an action (permissions could change)
      - Checking resource availability, then using it (resource could become unavailable)

      Fix by:
      - Using atomic operations when available
      - Using try/catch instead of check-then-use
      - Holding locks during check-and-use sequences
      - Using file descriptors instead of paths after initial open
      """,
      configurable: false
    }
  end

  @impl true
  def analyze({:conditional, meta, [condition | branches]} = node, _context)
      when is_list(meta) and is_list(branches) do
    # Look for check-then-use patterns in conditionals
    check_info = extract_check_info(condition)

    if check_info do
      # Look for corresponding use in branches
      issues =
        branches
        |> Enum.flat_map(fn branch -> find_use_in_branch(branch, check_info, node) end)

      issues
    else
      []
    end
  end

  # Handle block nodes to detect check-then-use in sequential statements
  def analyze({:block, meta, statements} = _node, context)
      when is_list(meta) and is_list(statements) do
    find_sequential_toctou(statements, context)
  end

  def analyze(_node, _context), do: []

  # ----- Private Helpers -----

  # Extract check function info from a condition
  defp extract_check_info({:function_call, meta, args}) when is_list(meta) do
    name = Keyword.get(meta, :name, "")

    check_type = find_check_type(name)

    if check_type do
      resources = extract_resource_from_args(args)
      %{type: check_type, function: name, resources: resources, args: args}
    else
      nil
    end
  end

  # Handle method calls (attribute access + call)
  defp extract_check_info(
         {:attribute_access, meta, [receiver, {:function_call, call_meta, args}]}
       )
       when is_list(meta) and is_list(call_meta) do
    method_name = Keyword.get(call_meta, :name, "")
    full_name = build_method_name(receiver, method_name)

    check_type = find_check_type(full_name) || find_check_type(method_name)

    if check_type do
      resources = extract_resource_from_args([receiver | args])
      %{type: check_type, function: full_name, resources: resources, args: args}
    else
      nil
    end
  end

  # Handle negated checks: not File.exists?(path)
  defp extract_check_info({:unary_op, meta, [operand]}) when is_list(meta) do
    operator = Keyword.get(meta, :operator)

    if operator in [:not, :!] do
      extract_check_info(operand)
    else
      nil
    end
  end

  defp extract_check_info(_), do: nil

  # Find which category a check function belongs to
  defp find_check_type(name) do
    Enum.find_value(@check_functions, fn {type, functions} ->
      if name in functions or ends_with_any?(name, functions), do: type, else: nil
    end)
  end

  defp ends_with_any?(name, functions) do
    Enum.any?(functions, fn func ->
      String.ends_with?(name, func) or String.ends_with?(name, "." <> func)
    end)
  end

  # Build full method name from receiver and method
  defp build_method_name({:variable, _, name}, method) when is_binary(name),
    do: "#{name}.#{method}"

  defp build_method_name({:variable, _, name}, method) when is_atom(name), do: "#{name}.#{method}"
  defp build_method_name(_, method), do: method

  # Extract resource identifiers from function arguments
  # Returns a list of all resource identifiers found in arguments
  defp extract_resource_from_args([]), do: []

  defp extract_resource_from_args(args) do
    args
    |> Enum.flat_map(fn
      {:variable, _, name} -> [name]
      {:literal, meta, value} when is_list(meta) -> [value]
      _ -> []
    end)
  end

  # Find use of checked resource in a branch
  defp find_use_in_branch(nil, _check_info, _original_node), do: []

  defp find_use_in_branch({:block, _, statements}, check_info, original_node)
       when is_list(statements) do
    Enum.flat_map(statements, &find_use_in_node(&1, check_info, original_node))
  end

  defp find_use_in_branch(node, check_info, original_node),
    do: find_use_in_node(node, check_info, original_node)

  defp find_use_in_node({:function_call, meta, args} = _node, check_info, original_node)
       when is_list(meta) do
    name = Keyword.get(meta, :name, "")
    use_functions = Map.get(@use_functions, check_info.type, [])

    if is_use_function?(name, use_functions) and same_resource?(args, check_info.resources) do
      [
        Analyzer.issue(
          analyzer: __MODULE__,
          category: :security,
          severity: :warning,
          message:
            "TOCTOU vulnerability: '#{check_info.function}' check followed by '#{name}' use",
          node: original_node,
          metadata: %{
            check_function: check_info.function,
            use_function: name,
            resource: List.first(check_info.resources),
            cwe: 367
          }
        )
      ]
    else
      # Recurse into arguments
      Enum.flat_map(args, &find_use_in_node(&1, check_info, original_node))
    end
  end

  # Handle nested conditionals
  defp find_use_in_node({:conditional, _, children}, check_info, original_node)
       when is_list(children) do
    Enum.flat_map(children, &find_use_in_branch(&1, check_info, original_node))
  end

  # Handle blocks
  defp find_use_in_node({:block, _, statements}, check_info, original_node)
       when is_list(statements) do
    Enum.flat_map(statements, &find_use_in_node(&1, check_info, original_node))
  end

  # Handle pattern match assignments
  defp find_use_in_node({:assignment, _, [_target, value]}, check_info, original_node) do
    find_use_in_node(value, check_info, original_node)
  end

  defp find_use_in_node({:pattern_match, _, [_pattern | rest]}, check_info, original_node) do
    Enum.flat_map(rest, &find_use_in_node(&1, check_info, original_node))
  end

  # Handle attribute access (method chains)
  defp find_use_in_node(
         {:attribute_access, _, [receiver, {:function_call, call_meta, args}]} = _node,
         check_info,
         original_node
       )
       when is_list(call_meta) do
    method_name = Keyword.get(call_meta, :name, "")
    full_name = build_method_name(receiver, method_name)
    use_functions = Map.get(@use_functions, check_info.type, [])

    if (is_use_function?(full_name, use_functions) or is_use_function?(method_name, use_functions)) and
         same_resource?([receiver | args], check_info.resources) do
      [
        Analyzer.issue(
          analyzer: __MODULE__,
          category: :security,
          severity: :warning,
          message:
            "TOCTOU vulnerability: '#{check_info.function}' check followed by '#{full_name}' use",
          node: original_node,
          metadata: %{
            check_function: check_info.function,
            use_function: full_name,
            resource: List.first(check_info.resources),
            cwe: 367
          }
        )
      ]
    else
      find_use_in_node(receiver, check_info, original_node) ++
        Enum.flat_map(args, &find_use_in_node(&1, check_info, original_node))
    end
  end

  defp find_use_in_node(_, _check_info, _original_node), do: []

  # Check if function name matches use functions
  defp is_use_function?(name, use_functions) do
    name in use_functions or
      Enum.any?(use_functions, fn func ->
        String.ends_with?(name, func) or String.ends_with?(name, "." <> func)
      end)
  end

  # Check if args reference any of the checked resources
  defp same_resource?(_args, []), do: true

  defp same_resource?(args, resources) when is_list(resources) do
    arg_resources =
      Enum.flat_map(args, fn
        {:variable, _, name} -> [name]
        {:literal, _, value} -> [value]
        _ -> []
      end)

    # Check if any argument resource matches any checked resource
    Enum.any?(arg_resources, fn arg_res ->
      Enum.member?(resources, arg_res)
    end)
  end

  # Find sequential TOCTOU patterns in a block of statements
  defp find_sequential_toctou(statements, _context) do
    statements
    |> Enum.with_index()
    |> Enum.flat_map(fn {stmt, idx} ->
      # Check if this statement is a check
      case extract_check_from_statement(stmt) do
        nil ->
          []

        check_info ->
          # Look for uses in subsequent statements
          subsequent = Enum.drop(statements, idx + 1)

          subsequent
          |> Enum.take(5)
          |> Enum.flat_map(&find_use_in_sequential(&1, check_info, stmt))
      end
    end)
  end

  # Extract check info from an assignment or direct call
  defp extract_check_from_statement({:assignment, _, [_target, value]}),
    do: extract_check_info(value)

  defp extract_check_from_statement({:function_call, _, _} = node), do: extract_check_info(node)
  defp extract_check_from_statement(_), do: nil

  # Find use in a subsequent statement
  defp find_use_in_sequential({:function_call, meta, args}, check_info, original_node)
       when is_list(meta) do
    name = Keyword.get(meta, :name, "")
    use_functions = Map.get(@use_functions, check_info.type, [])

    if is_use_function?(name, use_functions) and same_resource?(args, check_info.resources) do
      [
        Analyzer.issue(
          analyzer: __MODULE__,
          category: :security,
          severity: :warning,
          message:
            "TOCTOU vulnerability: '#{check_info.function}' check followed by '#{name}' use in sequential statements",
          node: original_node,
          metadata: %{
            check_function: check_info.function,
            use_function: name,
            resource: List.first(check_info.resources),
            cwe: 367
          }
        )
      ]
    else
      []
    end
  end

  defp find_use_in_sequential({:assignment, _, [_target, value]}, check_info, original_node) do
    find_use_in_sequential(value, check_info, original_node)
  end

  defp find_use_in_sequential(_, _check_info, _original_node), do: []
end
