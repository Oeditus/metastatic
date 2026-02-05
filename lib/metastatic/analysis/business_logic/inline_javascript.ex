defmodule Metastatic.Analysis.BusinessLogic.InlineJavascript do
  @moduledoc """
  Detects inline executable code in templates/strings (XSS/injection risk).

  Universal pattern: embedding code directly in strings/templates without sanitization.

  ## Examples

  **Python (Django template with unsafe JS):**
  ```python
  html = f'<script>var userId = {user_id};</script>'  # XSS risk - unescaped data
  ```

  **JavaScript (React with dangerouslySetInnerHTML):**
  ```javascript
  return <div dangerouslySetInnerHTML={{__html: userContent}} />;  # XSS vulnerability
  ```

  **Elixir (Phoenix template with raw JS):**
  ```elixir
  ~H\"\"\"
  <script>
    window.userId = <%= @user_id %>;  # Should use Phoenix.HTML.Tag or json encode
  </script>
  \"\"\"
  ```

  **C# (ASP.NET with Html.Raw):**
  ```csharp
  @Html.Raw($\"<script>var userId = {userId};</script>\")  # XSS risk
  ```

  **Go (template with unescaped JS):**
  ```go
  tmpl := template.Must(template.New(\"page\").Parse(
      `<script>var userId = {{.UserID}};</script>`  # Should use JS escaping
  ))
  ```

  **Java (JSP with script tag):**
  ```java
  out.println(\"<script>var userId = \" + userId + \";</script>\");  # XSS vulnerability
  ```

  **Ruby (Rails with javascript_tag):**
  ```ruby
  javascript_tag "var userId = " + user_id.to_s  # Should use escape_javascript
  ```

  **PHP (inline script without escaping):**
  ```php
  echo \"<script>var userId = $userId;</script>\";  # XSS risk - use htmlspecialchars
  ```
  """

  @behaviour Metastatic.Analysis.Analyzer
  alias Metastatic.Analysis.Analyzer

  @dangerous_patterns [
    "<script>",
    "</script>",
    "dangerouslysetinnerhtml",
    "html.raw",
    "javascript:",
    "onclick=",
    "onerror="
  ]

  @impl true
  def info do
    %{
      name: :inline_javascript,
      category: :security,
      description: "Detects inline JavaScript/code in strings (XSS risk)",
      severity: :error,
      explanation: "Avoid inline scripts - use CSP-compliant external scripts or proper escaping",
      configurable: true
    }
  end

  @impl true
  def analyze({:literal, meta, content} = node, _context)
      when is_list(meta) and is_binary(content) do
    # Check if this is a string literal in 3-tuple format
    if Keyword.get(meta, :subtype) == :string do
      content_lower = String.downcase(content)

      if Enum.any?(@dangerous_patterns, &String.contains?(content_lower, &1)) do
        [
          Analyzer.issue(
            analyzer: __MODULE__,
            category: :security,
            severity: :error,
            message: "Inline JavaScript in string literal - XSS vulnerability",
            node: node,
            metadata: %{
              pattern: "inline_script",
              suggestion: "Use external scripts, CSP, or proper escaping/sanitization"
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

  def analyze({:function_call, meta, args} = node, _context) when is_list(meta) do
    fn_name = Keyword.get(meta, :name, "")
    fn_lower = String.downcase(fn_name)

    # Check for dangerous functions
    if String.contains?(fn_lower, [
         "dangerouslysetinnerhtml",
         "html.raw",
         "javascript_tag"
       ]) do
      [
        Analyzer.issue(
          analyzer: __MODULE__,
          category: :security,
          severity: :error,
          message: "Using '#{fn_name}' to inject HTML/JS - potential XSS vulnerability",
          node: node,
          metadata: %{
            function: fn_name,
            suggestion: "Sanitize content or use framework's safe rendering methods"
          }
        )
      ]
    else
      # Check if args contain script tags
      if has_script_in_args?(args) do
        [
          Analyzer.issue(
            analyzer: __MODULE__,
            category: :security,
            severity: :warning,
            message: "Function call contains inline script - verify proper escaping",
            node: node,
            metadata: %{
              suggestion: "Ensure all user data is properly escaped"
            }
          )
        ]
      else
        []
      end
    end
  end

  def analyze(_node, _context), do: []

  defp has_script_in_args?(args) when is_list(args) do
    Enum.any?(args, fn
      {:literal, meta, content} when is_list(meta) and is_binary(content) ->
        Keyword.get(meta, :subtype) == :string and
          String.contains?(String.downcase(content), ["<script>", "</script>"])

      _ ->
        false
    end)
  end

  defp has_script_in_args?(_), do: false
end
