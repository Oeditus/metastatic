defmodule Mix.Tasks.Metastatic.Gen.SupplementalTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.Metastatic.Gen.Supplemental

  setup do
    dir = Path.join(System.tmp_dir!(), "gen_supp_#{:rand.uniform(1_000_000)}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)
    %{dir: dir}
  end

  # The generator writes to lib/ and test/ relative to the CWD, so run it
  # inside a throwaway directory.
  defp generate!(dir, args) do
    File.cd!(dir, fn ->
      capture_io(fn -> Supplemental.run(args) end)
    end)
  end

  describe "argument validation" do
    test "requires --language and exits 1" do
      dir = Path.join(System.tmp_dir!(), "gen_supp_missing_#{:rand.uniform(1_000_000)}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf(dir) end)

      out =
        File.cd!(dir, fn ->
          capture_io(fn ->
            assert catch_exit(Supplemental.run(["python.requests"])) == {:shutdown, 1}
          end)
        end)

      assert out =~ "Usage:"
    end
  end

  describe "generation" do
    test "creates the module and test files", %{dir: dir} do
      generate!(dir, ["python.requests", "--language", "python"])

      assert File.exists?(Path.join(dir, "lib/metastatic/supplemental/python/requests.ex"))
      assert File.exists?(Path.join(dir, "test/metastatic/supplemental/python/requests_test.exs"))
    end

    test "generated module implements the Supplemental behaviour", %{dir: dir} do
      generate!(dir, ["python.requests", "--language", "python"])

      content =
        File.read!(Path.join(dir, "lib/metastatic/supplemental/python/requests.ex"))

      assert content =~ "@behaviour Metastatic.Supplemental"
      assert content =~ "defmodule"
      assert content =~ "Requests"
      assert content =~ "def info"
      assert content =~ "def transform"
    end

    test "generated module records the target language", %{dir: dir} do
      generate!(dir, ["javascript.axios", "--language", "javascript"])

      content =
        File.read!(Path.join(dir, "lib/metastatic/supplemental/javascript/axios.ex"))

      assert content =~ "javascript"
    end

    test "passes constructs and library metadata through", %{dir: dir} do
      generate!(dir, [
        "python.requests",
        "--language",
        "python",
        "--constructs",
        "http_get,http_post",
        "--library",
        "requests",
        "--library-version",
        ">=2.28.0"
      ])

      content =
        File.read!(Path.join(dir, "lib/metastatic/supplemental/python/requests.ex"))

      assert content =~ "http_get"
      assert content =~ "http_post"
    end

    test "reports the created files", %{dir: dir} do
      out = generate!(dir, ["ruby.httparty", "--language", "ruby"])
      assert out =~ "creating"
      assert out =~ "Supplemental module created successfully"
    end

    test "generated source is syntactically valid Elixir", %{dir: dir} do
      generate!(dir, ["python.requests", "--language", "python"])

      content =
        File.read!(Path.join(dir, "lib/metastatic/supplemental/python/requests.ex"))

      assert {:ok, _ast} = Code.string_to_quoted(content)
    end

    test "generated test file is syntactically valid Elixir", %{dir: dir} do
      generate!(dir, ["python.requests", "--language", "python"])

      content =
        File.read!(Path.join(dir, "test/metastatic/supplemental/python/requests_test.exs"))

      assert {:ok, _ast} = Code.string_to_quoted(content)
    end
  end

  # Defects 8 and 9: the scaffold used to emit `target_language:`/`dependencies:`
  # (fields that do not exist on `Metastatic.Supplemental.Info`, so the module
  # did not compile) and tests whose bodies were comments only, so a freshly
  # generated scaffold turned the suite green while doing nothing.
  describe "generated scaffold correctness" do
    test "info/0 uses the real Info field names", %{dir: dir} do
      generate!(dir, ["python.requests", "--language", "python"])

      content = File.read!(Path.join(dir, "lib/metastatic/supplemental/python/requests.ex"))

      assert content =~ "language: :python"
      assert content =~ "requires:"
      assert content =~ "description:"
      refute content =~ "target_language:"
      refute content =~ "dependencies:"
    end

    test "info/0 includes the required :name field", %{dir: dir} do
      generate!(dir, ["python.requests", "--language", "python"])

      content = File.read!(Path.join(dir, "lib/metastatic/supplemental/python/requests.ex"))

      assert content =~ "name: :requests"
    end

    test "generated transform/3 matches the behaviour's arity and language argument", %{dir: dir} do
      generate!(dir, ["python.requests", "--language", "python"])

      content = File.read!(Path.join(dir, "lib/metastatic/supplemental/python/requests.ex"))

      # transform(meta_ast, language, metadata) -- the language, not :from_meta.
      refute content =~ ":from_meta"
      refute content =~ ":to_meta"
      assert content =~ "def transform(_ast, _language, _metadata), do: :error"
    end

    test "generated tests fail loudly instead of passing silently", %{dir: dir} do
      generate!(dir, ["python.requests", "--language", "python"])

      content =
        File.read!(Path.join(dir, "test/metastatic/supplemental/python/requests_test.exs"))

      assert content =~ "flunk("
      refute content =~ "# TODO: Implement test"
    end

    test "generated tests assert against a real Info struct", %{dir: dir} do
      generate!(dir, ["python.requests", "--language", "python"])

      content =
        File.read!(Path.join(dir, "test/metastatic/supplemental/python/requests_test.exs"))

      assert content =~ "assert info.language == :python"
      assert content =~ "Info.valid?(info)"
      refute content =~ "info.target_language"
    end
  end
end
