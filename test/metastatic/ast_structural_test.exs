defmodule Metastatic.ASTStructuralTest do
  use ExUnit.Case, async: true

  alias Metastatic.AST

  doctest Metastatic.AST

  describe "container conformance" do
    test "valid module container conforms" do
      ast =
        {:container, :module, "MyApp.Math",
         %{
           source_language: :elixir,
           has_state: false,
           organizational_model: :fp,
           visibility: %{public: [{"add", 2}], private: [], protected: []}
         }, []}

      assert AST.conforms?(ast)
    end

    test "valid class container conforms" do
      ast =
        {:container, :class, "Calculator",
         %{
           source_language: :python,
           has_state: true,
           organizational_model: :oop,
           visibility: %{public: [{"add", 2}], private: [{"_validate", 1}], protected: []},
           superclass: "BaseCalculator"
         }, []}

      assert AST.conforms?(ast)
    end

    test "namespace container conforms" do
      ast = {:container, :namespace, "Utils", %{}, []}
      assert AST.conforms?(ast)
    end

    test "container with members conforms" do
      function_def =
        {:function_def, :public, "add", ["x", "y"], %{arity: 2},
         {:binary_op, :arithmetic, :+, {:variable, "x"}, {:variable, "y"}}}

      container = {:container, :module, "Math", %{}, [function_def]}
      assert AST.conforms?(container)
    end

    test "container with invalid type does not conform" do
      ast = {:container, :invalid_type, "Name", %{}, []}
      refute AST.conforms?(ast)
    end

    test "container with non-string name does not conform" do
      ast = {:container, :module, :not_a_string, %{}, []}
      refute AST.conforms?(ast)
    end

    test "container with invalid member does not conform" do
      ast = {:container, :module, "Math", %{}, [{:invalid_node, "data"}]}
      refute AST.conforms?(ast)
    end

    test "nested containers conform" do
      inner = {:container, :class, "Inner", %{is_nested: true}, []}
      outer = {:container, :module, "Outer", %{}, [inner]}
      assert AST.conforms?(outer)
    end
  end

  describe "function_def conformance" do
    test "simple public function conforms" do
      ast =
        {:function_def, :public, "add", ["x", "y"], %{arity: 2},
         {:binary_op, :arithmetic, :+, {:variable, "x"}, {:variable, "y"}}}

      assert AST.conforms?(ast)
    end

    test "private function conforms" do
      ast =
        {:function_def, :private, "_helper", ["data"], %{arity: 1}, {:variable, "data"}}

      assert AST.conforms?(ast)
    end

    test "protected function conforms" do
      ast = {:function_def, :protected, "validate", [], %{arity: 0}, {:literal, :boolean, true}}
      assert AST.conforms?(ast)
    end

    test "function with pattern parameter conforms" do
      pattern_param = {:pattern, {:tuple, [{:variable, "x"}, :_]}}

      ast = {:function_def, :public, "get_first", [pattern_param], %{arity: 1}, {:variable, "x"}}

      assert AST.conforms?(ast)
    end

    test "function with default parameter conforms" do
      default_param = {:default, "name", {:literal, :string, "World"}}

      ast =
        {:function_def, :public, "greet", [default_param], %{arity: 1},
         {:function_call, "puts", [{:literal, :string, "Hello"}]}}

      assert AST.conforms?(ast)
    end

    test "function with guards in metadata conforms" do
      guard = {:binary_op, :comparison, :>, {:variable, "x"}, {:literal, :integer, 0}}

      ast =
        {:function_def, :public, "positive?", ["x"], %{arity: 1, guards: guard},
         {:literal, :boolean, true}}

      assert AST.conforms?(ast)
    end

    test "function with decorators in metadata conforms" do
      decorator = {:function_call, "decorator", []}

      ast =
        {:function_def, :public, "decorated", [], %{decorators: [decorator]},
         {:literal, :null, nil}}

      assert AST.conforms?(ast)
    end

    test "function with invalid visibility does not conform" do
      ast =
        {:function_def, :invalid_visibility, "func", [], %{}, {:literal, :integer, 0}}

      refute AST.conforms?(ast)
    end

    test "function with invalid parameter does not conform" do
      ast = {:function_def, :public, "func", [{:invalid_param, "x"}], %{}, {:variable, "x"}}
      refute AST.conforms?(ast)
    end

    test "function with invalid body does not conform" do
      ast = {:function_def, :public, "func", [], %{}, {:invalid_node, "data"}}
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
      getter = {:function_def, :public, "temperature", [], %{}, {:variable, "_temp"}}

      setter =
        {:function_def, :public, "temperature", ["value"], %{},
         {:assignment, {:variable, "_temp"}, {:variable, "value"}}}

      ast = {:property, "temperature", getter, setter, %{is_read_only: false}}
      assert AST.conforms?(ast)
    end

    test "read-only property conforms" do
      getter = {:function_def, :public, "name", [], %{}, {:variable, "@name"}}
      ast = {:property, "name", getter, nil, %{is_read_only: true}}
      assert AST.conforms?(ast)
    end

    test "write-only property conforms" do
      setter =
        {:function_def, :public, "password", ["value"], %{},
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
        {:function_def, :public, "add", ["x", "y"], %{},
         {:binary_op, :arithmetic, :+, {:variable, "x"}, {:variable, "y"}}}

      container = {:container, :module, "Math", %{}, [function_def]}
      vars = AST.variables(container)
      assert MapSet.equal?(vars, MapSet.new(["x", "y"]))
    end

    test "extracts variables from decorators in container metadata" do
      decorator = {:function_call, "decorator", [{:variable, "config"}]}
      container = {:container, :class, "MyClass", %{decorators: [decorator]}, []}
      vars = AST.variables(container)
      assert MapSet.member?(vars, "config")
    end

    test "extracts variables from nested containers" do
      inner_function =
        {:function_def, :public, "inner_func", [], %{}, {:variable, "inner_var"}}

      inner_container = {:container, :class, "Inner", %{}, [inner_function]}

      outer_function =
        {:function_def, :public, "outer_func", [], %{}, {:variable, "outer_var"}}

      outer_container = {:container, :module, "Outer", %{}, [inner_container, outer_function]}

      vars = AST.variables(outer_container)
      assert MapSet.equal?(vars, MapSet.new(["inner_var", "outer_var"]))
    end
  end

  describe "variable extraction from function_def" do
    test "extracts parameter variables" do
      ast =
        {:function_def, :public, "add", ["x", "y"], %{},
         {:binary_op, :arithmetic, :+, {:variable, "x"}, {:variable, "y"}}}

      vars = AST.variables(ast)
      assert MapSet.equal?(vars, MapSet.new(["x", "y"]))
    end

    test "extracts variables from pattern parameters" do
      pattern_param = {:pattern, {:tuple, [{:variable, "x"}, {:variable, "y"}]}}
      ast = {:function_def, :public, "func", [pattern_param], %{}, {:variable, "x"}}
      vars = AST.variables(ast)
      assert MapSet.equal?(vars, MapSet.new(["x", "y"]))
    end

    test "extracts variables from default parameters" do
      default_param = {:default, "name", {:variable, "default_name"}}

      ast =
        {:function_def, :public, "func", [default_param], %{},
         {:function_call, "puts", [{:variable, "name"}]}}

      vars = AST.variables(ast)
      assert MapSet.equal?(vars, MapSet.new(["name", "default_name"]))
    end

    test "extracts variables from guards" do
      guard = {:binary_op, :comparison, :>, {:variable, "threshold"}, {:literal, :integer, 0}}

      ast =
        {:function_def, :public, "check", ["x"], %{guards: guard},
         {:binary_op, :comparison, :>, {:variable, "x"}, {:variable, "threshold"}}}

      vars = AST.variables(ast)
      assert MapSet.equal?(vars, MapSet.new(["x", "threshold"]))
    end

    test "extracts variables from decorators" do
      decorator = {:function_call, "decorator", [{:variable, "config"}]}

      ast =
        {:function_def, :public, "func", [], %{decorators: [decorator]}, {:variable, "result"}}

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
      getter = {:function_def, :public, "temperature", [], %{}, {:variable, "_temp"}}
      ast = {:property, "temperature", getter, nil, %{}}
      vars = AST.variables(ast)
      assert MapSet.member?(vars, "_temp")
    end

    test "extracts variables from setter" do
      setter =
        {:function_def, :public, "temperature", ["value"], %{},
         {:assignment, {:variable, "_temp"}, {:variable, "value"}}}

      ast = {:property, "temperature", nil, setter, %{}}
      vars = AST.variables(ast)
      assert MapSet.equal?(vars, MapSet.new(["value", "_temp"]))
    end

    test "extracts variables from both getter and setter" do
      getter = {:function_def, :public, "temperature", [], %{}, {:variable, "_temp"}}

      setter =
        {:function_def, :public, "temperature", ["value"], %{},
         {:assignment, {:variable, "_temp"}, {:variable, "value"}}}

      ast = {:property, "temperature", getter, setter, %{}}
      vars = AST.variables(ast)
      assert MapSet.equal?(vars, MapSet.new(["_temp", "value"]))
    end
  end

  describe "helper functions" do
    test "container_name/1 extracts name" do
      ast = {:container, :module, "MyApp.Math", %{}, []}
      assert AST.container_name(ast) == "MyApp.Math"
    end

    test "function_name/1 extracts name" do
      ast = {:function_def, :public, "add", ["x", "y"], %{}, {:variable, "x"}}
      assert AST.function_name(ast) == "add"
    end

    test "function_visibility/1 extracts visibility" do
      ast = {:function_def, :public, "add", [], %{}, {:literal, :integer, 0}}
      assert AST.function_visibility(ast) == :public
    end

    test "has_state?/1 returns true when has_state is true" do
      ast = {:container, :class, "Counter", %{has_state: true}, []}
      assert AST.has_state?(ast)
    end

    test "has_state?/1 returns false when has_state is false" do
      ast = {:container, :module, "Math", %{has_state: false}, []}
      refute AST.has_state?(ast)
    end

    test "has_state?/1 returns false when has_state is not present" do
      ast = {:container, :module, "Math", %{}, []}
      refute AST.has_state?(ast)
    end
  end

  describe "complex integration scenarios" do
    test "full Python-style class with methods" do
      add_method =
        {:function_def, :public, "add", ["x", "y"], %{arity: 2, is_static: false},
         {:binary_op, :arithmetic, :+, {:variable, "x"}, {:variable, "y"}}}

      validate_method =
        {:function_def, :private, "_validate", ["value"], %{arity: 1},
         {:binary_op, :comparison, :>, {:variable, "value"}, {:literal, :integer, 0}}}

      class_ast =
        {:container, :class, "Calculator",
         %{
           source_language: :python,
           has_state: true,
           organizational_model: :oop,
           visibility: %{public: [{"add", 2}], private: [{"_validate", 1}], protected: []},
           superclass: "BaseCalculator"
         }, [add_method, validate_method]}

      assert AST.conforms?(class_ast)
      vars = AST.variables(class_ast)
      assert MapSet.equal?(vars, MapSet.new(["x", "y", "value"]))
    end

    test "full Elixir-style module with functions" do
      add_func =
        {:function_def, :public, "add", ["x", "y"],
         %{
           arity: 2,
           guards: nil,
           specs: "@spec add(number(), number()) :: number()"
         }, {:binary_op, :arithmetic, :+, {:variable, "x"}, {:variable, "y"}}}

      validate_func =
        {:function_def, :private, "validate", ["x"],
         %{
           arity: 1,
           guards: {:binary_op, :comparison, :>, {:variable, "x"}, {:literal, :integer, 0}}
         }, {:literal, :boolean, true}}

      module_ast =
        {:container, :module, "MyApp.Calculator",
         %{
           source_language: :elixir,
           has_state: false,
           organizational_model: :fp,
           visibility: %{public: [{"add", 2}], private: [{"validate", 1}], protected: []}
         }, [add_func, validate_func]}

      assert AST.conforms?(module_ast)
      vars = AST.variables(module_ast)
      assert MapSet.equal?(vars, MapSet.new(["x", "y"]))
    end

    test "class with properties" do
      getter = {:function_def, :public, "temperature", [], %{arity: 0}, {:variable, "_temp"}}

      setter =
        {:function_def, :public, "temperature", ["value"], %{arity: 1},
         {:assignment, {:variable, "_temp"}, {:variable, "value"}}}

      property = {:property, "temperature", getter, setter, %{is_read_only: false}}

      class_ast =
        {:container, :class, "Thermostat",
         %{
           source_language: :python,
           has_state: true,
           organizational_model: :oop
         }, [property]}

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
        {:function_def, :public, "complex_func", params, %{arity: 3},
         {:function_call, "process",
          [{:variable, "simple"}, {:variable, "x"}, {:variable, "y"}, {:variable, "name"}]}}

      assert AST.conforms?(ast)
      vars = AST.variables(ast)
      assert MapSet.equal?(vars, MapSet.new(["simple", "x", "y", "name"]))
    end
  end
end
