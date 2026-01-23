defmodule Metastatic.Analysis.DuplicationTest do
  use ExUnit.Case, async: true

  alias Metastatic.{Analysis.Duplication, Document}

  doctest Metastatic.Analysis.Duplication

  describe "detect/2 - Type I exact clones" do
    test "detects identical literals" do
      ast = {:literal, :integer, 42}
      doc1 = Document.new(ast, :elixir)
      doc2 = Document.new(ast, :python)

      {:ok, result} = Duplication.detect(doc1, doc2)

      assert result.duplicate?
      assert result.clone_type == :type_i
      assert result.similarity_score == 1.0
    end

    test "detects identical variables" do
      ast = {:variable, "x"}
      doc1 = Document.new(ast, :elixir)
      doc2 = Document.new(ast, :elixir)

      {:ok, result} = Duplication.detect(doc1, doc2)

      assert result.duplicate?
      assert result.clone_type == :type_i
    end

    test "detects identical binary operations" do
      ast = {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}}
      doc1 = Document.new(ast, :elixir)
      doc2 = Document.new(ast, :python)

      {:ok, result} = Duplication.detect(doc1, doc2)

      assert result.duplicate?
      assert result.clone_type == :type_i
      assert result.similarity_score == 1.0
    end

    test "detects identical complex expressions" do
      ast =
        {:binary_op, :arithmetic, :+,
         {:binary_op, :arithmetic, :*, {:variable, "x"}, {:literal, :integer, 2}},
         {:literal, :integer, 5}}

      doc1 = Document.new(ast, :elixir)
      doc2 = Document.new(ast, :elixir)

      {:ok, result} = Duplication.detect(doc1, doc2)

      assert result.duplicate?
      assert result.clone_type == :type_i
    end

    test "detects identical conditionals" do
      ast =
        {:conditional, {:variable, "x"}, {:literal, :integer, 1}, {:literal, :integer, 2}}

      doc1 = Document.new(ast, :elixir)
      doc2 = Document.new(ast, :python)

      {:ok, result} = Duplication.detect(doc1, doc2)

      assert result.duplicate?
      assert result.clone_type == :type_i
    end

    test "detects identical function calls" do
      ast = {:function_call, "print", [{:literal, :string, "hello"}]}
      doc1 = Document.new(ast, :python)
      doc2 = Document.new(ast, :elixir)

      {:ok, result} = Duplication.detect(doc1, doc2)

      assert result.duplicate?
      assert result.clone_type == :type_i
    end

    test "detects identical blocks" do
      ast =
        {:block,
         [
           {:assignment, {:variable, "x"}, {:literal, :integer, 5}},
           {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 1}}
         ]}

      doc1 = Document.new(ast, :elixir)
      doc2 = Document.new(ast, :elixir)

      {:ok, result} = Duplication.detect(doc1, doc2)

      assert result.duplicate?
      assert result.clone_type == :type_i
    end
  end

  describe "detect/2 - non-duplicates" do
    test "different literal types are not duplicates" do
      ast1 = {:literal, :integer, 42}
      ast2 = {:literal, :string, "42"}
      doc1 = Document.new(ast1, :elixir)
      doc2 = Document.new(ast2, :elixir)

      {:ok, result} = Duplication.detect(doc1, doc2)

      refute result.duplicate?
      assert result.clone_type == nil
      assert result.similarity_score == 0.0
    end

    test "different operations are not duplicates" do
      ast1 = {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}}
      ast2 = {:binary_op, :arithmetic, :-, {:variable, "x"}, {:literal, :integer, 5}}
      doc1 = Document.new(ast1, :elixir)
      doc2 = Document.new(ast2, :elixir)

      {:ok, result} = Duplication.detect(doc1, doc2)

      refute result.duplicate?
    end

    test "different types are not duplicates" do
      ast1 = {:literal, :integer, 42}
      ast2 = {:variable, "x"}
      doc1 = Document.new(ast1, :elixir)
      doc2 = Document.new(ast2, :elixir)

      {:ok, result} = Duplication.detect(doc1, doc2)

      refute result.duplicate?
    end
  end

  describe "detect/2 - result metadata" do
    test "includes locations from both documents" do
      ast = {:literal, :integer, 42}

      doc1 =
        Document.new(
          ast,
          :elixir,
          %{file: "file1.ex", start_line: 10, end_line: 10}
        )

      doc2 =
        Document.new(
          ast,
          :python,
          %{file: "file2.py", start_line: 20, end_line: 20}
        )

      {:ok, result} = Duplication.detect(doc1, doc2)

      assert [_, _] = result.locations
      assert Enum.any?(result.locations, &(&1.file == "file1.ex"))
      assert Enum.any?(result.locations, &(&1.file == "file2.py"))
    end

    test "includes exact fingerprint" do
      ast = {:literal, :integer, 42}
      doc1 = Document.new(ast, :elixir)
      doc2 = Document.new(ast, :python)

      {:ok, result} = Duplication.detect(doc1, doc2)

      assert result.fingerprints.exact != nil
      assert is_binary(result.fingerprints.exact)
    end

    test "includes metrics" do
      ast = {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}}
      doc1 = Document.new(ast, :elixir)
      doc2 = Document.new(ast, :elixir)

      {:ok, result} = Duplication.detect(doc1, doc2)

      assert result.metrics != nil
      assert result.metrics.size > 0
      assert result.metrics.variables == 1
    end

    test "counts variables correctly" do
      ast =
        {:binary_op, :arithmetic, :+, {:variable, "x"},
         {:binary_op, :arithmetic, :*, {:variable, "y"}, {:literal, :integer, 2}}}

      doc1 = Document.new(ast, :elixir)
      doc2 = Document.new(ast, :elixir)

      {:ok, result} = Duplication.detect(doc1, doc2)

      assert result.metrics.variables == 2
    end
  end

  describe "detect!/2" do
    test "returns result directly" do
      ast = {:literal, :integer, 42}
      doc1 = Document.new(ast, :elixir)
      doc2 = Document.new(ast, :elixir)

      result = Duplication.detect!(doc1, doc2)

      assert result.duplicate?
      assert result.clone_type == :type_i
    end
  end

  describe "similarity/2" do
    test "returns 1.0 for identical ASTs" do
      ast1 = {:literal, :integer, 42}
      ast2 = {:literal, :integer, 42}

      assert Duplication.similarity(ast1, ast2) == 1.0
    end

    test "returns low score for different AST types" do
      ast1 = {:literal, :integer, 42}
      ast2 = {:literal, :string, "hello"}

      score = Duplication.similarity(ast1, ast2)
      assert score > 0.0 and score < 0.5
    end

    test "returns 1.0 for complex identical ASTs" do
      ast = {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}}

      assert Duplication.similarity(ast, ast) == 1.0
    end
  end

  describe "fingerprint/1" do
    test "generates non-empty fingerprint" do
      ast = {:literal, :integer, 42}
      fingerprint = Duplication.fingerprint(ast)

      assert is_binary(fingerprint)
      assert String.length(fingerprint) > 0
    end

    test "identical ASTs produce identical fingerprints" do
      ast = {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}}
      fp1 = Duplication.fingerprint(ast)
      fp2 = Duplication.fingerprint(ast)

      assert fp1 == fp2
    end

    test "different ASTs produce different fingerprints" do
      ast1 = {:literal, :integer, 42}
      ast2 = {:literal, :integer, 43}
      fp1 = Duplication.fingerprint(ast1)
      fp2 = Duplication.fingerprint(ast2)

      assert fp1 != fp2
    end

    test "produces consistent fingerprints" do
      ast = {:conditional, {:variable, "x"}, {:literal, :integer, 1}, {:literal, :integer, 2}}
      fingerprints = Enum.map(1..10, fn _ -> Duplication.fingerprint(ast) end)

      assert Enum.uniq(fingerprints) |> length() == 1
    end
  end

  describe "cross-language detection" do
    test "detects clones across Python and Elixir" do
      # Same AST, different languages
      ast = {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}}
      doc1 = Document.new(ast, :python)
      doc2 = Document.new(ast, :elixir)

      {:ok, result} = Duplication.detect(doc1, doc2)

      assert result.duplicate?
      assert result.clone_type == :type_i
    end

    test "location includes language information" do
      ast = {:literal, :integer, 42}
      doc1 = Document.new(ast, :python)
      doc2 = Document.new(ast, :elixir)

      {:ok, result} = Duplication.detect(doc1, doc2)

      assert Enum.any?(result.locations, &(&1.language == :python))
      assert Enum.any?(result.locations, &(&1.language == :elixir))
    end
  end

  describe "detect/2 - Type II renamed clones" do
    test "detects renamed variables as Type II" do
      ast1 = {:variable, "x"}
      ast2 = {:variable, "y"}
      doc1 = Document.new(ast1, :elixir)
      doc2 = Document.new(ast2, :elixir)

      {:ok, result} = Duplication.detect(doc1, doc2)

      assert result.duplicate?
      assert result.clone_type == :type_ii
      assert result.similarity_score == 1.0
    end

    test "detects different literal values as Type II" do
      ast1 = {:literal, :integer, 42}
      ast2 = {:literal, :integer, 100}
      doc1 = Document.new(ast1, :elixir)
      doc2 = Document.new(ast2, :elixir)

      {:ok, result} = Duplication.detect(doc1, doc2)

      assert result.duplicate?
      assert result.clone_type == :type_ii
    end

    test "detects renamed binary operations as Type II" do
      ast1 = {:binary_op, :arithmetic, :+, {:variable, "a"}, {:literal, :integer, 1}}
      ast2 = {:binary_op, :arithmetic, :+, {:variable, "b"}, {:literal, :integer, 2}}
      doc1 = Document.new(ast1, :elixir)
      doc2 = Document.new(ast2, :python)

      {:ok, result} = Duplication.detect(doc1, doc2)

      assert result.duplicate?
      assert result.clone_type == :type_ii
    end

    test "detects renamed function calls as Type II" do
      ast1 = {:function_call, "foo", [{:variable, "x"}]}
      ast2 = {:function_call, "bar", [{:variable, "y"}]}
      doc1 = Document.new(ast1, :elixir)
      doc2 = Document.new(ast2, :elixir)

      {:ok, result} = Duplication.detect(doc1, doc2)

      assert result.duplicate?
      assert result.clone_type == :type_ii
    end

    test "detects renamed conditionals as Type II" do
      ast1 = {:conditional, {:variable, "x"}, {:literal, :integer, 1}, {:literal, :integer, 2}}
      ast2 = {:conditional, {:variable, "y"}, {:literal, :integer, 10}, {:literal, :integer, 20}}
      doc1 = Document.new(ast1, :elixir)
      doc2 = Document.new(ast2, :elixir)

      {:ok, result} = Duplication.detect(doc1, doc2)

      assert result.duplicate?
      assert result.clone_type == :type_ii
    end

    test "detects complex renamed expressions as Type II" do
      # Function implementation with different variable names
      ast1 =
        {:block,
         [
           {:assignment, {:variable, "result"},
            {:binary_op, :arithmetic, :+, {:variable, "a"}, {:variable, "b"}}},
           {:early_return, {:variable, "result"}}
         ]}

      ast2 =
        {:block,
         [
           {:assignment, {:variable, "sum"},
            {:binary_op, :arithmetic, :+, {:variable, "x"}, {:variable, "y"}}},
           {:early_return, {:variable, "sum"}}
         ]}

      doc1 = Document.new(ast1, :python)
      doc2 = Document.new(ast2, :elixir)

      {:ok, result} = Duplication.detect(doc1, doc2)

      assert result.duplicate?
      assert result.clone_type == :type_ii
    end

    test "Type II includes normalized fingerprint" do
      ast1 = {:variable, "x"}
      ast2 = {:variable, "y"}
      doc1 = Document.new(ast1, :elixir)
      doc2 = Document.new(ast2, :elixir)

      {:ok, result} = Duplication.detect(doc1, doc2)

      assert result.fingerprints.normalized != nil
      assert is_binary(result.fingerprints.normalized)
    end

    test "different operators are not Type II clones" do
      ast1 = {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}}
      ast2 = {:binary_op, :arithmetic, :-, {:variable, "x"}, {:literal, :integer, 5}}
      doc1 = Document.new(ast1, :elixir)
      doc2 = Document.new(ast2, :elixir)

      {:ok, result} = Duplication.detect(doc1, doc2)

      refute result.duplicate?
    end

    test "different literal types are not Type II clones" do
      ast1 = {:literal, :integer, 42}
      ast2 = {:literal, :string, "42"}
      doc1 = Document.new(ast1, :elixir)
      doc2 = Document.new(ast2, :elixir)

      {:ok, result} = Duplication.detect(doc1, doc2)

      refute result.duplicate?
    end
  end

  describe "edge cases" do
    test "handles wildcard patterns" do
      ast1 = {:variable, "_"}
      ast2 = {:variable, "_"}
      doc1 = Document.new(ast1, :elixir)
      doc2 = Document.new(ast2, :elixir)

      {:ok, result} = Duplication.detect(doc1, doc2)

      # Wildcards are treated as regular variables for exact matching
      assert result.duplicate?
    end

    test "handles empty blocks" do
      ast1 = {:block, []}
      ast2 = {:block, []}
      doc1 = Document.new(ast1, :elixir)
      doc2 = Document.new(ast2, :elixir)

      {:ok, result} = Duplication.detect(doc1, doc2)

      assert result.duplicate?
    end

    test "handles nil else branches" do
      ast1 = {:conditional, {:variable, "x"}, {:literal, :integer, 1}, nil}
      ast2 = {:conditional, {:variable, "x"}, {:literal, :integer, 1}, nil}
      doc1 = Document.new(ast1, :elixir)
      doc2 = Document.new(ast2, :elixir)

      {:ok, result} = Duplication.detect(doc1, doc2)

      assert result.duplicate?
    end

    test "conditional with else branch differs from without" do
      ast1 = {:conditional, {:variable, "x"}, {:literal, :integer, 1}, nil}
      ast2 = {:conditional, {:variable, "x"}, {:literal, :integer, 1}, {:literal, :integer, 2}}
      doc1 = Document.new(ast1, :elixir)
      doc2 = Document.new(ast2, :elixir)

      {:ok, result} = Duplication.detect(doc1, doc2)

      # These are similar enough to be Type III clones with default threshold
      # but have different structure (nil vs present else branch)
      assert result.duplicate?
      assert result.clone_type == :type_iii
    end
  end
end
