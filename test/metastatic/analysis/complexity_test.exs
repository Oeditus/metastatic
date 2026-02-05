defmodule Metastatic.Analysis.ComplexityTest do
  use ExUnit.Case, async: true

  alias Metastatic.Analysis.Complexity
  alias Metastatic.Analysis.Complexity.Result
  alias Metastatic.Document

  doctest Metastatic.Analysis.Complexity

  # Helpers for 3-tuple format
  defp literal(subtype, value), do: {:literal, [subtype: subtype], value}
  defp variable(name), do: {:variable, [], name}
  defp block(stmts), do: {:block, [], stmts}

  defp binary_op(category, operator, left, right) do
    {:binary_op, [category: category, operator: operator], [left, right]}
  end

  defp conditional(cond, then_branch, else_branch) do
    {:conditional, [], [cond, then_branch, else_branch]}
  end

  defp loop(loop_type, condition, body) do
    {:loop, [loop_type: loop_type], [condition, body]}
  end

  defp lambda(params, body) do
    {:lambda, [params: params, captures: []], [body]}
  end

  defp collection_op(op_type, func, collection) do
    {:collection_op, [op_type: op_type], [func, collection]}
  end

  defp early_return(value), do: {:early_return, [], [value]}

  describe "analyze/1 - basic functionality" do
    test "analyzes simple literal" do
      ast = literal(:integer, 42)
      doc = Document.new(ast, :python)

      assert {:ok, result} = Complexity.analyze(doc)
      assert result.cyclomatic == 1
      assert result.cognitive == 0
      assert result.max_nesting == 0
      assert result.warnings == []
    end

    test "analyzes arithmetic expression" do
      ast = binary_op(:arithmetic, :+, variable("x"), literal(:integer, 5))
      doc = Document.new(ast, :elixir)

      assert {:ok, result} = Complexity.analyze(doc)
      assert result.cyclomatic == 1
      assert is_struct(result, Result)
    end

    test "analyzes conditional" do
      ast = conditional(variable("x"), literal(:integer, 1), literal(:integer, 2))
      doc = Document.new(ast, :python)

      assert {:ok, result} = Complexity.analyze(doc)
      assert result.cyclomatic == 2
    end
  end

  describe "analyze/1 - threshold warnings" do
    test "no warnings for low complexity" do
      ast = literal(:integer, 42)
      doc = Document.new(ast, :python)

      assert {:ok, result} = Complexity.analyze(doc)
      assert result.warnings == []
      assert String.contains?(result.summary, "low complexity")
    end

    test "warns when cyclomatic exceeds threshold" do
      # Build AST with 11 decision points (complexity = 12)
      conditionals =
        for i <- 1..11 do
          conditional(variable("x#{i}"), literal(:integer, 1), literal(:integer, 2))
        end

      ast = block(conditionals)
      doc = Document.new(ast, :python)

      assert {:ok, result} = Complexity.analyze(doc)
      assert result.cyclomatic == 12
      assert match?([_ | _], result.warnings)
      assert Enum.any?(result.warnings, &String.contains?(&1, "Cyclomatic"))
    end

    test "custom thresholds" do
      ast = conditional(variable("x"), literal(:integer, 1), literal(:integer, 2))
      doc = Document.new(ast, :python)

      # Lower threshold to trigger warning
      assert {:ok, result} = Complexity.analyze(doc, thresholds: %{cyclomatic_warning: 1})
      assert result.cyclomatic == 2
      assert match?([_ | _], result.warnings)
    end
  end

  describe "analyze/1 - selective metrics" do
    test "calculates only cyclomatic when specified" do
      ast = conditional(variable("x"), literal(:integer, 1), literal(:integer, 2))
      doc = Document.new(ast, :python)

      assert {:ok, result} = Complexity.analyze(doc, metrics: [:cyclomatic])
      assert result.cyclomatic == 2
      assert result.cognitive == 0
      assert result.max_nesting == 0
    end

    test "calculates all metrics by default" do
      ast = literal(:integer, 42)
      doc = Document.new(ast, :python)

      assert {:ok, result} = Complexity.analyze(doc)
      assert is_integer(result.cyclomatic)
      assert is_integer(result.cognitive)
      assert is_integer(result.max_nesting)
      assert is_map(result.halstead)
      assert is_map(result.loc)
      assert is_map(result.function_metrics)
    end
  end

  describe "analyze!/1" do
    test "returns result directly" do
      ast = literal(:integer, 42)
      doc = Document.new(ast, :python)

      result = Complexity.analyze!(doc)
      assert is_struct(result, Result)
      assert result.cyclomatic == 1
    end

    test "works with options" do
      ast = conditional(variable("x"), literal(:integer, 1), literal(:integer, 2))
      doc = Document.new(ast, :elixir)

      result = Complexity.analyze!(doc, metrics: [:cyclomatic])
      assert result.cyclomatic == 2
    end
  end

  describe "analyze/1 - complex AST structures" do
    test "analyzes nested blocks" do
      ast =
        block([
          conditional(variable("x"), literal(:integer, 1), literal(:integer, 2)),
          loop(:while, variable("y"), literal(:integer, 3)),
          variable("z")
        ])

      doc = Document.new(ast, :python)

      assert {:ok, result} = Complexity.analyze(doc)
      # 1 (base) + 1 (conditional) + 1 (loop) = 3
      assert result.cyclomatic == 3
    end

    test "analyzes lambdas" do
      ast = lambda(["x"], conditional(variable("x"), literal(:integer, 1), literal(:integer, 2)))
      doc = Document.new(ast, :elixir)

      assert {:ok, result} = Complexity.analyze(doc)
      # 1 (base) + 1 (conditional) = 2
      assert result.cyclomatic == 2
    end

    test "analyzes collection operations" do
      ast =
        collection_op(
          :map,
          lambda(["x"], conditional(variable("x"), literal(:integer, 1), literal(:integer, 2))),
          variable("list")
        )

      doc = Document.new(ast, :python)

      assert {:ok, result} = Complexity.analyze(doc)
      assert result.cyclomatic == 2
    end
  end

  describe "analyze/1 - cross-language consistency" do
    test "same AST produces same complexity regardless of language" do
      ast = conditional(variable("x"), literal(:integer, 1), literal(:integer, 2))

      python_doc = Document.new(ast, :python)
      elixir_doc = Document.new(ast, :elixir)
      erlang_doc = Document.new(ast, :erlang)

      assert {:ok, python_result} = Complexity.analyze(python_doc)
      assert {:ok, elixir_result} = Complexity.analyze(elixir_doc)
      assert {:ok, erlang_result} = Complexity.analyze(erlang_doc)

      assert python_result.cyclomatic == elixir_result.cyclomatic
      assert python_result.cyclomatic == erlang_result.cyclomatic
    end

    test "complex logic has consistent complexity" do
      # while condition:
      #   if x:
      #     return 1
      ast =
        loop(
          :while,
          variable("condition"),
          conditional(variable("x"), early_return(literal(:integer, 1)), nil)
        )

      python_doc = Document.new(ast, :python)
      elixir_doc = Document.new(ast, :elixir)

      assert {:ok, python_result} = Complexity.analyze(python_doc)
      assert {:ok, elixir_result} = Complexity.analyze(elixir_doc)

      # Both should have complexity 3 (base + loop + conditional)
      assert python_result.cyclomatic == 3
      assert elixir_result.cyclomatic == 3
    end
  end
end
