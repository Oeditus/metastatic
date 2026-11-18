defmodule Metastatic.PrivTest do
  @moduledoc """
  Tests for `priv/` resolution and executable lookup.

  The interesting case is a language adapter shipped from a *host*
  application: its parser scripts live in the host's `priv/`, not
  Metastatic's. `parser_path/1` must find them without configuration.
  """

  use ExUnit.Case, async: false

  alias Metastatic.Priv

  describe "parser_path/1" do
    test "resolves a path that exists in Metastatic's own priv" do
      path = Priv.parser_path("parsers/python/parser.py")

      assert File.exists?(path)
      assert path =~ "parsers/python/parser.py"
    end

    test "accepts a path already prefixed with priv/" do
      with_prefix = Priv.parser_path("priv/parsers/python/parser.py")
      without_prefix = Priv.parser_path("parsers/python/parser.py")

      assert with_prefix == without_prefix
    end

    test "returns a predictable path when nothing exists" do
      # Callers rely on this to produce an error message naming a real path
      # rather than `nil`.
      assert Priv.parser_path("parsers/does-not-exist/parser") =~ "parsers/does-not-exist/parser"
    end

    test "honours configured :priv_dirs" do
      dir =
        Path.join(System.tmp_dir!(), "metastatic_priv_test_#{System.unique_integer([:positive])}")

      File.mkdir_p!(Path.join(dir, "parsers/rust"))
      marker = Path.join(dir, "parsers/rust/parser")
      File.write!(marker, "#!/bin/sh\n")

      previous = Application.get_env(:metastatic, :priv_dirs)

      try do
        Application.put_env(:metastatic, :priv_dirs, [dir])
        assert Priv.parser_path("parsers/rust/parser") == marker
      after
        Application.put_env(:metastatic, :priv_dirs, previous)
        File.rm_rf!(dir)
      end
    end

    test "resolves a parser shipped by the host application" do
      # Simulate the third-party-adapter layout: a host app whose `priv/`
      # contains the bridge. `:metastatic`'s own priv is searched first, so the
      # file name is unique to avoid a false positive.
      host_priv =
        Path.join(System.tmp_dir!(), "metastatic_host_#{System.unique_integer([:positive])}")

      File.mkdir_p!(Path.join(host_priv, "parsers/hostlang"))
      marker = Path.join(host_priv, "parsers/hostlang/bridge")
      File.write!(marker, "#!/bin/sh\n")

      previous = Application.get_env(:metastatic, :priv_dirs)

      try do
        Application.put_env(:metastatic, :priv_dirs, [host_priv])

        assert Priv.parser_path("parsers/hostlang/bridge") == marker
      after
        Application.put_env(:metastatic, :priv_dirs, previous)
        File.rm_rf!(host_priv)
      end
    end
  end

  describe "find_executable/1" do
    test "finds an executable on PATH" do
      assert Priv.find_executable("sh")
    end

    test "returns nil for an unknown executable" do
      assert Priv.find_executable("metastatic-definitely-not-installed") == nil
    end
  end

  describe "subprocess_env/0" do
    test "always provides a PATH" do
      env = Priv.subprocess_env()
      assert {"PATH", path} = List.keyfind(env, "PATH", 0)
      assert is_binary(path) and path != ""
    end

    test "merges caller extras on top" do
      env = Priv.subprocess_env([{"METASTATIC_TEST", "1"}])

      assert {"METASTATIC_TEST", "1"} = List.keyfind(env, "METASTATIC_TEST", 0)
    end
  end
end
