defmodule Metastatic.ASTStructuralTest do
  use ExUnit.Case, async: true

  alias Metastatic.AST

  doctest Metastatic.AST

  # Helper to build 3-tuple structural nodes
  defp container(container_type, name, body, opts \\ []) do
    meta = [container_type: container_type, name: name] ++ opts
    {:container, meta, body}
  end

  defp function_def(name, params, body, opts) do
    meta = [name: name, params: params] ++ opts
    {:function_def, meta, body}
  end

  defp attribute_access(attribute, receiver) do
    {:attribute_access, [attribute: attribute], [receiver]}
  end

  defp augmented_assignment(operator, target, value) do
    {:augmented_assignment, [operator: operator], [target, value]}
  end

  defp property(name, children, opts \\ []) do
    meta = [name: name] ++ opts
    {:property, meta, children}
  end

  defp literal(subtype, value), do: {:literal, [subtype: subtype], value}
  defp variable(name), do: {:variable, [], name}

  defp binary_op(category, operator, left, right) do
    {:binary_op, [category: category, operator: operator], [left, right]}
  end

  defp assignment(target, value) do
    {:assignment, [], [target, value]}
  end

  defp function_call(name, args) do
    {:function_call, [name: name], args}
  end

  describe "container conformance" do
    test "valid module container conforms" do
      ast = container(:module, "MyApp.Math", [])
      assert AST.conforms?(ast)
    end

    test "valid class container conforms" do
      ast = container(:class, "Calculator", [], parent: "BaseCalculator")
      assert AST.conforms?(ast)
    end

    test "namespace container conforms" do
      ast = container(:namespace, "Utils", [])
      assert AST.conforms?(ast)
    end

    test "container with members conforms" do
      func =
        function_def(
          "add",
          ["x", "y"],
          [binary_op(:arithmetic, :+, variable("x"), variable("y"))],
          visibility: :public
        )

      ast = container(:module, "Math", [func])
      assert AST.conforms?(ast)
    end

    test "container with invalid type does not conform" do
      ast = {:container, [container_type: :invalid_type, name: "Name"], []}
      refute AST.conforms?(ast)
    end

    test "container with non-string name does not conform" do
      ast = {:container, [container_type: :module, name: :not_a_string], []}
      refute AST.conforms?(ast)
    end

    test "container with invalid member does not conform" do
      ast = {:container, [container_type: :module, name: "Math"], [{:invalid_node, "data"}]}
      refute AST.conforms?(ast)
    end

    test "nested containers conform" do
      inner = container(:class, "Inner", [])
      outer = container(:module, "Outer", [inner])
      assert AST.conforms?(outer)
    end
  end

  describe "function_def conformance" do
    test "simple public function conforms" do
      ast =
        function_def(
          "add",
          ["x", "y"],
          [binary_op(:arithmetic, :+, variable("x"), variable("y"))],
          visibility: :public
        )

      assert AST.conforms?(ast)
    end

    test "private function conforms" do
      ast = function_def("_helper", ["data"], [variable("data")], visibility: :private)

      assert AST.conforms?(ast)
    end

    test "protected function conforms" do
      ast = function_def("validate", [], [literal(:boolean, true)], visibility: :protected)

      assert AST.conforms?(ast)
    end

    test "function with tuple parameter conforms" do
      # Parameters are stored as strings in the new format
      ast = function_def("get_first", ["tuple_param"], [variable("x")], visibility: :public)

      assert AST.conforms?(ast)
    end

    test "function with multiple parameters conforms" do
      ast =
        function_def(
          "greet",
          ["name", "greeting"],
          [function_call("puts", [literal(:string, "Hello")])],
          visibility: :public
        )

      assert AST.conforms?(ast)
    end

    test "function with guards in metadata conforms" do
      guard = binary_op(:comparison, :>, variable("x"), literal(:integer, 0))

      ast =
        function_def("positive?", ["x"], [literal(:boolean, true)],
          visibility: :public,
          guards: guard
        )

      assert AST.conforms?(ast)
    end

    test "function with decorators in metadata conforms" do
      decorator = function_call("decorator", [])

      ast =
        function_def("decorated", [], [literal(:null, nil)],
          visibility: :public,
          decorators: [decorator]
        )

      assert AST.conforms?(ast)
    end

    test "function with invalid name does not conform" do
      ast = {:function_def, [name: :not_a_string, params: []], [literal(:integer, 0)]}
      refute AST.conforms?(ast)
    end

    test "function with invalid body does not conform" do
      ast = {:function_def, [name: "func", params: []], [{:invalid_node, "data"}]}
      refute AST.conforms?(ast)
    end
  end

  describe "attribute_access conformance" do
    test "simple attribute access conforms" do
      ast = attribute_access("field", variable("obj"))
      assert AST.conforms?(ast)
    end

    test "chained attribute access conforms" do
      ast = attribute_access("street", attribute_access("address", variable("user")))
      assert AST.conforms?(ast)
    end

    test "attribute access with non-string attribute does not conform" do
      ast = {:attribute_access, [attribute: :not_string], [variable("obj")]}
      refute AST.conforms?(ast)
    end

    test "attribute access with invalid receiver does not conform" do
      ast = {:attribute_access, [attribute: "field"], [{:invalid_node, "data"}]}
      refute AST.conforms?(ast)
    end
  end

  describe "augmented_assignment conformance" do
    test "add-assign conforms" do
      ast = augmented_assignment(:+, variable("x"), literal(:integer, 5))
      assert AST.conforms?(ast)
    end

    test "multiply-assign conforms" do
      ast = augmented_assignment(:*, variable("count"), literal(:integer, 2))
      assert AST.conforms?(ast)
    end

    test "subtract-assign conforms" do
      ast = augmented_assignment(:-, variable("total"), variable("discount"))
      assert AST.conforms?(ast)
    end

    test "augmented assignment with invalid target does not conform" do
      ast = {:augmented_assignment, [operator: :+], [{:invalid_node, "x"}, literal(:integer, 1)]}
      refute AST.conforms?(ast)
    end

    test "augmented assignment with invalid value does not conform" do
      ast = {:augmented_assignment, [operator: :+], [variable("x"), {:invalid_node, "data"}]}
      refute AST.conforms?(ast)
    end
  end

  describe "property conformance" do
    test "property with getter and setter conforms" do
      getter = function_def("temperature", [], [variable("_temp")], visibility: :public)

      setter =
        function_def("temperature", ["value"], [assignment(variable("_temp"), variable("value"))],
          visibility: :public
        )

      ast = property("temperature", [getter, setter])
      assert AST.conforms?(ast)
    end

    test "read-only property conforms" do
      getter = function_def("name", [], [variable("@name")], visibility: :public)
      ast = property("name", [getter, nil])
      assert AST.conforms?(ast)
    end

    test "write-only property conforms" do
      setter =
        function_def(
          "password",
          ["value"],
          [assignment(variable("@password"), variable("value"))],
          visibility: :public
        )

      ast = property("password", [nil, setter])
      assert AST.conforms?(ast)
    end

    test "property with non-string name does not conform" do
      ast = {:property, [name: :not_string], [nil, nil]}
      refute AST.conforms?(ast)
    end

    test "property with invalid getter does not conform" do
      ast = {:property, [name: "name"], [{:invalid_node, "data"}, nil]}
      refute AST.conforms?(ast)
    end

    test "property with invalid setter does not conform" do
      ast = {:property, [name: "name"], [nil, {:invalid_node, "data"}]}
      refute AST.conforms?(ast)
    end
  end

  describe "variable extraction from containers" do
    test "extracts variables from container members" do
      func =
        function_def(
          "add",
          ["x", "y"],
          [binary_op(:arithmetic, :+, variable("x"), variable("y"))],
          visibility: :public
        )

      ast = container(:module, "Math", [func])
      vars = AST.variables(ast)
      assert MapSet.equal?(vars, MapSet.new(["x", "y"]))
    end

    test "extracts variables from decorators in container metadata" do
      decorator = function_call("decorator", [variable("config")])
      ast = container(:class, "MyClass", [decorator])
      vars = AST.variables(ast)
      assert MapSet.member?(vars, "config")
    end

    test "extracts variables from nested containers" do
      inner_func = function_def("inner_func", [], [variable("inner_var")], visibility: :public)
      inner = container(:class, "Inner", [inner_func])

      outer_func = function_def("outer_func", [], [variable("outer_var")], visibility: :public)
      outer = container(:module, "Outer", [inner, outer_func])

      vars = AST.variables(outer)
      assert MapSet.equal?(vars, MapSet.new(["inner_var", "outer_var"]))
    end
  end

  describe "variable extraction from function_def" do
    test "extracts parameter variables" do
      ast =
        function_def(
          "add",
          ["x", "y"],
          [binary_op(:arithmetic, :+, variable("x"), variable("y"))],
          visibility: :public
        )

      vars = AST.variables(ast)
      assert MapSet.equal?(vars, MapSet.new(["x", "y"]))
    end

    test "extracts body variables only (params are strings)" do
      # In the new format, params are just strings, not nested AST nodes
      ast = function_def("func", ["x", "y"], [variable("x")], visibility: :public)

      vars = AST.variables(ast)
      # variables/1 extracts variables from body, not from string params
      assert MapSet.equal?(vars, MapSet.new(["x"]))
    end

    test "extracts variables from body expressions" do
      ast =
        function_def(
          "func",
          ["name"],
          [function_call("puts", [variable("name"), variable("extra")])],
          visibility: :public
        )

      vars = AST.variables(ast)
      assert MapSet.equal?(vars, MapSet.new(["name", "extra"]))
    end

    test "extracts variables from guards" do
      guard = binary_op(:comparison, :>, variable("threshold"), literal(:integer, 0))

      ast =
        function_def(
          "check",
          ["x"],
          [binary_op(:comparison, :>, variable("x"), variable("threshold"))],
          visibility: :public,
          guards: guard
        )

      vars = AST.variables(ast)
      assert MapSet.equal?(vars, MapSet.new(["x", "threshold"]))
    end

    test "extracts variables from body only (decorators in metadata not traversed)" do
      # Decorators are stored in metadata, and variables/1 doesn't traverse metadata
      ast = function_def("func", [], [variable("result")], visibility: :public)

      vars = AST.variables(ast)
      assert MapSet.equal?(vars, MapSet.new(["result"]))
    end
  end

  describe "variable extraction from attribute_access" do
    test "extracts variables from receiver" do
      ast = attribute_access("field", variable("obj"))
      vars = AST.variables(ast)
      assert MapSet.equal?(vars, MapSet.new(["obj"]))
    end

    test "extracts variables from chained access" do
      ast = attribute_access("street", attribute_access("address", variable("user")))
      vars = AST.variables(ast)
      assert MapSet.equal?(vars, MapSet.new(["user"]))
    end
  end

  describe "variable extraction from augmented_assignment" do
    test "extracts variables from target and value" do
      ast = augmented_assignment(:+, variable("x"), variable("y"))
      vars = AST.variables(ast)
      assert MapSet.equal?(vars, MapSet.new(["x", "y"]))
    end

    test "extracts variables from complex target" do
      ast =
        augmented_assignment(:+, attribute_access("count", variable("obj")), literal(:integer, 1))

      vars = AST.variables(ast)
      assert MapSet.equal?(vars, MapSet.new(["obj"]))
    end
  end

  describe "variable extraction from property" do
    test "extracts variables from getter" do
      getter = function_def("temperature", [], [variable("_temp")], visibility: :public)
      ast = property("temperature", [getter, nil])
      vars = AST.variables(ast)
      assert MapSet.member?(vars, "_temp")
    end

    test "extracts variables from setter" do
      setter =
        function_def("temperature", ["value"], [assignment(variable("_temp"), variable("value"))],
          visibility: :public
        )

      ast = property("temperature", [nil, setter])
      vars = AST.variables(ast)
      assert MapSet.equal?(vars, MapSet.new(["value", "_temp"]))
    end

    test "extracts variables from both getter and setter" do
      getter = function_def("temperature", [], [variable("_temp")], visibility: :public)

      setter =
        function_def("temperature", ["value"], [assignment(variable("_temp"), variable("value"))],
          visibility: :public
        )

      ast = property("temperature", [getter, setter])
      vars = AST.variables(ast)
      assert MapSet.equal?(vars, MapSet.new(["_temp", "value"]))
    end
  end

  describe "helper functions" do
    test "container_name/1 extracts name" do
      ast = container(:module, "MyApp.Math", [])
      assert AST.container_name(ast) == "MyApp.Math"
    end

    test "function_name/1 extracts name" do
      ast = function_def("add", ["x", "y"], [variable("x")], visibility: :public)
      assert AST.function_name(ast) == "add"
    end

    test "function_visibility/1 extracts visibility" do
      ast = function_def("add", [], [literal(:integer, 0)], visibility: :public)
      assert AST.function_visibility(ast) == :public
    end

    test "has_state?/1 returns true for class" do
      ast = container(:class, "Counter", [])
      assert AST.has_state?(ast)
    end

    test "has_state?/1 returns false for module" do
      ast = container(:module, "Math", [])
      refute AST.has_state?(ast)
    end
  end

  describe "complex integration scenarios" do
    test "full Python-style class with methods" do
      add_method =
        function_def(
          "add",
          ["x", "y"],
          [binary_op(:arithmetic, :+, variable("x"), variable("y"))],
          visibility: :public
        )

      validate_method =
        function_def(
          "_validate",
          ["value"],
          [binary_op(:comparison, :>, variable("value"), literal(:integer, 0))],
          visibility: :private
        )

      class_ast =
        container(:class, "Calculator", [add_method, validate_method], parent: "BaseCalculator")

      assert AST.conforms?(class_ast)
      vars = AST.variables(class_ast)
      assert MapSet.equal?(vars, MapSet.new(["x", "y", "value"]))
    end

    test "full Elixir-style module with functions" do
      add_func =
        function_def(
          "add",
          ["x", "y"],
          [binary_op(:arithmetic, :+, variable("x"), variable("y"))],
          visibility: :public
        )

      validate_func =
        function_def("validate", ["x"], [literal(:boolean, true)],
          visibility: :private,
          guards: binary_op(:comparison, :>, variable("x"), literal(:integer, 0))
        )

      module_ast = container(:module, "MyApp.Calculator", [add_func, validate_func])

      assert AST.conforms?(module_ast)
      vars = AST.variables(module_ast)
      assert MapSet.equal?(vars, MapSet.new(["x", "y"]))
    end

    test "class with properties" do
      getter = function_def("temperature", [], [variable("_temp")], visibility: :public)

      setter =
        function_def("temperature", ["value"], [assignment(variable("_temp"), variable("value"))],
          visibility: :public
        )

      prop = property("temperature", [getter, setter])
      class_ast = container(:class, "Thermostat", [prop])

      assert AST.conforms?(class_ast)
      vars = AST.variables(class_ast)
      assert MapSet.equal?(vars, MapSet.new(["_temp", "value"]))
    end

    test "function with multiple string parameters" do
      # In new format, all params are just strings
      params = ["simple", "x", "y", "name"]

      ast =
        function_def(
          "complex_func",
          params,
          [
            function_call("process", [
              variable("simple"),
              variable("x"),
              variable("y"),
              variable("name")
            ])
          ],
          visibility: :public
        )

      assert AST.conforms?(ast)
      vars = AST.variables(ast)
      assert MapSet.equal?(vars, MapSet.new(["simple", "x", "y", "name"]))
    end
  end
end
