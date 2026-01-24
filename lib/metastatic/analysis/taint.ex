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
      ast = {:function_call, "eval", [{:function_call, "input", []}]}
      doc = Document.new(ast, :python)
      {:ok, result} = Taint.analyze(doc)

      result.has_taint_flows?  # => true

  ## Examples

      # No taint flows
      iex> ast = {:binary_op, :arithmetic, :+, {:literal, :integer, 1}, {:literal, :integer, 2}}
      iex> doc = Metastatic.Document.new(ast, :python)
      iex> {:ok, result} = Metastatic.Analysis.Taint.analyze(doc)
      iex> result.has_taint_flows?
      false

      # Tainted data to sink
      iex> ast = {:function_call, "eval", [{:function_call, "input", []}]}
      iex> doc = Metastatic.Document.new(ast, :python)
      iex> {:ok, result} = Metastatic.Analysis.Taint.analyze(doc)
      iex> result.has_taint_flows?
      true
  """

  alias Metastatic.Analysis.Taint.Result
  alias Metastatic.Document

  # Taint sources by language
  @taint_sources %{
    python: ["input", "raw_input", "sys.argv", "request.args", "request.form"],
    elixir: ["IO.gets", "System.argv"],
    erlang: ["io:get_line", "init:get_argument"]
  }

  # Taint sinks by language
  @taint_sinks %{
    python: [
      {"eval", :critical},
      {"exec", :critical},
      {"os.system", :critical},
      {"subprocess.call", :high},
      {"compile", :high}
    ],
    elixir: [
      {"Code.eval_string", :critical},
      {":os.cmd", :critical},
      {"System.cmd", :high}
    ],
    erlang: [
      {"erl_eval:expr", :critical},
      {":os.cmd", :critical}
    ]
  }

  @doc """
  Analyzes a document for taint flows.

  Returns `{:ok, result}` where result is a `Metastatic.Analysis.Taint.Result` struct.

  ## Examples

      iex> ast = {:literal, :integer, 42}
      iex> doc = Metastatic.Document.new(ast, :elixir)
      iex> {:ok, result} = Metastatic.Analysis.Taint.analyze(doc)
      iex> result.has_taint_flows?
      false
  """
  @spec analyze(Document.t() | {atom(), term()}, keyword()) ::
          {:ok, Result.t()} | {:error, term()}
  def analyze(input, opts \\ [])

  def analyze(input, opts) when is_tuple(input) do
    case Document.normalize(input) do
      {:ok, doc} -> analyze(doc, opts)
      {:error, reason} -> {:error, reason}
    end
  end

  def analyze(%Document{ast: ast, language: language} = _doc, _opts) do
    # Find taint sources
    sources = find_taint_sources(ast, language)

    # Find taint sinks
    sinks = find_taint_sinks(ast, language)

    # Detect flows from sources to sinks
    flows = detect_taint_flows(ast, sources, sinks)

    {:ok, Result.new(flows)}
  end

  @doc """
  Analyzes a document for taint flows, raising on error.

  ## Examples

      iex> ast = {:literal, :integer, 42}
      iex> doc = Metastatic.Document.new(ast, :elixir)
      iex> result = Metastatic.Analysis.Taint.analyze!(doc)
      iex> result.has_taint_flows?
      false
  """
  @spec analyze!(Document.t() | {atom(), term()}, keyword()) :: Result.t()
  def analyze!(input, opts \\ []) do
    case analyze(input, opts) do
      {:ok, result} -> result
      {:error, reason} -> raise "Taint analysis failed: #{inspect(reason)}"
    end
  end

  # Private implementation

  defp find_taint_sources(ast, language) do
    source_funcs = Map.get(@taint_sources, language, [])

    walk_ast(ast, [], fn node, acc ->
      case node do
        {:function_call, name, _args} ->
          if name in source_funcs do
            [name | acc]
          else
            acc
          end

        {:variable, "argv"} ->
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
        {:function_call, name, _args} ->
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
  defp detect_taint_flows(ast, sources, sinks) do
    if Enum.empty?(sources) or Enum.empty?(sinks) do
      []
    else
      walk_ast(ast, [], fn node, acc ->
        with {:function_call, name, args} <- node,
             {sink_name, risk} <- Enum.find(sinks, fn {sink_name, _} -> sink_name == name end),
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
      {:function_call, name, _} ->
        name in sources

      {:variable, name} ->
        name in sources or name == "argv"

      {:binary_op, _, _, left, right} ->
        check_taint_in_ast(left, sources) or check_taint_in_ast(right, sources)

      {:block, statements} when is_list(statements) ->
        Enum.any?(statements, &check_taint_in_ast(&1, sources))

      _ ->
        false
    end
  end

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

      {:function_call, _name, args} when is_list(args) ->
        Enum.reduce(args, acc, fn arg, a -> walk_ast(arg, a, func) end)

      {:assignment, target, value} ->
        acc |> walk_ast(target, func) |> walk_ast(value, func)

      {:loop, :while, cond, body} ->
        acc |> walk_ast(cond, func) |> walk_ast(body, func)

      {:loop, _, _iter, coll, body} ->
        acc |> walk_ast(coll, func) |> walk_ast(body, func)

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
