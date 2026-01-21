defmodule Mix.Tasks.Metastatic.ValidateEquivalenceTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.Metastatic.ValidateEquivalence

  @tmp_dir System.tmp_dir!()

  setup do
    # Equivalent files
    py_file1 = Path.join(@tmp_dir, "equiv1_#{:rand.uniform(10000)}.py")
    ex_file1 = Path.join(@tmp_dir, "equiv1_#{:rand.uniform(10000)}.ex")
    File.write!(py_file1, "x + 5")
    File.write!(ex_file1, "x + 5")

    # Different files
    py_file2 = Path.join(@tmp_dir, "diff1_#{:rand.uniform(10000)}.py")
    ex_file2 = Path.join(@tmp_dir, "diff2_#{:rand.uniform(10000)}.ex")
    File.write!(py_file2, "x + 5")
    File.write!(ex_file2, "a * b")

    on_exit(fn ->
      File.rm(py_file1)
      File.rm(ex_file1)
      File.rm(py_file2)
      File.rm(ex_file2)
    end)

    %{
      py_equiv: py_file1,
      ex_equiv: ex_file1,
      py_diff: py_file2,
      ex_diff: ex_file2
    }
  end

  describe "run/1 - equivalence checking" do
    test "identifies equivalent files (Python vs Elixir)", %{
      py_equiv: py_file,
      ex_equiv: ex_file
    } do
      args = [py_file, ex_file]

      output =
        capture_io(fn ->
          catch_exit(ValidateEquivalence.run(args))
        end)

      assert output =~ "Comparing:"
      assert output =~ "File 1: #{py_file} (python)"
      assert output =~ "File 2: #{ex_file} (elixir)"
      assert output =~ "Semantically equivalent"
    end

    test "identifies non-equivalent files", %{py_diff: py_file, ex_diff: ex_file} do
      args = [py_file, ex_file]

      output =
        capture_io(:stderr, fn ->
          catch_exit(ValidateEquivalence.run(args))
        end)

      assert output =~ "Not semantically equivalent"
    end

    test "shows detailed comparison with --verbose", %{py_equiv: py_file, ex_equiv: ex_file} do
      args = [py_file, ex_file, "--verbose"]

      output =
        capture_io(fn ->
          catch_exit(ValidateEquivalence.run(args))
        end)

      assert output =~ "Details:"
      assert output =~ "Variables:"
      assert output =~ "x"
      assert output =~ "MetaAST structure: identical"
    end

    test "shows differences with --verbose for non-equivalent files", %{
      py_diff: py_file,
      ex_diff: ex_file
    } do
      args = [py_file, ex_file, "--verbose"]

      # Need to capture both stdout and stderr
      stderr_output =
        capture_io(:stderr, fn ->
          catch_exit(ValidateEquivalence.run(args))
        end)

      # Error message goes to stderr
      assert stderr_output =~ "Not semantically equivalent"
    end
  end

  describe "error handling" do
    test "errors when only one file provided", %{py_equiv: py_file} do
      args = [py_file]

      output =
        capture_io(:stderr, fn ->
          catch_exit(ValidateEquivalence.run(args))
        end)

      assert output =~ "Two files required"
    end

    test "errors when no files provided" do
      args = []

      output =
        capture_io(:stderr, fn ->
          catch_exit(ValidateEquivalence.run(args))
        end)

      assert output =~ "Two files required"
    end

    test "errors when first file doesn't exist", %{ex_equiv: ex_file} do
      args = ["/nonexistent.py", ex_file]

      output =
        capture_io(:stderr, fn ->
          catch_exit(ValidateEquivalence.run(args))
        end)

      assert output =~ "First file does not exist"
    end

    test "errors when second file doesn't exist", %{py_equiv: py_file} do
      args = [py_file, "/nonexistent.ex"]

      output =
        capture_io(:stderr, fn ->
          catch_exit(ValidateEquivalence.run(args))
        end)

      assert output =~ "Second file does not exist"
    end

    test "errors when first path is a directory", %{ex_equiv: ex_file} do
      args = [@tmp_dir, ex_file]

      output =
        capture_io(:stderr, fn ->
          catch_exit(ValidateEquivalence.run(args))
        end)

      assert output =~ "First path is a directory"
    end

    test "errors when second path is a directory", %{py_equiv: py_file} do
      args = [py_file, @tmp_dir]

      output =
        capture_io(:stderr, fn ->
          catch_exit(ValidateEquivalence.run(args))
        end)

      assert output =~ "Second path is a directory"
    end
  end

  describe "language detection and specification" do
    test "auto-detects both languages from extensions", %{py_equiv: py_file, ex_equiv: ex_file} do
      args = [py_file, ex_file]

      output =
        capture_io(fn ->
          catch_exit(ValidateEquivalence.run(args))
        end)

      assert output =~ "(python)"
      assert output =~ "(elixir)"
    end

    test "allows explicit language for first file" do
      txt_file = Path.join(@tmp_dir, "test1_#{:rand.uniform(10000)}.txt")
      ex_file = Path.join(@tmp_dir, "test2_#{:rand.uniform(10000)}.ex")
      File.write!(txt_file, "x + 5")
      File.write!(ex_file, "x + 5")

      args = [txt_file, ex_file, "--lang1", "python"]

      output =
        capture_io(fn ->
          catch_exit(ValidateEquivalence.run(args))
        end)

      assert output =~ "(python)"
      assert output =~ "(elixir)"

      File.rm(txt_file)
      File.rm(ex_file)
    end

    test "allows explicit language for second file" do
      py_file = Path.join(@tmp_dir, "test1_#{:rand.uniform(10000)}.py")
      txt_file = Path.join(@tmp_dir, "test2_#{:rand.uniform(10000)}.txt")
      File.write!(py_file, "x + 5")
      File.write!(txt_file, "x + 5")

      args = [py_file, txt_file, "--lang2", "elixir"]

      output =
        capture_io(fn ->
          catch_exit(ValidateEquivalence.run(args))
        end)

      assert output =~ "(python)"
      assert output =~ "(elixir)"

      File.rm(py_file)
      File.rm(txt_file)
    end

    test "allows explicit languages for both files" do
      txt_file1 = Path.join(@tmp_dir, "test1_#{:rand.uniform(10000)}.txt")
      txt_file2 = Path.join(@tmp_dir, "test2_#{:rand.uniform(10000)}.txt")
      File.write!(txt_file1, "x + 5")
      File.write!(txt_file2, "x + 5")

      args = [txt_file1, txt_file2, "--lang1", "python", "--lang2", "elixir"]

      output =
        capture_io(fn ->
          catch_exit(ValidateEquivalence.run(args))
        end)

      assert output =~ "(python)"
      assert output =~ "(elixir)"

      File.rm(txt_file1)
      File.rm(txt_file2)
    end

    test "errors with invalid language for first file", %{py_equiv: py_file, ex_equiv: ex_file} do
      args = [py_file, ex_file, "--lang1", "invalid"]

      output =
        capture_io(:stderr, fn ->
          catch_exit(ValidateEquivalence.run(args))
        end)

      assert output =~ "Invalid language for lang1"
    end

    test "errors with invalid language for second file", %{
      py_equiv: py_file,
      ex_equiv: ex_file
    } do
      args = [py_file, ex_file, "--lang2", "invalid"]

      output =
        capture_io(:stderr, fn ->
          catch_exit(ValidateEquivalence.run(args))
        end)

      assert output =~ "Invalid language for lang2"
    end

    test "errors when cannot detect first language" do
      txt_file1 = Path.join(@tmp_dir, "test1_#{:rand.uniform(10000)}.txt")
      ex_file = Path.join(@tmp_dir, "test2_#{:rand.uniform(10000)}.ex")
      File.write!(txt_file1, "x + 5")
      File.write!(ex_file, "x + 5")

      args = [txt_file1, ex_file]

      output =
        capture_io(:stderr, fn ->
          catch_exit(ValidateEquivalence.run(args))
        end)

      assert output =~ "Cannot detect language"

      File.rm(txt_file1)
      File.rm(ex_file)
    end

    test "errors when cannot detect second language" do
      py_file = Path.join(@tmp_dir, "test1_#{:rand.uniform(10000)}.py")
      txt_file = Path.join(@tmp_dir, "test2_#{:rand.uniform(10000)}.txt")
      File.write!(py_file, "x + 5")
      File.write!(txt_file, "x + 5")

      args = [py_file, txt_file]

      output =
        capture_io(:stderr, fn ->
          catch_exit(ValidateEquivalence.run(args))
        end)

      assert output =~ "Cannot detect language"

      File.rm(py_file)
      File.rm(txt_file)
    end
  end

  describe "variable comparison" do
    test "shows common variables in verbose mode", %{py_equiv: py_file, ex_equiv: ex_file} do
      args = [py_file, ex_file, "--verbose"]

      output =
        capture_io(fn ->
          catch_exit(ValidateEquivalence.run(args))
        end)

      assert output =~ "Variables:"
      assert output =~ "x"
    end

    test "shows variable differences in verbose mode for non-equivalent files" do
      py_file = Path.join(@tmp_dir, "var1_#{:rand.uniform(10000)}.py")
      ex_file = Path.join(@tmp_dir, "var2_#{:rand.uniform(10000)}.ex")
      File.write!(py_file, "x + y")
      File.write!(ex_file, "a + b")

      args = [py_file, ex_file, "--verbose"]

      # Capture stderr for error message
      stderr_output =
        capture_io(:stderr, fn ->
          catch_exit(ValidateEquivalence.run(args))
        end)

      assert stderr_output =~ "Not semantically equivalent"

      File.rm(py_file)
      File.rm(ex_file)
    end
  end

  describe "complex expressions" do
    test "compares nested binary operations" do
      py_file = Path.join(@tmp_dir, "nested1_#{:rand.uniform(10000)}.py")
      ex_file = Path.join(@tmp_dir, "nested2_#{:rand.uniform(10000)}.ex")
      File.write!(py_file, "(a + b) * (c - d)")
      File.write!(ex_file, "(a + b) * (c - d)")

      args = [py_file, ex_file]

      output =
        capture_io(fn ->
          catch_exit(ValidateEquivalence.run(args))
        end)

      assert output =~ "Semantically equivalent"

      File.rm(py_file)
      File.rm(ex_file)
    end

    test "compares function calls" do
      py_file = Path.join(@tmp_dir, "func1_#{:rand.uniform(10000)}.py")
      ex_file = Path.join(@tmp_dir, "func2_#{:rand.uniform(10000)}.ex")
      File.write!(py_file, "foo(1, 2, 3)")
      File.write!(ex_file, "foo(1, 2, 3)")

      args = [py_file, ex_file]

      output =
        capture_io(fn ->
          catch_exit(ValidateEquivalence.run(args))
        end)

      assert output =~ "Semantically equivalent"

      File.rm(py_file)
      File.rm(ex_file)
    end

    test "identifies structural differences" do
      py_file = Path.join(@tmp_dir, "diff1_#{:rand.uniform(10000)}.py")
      ex_file = Path.join(@tmp_dir, "diff2_#{:rand.uniform(10000)}.ex")
      File.write!(py_file, "a + b")
      File.write!(ex_file, "a * b")

      args = [py_file, ex_file]

      output =
        capture_io(:stderr, fn ->
          catch_exit(ValidateEquivalence.run(args))
        end)

      assert output =~ "Not semantically equivalent"

      File.rm(py_file)
      File.rm(ex_file)
    end
  end
end
