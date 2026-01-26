defmodule Metastatic.ASTStructuralTest do
  use ExUnit.Case, async: true

  alias Metastatic.AST

  doctest Metastatic.AST

  describe "container conformance" do
    test "valid module container conforms" do
      ast = {:container, :module, "MyApp.Math", nil, [], [], []}

      assert AST.conforms?(ast)
    end

    test "valid class container conforms" do
      ast = {:container, :class, "Calculator", "BaseCalculator", [], [], []}

      assert AST.conforms?(ast)
    end

    test "namespace container conforms" do
      ast = {:container, :namespace, "Utils", nil, [], [], []}
      assert AST.conforms?(ast)
    end

    test "container with members conforms" do
      function_def =
        {:function_def, "add", ["x", "y"], nil, %{visibility: :public, arity: 2},
         {:binary_op, :arithmetic, :+, {:variable, "x"}, {:variable, "y"}}}

      container = {:container, :module, "Math", nil, [], [], [function_def]}
      assert AST.conforms?(container)
    end

    test "container with invalid type does not conform" do
      ast = {:container, :invalid_type, "Name", nil, [], [], []}
      refute AST.conforms?(ast)
    end

    test "container with non-string name does not conform" do
      ast = {:container, :module, :not_a_string, nil, [], [], []}
      refute AST.conforms?(ast)
    end

    test "container with invalid member does not conform" do
      ast = {:container, :module, "Math", nil, [], [], [{:invalid_node, "data"}]}
      refute AST.conforms?(ast)
    end

    test "nested containers conform" do
      inner = {:container, :class, "Inner", nil, [], [], []}
      outer = {:container, :module, "Outer", nil, [], [], [inner]}
      assert AST.conforms?(outer)
    end
  end

  describe "function_def conformance" do
    test "simple public function conforms" do
      ast =
        {:function_def, "add", ["x", "y"], nil, %{visibility: :public, arity: 2},
         {:binary_op, :arithmetic, :+, {:variable, "x"}, {:variable, "y"}}}

      assert AST.conforms?(ast)
    end

    test "private function conforms" do
      ast =
        {:function_def, "_helper", ["data"], nil, %{visibility: :private, arity: 1},
         {:variable, "data"}}

      assert AST.conforms?(ast)
    end

    test "protected function conforms" do
      ast =
        {:function_def, "validate", [], nil, %{visibility: :protected, arity: 0},
         {:literal, :boolean, true}}

      assert AST.conforms?(ast)
    end

    test "function with pattern parameter conforms" do
      pattern_param = {:pattern, {:tuple, [{:variable, "x"}, :_]}}

      ast =
        {:function_def, "get_first", [pattern_param], nil, %{visibility: :public, arity: 1},
         {:variable, "x"}}

      assert AST.conforms?(ast)
    end

    test "function with default parameter conforms" do
      default_param = {:default, "name", {:literal, :string, "World"}}

      ast =
        {:function_def, "greet", [default_param], nil, %{visibility: :public, arity: 1},
         {:function_call, "puts", [{:literal, :string, "Hello"}]}}

      assert AST.conforms?(ast)
    end

    test "function with guards in metadata conforms" do
      guard = {:binary_op, :comparison, :>, {:variable, "x"}, {:literal, :integer, 0}}

      ast =
        {:function_def, "positive?", ["x"], nil, %{visibility: :public, arity: 1, guards: guard},
         {:literal, :boolean, true}}

      assert AST.conforms?(ast)
    end

    test "function with decorators in metadata conforms" do
      decorator = {:function_call, "decorator", []}

      ast =
        {:function_def, "decorated", [], nil, %{visibility: :public, decorators: [decorator]},
         {:literal, :null, nil}}

      assert AST.conforms?(ast)
    end

    test "function with invalid visibility does not conform" do
      ast =
        {:function_def, :invalid_visibility, "func", [], %{}, {:literal, :integer, 0}}

      refute AST.conforms?(ast)
    end

    test "function with invalid parameter does not conform" do
      ast =
        {:function_def, "func", [{:invalid_param, "x"}], nil, %{visibility: :public},
         {:variable, "x"}}

      refute AST.conforms?(ast)
    end

    test "function with invalid body does not conform" do
      ast = {:function_def, "func", [], nil, %{visibility: :public}, {:invalid_node, "data"}}
      refute AST.conforms?(ast)
    end
  end

  describe "attribute_access conformance" do
    test "simple attribute access conforms" do
      ast = {:attribute_access, {:variable, "obj"}, "field"}
      assert AST.conforms?(ast)
    end

    test "chained attribute access conforms" do
      ast =
        {:attribute_access, {:attribute_access, {:variable, "user"}, "address"}, "street"}

      assert AST.conforms?(ast)
    end

    test "attribute access with non-string attribute does not conform" do
      ast = {:attribute_access, {:variable, "obj"}, :not_string}
      refute AST.conforms?(ast)
    end

    test "attribute access with invalid receiver does not conform" do
      ast = {:attribute_access, {:invalid_node, "data"}, "field"}
      refute AST.conforms?(ast)
    end
  end

  describe "augmented_assignment conformance" do
    test "add-assign conforms" do
      ast = {:augmented_assignment, :+, {:variable, "x"}, {:literal, :integer, 5}}
      assert AST.conforms?(ast)
    end

    test "multiply-assign conforms" do
      ast = {:augmented_assignment, :*, {:variable, "count"}, {:literal, :integer, 2}}
      assert AST.conforms?(ast)
    end

    test "subtract-assign conforms" do
      ast = {:augmented_assignment, :-, {:variable, "total"}, {:variable, "discount"}}
      assert AST.conforms?(ast)
    end

    test "augmented assignment with invalid target does not conform" do
      ast = {:augmented_assignment, :+, {:invalid_node, "x"}, {:literal, :integer, 1}}
      refute AST.conforms?(ast)
    end

    test "augmented assignment with invalid value does not conform" do
      ast = {:augmented_assignment, :+, {:variable, "x"}, {:invalid_node, "data"}}
      refute AST.conforms?(ast)
    end
  end

  describe "property conformance" do
    test "property with getter and setter conforms" do
      getter =
        {:function_def, "temperature", [], nil, %{visibility: :public}, {:variable, "_temp"}}

      setter =
        {:function_def, "temperature", ["value"], nil, %{visibility: :public},
         {:assignment, {:variable, "_temp"}, {:variable, "value"}}}

      ast = {:property, "temperature", getter, setter, %{is_read_only: false}}
      assert AST.conforms?(ast)
    end

    test "read-only property conforms" do
      getter = {:function_def, "name", [], nil, %{visibility: :public}, {:variable, "@name"}}
      ast = {:property, "name", getter, nil, %{is_read_only: true}}
      assert AST.conforms?(ast)
    end

    test "write-only property conforms" do
      setter =
        {:function_def, "password", ["value"], nil, %{visibility: :public},
         {:assignment, {:variable, "@password"}, {:variable, "value"}}}

      ast = {:property, "password", nil, setter, %{is_write_only: true}}
      assert AST.conforms?(ast)
    end

    test "property with non-string name does not conform" do
      ast = {:property, :not_string, nil, nil, %{}}
      refute AST.conforms?(ast)
    end

    test "property with invalid getter does not conform" do
      ast = {:property, "name", {:invalid_node, "data"}, nil, %{}}
      refute AST.conforms?(ast)
    end

    test "property with invalid setter does not conform" do
      ast = {:property, "name", nil, {:invalid_node, "data"}, %{}}
      refute AST.conforms?(ast)
    end
  end

  describe "variable extraction from containers" do
    test "extracts variables from container members" do
      function_def =
        {:function_def, "add", ["x", "y"], nil, %{visibility: :public},
         {:binary_op, :arithmetic, :+, {:variable, "x"}, {:variable, "y"}}}

      container = {:container, :module, "Math", nil, [], [], [function_def]}
      vars = AST.variables(container)
      assert MapSet.equal?(vars, MapSet.new(["x", "y"]))
    end

    test "extracts variables from decorators in container metadata" do
      # Decorator should be part of the container body to be extracted
      decorator = {:function_call, "decorator", [{:variable, "config"}]}
      container = {:container, :class, "MyClass", nil, [], [], [decorator]}
      vars = AST.variables(container)
      assert MapSet.member?(vars, "config")
    end

    test "extracts variables from nested containers" do
      inner_function =
        {:function_def, "inner_func", [], nil, %{visibility: :public}, {:variable, "inner_var"}}

      inner_container = {:container, :class, "Inner", nil, [], [], [inner_function]}

      outer_function =
        {:function_def, "outer_func", [], nil, %{visibility: :public}, {:variable, "outer_var"}}

      outer_container =
        {:container, :module, "Outer", nil, [], [], [inner_container, outer_function]}

      vars = AST.variables(outer_container)
      assert MapSet.equal?(vars, MapSet.new(["inner_var", "outer_var"]))
    end
  end

  describe "variable extraction from function_def" do
    test "extracts parameter variables" do
      ast =
        {:function_def, "add", ["x", "y"], nil, %{visibility: :public},
         {:binary_op, :arithmetic, :+, {:variable, "x"}, {:variable, "y"}}}

      vars = AST.variables(ast)
      assert MapSet.equal?(vars, MapSet.new(["x", "y"]))
    end

    test "extracts variables from pattern parameters" do
      pattern_param = {:pattern, {:tuple, [{:variable, "x"}, {:variable, "y"}]}}

      ast =
        {:function_def, "func", [pattern_param], nil, %{visibility: :public}, {:variable, "x"}}

      vars = AST.variables(ast)
      assert MapSet.equal?(vars, MapSet.new(["x", "y"]))
    end

    test "extracts variables from default parameters" do
      default_param = {:default, "name", {:variable, "default_name"}}

      ast =
        {:function_def, "func", [default_param], nil, %{visibility: :public},
         {:function_call, "puts", [{:variable, "name"}]}}

      vars = AST.variables(ast)
      assert MapSet.equal?(vars, MapSet.new(["name", "default_name"]))
    end

    test "extracts variables from guards" do
      guard = {:binary_op, :comparison, :>, {:variable, "threshold"}, {:literal, :integer, 0}}

      ast =
        {:function_def, "check", ["x"], nil, %{visibility: :public, guards: guard},
         {:binary_op, :comparison, :>, {:variable, "x"}, {:variable, "threshold"}}}

      vars = AST.variables(ast)
      assert MapSet.equal?(vars, MapSet.new(["x", "threshold"]))
    end

    test "extracts variables from decorators" do
      decorator = {:function_call, "decorator", [{:variable, "config"}]}

      ast =
        {:function_def, "func", [], nil, %{visibility: :public, decorators: [decorator]},
         {:variable, "result"}}

      vars = AST.variables(ast)
      assert MapSet.equal?(vars, MapSet.new(["config", "result"]))
    end
  end

  describe "variable extraction from attribute_access" do
    test "extracts variables from receiver" do
      ast = {:attribute_access, {:variable, "obj"}, "field"}
      vars = AST.variables(ast)
      assert MapSet.equal?(vars, MapSet.new(["obj"]))
    end

    test "extracts variables from chained access" do
      ast =
        {:attribute_access, {:attribute_access, {:variable, "user"}, "address"}, "street"}

      vars = AST.variables(ast)
      assert MapSet.equal?(vars, MapSet.new(["user"]))
    end
  end

  describe "variable extraction from augmented_assignment" do
    test "extracts variables from target and value" do
      ast = {:augmented_assignment, :+, {:variable, "x"}, {:variable, "y"}}
      vars = AST.variables(ast)
      assert MapSet.equal?(vars, MapSet.new(["x", "y"]))
    end

    test "extracts variables from complex target" do
      ast =
        {:augmented_assignment, :+, {:attribute_access, {:variable, "obj"}, "count"},
         {:literal, :integer, 1}}

      vars = AST.variables(ast)
      assert MapSet.equal?(vars, MapSet.new(["obj"]))
    end
  end

  describe "variable extraction from property" do
    test "extracts variables from getter" do
      getter =
        {:function_def, "temperature", [], nil, %{visibility: :public}, {:variable, "_temp"}}

      ast = {:property, "temperature", getter, nil, %{}}
      vars = AST.variables(ast)
      assert MapSet.member?(vars, "_temp")
    end

    test "extracts variables from setter" do
      setter =
        {:function_def, "temperature", ["value"], nil, %{visibility: :public},
         {:assignment, {:variable, "_temp"}, {:variable, "value"}}}

      ast = {:property, "temperature", nil, setter, %{}}
      vars = AST.variables(ast)
      assert MapSet.equal?(vars, MapSet.new(["value", "_temp"]))
    end

    test "extracts variables from both getter and setter" do
      getter =
        {:function_def, "temperature", [], nil, %{visibility: :public}, {:variable, "_temp"}}

      setter =
        {:function_def, "temperature", ["value"], nil, %{visibility: :public},
         {:assignment, {:variable, "_temp"}, {:variable, "value"}}}

      ast = {:property, "temperature", getter, setter, %{}}
      vars = AST.variables(ast)
      assert MapSet.equal?(vars, MapSet.new(["_temp", "value"]))
    end
  end

  describe "helper functions" do
    test "container_name/1 extracts name" do
      ast = {:container, :module, "MyApp.Math", nil, [], [], []}
      assert AST.container_name(ast) == "MyApp.Math"
    end

    test "function_name/1 extracts name" do
      ast = {:function_def, "add", ["x", "y"], nil, %{visibility: :public}, {:variable, "x"}}
      assert AST.function_name(ast) == "add"
    end

    test "function_visibility/1 extracts visibility" do
      ast = {:function_def, "add", [], nil, %{visibility: :public}, {:literal, :integer, 0}}
      assert AST.function_visibility(ast) == :public
    end

    test "has_state?/1 returns true when has_state is true" do
      ast = {:container, :class, "Counter", nil, [], [], []}
      assert AST.has_state?(ast)
    end

    test "has_state?/1 returns false when has_state is false" do
      ast = {:container, :module, "Math", nil, [], [], []}
      refute AST.has_state?(ast)
    end

    test "has_state?/1 returns false when has_state is not present" do
      ast = {:container, :module, "Math", nil, [], [], []}
      refute AST.has_state?(ast)
    end
  end

  describe "complex integration scenarios" do
    test "full Python-style class with methods" do
      add_method =
        {:function_def, "add", ["x", "y"], nil,
         %{visibility: :public, arity: 2, is_static: false},
         {:binary_op, :arithmetic, :+, {:variable, "x"}, {:variable, "y"}}}

      validate_method =
        {:function_def, "_validate", ["value"], nil, %{visibility: :private, arity: 1},
         {:binary_op, :comparison, :>, {:variable, "value"}, {:literal, :integer, 0}}}

      class_ast =
        {:container, :class, "Calculator", "BaseCalculator", [], [],
         [add_method, validate_method]}

      assert AST.conforms?(class_ast)
      vars = AST.variables(class_ast)
      assert MapSet.equal?(vars, MapSet.new(["x", "y", "value"]))
    end

    test "full Elixir-style module with functions" do
      add_func =
        {:function_def, "add", ["x", "y"], nil,
         %{
           visibility: :public,
           arity: 2,
           guards: nil,
           specs: "@spec add(number(), number()) :: number()"
         }, {:binary_op, :arithmetic, :+, {:variable, "x"}, {:variable, "y"}}}

      validate_func =
        {:function_def, "validate", ["x"], nil,
         %{
           visibility: :private,
           arity: 1,
           guards: {:binary_op, :comparison, :>, {:variable, "x"}, {:literal, :integer, 0}}
         }, {:literal, :boolean, true}}

      module_ast =
        {:container, :module, "MyApp.Calculator", nil, [], [], [add_func, validate_func]}

      assert AST.conforms?(module_ast)
      vars = AST.variables(module_ast)
      assert MapSet.equal?(vars, MapSet.new(["x", "y"]))
    end

    test "class with properties" do
      getter =
        {:function_def, "temperature", [], nil, %{visibility: :public, arity: 0},
         {:variable, "_temp"}}

      setter =
        {:function_def, "temperature", ["value"], nil, %{visibility: :public, arity: 1},
         {:assignment, {:variable, "_temp"}, {:variable, "value"}}}

      property = {:property, "temperature", getter, setter, %{is_read_only: false}}

      class_ast =
        {:container, :class, "Thermostat", nil, [], [], [property]}

      assert AST.conforms?(class_ast)
      vars = AST.variables(class_ast)
      assert MapSet.equal?(vars, MapSet.new(["_temp", "value"]))
    end

    test "function with all parameter types" do
      params = [
        "simple",
        {:pattern, {:tuple, [{:variable, "x"}, {:variable, "y"}]}},
        {:default, "name", {:literal, :string, "default"}}
      ]

      ast =
        {:function_def, "complex_func", params, nil, %{visibility: :public, arity: 3},
         {:function_call, "process",
          [{:variable, "simple"}, {:variable, "x"}, {:variable, "y"}, {:variable, "name"}]}}

      assert AST.conforms?(ast)
      vars = AST.variables(ast)
      assert MapSet.equal?(vars, MapSet.new(["simple", "x", "y", "name"]))
    end
  end
end
