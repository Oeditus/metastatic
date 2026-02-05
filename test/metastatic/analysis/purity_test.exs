defmodule Metastatic.Analysis.PurityTest do
  use ExUnit.Case, async: true

  alias Metastatic.Analysis.Purity
  alias Metastatic.Analysis.Purity.Result
  alias Metastatic.Document

  doctest Metastatic.Analysis.Purity

  # Helper functions for building 3-tuple MetaAST nodes
  defp literal(subtype, value), do: {:literal, [subtype: subtype], value}
  defp variable(name), do: {:variable, [], name}
  defp block(stmts), do: {:block, [], stmts}
  defp conditional(cond_expr, then_b, else_b), do: {:conditional, [], [cond_expr, then_b, else_b]}
  defp assignment(target, value), do: {:assignment, [], [target, value]}

  defp binary_op(cat, op, left, right),
    do: {:binary_op, [category: cat, operator: op], [left, right]}

  defp function_call(name, args), do: {:function_call, [name: name], args}
  defp loop_while(cond_expr, body), do: {:loop, [loop_type: :while], [cond_expr, body]}
  defp loop_for(iter, coll, body), do: {:loop, [loop_type: :for, iterator: iter], [coll, body]}
  defp lambda(params, body), do: {:lambda, [params: params], [body]}
  defp inline_match(pattern, value), do: {:inline_match, [], [pattern, value]}

  defp exception_handling(try_block, catches, finally_block),
    do: {:exception_handling, [], [try_block, catches, finally_block]}

  defp collection_op(op, func, coll), do: {:collection_op, [operation: op], [func, coll]}

  defp collection_op(op, func, coll, init),
    do: {:collection_op, [operation: op], [func, coll, init]}

  describe "analyze/1 - pure constructs" do
    test "literals are pure" do
      ast = literal(:integer, 42)
      doc = Document.new(ast, :python)

      assert {:ok, result} = Purity.analyze(doc)
      assert result.pure?
      assert result.effects == []
      assert result.confidence == :high
    end

    test "variables are pure" do
      ast = variable("x")
      doc = Document.new(ast, :elixir)

      assert {:ok, result} = Purity.analyze(doc)
      assert result.pure?
    end

    test "arithmetic operations are pure" do
      ast = binary_op(:arithmetic, :+, variable("x"), literal(:integer, 5))

      doc = Document.new(ast, :python)

      assert {:ok, result} = Purity.analyze(doc)
      assert result.pure?
      assert result.summary == "Function is pure"
    end

    test "comparison operations are pure" do
      ast = binary_op(:comparison, :>, variable("x"), literal(:integer, 10))

      doc = Document.new(ast, :elixir)

      assert {:ok, result} = Purity.analyze(doc)
      assert result.pure?
    end

    test "conditionals with pure branches are pure" do
      ast = conditional(variable("cond"), literal(:integer, 1), literal(:integer, 2))

      doc = Document.new(ast, :python)

      assert {:ok, result} = Purity.analyze(doc)
      assert result.pure?
    end

    test "blocks with pure statements are pure" do
      ast =
        block([
          variable("x"),
          binary_op(:arithmetic, :+, variable("x"), literal(:integer, 1))
        ])

      doc = Document.new(ast, :elixir)

      assert {:ok, result} = Purity.analyze(doc)
      assert result.pure?
    end

    test "lambdas with pure bodies are pure" do
      ast =
        lambda([variable("x")], binary_op(:arithmetic, :*, variable("x"), literal(:integer, 2)))

      doc = Document.new(ast, :python)

      assert {:ok, result} = Purity.analyze(doc)
      assert result.pure?
    end

    test "pattern matching is pure (BEAM)" do
      ast = inline_match(variable("x"), literal(:integer, 42))

      doc = Document.new(ast, :elixir)

      assert {:ok, result} = Purity.analyze(doc)
      assert result.pure?
    end
  end

  describe "analyze/1 - impure I/O operations" do
    test "print function is impure" do
      ast = function_call("print", [literal(:string, "hello")])
      doc = Document.new(ast, :python)

      assert {:ok, result} = Purity.analyze(doc)
      refute result.pure?
      assert :io in result.effects
      assert result.confidence == :high
      assert result.summary =~ "I/O operations"
    end

    test "IO.puts is impure" do
      ast = function_call("IO.puts", [literal(:string, "hello")])
      doc = Document.new(ast, :elixir)

      assert {:ok, result} = Purity.analyze(doc)
      refute result.pure?
      assert :io in result.effects
    end

    test "file operations are impure" do
      ast = function_call("File.read", [literal(:string, "file.txt")])
      doc = Document.new(ast, :elixir)

      assert {:ok, result} = Purity.analyze(doc)
      refute result.pure?
      assert :io in result.effects
    end

    test "open function is impure" do
      ast = function_call("open", [literal(:string, "file.txt")])
      doc = Document.new(ast, :python)

      assert {:ok, result} = Purity.analyze(doc)
      refute result.pure?
      assert :io in result.effects
    end

    test "input function is impure" do
      ast = function_call("input", [literal(:string, "Enter value: ")])
      doc = Document.new(ast, :python)

      assert {:ok, result} = Purity.analyze(doc)
      refute result.pure?
      assert :io in result.effects
    end
  end

  describe "analyze/1 - impure mutations" do
    test "assignment outside loop is not mutation" do
      ast = assignment(variable("x"), literal(:integer, 5))
      doc = Document.new(ast, :python)

      assert {:ok, result} = Purity.analyze(doc)
      refute result.pure?
      assert :mutation in result.effects
    end

    test "assignment inside while loop is mutation" do
      ast =
        loop_while(
          variable("condition"),
          block([
            assignment(
              variable("x"),
              binary_op(:arithmetic, :+, variable("x"), literal(:integer, 1))
            )
          ])
        )

      doc = Document.new(ast, :python)

      assert {:ok, result} = Purity.analyze(doc)
      refute result.pure?
      assert :mutation in result.effects
    end

    test "assignment inside for loop is mutation" do
      ast =
        loop_for(
          variable("i"),
          variable("range"),
          block([
            assignment(
              variable("sum"),
              binary_op(:arithmetic, :+, variable("sum"), variable("i"))
            )
          ])
        )

      doc = Document.new(ast, :python)

      assert {:ok, result} = Purity.analyze(doc)
      refute result.pure?
      assert :mutation in result.effects
    end
  end

  describe "analyze/1 - impure random operations" do
    test "random function is impure" do
      ast = function_call("random", [])
      doc = Document.new(ast, :python)

      assert {:ok, result} = Purity.analyze(doc)
      refute result.pure?
      assert :random in result.effects
    end

    test "randint is impure" do
      ast = function_call("random.randint", [literal(:integer, 1), literal(:integer, 10)])

      doc = Document.new(ast, :python)

      assert {:ok, result} = Purity.analyze(doc)
      refute result.pure?
      assert :random in result.effects
    end

    test ":rand.uniform is impure" do
      ast = function_call(":rand.uniform", [])
      doc = Document.new(ast, :elixir)

      assert {:ok, result} = Purity.analyze(doc)
      refute result.pure?
      assert :random in result.effects
    end
  end

  describe "analyze/1 - impure time operations" do
    test "time function is impure" do
      ast = function_call("time", [])
      doc = Document.new(ast, :python)

      assert {:ok, result} = Purity.analyze(doc)
      refute result.pure?
      assert :time in result.effects
    end

    test "DateTime.utc_now is impure" do
      ast = function_call("DateTime.utc_now", [])
      doc = Document.new(ast, :elixir)

      assert {:ok, result} = Purity.analyze(doc)
      refute result.pure?
      assert :time in result.effects
    end

    test "erlang:now is impure" do
      ast = function_call("erlang:now", [])
      doc = Document.new(ast, :erlang)

      assert {:ok, result} = Purity.analyze(doc)
      refute result.pure?
      assert :time in result.effects
    end
  end

  describe "analyze/1 - impure network operations" do
    test "http functions are impure" do
      ast = function_call("http.get", [literal(:string, "http://example.com")])
      doc = Document.new(ast, :python)

      assert {:ok, result} = Purity.analyze(doc)
      refute result.pure?
      assert :network in result.effects
    end

    test "HTTPoison calls are impure" do
      ast = function_call("HTTPoison.get", [literal(:string, "http://example.com")])
      doc = Document.new(ast, :elixir)

      assert {:ok, result} = Purity.analyze(doc)
      refute result.pure?
      assert :network in result.effects
    end
  end

  describe "analyze/1 - impure database operations" do
    test "query functions are impure" do
      ast = function_call("query", [literal(:string, "SELECT * FROM users")])
      doc = Document.new(ast, :python)

      assert {:ok, result} = Purity.analyze(doc)
      refute result.pure?
      assert :database in result.effects
    end

    test "Repo operations are impure" do
      ast = function_call("Repo.all", [variable("User")])
      doc = Document.new(ast, :elixir)

      assert {:ok, result} = Purity.analyze(doc)
      refute result.pure?
      assert :database in result.effects
    end
  end

  describe "analyze/1 - exception handling" do
    test "exception handling is impure" do
      ast =
        exception_handling(
          function_call("risky_operation", []),
          [variable("error")],
          literal(:atom, :ok)
        )

      doc = Document.new(ast, :elixir)

      assert {:ok, result} = Purity.analyze(doc)
      refute result.pure?
      assert :exception in result.effects
    end
  end

  describe "analyze/1 - unknown functions" do
    test "unknown function calls result in low confidence" do
      ast = function_call("custom_user_function", [variable("x")])
      doc = Document.new(ast, :python)

      assert {:ok, result} = Purity.analyze(doc)
      refute result.pure?
      assert result.confidence == :low
      assert "custom_user_function" in result.unknown_calls
      assert result.summary =~ "unknown"
    end

    test "multiple unknown functions are tracked" do
      ast =
        block([
          function_call("func1", []),
          function_call("func2", [])
        ])

      doc = Document.new(ast, :python)

      assert {:ok, result} = Purity.analyze(doc)
      refute result.pure?
      assert result.confidence == :low
      assert "func1" in result.unknown_calls
      assert "func2" in result.unknown_calls
    end
  end

  describe "analyze/1 - mixed effects" do
    test "multiple effect types are detected" do
      ast =
        block([
          function_call("print", [literal(:string, "hello")]),
          function_call("random", []),
          loop_while(
            variable("true"),
            assignment(variable("x"), literal(:integer, 1))
          )
        ])

      doc = Document.new(ast, :python)

      assert {:ok, result} = Purity.analyze(doc)
      refute result.pure?
      assert :io in result.effects
      assert :random in result.effects
      assert :mutation in result.effects
      assert result.confidence == :high
    end
  end

  describe "analyze!/1" do
    test "returns result directly on success" do
      ast = literal(:integer, 42)
      doc = Document.new(ast, :python)

      result = Purity.analyze!(doc)
      assert %Result{} = result
      assert result.pure?
    end
  end

  describe "collection operations" do
    test "map operations are pure if function is pure" do
      ast =
        collection_op(
          :map,
          lambda(
            [variable("x")],
            binary_op(:arithmetic, :*, variable("x"), literal(:integer, 2))
          ),
          variable("list")
        )

      doc = Document.new(ast, :elixir)

      assert {:ok, result} = Purity.analyze(doc)
      assert result.pure?
    end

    test "reduce operations are pure if function is pure" do
      ast =
        collection_op(
          :reduce,
          lambda(
            [variable("acc"), variable("x")],
            binary_op(:arithmetic, :+, variable("acc"), variable("x"))
          ),
          variable("list"),
          literal(:integer, 0)
        )

      doc = Document.new(ast, :elixir)

      assert {:ok, result} = Purity.analyze(doc)
      assert result.pure?
    end
  end

  describe "language-aware input format" do
    test "accepts `language, native_ast, []` params for Python" do
      # Python AST for: 42
      python_ast = %{"_type" => "Constant", "value" => 42}

      assert {:ok, result} = Purity.analyze(:python, python_ast, [])
      assert result.pure?
      assert result.effects == []
    end

    test "accepts `language, native_ast, []` params for Python impure code" do
      # Python AST for: print("hello")
      python_ast = %{
        "_type" => "Call",
        "func" => %{"_type" => "Name", "id" => "print"},
        "args" => [%{"_type" => "Constant", "value" => "hello"}],
        "keywords" => []
      }

      assert {:ok, result} = Purity.analyze(:python, python_ast, [])
      refute result.pure?
      assert :io in result.effects
    end

    test "accepts `language, native_ast, []` params for Elixir" do
      # Elixir AST for: x + 5
      elixir_ast = {:+, [], [{:x, [], nil}, 5]}

      assert {:ok, result} = Purity.analyze(:elixir, elixir_ast, [])
      assert result.pure?
    end

    test "analyze! also accepts tuple format" do
      python_ast = %{"_type" => "Constant", "value" => 42}

      result = Purity.analyze!(:python, python_ast, [])
      assert %Result{} = result
      assert result.pure?
    end

    test "returns error for unsupported language" do
      assert {:error, {:unsupported_language, _}} =
               Purity.analyze(:unsupported_lang, :some_ast, [])
    end
  end
end
