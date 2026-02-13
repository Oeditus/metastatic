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
      ast = {:function_call, [name: "eval"], [{:variable, [], "user_input"}]}
      doc = Document.new(ast, :python)
      {:ok, result} = Security.analyze(doc)

      result.has_vulnerabilities?   # => true
      result.total_vulnerabilities  # => 1

  ## Examples

      # No vulnerabilities
      iex> ast = {:binary_op, [category: :arithmetic, operator: :+], [{:literal, [subtype: :integer], 1}, {:literal, [subtype: :integer], 2}]}
      iex> doc = Metastatic.Document.new(ast, :python)
      iex> {:ok, result} = Metastatic.Analysis.Security.analyze(doc)
      iex> result.has_vulnerabilities?
      false

      # Unsafe eval detected
      iex> ast = {:function_call, [name: "eval"], [{:literal, [subtype: :string], "1+1"}]}
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

  # Dangerous function patterns by language (expanded for CWE-502 coverage)
  @dangerous_functions %{
    # Python dangerous functions
    python: %{
      # CWE-94/95: Code Injection
      "eval" => {:unsafe_deserialization, :critical, 95},
      "exec" => {:unsafe_deserialization, :critical, 95},
      "compile" => {:unsafe_deserialization, :high, 95},
      # CWE-502: Unsafe Deserialization
      "pickle.loads" => {:unsafe_deserialization, :critical, 502},
      "pickle.load" => {:unsafe_deserialization, :critical, 502},
      "cPickle.loads" => {:unsafe_deserialization, :critical, 502},
      "cPickle.load" => {:unsafe_deserialization, :critical, 502},
      "marshal.loads" => {:unsafe_deserialization, :critical, 502},
      "marshal.load" => {:unsafe_deserialization, :critical, 502},
      # Without safe_load
      "yaml.load" => {:unsafe_deserialization, :high, 502},
      "yaml.unsafe_load" => {:unsafe_deserialization, :critical, 502},
      "jsonpickle.decode" => {:unsafe_deserialization, :high, 502},
      "shelve.open" => {:unsafe_deserialization, :high, 502},
      "dill.loads" => {:unsafe_deserialization, :critical, 502},
      # CWE-78: Command Injection
      "os.system" => {:injection, :critical, 78},
      "subprocess.call" => {:injection, :high, 78},
      "subprocess.run" => {:injection, :high, 78},
      "subprocess.Popen" => {:injection, :high, 78}
    },
    # JavaScript dangerous functions
    javascript: %{
      # CWE-94/95: Code Injection
      "eval" => {:unsafe_deserialization, :critical, 95},
      "Function" => {:unsafe_deserialization, :critical, 95},
      # CWE-502: Unsafe Deserialization
      "serialize-javascript" => {:unsafe_deserialization, :high, 502},
      "node-serialize" => {:unsafe_deserialization, :critical, 502},
      "funcster" => {:unsafe_deserialization, :critical, 502},
      # CWE-78: Command Injection
      "child_process.exec" => {:injection, :critical, 78},
      "child_process.execSync" => {:injection, :critical, 78}
    },
    # Elixir dangerous functions
    elixir: %{
      # CWE-94/95: Code Injection
      "Code.eval_string" => {:unsafe_deserialization, :critical, 95},
      "Code.eval_quoted" => {:unsafe_deserialization, :critical, 95},
      "Code.eval_file" => {:unsafe_deserialization, :critical, 95},
      # CWE-502: Unsafe Deserialization
      ":erlang.binary_to_term" => {:unsafe_deserialization, :critical, 502},
      "Plug.Crypto.non_executable_binary_to_term" => {:unsafe_deserialization, :high, 502},
      # CWE-78: Command Injection
      ":os.cmd" => {:injection, :critical, 78},
      "System.cmd" => {:injection, :high, 78},
      "System.shell" => {:injection, :critical, 78}
    },
    # Ruby dangerous functions
    ruby: %{
      # CWE-94/95: Code Injection
      "eval" => {:unsafe_deserialization, :critical, 95},
      "instance_eval" => {:unsafe_deserialization, :critical, 95},
      "class_eval" => {:unsafe_deserialization, :critical, 95},
      # CWE-502: Unsafe Deserialization
      "Marshal.load" => {:unsafe_deserialization, :critical, 502},
      "Marshal.restore" => {:unsafe_deserialization, :critical, 502},
      "YAML.load" => {:unsafe_deserialization, :high, 502},
      "Psych.load" => {:unsafe_deserialization, :high, 502},
      "Oj.load" => {:unsafe_deserialization, :high, 502},
      # CWE-78: Command Injection
      "system" => {:injection, :critical, 78},
      "exec" => {:injection, :critical, 78},
      "`" => {:injection, :critical, 78}
    },
    # Java dangerous functions
    java: %{
      # CWE-502: Unsafe Deserialization
      "ObjectInputStream.readObject" => {:unsafe_deserialization, :critical, 502},
      "XMLDecoder.readObject" => {:unsafe_deserialization, :critical, 502},
      "XStream.fromXML" => {:unsafe_deserialization, :high, 502},
      "ObjectMapper.readValue" => {:unsafe_deserialization, :high, 502},
      "Yaml.load" => {:unsafe_deserialization, :high, 502},
      # CWE-78: Command Injection
      "Runtime.exec" => {:injection, :critical, 78},
      "ProcessBuilder" => {:injection, :high, 78}
    },
    # Erlang dangerous functions
    erlang: %{
      "erl_eval:expr" => {:unsafe_deserialization, :critical, 95},
      "erl_eval:exprs" => {:unsafe_deserialization, :critical, 95},
      # CWE-502: Unsafe Deserialization
      "binary_to_term" => {:unsafe_deserialization, :critical, 502},
      "erlang:binary_to_term" => {:unsafe_deserialization, :critical, 502},
      # CWE-78: Command Injection
      ":os.cmd" => {:injection, :critical, 78},
      "os:cmd" => {:injection, :critical, 78}
    }
  }

  # Weak cryptography patterns
  @weak_crypto ["md5", "MD5", "sha1", "SHA1", "des", "DES"]

  # Secret patterns (regex-like strings to check)
  # Note: These are defined as a function to avoid Elixir 1.18 attribute escaping issues
  defp secret_patterns do
    [
      # Patterns matching assignment/declaration syntax
      {"password", ~r/password[\s:=]+["'].+["']/i},
      {"api_key", ~r/api[_-]?key[\s:=]+["'].+["']/i},
      {"secret", ~r/secret[\s:=]+["'].+["']/i},
      {"token", ~r/token[\s:=]+["'].+["']/i},
      # Patterns matching secret-like string content
      {"api_key", ~r/^(sk|pk|Bearer|[A-Za-z0-9_-]{32,}$)/},
      {"token", ~r/^[A-Za-z0-9_.-]{20,}$/},
      {"secret", ~r/^[A-Za-z0-9+\/=]{40,}$/}
    ]
  end

  use Metastatic.Document.Analyzer,
    doc: """
    Analyzes a document for security vulnerabilities.

    Returns `{:ok, result}` where result is a `Metastatic.Analysis.Security.Result` struct.

    ## Options

    - `:categories` - List of vulnerability categories to check (default: all)
    - `:min_severity` - Minimum severity to report (default: :low)

    ## Examples

        iex> ast = {:literal, [subtype: :integer], 42}
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

    vulns_from_calls =
      Enum.flat_map(dangerous_calls, fn
        {func_name, {category, severity, cwe}} when is_binary(func_name) ->
          [
            %{
              category: category,
              severity: severity,
              description: "Dangerous function '#{func_name}' detected",
              recommendation: get_recommendation(category, func_name),
              cwe: cwe,
              context: %{function: func_name}
            }
          ]

        _other ->
          # Skip malformed entries
          []
      end)

    vulns_from_calls ++ vulns
  end

  # 3-tuple format
  defp find_dangerous_calls(ast, language) do
    patterns = Map.get(@dangerous_functions, language, %{})

    walk_ast(ast, [], fn node, acc ->
      case node do
        {:function_call, meta, _args} when is_list(meta) ->
          name = Keyword.get(meta, :name, "")

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

  # 3-tuple format
  defp find_hardcoded_secrets(ast) do
    walk_ast(ast, [], fn node, acc ->
      with {:literal, meta, value} when is_list(meta) and is_binary(value) <- node,
           :string <- Keyword.get(meta, :subtype) do
        Enum.reduce(secret_patterns(), acc, fn {type, pattern}, acc ->
          if Regex.match?(pattern, value), do: [{type, value} | acc], else: acc
        end)
      else
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

  # 3-tuple format
  defp find_weak_crypto(ast) do
    walk_ast(ast, [], fn node, acc ->
      case node do
        {:function_call, meta, _args} when is_list(meta) ->
          name = Keyword.get(meta, :name, "")

          if Enum.any?(@weak_crypto, &String.contains?(name, &1)) do
            [name | acc]
          else
            acc
          end

        {:literal, meta, value} when is_list(meta) and is_binary(value) ->
          subtype = Keyword.get(meta, :subtype)

          if subtype == :string and Enum.any?(@weak_crypto, &String.contains?(value, &1)) do
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

  # 3-tuple format
  defp find_insecure_urls(ast) do
    walk_ast(ast, [], fn node, acc ->
      case node do
        {:literal, meta, value} when is_list(meta) and is_binary(value) ->
          subtype = Keyword.get(meta, :subtype)

          if subtype == :string and String.starts_with?(value, "http://") do
            [value | acc]
          else
            acc
          end

        _ ->
          acc
      end
    end)
  end

  # Generic AST walker (3-tuple format)
  defp walk_ast(ast, acc, func) do
    acc = func.(ast, acc)

    case ast do
      {:block, _meta, statements} when is_list(statements) ->
        Enum.reduce(statements, acc, fn stmt, a -> walk_ast(stmt, a, func) end)

      {:conditional, _meta, [cond_expr, then_br, else_br]} ->
        acc = walk_ast(cond_expr, acc, func)
        acc = walk_ast(then_br, acc, func)
        walk_ast(else_br, acc, func)

      {:binary_op, _meta, [left, right]} ->
        acc = walk_ast(left, acc, func)
        walk_ast(right, acc, func)

      {:unary_op, _meta, [operand]} ->
        walk_ast(operand, acc, func)

      {:function_call, _meta, args} when is_list(args) ->
        Enum.reduce(args, acc, fn arg, a -> walk_ast(arg, a, func) end)

      {:assignment, _meta, [target, value]} ->
        acc = walk_ast(target, acc, func)
        walk_ast(value, acc, func)

      {:loop, meta, children} when is_list(meta) and is_list(children) ->
        Enum.reduce(children, acc, fn child, a -> walk_ast(child, a, func) end)

      {:lambda, _meta, [body]} ->
        walk_ast(body, acc, func)

      # M2.2s Structural layer (3-tuple format)
      {:container, meta, [body]} when is_list(meta) ->
        # Walk container body (modules, classes, etc.)
        if is_list(body) do
          Enum.reduce(body, acc, fn child, a -> walk_ast(child, a, func) end)
        else
          walk_ast(body, acc, func)
        end

      {:function_def, meta, [body]} when is_list(meta) ->
        # Walk function body
        walk_ast(body, acc, func)

      {:language_specific, meta, native_ast} when is_list(meta) and is_map(native_ast) ->
        # Walk through metadata values (which contain MetaAST)
        # Only walk values that are tuples (AST nodes) or lists
        Enum.reduce(Map.values(native_ast), acc, fn
          value, a when is_tuple(value) or is_list(value) -> walk_ast(value, a, func)
          _other, a -> a
        end)

      # Plain list (not wrapped in tuple) - walk each element
      list when is_list(list) ->
        Enum.reduce(list, acc, fn elem, a -> walk_ast(elem, a, func) end)

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
