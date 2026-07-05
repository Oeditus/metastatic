defmodule Mix.Tasks.Metastatic.InspectTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.Metastatic.Inspect

  @tmp_dir System.tmp_dir!()

  setup do
    python_file = Path.join(@tmp_dir, "test_inspect_#{:rand.uniform(10000)}.py")
    elixir_file = Path.join(@tmp_dir, "test_inspect_#{:rand.uniform(10000)}.ex")

    File.write!(python_file, "x + 5")
    File.write!(elixir_file, "a * b + c")

    on_exit(fn ->
      File.rm(python_file)
      File.rm(elixir_file)
    end)

    %{python_file: python_file, elixir_file: elixir_file}
  end

  describe "run/1 - basic inspection" do
    test "inspects Python file with default tree format", %{python_file: python_file} do
      args = [python_file]

      output =
        capture_io(fn ->
          catch_exit(Inspect.run(args))
        end)

      assert output =~ "Language: python"
      assert output =~ "Layer: core"
      assert output =~ "Depth: 2"
      assert output =~ "Nodes: 3"
      assert output =~ "Variables: 1"
      assert output =~ "binary_op (arithmetic: +)"
      assert output =~ "variable: x"
      assert output =~ "literal (integer): 5"
    end

    test "inspects Elixir file", %{elixir_file: elixir_file} do
      args = [elixir_file]

      output =
        capture_io(fn ->
          catch_exit(Inspect.run(args))
        end)

      assert output =~ "Language: elixir"
      assert output =~ "Layer: core"
      assert output =~ "Depth: 3"
      assert output =~ "Nodes: 5"
      assert output =~ "Variables: 3"
    end

    test "errors when file doesn't exist" do
      args = ["/nonexistent.py"]

      output =
        capture_io(:stderr, fn ->
          catch_exit(Inspect.run(args))
        end)

      assert output =~ "File does not exist"
    end

    test "errors when no file provided" do
      args = []

      output =
        capture_io(:stderr, fn ->
          catch_exit(Inspect.run(args))
        end)

      assert output =~ "No source file provided"
    end

    test "errors when path is a directory" do
      args = [@tmp_dir]

      output =
        capture_io(:stderr, fn ->
          catch_exit(Inspect.run(args))
        end)

      assert output =~ "is a directory"
    end
  end

  describe "output formats" do
    test "tree format (default)", %{python_file: python_file} do
      args = [python_file, "--format", "tree"]

      output =
        capture_io(fn ->
          catch_exit(Inspect.run(args))
        end)

      assert output =~ "binary_op (arithmetic: +)"
      assert output =~ "  variable: x"
      assert output =~ "  literal (integer): 5"
    end

    test "json format", %{python_file: python_file} do
      args = [python_file, "--format", "json"]

      output =
        capture_io(fn ->
          catch_exit(Inspect.run(args))
        end)

      assert output =~ ~s("type": "binary_op")
      assert output =~ ~s("category": "arithmetic")
      assert output =~ ~s("operator": "+")
      assert output =~ ~s("type": "variable")
      assert output =~ ~s("name": "x")
    end

    test "plain format", %{python_file: python_file} do
      args = [python_file, "--format", "plain"]

      output =
        capture_io(fn ->
          catch_exit(Inspect.run(args))
        end)

      assert output =~ "binary_op(arithmetic, +,"
      assert output =~ "variable(x)"
      assert output =~ "literal(integer, 5)"
    end

    test "errors with invalid format", %{python_file: python_file} do
      args = [python_file, "--format", "invalid"]

      output =
        capture_io(:stderr, fn ->
          catch_exit(Inspect.run(args))
        end)

      assert output =~ "Invalid format: invalid"
    end
  end

  describe "layer filtering" do
    test "shows all layers by default", %{elixir_file: elixir_file} do
      args = [elixir_file]

      output =
        capture_io(fn ->
          catch_exit(Inspect.run(args))
        end)

      assert output =~ "MetaAST:"
      refute output =~ "Filtered AST"
    end

    test "filters to core layer", %{elixir_file: elixir_file} do
      args = [elixir_file, "--layer", "core"]

      output =
        capture_io(fn ->
          catch_exit(Inspect.run(args))
        end)

      assert output =~ "Filtered AST (core layer):"
      assert output =~ "binary_op"
    end

    test "filters to extended layer" do
      # Create a file with extended constructs (lambda)
      lambda_file = Path.join(@tmp_dir, "lambda_#{:rand.uniform(10000)}.py")
      File.write!(lambda_file, "lambda x: x + 1")

      args = [lambda_file, "--layer", "extended"]

      output =
        capture_io(fn ->
          catch_exit(Inspect.run(args))
        end)

      assert output =~ "Filtered AST (extended layer):"

      File.rm(lambda_file)
    end

    test "errors with invalid layer", %{python_file: python_file} do
      args = [python_file, "--layer", "invalid"]

      output =
        capture_io(:stderr, fn ->
          catch_exit(Inspect.run(args))
        end)

      assert output =~ "Invalid layer: invalid"
    end
  end

  describe "variable extraction" do
    test "shows only variables with --variables flag", %{elixir_file: elixir_file} do
      args = [elixir_file, "--variables"]

      output =
        capture_io(fn ->
          catch_exit(Inspect.run(args))
        end)

      assert output =~ "Variables:"
      assert output =~ "a"
      assert output =~ "b"
      assert output =~ "c"
      refute output =~ "MetaAST:"
      refute output =~ "binary_op"
    end

    test "shows 'No variables found' when there are none" do
      literal_file = Path.join(@tmp_dir, "literal_#{:rand.uniform(10000)}.py")
      File.write!(literal_file, "42")

      args = [literal_file, "--variables"]

      output =
        capture_io(fn ->
          catch_exit(Inspect.run(args))
        end)

      assert output =~ "No variables found"

      File.rm(literal_file)
    end
  end

  describe "language detection and specification" do
    test "auto-detects language from .py extension", %{python_file: python_file} do
      args = [python_file]

      output =
        capture_io(fn ->
          catch_exit(Inspect.run(args))
        end)

      assert output =~ "Language: python"
    end

    test "auto-detects language from .ex extension", %{elixir_file: elixir_file} do
      args = [elixir_file]

      output =
        capture_io(fn ->
          catch_exit(Inspect.run(args))
        end)

      assert output =~ "Language: elixir"
    end

    test "allows explicit language specification" do
      txt_file = Path.join(@tmp_dir, "test_#{:rand.uniform(10000)}.txt")
      File.write!(txt_file, "x + 5")

      args = [txt_file, "--language", "python"]

      output =
        capture_io(fn ->
          catch_exit(Inspect.run(args))
        end)

      assert output =~ "Language: python"

      File.rm(txt_file)
    end

    test "errors with invalid language", %{python_file: python_file} do
      args = [python_file, "--language", "invalid"]

      output =
        capture_io(:stderr, fn ->
          catch_exit(Inspect.run(args))
        end)

      assert output =~ "Invalid language: invalid"
    end

    test "errors when cannot detect language" do
      txt_file = Path.join(@tmp_dir, "test_#{:rand.uniform(10000)}.txt")
      File.write!(txt_file, "x + 5")

      args = [txt_file]

      output =
        capture_io(:stderr, fn ->
          catch_exit(Inspect.run(args))
        end)

      assert output =~ "Cannot detect language"

      File.rm(txt_file)
    end
  end

  describe "complex expressions" do
    test "inspects nested binary operations" do
      nested_file = Path.join(@tmp_dir, "nested_#{:rand.uniform(10000)}.py")
      File.write!(nested_file, "(a + b) * (c - d)")

      args = [nested_file]

      output =
        capture_io(fn ->
          catch_exit(Inspect.run(args))
        end)

      assert output =~ "Depth: 3"
      assert output =~ "Nodes: 7"
      assert output =~ "Variables: 4"

      File.rm(nested_file)
    end

    test "inspects function calls with arguments" do
      func_file = Path.join(@tmp_dir, "func_#{:rand.uniform(10000)}.ex")
      File.write!(func_file, "foo(1, 2, 3)")

      args = [func_file]

      output =
        capture_io(fn ->
          catch_exit(Inspect.run(args))
        end)

      assert output =~ "function_call: foo"
      assert output =~ "literal (integer): 1"
      assert output =~ "literal (integer): 2"
      assert output =~ "literal (integer): 3"

      File.rm(func_file)
    end
  end

  describe "combined options" do
    test "JSON format with layer filter", %{elixir_file: elixir_file} do
      args = [elixir_file, "--format", "json", "--layer", "core"]

      output =
        capture_io(fn ->
          catch_exit(Inspect.run(args))
        end)

      assert output =~ ~s("type": "binary_op")
      assert output =~ "Filtered AST (core layer):"
    end

    test "plain format with explicit language" do
      txt_file = Path.join(@tmp_dir, "test_#{:rand.uniform(10000)}.txt")
      File.write!(txt_file, "x + y")

      args = [txt_file, "--format", "plain", "--language", "python"]

      output =
        capture_io(fn ->
          catch_exit(Inspect.run(args))
        end)

      assert output =~ "binary_op(arithmetic, +,"
      assert output =~ "variable(x)"
      assert output =~ "variable(y)"

      File.rm(txt_file)
    end
  end
end
