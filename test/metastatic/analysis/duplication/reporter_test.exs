defmodule Metastatic.Analysis.Duplication.ReporterTest do
  use ExUnit.Case, async: true

  alias Metastatic.Analysis.Duplication.{Reporter, Result}

  doctest Metastatic.Analysis.Duplication.Reporter

  describe "format/2 with :text format" do
    test "formats no duplicate" do
      result = Result.no_duplicate()
      output = Reporter.format(result, :text)

      assert output == "No duplicate detected"
    end

    test "formats Type I clone" do
      result = Result.exact_clone()
      output = Reporter.format(result, :text)

      assert String.contains?(output, "Type I")
      assert String.contains?(output, "Duplicate detected")
    end

    test "formats Type II clone" do
      result = Result.renamed_clone()
      output = Reporter.format(result, :text)

      assert String.contains?(output, "Type II")
      assert String.contains?(output, "Duplicate detected")
    end

    test "formats Type III clone with similarity score" do
      result = Result.near_miss_clone(0.85)
      output = Reporter.format(result, :text)

      assert String.contains?(output, "Type III")
      assert String.contains?(output, "0.85")
    end
  end

  describe "format/2 with :json format" do
    test "formats no duplicate as JSON" do
      result = Result.no_duplicate()
      output = Reporter.format(result, :json)

      assert {:ok, data} = Jason.decode(output)
      assert data["duplicate"] == false
    end

    test "formats Type I clone as JSON" do
      result = Result.exact_clone()
      output = Reporter.format(result, :json)

      assert {:ok, data} = Jason.decode(output)
      assert data["duplicate"] == true
      assert data["clone_type"] == "type_i"
    end

    test "formats Type III clone with similarity as JSON" do
      result = Result.near_miss_clone(0.85)
      output = Reporter.format(result, :json)

      assert {:ok, data} = Jason.decode(output)
      assert data["duplicate"] == true
      assert data["clone_type"] == "type_iii"
      assert data["similarity_score"] == 0.85
    end
  end

  describe "format/2 with :detailed format" do
    test "formats no duplicate" do
      result = Result.no_duplicate()
      output = Reporter.format(result, :detailed)

      assert output == "No duplicate detected"
    end

    test "formats Type I clone with all details" do
      result = Result.exact_clone()
      output = Reporter.format(result, :detailed)

      assert String.contains?(output, "Duplicate Detection Result")
      assert String.contains?(output, "=")
      assert String.contains?(output, "Clone Type: Type I")
      assert String.contains?(output, "Locations:")
      assert String.contains?(output, "Fingerprints:")
      assert String.contains?(output, "Metrics:")
    end

    test "includes location information when available" do
      result =
        Result.exact_clone()
        |> Result.with_locations([
          %{file: "foo.ex", start_line: 10, end_line: 15, language: :elixir},
          %{file: "bar.py", start_line: 20, end_line: 25, language: :python}
        ])

      output = Reporter.format(result, :detailed)

      assert String.contains?(output, "foo.ex")
      assert String.contains?(output, "bar.py")
      assert String.contains?(output, "10-15")
      assert String.contains?(output, "20-25")
    end
  end

  describe "format_groups/2 with :text format" do
    test "formats empty groups" do
      output = Reporter.format_groups([], :text)
      assert output == "No clone groups found"
    end

    test "formats single group" do
      groups = [
        %{
          size: 2,
          clone_type: :type_i,
          locations: [
            %{file: "foo.ex", start_line: 10, end_line: 15, language: :elixir},
            %{file: "bar.py", start_line: 20, end_line: 25, language: :python}
          ]
        }
      ]

      output = Reporter.format_groups(groups, :text)

      assert String.contains?(output, "Found 1 clone group")
      assert String.contains?(output, "Clone Group 1")
      assert String.contains?(output, "Type I")
      assert String.contains?(output, "Size: 2 documents")
      assert String.contains?(output, "foo.ex")
      assert String.contains?(output, "bar.py")
    end

    test "formats multiple groups" do
      groups = [
        %{
          size: 2,
          clone_type: :type_i,
          locations: [
            %{file: "a.ex", start_line: 1, end_line: 5, language: :elixir},
            %{file: "b.ex", start_line: 10, end_line: 15, language: :elixir}
          ]
        },
        %{
          size: 3,
          clone_type: :type_ii,
          locations: [
            %{file: "c.py", start_line: 1, end_line: 10, language: :python},
            %{file: "d.py", start_line: 20, end_line: 30, language: :python},
            %{file: "e.rb", start_line: 5, end_line: 15, language: :ruby}
          ]
        }
      ]

      output = Reporter.format_groups(groups, :text)

      assert String.contains?(output, "Found 2 clone group")
      assert String.contains?(output, "Clone Group 1")
      assert String.contains?(output, "Clone Group 2")
      assert String.contains?(output, "a.ex")
      assert String.contains?(output, "c.py")
      assert String.contains?(output, "d.py")
      assert String.contains?(output, "e.rb")
    end
  end

  describe "format_groups/2 with :json format" do
    test "formats empty groups as JSON" do
      output = Reporter.format_groups([], :json)

      assert {:ok, data} = Jason.decode(output)
      assert data["total_groups"] == 0
      assert data["total_clones"] == 0
      assert data["clone_groups"] == []
    end

    test "formats single group as JSON" do
      groups = [
        %{
          size: 2,
          clone_type: :type_i,
          locations: [
            %{file: "foo.ex", start_line: 10, end_line: 15, language: :elixir}
          ]
        }
      ]

      output = Reporter.format_groups(groups, :json)

      assert {:ok, data} = Jason.decode(output)
      assert data["total_groups"] == 1
      assert data["total_clones"] == 2
      assert length(data["clone_groups"]) == 1
    end

    test "formats multiple groups as JSON" do
      groups = [
        %{size: 2, clone_type: :type_i, locations: []},
        %{size: 3, clone_type: :type_ii, locations: []}
      ]

      output = Reporter.format_groups(groups, :json)

      assert {:ok, data} = Jason.decode(output)
      assert data["total_groups"] == 2
      assert data["total_clones"] == 5
      assert length(data["clone_groups"]) == 2
    end
  end

  describe "format_groups/2 with :detailed format" do
    test "formats empty groups" do
      output = Reporter.format_groups([], :detailed)
      assert output == "No clone groups found"
    end

    test "formats single group with details" do
      groups = [
        %{
          size: 2,
          clone_type: :type_i,
          locations: [
            %{file: "foo.ex", start_line: 10, end_line: 15, language: :elixir},
            %{file: "bar.py", start_line: 20, end_line: 25, language: :python}
          ]
        }
      ]

      output = Reporter.format_groups(groups, :detailed)

      assert String.contains?(output, "Clone Group Analysis")
      assert String.contains?(output, "Total Groups: 1")
      assert String.contains?(output, "Total Clones: 2")
      assert String.contains?(output, "Clone Group 1")
      assert String.contains?(output, "foo.ex:10-15")
      assert String.contains?(output, "bar.py:20-25")
    end

    test "formats multiple groups with details" do
      groups = [
        %{
          size: 2,
          clone_type: :type_i,
          locations: [
            %{file: "a.ex", start_line: 1, end_line: 5, language: :elixir}
          ]
        },
        %{
          size: 3,
          clone_type: :type_ii,
          locations: [
            %{file: "b.py", start_line: 10, end_line: 20, language: :python}
          ]
        }
      ]

      output = Reporter.format_groups(groups, :detailed)

      assert String.contains?(output, "Total Groups: 2")
      assert String.contains?(output, "Total Clones: 5")
      assert String.contains?(output, "Clone Group 1")
      assert String.contains?(output, "Clone Group 2")
    end
  end

  describe "format/2 with default format" do
    test "defaults to :text format" do
      result = Result.exact_clone()
      output_default = Reporter.format(result)
      output_text = Reporter.format(result, :text)

      assert output_default == output_text
    end
  end

  describe "format_groups/2 with default format" do
    test "defaults to :text format" do
      groups = [%{size: 2, clone_type: :type_i, locations: []}]
      output_default = Reporter.format_groups(groups)
      output_text = Reporter.format_groups(groups, :text)

      assert output_default == output_text
    end
  end
end
