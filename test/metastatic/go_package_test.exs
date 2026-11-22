defmodule Metastatic.GoPackageTest do
  use ExUnit.Case, async: false

  @moduletag :tmp_dir
  @moduletag timeout: 180_000
  @project_root Path.expand("../..", __DIR__)

  test "a clean Hex package contains a buildable Go bridge without checkout fallbacks",
       %{tmp_dir: directory} do
    archive = Path.join(directory, "metastatic.tar")

    {output, status} =
      System.cmd("mix", ["hex.build", "--output", archive],
        cd: @project_root,
        stderr_to_stdout: true
      )

    assert status == 0, output
    assert {:ok, outer} = :erl_tar.extract(String.to_charlist(archive), [:memory])
    assert {_, contents} = List.keyfind(outer, ~c"contents.tar.gz", 0)
    assert {:ok, entries} = :erl_tar.extract({:binary, contents}, [:compressed, :memory])
    files = Map.new(entries, fn {path, content} -> {List.to_string(path), content} end)

    for name <- ["go.mod", "main.go", "ast.go", "to_json.go", "from_json.go"] do
      assert Map.has_key?(files, "priv/parsers/go/#{name}"), "Go package asset missing: #{name}"
    end

    refute Enum.any?(Map.keys(files), &String.contains?(&1, "parsers/go/bin/"))

    if Metastatic.Priv.find_executable("go") do
      package = Path.join(directory, "package")

      for {path, content} <- files do
        destination = Path.join(package, path)
        File.mkdir_p!(Path.dirname(destination))
        File.write!(destination, content)
      end

      script = """
      alias Metastatic.Adapters.Go.Subprocess
      source = "package p\\nfunc Add(a, b int) int { return a + b }\\n"
      {:ok, ast} = Subprocess.parse(source)
      {:ok, rebuilt} = Subprocess.unparse(ast)
      {:ok, _} = Subprocess.parse(rebuilt)
      {:ok, %{"status" => "ok"}} = Subprocess.selftest()
      IO.puts("PACKAGED_GO_ROUND_TRIP_OK")
      """

      paths = [
        "lib/metastatic/priv.ex",
        "lib/metastatic/subprocess.ex",
        "lib/metastatic/json.ex",
        "lib/metastatic/adapter/bridge.ex",
        "lib/metastatic/adapters/go/subprocess.ex"
      ]

      args = Enum.flat_map(paths, &["-r", Path.join(package, &1)]) ++ ["-e", script]

      {output, status} =
        System.cmd(System.find_executable("elixir"), args,
          cd: directory,
          stderr_to_stdout: true,
          env: [{"XDG_CACHE_HOME", Path.join(directory, "cache")}]
        )

      assert status == 0, output
      assert output =~ "PACKAGED_GO_ROUND_TRIP_OK"
    end
  end
end
