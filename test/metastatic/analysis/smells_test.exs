defmodule Metastatic.Analysis.SmellsTest do
  use ExUnit.Case, async: true

  alias Metastatic.Analysis.Smells
  alias Metastatic.Analysis.Smells.Result
  alias Metastatic.Document

  doctest Metastatic.Analysis.Smells

  # Helper functions for building 3-tuple MetaAST nodes
  defp literal(subtype, value), do: {:literal, [subtype: subtype], value}
  defp variable(name), do: {:variable, [], name}
  defp block(stmts), do: {:block, [], stmts}
  defp conditional(cond_expr, then_b, else_b), do: {:conditional, [], [cond_expr, then_b, else_b]}
  defp assignment(target, value), do: {:assignment, [], [target, value]}

  defp binary_op(cat, op, left, right),
    do: {:binary_op, [category: cat, operator: op], [left, right]}

  defp unary_op(cat, op, operand), do: {:unary_op, [category: cat, operator: op], [operand]}
  defp loop(loop_type, cond_expr, body), do: {:loop, [loop_type: loop_type], [cond_expr, body]}

  defp language_specific(lang, hint, native),
    do: {:language_specific, [language: lang, hint: hint], native}

  describe "analyze/1 - long function detection" do
    test "detects long function with correct smell type and location" do
      # Create AST with 51 statements (exceeds default threshold of 50)
      # Use actual statements (assignments) not just expressions
      statements =
        for i <- 1..51 do
          assignment(
            variable("x#{i}"),
            binary_op(:arithmetic, :+, variable("y#{i}"), literal(:integer, i))
          )
        end

      ast = block(statements)
      doc = Document.new(ast, :python, %{function_name: "calculate", line: 42})

      assert {:ok, result} = Smells.analyze(doc)
      assert result.has_smells?
      assert result.total_smells >= 1

      long_function_smell = Enum.find(result.smells, &(&1.type == :long_function))
      assert long_function_smell != nil
      assert long_function_smell.type == :long_function
      assert long_function_smell.severity in [:low, :medium, :high, :critical]
      assert long_function_smell.description =~ "51 statements"
      assert long_function_smell.suggestion != nil
      assert long_function_smell.context.statement_count == 51
      assert long_function_smell.context.threshold == 50

      # Verify location information
      assert long_function_smell.location != nil
      assert long_function_smell.location.function == "calculate"
      assert long_function_smell.location.line == 42
    end

    @tag skip: true, reason: :no_metadata
    test "detects long function with location from AST when metadata absent" do
      # Use actual statements
      statements =
        for i <- 1..60 do
          assignment(variable("x#{i}"), literal(:integer, i))
        end

      # Include language_specific node with line info
      ast_with_location =
        block([
          language_specific(:python, :statement, %{
            line: 100,
            body: assignment(variable("z"), literal(:integer, 1))
          })
          | statements
        ])

      doc = Document.new(ast_with_location, :python)

      assert {:ok, result} = Smells.analyze(doc)
      assert result.has_smells?

      long_function_smell = Enum.find(result.smells, &(&1.type == :long_function))
      assert long_function_smell != nil
      assert long_function_smell.location != nil
      assert long_function_smell.location.line == 100
    end

    test "no long function smell when below threshold" do
      statements =
        for i <- 1..30 do
          assignment(variable("x#{i}"), literal(:integer, i))
        end

      ast = block(statements)
      doc = Document.new(ast, :python)

      assert {:ok, result} = Smells.analyze(doc)

      long_function_smell = Enum.find(result.smells, &(&1.type == :long_function))
      assert long_function_smell == nil
    end

    test "severity increases with extreme statement counts" do
      # 150 statements = 3x threshold
      statements =
        for i <- 1..150 do
          assignment(variable("x#{i}"), literal(:integer, i))
        end

      ast = block(statements)
      doc = Document.new(ast, :python)

      assert {:ok, result} = Smells.analyze(doc)

      long_function_smell = Enum.find(result.smells, &(&1.type == :long_function))
      assert long_function_smell != nil
      assert long_function_smell.severity == :critical
    end

    test "respects custom thresholds" do
      statements =
        for i <- 1..25 do
          assignment(variable("x#{i}"), literal(:integer, i))
        end

      ast = block(statements)
      doc = Document.new(ast, :python)

      # Custom threshold of 20
      assert {:ok, result} = Smells.analyze(doc, thresholds: %{max_statements: 20})

      long_function_smell = Enum.find(result.smells, &(&1.type == :long_function))
      assert long_function_smell != nil
      assert long_function_smell.context.threshold == 20
    end
  end

  describe "analyze/1 - deep nesting detection" do
    test "detects deep nesting with correct smell type and location" do
      # Create AST with nesting depth of 5 (exceeds default threshold of 4)
      ast =
        conditional(
          variable("a"),
          conditional(
            variable("b"),
            conditional(
              variable("c"),
              conditional(
                variable("d"),
                conditional(variable("e"), literal(:integer, 1), literal(:integer, 2)),
                literal(:integer, 3)
              ),
              literal(:integer, 4)
            ),
            literal(:integer, 5)
          ),
          literal(:integer, 6)
        )

      doc = Document.new(ast, :python, %{function_name: "nested_logic", line: 15})

      assert {:ok, result} = Smells.analyze(doc)
      assert result.has_smells?

      deep_nesting_smell = Enum.find(result.smells, &(&1.type == :deep_nesting))
      assert deep_nesting_smell != nil
      assert deep_nesting_smell.type == :deep_nesting
      assert deep_nesting_smell.severity in [:low, :medium, :high, :critical]
      assert deep_nesting_smell.description =~ "Nesting depth of 5"
      assert deep_nesting_smell.suggestion =~ "Reduce nesting"
      assert deep_nesting_smell.context.max_nesting == 5
      assert deep_nesting_smell.context.threshold == 4

      # Verify location information
      assert deep_nesting_smell.location != nil
      assert deep_nesting_smell.location.function == "nested_logic"
      assert deep_nesting_smell.location.line == 15
    end

    test "detects deep nesting with location from elixir_meta" do
      ast =
        conditional(
          variable("a"),
          conditional(
            variable("b"),
            conditional(
              variable("c"),
              conditional(
                variable("d"),
                conditional(variable("e"), literal(:integer, 1), literal(:integer, 2)),
                literal(:integer, 3)
              ),
              literal(:integer, 4)
            ),
            literal(:integer, 5)
          ),
          literal(:integer, 6)
        )

      doc = Document.new(ast, :elixir, %{elixir_meta: [line: 77]})

      assert {:ok, result} = Smells.analyze(doc)

      deep_nesting_smell = Enum.find(result.smells, &(&1.type == :deep_nesting))
      assert deep_nesting_smell != nil
      assert deep_nesting_smell.location != nil
      assert Map.get(deep_nesting_smell.location, :line) == 77
    end

    test "no deep nesting smell when below threshold" do
      ast =
        conditional(
          variable("a"),
          conditional(variable("b"), literal(:integer, 1), literal(:integer, 2)),
          literal(:integer, 3)
        )

      doc = Document.new(ast, :python)

      assert {:ok, result} = Smells.analyze(doc)

      deep_nesting_smell = Enum.find(result.smells, &(&1.type == :deep_nesting))
      assert deep_nesting_smell == nil
    end

    test "respects custom nesting thresholds" do
      ast =
        conditional(
          variable("a"),
          conditional(
            variable("b"),
            conditional(variable("c"), literal(:integer, 1), literal(:integer, 2)),
            literal(:integer, 3)
          ),
          literal(:integer, 4)
        )

      doc = Document.new(ast, :python)

      # Custom threshold of 2
      assert {:ok, result} = Smells.analyze(doc, thresholds: %{max_nesting: 2})

      deep_nesting_smell = Enum.find(result.smells, &(&1.type == :deep_nesting))
      assert deep_nesting_smell != nil
      assert deep_nesting_smell.context.threshold == 2
    end
  end

  describe "analyze/1 - magic number detection with location metadata" do
    test "detects magic numbers with location metadata from AST" do
      # language_specific node wrapping entire expression with body containing the binary_op
      ast =
        language_specific(:python, :expression, %{
          line: 33,
          body: binary_op(:arithmetic, :+, variable("x"), literal(:integer, 42))
        })

      doc = Document.new(ast, :python)

      assert {:ok, result} = Smells.analyze(doc)
      assert result.has_smells?

      magic_number_smells = Enum.filter(result.smells, &(&1.type == :magic_number))
      assert match?([_ | _], magic_number_smells)

      smell = hd(magic_number_smells)
      assert smell.type == :magic_number
      assert smell.severity == :low
      assert smell.description =~ "42"
      assert smell.suggestion =~ "named constant"
      assert smell.location != nil
      assert smell.location.line == 33
    end

    test "detects magic numbers in binary operations" do
      ast = binary_op(:arithmetic, :*, variable("radius"), literal(:float, 3.14159))

      doc = Document.new(ast, :python)

      assert {:ok, result} = Smells.analyze(doc)

      magic_number_smells = Enum.filter(result.smells, &(&1.type == :magic_number))
      assert match?([_], magic_number_smells)

      smell = hd(magic_number_smells)
      assert smell.context.value == 3.14159
      assert smell.context.in_expression == true
    end

    test "detects multiple magic numbers with different locations" do
      ast =
        block([
          language_specific(:python, :expression, %{
            line: 10,
            body: binary_op(:arithmetic, :+, literal(:integer, 42), variable("x"))
          }),
          language_specific(:python, :expression, %{
            line: 20,
            body: binary_op(:arithmetic, :*, literal(:integer, 100), variable("y"))
          })
        ])

      doc = Document.new(ast, :python)

      assert {:ok, result} = Smells.analyze(doc)

      magic_number_smells = Enum.filter(result.smells, &(&1.type == :magic_number))
      assert match?([_, _], magic_number_smells)

      lines = Enum.map(magic_number_smells, & &1.location.line) |> Enum.sort()
      assert lines == [10, 20]
    end

    test "ignores common constants 0, 1, -1" do
      ast =
        block([
          binary_op(:arithmetic, :+, variable("x"), literal(:integer, 0)),
          binary_op(:arithmetic, :+, variable("y"), literal(:integer, 1)),
          binary_op(:arithmetic, :+, variable("z"), literal(:integer, -1))
        ])

      doc = Document.new(ast, :python)

      assert {:ok, result} = Smells.analyze(doc)

      magic_number_smells = Enum.filter(result.smells, &(&1.type == :magic_number))
      assert magic_number_smells == []
    end

    test "detects magic numbers in unary operations" do
      ast = unary_op(:arithmetic, :-, literal(:integer, 273))

      doc = Document.new(ast, :python)

      assert {:ok, result} = Smells.analyze(doc)

      magic_number_smells = Enum.filter(result.smells, &(&1.type == :magic_number))
      assert match?([_], magic_number_smells)
    end

    test "handles language_specific nodes in magic number detection" do
      # Test that language_specific wrapper is properly traversed
      ast =
        language_specific(:ruby, :expression, %{
          line: 55,
          body: binary_op(:arithmetic, :+, variable("x"), literal(:integer, 99))
        })

      doc = Document.new(ast, :ruby)

      assert {:ok, result} = Smells.analyze(doc)

      magic_number_smells = Enum.filter(result.smells, &(&1.type == :magic_number))
      assert match?([_ | _], magic_number_smells)

      smell = hd(magic_number_smells)
      assert smell.location != nil
      assert smell.location.line == 55
    end

    test "handles nested language_specific nodes without body" do
      # language_specific node without body should not crash
      ast =
        binary_op(
          :arithmetic,
          :+,
          language_specific(:go, :variable, %{line: 12}),
          literal(:integer, 7)
        )

      doc = Document.new(ast, :go)

      assert {:ok, result} = Smells.analyze(doc)
      # Should detect the magic number 7
      magic_number_smells = Enum.filter(result.smells, &(&1.type == :magic_number))
      assert match?([_], magic_number_smells)
    end
  end

  describe "analyze/1 - complex conditional detection with location and severity" do
    @tag skip: true, reason: :no_metadata
    test "detects complex conditionals with location metadata" do
      # Create deeply nested boolean: ((a and b) and c) or d - depth = 3
      ast =
        conditional(
          binary_op(
            :boolean,
            :or,
            binary_op(
              :boolean,
              :and,
              binary_op(:boolean, :and, variable("a"), variable("b")),
              variable("c")
            ),
            variable("d")
          ),
          literal(:integer, 1),
          literal(:integer, 2)
        )

      doc = Document.new(ast, :python, %{line: 88})

      assert {:ok, result} = Smells.analyze(doc)

      complex_conditional_smells =
        Enum.filter(result.smells, &(&1.type == :complex_conditional))

      assert match?([_ | _], complex_conditional_smells)

      smell = hd(complex_conditional_smells)
      assert smell.type == :complex_conditional
      assert smell.description =~ "nested boolean operations"
      assert smell.suggestion =~ "Extract condition logic"
      assert smell.context.complexity_depth > 2
      assert smell.location != nil
      assert smell.location.line == 88
    end

    test "determines severity based on boolean nesting depth" do
      # Depth 3: medium severity - ((a or b) and c) or d
      ast_medium =
        conditional(
          binary_op(
            :boolean,
            :or,
            binary_op(
              :boolean,
              :and,
              binary_op(:boolean, :or, variable("a"), variable("b")),
              variable("c")
            ),
            variable("d")
          ),
          literal(:integer, 1),
          literal(:integer, 2)
        )

      doc_medium = Document.new(ast_medium, :python)
      assert {:ok, result_medium} = Smells.analyze(doc_medium)

      smell_medium =
        Enum.find(result_medium.smells, &(&1.type == :complex_conditional))

      assert smell_medium != nil
      assert smell_medium.severity == :medium

      # Depth 4: high severity - (((a or b) and c) and d) or e
      ast_high =
        conditional(
          binary_op(
            :boolean,
            :or,
            binary_op(
              :boolean,
              :and,
              binary_op(
                :boolean,
                :and,
                binary_op(:boolean, :or, variable("a"), variable("b")),
                variable("c")
              ),
              variable("d")
            ),
            variable("e")
          ),
          literal(:integer, 1),
          literal(:integer, 2)
        )

      doc_high = Document.new(ast_high, :python)
      assert {:ok, result_high} = Smells.analyze(doc_high)

      smell_high = Enum.find(result_high.smells, &(&1.type == :complex_conditional))
      assert smell_high != nil
      assert smell_high.severity == :high
    end

    @tag skip: true, reason: :no_metadata
    test "detects complex conditionals in while loops" do
      # while ((a and b) and c) or d: ... - depth = 3
      ast =
        loop(
          :while,
          binary_op(
            :boolean,
            :or,
            binary_op(
              :boolean,
              :and,
              binary_op(:boolean, :and, variable("a"), variable("b")),
              variable("c")
            ),
            variable("d")
          ),
          literal(:integer, 1)
        )

      doc = Document.new(ast, :python, %{line: 45})

      assert {:ok, result} = Smells.analyze(doc)

      complex_conditional_smells =
        Enum.filter(result.smells, &(&1.type == :complex_conditional))

      assert match?([_ | _], complex_conditional_smells)

      smell = hd(complex_conditional_smells)
      assert smell.context.complexity_depth == 3
      assert smell.location.line == 45
    end

    test "handles unary boolean operations in depth calculation" do
      # not ((a and b) or c) - depth = 3
      ast =
        conditional(
          unary_op(
            :boolean,
            :not,
            binary_op(
              :boolean,
              :or,
              binary_op(:boolean, :and, variable("a"), variable("b")),
              variable("c")
            )
          ),
          literal(:integer, 1),
          literal(:integer, 2)
        )

      doc = Document.new(ast, :python)

      assert {:ok, result} = Smells.analyze(doc)

      complex_conditional_smells = Enum.filter(result.smells, &(&1.type == :complex_conditional))
      assert match?([_ | _], complex_conditional_smells)

      smell = hd(complex_conditional_smells)
      # Depth should be 3: not (1) -> or (2) -> and (3)
      assert smell.context.complexity_depth == 3
    end

    test "handles language_specific nodes in complex conditional detection" do
      # Complex condition wrapped in language_specific: ((a or b) and c) or d - depth = 3
      ast =
        language_specific(:javascript, :conditional, %{
          line: 66,
          body:
            conditional(
              binary_op(
                :boolean,
                :or,
                binary_op(
                  :boolean,
                  :and,
                  binary_op(:boolean, :or, variable("a"), variable("b")),
                  variable("c")
                ),
                variable("d")
              ),
              literal(:integer, 1),
              literal(:integer, 2)
            )
        })

      doc = Document.new(ast, :javascript)

      assert {:ok, result} = Smells.analyze(doc)

      complex_conditional_smells = Enum.filter(result.smells, &(&1.type == :complex_conditional))
      assert match?([_ | _], complex_conditional_smells)

      smell = hd(complex_conditional_smells)
      assert smell.location != nil
      assert smell.location.line == 66
    end

    test "no complex conditional smell for simple conditions" do
      # Simple condition: just 'a or b'
      ast =
        conditional(
          binary_op(:boolean, :or, variable("a"), variable("b")),
          literal(:integer, 1),
          literal(:integer, 2)
        )

      doc = Document.new(ast, :python)

      assert {:ok, result} = Smells.analyze(doc)

      complex_conditional_smells = Enum.filter(result.smells, &(&1.type == :complex_conditional))
      # Depth 2 is below threshold
      assert complex_conditional_smells == []
    end
  end

  describe "extract_location/1 - location extraction from document and AST" do
    test "extracts location from document metadata with function name and line" do
      # Force a smell by using many statements
      statements =
        for i <- 1..60, do: assignment(variable("x#{i}"), literal(:integer, i))

      doc_with_smell =
        Document.new(block(statements), :python, %{function_name: "bar", line: 50})

      assert {:ok, result} = Smells.analyze(doc_with_smell)
      assert result.has_smells?

      smell = hd(result.smells)
      assert smell.location.function == "bar"
      assert smell.location.line == 50
    end

    test "extracts location from document metadata with only line" do
      statements =
        for i <- 1..60, do: assignment(variable("x#{i}"), literal(:integer, i))

      doc = Document.new(block(statements), :elixir, %{line: 99})

      assert {:ok, result} = Smells.analyze(doc)

      smell = hd(result.smells)
      assert smell.location.line == 99
      refute Map.has_key?(smell.location, :function)
    end

    test "extracts location from elixir_meta in metadata" do
      statements =
        for i <- 1..60, do: assignment(variable("x#{i}"), literal(:integer, i))

      doc = Document.new(block(statements), :elixir, %{elixir_meta: [line: 222]})

      assert {:ok, result} = Smells.analyze(doc)

      smell = hd(result.smells)
      assert smell.location.line == 222
    end

    @tag skip: true, reason: :no_metadata
    test "extracts location from AST language_specific node when metadata absent" do
      statements =
        for i <- 1..60, do: assignment(variable("x#{i}"), literal(:integer, i))

      ast =
        block([
          language_specific(:python, :function, %{line: 333})
          | statements
        ])

      doc = Document.new(ast, :python)

      assert {:ok, result} = Smells.analyze(doc)

      smell = hd(result.smells)
      assert smell.location != nil
      assert smell.location.line == 333
    end

    test "returns nil location when no metadata or language_specific nodes present" do
      statements =
        for i <- 1..60, do: assignment(variable("x#{i}"), literal(:integer, i))

      doc = Document.new(block(statements), :python)

      assert {:ok, result} = Smells.analyze(doc)

      # Should still detect smell but location may be nil
      smell = hd(result.smells)
      # Location could be nil or absent
      assert smell.location == nil or smell.location == %{}
    end

    @tag skip: true, reason: :no_metadata
    test "extracts location from nested language_specific nodes in AST" do
      statements =
        for i <- 1..60, do: assignment(variable("x#{i}"), literal(:integer, i))

      ast =
        block([
          conditional(
            variable("x"),
            language_specific(:ruby, :block, %{line: 444}),
            literal(:integer, 1)
          )
          | statements
        ])

      doc = Document.new(ast, :ruby)

      assert {:ok, result} = Smells.analyze(doc)

      smell = hd(result.smells)
      assert smell.location != nil
      assert smell.location.line == 444
    end
  end

  describe "analyze/1 - no smells" do
    test "returns no smells for simple clean code" do
      ast = binary_op(:arithmetic, :+, variable("x"), variable("y"))
      doc = Document.new(ast, :python)

      assert {:ok, result} = Smells.analyze(doc)
      refute result.has_smells?
      assert result.total_smells == 0
      assert result.smells == []
      assert result.summary =~ "No code smells"
    end

    test "returns no smells for literal values" do
      ast = literal(:integer, 42)
      doc = Document.new(ast, :elixir)

      assert {:ok, result} = Smells.analyze(doc)
      refute result.has_smells?
    end
  end

  describe "analyze/1 - result structure" do
    test "returns proper result structure with multiple smells" do
      # AST that triggers multiple smell types
      statements =
        for i <- 1..60 do
          assignment(variable("x#{i}"), literal(:integer, i + 10))
        end

      ast =
        conditional(
          variable("a"),
          conditional(
            variable("b"),
            conditional(
              variable("c"),
              conditional(
                variable("d"),
                conditional(variable("e"), block(statements), literal(:integer, 2)),
                literal(:integer, 3)
              ),
              literal(:integer, 4)
            ),
            literal(:integer, 5)
          ),
          literal(:integer, 6)
        )

      doc = Document.new(ast, :python)

      assert {:ok, result} = Smells.analyze(doc)
      assert is_struct(result, Result)
      assert result.has_smells?
      assert result.total_smells > 0
      assert is_list(result.smells)
      assert is_map(result.by_severity)
      assert is_map(result.by_type)
      assert is_binary(result.summary)

      # Should have both long_function and deep_nesting
      smell_types = Enum.map(result.smells, & &1.type) |> MapSet.new()
      assert :long_function in smell_types
      assert :deep_nesting in smell_types
    end

    test "all smells have required fields" do
      ast = binary_op(:arithmetic, :+, variable("x"), literal(:integer, 42))
      doc = Document.new(ast, :python)

      assert {:ok, result} = Smells.analyze(doc)

      Enum.each(result.smells, fn smell ->
        assert Map.has_key?(smell, :type)
        assert Map.has_key?(smell, :severity)
        assert Map.has_key?(smell, :description)
        assert Map.has_key?(smell, :suggestion)
        assert Map.has_key?(smell, :context)
        assert Map.has_key?(smell, :location)
        assert is_atom(smell.type)
        assert smell.severity in [:critical, :high, :medium, :low]
        assert is_binary(smell.description)
        assert is_binary(smell.suggestion)
      end)
    end
  end
end
