defmodule Metastatic.Analysis.BusinessLogic.PathTraversal do
  @moduledoc """
  Detects potential Path Traversal vulnerabilities (CWE-22).

  This analyzer identifies code patterns where user input is used in file path
  operations without proper validation, allowing attackers to access files
  outside the intended directory.

  ## Cross-Language Applicability

  Path traversal is a **universal file system vulnerability**:

  - **Elixir**: `File.read!(params["filename"])`
  - **Python**: `open(request.args.get('file'))`
  - **JavaScript/Node**: `fs.readFile(req.query.file)`
  - **Ruby**: `File.read(params[:file])`
  - **PHP**: `file_get_contents($_GET['file'])`
  - **Java**: `new File(request.getParameter("path"))`
  - **C#**: `File.ReadAllText(Request.QueryString["file"])`
  - **Go**: `ioutil.ReadFile(r.URL.Query().Get("file"))`

  ## Problem

  When file paths are constructed from user input without validation:
  - Attackers can use `../` sequences to escape directories
  - Can read sensitive files like `/etc/passwd` or config files
  - Can write to arbitrary locations
  - Can execute arbitrary files in some cases

  ## Detection Strategy

  Detects patterns where:
  1. File operation functions receive user-controlled input
  2. Path construction uses concatenation with user input
  3. No path validation/sanitization is apparent

  ## Examples

  ### Bad (Elixir)

      def download(conn, %{"file" => filename}) do
        path = "/uploads/" <> filename
        send_file(conn, 200, path)
      end

  ### Good (Elixir)

      def download(conn, %{"file" => filename}) do
        safe_name = Path.basename(filename)  # Remove directory components
        path = Path.join("/uploads", safe_name)

        if String.starts_with?(path, "/uploads/") do
          send_file(conn, 200, path)
        else
          send_resp(conn, 400, "Invalid path")
        end
      end
  """

  @behaviour Metastatic.Analysis.Analyzer

  alias Metastatic.Analysis.Analyzer

  @file_functions ~w[
    read read! write write! stream! open
    read_file read_file! write_file
    readFile writeFile readFileSync writeFileSync
    file_get_contents file_put_contents fopen
    File.read File.write File.stream File.open
    Path.join Path.expand Path.absname
    send_file send_download download
    include require require_once include_once
    readdir opendir scandir glob
    unlink delete rm remove
    copy cp rename mv move
    mkdir rmdir
  ]

  @path_functions ~w[
    join expand absname relative_to
    Path.join Path.expand Path.absname
    path.join path.resolve path.normalize
    os.path.join os.path.abspath
    Paths.get File.separator
  ]

  @user_input_patterns ~w[
    params request args query body
    input user filename file path
    name document image upload
    get post
  ]

  @impl true
  def info do
    %{
      name: :path_traversal,
      category: :security,
      description: "Detects potential Path Traversal vulnerabilities (CWE-22)",
      severity: :error,
      explanation: """
      Path traversal occurs when user input is used to construct file paths without
      proper validation. Attackers can use sequences like `../` to:
      - Read sensitive files outside the intended directory
      - Write to arbitrary locations on the file system
      - Potentially execute arbitrary code

      Always validate and sanitize file paths:
      - Use Path.basename() to remove directory components
      - Validate the final path is within the expected directory
      - Use allowlists for permitted files when possible
      """,
      configurable: true
    }
  end

  @impl true
  # Detect file operations with potentially tainted paths
  def analyze({:function_call, meta, args} = node, context) when is_list(meta) do
    func_name = Keyword.get(meta, :name, "")

    cond do
      is_file_function?(func_name) and has_tainted_path_argument?(args, context) ->
        [create_path_traversal_issue(node, func_name, "file operation with user-controlled path")]

      is_path_function?(func_name) and has_tainted_path_argument?(args, context) ->
        [
          Analyzer.issue(
            analyzer: __MODULE__,
            category: :security,
            severity: :warning,
            message:
              "Potential path traversal: '#{func_name}' with user-controlled input - validate result",
            node: node,
            metadata: %{
              cwe: 22,
              function: func_name,
              suggestion: "Validate the resulting path is within the expected directory"
            }
          )
        ]

      true ->
        []
    end
  end

  # Detect path concatenation with user input
  def analyze({:binary_op, meta, [left, right]} = node, context) when is_list(meta) do
    operator = Keyword.get(meta, :operator)

    if operator in [:concat, :<>, :+, :/] do
      cond do
        looks_like_path?(left) and contains_user_input?(right, context) ->
          [
            create_path_traversal_issue(
              node,
              "concatenation",
              "path concatenation with user input"
            )
          ]

        looks_like_path?(right) and contains_user_input?(left, context) ->
          [
            create_path_traversal_issue(
              node,
              "concatenation",
              "user input concatenated with path"
            )
          ]

        true ->
          []
      end
    else
      []
    end
  end

  def analyze(_node, _context), do: []

  # ----- Private Helpers -----

  defp create_path_traversal_issue(node, func_name, description) do
    Analyzer.issue(
      analyzer: __MODULE__,
      category: :security,
      severity: :error,
      message: "Potential path traversal: #{description} in '#{func_name}'",
      node: node,
      metadata: %{
        cwe: 22,
        function: func_name,
        suggestion: "Use Path.basename() and validate path is within allowed directory"
      }
    )
  end

  defp is_file_function?(func_name) when is_binary(func_name) do
    func_lower = String.downcase(func_name)

    Enum.any?(@file_functions, fn pattern ->
      String.contains?(func_lower, String.downcase(pattern))
    end)
  end

  defp is_file_function?(_), do: false

  defp is_path_function?(func_name) when is_binary(func_name) do
    func_lower = String.downcase(func_name)

    Enum.any?(@path_functions, fn pattern ->
      String.contains?(func_lower, String.downcase(pattern))
    end)
  end

  defp is_path_function?(_), do: false

  defp has_tainted_path_argument?(args, context) when is_list(args) do
    Enum.any?(args, &contains_user_input?(&1, context))
  end

  defp has_tainted_path_argument?(_, _), do: false

  defp contains_user_input?(node, context) do
    case node do
      {:variable, _meta, name} when is_binary(name) ->
        is_user_input_variable?(name) or in_tainted_scope?(name, context)

      {:function_call, meta, _args} when is_list(meta) ->
        func_name = Keyword.get(meta, :name, "")
        is_user_input_function?(func_name)

      {:attribute_access, _meta, children} when is_list(children) ->
        Enum.any?(children, &contains_user_input?(&1, context))

      {:binary_op, _meta, [left, right]} ->
        contains_user_input?(left, context) or contains_user_input?(right, context)

      {:map_access, _meta, [_map, key]} ->
        # map["key"] pattern - check if it's params/request access
        contains_user_input?(key, context)

      _ ->
        false
    end
  end

  defp is_user_input_variable?(name) when is_binary(name) do
    name_lower = String.downcase(name)
    Enum.any?(@user_input_patterns, &String.contains?(name_lower, &1))
  end

  defp is_user_input_function?(func_name) when is_binary(func_name) do
    func_lower = String.downcase(func_name)
    Enum.any?(@user_input_patterns, &String.contains?(func_lower, &1))
  end

  defp is_user_input_function?(_), do: false

  defp in_tainted_scope?(name, context) do
    tainted_vars = Map.get(context, :tainted_vars, MapSet.new())
    MapSet.member?(tainted_vars, name)
  end

  defp looks_like_path?({:literal, meta, value}) when is_list(meta) and is_binary(value) do
    String.contains?(value, "/") or
      String.contains?(value, "\\") or
      String.starts_with?(value, ".") or
      String.ends_with?(value, [".txt", ".json", ".xml", ".html", ".log", ".conf", ".cfg"])
  end

  defp looks_like_path?({:variable, _meta, name}) when is_binary(name) do
    name_lower = String.downcase(name)

    String.contains?(name_lower, "path") or
      String.contains?(name_lower, "dir") or
      String.contains?(name_lower, "file") or
      String.contains?(name_lower, "folder")
  end

  defp looks_like_path?(_), do: false
end
