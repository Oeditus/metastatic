defmodule Metastatic.Analysis.Duplication.FingerprintTest do
  use ExUnit.Case, async: true

  alias Metastatic.Analysis.Duplication.Fingerprint

  doctest Metastatic.Analysis.Duplication.Fingerprint

  describe "exact/1" do
    test "generates non-empty fingerprint" do
      ast = {:literal, :integer, 42}
      fp = Fingerprint.exact(ast)

      assert is_binary(fp)
      assert String.length(fp) > 0
    end

    test "identical ASTs produce identical fingerprints" do
      ast = {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}}
      fp1 = Fingerprint.exact(ast)
      fp2 = Fingerprint.exact(ast)

      assert fp1 == fp2
    end

    test "different ASTs produce different fingerprints" do
      ast1 = {:literal, :integer, 42}
      ast2 = {:literal, :integer, 43}
      fp1 = Fingerprint.exact(ast1)
      fp2 = Fingerprint.exact(ast2)

      assert fp1 != fp2
    end

    test "different variable names produce different fingerprints" do
      ast1 = {:variable, "x"}
      ast2 = {:variable, "y"}
      fp1 = Fingerprint.exact(ast1)
      fp2 = Fingerprint.exact(ast2)

      assert fp1 != fp2
    end

    test "different literal values produce different fingerprints" do
      ast1 = {:literal, :string, "hello"}
      ast2 = {:literal, :string, "world"}
      fp1 = Fingerprint.exact(ast1)
      fp2 = Fingerprint.exact(ast2)

      assert fp1 != fp2
    end

    test "produces consistent results" do
      ast = {:conditional, {:variable, "x"}, {:literal, :integer, 1}, {:literal, :integer, 2}}
      fingerprints = Enum.map(1..10, fn _ -> Fingerprint.exact(ast) end)

      assert [_] = Enum.uniq(fingerprints)
    end
  end

  describe "normalized/1" do
    test "generates non-empty fingerprint" do
      ast = {:literal, :integer, 42}
      fp = Fingerprint.normalized(ast)

      assert is_binary(fp)
      assert String.length(fp) > 0
    end

    test "identical ASTs produce identical normalized fingerprints" do
      ast = {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}}
      fp1 = Fingerprint.normalized(ast)
      fp2 = Fingerprint.normalized(ast)

      assert fp1 == fp2
    end

    test "different variable names produce same normalized fingerprint" do
      ast1 = {:variable, "x"}
      ast2 = {:variable, "y"}
      fp1 = Fingerprint.normalized(ast1)
      fp2 = Fingerprint.normalized(ast2)

      assert fp1 == fp2
    end

    test "different literal values produce same normalized fingerprint" do
      ast1 = {:literal, :integer, 42}
      ast2 = {:literal, :integer, 100}
      fp1 = Fingerprint.normalized(ast1)
      fp2 = Fingerprint.normalized(ast2)

      assert fp1 == fp2
    end

    test "different literal types produce different normalized fingerprints" do
      ast1 = {:literal, :integer, 42}
      ast2 = {:literal, :string, "42"}
      fp1 = Fingerprint.normalized(ast1)
      fp2 = Fingerprint.normalized(ast2)

      assert fp1 != fp2
    end

    test "binary operations with different variables produce same normalized fingerprint" do
      ast1 = {:binary_op, :arithmetic, :+, {:variable, "a"}, {:literal, :integer, 1}}
      ast2 = {:binary_op, :arithmetic, :+, {:variable, "b"}, {:literal, :integer, 2}}
      fp1 = Fingerprint.normalized(ast1)
      fp2 = Fingerprint.normalized(ast2)

      assert fp1 == fp2
    end

    test "binary operations with different operators produce different normalized fingerprints" do
      ast1 = {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}}
      ast2 = {:binary_op, :arithmetic, :-, {:variable, "x"}, {:literal, :integer, 5}}
      fp1 = Fingerprint.normalized(ast1)
      fp2 = Fingerprint.normalized(ast2)

      assert fp1 != fp2
    end

    test "function calls with different names produce same normalized fingerprint" do
      ast1 = {:function_call, "foo", [{:variable, "x"}]}
      ast2 = {:function_call, "bar", [{:variable, "y"}]}
      fp1 = Fingerprint.normalized(ast1)
      fp2 = Fingerprint.normalized(ast2)

      assert fp1 == fp2
    end

    test "conditionals with different values produce same normalized fingerprint" do
      ast1 = {:conditional, {:variable, "x"}, {:literal, :integer, 1}, {:literal, :integer, 2}}
      ast2 = {:conditional, {:variable, "y"}, {:literal, :integer, 10}, {:literal, :integer, 20}}
      fp1 = Fingerprint.normalized(ast1)
      fp2 = Fingerprint.normalized(ast2)

      assert fp1 == fp2
    end

    test "blocks with different statement values produce same normalized fingerprint" do
      ast1 =
        {:block, [{:assignment, {:variable, "x"}, {:literal, :integer, 5}}, {:variable, "x"}]}

      ast2 =
        {:block, [{:assignment, {:variable, "y"}, {:literal, :integer, 10}}, {:variable, "y"}]}

      fp1 = Fingerprint.normalized(ast1)
      fp2 = Fingerprint.normalized(ast2)

      assert fp1 == fp2
    end

    test "loops with different iterator names produce same normalized fingerprint" do
      ast1 = {:loop, :for, {:variable, "i"}, {:variable, "list"}, {:variable, "i"}}
      ast2 = {:loop, :for, {:variable, "j"}, {:variable, "items"}, {:variable, "j"}}
      fp1 = Fingerprint.normalized(ast1)
      fp2 = Fingerprint.normalized(ast2)

      assert fp1 == fp2
    end
  end

  describe "tokens/1" do
    test "extracts tokens from literal" do
      ast = {:literal, :integer, 42}
      tokens = Fingerprint.tokens(ast)

      assert :literal in tokens
      assert :integer in tokens
    end

    test "extracts tokens from variable" do
      ast = {:variable, "x"}
      tokens = Fingerprint.tokens(ast)

      assert :variable in tokens
    end

    test "extracts tokens from binary operation" do
      ast = {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}}
      tokens = Fingerprint.tokens(ast)

      assert :binary_op in tokens
      assert :arithmetic in tokens
      assert :+ in tokens
      assert :variable in tokens
      assert :literal in tokens
      assert :integer in tokens
    end

    test "extracts tokens from function call" do
      ast = {:function_call, "print", [{:literal, :string, "hello"}]}
      tokens = Fingerprint.tokens(ast)

      assert :function_call in tokens
      assert :literal in tokens
      assert :string in tokens
    end

    test "extracts tokens from conditional" do
      ast = {:conditional, {:variable, "x"}, {:literal, :integer, 1}, {:literal, :integer, 2}}
      tokens = Fingerprint.tokens(ast)

      assert :conditional in tokens
      assert :variable in tokens
      assert :literal in tokens
    end

    test "extracts tokens from block" do
      ast = {:block, [{:variable, "x"}, {:variable, "y"}]}
      tokens = Fingerprint.tokens(ast)

      assert :block in tokens
      assert :variable in tokens
    end

    test "extracts tokens from loop" do
      ast = {:loop, :while, {:variable, "x"}, {:variable, "y"}}
      tokens = Fingerprint.tokens(ast)

      assert :loop in tokens
      assert :while in tokens
      assert :variable in tokens
    end

    test "extracts tokens from lambda" do
      ast = {:lambda, ["x"], [], {:variable, "x"}}
      tokens = Fingerprint.tokens(ast)

      assert :lambda in tokens
      assert :variable in tokens
    end

    test "extracts tokens from collection operation" do
      ast = {:collection_op, :map, {:lambda, [], [], {:variable, "x"}}, {:variable, "list"}}
      tokens = Fingerprint.tokens(ast)

      assert :collection_op in tokens
      assert :map in tokens
      assert :lambda in tokens
    end

    test "tokens list maintains structure" do
      ast = {:binary_op, :arithmetic, :+, {:variable, "x"}, {:variable, "y"}}
      tokens = Fingerprint.tokens(ast)

      # Tokens should be in order
      assert is_list(tokens)
      assert length(tokens) > 0
    end
  end

  describe "match?/2" do
    test "returns true for identical fingerprints" do
      fp1 = "ABC123"
      fp2 = "ABC123"

      assert Fingerprint.match?(fp1, fp2)
    end

    test "returns false for different fingerprints" do
      fp1 = "ABC123"
      fp2 = "DEF456"

      refute Fingerprint.match?(fp1, fp2)
    end

    test "works with real fingerprints" do
      ast = {:literal, :integer, 42}
      fp1 = Fingerprint.exact(ast)
      fp2 = Fingerprint.exact(ast)

      assert Fingerprint.match?(fp1, fp2)
    end
  end

  describe "edge cases" do
    test "handles wildcard variable" do
      ast = {:variable, "_"}
      fp = Fingerprint.exact(ast)

      assert is_binary(fp)
    end

    test "handles empty block" do
      ast = {:block, []}
      fp = Fingerprint.normalized(ast)

      assert is_binary(fp)
    end

    test "handles nil else branch" do
      ast = {:conditional, {:variable, "x"}, {:literal, :integer, 1}, nil}
      fp = Fingerprint.normalized(ast)

      assert is_binary(fp)
    end

    test "normalized fingerprint ignores nil vs present else branch structure" do
      ast1 = {:conditional, {:variable, "x"}, {:literal, :integer, 1}, nil}

      ast2 =
        {:conditional, {:variable, "x"}, {:literal, :integer, 1}, {:literal, :integer, 2}}

      fp1 = Fingerprint.normalized(ast1)
      fp2 = Fingerprint.normalized(ast2)

      # These should be different since structure differs (nil vs present)
      assert fp1 != fp2
    end

    test "handles language_specific nodes" do
      ast = {:language_specific, :python, %{code: "async def foo(): pass"}, :async_function}
      fp = Fingerprint.normalized(ast)

      assert is_binary(fp)
    end

    test "normalized ignores language_specific data but preserves hint" do
      ast1 = {:language_specific, :python, %{code: "async def foo(): pass"}, :async_function}
      ast2 = {:language_specific, :python, %{code: "async def bar(): return 1"}, :async_function}
      fp1 = Fingerprint.normalized(ast1)
      fp2 = Fingerprint.normalized(ast2)

      assert fp1 == fp2
    end

    test "handles deeply nested structures" do
      ast =
        {:binary_op, :arithmetic, :+,
         {:binary_op, :arithmetic, :*,
          {:binary_op, :arithmetic, :/, {:variable, "a"}, {:variable, "b"}}, {:variable, "c"}},
         {:literal, :integer, 1}}

      fp = Fingerprint.normalized(ast)

      assert is_binary(fp)
    end

    test "handles tuple elements" do
      ast = {:tuple, [{:variable, "x"}, {:literal, :integer, 42}, {:variable, "y"}]}
      fp = Fingerprint.normalized(ast)

      assert is_binary(fp)
    end
  end

  describe "complex scenarios" do
    test "normalized fingerprints for renamed function implementations" do
      # Python-style: def add(a, b): return a + b
      ast1 =
        {:block,
         [
           {:assignment, {:variable, "result"},
            {:binary_op, :arithmetic, :+, {:variable, "a"}, {:variable, "b"}}},
           {:early_return, {:variable, "result"}}
         ]}

      # Same function with different variable names
      ast2 =
        {:block,
         [
           {:assignment, {:variable, "sum"},
            {:binary_op, :arithmetic, :+, {:variable, "x"}, {:variable, "y"}}},
           {:early_return, {:variable, "sum"}}
         ]}

      fp1 = Fingerprint.normalized(ast1)
      fp2 = Fingerprint.normalized(ast2)

      assert fp1 == fp2
    end

    test "different control flow produces different normalized fingerprints" do
      # if x: return 1 else: return 2
      ast1 =
        {:conditional, {:variable, "x"}, {:early_return, {:literal, :integer, 1}},
         {:early_return, {:literal, :integer, 2}}}

      # while x: return 1
      ast2 = {:loop, :while, {:variable, "x"}, {:early_return, {:literal, :integer, 1}}}

      fp1 = Fingerprint.normalized(ast1)
      fp2 = Fingerprint.normalized(ast2)

      assert fp1 != fp2
    end

    test "map operations with different iterators produce same normalized fingerprint" do
      ast1 =
        {:collection_op, :map, {:lambda, ["x"], [], {:variable, "x"}}, {:variable, "items"}}

      ast2 =
        {:collection_op, :map, {:lambda, ["y"], [], {:variable, "y"}}, {:variable, "data"}}

      fp1 = Fingerprint.normalized(ast1)
      fp2 = Fingerprint.normalized(ast2)

      assert fp1 == fp2
    end
  end
end
