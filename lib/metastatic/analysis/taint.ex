defmodule Metastatic.Analysis.Taint do
  @moduledoc """
  Taint analysis at the MetaAST level.

  Tracks data flow from untrusted sources (taint sources) to dangerous
  operations (taint sinks), identifying potential security vulnerabilities.
  Works across all supported languages.

  ## Taint Sources

  - User input functions (input, gets, argv)
  - File reads
  - Network requests
  - Environment variables

  ## Taint Sinks

  - Code execution (eval, exec, system)
  - SQL queries
  - File operations
  - Shell commands

  ## Usage

      alias Metastatic.{Document, Analysis.Taint}

      # Analyze for taint flows
      ast = {:function_call, [name: "eval"], [{:function_call, [name: "input"], []}]}
      doc = Document.new(ast, :python)
      {:ok, result} = Taint.analyze(doc)

      result.has_taint_flows?  # => true

  ## Examples

      # No taint flows
      iex> ast = {:binary_op, [category: :arithmetic, operator: :+], [{:literal, [subtype: :integer], 1}, {:literal, [subtype: :integer], 2}]}
      iex> doc = Metastatic.Document.new(ast, :python)
      iex> {:ok, result} = Metastatic.Analysis.Taint.analyze(doc)
      iex> result.has_taint_flows?
      false

      # Tainted data to sink
      iex> ast = {:function_call, [name: "eval"], [{:function_call, [name: "input"], []}]}
      iex> doc = Metastatic.Document.new(ast, :python)
      iex> {:ok, result} = Metastatic.Analysis.Taint.analyze(doc)
      iex> result.has_taint_flows?
      true
  """

  alias Metastatic.Analysis.Taint.Result
  alias Metastatic.Document

  # Taint sources by language (expanded for better CWE-78/77/94 coverage)
  @taint_sources %{
    python: [
      "input",
      "raw_input",
      "sys.argv",
      "request.args",
      "request.form",
      "request.data",
      "request.json",
      "request.files",
      "request.cookies",
      "os.environ",
      "getenv",
      "flask.request",
      "django.request",
      "sys.stdin",
      "fileinput"
    ],
    javascript: [
      "req.body",
      "req.query",
      "req.params",
      "req.headers",
      "req.cookies",
      "process.argv",
      "process.env",
      "readline",
      "prompt"
    ],
    elixir: [
      "IO.gets",
      "System.argv",
      "System.get_env",
      "conn.params",
      "conn.body_params",
      "conn.query_params",
      "socket.assigns",
      "Phoenix.LiveView"
    ],
    ruby: [
      "params",
      "request.params",
      "ARGV",
      "ENV",
      "gets",
      "readline",
      "request.body",
      "request.headers"
    ],
    erlang: ["io:get_line", "init:get_argument", "os:getenv"]
  }

  # Taint sinks by language (expanded for CWE-78/77/94)
  # CWE-78: OS Command Injection
  # CWE-77: Command Injection
  # CWE-94: Code Injection
  @taint_sinks %{
    python: [
      # CWE-94: Code Injection
      {"eval", :critical},
      {"exec", :critical},
      {"compile", :high},
      {"__import__", :high},
      {"importlib.import_module", :high},
      # CWE-78/77: Command Injection
      {"os.system", :critical},
      {"os.popen", :critical},
      {"subprocess.call", :high},
      {"subprocess.run", :high},
      {"subprocess.Popen", :high},
      {"commands.getoutput", :critical},
      {"commands.getstatusoutput", :critical},
      # Shell utilities
      {"os.execl", :critical},
      {"os.execle", :critical},
      {"os.execlp", :critical},
      {"os.execv", :critical},
      {"os.execve", :critical},
      {"os.spawnl", :high},
      {"os.spawnle", :high}
    ],
    javascript: [
      # CWE-94: Code Injection
      {"eval", :critical},
      {"Function", :critical},
      {"setTimeout", :high},
      {"setInterval", :high},
      {"new Function", :critical},
      # CWE-78/77: Command Injection
      {"child_process.exec", :critical},
      {"child_process.execSync", :critical},
      {"child_process.spawn", :high},
      {"child_process.spawnSync", :high},
      {"child_process.execFile", :high},
      {"require('child_process')", :high}
    ],
    elixir: [
      # CWE-94: Code Injection
      {"Code.eval_string", :critical},
      {"Code.eval_quoted", :critical},
      {"Code.eval_file", :critical},
      {"Code.compile_string", :high},
      # CWE-78/77: Command Injection
      {":os.cmd", :critical},
      {"System.cmd", :high},
      {"System.shell", :critical},
      {"Port.open", :high}
    ],
    ruby: [
      # CWE-94: Code Injection
      {"eval", :critical},
      {"instance_eval", :critical},
      {"class_eval", :critical},
      {"module_eval", :critical},
      {"send", :high},
      {"__send__", :high},
      {"public_send", :high},
      # CWE-78/77: Command Injection
      {"system", :critical},
      {"exec", :critical},
      # backticks
      {"`", :critical},
      {"%x", :critical},
      {"Open3.capture2", :high},
      {"Open3.capture3", :high},
      {"IO.popen", :high}
    ],
    erlang: [
      {"erl_eval:expr", :critical},
      {"erl_eval:exprs", :critical},
      {":os.cmd", :critical},
      {"open_port", :high}
    ]
  }
  use Metastatic.Document.Analyzer,
    doc: """
    Analyzes a document for taint flows.

    Returns `{:ok, result}` where result is a `Metastatic.Analysis.Taint.Result` struct.

    ## Examples

        iex> ast = {:literal, [subtype: :integer], 42}
        iex> doc = Metastatic.Document.new(ast, :elixir)
        iex> {:ok, result} = Metastatic.Analysis.Taint.analyze(doc)
        iex> result.has_taint_flows?
        false
    """

  @impl Metastatic.Document.Analyzer
  def handle_analyze(%Document{ast: ast, language: language} = _doc, _opts \\ []) do
    # Find taint sources
    sources = find_taint_sources(ast, language)

    # Find taint sinks
    sinks = find_taint_sinks(ast, language)

    # Detect flows from sources to sinks
    flows = detect_taint_flows(ast, sources, sinks)

    {:ok, Result.new(flows)}
  end

  # Private implementation

  # 3-tuple format
  defp find_taint_sources(ast, language) do
    source_funcs = Map.get(@taint_sources, language, [])

    walk_ast(ast, [], fn node, acc ->
      case node do
        {:function_call, meta, _args} when is_list(meta) ->
          name = Keyword.get(meta, :name, "")

          if name in source_funcs do
            [name | acc]
          else
            acc
          end

        {:variable, _meta, "argv"} ->
          ["argv" | acc]

        _ ->
          acc
      end
    end)
  end

  defp find_taint_sinks(ast, language) do
    sink_patterns = Map.get(@taint_sinks, language, [])

    walk_ast(ast, [], fn node, acc ->
      case node do
        {:function_call, meta, _args} when is_list(meta) ->
          name = Keyword.get(meta, :name, "")

          case Enum.find(sink_patterns, fn {n, _} -> n == name end) do
            {func, risk} -> [{func, risk} | acc]
            nil -> acc
          end

        _ ->
          acc
      end
    end)
  end

  # Simplified taint flow detection
  # Checks if any sink has a taint source in its arguments
  # 3-tuple format
  defp detect_taint_flows(ast, sources, sinks) do
    if Enum.empty?(sources) or Enum.empty?(sinks) do
      []
    else
      walk_ast(ast, [], fn node, acc ->
        with {:function_call, meta, args} when is_list(meta) <- node,
             name <- Keyword.get(meta, :name, ""),
             {sink_name, risk} when is_list(args) <-
               Enum.find(sinks, fn {sink_name, _} -> sink_name == name end),
             true <- has_taint_source?(args, sources) do
          flow = %{
            source: Enum.join(sources, ", "),
            sink: sink_name,
            risk: risk,
            path: [sink_name],
            recommendation: get_recommendation(risk)
          }

          [flow | acc]
        else
          _ -> acc
        end
      end)
    end
  end

  defp has_taint_source?(args, sources) when is_list(args) do
    Enum.any?(args, fn arg -> check_taint_in_ast(arg, sources) end)
  end

  defp check_taint_in_ast(ast, sources) do
    case ast do
      {:function_call, meta, _args} when is_list(meta) ->
        name = Keyword.get(meta, :name, "")
        name in sources

      {:variable, _meta, name} ->
        name in sources or name == "argv"

      {:binary_op, _meta, [left, right]} ->
        check_taint_in_ast(left, sources) or check_taint_in_ast(right, sources)

      {:block, _meta, statements} when is_list(statements) ->
        Enum.any?(statements, &check_taint_in_ast(&1, sources))

      _ ->
        false
    end
  end

  defp walk_ast(ast, acc, func) do
    acc = func.(ast, acc)

    case ast do
      {:block, _meta, statements} when is_list(statements) ->
        Enum.reduce(statements, acc, fn stmt, a -> walk_ast(stmt, a, func) end)

      {:conditional, _meta, [cond_expr, then_br, else_br]} ->
        acc
        |> walk_ast(cond_expr, func)
        |> walk_ast(then_br, func)
        |> walk_ast(else_br, func)

      {:binary_op, _meta, [left, right]} ->
        acc |> walk_ast(left, func) |> walk_ast(right, func)

      {:function_call, _meta, args} when is_list(args) ->
        Enum.reduce(args, acc, fn arg, a -> walk_ast(arg, a, func) end)

      {:assignment, _meta, [target, value]} ->
        acc |> walk_ast(target, func) |> walk_ast(value, func)

      {:loop, meta, children} when is_list(meta) and is_list(children) ->
        Enum.reduce(children, acc, fn child, a -> walk_ast(child, a, func) end)

      nil ->
        acc

      _ ->
        acc
    end
  end

  defp get_recommendation(:critical) do
    "Never pass untrusted input to code execution functions. Validate and sanitize all input."
  end

  defp get_recommendation(:high) do
    "Sanitize and validate all user input before use. Use parameterized queries or safe alternatives."
  end

  defp get_recommendation(_) do
    "Review data flow and add appropriate input validation."
  end
end
