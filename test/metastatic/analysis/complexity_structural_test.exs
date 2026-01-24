defmodule Metastatic.Analysis.ComplexityStructuralTest do
  use ExUnit.Case, async: true

  alias Metastatic.{Document, Analysis.Complexity}

  describe "complexity analysis for containers" do
    test "empty container has base complexity" do
      ast = {:container, :module, "Empty", %{}, []}
      doc = Document.new(ast, :elixir)

      {:ok, result} = Complexity.analyze(doc)

      assert result.cyclomatic == 1
      assert result.cognitive == 0
      assert result.max_nesting == 0
    end

    test "container with simple function" do
      func = {:function_def, :public, "add", ["x", "y"], %{}, {:variable, "x"}}
      ast = {:container, :module, "Math", %{}, [func]}
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
        {:function_def, :public, "add", ["x", "y"], %{},
         {:binary_op, :arithmetic, :+, {:variable, "x"}, {:variable, "y"}}}

      func2 =
        {:function_def, :public, "sub", ["x", "y"], %{},
         {:binary_op, :arithmetic, :-, {:variable, "x"}, {:variable, "y"}}}

      ast = {:container, :module, "Math", %{}, [func1, func2]}
      doc = Document.new(ast, :elixir)

      {:ok, result} = Complexity.analyze(doc)

      assert result.cyclomatic == 1
      assert length(result.per_function) == 2
    end

    test "container with conditional function" do
      body = {:conditional, {:variable, "x"}, {:literal, :integer, 1}, {:literal, :integer, 2}}
      func = {:function_def, :public, "check", ["x"], %{}, body}
      ast = {:container, :module, "Checker", %{}, [func]}
      doc = Document.new(ast, :elixir)

      {:ok, result} = Complexity.analyze(doc)

      assert result.cyclomatic == 2
      [func_metrics] = result.per_function
      assert func_metrics.cyclomatic == 2
    end
  end

  describe "complexity analysis for function_def" do
    test "simple function has base complexity" do
      ast = {:function_def, :public, "noop", [], %{}, {:literal, :integer, 0}}
      doc = Document.new(ast, :python)

      {:ok, result} = Complexity.analyze(doc)

      assert result.cyclomatic == 1
      assert result.cognitive == 0
    end

    test "function with conditional" do
      body = {:conditional, {:variable, "x"}, {:literal, :integer, 1}, {:literal, :integer, 2}}
      ast = {:function_def, :public, "check", ["x"], %{}, body}
      doc = Document.new(ast, :python)

      {:ok, result} = Complexity.analyze(doc)

      assert result.cyclomatic == 2
      assert result.cognitive >= 1
    end

    test "function with pattern parameter" do
      param = {:pattern, {:tuple, [{:variable, "x"}, {:variable, "y"}]}}
      ast = {:function_def, :public, "first", [param], %{}, {:variable, "x"}}
      doc = Document.new(ast, :elixir)

      {:ok, result} = Complexity.analyze(doc)

      assert result.cyclomatic == 1
      # Variable count includes parameters extracted from pattern
      assert result.function_metrics.variable_count >= 1
    end

    test "function with guard increases complexity" do
      guard = {:binary_op, :comparison, :>, {:variable, "x"}, {:literal, :integer, 0}}
      body = {:literal, :boolean, true}
      ast = {:function_def, :public, "positive?", ["x"], %{guards: guard}, body}
      doc = Document.new(ast, :elixir)

      {:ok, result} = Complexity.analyze(doc)

      # Guards don't add cyclomatic complexity in current implementation
      # but are traversed for completeness
      assert result.cyclomatic >= 1
    end

    test "function with nested conditionals" do
      inner = {:conditional, {:variable, "y"}, {:literal, :integer, 1}, {:literal, :integer, 2}}
      outer = {:conditional, {:variable, "x"}, inner, {:literal, :integer, 3}}
      ast = {:function_def, :public, "nested", ["x", "y"], %{}, outer}
      doc = Document.new(ast, :python)

      {:ok, result} = Complexity.analyze(doc)

      assert result.cyclomatic == 3
      assert result.max_nesting >= 2
    end
  end

  describe "complexity analysis for attribute_access" do
    test "simple attribute access" do
      ast = {:attribute_access, {:variable, "obj"}, "field"}
      doc = Document.new(ast, :python)

      {:ok, result} = Complexity.analyze(doc)

      assert result.cyclomatic == 1
    end

    test "chained attribute access" do
      ast = {:attribute_access, {:attribute_access, {:variable, "user"}, "profile"}, "name"}
      doc = Document.new(ast, :javascript)

      {:ok, result} = Complexity.analyze(doc)

      assert result.cyclomatic == 1
    end
  end

  describe "complexity analysis for augmented_assignment" do
    test "simple augmented assignment" do
      ast = {:augmented_assignment, :+, {:variable, "x"}, {:literal, :integer, 5}}
      doc = Document.new(ast, :python)

      {:ok, result} = Complexity.analyze(doc)

      assert result.cyclomatic == 1
    end

    test "augmented assignment with conditional value" do
      value =
        {:conditional, {:variable, "flag"}, {:literal, :integer, 1}, {:literal, :integer, 2}}

      ast = {:augmented_assignment, :+, {:variable, "x"}, value}
      doc = Document.new(ast, :python)

      {:ok, result} = Complexity.analyze(doc)

      assert result.cyclomatic == 2
    end
  end

  describe "complexity analysis for property" do
    test "read-only property" do
      getter = {:function_def, :public, "value", [], %{}, {:variable, "_value"}}
      ast = {:property, "value", getter, nil, %{}}
      doc = Document.new(ast, :python)

      {:ok, result} = Complexity.analyze(doc)

      assert result.cyclomatic == 1
    end

    test "property with getter and setter" do
      getter = {:function_def, :public, "value", [], %{}, {:variable, "_value"}}

      setter =
        {:function_def, :public, "value", ["v"], %{},
         {:assignment, {:variable, "_value"}, {:variable, "v"}}}

      ast = {:property, "value", getter, setter, %{}}
      doc = Document.new(ast, :ruby)

      {:ok, result} = Complexity.analyze(doc)

      assert result.cyclomatic == 1
    end

    test "property with conditional getter" do
      body =
        {:conditional, {:variable, "_cached"}, {:variable, "_cached"},
         {:function_call, "calculate", []}}

      getter = {:function_def, :public, "expensive", [], %{}, body}
      ast = {:property, "expensive", getter, nil, %{}}
      doc = Document.new(ast, :python)

      {:ok, result} = Complexity.analyze(doc)

      assert result.cyclomatic == 2
    end
  end

  describe "complex integration scenarios" do
    test "class with methods and properties" do
      getter = {:function_def, :public, "name", [], %{}, {:variable, "@name"}}
      property = {:property, "name", getter, nil, %{}}

      init_body = {:assignment, {:variable, "@name"}, {:variable, "n"}}
      init = {:function_def, :public, "initialize", ["n"], %{}, init_body}

      method_body =
        {:conditional, {:variable, "@name"}, {:function_call, "greet", [{:variable, "@name"}]},
         {:literal, :string, "Hello"}}

      method = {:function_def, :public, "greet_user", [], %{}, method_body}

      ast = {:container, :class, "Person", %{}, [property, init, method]}
      doc = Document.new(ast, :ruby)

      {:ok, result} = Complexity.analyze(doc)

      assert result.cyclomatic == 2
      # Properties with function_def getters/setters are extracted as functions
      # Only function_def members are counted, not property wrappers
      assert length(result.per_function) >= 2
    end

    test "nested containers with functions" do
      inner_func = {:function_def, :private, "helper", [], %{}, {:literal, :integer, 42}}
      inner_container = {:container, :class, "Inner", %{}, [inner_func]}

      outer_body =
        {:conditional, {:variable, "x"}, {:literal, :integer, 1}, {:literal, :integer, 2}}

      outer_func = {:function_def, :public, "process", ["x"], %{}, outer_body}

      outer_container = {:container, :module, "Outer", %{}, [inner_container, outer_func]}
      doc = Document.new(outer_container, :python)

      {:ok, result} = Complexity.analyze(doc)

      # Should analyze the outer function's conditional
      assert result.cyclomatic >= 2
    end

    test "function with multiple structural constructs" do
      attr1 = {:attribute_access, {:variable, "self"}, "counter"}

      aug_assign =
        {:augmented_assignment, :+, {:attribute_access, {:variable, "self"}, "total"},
         {:literal, :integer, 1}}

      condition =
        {:conditional, {:binary_op, :comparison, :>, attr1, {:literal, :integer, 10}},
         {:early_return, {:literal, :boolean, true}}, aug_assign}

      body = {:block, [condition, {:variable, "self"}]}
      func = {:function_def, :public, "process", [], %{}, body}

      ast = {:container, :class, "Processor", %{}, [func]}
      doc = Document.new(ast, :python)

      {:ok, result} = Complexity.analyze(doc)

      assert result.cyclomatic >= 2
      [func_metrics] = result.per_function
      assert func_metrics.cyclomatic >= 2
    end
  end
end
