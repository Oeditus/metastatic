defmodule Metastatic.Adapters.Java.SubprocessTest do
  use ExUnit.Case, async: false

  alias Metastatic.Adapters.Java.Subprocess

  setup do
    directory =
      Path.join(
        System.tmp_dir!(),
        "metastatic_java_runtime_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(directory)
    previous = Map.take(System.get_env(), ["PATH", "JAVA_HOME", "HOME"])
    System.put_env(%{"PATH" => directory, "JAVA_HOME" => directory, "HOME" => directory})

    on_exit(fn ->
      for key <- ["PATH", "JAVA_HOME", "HOME"] do
        case previous[key] do
          nil -> System.delete_env(key)
          value -> System.put_env(key, value)
        end
      end

      File.rm_rf!(directory)
    end)

    {:ok, directory: directory}
  end

  test "returns an error when no runtime is installed" do
    assert Subprocess.java_executable() == nil
    assert {:error, reason} = Subprocess.parse("class A {}")
    assert reason =~ "Java parser unavailable"
  end

  test "prefers JAVA_HOME over PATH", %{directory: directory} do
    home_java = executable(Path.join(directory, "bin/java"))
    executable(Path.join(directory, "java"))

    assert Subprocess.java_executable() == home_java
  end

  test "falls back to PATH when JAVA_HOME is invalid", %{directory: directory} do
    path_java = executable(Path.join(directory, "java"))
    assert Subprocess.java_executable() == path_java
  end

  test "falls back to an installed JDK when the PATH shim fails", %{directory: directory} do
    executable(Path.join(directory, "java"), 1)

    installed_java =
      executable(Path.join(directory, ".local/share/mise/installs/java/test-jdk/bin/java"))

    assert Subprocess.java_executable() == installed_java
  end

  defp executable(path, status \\ 0) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "#!/bin/sh\nexit #{status}\n")
    File.chmod!(path, 0o755)
    path
  end
end
