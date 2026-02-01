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

      # No code smells - using common constants 0, 1, -1
      iex> ast = {:binary_op, :arithmetic, :+, {:literal, :integer, 1}, {:literal, :integer, 0}}
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

  use Metastatic.Document.Analyzer,
    doc: """
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

  @impl Metastatic.Document.Analyzer
  def handle_analyze(%Document{ast: ast} = doc, opts \\ []) do
    thresholds = Keyword.get(opts, :thresholds, %{}) |> merge_thresholds()

    smells =
      []
      |> detect_long_function(doc, thresholds)
      |> detect_deep_nesting(doc, thresholds)
      |> detect_magic_numbers(ast, thresholds)
      |> detect_complex_conditionals(ast, thresholds)

    {:ok, Result.new(smells)}
  end

  # Private implementation

  defp merge_thresholds(overrides) do
    Map.merge(@default_thresholds, overrides)
  end

  # Detect long functions using per-function complexity metrics
  defp detect_long_function(smells, doc, thresholds) do
    {:ok, complexity} = Complexity.analyze(doc)

    # Check per-function metrics for long functions
    per_function_smells =
      complexity.per_function
      |> Enum.filter(fn func ->
        func.statements > thresholds.max_statements
      end)
      |> Enum.map(fn func ->
        %{
          type: :long_function,
          severity:
            determine_severity(:long_function, func.statements, thresholds.max_statements),
          description:
            "Function '#{func.name}' has #{func.statements} statements (threshold: #{thresholds.max_statements})",
          suggestion: "Break this function into smaller, focused functions",
          context: %{
            function_name: func.name,
            statement_count: func.statements,
            threshold: thresholds.max_statements
          },
          location: %{function: func.name}
        }
      end)

    per_function_smells ++ smells
  end

  # Detect deep nesting using per-function complexity metrics
  defp detect_deep_nesting(smells, doc, thresholds) do
    {:ok, complexity} = Complexity.analyze(doc)

    # Check per-function metrics for deep nesting
    per_function_smells =
      complexity.per_function
      |> Enum.filter(fn func ->
        func.max_nesting > thresholds.max_nesting
      end)
      |> Enum.map(fn func ->
        %{
          type: :deep_nesting,
          severity:
            determine_severity(:deep_nesting, func.max_nesting, thresholds.max_nesting),
          description:
            "Function '#{func.name}' has nesting depth of #{func.max_nesting} (threshold: #{thresholds.max_nesting})",
          suggestion: "Reduce nesting by extracting functions or using early returns",
          context: %{
            function_name: func.name,
            max_nesting: func.max_nesting,
            threshold: thresholds.max_nesting
          },
          location: %{function: func.name}
        }
      end)

    per_function_smells ++ smells
  end

  # Detect magic numbers (numeric literals in complex expressions)
  defp detect_magic_numbers(smells, ast, _thresholds) do
    magic_numbers = find_magic_numbers(ast, [], nil)

    Enum.map(magic_numbers, fn {value, context, line} ->
      %{
        type: :magic_number,
        severity: :low,
        description: "Magic number #{value} should be a named constant",
        suggestion: "Extract #{value} to a named constant",
        context: context,
        location: if(line, do: %{line: line}, else: nil)
      }
    end) ++ smells
  end

  defp find_magic_numbers(ast, context, current_line) do
    case ast do
      {:binary_op, _, _, left, right} ->
        # Check for numeric literals in binary operations
        find_magic_numbers(left, [:binary_op | context], current_line) ++
          find_magic_numbers(right, [:binary_op | context], current_line)

      {:literal, :integer, value} when is_integer(value) and value not in [0, 1, -1] ->
        # Report integers other than 0, 1, -1 in operation context
        if :binary_op in context or :unary_op in context do
          [{value, %{value: value, in_expression: true}, current_line}]
        else
          []
        end

      {:literal, :float, value} when is_float(value) ->
        # Report all float literals in operation context
        if :binary_op in context or :unary_op in context do
          [{value, %{value: value, in_expression: true}, current_line}]
        else
          []
        end

      {:unary_op, _, _, operand} ->
        find_magic_numbers(operand, [:unary_op | context], current_line)

      {:conditional, cond, then_br, else_br} ->
        find_magic_numbers(cond, context, current_line) ++
          find_magic_numbers(then_br, context, current_line) ++
          find_magic_numbers(else_br, context, current_line)

      {:block, statements} when is_list(statements) ->
        Enum.flat_map(statements, &find_magic_numbers(&1, context, current_line))

      {:function_call, _name, args} when is_list(args) ->
        Enum.flat_map(args, &find_magic_numbers(&1, context, current_line))

      {:language_specific, _lang, _native, _type, metadata} ->
        # Extract line information from language-specific wrapper
        line = extract_line_from_metadata(metadata)
        find_magic_numbers_in_metadata(metadata, context, line)

      _ ->
        []
    end
  end

  defp find_magic_numbers_in_metadata(metadata, context, line) when is_map(metadata) do
    # Check if metadata has a body field to recurse into
    case Map.get(metadata, :body) do
      nil -> []
      body -> find_magic_numbers(body, context, line)
    end
  end

  # Detect complex conditionals (nested boolean operations)
  defp detect_complex_conditionals(smells, ast, _thresholds) do
    complex_conditions = find_complex_conditionals(ast, 0, nil)

    Enum.map(complex_conditions, fn {depth, line} ->
      %{
        type: :complex_conditional,
        severity: if(depth > 3, do: :high, else: :medium),
        description: "Complex conditional with #{depth} nested boolean operations",
        suggestion: "Extract condition logic into well-named boolean variables",
        context: %{complexity_depth: depth},
        location: if(line, do: %{line: line}, else: nil)
      }
    end) ++ smells
  end

  defp find_complex_conditionals(ast, depth, current_line) do
    case ast do
      {:conditional, cond, then_br, else_br} ->
        cond_depth = count_boolean_depth(cond, 0)

        results =
          if cond_depth > 2 do
            [{cond_depth, current_line}]
          else
            []
          end

        results ++
          find_complex_conditionals(then_br, depth, current_line) ++
          find_complex_conditionals(else_br, depth, current_line)

      {:block, statements} when is_list(statements) ->
        Enum.flat_map(statements, &find_complex_conditionals(&1, depth, current_line))

      {:loop, :while, cond, body} ->
        cond_depth = count_boolean_depth(cond, 0)

        results =
          if cond_depth > 2 do
            [{cond_depth, current_line}]
          else
            []
          end

        results ++ find_complex_conditionals(body, depth, current_line)

      {:loop, _, _iter, _coll, body} ->
        find_complex_conditionals(body, depth, current_line)

      {:language_specific, _lang, _native, _type, metadata} ->
        # Extract line information from language-specific wrapper
        line = extract_line_from_metadata(metadata)
        find_complex_conditionals_in_metadata(metadata, depth, line)

      _ ->
        []
    end
  end

  defp find_complex_conditionals_in_metadata(metadata, depth, line) when is_map(metadata) do
    case Map.get(metadata, :body) do
      nil -> []
      body -> find_complex_conditionals(body, depth, line)
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

  # Extract location information from document metadata
  defp extract_location(%Document{metadata: metadata, ast: ast}) do
    # Try to extract from metadata first
    location = extract_location_from_metadata(metadata)

    # If not in metadata, try to walk AST for language_specific nodes
    if location do
      location
    else
      extract_location_from_ast(ast)
    end
  end

  defp extract_location_from_metadata(metadata) when is_map(metadata) do
    cond do
      # Function name and line from metadata
      Map.has_key?(metadata, :function_name) and Map.has_key?(metadata, :line) ->
        %{
          function: metadata.function_name,
          line: metadata.line
        }

      # Just line number
      Map.has_key?(metadata, :line) ->
        %{line: metadata.line}

      # Check elixir_meta for line info
      Map.has_key?(metadata, :elixir_meta) ->
        case extract_line_from_elixir_meta(metadata.elixir_meta) do
          nil -> nil
          line -> %{line: line}
        end

      true ->
        nil
    end
  end

  defp extract_location_from_metadata(_), do: nil

  defp extract_line_from_metadata(metadata) when is_map(metadata) do
    cond do
      Map.has_key?(metadata, :line) -> metadata.line
      Map.has_key?(metadata, :elixir_meta) -> extract_line_from_elixir_meta(metadata.elixir_meta)
      true -> nil
    end
  end

  defp extract_line_from_metadata(_), do: nil

  defp extract_line_from_elixir_meta(elixir_meta) when is_list(elixir_meta) do
    Keyword.get(elixir_meta, :line)
  end

  defp extract_line_from_elixir_meta(_), do: nil

  defp extract_location_from_ast(ast) do
    case find_first_language_specific_node(ast) do
      {:ok, metadata} -> extract_location_from_metadata(metadata)
      :not_found -> nil
    end
  end

  defp find_first_language_specific_node(ast) do
    case ast do
      {:language_specific, _lang, _native, _type, metadata} when is_map(metadata) ->
        {:ok, metadata}

      tuple when is_tuple(tuple) ->
        tuple
        |> Tuple.to_list()
        |> Enum.find_value(:not_found, &find_first_language_specific_node/1)

      list when is_list(list) ->
        Enum.find_value(list, :not_found, &find_first_language_specific_node/1)

      %{} = map ->
        map
        |> Map.values()
        |> Enum.find_value(:not_found, &find_first_language_specific_node/1)

      _ ->
        :not_found
    end
  end
end
