defmodule Metastatic.SubprocessTest do
  @moduledoc """
  Tests for the shared subprocess plumbing extracted in the 2026-11-18 audit.

  Before this module existed, nine adapter bridges each carried their own copy
  of "write temp file, shell out, delete temp file", with drifting error
  formats and inconsistent cleanup.
  """

  use ExUnit.Case, async: true

  alias Metastatic.Subprocess

  doctest Metastatic.Subprocess

  describe "write_temp_file/2" do
    test "writes the input and returns a readable path" do
      path = Subprocess.write_temp_file("hello")
      on_exit(fn -> File.rm(path) end)

      assert File.read!(path) == "hello"
    end

    test "honours the :ext option" do
      path = Subprocess.write_temp_file("x", ext: ".py")
      on_exit(fn -> File.rm(path) end)

      assert Path.extname(path) == ".py"
    end

    test "honours the :prefix option" do
      path = Subprocess.write_temp_file("x", prefix: "custom_prefix")
      on_exit(fn -> File.rm(path) end)

      assert Path.basename(path) =~ "custom_prefix"
    end

    test "produces distinct paths for concurrent writers" do
      paths =
        1..20
        |> Enum.map(fn i -> Task.async(fn -> Subprocess.write_temp_file("payload #{i}") end) end)
        |> Task.await_many()

      on_exit(fn -> Enum.each(paths, &File.rm/1) end)

      assert length(Enum.uniq(paths)) == 20
    end
  end

  describe "with_temp_file/3" do
    test "passes an existing file to the callback" do
      result = Subprocess.with_temp_file("data", [], fn path -> File.read!(path) end)
      assert result == "data"
    end

    test "removes the file after the callback returns" do
      path = Subprocess.with_temp_file("data", [], fn path -> path end)
      refute File.exists?(path)
    end

    test "removes the file even when the callback raises" do
      path =
        try do
          Subprocess.with_temp_file("data", [], fn path -> raise("boom #{path}") end)
        rescue
          error -> error |> Exception.message() |> String.replace_prefix("boom ", "")
        end

      refute File.exists?(path)
    end
  end

  describe "run/4" do
    test "returns stdout on success" do
      assert {:ok, "hello"} = Subprocess.run("cat", [], "hello")
    end

    test "appends the temp-file path as the last argument" do
      assert {:ok, output} = Subprocess.run("cat", ["-A"], "abc")
      assert output =~ "abc"
    end

    test "reports a non-zero exit as an error tuple" do
      assert {:error, reason} = Subprocess.run("sh", ["-c", "exit 3"], "")
      assert reason =~ "Exit code 3"
    end

    test "reports a missing executable as an error tuple, not a raise" do
      assert {:error, reason} = Subprocess.run("/nonexistent/binary", [], "x")
      assert is_binary(reason)
    end

    test "never leaves a temp file behind on failure" do
      before = temp_files("metastatic_cleanup_fail")

      assert {:error, _} =
               Subprocess.run("sh", ["-c", "exit 1"], "payload",
                 prefix: "metastatic_cleanup_fail"
               )

      assert temp_files("metastatic_cleanup_fail") == before
    end

    test "never leaves a temp file behind on success" do
      before = temp_files("metastatic_cleanup_ok")
      assert {:ok, _} = Subprocess.run("cat", [], "payload", prefix: "metastatic_cleanup_ok")
      assert temp_files("metastatic_cleanup_ok") == before
    end

    test "honours :cd" do
      assert {:ok, output} = Subprocess.run("sh", ["-c", "pwd"], "", cd: System.tmp_dir!())
      assert String.trim(output) == System.tmp_dir!()
    end

    test "honours :env" do
      assert {:ok, output} =
               Subprocess.run("sh", ["-c", "echo $MY_VAR"], "", env: [{"MY_VAR", "v"}])

      assert String.trim(output) == "v"
    end
  end

  describe "format_error/1" do
    test "includes the line number when present" do
      assert Subprocess.format_error(%{"type" => "SyntaxError", "msg" => "bad", "lineno" => 3}) ==
               "SyntaxError at line 3: bad"
    end

    test "omits the line number when absent" do
      assert Subprocess.format_error(%{"type" => "SyntaxError", "msg" => "bad"}) ==
               "SyntaxError: bad"
    end

    test "ignores a nil line number" do
      assert Subprocess.format_error(%{"type" => "E", "msg" => "m", "lineno" => nil}) == "E: m"
    end

    test "passes a plain string through" do
      assert Subprocess.format_error("plain") == "plain"
    end

    test "inspects unknown shapes" do
      assert Subprocess.format_error({:weird, 1}) == "{:weird, 1}"
    end
  end

  defp temp_files(prefix) do
    Path.wildcard(Path.join(System.tmp_dir!(), "#{prefix}*"))
  end
end
