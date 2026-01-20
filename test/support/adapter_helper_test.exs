defmodule Metastatic.Test.AdapterHelperTest do
  use ExUnit.Case

  import Metastatic.Test.AdapterHelper

  # Mock adapter for testing
  defmodule TestAdapter do
    @behaviour Metastatic.Adapter

    @impl true
    def parse(source) do
      # Simple parser: just wrap in a map
      {:ok, %{source: source}}
    end

    @impl true
    def to_meta(%{source: source}) do
      # Convert to a simple literal MetaAST
      value = String.to_integer(String.trim(source))
      {:ok, {:literal, :integer, value}, %{original: source}}
    end

    @impl true
    def from_meta({:literal, :integer, value}, metadata) do
      # Convert back to native AST
      {:ok, %{source: metadata[:original] || to_string(value)}}
    end

    @impl true
    def unparse(%{source: source}) do
      {:ok, source}
    end

    @impl true
    def file_extensions, do: [".test"]
  end

  # Failing adapter for error cases
  defmodule FailingAdapter do
    @behaviour Metastatic.Adapter

    @impl true
    def parse(_), do: {:error, :parse_failed}

    @impl true
    def to_meta(_), do: {:error, :to_meta_failed}

    @impl true
    def from_meta(_, _), do: {:error, :from_meta_failed}

    @impl true
    def unparse(_), do: {:error, :unparse_failed}

    @impl true
    def file_extensions, do: [".fail"]
  end

  describe "assert_round_trip/3" do
    test "succeeds for exact match" do
      source = "42"
      assert :ok = assert_round_trip(TestAdapter, source, exact: true)
    end

    test "succeeds for semantic match" do
      source = "  42  "
      # Even with whitespace differences, semantic match works
      assert :ok = assert_round_trip(TestAdapter, source)
    end

    test "fails on adapter error" do
      assert_raise ExUnit.AssertionError, ~r/Round-trip failed/, fn ->
        assert_round_trip(FailingAdapter, "test")
      end
    end
  end

  describe "assert_valid_meta_ast/3" do
    test "validates correct MetaAST" do
      source = "42"
      doc = assert_valid_meta_ast(TestAdapter, source, language: :test)

      assert doc.ast == {:literal, :integer, 42}
      assert doc.language == :test
    end

    test "checks max_depth constraint" do
      source = "42"

      assert_raise ExUnit.AssertionError, ~r/AST depth .* exceeds maximum/, fn ->
        assert_valid_meta_ast(TestAdapter, source, max_depth: 0)
      end
    end

    test "fails on parse error" do
      assert_raise ExUnit.AssertionError, ~r/Failed to produce MetaAST/, fn ->
        assert_valid_meta_ast(FailingAdapter, "test")
      end
    end
  end

  describe "assert_valid_reification/3" do
    test "reifies MetaAST to source" do
      ast = {:literal, :integer, 42}
      metadata = %{original: "42"}

      source = assert_valid_reification(TestAdapter, ast, metadata)
      assert source == "42"
    end

    test "fails on empty source" do
      defmodule EmptyAdapter do
        @behaviour Metastatic.Adapter

        @impl true
        def parse(_), do: {:ok, %{}}
        @impl true
        def to_meta(_), do: {:ok, {:literal, :integer, 1}, %{}}
        @impl true
        def from_meta(_, _), do: {:ok, %{}}
        @impl true
        def unparse(_), do: {:ok, ""}
        @impl true
        def file_extensions, do: [".empty"]
      end

      ast = {:literal, :integer, 42}

      assert_raise ExUnit.AssertionError, ~r/produced empty or invalid source/, fn ->
        assert_valid_reification(EmptyAdapter, ast, %{})
      end
    end

    test "fails on reification error" do
      ast = {:literal, :integer, 42}

      assert_raise ExUnit.AssertionError, ~r/Reification failed/, fn ->
        assert_valid_reification(FailingAdapter, ast, %{})
      end
    end
  end

  describe "calculate_fidelity/2" do
    test "returns 100.0 for exact match" do
      assert 100.0 = calculate_fidelity("hello", "hello")
    end

    test "returns lower score for different strings" do
      fidelity = calculate_fidelity("hello", "hallo")
      assert fidelity > 0.0
      assert fidelity < 100.0
    end

    test "returns 0.0 for completely different strings" do
      fidelity = calculate_fidelity("abc", "xyz")
      assert fidelity < 50.0
    end

    test "handles empty strings" do
      assert 100.0 = calculate_fidelity("", "")
    end

    test "calculates reasonable similarity" do
      # "test" vs "text" - one character difference
      fidelity = calculate_fidelity("test", "text")
      assert fidelity > 70.0
    end
  end

  describe "measure_performance/2" do
    test "measures all pipeline stages" do
      source = "42"
      metrics = measure_performance(TestAdapter, source)

      assert is_integer(metrics.parse_time_us)
      assert is_integer(metrics.to_meta_time_us)
      assert is_integer(metrics.from_meta_time_us)
      assert is_integer(metrics.unparse_time_us)
      assert is_integer(metrics.total_time_us)

      # Total should be sum of all stages
      expected_total =
        metrics.parse_time_us +
          metrics.to_meta_time_us +
          metrics.from_meta_time_us +
          metrics.unparse_time_us

      assert metrics.total_time_us == expected_total
    end

    test "all times are non-negative" do
      source = "42"
      metrics = measure_performance(TestAdapter, source)

      assert metrics.parse_time_us >= 0
      assert metrics.to_meta_time_us >= 0
      assert metrics.from_meta_time_us >= 0
      assert metrics.unparse_time_us >= 0
      assert metrics.total_time_us >= 0
    end
  end

  describe "load_fixtures/1" do
    test "returns empty list for non-existent directory" do
      assert [] = load_fixtures("/nonexistent/path")
    end

    test "loads fixtures from directory" do
      # Create temporary fixture directory
      dir = System.tmp_dir!() |> Path.join("metastatic_test_fixtures")
      File.mkdir_p!(dir)

      # Create a test file
      File.write!(Path.join(dir, "test.py"), "x = 1")

      fixtures = load_fixtures(dir)
      assert [{"test.py", "x = 1", nil}] = fixtures

      # Cleanup
      File.rm_rf!(dir)
    end

    test "loads expected MetaAST when available" do
      # Create temporary fixture directory
      dir = System.tmp_dir!() |> Path.join("metastatic_test_fixtures2")
      expected_dir = Path.join(dir, "expected")
      File.mkdir_p!(expected_dir)

      # Create test file and expected AST
      File.write!(Path.join(dir, "test.py"), "x = 1")
      File.write!(Path.join(expected_dir, "test.exs"), "{:literal, :integer, 1}")

      fixtures = load_fixtures(dir)
      assert [{"test.py", "x = 1", {:literal, :integer, 1}}] = fixtures

      # Cleanup
      File.rm_rf!(dir)
    end

    test "filters files by extension" do
      # Create temporary fixture directory
      dir = System.tmp_dir!() |> Path.join("metastatic_test_fixtures3")
      File.mkdir_p!(dir)

      # Create various files
      File.write!(Path.join(dir, "test.py"), "python")
      File.write!(Path.join(dir, "test.js"), "javascript")
      File.write!(Path.join(dir, "test.txt"), "text")
      File.write!(Path.join(dir, "README.md"), "markdown")

      fixtures = load_fixtures(dir)

      # Should only load .py, .js, .ex files
      assert length(fixtures) == 2
      assert Enum.any?(fixtures, fn {name, _, _} -> name == "test.py" end)
      assert Enum.any?(fixtures, fn {name, _, _} -> name == "test.js" end)

      # Cleanup
      File.rm_rf!(dir)
    end
  end

  describe "integration tests" do
    test "full workflow with TestAdapter" do
      source = "42"

      # Validate MetaAST production
      doc = assert_valid_meta_ast(TestAdapter, source, language: :test)
      assert doc.ast == {:literal, :integer, 42}

      # Validate reification
      result_source = assert_valid_reification(TestAdapter, doc.ast, doc.metadata)
      assert result_source == source

      # Validate round-trip
      assert :ok = assert_round_trip(TestAdapter, source, exact: true)

      # Measure performance
      metrics = measure_performance(TestAdapter, source)
      assert metrics.total_time_us >= 0

      # Calculate fidelity
      fidelity = calculate_fidelity(source, source)
      assert fidelity == 100.0
    end
  end
end
