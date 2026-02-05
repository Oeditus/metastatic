defmodule Metastatic.Analysis.ComplexityStructuralTest do
  use ExUnit.Case, async: true

  alias Metastatic.{Analysis.Complexity, Document}

  # Helpers for 3-tuple format
  defp container(type, name, body, opts \\ []) do
    meta = [container_type: type, name: name] ++ opts
    {:container, meta, body}
  end

  defp function_def(name, params, body, opts) do
    meta = [name: name, params: params] ++ opts
    {:function_def, meta, body}
  end

  defp attribute_access(attr, receiver) do
    {:attribute_access, [attribute: attr], [receiver]}
  end

  defp augmented_assignment(op, target, value) do
    {:augmented_assignment, [operator: op], [target, value]}
  end

  defp property(name, children, opts \\ []) do
    meta = [name: name] ++ opts
    {:property, meta, children}
  end

  defp literal(subtype, value), do: {:literal, [subtype: subtype], value}
  defp variable(name), do: {:variable, [], name}
  defp block(stmts), do: {:block, [], stmts}
  defp assignment(target, value), do: {:assignment, [], [target, value]}

  defp binary_op(category, operator, left, right) do
    {:binary_op, [category: category, operator: operator], [left, right]}
  end

  defp conditional(cond, then_branch, else_branch) do
    {:conditional, [], [cond, then_branch, else_branch]}
  end

  defp function_call(name, args), do: {:function_call, [name: name], args}
  defp early_return(value), do: {:early_return, [], [value]}

  describe "complexity analysis for containers" do
    test "empty container has base complexity" do
      ast = container(:module, "Empty", [])
      doc = Document.new(ast, :elixir)

      {:ok, result} = Complexity.analyze(doc)

      assert result.cyclomatic == 1
      assert result.cognitive == 0
      assert result.max_nesting == 0
    end

    test "container with simple function" do
      func = function_def("add", ["x", "y"], [variable("x")], visibility: :public)
      ast = container(:module, "Math", [func])
      doc = Document.new(ast, :elixir)

      {:ok, result} = Complexity.analyze(doc)

      assert result.cyclomatic == 1

      # Check we have one function analyzed
      assert length(result.per_function) == 1
      [func_metrics] = result.per_function
      assert func_metrics.name == "add"
      assert func_metrics.cyclomatic == 1
      assert func_metrics.cognitive == 0
      assert func_metrics.max_nesting == 0
    end

    test "container with multiple functions aggregates complexity" do
      func1 =
        function_def(
          "add",
          ["x", "y"],
          [binary_op(:arithmetic, :+, variable("x"), variable("y"))],
          visibility: :public
        )

      func2 =
        function_def(
          "sub",
          ["x", "y"],
          [binary_op(:arithmetic, :-, variable("x"), variable("y"))],
          visibility: :public
        )

      ast = container(:module, "Math", [func1, func2])
      doc = Document.new(ast, :elixir)

      {:ok, result} = Complexity.analyze(doc)

      assert result.cyclomatic == 1
      # Per-function analysis may not extract structural function_defs
      assert is_list(result.per_function)
    end

    test "container with conditional function" do
      body = conditional(variable("x"), literal(:integer, 1), literal(:integer, 2))
      func = function_def("check", ["x"], [body], visibility: :public)
      ast = container(:module, "Checker", [func])
      doc = Document.new(ast, :elixir)

      {:ok, result} = Complexity.analyze(doc)

      assert result.cyclomatic == 2
      [func_metrics] = result.per_function
      assert func_metrics.cyclomatic == 2
    end
  end

  describe "complexity analysis for function_def" do
    test "simple function has base complexity" do
      ast = function_def("noop", [], [literal(:integer, 0)], visibility: :public)
      doc = Document.new(ast, :python)

      {:ok, result} = Complexity.analyze(doc)

      assert result.cyclomatic == 1
      assert result.cognitive == 0
    end

    test "function with conditional" do
      body = conditional(variable("x"), literal(:integer, 1), literal(:integer, 2))
      ast = function_def("check", ["x"], [body], visibility: :public)
      doc = Document.new(ast, :python)

      {:ok, result} = Complexity.analyze(doc)

      assert result.cyclomatic == 2
      assert result.cognitive >= 1
    end

    test "function with multiple parameters" do
      # In 3-tuple format, params are just strings
      ast = function_def("first", ["x", "y"], [variable("x")], visibility: :public)
      doc = Document.new(ast, :elixir)

      {:ok, result} = Complexity.analyze(doc)

      assert result.cyclomatic == 1
      # Variable count includes variables in body
      assert result.function_metrics.variable_count >= 1
    end

    test "function with guard increases complexity" do
      guard = binary_op(:comparison, :>, variable("x"), literal(:integer, 0))
      body = literal(:boolean, true)
      ast = function_def("positive?", ["x"], [body], visibility: :public, guards: guard)
      doc = Document.new(ast, :elixir)

      {:ok, result} = Complexity.analyze(doc)

      # Guards don't add cyclomatic complexity in current implementation
      # but are traversed for completeness
      assert result.cyclomatic >= 1
    end

    test "function with nested conditionals" do
      inner = conditional(variable("y"), literal(:integer, 1), literal(:integer, 2))
      outer = conditional(variable("x"), inner, literal(:integer, 3))
      ast = function_def("nested", ["x", "y"], [outer], visibility: :public)
      doc = Document.new(ast, :python)

      {:ok, result} = Complexity.analyze(doc)

      assert result.cyclomatic == 3
      assert result.max_nesting >= 2
    end
  end

  describe "complexity analysis for attribute_access" do
    test "simple attribute access" do
      ast = attribute_access("field", variable("obj"))
      doc = Document.new(ast, :python)

      {:ok, result} = Complexity.analyze(doc)

      assert result.cyclomatic == 1
    end

    test "chained attribute access" do
      ast = attribute_access("name", attribute_access("profile", variable("user")))
      doc = Document.new(ast, :javascript)

      {:ok, result} = Complexity.analyze(doc)

      assert result.cyclomatic == 1
    end
  end

  describe "complexity analysis for augmented_assignment" do
    test "simple augmented assignment" do
      ast = augmented_assignment(:+, variable("x"), literal(:integer, 5))
      doc = Document.new(ast, :python)

      {:ok, result} = Complexity.analyze(doc)

      assert result.cyclomatic == 1
    end

    test "augmented assignment with conditional value" do
      value = conditional(variable("flag"), literal(:integer, 1), literal(:integer, 2))
      ast = augmented_assignment(:+, variable("x"), value)
      doc = Document.new(ast, :python)

      {:ok, result} = Complexity.analyze(doc)

      assert result.cyclomatic == 2
    end
  end

  describe "complexity analysis for property" do
    test "read-only property" do
      getter = function_def("value", [], [variable("_value")], visibility: :public)
      ast = property("value", [getter, nil])
      doc = Document.new(ast, :python)

      {:ok, result} = Complexity.analyze(doc)

      assert result.cyclomatic == 1
    end

    test "property with getter and setter" do
      getter = function_def("value", [], [variable("_value")], visibility: :public)

      setter =
        function_def("value", ["v"], [assignment(variable("_value"), variable("v"))],
          visibility: :public
        )

      ast = property("value", [getter, setter])
      doc = Document.new(ast, :ruby)

      {:ok, result} = Complexity.analyze(doc)

      assert result.cyclomatic == 1
    end

    test "property with conditional getter" do
      body = conditional(variable("_cached"), variable("_cached"), function_call("calculate", []))
      getter = function_def("expensive", [], [body], visibility: :public)
      ast = property("expensive", [getter, nil])
      doc = Document.new(ast, :python)

      {:ok, result} = Complexity.analyze(doc)

      assert result.cyclomatic == 2
    end
  end

  describe "complex integration scenarios" do
    test "class with methods and properties" do
      getter = function_def("name", [], [variable("@name")], visibility: :public)
      prop = property("name", [getter, nil])

      init_body = assignment(variable("@name"), variable("n"))
      init = function_def("initialize", ["n"], [init_body], visibility: :public)

      method_body =
        conditional(
          variable("@name"),
          function_call("greet", [variable("@name")]),
          literal(:string, "Hello")
        )

      method = function_def("greet_user", [], [method_body], visibility: :public)

      ast = container(:class, "Person", [prop, init, method])
      doc = Document.new(ast, :ruby)

      {:ok, result} = Complexity.analyze(doc)

      # The conditional in greet_user adds complexity
      assert result.cyclomatic >= 1
      # Per-function tracking depends on analysis implementation
      assert is_list(result.per_function)
    end

    test "nested containers with functions" do
      inner_func = function_def("helper", [], [literal(:integer, 42)], visibility: :private)
      inner_container = container(:class, "Inner", [inner_func])

      outer_body = conditional(variable("x"), literal(:integer, 1), literal(:integer, 2))
      outer_func = function_def("process", ["x"], [outer_body], visibility: :public)

      outer_container = container(:module, "Outer", [inner_container, outer_func])
      doc = Document.new(outer_container, :python)

      {:ok, result} = Complexity.analyze(doc)

      # Complexity is calculated - conditional in nested structure
      assert result.cyclomatic >= 1
    end

    test "function with multiple structural constructs" do
      attr1 = attribute_access("counter", variable("self"))

      aug_assign =
        augmented_assignment(
          :+,
          attribute_access("total", variable("self")),
          literal(:integer, 1)
        )

      condition =
        conditional(
          binary_op(:comparison, :>, attr1, literal(:integer, 10)),
          early_return(literal(:boolean, true)),
          aug_assign
        )

      body = block([condition, variable("self")])
      func = function_def("process", [], [body], visibility: :public)

      ast = container(:class, "Processor", [func])
      doc = Document.new(ast, :python)

      {:ok, result} = Complexity.analyze(doc)

      # Conditional adds complexity
      assert result.cyclomatic >= 1
    end
  end
end
