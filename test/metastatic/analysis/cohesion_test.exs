defmodule Metastatic.Analysis.CohesionTest do
  use ExUnit.Case, async: true

  alias Metastatic.{Document, Analysis.Cohesion}
  alias Metastatic.Analysis.Cohesion.Result

  doctest Metastatic.Analysis.Cohesion
  doctest Metastatic.Analysis.Cohesion.Result
  doctest Metastatic.Analysis.Cohesion.Formatter

  describe "analyze/1 with perfect cohesion" do
    test "class with all methods sharing state" do
      # All three methods access "balance" instance variable
      ast =
        {:container, :class, "BankAccount", %{},
         [
           {:function_def, :public, "deposit", ["amount"], %{},
            {:augmented_assignment, :+, {:attribute_access, {:variable, "self"}, "balance"},
             {:variable, "amount"}}},
           {:function_def, :public, "withdraw", ["amount"], %{},
            {:augmented_assignment, :-, {:attribute_access, {:variable, "self"}, "balance"},
             {:variable, "amount"}}},
           {:function_def, :public, "get_balance", [], %{},
            {:attribute_access, {:variable, "self"}, "balance"}}
         ]}

      doc = Document.new(ast, :python)
      {:ok, result} = Cohesion.analyze(doc)

      assert result.container_name == "BankAccount"
      assert result.container_type == :class
      assert result.method_count == 3
      assert result.method_pairs == 3
      assert result.connected_pairs == 3
      assert result.lcom == 0
      assert result.tcc == 1.0
      assert result.lcc == 1.0
      assert result.shared_state == ["balance"]
      assert result.assessment == :excellent
    end

    test "class with multiple shared variables" do
      # Methods share multiple instance variables
      ast =
        {:container, :class, "Rectangle", %{},
         [
           {:function_def, :public, "set_dimensions", ["w", "h"], %{},
            {:block,
             [
               {:assignment, {:attribute_access, {:variable, "self"}, "width"}, {:variable, "w"}},
               {:assignment, {:attribute_access, {:variable, "self"}, "height"}, {:variable, "h"}}
             ]}},
           {:function_def, :public, "area", [], %{},
            {:binary_op, :arithmetic, :*, {:attribute_access, {:variable, "self"}, "width"},
             {:attribute_access, {:variable, "self"}, "height"}}},
           {:function_def, :public, "perimeter", [], %{},
            {:binary_op, :arithmetic, :*, {:literal, :integer, 2},
             {:binary_op, :arithmetic, :+, {:attribute_access, {:variable, "self"}, "width"},
              {:attribute_access, {:variable, "self"}, "height"}}}}
         ]}

      doc = Document.new(ast, :python)
      {:ok, result} = Cohesion.analyze(doc)

      assert result.lcom == 0
      assert result.tcc == 1.0
      assert "height" in result.shared_state
      assert "width" in result.shared_state
      assert result.assessment == :excellent
    end
  end

  describe "analyze/1 with poor cohesion" do
    test "utility class with unrelated methods" do
      # No shared state - each method independent
      ast =
        {:container, :class, "Utilities", %{},
         [
           {:function_def, :public, "format_date", ["date"], %{},
            {:function_call, "str", [{:variable, "date"}]}},
           {:function_def, :public, "calculate_tax", ["amount"], %{},
            {:binary_op, :arithmetic, :*, {:variable, "amount"}, {:literal, :float, 0.08}}},
           {:function_def, :public, "send_email", ["to", "msg"], %{},
            {:function_call, "send", [{:variable, "to"}, {:variable, "msg"}]}}
         ]}

      doc = Document.new(ast, :python)
      {:ok, result} = Cohesion.analyze(doc)

      assert result.method_count == 3
      assert result.lcom == 2
      assert result.tcc == 0.0
      assert result.lcc == 0.0
      assert result.shared_state == []
      assert result.assessment == :very_poor
      assert length(result.warnings) > 0
    end

    test "class with disjoint method groups" do
      # Two groups: {add, get_total} share "total", {format} is separate
      ast =
        {:container, :class, "Calculator", %{},
         [
           {:function_def, :public, "add", ["x"], %{},
            {:augmented_assignment, :+, {:attribute_access, {:variable, "self"}, "total"},
             {:variable, "x"}}},
           {:function_def, :public, "get_total", [], %{},
            {:attribute_access, {:variable, "self"}, "total"}},
           {:function_def, :public, "format", ["value"], %{},
            {:function_call, "str", [{:variable, "value"}]}}
         ]}

      doc = Document.new(ast, :python)
      {:ok, result} = Cohesion.analyze(doc)

      assert result.lcom == 1
      assert result.tcc < 1.0
      assert result.connected_pairs == 1
      assert result.assessment != :excellent
    end
  end

  describe "analyze/1 with moderate cohesion" do
    test "class with partial state sharing" do
      # Some methods share state, others don't
      ast =
        {:container, :class, "Person", %{},
         [
           {:function_def, :public, "set_name", ["name"], %{},
            {:assignment, {:attribute_access, {:variable, "self"}, "name"}, {:variable, "name"}}},
           {:function_def, :public, "get_name", [], %{},
            {:attribute_access, {:variable, "self"}, "name"}},
           {:function_def, :public, "set_age", ["age"], %{},
            {:assignment, {:attribute_access, {:variable, "self"}, "age"}, {:variable, "age"}}},
           {:function_def, :public, "validate_email", ["email"], %{},
            {:function_call, "is_valid", [{:variable, "email"}]}}
         ]}

      doc = Document.new(ast, :python)
      {:ok, result} = Cohesion.analyze(doc)

      assert result.method_count == 4
      assert result.lcom > 0
      assert result.tcc > 0.0 and result.tcc < 1.0
      # This class has poor cohesion (only 2 methods connected out of 6 pairs)
      assert result.assessment in [:fair, :good, :poor, :very_poor]
    end
  end

  describe "analyze/1 edge cases" do
    test "container with no methods" do
      ast = {:container, :module, "Empty", %{}, []}
      doc = Document.new(ast, :python)
      {:ok, result} = Cohesion.analyze(doc)

      assert result.method_count == 0
      assert result.method_pairs == 0
      assert result.lcom == 0
      assert result.tcc == 0.0
    end

    test "container with single method" do
      ast =
        {:container, :class, "Single", %{},
         [
           {:function_def, :public, "do_something", [], %{}, {:literal, :integer, 42}}
         ]}

      doc = Document.new(ast, :python)
      {:ok, result} = Cohesion.analyze(doc)

      assert result.method_count == 1
      assert result.method_pairs == 0
      assert result.lcom == 0
    end

    test "container with two methods no shared state" do
      ast =
        {:container, :class, "TwoMethods", %{},
         [
           {:function_def, :public, "foo", [], %{}, {:literal, :integer, 1}},
           {:function_def, :public, "bar", [], %{}, {:literal, :integer, 2}}
         ]}

      doc = Document.new(ast, :python)
      {:ok, result} = Cohesion.analyze(doc)

      assert result.method_count == 2
      assert result.method_pairs == 1
      assert result.lcom == 1
      assert result.tcc == 0.0
    end

    test "container with nested function definitions" do
      # Outer function contains inner helper
      inner_func =
        {:function_def, :private, "helper", ["x"], %{},
         {:binary_op, :arithmetic, :*, {:variable, "x"}, {:literal, :integer, 2}}}

      ast =
        {:container, :class, "Outer", %{},
         [
           {:function_def, :public, "process", ["value"], %{},
            {:block,
             [
               inner_func,
               {:function_call, "helper", [{:variable, "value"}]}
             ]}}
         ]}

      doc = Document.new(ast, :python)
      {:ok, result} = Cohesion.analyze(doc)

      # Should only count top-level methods
      assert result.method_count == 1
    end
  end

  describe "analyze/1 with complex state access" do
    test "methods with conditional state access" do
      ast =
        {:container, :class, "Conditional", %{},
         [
           {:function_def, :public, "maybe_use_state", ["flag"], %{},
            {:conditional, {:variable, "flag"}, {:attribute_access, {:variable, "self"}, "data"},
             {:literal, :null, nil}}},
           {:function_def, :public, "always_use_state", [], %{},
            {:attribute_access, {:variable, "self"}, "data"}}
         ]}

      doc = Document.new(ast, :python)
      {:ok, result} = Cohesion.analyze(doc)

      # Both methods access "data", so they're connected
      assert result.connected_pairs == 1
      assert result.lcom == 0
      assert "data" in result.shared_state
    end

    test "methods with state in loop bodies" do
      ast =
        {:container, :class, "WithLoop", %{},
         [
           {:function_def, :public, "increment_all", ["items"], %{},
            {:loop, :for_each, {:variable, "item"}, {:variable, "items"},
             {:augmented_assignment, :+, {:attribute_access, {:variable, "self"}, "counter"},
              {:variable, "item"}}}},
           {:function_def, :public, "get_counter", [], %{},
            {:attribute_access, {:variable, "self"}, "counter"}}
         ]}

      doc = Document.new(ast, :python)
      {:ok, result} = Cohesion.analyze(doc)

      assert result.lcom == 0
      assert "counter" in result.shared_state
    end

    test "methods accessing state through properties" do
      getter =
        {:function_def, :public, "value", [], %{},
         {:attribute_access, {:variable, "self"}, "_value"}}

      setter =
        {:function_def, :public, "value", ["v"], %{},
         {:assignment, {:attribute_access, {:variable, "self"}, "_value"}, {:variable, "v"}}}

      ast =
        {:container, :class, "WithProperty", %{},
         [
           {:property, "value", getter, setter, %{}}
         ]}

      doc = Document.new(ast, :python)
      {:ok, result} = Cohesion.analyze(doc)

      # Properties are not counted as methods for cohesion
      assert result.method_count == 0
    end
  end

  describe "analyze/1 with different container types" do
    test "module container" do
      ast =
        {:container, :module, "MyModule", %{},
         [
           {:function_def, :public, "func1", [], %{},
            {:attribute_access, {:variable, "@"}, "state"}},
           {:function_def, :public, "func2", [], %{},
            {:attribute_access, {:variable, "@"}, "state"}}
         ]}

      doc = Document.new(ast, :elixir)
      {:ok, result} = Cohesion.analyze(doc)

      assert result.container_type == :module
      assert result.lcom == 0
    end

    test "namespace container" do
      ast =
        {:container, :namespace, "MyNamespace", %{},
         [
           {:function_def, :public, "helper", [], %{}, {:literal, :integer, 1}}
         ]}

      doc = Document.new(ast, :csharp)
      {:ok, result} = Cohesion.analyze(doc)

      assert result.container_type == :namespace
    end
  end

  describe "analyze/1 error cases" do
    test "non-container AST returns error" do
      ast = {:literal, :integer, 42}
      doc = Document.new(ast, :python)
      {:error, reason} = Cohesion.analyze(doc)

      assert reason == "AST does not contain a container"
    end

    test "function_call returns error" do
      ast = {:function_call, "foo", []}
      doc = Document.new(ast, :python)
      assert {:error, _} = Cohesion.analyze(doc)
    end
  end

  describe "Result.assess/2" do
    test "excellent cohesion" do
      assert Result.assess(0, 0.9) == :excellent
      assert Result.assess(0, 0.8) == :excellent
    end

    test "good cohesion" do
      assert Result.assess(1, 0.7) == :good
      assert Result.assess(1, 0.6) == :good
    end

    test "fair cohesion" do
      assert Result.assess(2, 0.5) == :fair
      assert Result.assess(3, 0.4) == :fair
    end

    test "poor cohesion" do
      assert Result.assess(4, 0.3) == :poor
      assert Result.assess(5, 0.2) == :poor
    end

    test "very poor cohesion" do
      assert Result.assess(10, 0.1) == :very_poor
      assert Result.assess(6, 0.1) == :very_poor
    end
  end

  describe "Result.generate_warnings/3" do
    test "high LCOM warning" do
      warnings = Result.generate_warnings(8, 0.5, 5)
      assert Enum.any?(warnings, &String.contains?(&1, "Very high LCOM"))
    end

    test "low TCC warning" do
      warnings = Result.generate_warnings(2, 0.2, 5)
      assert Enum.any?(warnings, &String.contains?(&1, "Low TCC"))
    end

    test "small method count warning" do
      warnings = Result.generate_warnings(0, 1.0, 2)
      assert Enum.any?(warnings, &String.contains?(&1, "Only 2 methods"))
    end

    test "no warnings for good metrics" do
      warnings = Result.generate_warnings(1, 0.7, 5)
      assert warnings == []
    end
  end

  describe "Result.generate_recommendations/3" do
    test "excellent assessment" do
      recs = Result.generate_recommendations(:excellent, 5, 0.9)
      assert [rec] = recs
      assert String.contains?(rec, "excellent")
    end

    test "poor assessment with high method count" do
      recs = Result.generate_recommendations(:poor, 15, 0.2)
      assert length(recs) > 1
      assert Enum.any?(recs, &String.contains?(&1, "High method count"))
    end

    test "very poor assessment" do
      recs = Result.generate_recommendations(:very_poor, 20, 0.1)
      assert length(recs) >= 3
      assert Enum.any?(recs, &String.contains?(&1, "very poor cohesion"))
    end
  end
end
