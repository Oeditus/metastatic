defmodule Mix.Tasks.Metastatic.ValidateEquivalenceTest do
  @moduledoc """
  Regression tests for defect 11.

  `mix metastatic.validate-equivalence` used to strip a hand-maintained list of
  location keys and then compare the raw remainder. Adapter bookkeeping such as
  `:original_meta`, `:origin` and `:desugar` therefore made two semantically
  identical files compare as *different*, while `Document.equivalent?/2` (which
  uses `AST.canonicalize/1`) called them equal. The task now delegates to the
  same canonicaliser.
  """

  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Mix.Tasks.Metastatic.ValidateEquivalence

  @tmp Path.join(System.tmp_dir!(), "metastatic_validate_equivalence_test")

  setup do
    File.mkdir_p!(@tmp)
    on_exit(fn -> File.rm_rf!(@tmp) end)
    :ok
  end

  defp write(name, content) do
    path = Path.join(@tmp, name)
    File.write!(path, content)
    path
  end

  defp run_task(args) do
    capture_io(fn ->
      try do
        ValidateEquivalence.run(args)
      catch
        :exit, {:shutdown, code} -> Process.put(:exit_code, code)
      end
    end)
  end

  describe "metadata that does not affect semantics" do
    test "identical source in the same language is equivalent" do
      f1 = write("a.ex", "x = 1 + 2")
      f2 = write("b.ex", "x = 1 + 2")

      run_task([f1, f2, "--lang1", "elixir", "--lang2", "elixir"])
      assert Process.get(:exit_code) == 0
    end

    test "differing whitespace and line numbers are ignored" do
      f1 = write("c.ex", "x = 1 + 2")
      f2 = write("d.ex", "\n\n\nx = 1 + 2\n")

      run_task([f1, f2, "--lang1", "elixir", "--lang2", "elixir"])
      assert Process.get(:exit_code) == 0
    end

    test "genuinely different programs are not equivalent" do
      f1 = write("e.ex", "x = 1 + 2")
      f2 = write("f.ex", "x = 1 - 2")

      run_task([f1, f2, "--lang1", "elixir", "--lang2", "elixir"])
      assert Process.get(:exit_code) == 1
    end
  end

  describe "--alpha" do
    test "renamed variables compare equal" do
      f1 = write("g.ex", "x = 1 + 2")
      f2 = write("h.ex", "y = 1 + 2")

      run_task([f1, f2, "--lang1", "elixir", "--lang2", "elixir", "--alpha"])
      assert Process.get(:exit_code) == 0
    end

    test "without --alpha renamed variables differ" do
      f1 = write("i.ex", "x = 1 + 2")
      f2 = write("j.ex", "y = 1 + 2")

      run_task([f1, f2, "--lang1", "elixir", "--lang2", "elixir"])
      assert Process.get(:exit_code) == 1
    end
  end

  describe "argument validation" do
    test "requires two files" do
      f1 = write("k.ex", "x = 1")

      run_task([f1, "--lang1", "elixir", "--lang2", "elixir"])
      # Usage errors exit 2, distinct from "the comparison ran and failed" (1).
      assert Process.get(:exit_code) == 2
    end

    test "reports a missing file" do
      f1 = write("l.ex", "x = 1")

      run_task([f1, "/nonexistent/file.ex", "--lang1", "elixir", "--lang2", "elixir"])
      assert Process.get(:exit_code) == 2
    end
  end
end
