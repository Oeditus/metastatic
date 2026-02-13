defmodule Metastatic.Analysis.BusinessLogic.UnrestrictedFileUpload do
  @moduledoc """
  Detects unrestricted file upload vulnerabilities (CWE-434).

  This analyzer identifies code patterns where file uploads are processed
  without proper validation of file type, size, or content.

  ## Cross-Language Applicability

  Unrestricted file upload is a **universal web vulnerability**:

  - **Elixir/Phoenix**: `File.write!(path, upload.content)` without validation
  - **Python/Flask**: `file.save(path)` without checking extension
  - **JavaScript/Express**: `multer` without file filter
  - **Ruby/Rails**: `file.attach` without validation
  - **PHP**: `move_uploaded_file()` without checks
  - **Java/Spring**: `transferTo()` without validation
  - **C#/ASP.NET**: `SaveAs()` without file type check

  ## Problem

  When file uploads lack validation:
  - Attackers can upload executable files (web shells)
  - Server can be compromised through uploaded malware
  - Denial of service through large file uploads
  - Storage exhaustion attacks

  ## Detection Strategy

  Detects patterns where:
  1. File save/write operations receive uploaded content
  2. No file type/extension validation is apparent
  3. No file size validation is apparent
  4. Original filename is used directly without sanitization

  ## Examples

  ### Bad (Elixir)

      def upload(conn, %{"file" => upload}) do
        path = "/uploads/\#{upload.filename}"
        File.write!(path, upload.path |> File.read!())
        json(conn, %{status: "uploaded"})
      end

  ### Good (Elixir)

      @allowed_extensions ~w[.jpg .jpeg .png .gif]
      @max_size 5_000_000

      def upload(conn, %{"file" => upload}) do
        ext = Path.extname(upload.filename) |> String.downcase()
        size = File.stat!(upload.path).size

        cond do
          ext not in @allowed_extensions ->
            conn |> put_status(400) |> json(%{error: "Invalid file type"})

          size > @max_size ->
            conn |> put_status(400) |> json(%{error: "File too large"})

          true ->
            safe_name = "\#{UUID.uuid4()}\#{ext}"
            File.copy!(upload.path, "/uploads/\#{safe_name}")
            json(conn, %{status: "uploaded", filename: safe_name})
        end
      end
  """

  @behaviour Metastatic.Analysis.Analyzer

  alias Metastatic.Analysis.Analyzer

  @file_save_functions ~w[
    write write! copy copy! stream!
    save save! store store!
    File.write File.copy File.stream
    move_uploaded_file transferTo attach
    saveAs SaveAs DownloadTo
    put_object upload_file
    move rename
  ]

  @validation_indicators ~w[
    extname extension content_type mime_type
    file_type allowed_types valid_extension
    file_size size max_size limit
    validate_upload check_file verify_file
    allowed? valid? acceptable?
  ]

  @upload_patterns ~w[
    upload uploaded file attachment
    multipart form_data formdata
    plug_upload phoenix_upload
  ]

  @impl true
  def info do
    %{
      name: :unrestricted_file_upload,
      category: :security,
      description: "Detects unrestricted file upload vulnerabilities (CWE-434)",
      severity: :error,
      explanation: """
      Unrestricted file upload occurs when files are saved without validating their
      type, size, or content. This can allow attackers to:
      - Upload executable files (web shells, malware)
      - Compromise the server
      - Exhaust storage through large files
      - Bypass security controls

      Always validate uploads:
      - Check file extension against allowlist
      - Validate MIME type/content type
      - Enforce maximum file size
      - Use random filenames, not user-supplied names
      - Store outside web root when possible
      """,
      configurable: true
    }
  end

  @impl true
  # Detect function definitions handling uploads without validation
  def analyze({:function_def, meta, body} = node, _context) when is_list(meta) do
    func_name = Keyword.get(meta, :name, "")
    params = Keyword.get(meta, :params, [])

    if handles_file_upload?(func_name, params) do
      body_list = if is_list(body), do: body, else: [body]

      has_validation? = has_upload_validation?(body_list)
      has_save_op? = has_file_save_operation?(body_list)

      if has_save_op? and not has_validation? do
        [
          Analyzer.issue(
            analyzer: __MODULE__,
            category: :security,
            severity: :error,
            message: "Unrestricted file upload: '#{func_name}' saves files without validation",
            node: node,
            metadata: %{
              cwe: 434,
              function: func_name,
              suggestion: "Add file type, size, and content validation before saving"
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

  # Detect direct file saves with upload-like variables
  def analyze({:function_call, meta, args} = node, context) when is_list(meta) do
    func_name = Keyword.get(meta, :name, "")

    if is_file_save_function?(func_name) and involves_upload?(args, context) and
         not in_validation_context?(context) do
      [
        Analyzer.issue(
          analyzer: __MODULE__,
          category: :security,
          severity: :warning,
          message: "Potential unrestricted file upload: '#{func_name}' with uploaded content",
          node: node,
          metadata: %{
            cwe: 434,
            function: func_name,
            suggestion: "Ensure file type, size, and name are validated before this operation"
          }
        )
      ]
    else
      []
    end
  end

  def analyze(_node, _context), do: []

  # ----- Private Helpers -----

  defp handles_file_upload?(func_name, params) when is_binary(func_name) do
    func_lower = String.downcase(func_name)

    String.contains?(func_lower, "upload") or
      String.contains?(func_lower, "import") or
      String.contains?(func_lower, "attach") or
      has_upload_param?(params)
  end

  defp handles_file_upload?(_, _), do: false

  defp has_upload_param?(params) when is_list(params) do
    Enum.any?(params, fn
      {:param, _, name} when is_binary(name) ->
        name_lower = String.downcase(name)
        Enum.any?(@upload_patterns, &String.contains?(name_lower, &1))

      _ ->
        false
    end)
  end

  defp has_upload_param?(_), do: false

  defp is_file_save_function?(func_name) when is_binary(func_name) do
    func_lower = String.downcase(func_name)

    Enum.any?(@file_save_functions, fn pattern ->
      String.contains?(func_lower, String.downcase(pattern))
    end)
  end

  defp is_file_save_function?(_), do: false

  defp has_upload_validation?(body) when is_list(body) do
    Enum.any?(body, &contains_validation?/1)
  end

  defp contains_validation?(node) do
    case node do
      {:function_call, meta, _args} when is_list(meta) ->
        func_name = Keyword.get(meta, :name, "")
        is_validation_function?(func_name)

      {:conditional, _meta, [condition | _branches]} ->
        contains_validation?(condition) or involves_size_or_type_check?(condition)

      {:binary_op, meta, [left, right]} when is_list(meta) ->
        operator = Keyword.get(meta, :operator)

        if operator in [:in, :==, :===, :>, :<, :>=, :<=] do
          involves_validation_variable?(left) or involves_validation_variable?(right)
        else
          contains_validation?(left) or contains_validation?(right)
        end

      {:case, _meta, [expr | _arms]} ->
        involves_validation_variable?(expr)

      {:block, _meta, statements} when is_list(statements) ->
        Enum.any?(statements, &contains_validation?/1)

      {:pipe, _meta, stages} when is_list(stages) ->
        Enum.any?(stages, &contains_validation?/1)

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

    Enum.any?(@validation_indicators, fn ind ->
      String.contains?(func_lower, String.downcase(ind))
    end)
  end

  defp is_validation_function?(_), do: false

  defp involves_size_or_type_check?(node) do
    case node do
      {:function_call, meta, _} when is_list(meta) ->
        func_name = Keyword.get(meta, :name, "")
        func_lower = String.downcase(func_name)

        String.contains?(func_lower, "size") or
          String.contains?(func_lower, "type") or
          String.contains?(func_lower, "ext")

      {:attribute_access, _meta, children} when is_list(children) ->
        Enum.any?(children, &involves_validation_variable?/1)

      _ ->
        false
    end
  end

  defp involves_validation_variable?(node) do
    case node do
      {:variable, _meta, name} when is_binary(name) ->
        name_lower = String.downcase(name)
        Enum.any?(@validation_indicators, &String.contains?(name_lower, &1))

      {:function_call, meta, _} when is_list(meta) ->
        func_name = Keyword.get(meta, :name, "")
        is_validation_function?(func_name)

      {:attribute_access, _meta, children} when is_list(children) ->
        Enum.any?(children, fn
          {:literal, _, attr} when is_binary(attr) or is_atom(attr) ->
            attr_lower = to_string(attr) |> String.downcase()
            Enum.any?(@validation_indicators, &String.contains?(attr_lower, &1))

          other ->
            involves_validation_variable?(other)
        end)

      _ ->
        false
    end
  end

  defp has_file_save_operation?(body) when is_list(body) do
    Enum.any?(body, &contains_file_save?/1)
  end

  defp contains_file_save?(node) do
    case node do
      {:function_call, meta, _args} when is_list(meta) ->
        func_name = Keyword.get(meta, :name, "")
        is_file_save_function?(func_name)

      {:pipe, _meta, stages} when is_list(stages) ->
        Enum.any?(stages, &contains_file_save?/1)

      {:block, _meta, statements} when is_list(statements) ->
        Enum.any?(statements, &contains_file_save?/1)

      tuple when is_tuple(tuple) ->
        tuple |> Tuple.to_list() |> Enum.any?(&contains_file_save?/1)

      list when is_list(list) ->
        Enum.any?(list, &contains_file_save?/1)

      _ ->
        false
    end
  end

  defp involves_upload?(args, _context) when is_list(args) do
    Enum.any?(args, fn arg ->
      case arg do
        {:variable, _meta, name} when is_binary(name) ->
          name_lower = String.downcase(name)
          Enum.any?(@upload_patterns, &String.contains?(name_lower, &1))

        {:attribute_access, _meta, children} when is_list(children) ->
          Enum.any?(children, fn
            {:variable, _, name} when is_binary(name) ->
              name_lower = String.downcase(name)
              Enum.any?(@upload_patterns, &String.contains?(name_lower, &1))

            _ ->
              false
          end)

        _ ->
          false
      end
    end)
  end

  defp involves_upload?(_, _), do: false

  defp in_validation_context?(context) do
    parent_stack = Map.get(context, :parent_stack, [])
    Enum.any?(parent_stack, &contains_validation?/1)
  end
end
