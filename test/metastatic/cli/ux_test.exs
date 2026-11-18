defmodule Metastatic.CLI.UxTest do
  @moduledoc """
  Tests for the CLI ergonomics fixed in the 2026-11-18 audit (phase 3).

  These are deliberately behavioural: they assert what a user sees and what
  exit status a script observes, not internal structure.
  """

  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Metastatic.CLI

  doctest Metastatic.CLI

  describe "format_reason/1 (item 3)" do
    test "a plain string is not wrapped in inspect syntax" do
      assert CLI.format_reason("Syntax error at line 1") == "Syntax error at line 1"
      refute CLI.format_reason("Syntax error at line 1") =~ ~s(")
    end

    test "unwraps a {:error, string} tuple" do
      assert CLI.format_reason({:error, "boom"}) == "boom"
    end

    test "unwraps a nested {:error, {:error, string}}" do
      assert CLI.format_reason({:error, {:error, "boom"}}) == "boom"
    end

    test "inspects an atom reason" do
      assert CLI.format_reason({:error, :enoent}) == ":enoent"
    end

    test "inspects a genuinely opaque reason" do
      assert CLI.format_reason(%{code: 1}) == "%{code: 1}"
    end
  end

  describe "fatal/2 exit codes (item 16)" do
    test "defaults to exit status 1" do
      assert catch_exit(capture_io(:stderr, fn -> CLI.fatal("boom") end)) == {:shutdown, 1}
    end

    test "accepts an explicit usage-error status" do
      assert catch_exit(capture_io(:stderr, fn -> CLI.fatal("boom", 2) end)) == {:shutdown, 2}
    end

    test "prints the message with an Error: prefix" do
      out = capture_io(:stderr, fn -> catch_exit(CLI.fatal("boom")) end)
      assert out =~ "Error:"
      assert out =~ "boom"
    end
  end

  describe "help_requested?/1 (item 5)" do
    test "recognises --help" do
      assert CLI.help_requested?(["--help"])
    end

    test "recognises -h among other arguments" do
      assert CLI.help_requested?(["file.py", "-h"])
    end

    test "does not fire on ordinary arguments" do
      refute CLI.help_requested?(["file.py", "--format", "json"])
    end

    test "does not fire on an empty argument list" do
      refute CLI.help_requested?([])
    end
  end

  describe "help/1 (item 5)" do
    test "prints the task's usage block and exits 0" do
      out =
        capture_io(fn ->
          assert catch_exit(CLI.help(Mix.Tasks.Metastatic.Translate)) == {:shutdown, 0}
        end)

      assert out =~ "mix metastatic.translate"
      assert out =~ "--from"
      assert out =~ "--to"
    end
  end

  describe "every metastatic task accepts --help (item 5)" do
    for task <- [
          Mix.Tasks.Metastatic.Translate,
          Mix.Tasks.Metastatic.Inspect,
          Mix.Tasks.Metastatic.ValidateEquivalence,
          Mix.Tasks.Metastatic.SupplementalCheck,
          Mix.Tasks.Metastatic.Lint.Prose,
          Mix.Tasks.Metastatic.Gen.Supplemental
        ] do
      test "#{inspect(task)} exits 0 on --help" do
        out =
          capture_io(fn ->
            assert catch_exit(unquote(task).run(["--help"])) == {:shutdown, 0}
          end)

        assert String.trim(out) != ""
      end
    end
  end
end
