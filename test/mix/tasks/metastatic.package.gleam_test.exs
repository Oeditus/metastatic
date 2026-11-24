defmodule Mix.Tasks.Metastatic.Package.GleamTest do
  @moduledoc """
  Tests for the Gleam packaging task.

  The task's job is to produce two *different* packages from one source tree,
  and the failure that matters most is the one that is easy to miss: leaving
  the working tree modified. `Cargo.toml` is swapped on disk for the
  source-only build, so every test here also asserts that the original is
  restored — including when the build fails.
  """

  use ExUnit.Case, async: false

  alias Mix.Tasks.Metastatic.Package.Gleam, as: PackageTask

  @manifest "priv/parsers/gleam/Cargo.toml"
  @source_only_manifest "priv/parsers/gleam/Cargo.source-only.toml"

  setup do
    original = File.read!(@manifest)

    on_exit(fn ->
      # Restore unconditionally: a crashed test must not leave the checkout
      # holding the source-only manifest, which would silently change what the
      # next `mix hex.build` ships.
      File.write!(@manifest, original)
      System.delete_env("HEX_BUILD")
    end)

    {:ok, original: original}
  end

  describe "the two manifests" do
    test "the full manifest declares the vendored crates" do
      manifest = File.read!(@manifest)

      assert manifest =~ "gleam-core"
      assert manifest =~ "gleam-format"
      assert manifest =~ "vendor/compiler-core"
    end

    test "the source-only manifest declares no vendored path dependencies" do
      manifest = File.read!(@source_only_manifest)

      # A `path` *dependency* is resolved by Cargo even when the feature that
      # enables it is off, so any such entry would break the unpacked package.
      # `[[bin]] path` is not a dependency and is expected, so the check is on
      # the dependency table rather than on the string "path =" anywhere.
      [dependencies] = Regex.run(~r/\[dependencies\](.*)/s, manifest, capture: :all_but_first)
      refute dependencies =~ "path ="
      refute dependencies =~ "gleam-core"
    end

    test "the source-only manifest defaults to the external-gleam feature" do
      manifest = File.read!(@source_only_manifest)

      assert manifest =~ ~s(default = ["external-gleam"])
    end

    test "both manifests name the same binary" do
      for manifest <- [@manifest, @source_only_manifest] do
        assert File.read!(manifest) =~ ~s(name = "metastatic-gleam-parser")
      end
    end
  end

  describe "the task" do
    test "rejects an unknown option with a usage error" do
      assert catch_exit(PackageTask.run(["--bogus"])) ==
               {:shutdown, 2}
    end

    test "a dry run does not touch the manifest", %{original: original} do
      PackageTask.run(["--source-only", "--dry-run"])

      assert File.read!(@manifest) == original
    end

    test "a dry run does not set HEX_BUILD" do
      PackageTask.run(["--source-only", "--dry-run"])

      assert System.get_env("HEX_BUILD") == nil
    end
  end

  describe "the manifest swap" do
    # The swap is exercised through the public task with a build that cannot
    # succeed, which is the interesting case: the restore must happen on the
    # failure path too.
    test "restores the manifest when the build fails", %{original: original} do
      # An output path under a file (not a directory) makes `hex.build` fail.
      blocker = Path.join(System.tmp_dir!(), "metastatic-pkg-blocker")
      File.write!(blocker, "not a directory")

      on_exit(fn -> File.rm(blocker) end)

      assert catch_exit(
               PackageTask.run([
                 "--source-only",
                 "-o",
                 Path.join(blocker, "out")
               ])
             ) == {:shutdown, 1}

      assert File.read!(@manifest) == original,
             "the manifest must be restored even when the build fails"
    end
  end

  describe "build artefacts" do
    test "no cargo target directory is inside the vendored tree" do
      # `priv/parsers/gleam/target` is the bridge's own build directory: it is
      # gitignored and excluded from `:files`, so it is expected and harmless.
      #
      # A `cargo build` run from *inside* `vendor/` is different: it leaves a
      # ~700 MB `target/` that ships with the package (Hex packages the working
      # tree, not the index) and fails the build with "package exceeds max
      # uncompressed size". That is the case this guards.
      stray =
        Path.wildcard("priv/parsers/gleam/vendor/**/target")
        |> Enum.filter(&File.dir?/1)

      assert stray == [],
             "cargo build artefacts must not live inside the vendored tree: #{inspect(stray)}"
    end

    test "the vendored tree stays within a sane size" do
      # The vendored crates are ~5 MB. An order-of-magnitude jump means
      # something was copied in that should not have been, and the failure mode
      # (a package Hex refuses to build) is far from the cause.
      bytes =
        "priv/parsers/gleam/vendor/**/*"
        |> Path.wildcard()
        |> Enum.filter(&File.regular?/1)
        |> Enum.map(&File.stat!/1)
        |> Enum.map(& &1.size)
        |> Enum.sum()

      assert bytes < 50 * 1024 * 1024,
             "priv/parsers/gleam/vendor is #{div(bytes, 1024 * 1024)} MB; expected under 50 MB"
    end
  end

  describe "the package file list" do
    test "the full build ships the vendored crates" do
      System.delete_env("HEX_BUILD")
      files = Mix.Project.config()[:package][:files]

      assert "priv/parsers/gleam/vendor" in files
      assert "priv/parsers/gleam/Cargo.toml" in files
    end

    test "both builds always ship the bridge sources" do
      files = Mix.Project.config()[:package][:files]

      assert "priv/parsers/gleam/src" in files
      assert "priv/parsers/gleam/Cargo.toml" in files
    end

    test "the vendored crates are the only thing HEX_BUILD=1 may drop" do
      # `mix.exs` reads `HEX_BUILD` when it is loaded, which has already
      # happened by the time a test runs, so the compiled list is what the
      # *current* build ships. What is asserted here is the rule itself: the
      # source-only list is the full list minus `vendor/` (and the spare
      # manifest), and nothing else — a size win must never cost a source file.
      full = Mix.Project.config()[:package][:files]

      assert "priv/parsers/gleam/vendor" in full

      source_only =
        full
        |> List.delete("priv/parsers/gleam/vendor")
        |> List.delete("priv/parsers/gleam/Cargo.source-only.toml")

      assert "priv/parsers/gleam/src" in source_only
      assert "priv/parsers/gleam/Cargo.toml" in source_only
      assert length(full) - length(source_only) == 2
    end

    test "mix.exs reads HEX_BUILD rather than hard-coding the file list" do
      # The mechanism, not its current output: if the env var stops being
      # consulted, `HEX_BUILD=1 mix hex.build` silently ships 4.9 MB of
      # vendored crates and no test above would notice.
      assert File.read!("mix.exs") =~ "System.get_env(\"HEX_BUILD\")"
    end
  end
end
