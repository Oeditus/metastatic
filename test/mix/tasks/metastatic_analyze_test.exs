defmodule Mix.Tasks.Metastatic.AnalyzeTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.Metastatic.Analyze

  @tmp_dir System.tmp_dir!()

  setup do
    python_file = Path.join(@tmp_dir, "test_analyze_#{:rand.uniform(10000)}.py")
    elixir_file = Path.join(@tmp_dir, "test_analyze_#{:rand.uniform(10000)}.ex")

    File.write!(python_file, "x + 5")
    File.write!(elixir_file, "a * b + c")

    on_exit(fn ->
      File.rm(python_file)
      File.rm(elixir_file)
    end)

    %{python_file: python_file, elixir_file: elixir_file}
  end

  describe "run/1 - basic analysis" do
    test "analyzes Python file with standard validation", %{python_file: python_file} do
      args = [python_file]

      output =
        capture_io(fn ->
          catch_exit(Analyze.run(args))
        end)

      assert output =~ "File: #{python_file}"
      assert output =~ "Metrics:"
      assert output =~ "Layer: core"
      assert output =~ "Depth: 2"
      assert output =~ "Nodes: 3"
      assert output =~ "Variables: 1"
      assert output =~ "Validation:"
      assert output =~ "Level: core"
      assert output =~ "Native Constructs: 0"
      assert output =~ "No warnings"
      assert output =~ "Pure M2.1 (Core) - fully portable"
    end

    test "analyzes Elixir file", %{elixir_file: elixir_file} do
      args = [elixir_file]

      output =
        capture_io(fn ->
          catch_exit(Analyze.run(args))
        end)

      assert output =~ "Layer: core"
      assert output =~ "Depth: 3"
      assert output =~ "Nodes: 5"
      assert output =~ "Variables: 3"
      assert output =~ "Variables:"
      assert output =~ "a"
      assert output =~ "b"
      assert output =~ "c"
    end

    test "errors when file doesn't exist" do
      args = ["/nonexistent.py"]

      output =
        capture_io(:stderr, fn ->
          catch_exit(Analyze.run(args))
        end)

      assert output =~ "File does not exist"
    end

    test "errors when no file provided" do
      args = []

      output =
        capture_io(:stderr, fn ->
          catch_exit(Analyze.run(args))
        end)

      assert output =~ "No source file provided"
    end
  end

  describe "validation modes" do
    test "strict validation mode", %{python_file: python_file} do
      args = [python_file, "--validate", "strict"]

      output =
        capture_io(fn ->
          catch_exit(Analyze.run(args))
        end)

      assert output =~ "Validation:"
      assert output =~ "No warnings"
    end

    test "standard validation mode (default)", %{python_file: python_file} do
      args = [python_file, "--validate", "standard"]

      output =
        capture_io(fn ->
          catch_exit(Analyze.run(args))
        end)

      assert output =~ "Validation:"
      assert output =~ "Level: core"
    end

    test "permissive validation mode", %{python_file: python_file} do
      args = [python_file, "--validate", "permissive"]

      output =
        capture_io(fn ->
          catch_exit(Analyze.run(args))
        end)

      assert output =~ "Validation:"
      assert output =~ "No warnings"
    end

    test "errors with invalid validation mode", %{python_file: python_file} do
      args = [python_file, "--validate", "invalid"]

      output =
        capture_io(:stderr, fn ->
          catch_exit(Analyze.run(args))
        end)

      assert output =~ "Invalid validation mode: invalid"
    end
  end

  describe "language detection and specification" do
    test "auto-detects language from .py extension", %{python_file: python_file} do
      args = [python_file]

      output =
        capture_io(fn ->
          catch_exit(Analyze.run(args))
        end)

      assert output =~ "Metrics:"
      refute output =~ "Error"
    end

    test "auto-detects language from .ex extension", %{elixir_file: elixir_file} do
      args = [elixir_file]

      output =
        capture_io(fn ->
          catch_exit(Analyze.run(args))
        end)

      assert output =~ "Metrics:"
      refute output =~ "Error"
    end

    test "allows explicit language specification" do
      txt_file = Path.join(@tmp_dir, "test_#{:rand.uniform(10000)}.txt")
      File.write!(txt_file, "x + 5")

      args = [txt_file, "--language", "python"]

      output =
        capture_io(fn ->
          catch_exit(Analyze.run(args))
        end)

      assert output =~ "Metrics:"
      assert output =~ "Layer: core"

      File.rm(txt_file)
    end

    test "errors with invalid language", %{python_file: python_file} do
      args = [python_file, "--language", "invalid"]

      output =
        capture_io(:stderr, fn ->
          catch_exit(Analyze.run(args))
        end)

      assert output =~ "Invalid language: invalid"
    end

    test "errors when cannot detect language" do
      txt_file = Path.join(@tmp_dir, "test_#{:rand.uniform(10000)}.txt")
      File.write!(txt_file, "x + 5")

      args = [txt_file]

      output =
        capture_io(:stderr, fn ->
          catch_exit(Analyze.run(args))
        end)

      assert output =~ "Cannot detect language"

      File.rm(txt_file)
    end
  end

  describe "layer detection" do
    test "detects core layer for simple expressions", %{python_file: python_file} do
      args = [python_file]

      output =
        capture_io(fn ->
          catch_exit(Analyze.run(args))
        end)

      assert output =~ "Layer: core"
      assert output =~ "Pure M2.1 (Core) - fully portable"
    end

    test "detects extended layer for lambdas" do
      lambda_file = Path.join(@tmp_dir, "lambda_#{:rand.uniform(10000)}.py")
      File.write!(lambda_file, "lambda x: x + 1")

      args = [lambda_file]

      output =
        capture_io(fn ->
          catch_exit(Analyze.run(args))
        end)

      assert output =~ "Layer: extended"
      assert output =~ "M2.2 (Extended) - widely portable"

      File.rm(lambda_file)
    end
  end

  describe "variable reporting" do
    test "shows variables when count is 20 or less", %{elixir_file: elixir_file} do
      args = [elixir_file]

      output =
        capture_io(fn ->
          catch_exit(Analyze.run(args))
        end)

      assert output =~ "Variables:"
      assert output =~ "a"
      assert output =~ "b"
      assert output =~ "c"
    end

    test "omits variable list when file has no variables" do
      literal_file = Path.join(@tmp_dir, "literal_#{:rand.uniform(10000)}.py")
      File.write!(literal_file, "42")

      args = [literal_file]

      output =
        capture_io(fn ->
          catch_exit(Analyze.run(args))
        end)

      assert output =~ "Variables: 0"
      refute output =~ "Variables:\n"

      File.rm(literal_file)
    end
  end

  describe "complex expressions" do
    test "analyzes nested binary operations" do
      nested_file = Path.join(@tmp_dir, "nested_#{:rand.uniform(10000)}.py")
      File.write!(nested_file, "(a + b) * (c - d)")

      args = [nested_file]

      output =
        capture_io(fn ->
          catch_exit(Analyze.run(args))
        end)

      assert output =~ "Depth: 3"
      assert output =~ "Nodes: 7"
      assert output =~ "Variables: 4"

      File.rm(nested_file)
    end

    test "analyzes function calls" do
      func_file = Path.join(@tmp_dir, "func_#{:rand.uniform(10000)}.ex")
      File.write!(func_file, "foo(bar(1), baz(2))")

      args = [func_file]

      output =
        capture_io(fn ->
          catch_exit(Analyze.run(args))
        end)

      assert output =~ "Depth: 3"
      assert output =~ "Layer: core"

      File.rm(func_file)
    end
  end

  describe "combined options" do
    test "strict validation with explicit language" do
      txt_file = Path.join(@tmp_dir, "test_#{:rand.uniform(10000)}.txt")
      File.write!(txt_file, "x + y")

      args = [txt_file, "--validate", "strict", "--language", "python"]

      output =
        capture_io(fn ->
          catch_exit(Analyze.run(args))
        end)

      assert output =~ "Validation:"
      assert output =~ "No warnings"

      File.rm(txt_file)
    end

    test "permissive validation with complex expression" do
      complex_file = Path.join(@tmp_dir, "complex_#{:rand.uniform(10000)}.py")
      File.write!(complex_file, "lambda x: x * 2")

      args = [complex_file, "--validate", "permissive"]

      output =
        capture_io(fn ->
          catch_exit(Analyze.run(args))
        end)

      assert output =~ "Layer: extended"
      assert output =~ "M2.2 (Extended)"

      File.rm(complex_file)
    end
  end
end
