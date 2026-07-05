defmodule Mix.Tasks.Metastatic.TranslateTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.Metastatic.Translate

  @tmp_dir System.tmp_dir!()

  setup do
    # Create temporary test files
    python_file = Path.join(@tmp_dir, "test_translate_#{:rand.uniform(10000)}.py")
    elixir_file = Path.join(@tmp_dir, "test_translate_#{:rand.uniform(10000)}.ex")
    output_file = Path.join(@tmp_dir, "output_#{:rand.uniform(10000)}.ex")

    File.write!(python_file, "x + 5")
    File.write!(elixir_file, "a * b")

    on_exit(fn ->
      File.rm(python_file)
      File.rm(elixir_file)
      File.rm(output_file)
    end)

    %{
      python_file: python_file,
      elixir_file: elixir_file,
      output_file: output_file
    }
  end

  describe "run/1" do
    test "translates Python to Elixir with explicit output", %{
      python_file: python_file,
      output_file: output_file
    } do
      args = ["--from", "python", "--to", "elixir", python_file, "--output", output_file]

      assert capture_io(fn ->
               catch_exit(Translate.run(args))
             end) =~ "Translation complete"

      assert File.exists?(output_file)
      assert File.read!(output_file) =~ "x + 5"
    end

    test "translates Elixir to Python with auto-output", %{elixir_file: elixir_file} do
      args = ["--from", "elixir", "--to", "python", elixir_file]
      expected_output = String.replace_suffix(elixir_file, ".ex", ".py")

      output =
        capture_io(fn ->
          catch_exit(Translate.run(args))
        end)

      assert output =~ "Translated to"
      assert File.exists?(expected_output)
      assert File.read!(expected_output) =~ "a * b"

      File.rm(expected_output)
    end

    test "auto-detects source language from extension", %{
      python_file: python_file,
      output_file: output_file
    } do
      args = ["--to", "elixir", python_file, "--output", output_file]

      assert capture_io(fn ->
               catch_exit(Translate.run(args))
             end) =~ "Translation complete"

      assert File.exists?(output_file)
    end

    test "errors when source file doesn't exist" do
      args = ["--from", "python", "--to", "elixir", "/nonexistent.py", "--output", "/tmp/out.ex"]

      output =
        capture_io(:stderr, fn ->
          catch_exit(Translate.run(args))
        end)

      assert output =~ "Source path does not exist"
    end

    test "errors when no source file provided" do
      args = ["--from", "python", "--to", "elixir"]

      output =
        capture_io(:stderr, fn ->
          catch_exit(Translate.run(args))
        end)

      assert output =~ "No source file or directory provided"
    end

    test "errors when --to option missing", %{python_file: python_file} do
      args = ["--from", "python", python_file]

      output =
        capture_io(:stderr, fn ->
          catch_exit(Translate.run(args))
        end)

      assert output =~ "Missing required option: --to"
    end

    test "errors when source and target languages are the same", %{python_file: python_file} do
      args = ["--from", "python", "--to", "python", python_file]

      output =
        capture_io(:stderr, fn ->
          catch_exit(Translate.run(args))
        end)

      assert output =~ "Source and target languages are the same"
    end

    test "errors with invalid source language", %{python_file: python_file} do
      args = ["--from", "invalid", "--to", "python", python_file]

      output =
        capture_io(:stderr, fn ->
          catch_exit(Translate.run(args))
        end)

      assert output =~ "Invalid --from language"
    end

    test "errors with invalid target language", %{python_file: python_file} do
      args = ["--from", "python", "--to", "invalid", python_file]

      output =
        capture_io(:stderr, fn ->
          catch_exit(Translate.run(args))
        end)

      assert output =~ "Invalid --to language"
    end

    test "supports case-insensitive language names", %{
      python_file: python_file,
      output_file: output_file
    } do
      args = ["--from", "PYTHON", "--to", "ELIXIR", python_file, "--output", output_file]

      assert capture_io(fn ->
               catch_exit(Translate.run(args))
             end) =~ "Translation complete"

      assert File.exists?(output_file)
    end
  end

  describe "directory translation" do
    setup do
      source_dir = Path.join(@tmp_dir, "src_#{:rand.uniform(10000)}")
      output_dir = Path.join(@tmp_dir, "out_#{:rand.uniform(10000)}")

      File.mkdir_p!(source_dir)
      File.write!(Path.join(source_dir, "file1.py"), "x + 1")
      File.write!(Path.join(source_dir, "file2.py"), "y * 2")

      on_exit(fn ->
        File.rm_rf(source_dir)
        File.rm_rf(output_dir)
      end)

      %{source_dir: source_dir, output_dir: output_dir}
    end

    test "translates entire directory", %{source_dir: source_dir, output_dir: output_dir} do
      args = ["--from", "python", "--to", "elixir", source_dir, "--output", output_dir]

      output =
        capture_io(fn ->
          catch_exit(Translate.run(args))
        end)

      assert output =~ "Translated 2 files"
      assert File.exists?(Path.join(output_dir, "file1.ex"))
      assert File.exists?(Path.join(output_dir, "file2.ex"))
    end

    test "errors when directory translation missing --output", %{source_dir: source_dir} do
      args = ["--from", "python", "--to", "elixir", source_dir]

      output =
        capture_io(:stderr, fn ->
          catch_exit(Translate.run(args))
        end)

      assert output =~ "Directory translation requires --output option"
    end
  end

  describe "complex expressions" do
    test "translates nested binary operations" do
      python_file = Path.join(@tmp_dir, "complex_#{:rand.uniform(10000)}.py")
      output_file = Path.join(@tmp_dir, "complex_out_#{:rand.uniform(10000)}.ex")

      File.write!(python_file, "(a + b) * (c - d)")

      args = ["--from", "python", "--to", "elixir", python_file, "--output", output_file]

      capture_io(fn ->
        catch_exit(Translate.run(args))
      end)

      assert File.exists?(output_file)
      content = File.read!(output_file)
      assert content =~ "a + b"
      assert content =~ "c - d"

      File.rm(python_file)
      File.rm(output_file)
    end

    test "translates function calls" do
      elixir_file = Path.join(@tmp_dir, "func_#{:rand.uniform(10000)}.ex")
      output_file = Path.join(@tmp_dir, "func_out_#{:rand.uniform(10000)}.py")

      File.write!(elixir_file, "foo(1, 2, 3)")

      args = ["--from", "elixir", "--to", "python", elixir_file, "--output", output_file]

      capture_io(fn ->
        catch_exit(Translate.run(args))
      end)

      assert File.exists?(output_file)
      assert File.read!(output_file) =~ "foo(1, 2, 3)"

      File.rm(elixir_file)
      File.rm(output_file)
    end
  end
end
