defmodule Metastatic.Test.AdapterHelper do
  @moduledoc """
  Testing utilities for language adapters (M1 ↔ M2 transformations).

  Provides macros and helper functions to test adapter round-trip fidelity,
  validate conformance, and measure transformation quality.

  ## M1 ↔ M2 Round-Trip Testing

  A round-trip test validates the following pipeline:

      Source → M1 → M2 → M1 → Source

  Where:
  - Source → M1: `adapter.parse/1`
  - M1 → M2: `adapter.to_meta/1`
  - M2 → M1: `adapter.from_meta/2`
  - M1 → Source: `adapter.unparse/1`

  ## Fidelity Metrics

  - **Exact match**: Source output matches input exactly
  - **Semantic match**: ASTs match even if formatting differs
  - **Partial match**: Core structure preserved but details lost

  ## Usage

      defmodule MyAdapterTest do
        use ExUnit.Case
        import Metastatic.Test.AdapterHelper

        test "round-trip simple arithmetic" do
          source = "x + 5"
          assert_round_trip(MyAdapter, source)
        end

        test "validates M2 conformance" do
          source = "x + 5"
          assert_valid_meta_ast(MyAdapter, source)
        end
      end
  """

  import ExUnit.Assertions

  alias Metastatic.{AST, Adapter, Document, Validator}

  # Public API

  @doc """
  Assert that source code round-trips successfully through the adapter.

  Validates: Source → M1 → M2 → M1 → Source

  ## Options

  - `:exact` - Require exact source match (default: `false`)
  - `:semantic` - Allow formatting differences (default: `true`)

  ## Examples

      assert_round_trip(MyAdapter, "x + 5")
      assert_round_trip(MyAdapter, "x + 5", exact: true)
  """
  @spec assert_round_trip(module(), String.t(), keyword()) :: :ok
  def assert_round_trip(adapter, source, opts \\ []) do
    exact = Keyword.get(opts, :exact, false)

    case Adapter.round_trip(adapter, source) do
      {:ok, result} ->
        if exact do
          assert result == source,
                 "Round-trip failed: expected exact match\n\nOriginal:\n#{source}\n\nResult:\n#{result}"
        else
          # For semantic match, compare normalized versions
          assert normalize_source(result) == normalize_source(source),
                 "Round-trip failed: semantic mismatch\n\nOriginal:\n#{source}\n\nResult:\n#{result}"
        end

        :ok

      {:error, reason} ->
        flunk("Round-trip failed: #{inspect(reason)}")
    end
  end

  @doc """
  Assert that source code produces a valid MetaAST.

  Validates: Source → M1 → M2 and checks M2 conformance.

  ## Options

  - `:mode` - Validation mode (`:strict`, `:standard`, `:permissive`)
  - `:max_depth` - Maximum allowed AST depth
  - `:max_nodes` - Maximum allowed node count

  ## Examples

      assert_valid_meta_ast(MyAdapter, "x + 5")
      assert_valid_meta_ast(MyAdapter, "x + 5", mode: :strict)
  """
  @spec assert_valid_meta_ast(module(), String.t(), keyword()) :: Document.t()
  def assert_valid_meta_ast(adapter, source, opts \\ []) do
    language = opts[:language] || :unknown
    mode = Keyword.get(opts, :mode, :standard)

    with {:ok, native_ast} <- adapter.parse(source),
         {:ok, meta_ast, metadata} <- adapter.to_meta(native_ast) do
      # Check structural conformance
      assert AST.conforms?(meta_ast),
             "MetaAST does not conform to M2 meta-model: #{inspect(meta_ast)}"

      # Create document and validate
      doc = Document.new(meta_ast, language, metadata, source)

      validation_opts = Keyword.put(opts, :mode, mode)

      case Validator.validate(doc, validation_opts) do
        {:ok, _validation_meta} ->
          doc

        {:error, {:max_depth_exceeded, depth, max}} ->
          flunk("AST depth #{depth} exceeds maximum #{max}")

        {:error, {:max_variables_exceeded, count, max}} ->
          flunk("Variable count #{count} exceeds maximum #{max}")

        {:error, errors} ->
          flunk("Validation failed: #{inspect(errors)}")
      end
    else
      {:error, reason} ->
        flunk("Failed to produce MetaAST: #{inspect(reason)}")
    end
  end

  @doc """
  Assert that MetaAST can be reified back to source.

  Validates: M2 → M1 → Source

  ## Examples

      ast = {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}}
      assert_valid_reification(MyAdapter, ast, %{})
  """
  @spec assert_valid_reification(module(), AST.meta_ast(), map()) :: String.t()
  def assert_valid_reification(adapter, meta_ast, metadata) do
    with {:ok, native_ast} <- adapter.from_meta(meta_ast, metadata),
         {:ok, source} <- adapter.unparse(native_ast) do
      assert is_binary(source) and byte_size(source) > 0,
             "Reification produced empty or invalid source"

      source
    else
      {:error, reason} ->
        flunk("Reification failed: #{inspect(reason)}")
    end
  end

  @doc """
  Calculate round-trip fidelity score.

  Returns a percentage (0.0 to 100.0) representing how closely the
  round-trip output matches the input.

  ## Examples

      fidelity = calculate_fidelity(original, round_trip_result)
      # => 95.5
  """
  @spec calculate_fidelity(String.t(), String.t()) :: float()
  def calculate_fidelity(original, result) do
    if original == result do
      100.0
    else
      # Use Levenshtein distance for similarity
      distance = levenshtein_distance(original, result)
      max_length = max(String.length(original), String.length(result))

      if max_length == 0 do
        100.0
      else
        (1.0 - distance / max_length) * 100.0
      end
    end
  end

  @doc """
  Measure adapter performance.

  Returns timing information for each stage of the transformation pipeline.

  ## Examples

      metrics = measure_performance(MyAdapter, source)
      # => %{
      #   parse_time_us: 150,
      #   to_meta_time_us: 200,
      #   from_meta_time_us: 180,
      #   unparse_time_us: 120,
      #   total_time_us: 650
      # }
  """
  @spec measure_performance(module(), String.t()) :: map()
  def measure_performance(adapter, source) do
    {parse_time, {:ok, native_ast}} = :timer.tc(fn -> adapter.parse(source) end)
    {to_meta_time, {:ok, meta_ast, metadata}} = :timer.tc(fn -> adapter.to_meta(native_ast) end)

    {from_meta_time, {:ok, native_ast2}} =
      :timer.tc(fn -> adapter.from_meta(meta_ast, metadata) end)

    {unparse_time, {:ok, _result}} = :timer.tc(fn -> adapter.unparse(native_ast2) end)

    %{
      parse_time_us: parse_time,
      to_meta_time_us: to_meta_time,
      from_meta_time_us: from_meta_time,
      unparse_time_us: unparse_time,
      total_time_us: parse_time + to_meta_time + from_meta_time + unparse_time
    }
  end

  @doc """
  Load test fixtures from a directory.

  Expects a directory structure like:

      fixtures/
      ├── python/
      │   ├── simple_arithmetic.py
      │   ├── list_comprehension.py
      │   └── expected/
      │       ├── simple_arithmetic.exs
      │       └── list_comprehension.exs

  Returns a list of `{source_file, source_code, expected_meta_ast}` tuples.

  ## Examples

      fixtures = load_fixtures("test/fixtures/python")
  """
  @spec load_fixtures(String.t()) :: [{String.t(), String.t(), term() | nil}]
  def load_fixtures(dir) do
    if File.dir?(dir) do
      dir
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, [".py", ".js", ".ex"]))
      |> Enum.map(fn file ->
        source_path = Path.join(dir, file)
        source_code = File.read!(source_path)

        # Try to load expected MetaAST
        expected_path = Path.join([dir, "expected", Path.rootname(file) <> ".exs"])

        expected_ast =
          if File.exists?(expected_path) do
            {ast, _} = Code.eval_file(expected_path)
            ast
          else
            nil
          end

        {file, source_code, expected_ast}
      end)
    else
      []
    end
  end

  # Private Helpers

  defp normalize_source(source) do
    source
    |> String.trim()
    |> String.replace(~r/\s+/, " ")
    |> String.downcase()
  end

  defp levenshtein_distance(s1, s2) do
    s1_len = String.length(s1)
    s2_len = String.length(s2)

    # Initialize distance matrix
    matrix = init_matrix(s1_len + 1, s2_len + 1)

    # Calculate distances
    Enum.reduce(0..s1_len, matrix, fn i, acc ->
      Enum.reduce(0..s2_len, acc, fn j, inner_acc ->
        cond do
          i == 0 ->
            put_distance(inner_acc, i, j, j)

          j == 0 ->
            put_distance(inner_acc, i, j, i)

          String.at(s1, i - 1) == String.at(s2, j - 1) ->
            put_distance(inner_acc, i, j, get_distance(inner_acc, i - 1, j - 1))

          true ->
            min_dist =
              min(
                get_distance(inner_acc, i - 1, j),
                min(
                  get_distance(inner_acc, i, j - 1),
                  get_distance(inner_acc, i - 1, j - 1)
                )
              ) + 1

            put_distance(inner_acc, i, j, min_dist)
        end
      end)
    end)
    |> get_distance(s1_len, s2_len)
  end

  defp init_matrix(rows, cols) do
    for i <- 0..(rows - 1), j <- 0..(cols - 1), into: %{} do
      {{i, j}, 0}
    end
  end

  defp get_distance(matrix, i, j), do: Map.get(matrix, {i, j}, 0)
  defp put_distance(matrix, i, j, value), do: Map.put(matrix, {i, j}, value)
end
