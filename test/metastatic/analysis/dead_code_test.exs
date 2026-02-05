defmodule Metastatic.Analysis.DeadCodeTest do
  use ExUnit.Case, async: true

  alias Metastatic.{Analysis.DeadCode, Document}

  doctest Metastatic.Analysis.DeadCode
  doctest Metastatic.Analysis.DeadCode.Result

  # Helper functions for building 3-tuple MetaAST nodes
  defp literal(subtype, value), do: {:literal, [subtype: subtype], value}
  defp variable(name), do: {:variable, [], name}
  defp block(stmts), do: {:block, [], stmts}
  defp early_return(value), do: {:early_return, [], [value]}
  defp conditional(cond, then_b, else_b), do: {:conditional, [], [cond, then_b, else_b]}
  defp assignment(target, value), do: {:assignment, [], [target, value]}

  defp binary_op(cat, op, left, right),
    do: {:binary_op, [category: cat, operator: op], [left, right]}

  defp function_call(name, args), do: {:function_call, [name: name], args}
  defp loop(loop_type, condition, body), do: {:loop, [loop_type: loop_type], [condition, body]}
  defp lambda(params, body), do: {:lambda, [params: params], [body]}

  defp exception_handling(try_block, catches, finally),
    do: {:exception_handling, [], [try_block, catches, finally]}

  describe "analyze/1 - no dead code" do
    test "simple literal has no dead code" do
      ast = literal(:integer, 42)
      doc = Document.new(ast, :python)

      {:ok, result} = DeadCode.analyze(doc)

      assert result.has_dead_code? == false
      assert result.total_dead_statements == 0
      assert result.dead_locations == []
    end

    test "binary operation has no dead code" do
      ast = binary_op(:arithmetic, :+, variable("x"), literal(:integer, 5))
      doc = Document.new(ast, :elixir)

      {:ok, result} = DeadCode.analyze(doc)

      refute result.has_dead_code?
    end

    test "function call has no dead code" do
      ast = function_call("print", [literal(:string, "hello")])
      doc = Document.new(ast, :python)

      {:ok, result} = DeadCode.analyze(doc)

      refute result.has_dead_code?
    end

    test "conditional with both branches has no dead code" do
      ast = conditional(variable("x"), literal(:integer, 1), literal(:integer, 2))
      doc = Document.new(ast, :elixir)

      {:ok, result} = DeadCode.analyze(doc)

      refute result.has_dead_code?
    end

    test "block with multiple statements has no dead code" do
      ast =
        block([
          assignment(variable("x"), literal(:integer, 1)),
          assignment(variable("y"), literal(:integer, 2)),
          binary_op(:arithmetic, :+, variable("x"), variable("y"))
        ])

      doc = Document.new(ast, :python)

      {:ok, result} = DeadCode.analyze(doc)

      refute result.has_dead_code?
    end
  end

  describe "analyze/1 - unreachable after return" do
    test "detects code after early_return" do
      ast =
        block([
          early_return(literal(:integer, 42)),
          function_call("print", [literal(:string, "unreachable")])
        ])

      doc = Document.new(ast, :python)

      {:ok, result} = DeadCode.analyze(doc)

      assert result.has_dead_code?
      assert result.total_dead_statements == 1
      assert [location] = result.dead_locations
      assert location.type == :unreachable_after_return
      assert location.confidence == :high
    end

    test "detects multiple unreachable statements after return" do
      ast =
        block([
          early_return(literal(:integer, 1)),
          literal(:integer, 2),
          literal(:integer, 3)
        ])

      doc = Document.new(ast, :elixir)

      {:ok, result} = DeadCode.analyze(doc)

      assert result.has_dead_code?
      assert result.total_dead_statements == 2
      assert length(result.dead_locations) == 2
    end

    test "detects unreachable code in conditional branch" do
      ast =
        conditional(
          variable("x"),
          block([early_return(literal(:integer, 1)), literal(:integer, 2)]),
          literal(:integer, 3)
        )

      doc = Document.new(ast, :python)

      {:ok, result} = DeadCode.analyze(doc)

      assert result.has_dead_code?
      assert [location] = result.dead_locations
      assert location.type == :unreachable_after_return
    end

    test "detects unreachable code in loop body" do
      ast =
        loop(
          :while,
          literal(:boolean, true),
          block([early_return(literal(:integer, 1)), literal(:integer, 2)])
        )

      doc = Document.new(ast, :python)

      {:ok, result} = DeadCode.analyze(doc)

      assert result.has_dead_code?
      assert [location] = result.dead_locations
      assert location.type == :unreachable_after_return
    end

    test "detects unreachable code in lambda body" do
      ast =
        lambda(
          ["x"],
          block([early_return(literal(:integer, 1)), literal(:integer, 2)])
        )

      doc = Document.new(ast, :elixir)

      {:ok, result} = DeadCode.analyze(doc)

      assert result.has_dead_code?
      assert [location] = result.dead_locations
      assert location.type == :unreachable_after_return
    end

    test "detects unreachable code in exception handling" do
      try_block =
        block([early_return(literal(:integer, 1)), literal(:integer, 2)])

      ast = exception_handling(try_block, [], nil)
      doc = Document.new(ast, :python)

      {:ok, result} = DeadCode.analyze(doc)

      assert result.has_dead_code?
      assert [location] = result.dead_locations
      assert location.type == :unreachable_after_return
    end
  end

  describe "analyze/1 - constant conditionals" do
    test "detects unreachable else branch with constant true" do
      ast = conditional(literal(:boolean, true), literal(:integer, 1), literal(:integer, 2))
      doc = Document.new(ast, :python)

      {:ok, result} = DeadCode.analyze(doc)

      assert result.has_dead_code?
      assert [location] = result.dead_locations
      assert location.type == :constant_conditional
      assert location.confidence == :high
      assert location.context.dead_branch == :else
    end

    test "detects unreachable then branch with constant false" do
      ast = conditional(literal(:boolean, false), literal(:integer, 1), literal(:integer, 2))
      doc = Document.new(ast, :elixir)

      {:ok, result} = DeadCode.analyze(doc)

      assert result.has_dead_code?
      assert [location] = result.dead_locations
      assert location.type == :constant_conditional
      assert location.context.dead_branch == :then
    end

    test "treats integer 0 as constant false" do
      ast = conditional(literal(:integer, 0), literal(:integer, 1), literal(:integer, 2))
      doc = Document.new(ast, :python)

      {:ok, result} = DeadCode.analyze(doc)

      assert result.has_dead_code?
      assert [location] = result.dead_locations
      assert location.context.dead_branch == :then
    end

    test "treats non-zero integer as constant true" do
      ast = conditional(literal(:integer, 1), literal(:integer, 1), literal(:integer, 2))
      doc = Document.new(ast, :python)

      {:ok, result} = DeadCode.analyze(doc)

      assert result.has_dead_code?
      assert [location] = result.dead_locations
      assert location.context.dead_branch == :else
    end

    test "treats null/nil as constant false" do
      ast = conditional(literal(:null, nil), literal(:integer, 1), literal(:integer, 2))
      doc = Document.new(ast, :python)

      {:ok, result} = DeadCode.analyze(doc)

      assert result.has_dead_code?
      assert [location] = result.dead_locations
      assert location.context.dead_branch == :then
    end

    test "treats empty string as constant false" do
      ast = conditional(literal(:string, ""), literal(:integer, 1), literal(:integer, 2))
      doc = Document.new(ast, :python)

      {:ok, result} = DeadCode.analyze(doc)

      assert result.has_dead_code?
    end

    test "treats non-empty string as constant true" do
      ast = conditional(literal(:string, "hello"), literal(:integer, 1), literal(:integer, 2))
      doc = Document.new(ast, :python)

      {:ok, result} = DeadCode.analyze(doc)

      assert result.has_dead_code?
      assert [location] = result.dead_locations
      assert location.context.dead_branch == :else
    end

    test "does not flag non-constant conditionals" do
      ast = conditional(variable("x"), literal(:integer, 1), literal(:integer, 2))
      doc = Document.new(ast, :elixir)

      {:ok, result} = DeadCode.analyze(doc)

      refute result.has_dead_code?
    end

    test "detects nested constant conditionals" do
      inner = conditional(literal(:boolean, true), literal(:integer, 1), literal(:integer, 2))
      outer = conditional(literal(:boolean, false), inner, literal(:integer, 3))
      doc = Document.new(outer, :python)

      {:ok, result} = DeadCode.analyze(doc)

      assert result.has_dead_code?
      # Should detect both: outer's then branch and inner's else branch
      assert result.total_dead_statements == 2
    end

    test "does not report unreachable when else branch is nil" do
      ast = conditional(literal(:boolean, true), literal(:integer, 1), nil)
      doc = Document.new(ast, :python)

      {:ok, result} = DeadCode.analyze(doc)

      refute result.has_dead_code?
    end
  end

  describe "analyze/1 - combined patterns" do
    test "detects both unreachable after return and constant conditional" do
      # Block with return followed by code
      blk = block([early_return(literal(:integer, 1)), literal(:integer, 2)])
      # Constant conditional
      ast = conditional(literal(:boolean, true), blk, literal(:integer, 3))
      doc = Document.new(ast, :python)

      {:ok, result} = DeadCode.analyze(doc)

      assert result.has_dead_code?
      # Should detect: unreachable after return (1) + constant conditional (1) = 2
      assert result.total_dead_statements == 2

      types = Enum.map(result.dead_locations, & &1.type)
      assert :unreachable_after_return in types
      assert :constant_conditional in types
    end

    test "complex nested structure with multiple dead code patterns" do
      inner_blk = block([early_return(literal(:integer, 1)), literal(:integer, 2)])
      cond_ast = conditional(literal(:boolean, false), inner_blk, literal(:integer, 3))
      outer_blk = block([cond_ast, literal(:integer, 4)])
      doc = Document.new(outer_blk, :python)

      {:ok, result} = DeadCode.analyze(doc)

      # Constant conditional makes then branch dead, plus unreachable after return within it
      assert result.has_dead_code?
    end
  end

  describe "analyze/1 - options" do
    test "min_confidence filters low confidence results" do
      ast = block([early_return(literal(:integer, 1)), literal(:integer, 2)])
      doc = Document.new(ast, :python)

      {:ok, result_all} = DeadCode.analyze(doc, min_confidence: :low)
      {:ok, result_high} = DeadCode.analyze(doc, min_confidence: :high)

      # Both should detect the high-confidence unreachable code
      assert result_all.has_dead_code?
      assert result_high.has_dead_code?
      assert result_all.total_dead_statements == result_high.total_dead_statements
    end
  end

  describe "analyze!/1" do
    test "returns result directly" do
      ast = literal(:integer, 42)
      doc = Document.new(ast, :python)

      result = DeadCode.analyze!(doc)

      refute result.has_dead_code?
    end

    test "works with dead code" do
      ast = block([early_return(literal(:integer, 1)), literal(:integer, 2)])
      doc = Document.new(ast, :python)

      result = DeadCode.analyze!(doc)

      assert result.has_dead_code?
    end
  end

  describe "Result struct" do
    test "no_dead_code/0 creates empty result" do
      result = DeadCode.Result.no_dead_code()

      refute result.has_dead_code?
      assert result.total_dead_statements == 0
      assert result.dead_locations == []
      assert result.summary =~ "No dead code"
    end

    test "new/1 builds summary correctly" do
      locations = [
        %{
          type: :unreachable_after_return,
          reason: "test",
          confidence: :high,
          suggestion: "remove",
          context: nil
        },
        %{
          type: :constant_conditional,
          reason: "test",
          confidence: :high,
          suggestion: "fix",
          context: nil
        }
      ]

      result = DeadCode.Result.new(locations)

      assert result.has_dead_code?
      assert result.total_dead_statements == 2
      assert result.by_type[:unreachable_after_return] == 1
      assert result.by_type[:constant_conditional] == 1
      assert result.summary =~ "2 dead code location"
    end

    test "to_map/1 converts to JSON-compatible map" do
      result = DeadCode.Result.no_dead_code()
      map = DeadCode.Result.to_map(result)

      assert is_map(map)
      assert map.has_dead_code == false
      assert map.total_dead_statements == 0
      assert is_list(map.locations)
    end
  end
end
