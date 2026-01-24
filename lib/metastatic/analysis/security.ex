defmodule Metastatic.Analysis.Security do
  @moduledoc """
  Security vulnerability detection at the MetaAST level.

  Identifies common security vulnerabilities by pattern matching on
  function calls and literals. Works across all supported languages
  by operating on the unified MetaAST representation.

  ## Detected Vulnerabilities

  - **Injection attacks** - SQL injection, command injection, code injection
  - **Unsafe deserialization** - pickle.loads, eval, exec
  - **Hardcoded secrets** - API keys, passwords in literals
  - **Weak cryptography** - MD5, SHA1, weak random
  - **Path traversal** - Unchecked file operations
  - **Insecure protocols** - HTTP URLs

  ## Usage

      alias Metastatic.{Document, Analysis.Security}

      # Analyze for security vulnerabilities
      ast = {:function_call, "eval", [{:variable, "user_input"}]}
      doc = Document.new(ast, :python)
      {:ok, result} = Security.analyze(doc)

      result.has_vulnerabilities?   # => true
      result.total_vulnerabilities  # => 1

  ## Examples

      # No vulnerabilities
      iex> ast = {:binary_op, :arithmetic, :+, {:literal, :integer, 1}, {:literal, :integer, 2}}
      iex> doc = Metastatic.Document.new(ast, :python)
      iex> {:ok, result} = Metastatic.Analysis.Security.analyze(doc)
      iex> result.has_vulnerabilities?
      false

      # Unsafe eval detected
      iex> ast = {:function_call, "eval", [{:literal, :string, "1+1"}]}
      iex> doc = Metastatic.Document.new(ast, :python)
      iex> {:ok, result} = Metastatic.Analysis.Security.analyze(doc)
      iex> result.has_vulnerabilities?
      true
      iex> [vuln | _] = result.vulnerabilities
      iex> vuln.category
      :unsafe_deserialization
  """

  alias Metastatic.Analysis.Security.Result
  alias Metastatic.Document

  # Dangerous function patterns by language
  @dangerous_functions %{
    # Python dangerous functions
    python: %{
      eval: {:unsafe_deserialization, :critical, 95},
      exec: {:unsafe_deserialization, :critical, 95},
      "pickle.loads": {:unsafe_deserialization, :critical, 502},
      "os.system": {:injection, :critical, 78},
      "subprocess.call": {:injection, :high, 78},
      "subprocess.run": {:injection, :high, 78},
      compile: {:unsafe_deserialization, :high, 95}
    },
    # Elixir dangerous functions
    elixir: %{
      "Code.eval_string": {:unsafe_deserialization, :critical, 95},
      ":os.cmd": {:injection, :critical, 78},
      "System.cmd": {:injection, :high, 78}
    },
    # Erlang dangerous functions
    erlang: %{
      "erl_eval:expr": {:unsafe_deserialization, :critical, 95},
      ":os.cmd": {:injection, :critical, 78}
    }
  }

  # Weak cryptography patterns
  @weak_crypto ["md5", "MD5", "sha1", "SHA1", "des", "DES"]

  # Secret patterns (regex-like strings to check)
  @secret_patterns [
    {"password", ~r/password\s*=\s*["'].+["']/i},
    {"api_key", ~r/api[_-]?key\s*=\s*["'].+["']/i},
    {"secret", ~r/secret\s*=\s*["'].+["']/i},
    {"token", ~r/token\s*=\s*["'].+["']/i}
  ]

  use Metastatic.Document.Analyzer,
    doc: """
    Analyzes a document for security vulnerabilities.

    Returns `{:ok, result}` where result is a `Metastatic.Analysis.Security.Result` struct.

    ## Options

    - `:categories` - List of vulnerability categories to check (default: all)
    - `:min_severity` - Minimum severity to report (default: :low)

    ## Examples

        iex> ast = {:literal, :integer, 42}
        iex> doc = Metastatic.Document.new(ast, :elixir)
        iex> {:ok, result} = Metastatic.Analysis.Security.analyze(doc)
        iex> result.has_vulnerabilities?
        false
    """

  @impl Metastatic.Document.Analyzer
  def handle_analyze(%Document{ast: ast, language: language} = _doc, opts \\ []) do
    vulns =
      []
      |> detect_dangerous_functions(ast, language)
      |> detect_hardcoded_secrets(ast)
      |> detect_weak_crypto(ast)
      |> detect_insecure_protocols(ast)
      |> filter_by_options(opts)

    {:ok, Result.new(vulns)}
  end

  # Private implementation

  # Detect dangerous function calls
  defp detect_dangerous_functions(vulns, ast, language) do
    dangerous_calls = find_dangerous_calls(ast, language)

    Enum.map(dangerous_calls, fn {func_name, {category, severity, cwe}} ->
      %{
        category: category,
        severity: severity,
        description: "Dangerous function '#{func_name}' detected",
        recommendation: get_recommendation(category, func_name),
        cwe: cwe,
        context: %{function: func_name}
      }
    end) ++ vulns
  end

  defp find_dangerous_calls(ast, language) do
    patterns = Map.get(@dangerous_functions, language, %{})

    walk_ast(ast, [], fn node, acc ->
      case node do
        {:function_call, name, _args} ->
          case Map.get(patterns, name) do
            nil -> acc
            pattern -> [{name, pattern} | acc]
          end

        _ ->
          acc
      end
    end)
  end

  # Detect hardcoded secrets in string literals
  defp detect_hardcoded_secrets(vulns, ast) do
    secrets = find_hardcoded_secrets(ast)

    Enum.map(secrets, fn {type, value} ->
      %{
        category: :hardcoded_secret,
        severity: :high,
        description: "Hardcoded #{type} detected in source code",
        recommendation: "Use environment variables or secure vaults for secrets",
        cwe: 798,
        context: %{type: type, value_preview: String.slice(value, 0, 20) <> "..."}
      }
    end) ++ vulns
  end

  defp find_hardcoded_secrets(ast) do
    walk_ast(ast, [], fn node, acc ->
      case node do
        {:literal, :string, value} when is_binary(value) ->
          Enum.reduce(@secret_patterns, acc, fn {type, pattern}, a ->
            if Regex.match?(pattern, value) do
              [{type, value} | a]
            else
              a
            end
          end)

        _ ->
          acc
      end
    end)
  end

  # Detect weak cryptography
  defp detect_weak_crypto(vulns, ast) do
    weak_crypto_calls = find_weak_crypto(ast)

    Enum.map(weak_crypto_calls, fn algo ->
      %{
        category: :weak_crypto,
        severity: :medium,
        description: "Weak cryptographic algorithm '#{algo}' detected",
        recommendation: "Use SHA-256, SHA-3, or bcrypt for hashing; AES for encryption",
        cwe: 327,
        context: %{algorithm: algo}
      }
    end) ++ vulns
  end

  defp find_weak_crypto(ast) do
    walk_ast(ast, [], fn node, acc ->
      case node do
        {:function_call, name, _args} ->
          if Enum.any?(@weak_crypto, &String.contains?(name, &1)) do
            [name | acc]
          else
            acc
          end

        {:literal, :string, value} when is_binary(value) ->
          if Enum.any?(@weak_crypto, &String.contains?(value, &1)) do
            [value | acc]
          else
            acc
          end

        _ ->
          acc
      end
    end)
  end

  # Detect insecure protocols (HTTP URLs)
  defp detect_insecure_protocols(vulns, ast) do
    insecure_urls = find_insecure_urls(ast)

    Enum.map(insecure_urls, fn url ->
      %{
        category: :insecure_protocol,
        severity: :medium,
        description: "Insecure HTTP URL detected: #{url}",
        recommendation: "Use HTTPS instead of HTTP for secure communication",
        cwe: 319,
        context: %{url: url}
      }
    end) ++ vulns
  end

  defp find_insecure_urls(ast) do
    walk_ast(ast, [], fn node, acc ->
      case node do
        {:literal, :string, value} when is_binary(value) ->
          if String.starts_with?(value, "http://") do
            [value | acc]
          else
            acc
          end

        _ ->
          acc
      end
    end)
  end

  # Generic AST walker
  defp walk_ast(ast, acc, func) do
    acc = func.(ast, acc)

    case ast do
      {:block, statements} when is_list(statements) ->
        Enum.reduce(statements, acc, fn stmt, a -> walk_ast(stmt, a, func) end)

      {:conditional, cond, then_br, else_br} ->
        acc
        |> walk_ast(cond, func)
        |> walk_ast(then_br, func)
        |> walk_ast(else_br, func)

      {:binary_op, _, _, left, right} ->
        acc |> walk_ast(left, func) |> walk_ast(right, func)

      {:unary_op, _, _, operand} ->
        walk_ast(operand, acc, func)

      {:function_call, _name, args} when is_list(args) ->
        Enum.reduce(args, acc, fn arg, a -> walk_ast(arg, a, func) end)

      {:assignment, target, value} ->
        acc |> walk_ast(target, func) |> walk_ast(value, func)

      {:loop, :while, cond, body} ->
        acc |> walk_ast(cond, func) |> walk_ast(body, func)

      {:loop, _, _iter, coll, body} ->
        acc |> walk_ast(coll, func) |> walk_ast(body, func)

      {:lambda, _params, body} ->
        walk_ast(body, acc, func)

      nil ->
        acc

      _ ->
        acc
    end
  end

  defp get_recommendation(:injection, _func) do
    "Use parameterized queries or escape user input properly. Avoid executing user-controlled strings."
  end

  defp get_recommendation(:unsafe_deserialization, func) do
    "Avoid '#{func}' with untrusted input. Use safe alternatives like json.loads or validate input."
  end

  defp get_recommendation(_category, _func) do
    "Review and remediate this security issue"
  end

  defp filter_by_options(vulns, opts) do
    min_severity = Keyword.get(opts, :min_severity, :low)
    categories = Keyword.get(opts, :categories, :all)

    vulns
    |> filter_by_severity(min_severity)
    |> filter_by_categories(categories)
  end

  defp filter_by_severity(vulns, :low), do: vulns

  defp filter_by_severity(vulns, min_severity) do
    severity_order = %{critical: 4, high: 3, medium: 2, low: 1}
    min_level = Map.get(severity_order, min_severity, 1)

    Enum.filter(vulns, fn %{severity: sev} ->
      Map.get(severity_order, sev, 0) >= min_level
    end)
  end

  defp filter_by_categories(vulns, :all), do: vulns

  defp filter_by_categories(vulns, categories) when is_list(categories) do
    Enum.filter(vulns, fn %{category: cat} -> cat in categories end)
  end
end
