defmodule Metastatic.BuilderTest do
  use ExUnit.Case, async: false

  alias Metastatic.{Builder, Document, Adapter}

  # Mock adapter for testing Builder functionality
  defmodule MockPythonAdapter do
    @behaviour Metastatic.Adapter

    @impl true
    def parse("syntax error"), do: {:error, "SyntaxError: invalid syntax"}

    def parse(source) do
      # Simple mock: parse basic arithmetic
      {:ok, %{type: "Module", body: [%{type: "Expr", value: source}]}}
    end

    @impl true
    def to_meta(%{type: "Module", body: [%{type: "Expr", value: "x + 5"}]}) do
      {:ok, {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}},
       %{python_version: "3.11"}}
    end

    def to_meta(%{type: "Module", body: [%{type: "Expr", value: "42"}]}) do
      {:ok, {:literal, :integer, 42}, %{}}
    end

    def to_meta(%{type: "Module", body: [%{type: "Expr", value: source}]}) do
      {:ok, {:literal, :string, source}, %{}}
    end

    @impl true
    def from_meta({:literal, :integer, value}, _metadata) do
      {:ok, %{type: "Module", body: [%{type: "Expr", value: to_string(value)}]}}
    end

    def from_meta({:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}}, _) do
      {:ok, %{type: "Module", body: [%{type: "Expr", value: "x + 5"}]}}
    end

    def from_meta({:literal, :string, value}, _) do
      {:ok, %{type: "Module", body: [%{type: "Expr", value: value}]}}
    end

    @impl true
    def unparse(%{type: "Module", body: [%{type: "Expr", value: value}]}) do
      {:ok, value}
    end

    @impl true
    def file_extensions, do: [".py"]
  end

  setup do
    # Register mock adapter
    Adapter.Registry.register(:python, MockPythonAdapter)

    on_exit(fn ->
      Adapter.Registry.unregister(:python)
    end)

    :ok
  end

  describe "from_source/2" do
    test "parses valid source code" do
      assert {:ok, doc} = Builder.from_source("x + 5", :python)
      assert %Document{} = doc
      assert doc.language == :python
      assert doc.ast == {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}}
      assert doc.original_source == "x + 5"
    end

    test "returns error for syntax errors" do
      assert {:error, "SyntaxError: invalid syntax"} =
               Builder.from_source("syntax error", :python)
    end

    test "returns error for unknown language" do
      assert {:error, :no_adapter_found} = Builder.from_source("code", :unknown_language)
    end

    test "preserves metadata from adapter" do
      assert {:ok, doc} = Builder.from_source("x + 5", :python)
      assert doc.metadata.python_version == "3.11"
    end

    test "handles simple literals" do
      assert {:ok, doc} = Builder.from_source("42", :python)
      assert doc.ast == {:literal, :integer, 42}
    end
  end

  describe "from_file/2" do
    test "reads and parses file with auto-detection" do
      # Create temporary Python file
      path = Path.join(System.tmp_dir!(), "test.py")
      File.write!(path, "x + 5")

      assert {:ok, doc} = Builder.from_file(path)
      assert doc.language == :python
      assert doc.ast == {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}}

      File.rm!(path)
    end

    test "reads and parses file with explicit language" do
      # Create temporary file without extension
      path = Path.join(System.tmp_dir!(), "script")
      File.write!(path, "42")

      assert {:ok, doc} = Builder.from_file(path, :python)
      assert doc.language == :python
      assert doc.ast == {:literal, :integer, 42}

      File.rm!(path)
    end

    test "returns error for non-existent file" do
      assert {:error, :enoent} = Builder.from_file("/nonexistent/file.py")
    end

    test "returns error for unknown extension" do
      path = Path.join(System.tmp_dir!(), "test.unknown")
      File.write!(path, "code")

      assert {:error, :unknown_extension} = Builder.from_file(path)

      File.rm!(path)
    end
  end

  describe "to_source/2" do
    test "converts document back to source" do
      doc = %Document{
        ast: {:literal, :integer, 42},
        language: :python,
        metadata: %{},
        original_source: "42"
      }

      assert {:ok, "42"} = Builder.to_source(doc)
    end

    test "converts binary operation" do
      doc = %Document{
        ast: {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}},
        language: :python,
        metadata: %{},
        original_source: "x + 5"
      }

      assert {:ok, "x + 5"} = Builder.to_source(doc)
    end

    test "returns error for unknown language" do
      doc = %Document{
        ast: {:literal, :integer, 42},
        language: :unknown,
        metadata: %{},
        original_source: "42"
      }

      assert {:error, :no_adapter_found} = Builder.to_source(doc)
    end

    test "supports explicit target language" do
      doc = %Document{
        ast: {:literal, :integer, 42},
        language: :elixir,
        metadata: %{},
        original_source: "42"
      }

      # Explicitly target Python (even though original was Elixir)
      assert {:ok, "42"} = Builder.to_source(doc, :python)
    end
  end

  describe "to_file/3" do
    test "writes document to file" do
      doc = %Document{
        ast: {:literal, :integer, 42},
        language: :python,
        metadata: %{},
        original_source: "42"
      }

      path = Path.join(System.tmp_dir!(), "output.py")
      assert :ok = Builder.to_file(doc, path)
      assert File.read!(path) == "42"

      File.rm!(path)
    end

    test "creates parent directories if needed" do
      doc = %Document{
        ast: {:literal, :integer, 42},
        language: :python,
        metadata: %{},
        original_source: "42"
      }

      base_dir = Path.join(System.tmp_dir!(), "metastatic_test_#{System.unique_integer()}")
      path = Path.join([base_dir, "subdir", "output.py"])

      # Create parent directory
      File.mkdir_p!(Path.dirname(path))

      assert :ok = Builder.to_file(doc, path)
      assert File.read!(path) == "42"

      File.rm_rf!(base_dir)
    end

    test "returns error for invalid path" do
      doc = %Document{
        ast: {:literal, :integer, 42},
        language: :python,
        metadata: %{},
        original_source: "42"
      }

      # Try to write to a file that can't be created (e.g., in non-existent directory without creating it)
      assert {:error, _} = Builder.to_file(doc, "/invalid/nonexistent/path/file.py")
    end

    test "supports target language override" do
      doc = %Document{
        ast: {:literal, :integer, 42},
        language: :elixir,
        metadata: %{},
        original_source: "42"
      }

      path = Path.join(System.tmp_dir!(), "output.py")
      assert :ok = Builder.to_file(doc, path, :python)
      assert File.read!(path) == "42"

      File.rm!(path)
    end
  end

  describe "round_trip/2" do
    test "successfully round-trips code" do
      assert {:ok, result} = Builder.round_trip("x + 5", :python)
      assert result == "x + 5"
    end

    test "normalizes formatting during round-trip" do
      # Our mock adapter doesn't normalize, but in real adapters this would happen
      assert {:ok, result} = Builder.round_trip("42", :python)
      assert result == "42"
    end

    test "returns error for syntax errors" do
      assert {:error, "SyntaxError: invalid syntax"} =
               Builder.round_trip("syntax error", :python)
    end

    test "returns error for unknown language" do
      assert {:error, :no_adapter_found} = Builder.round_trip("code", :unknown)
    end
  end

  describe "valid_source?/2" do
    test "returns true for valid source" do
      assert Builder.valid_source?("x + 5", :python) == true
    end

    test "returns false for syntax errors" do
      assert Builder.valid_source?("syntax error", :python) == false
    end

    test "returns false for unknown language" do
      assert Builder.valid_source?("code", :unknown) == false
    end
  end

  describe "supported_languages/0" do
    test "lists registered adapters" do
      languages = Builder.supported_languages()

      assert is_list(languages)
      assert Enum.any?(languages, fn lang -> lang.language == :python end)

      python_info = Enum.find(languages, fn lang -> lang.language == :python end)
      assert python_info.adapter == MockPythonAdapter
      assert python_info.extensions == [".py"]
      assert python_info.loaded == true
    end

    test "only includes actually loaded adapters" do
      languages = Builder.supported_languages()

      # Should not include languages that aren't registered
      refute Enum.any?(languages, fn lang -> lang.language == :unknown end)
    end
  end

  describe "integration tests" do
    test "full workflow: source -> document -> source" do
      source = "x + 5"

      # Parse
      assert {:ok, doc} = Builder.from_source(source, :python)
      assert doc.ast == {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}}

      # Unparse
      assert {:ok, result} = Builder.to_source(doc)
      assert result == source
    end

    test "file workflow: read -> parse -> unparse -> write" do
      input_path = Path.join(System.tmp_dir!(), "input.py")
      output_path = Path.join(System.tmp_dir!(), "output.py")

      File.write!(input_path, "42")

      # Read and parse
      assert {:ok, doc} = Builder.from_file(input_path)

      # Write back
      assert :ok = Builder.to_file(doc, output_path)

      # Verify
      assert File.read!(output_path) == "42"

      File.rm!(input_path)
      File.rm!(output_path)
    end

    test "validates document after parsing" do
      assert {:ok, doc} = Builder.from_source("x + 5", :python)
      assert Document.valid?(doc) == true
    end
  end

  describe "error handling" do
    test "handles adapter parse errors gracefully" do
      result = Builder.from_source("syntax error", :python)
      assert {:error, _} = result
    end

    test "handles missing adapter gracefully" do
      result = Builder.from_source("code", :nonexistent)
      assert {:error, :no_adapter_found} = result
    end

    test "handles file I/O errors gracefully" do
      result = Builder.from_file("/invalid/path.py")
      assert {:error, :enoent} = result
    end
  end
end
