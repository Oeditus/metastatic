defmodule Metastatic.Analysis.Smells do
  @moduledoc """
  Code smell detection at the MetaAST level.

  Identifies design and maintainability issues that indicate poor code quality.
  Works across all supported languages by operating on the unified MetaAST
  representation and leveraging existing complexity metrics.

  ## Detected Smells

  - **Long function** - Too many statements (threshold: 50)
  - **Deep nesting** - Excessive nesting depth (threshold: 4)
  - **Magic numbers** - Unexplained numeric literals in expressions
  - **Complex conditionals** - Deeply nested boolean operations
  - **Long parameter list** - Too many parameters (threshold: 5)

  ## Usage

      alias Metastatic.{Document, Analysis.Smells}

      # Analyze for code smells
      ast = {:block, (for i <- 1..100, do: {:literal, :integer, i})}
      doc = Document.new(ast, :python)
      {:ok, result} = Smells.analyze(doc)

      result.has_smells?    # => true
      result.total_smells   # => 1
      result.smells         # => [%{type: :long_function, ...}]

  ## Examples

      # No code smells
      iex> ast = {:binary_op, :arithmetic, :+, {:literal, :integer, 1}, {:literal, :integer, 2}}
      iex> doc = Metastatic.Document.new(ast, :python)
      iex> {:ok, result} = Metastatic.Analysis.Smells.analyze(doc)
      iex> result.has_smells?
      false

      # Magic number detected
      iex> ast = {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 42}}
      iex> doc = Metastatic.Document.new(ast, :python)
      iex> {:ok, result} = Metastatic.Analysis.Smells.analyze(doc)
      iex> result.has_smells?
      true
      iex> [smell | _] = result.smells
      iex> smell.type
      :magic_number
  """

  alias Metastatic.Analysis.{Complexity, Smells.Result}
  alias Metastatic.Document

  # Default thresholds
  @default_thresholds %{
    max_statements: 50,
    max_nesting: 4,
    max_parameters: 5,
    max_cognitive: 15
  }

  @doc """
  Analyzes a document for code smells.

  Returns `{:ok, result}` where result is a `Metastatic.Analysis.Smells.Result` struct.

  ## Options

  - `:thresholds` - Map of threshold overrides (see default thresholds)
  - `:detect` - List of smell types to detect (default: all)

  ## Examples

      iex> ast = {:literal, :integer, 42}
      iex> doc = Metastatic.Document.new(ast, :elixir)
      iex> {:ok, result} = Metastatic.Analysis.Smells.analyze(doc)
      iex> result.has_smells?
      false
  """
  @spec analyze(Document.t(), keyword()) :: {:ok, Result.t()}
  def analyze(%Document{ast: ast} = doc, opts \\ []) do
    thresholds = Keyword.get(opts, :thresholds, %{}) |> merge_thresholds()

    smells =
      []
      |> detect_long_function(doc, thresholds)
      |> detect_deep_nesting(doc, thresholds)

    magic_smells = detect_magic_numbers(ast, thresholds)
    complex_smells = detect_complex_conditionals(ast, thresholds)

    smells = smells ++ magic_smells ++ complex_smells

    {:ok, Result.new(smells)}
  end

  @doc """
  Analyzes a document for code smells, raising on error.

  ## Examples

      iex> ast = {:literal, :integer, 42}
      iex> doc = Metastatic.Document.new(ast, :elixir)
      iex> result = Metastatic.Analysis.Smells.analyze!(doc)
      iex> result.has_smells?
      false
  """
  @spec analyze!(Document.t(), keyword()) :: Result.t()
  def analyze!(doc, opts \\ []) do
    {:ok, result} = analyze(doc, opts)
    result
  end

  # Private implementation

  defp merge_thresholds(overrides) do
    Map.merge(@default_thresholds, overrides)
  end

  # Detect long functions using complexity metrics
  defp detect_long_function(smells, doc, thresholds) do
    {:ok, complexity} = Complexity.analyze(doc)
    statement_count = Map.get(complexity.function_metrics, :statement_count, 0)

    if statement_count > thresholds.max_statements do
      smell = %{
        type: :long_function,
        severity: determine_severity(:long_function, statement_count, thresholds.max_statements),
        description:
          "Function has #{statement_count} statements (threshold: #{thresholds.max_statements})",
        suggestion: "Break this function into smaller, focused functions",
        context: %{statement_count: statement_count, threshold: thresholds.max_statements}
      }

      [smell | smells]
    else
      smells
    end
  end

  # Detect deep nesting using complexity metrics
  defp detect_deep_nesting(smells, doc, thresholds) do
    {:ok, complexity} = Complexity.analyze(doc)

    if complexity.max_nesting > thresholds.max_nesting do
      smell = %{
        type: :deep_nesting,
        severity:
          determine_severity(:deep_nesting, complexity.max_nesting, thresholds.max_nesting),
        description:
          "Nesting depth of #{complexity.max_nesting} exceeds threshold of #{thresholds.max_nesting}",
        suggestion: "Reduce nesting by extracting functions or using early returns",
        context: %{max_nesting: complexity.max_nesting, threshold: thresholds.max_nesting}
      }

      [smell | smells]
    else
      smells
    end
  end

  # Detect magic numbers (numeric literals in complex expressions)
  defp detect_magic_numbers(ast, _thresholds) do
    magic_numbers = find_magic_numbers(ast, [])

    Enum.map(magic_numbers, fn {value, context} ->
      %{
        type: :magic_number,
        severity: :low,
        description: "Magic number #{value} should be a named constant",
        suggestion: "Extract #{value} to a named constant",
        context: context
      }
    end)
  end

  defp find_magic_numbers(ast, context) do
    case ast do
      {:binary_op, _, _, left, right} ->
        # Check for numeric literals in binary operations
        find_magic_numbers(left, [:binary_op | context]) ++
          find_magic_numbers(right, [:binary_op | context])

      {:literal, :integer, value} when is_integer(value) and value not in [0, 1, -1] ->
        # Report integers other than 0, 1, -1 in operation context
        if :binary_op in context or :unary_op in context do
          [{value, %{value: value, in_expression: true}}]
        else
          []
        end

      {:literal, :float, value} when is_float(value) ->
        # Report all float literals in operation context
        if :binary_op in context or :unary_op in context do
          [{value, %{value: value, in_expression: true}}]
        else
          []
        end

      {:unary_op, _, _, operand} ->
        find_magic_numbers(operand, [:unary_op | context])

      {:conditional, cond, then_br, else_br} ->
        find_magic_numbers(cond, context) ++
          find_magic_numbers(then_br, context) ++
          find_magic_numbers(else_br, context)

      {:block, statements} when is_list(statements) ->
        Enum.flat_map(statements, &find_magic_numbers(&1, context))

      {:function_call, _name, args} when is_list(args) ->
        Enum.flat_map(args, &find_magic_numbers(&1, context))

      _ ->
        []
    end
  end

  # Detect complex conditionals (nested boolean operations)
  defp detect_complex_conditionals(ast, _thresholds) do
    complex_conditions = find_complex_conditionals(ast, 0)

    Enum.map(complex_conditions, fn depth ->
      %{
        type: :complex_conditional,
        severity: if(depth > 3, do: :high, else: :medium),
        description: "Complex conditional with #{depth} nested boolean operations",
        suggestion: "Extract condition logic into well-named boolean variables",
        context: %{complexity_depth: depth}
      }
    end)
  end

  defp find_complex_conditionals(ast, depth) do
    case ast do
      {:conditional, cond, then_br, else_br} ->
        cond_depth = count_boolean_depth(cond, 0)

        results =
          if cond_depth > 2 do
            [cond_depth]
          else
            []
          end

        results ++
          find_complex_conditionals(then_br, depth) ++
          find_complex_conditionals(else_br, depth)

      {:block, statements} when is_list(statements) ->
        Enum.flat_map(statements, &find_complex_conditionals(&1, depth))

      {:loop, :while, cond, body} ->
        cond_depth = count_boolean_depth(cond, 0)

        results =
          if cond_depth > 2 do
            [cond_depth]
          else
            []
          end

        results ++ find_complex_conditionals(body, depth)

      {:loop, _, _iter, _coll, body} ->
        find_complex_conditionals(body, depth)

      _ ->
        []
    end
  end

  defp count_boolean_depth({:binary_op, :boolean, _op, left, right}, depth) do
    max(
      count_boolean_depth(left, depth + 1),
      count_boolean_depth(right, depth + 1)
    )
  end

  defp count_boolean_depth({:unary_op, :boolean, _op, operand}, depth) do
    count_boolean_depth(operand, depth + 1)
  end

  defp count_boolean_depth(_, depth), do: depth

  # Determine severity based on how much threshold is exceeded
  defp determine_severity(_type, value, threshold) do
    ratio = value / threshold

    cond do
      ratio >= 3.0 -> :critical
      ratio >= 2.0 -> :high
      ratio >= 1.5 -> :medium
      true -> :low
    end
  end
end
