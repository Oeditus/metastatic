defmodule Metastatic.Analysis.Duplication.ResultTest do
  use ExUnit.Case, async: true

  alias Metastatic.Analysis.Duplication.Result

  doctest Metastatic.Analysis.Duplication.Result

  describe "no_duplicate/0" do
    test "creates result with duplicate? false" do
      result = Result.no_duplicate()
      refute result.duplicate?
    end

    test "has zero similarity score" do
      result = Result.no_duplicate()
      assert result.similarity_score == 0.0
    end

    test "has nil clone_type" do
      result = Result.no_duplicate()
      assert result.clone_type == nil
    end

    test "has appropriate summary" do
      result = Result.no_duplicate()
      assert result.summary == "No duplication detected"
    end
  end

  describe "exact_clone/0" do
    test "creates result with duplicate? true" do
      result = Result.exact_clone()
      assert result.duplicate?
    end

    test "has similarity score of 1.0" do
      result = Result.exact_clone()
      assert result.similarity_score == 1.0
    end

    test "has clone_type :type_i" do
      result = Result.exact_clone()
      assert result.clone_type == :type_i
    end

    test "has appropriate summary" do
      result = Result.exact_clone()
      assert result.summary == "Exact clone detected (Type I)"
    end
  end

  describe "renamed_clone/0" do
    test "creates result with duplicate? true" do
      result = Result.renamed_clone()
      assert result.duplicate?
    end

    test "has similarity score of 1.0" do
      result = Result.renamed_clone()
      assert result.similarity_score == 1.0
    end

    test "has clone_type :type_ii" do
      result = Result.renamed_clone()
      assert result.clone_type == :type_ii
    end

    test "has appropriate summary" do
      result = Result.renamed_clone()
      assert result.summary == "Renamed clone detected (Type II)"
    end
  end

  describe "near_miss_clone/1" do
    test "creates result with duplicate? true" do
      result = Result.near_miss_clone(0.85)
      assert result.duplicate?
    end

    test "has specified similarity score" do
      result = Result.near_miss_clone(0.75)
      assert result.similarity_score == 0.75
    end

    test "has clone_type :type_iii" do
      result = Result.near_miss_clone(0.9)
      assert result.clone_type == :type_iii
    end

    test "has summary with percentage" do
      result = Result.near_miss_clone(0.85)
      assert result.summary =~ "85.0%"
    end
  end

  describe "semantic_clone/1" do
    test "creates result with duplicate? true" do
      result = Result.semantic_clone(0.9)
      assert result.duplicate?
    end

    test "has specified similarity score" do
      result = Result.semantic_clone(0.8)
      assert result.similarity_score == 0.8
    end

    test "has clone_type :type_iv" do
      result = Result.semantic_clone(0.95)
      assert result.clone_type == :type_iv
    end

    test "has summary with percentage" do
      result = Result.semantic_clone(0.9)
      assert result.summary =~ "90.0%"
    end
  end

  describe "with_location/2" do
    test "adds location to result" do
      result = Result.exact_clone()
      location = %{file: "test.ex", start_line: 10, end_line: 20, language: :elixir}

      updated = Result.with_location(result, location)
      assert [^location] = updated.locations
    end

    test "prepends to existing locations" do
      result = Result.exact_clone()
      loc1 = %{file: "test1.ex", start_line: 10, end_line: 20, language: :elixir}
      loc2 = %{file: "test2.ex", start_line: 30, end_line: 40, language: :elixir}

      updated =
        result
        |> Result.with_location(loc1)
        |> Result.with_location(loc2)

      assert [^loc2, ^loc1] = updated.locations
    end
  end

  describe "with_locations/2" do
    test "adds multiple locations at once" do
      result = Result.exact_clone()

      locations = [
        %{file: "test1.ex", start_line: 10, end_line: 20, language: :elixir},
        %{file: "test2.ex", start_line: 30, end_line: 40, language: :elixir}
      ]

      updated = Result.with_locations(result, locations)
      assert length(updated.locations) == 2
    end
  end

  describe "with_fingerprints/2" do
    test "adds fingerprints to result" do
      result = Result.exact_clone()
      fingerprints = %{exact: "abc123", normalized: "def456"}

      updated = Result.with_fingerprints(result, fingerprints)
      assert updated.fingerprints.exact == "abc123"
      assert updated.fingerprints.normalized == "def456"
    end

    test "merges with existing fingerprints" do
      result = Result.exact_clone()

      updated =
        result
        |> Result.with_fingerprints(%{exact: "abc"})
        |> Result.with_fingerprints(%{normalized: "def"})

      assert updated.fingerprints.exact == "abc"
      assert updated.fingerprints.normalized == "def"
    end
  end

  describe "with_metrics/2" do
    test "adds metrics to result" do
      result = Result.exact_clone()
      metrics = %{size: 100, complexity: 5, variables: 3}

      updated = Result.with_metrics(result, metrics)
      assert updated.metrics.size == 100
      assert updated.metrics.complexity == 5
      assert updated.metrics.variables == 3
    end
  end

  describe "with_difference/2" do
    test "adds difference to result" do
      result = Result.near_miss_clone(0.85)
      diff = %{type: :statement_added, description: "Extra return"}

      updated = Result.with_difference(result, diff)
      assert [^diff] = updated.differences
    end

    test "prepends to existing differences" do
      result = Result.near_miss_clone(0.85)
      diff1 = %{type: :statement_added, description: "Extra return"}
      diff2 = %{type: :variable_renamed, description: "x renamed to y"}

      updated =
        result
        |> Result.with_difference(diff1)
        |> Result.with_difference(diff2)

      assert [^diff2, ^diff1] = updated.differences
    end
  end

  describe "with_differences/2" do
    test "adds multiple differences at once" do
      result = Result.near_miss_clone(0.85)

      diffs = [
        %{type: :statement_added, description: "Extra return"},
        %{type: :variable_renamed, description: "x renamed to y"}
      ]

      updated = Result.with_differences(result, diffs)
      assert length(updated.differences) == 2
    end
  end

  describe "with_summary/2" do
    test "updates the summary" do
      result = Result.exact_clone()
      updated = Result.with_summary(result, "Custom summary")

      assert updated.summary == "Custom summary"
    end
  end
end
