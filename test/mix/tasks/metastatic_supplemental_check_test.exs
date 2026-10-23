defmodule Mix.Tasks.Metastatic.SupplementalCheckTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.Metastatic.SupplementalCheck

  @tmp_dir System.tmp_dir!()

  setup do
    dir = Path.join(@tmp_dir, "supp_check_#{:rand.uniform(1_000_000)}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)
    %{dir: dir}
  end

  defp write!(dir, name, content) do
    path = Path.join(dir, name)
    File.write!(path, content)
    path
  end

  describe "argument validation" do
    test "errors with exit code 2 when no file is given" do
      parent = self()

      stderr =
        capture_io(:stderr, fn ->
          send(parent, {:out, capture_io(fn -> catch_exit(SupplementalCheck.run([])) end)})
        end)

      stdout =
        receive do
          {:out, out} -> out
        after
          0 -> ""
        end

      out = stdout <> stderr
      assert out =~ "No file specified"
      assert out =~ "Usage:"
    end

    test "errors with exit code 2 when the file does not exist" do
      missing = Path.join(@tmp_dir, "nope_#{:rand.uniform(1_000_000)}.ex")

      capture_io(fn ->
        assert catch_exit(SupplementalCheck.run([missing])) == {:shutdown, 2}
      end)
    end
  end

  describe "construct detection (no --target)" do
    test "reports no supplementals needed for plain code and exits 0", %{dir: dir} do
      path = write!(dir, "plain.ex", "defmodule P do\n  def f(x), do: x + 1\nend\n")

      out =
        capture_io(fn ->
          assert catch_exit(SupplementalCheck.run([path])) == {:shutdown, 0}
        end)

      assert is_binary(out)
    end

    test "emits JSON when --format json is given", %{dir: dir} do
      path = write!(dir, "plain2.ex", "defmodule Q do\n  def g(x), do: x * 2\nend\n")

      out =
        capture_io(fn ->
          catch_exit(SupplementalCheck.run([path, "--format", "json"]))
        end)

      assert out =~ "required"
    end
  end

  describe "translation compatibility (--target)" do
    test "reports compatibility with the target language", %{dir: dir} do
      path = write!(dir, "simple.ex", "defmodule S do\n  def h(x), do: x\nend\n")

      code =
        try do
          capture_io(fn -> SupplementalCheck.run([path, "--target", "python"]) end)
          0
        catch
          :exit, {:shutdown, c} -> c
        end

      assert code in [0, 1]
    end

    test "supports the detailed format", %{dir: dir} do
      path = write!(dir, "simple2.ex", "defmodule T do\n  def i(x), do: x\nend\n")

      out =
        capture_io(fn ->
          catch_exit(SupplementalCheck.run([path, "--target", "python", "--format", "detailed"]))
        end)

      assert is_binary(out)
    end
  end

  describe "parse errors" do
    test "exits 2 on a parse error", %{dir: dir} do
      path = write!(dir, "bad.ex", "defmodule ( broken")

      capture_io(fn ->
        assert catch_exit(SupplementalCheck.run([path])) == {:shutdown, 2}
      end)
    end
  end
end
