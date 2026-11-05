defmodule Metastatic.SQLPackageTest do
  use ExUnit.Case, async: false

  @moduletag :tmp_dir
  @project_root Path.expand("../..", __DIR__)
  @required_sql_files ~w(
    priv/parsers/sql/Cargo.toml
    priv/parsers/sql/Cargo.lock
    priv/parsers/sql/src/main.rs
  )

  setup %{tmp_dir: directory} do
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

    %{directory: directory, files: files}
  end

  test "Hex packages include the complete portable SQL parser, not local build artifacts",
       %{files: files} do
    for path <- @required_sql_files do
      assert Map.has_key?(files, path), "Hex package omits SQL parser asset #{path}"
    end

    assert files["priv/parsers/sql/Cargo.toml"] =~ "sqlparser"
    assert files["priv/parsers/sql/Cargo.lock"] =~ "metastatic-sql-parser"
    refute Enum.any?(Map.keys(files), &String.starts_with?(&1, "priv/parsers/sql/target/"))
    refute Map.has_key?(files, "priv/parsers/sql/bin/sql_parser")
  end

  @tag skip: is_nil(System.find_executable("cargo"))
  @tag timeout: 180_000
  test "a clean unpacked package parses and unparses a SQL view without checkout fallbacks",
       %{directory: directory, files: files} do
    for path <- @required_sql_files do
      assert Map.has_key?(files, path), "Hex package omits SQL parser asset #{path}"
    end

    package = Path.join(directory, "package")

    for {path, content} <- files do
      destination = Path.join(package, path)
      File.mkdir_p!(Path.dirname(destination))
      File.write!(destination, content)
    end

    # Only load packaged source files in a fresh VM. The parent application's
    # priv directory and compile-time checkout must not mask missing assets.
    script = """
    source = "CREATE OR REPLACE VIEW active_items AS SELECT id FROM items WHERE deleted_at IS NULL"
    alias Metastatic.Adapters.SQL.Subprocess
    {:ok, [statement]} = Subprocess.parse(source, dialect: :postgres)
    {:ok, rebuilt} = Subprocess.unparse([statement])
    {:ok, [_]} = Subprocess.parse(rebuilt, dialect: :postgres)
    IO.puts("PACKAGED_SQL_ROUND_TRIP_OK")
    """

    {output, status} =
      System.cmd(
        System.find_executable("elixir"),
        [
          "-r",
          Path.join(package, "lib/metastatic/priv.ex"),
          "-r",
          Path.join(package, "lib/metastatic/adapters/sql/subprocess.ex"),
          "-e",
          script
        ],
        cd: directory,
        stderr_to_stdout: true,
        env: [{"CARGO_TARGET_DIR", Path.join(@project_root, "_build/sql-parser-package")}]
      )

    assert status == 0, output
    assert output =~ "PACKAGED_SQL_ROUND_TRIP_OK"
  end
end
