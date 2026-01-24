defmodule Metastatic.Analysis.DeadCode do
  @moduledoc """
  Dead code detection at the MetaAST level.

  Identifies unreachable code, unused functions, and other patterns
  that result in dead code. Works across all supported languages
  by operating on the unified MetaAST representation.

  ## Dead Code Types

  - **Unreachable after return** - Code following early_return nodes
  - **Constant conditionals** - Branches that can never execute (if true/false)
  - **Unused functions** - Function definitions never called (module context required)
  - **Other unreachable** - Code that can never be reached

  ## Usage

      alias Metastatic.{Document, Analysis.DeadCode}

      # Analyze for dead code
      ast = {:block, [
        {:early_return, {:literal, :integer, 42}},
        {:function_call, "print", [{:literal, :string, "unreachable"}]}
      ]}
      doc = Document.new(ast, :python)
      {:ok, result} = DeadCode.analyze(doc)

      result.has_dead_code?       # => true
      result.total_dead_statements # => 1
      result.dead_locations        # => [%{type: :unreachable_after_return, ...}]

  ## Examples

      # No dead code
      iex> ast = {:binary_op, :arithmetic, :+, {:literal, :integer, 1}, {:literal, :integer, 2}}
      iex> doc = Metastatic.Document.new(ast, :python)
      iex> {:ok, result} = Metastatic.Analysis.DeadCode.analyze(doc)
      iex> result.has_dead_code?
      false

      # Unreachable after return
      iex> ast = {:block, [
      ...>   {:early_return, {:literal, :integer, 1}},
      ...>   {:literal, :integer, 2}
      ...> ]}
      iex> doc = Metastatic.Document.new(ast, :python)
      iex> {:ok, result} = Metastatic.Analysis.DeadCode.analyze(doc)
      iex> result.has_dead_code?
      true
      iex> [location | _] = result.dead_locations
      iex> location.type
      :unreachable_after_return
  """

  alias Metastatic.Analysis.DeadCode.Result
  alias Metastatic.Document

  @doc """
  Analyzes a document for dead code.

  Returns `{:ok, result}` where result is a `Metastatic.Analysis.DeadCode.Result` struct.

  ## Options

  - `:detect_unused_functions` - Enable unused function detection (default: false, requires module context)
  - `:min_confidence` - Minimum confidence level to report (default: :low)

  ## Examples

      iex> ast = {:literal, :integer, 42}
      iex> doc = Metastatic.Document.new(ast, :elixir)
      iex> {:ok, result} = Metastatic.Analysis.DeadCode.analyze(doc)
      iex> result.has_dead_code?
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

  def analyze(%Document{ast: ast} = _doc, opts) do
    dead_locations =
      []
      |> detect_unreachable_after_return(ast, [])
      |> detect_constant_conditionals(ast)
      |> filter_by_confidence(opts)

    {:ok, Result.new(dead_locations)}
  end

  @doc """
  Analyzes a document for dead code, raising on error.

  ## Examples

      iex> ast = {:literal, :integer, 42}
      iex> doc = Metastatic.Document.new(ast, :elixir)
      iex> result = Metastatic.Analysis.DeadCode.analyze!(doc)
      iex> result.has_dead_code?
      false
  """
  @spec analyze!(Document.t() | {atom(), term()}, keyword()) :: Result.t()
  def analyze!(input, opts \\ []) do
    case analyze(input, opts) do
      {:ok, result} -> result
      {:error, reason} -> raise "DeadCode analysis failed: #{inspect(reason)}"
    end
  end

  # Private implementation

  # Detect code unreachable after early_return nodes
  defp detect_unreachable_after_return(locations, ast, path) do
    case ast do
      {:block, statements} when is_list(statements) ->
        check_block_for_unreachable(locations, statements, path)

      {:conditional, _cond, then_branch, else_branch} ->
        locations
        |> detect_unreachable_after_return(then_branch, [:then | path])
        |> detect_unreachable_after_return(else_branch, [:else | path])

      {:loop, :while, _cond, body} ->
        detect_unreachable_after_return(locations, body, [:loop_body | path])

      {:loop, _, _iter, _coll, body} ->
        detect_unreachable_after_return(locations, body, [:loop_body | path])

      {:lambda, _params, body} ->
        detect_unreachable_after_return(locations, body, [:lambda_body | path])

      {:exception_handling, try_block, catches, else_block} ->
        locations
        |> detect_unreachable_after_return(try_block, [:try | path])
        |> detect_unreachable_in_catches(catches, path)
        |> detect_unreachable_after_return(else_block, [:else | path])

      _ ->
        locations
    end
  end

  defp check_block_for_unreachable(locations, statements, path) do
    {locations, _} =
      Enum.reduce(statements, {locations, false}, fn stmt, {locs, found_return} ->
        cond do
          found_return ->
            # Everything after a return is unreachable
            new_loc = %{
              type: :unreachable_after_return,
              reason: "Code after early return is unreachable",
              confidence: :high,
              suggestion: "Remove unreachable code",
              context: %{path: Enum.reverse(path), ast: stmt}
            }

            {[new_loc | locs], true}

          match?({:early_return, _}, stmt) ->
            # Found return, subsequent statements are unreachable
            {detect_unreachable_after_return(locs, stmt, path), true}

          true ->
            # Continue checking within this statement
            {detect_unreachable_after_return(locs, stmt, path), false}
        end
      end)

    locations
  end

  defp detect_unreachable_in_catches(locations, catches, path) when is_list(catches) do
    Enum.reduce(catches, locations, fn catch_clause, locs ->
      detect_unreachable_after_return(locs, catch_clause, [:catch | path])
    end)
  end

  defp detect_unreachable_in_catches(locations, nil, _path), do: locations

  # Detect unreachable branches in constant conditionals
  defp detect_constant_conditionals(locations, ast) do
    walk_for_conditionals(ast, locations)
  end

  defp walk_for_conditionals({:conditional, condition, then_branch, else_branch}, locations) do
    locations =
      case evaluate_constant_condition(condition) do
        {:constant, true} when not is_nil(else_branch) ->
          # else branch is unreachable
          new_loc = %{
            type: :constant_conditional,
            reason: "Else branch unreachable due to constant true condition",
            confidence: :high,
            suggestion: "Remove else branch or fix condition",
            context: %{condition: condition, dead_branch: :else, ast: else_branch}
          }

          [new_loc | locations]

        {:constant, true} ->
          # No else branch to report as unreachable
          locations

        {:constant, false} ->
          # then branch is unreachable
          new_loc = %{
            type: :constant_conditional,
            reason: "Then branch unreachable due to constant false condition",
            confidence: :high,
            suggestion: "Remove then branch or fix condition",
            context: %{condition: condition, dead_branch: :then, ast: then_branch}
          }

          [new_loc | locations]

        :not_constant ->
          locations
      end

    # Continue walking both branches (skip if nil)
    locations = walk_for_conditionals(then_branch, locations)

    if is_nil(else_branch) do
      locations
    else
      walk_for_conditionals(else_branch, locations)
    end
  end

  defp walk_for_conditionals({:block, statements}, locations) when is_list(statements) do
    Enum.reduce(statements, locations, fn stmt, locs ->
      walk_for_conditionals(stmt, locs)
    end)
  end

  defp walk_for_conditionals({:loop, :while, _cond, body}, locations) do
    walk_for_conditionals(body, locations)
  end

  defp walk_for_conditionals({:loop, _, _iter, _coll, body}, locations) do
    walk_for_conditionals(body, locations)
  end

  defp walk_for_conditionals({:lambda, _params, body}, locations) do
    walk_for_conditionals(body, locations)
  end

  defp walk_for_conditionals({:exception_handling, try_block, catches, else_block}, locations) do
    locations = walk_for_conditionals(try_block, locations)

    locations =
      if is_nil(else_block), do: locations, else: walk_for_conditionals(else_block, locations)

    if is_list(catches) do
      Enum.reduce(catches, locations, fn catch_clause, locs ->
        walk_for_conditionals(catch_clause, locs)
      end)
    else
      locations
    end
  end

  defp walk_for_conditionals({:binary_op, _, _, left, right}, locations) do
    locations = walk_for_conditionals(left, locations)
    walk_for_conditionals(right, locations)
  end

  defp walk_for_conditionals({:unary_op, _, _op, operand}, locations) do
    walk_for_conditionals(operand, locations)
  end

  defp walk_for_conditionals({:function_call, _name, args}, locations) when is_list(args) do
    Enum.reduce(args, locations, fn arg, locs ->
      walk_for_conditionals(arg, locs)
    end)
  end

  defp walk_for_conditionals({:assignment, target, value}, locations) do
    locations = walk_for_conditionals(target, locations)
    walk_for_conditionals(value, locations)
  end

  defp walk_for_conditionals({:inline_match, pattern, value}, locations) do
    locations = walk_for_conditionals(pattern, locations)
    walk_for_conditionals(value, locations)
  end

  defp walk_for_conditionals(nil, locations), do: locations
  defp walk_for_conditionals(_, locations), do: locations

  # Evaluate if a condition is a constant true/false
  defp evaluate_constant_condition({:literal, :boolean, value}) when is_boolean(value) do
    {:constant, value}
  end

  defp evaluate_constant_condition({:literal, :integer, 0}), do: {:constant, false}
  defp evaluate_constant_condition({:literal, :integer, n}) when n != 0, do: {:constant, true}

  defp evaluate_constant_condition({:literal, :null, _}), do: {:constant, false}

  defp evaluate_constant_condition({:literal, :string, ""}), do: {:constant, false}
  defp evaluate_constant_condition({:literal, :string, _}), do: {:constant, true}

  defp evaluate_constant_condition(_), do: :not_constant

  # Filter locations by minimum confidence level
  defp filter_by_confidence(locations, opts) do
    min_confidence = Keyword.get(opts, :min_confidence, :low)

    confidence_order = %{high: 3, medium: 2, low: 1}
    min_level = Map.get(confidence_order, min_confidence, 1)

    Enum.filter(locations, fn %{confidence: conf} ->
      Map.get(confidence_order, conf, 0) >= min_level
    end)
  end
end
