defmodule Mix.Tasks.Metastatic.Lint.ProseTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.Metastatic.Lint.Prose

  @tmp_dir System.tmp_dir!()

  setup do
    dir = Path.join(@tmp_dir, "prose_lint_#{:rand.uniform(1_000_000)}")
    File.mkdir_p!(dir)

    on_exit(fn -> File.rm_rf(dir) end)

    %{dir: dir}
  end

  defp write!(dir, name, content) do
    path = Path.join(dir, name)
    File.write!(path, content)
    path
  end

  # The task reports summaries and errors via Mix.shell().error/1, which
  # writes to stderr; capture both streams and concatenate so assertions see
  # everything regardless of which stream it went to.
  #
  # The task now exits with a status code (0 clean, 1 issues, 2 nothing to
  # lint), so the exit is caught here and returned alongside the output.
  defp run(args) do
    parent = self()

    stderr =
      capture_io(:stderr, fn ->
        stdout = capture_io(fn -> send(parent, {:exit, catch_exit(Prose.run(args))}) end)
        send(parent, {:stdout, stdout})
      end)

    stdout =
      receive do
        {:stdout, out} -> out
      after
        0 -> ""
      end

    exit_status =
      receive do
        {:exit, status} -> status
      after
        0 -> :no_exit
      end

    {stdout <> stderr, exit_status}
  end

  describe "clean prose" do
    test "reports a clean file and exits 0", %{dir: dir} do
      path = write!(dir, "clean.md", "The cat sat on the mat. It was warm.")
      {out, status} = run([path])

      assert out =~ "clean"
      assert out =~ "passed prose linting cleanly"
      assert status == {:shutdown, 0}
    end
  end

  describe "prose with issues" do
    test "reports issues and exits 1 so it can gate CI", %{dir: dir} do
      # A long, passive, weasel-laden sentence trips several rules.
      content =
        "It was decided by the committee that the report should possibly be " <>
          "reviewed by several people before it might be approved by the board " <>
          "and then perhaps forwarded to the various stakeholders for comments."

      path = write!(dir, "messy.md", content)
      {out, status} = run([path])

      assert out =~ "issue(s)"
      assert out =~ "Found"
      assert status == {:shutdown, 1}
    end
  end

  describe "directory expansion" do
    test "lints every markdown file in a directory", %{dir: dir} do
      write!(dir, "a.md", "A short clean sentence.")
      write!(dir, "b.txt", "Another short clean sentence.")
      # Non-prose files must be ignored by the wildcard.
      write!(dir, "c.ex", "defmodule X do end")

      {out, _status} = run([dir])

      assert out =~ "a.md"
      assert out =~ "b.txt"
      refute out =~ "c.ex"
    end
  end

  describe "edge cases" do
    test "reports a missing path and exits 2" do
      {out, status} =
        run([Path.join(@tmp_dir, "definitely_missing_#{:rand.uniform(1_000_000)}.md")])

      assert out =~ "Path not found"
      assert out =~ "No files to lint"
      assert status == {:shutdown, 2}
    end

    test "reports no files when given an empty directory", %{dir: dir} do
      {out, status} = run([dir])
      assert out =~ "No files to lint"
      assert status == {:shutdown, 2}
    end

    test "says which file it lints when given no argument" do
      # Runs from the project root, where README.md exists.
      {out, _status} = run([])
      assert out =~ "README.md"
    end
  end

  describe "options" do
    test "accepts --max-words and --format options", %{dir: dir} do
      path = write!(dir, "opt.md", "A short sentence.")
      {out, _status} = run([path, "--max-words", "5", "--format", "text"])

      assert is_binary(out)
    end

    test "--help prints the usage block and exits 0" do
      {out, status} = run(["--help"])

      assert out =~ "mix metastatic.lint.prose"
      assert status == {:shutdown, 0}
    end
  end
end
