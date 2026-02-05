defmodule Metastatic.ValidatorStructuralTest do
  use ExUnit.Case, async: true

  alias Metastatic.{Document, Validator}

  # Helpers for building 3-tuple structural nodes
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

  defp assignment(target, value), do: {:assignment, [], [target, value]}
  defp block(statements), do: {:block, [], statements}

  defp conditional(condition, then_branch, else_branch) do
    {:conditional, [], [condition, then_branch, else_branch]}
  end

  defp function_call(name, args), do: {:function_call, [name: name], args}

  describe "structural layer validation" do
    test "container validates as structural level" do
      ast = container(:module, "Math", [])
      doc = %Document{ast: ast, language: :elixir, metadata: %{}}

      assert {:ok, meta} = Validator.validate(doc)
      assert meta.level == :extended
      assert meta.native_constructs == 0
    end

    test "function_def validates as structural level" do
      ast = function_def("add", ["x", "y"], [variable("x")], visibility: :public)
      doc = %Document{ast: ast, language: :python, metadata: %{}}

      assert {:ok, meta} = Validator.validate(doc)
      assert meta.level == :extended
      assert meta.native_constructs == 0
    end

    test "attribute_access validates as structural level" do
      ast = attribute_access("field", variable("obj"))
      doc = %Document{ast: ast, language: :javascript, metadata: %{}}

      assert {:ok, meta} = Validator.validate(doc)
      assert meta.level == :extended
    end

    test "augmented_assignment validates as structural level" do
      ast = augmented_assignment(:+, variable("x"), literal(:integer, 5))
      doc = %Document{ast: ast, language: :python, metadata: %{}}

      assert {:ok, meta} = Validator.validate(doc)
      assert meta.level == :extended
    end

    test "property validates as structural level" do
      getter = function_def("name", [], [variable("@name")], visibility: :public)
      ast = property("name", [getter, nil])
      doc = %Document{ast: ast, language: :ruby, metadata: %{}}

      assert {:ok, meta} = Validator.validate(doc)
      assert meta.level == :extended
    end

    test "container with core-only members validates as structural" do
      add_method =
        function_def(
          "add",
          ["x", "y"],
          [binary_op(:arithmetic, :+, variable("x"), variable("y"))],
          visibility: :public
        )

      ast = container(:class, "Calculator", [add_method])
      doc = %Document{ast: ast, language: :python, metadata: %{}}

      assert {:ok, meta} = Validator.validate(doc)
      assert meta.level == :extended
    end

    test "container passes strict mode validation" do
      ast = container(:module, "Math", [])
      doc = %Document{ast: ast, language: :elixir, metadata: %{}}

      assert {:ok, meta} = Validator.validate(doc, mode: :strict)
      assert meta.level == :extended
      assert meta.native_constructs == 0
    end

    test "function_def passes strict mode validation" do
      ast = function_def("func", [], [literal(:integer, 42)], visibility: :public)
      doc = %Document{ast: ast, language: :elixir, metadata: %{}}

      assert {:ok, meta} = Validator.validate(doc, mode: :strict)
      assert meta.native_constructs == 0
    end
  end

  describe "variable extraction in validation" do
    test "extracts variables from container" do
      func =
        function_def(
          "add",
          ["x", "y"],
          [binary_op(:arithmetic, :+, variable("x"), variable("y"))],
          visibility: :public
        )

      ast = container(:module, "Math", [func])
      doc = %Document{ast: ast, language: :elixir, metadata: %{}}

      assert {:ok, meta} = Validator.validate(doc)
      assert MapSet.equal?(meta.variables, MapSet.new(["x", "y"]))
    end

    test "extracts variables from function_def" do
      ast =
        function_def(
          "func",
          ["param"],
          [function_call("process", [variable("param"), variable("global")])],
          visibility: :public
        )

      doc = %Document{ast: ast, language: :python, metadata: %{}}

      assert {:ok, meta} = Validator.validate(doc)
      assert MapSet.equal?(meta.variables, MapSet.new(["param", "global"]))
    end

    test "extracts variables from attribute_access" do
      ast = attribute_access("name", attribute_access("profile", variable("user")))
      doc = %Document{ast: ast, language: :javascript, metadata: %{}}

      assert {:ok, meta} = Validator.validate(doc)
      assert MapSet.member?(meta.variables, "user")
    end

    test "extracts variables from augmented_assignment" do
      ast = augmented_assignment(:+, variable("counter"), variable("increment"))
      doc = %Document{ast: ast, language: :python, metadata: %{}}

      assert {:ok, meta} = Validator.validate(doc)
      assert MapSet.equal?(meta.variables, MapSet.new(["counter", "increment"]))
    end

    test "extracts variables from property" do
      getter = function_def("value", [], [variable("_value")], visibility: :public)

      setter =
        function_def("value", ["v"], [assignment(variable("_value"), variable("v"))],
          visibility: :public
        )

      ast = property("value", [getter, setter])
      doc = %Document{ast: ast, language: :python, metadata: %{}}

      assert {:ok, meta} = Validator.validate(doc)
      assert MapSet.equal?(meta.variables, MapSet.new(["_value", "v"]))
    end
  end

  describe "depth calculation for structural types" do
    test "container depth includes members" do
      inner_func = function_def("inner", [], [literal(:integer, 1)], visibility: :public)
      ast = container(:module, "Outer", [inner_func])
      doc = %Document{ast: ast, language: :elixir, metadata: %{}}

      assert {:ok, meta} = Validator.validate(doc)
      assert meta.depth >= 3
    end

    test "function_def depth includes body" do
      nested_conditional =
        conditional(
          variable("x"),
          conditional(variable("y"), literal(:integer, 1), literal(:integer, 2)),
          literal(:integer, 3)
        )

      ast = function_def("nested", ["x", "y"], [nested_conditional], visibility: :public)
      doc = %Document{ast: ast, language: :python, metadata: %{}}

      assert {:ok, meta} = Validator.validate(doc)
      assert meta.depth >= 4
    end

    test "property depth includes getter and setter" do
      getter =
        function_def(
          "temp",
          [],
          [conditional(variable("_cached"), variable("_cached"), function_call("calculate", []))],
          visibility: :public
        )

      setter = function_def("temp", ["v"], [variable("v")], visibility: :public)
      ast = property("temp", [getter, setter])
      doc = %Document{ast: ast, language: :python, metadata: %{}}

      assert {:ok, meta} = Validator.validate(doc)
      assert meta.depth >= 3
    end
  end

  describe "node counting for structural types" do
    test "container nodes include all members" do
      func1 = function_def("f1", [], [literal(:integer, 1)], visibility: :public)
      func2 = function_def("f2", [], [literal(:integer, 2)], visibility: :public)
      ast = container(:module, "Math", [func1, func2])
      doc = %Document{ast: ast, language: :elixir, metadata: %{}}

      assert {:ok, meta} = Validator.validate(doc)
      # 1 container + 2 function_defs + 2 literals = 5 nodes minimum
      assert meta.node_count >= 5
    end

    test "function_def nodes include body" do
      body =
        block([
          assignment(variable("x"), literal(:integer, 1)),
          assignment(variable("y"), literal(:integer, 2)),
          binary_op(:arithmetic, :+, variable("x"), variable("y"))
        ])

      ast = function_def("func", [], [body], visibility: :public)
      doc = %Document{ast: ast, language: :python, metadata: %{}}

      assert {:ok, meta} = Validator.validate(doc)
      # Many nodes in body
      assert meta.node_count >= 8
    end
  end

  describe "invalid structural constructs" do
    test "container with invalid type fails validation" do
      ast = {:container, [container_type: :invalid, name: "Test"], []}
      doc = %Document{ast: ast, language: :elixir, metadata: %{}}

      assert {:error, {:invalid_structure, _}} = Validator.validate(doc)
    end

    test "function_def with non-string name fails validation" do
      ast = {:function_def, [name: :not_string, params: []], [literal(:integer, 1)]}
      doc = %Document{ast: ast, language: :python, metadata: %{}}

      assert {:error, {:invalid_structure, _}} = Validator.validate(doc)
    end

    test "attribute_access with non-string attribute fails validation" do
      ast = {:attribute_access, [attribute: :not_string], [variable("obj")]}
      doc = %Document{ast: ast, language: :javascript, metadata: %{}}

      assert {:error, {:invalid_structure, _}} = Validator.validate(doc)
    end

    test "augmented_assignment with invalid target fails validation" do
      ast = {:augmented_assignment, [operator: :+], [{:invalid, "node"}, literal(:integer, 1)]}
      doc = %Document{ast: ast, language: :python, metadata: %{}}

      assert {:error, {:invalid_structure, _}} = Validator.validate(doc)
    end

    test "property with non-string name fails validation" do
      ast = {:property, [name: :not_string], [nil, nil]}
      doc = %Document{ast: ast, language: :ruby, metadata: %{}}

      assert {:error, {:invalid_structure, _}} = Validator.validate(doc)
    end

    test "nested invalid structure in container fails validation" do
      invalid_member = {:invalid_node, "data"}
      ast = container(:module, "Test", [invalid_member])
      doc = %Document{ast: ast, language: :elixir, metadata: %{}}

      assert {:error, {:invalid_structure, _}} = Validator.validate(doc)
    end
  end

  describe "complex structural scenarios" do
    test "validates Python-style class" do
      init_method =
        function_def(
          "__init__",
          ["self", "name"],
          [assignment(attribute_access("name", variable("self")), variable("name"))],
          visibility: :public
        )

      greet_method =
        function_def(
          "greet",
          ["self"],
          [function_call("print", [attribute_access("name", variable("self"))])],
          visibility: :public
        )

      class_ast = container(:class, "Person", [init_method, greet_method])
      doc = %Document{ast: class_ast, language: :python, metadata: %{}}

      assert {:ok, meta} = Validator.validate(doc)
      assert meta.level == :extended
      assert MapSet.member?(meta.variables, "self")
      assert MapSet.member?(meta.variables, "name")
    end

    test "validates Elixir-style module with public and private functions" do
      public_func =
        function_def(
          "add",
          ["a", "b"],
          [binary_op(:arithmetic, :+, variable("a"), variable("b"))],
          visibility: :public
        )

      private_func =
        function_def(
          "do_add",
          ["x", "y"],
          [binary_op(:arithmetic, :+, variable("x"), variable("y"))],
          visibility: :private
        )

      module_ast = container(:module, "Math", [public_func, private_func])
      doc = %Document{ast: module_ast, language: :elixir, metadata: %{}}

      assert {:ok, meta} = Validator.validate(doc)
      assert meta.level == :extended
    end

    test "validates class with property" do
      getter = function_def("name", [], [variable("_name")], visibility: :public)

      setter =
        function_def("name", ["value"], [assignment(variable("_name"), variable("value"))],
          visibility: :public
        )

      name_property = property("name", [getter, setter])

      greet_method =
        function_def("greet", [], [function_call("print", [variable("_name")])],
          visibility: :public
        )

      class_ast = container(:class, "Person", [name_property, greet_method])
      doc = %Document{ast: class_ast, language: :python, metadata: %{}}

      assert {:ok, meta} = Validator.validate(doc)
      assert meta.level == :extended
    end

    test "validates nested modules" do
      inner_func = function_def("helper", [], [literal(:integer, 42)], visibility: :private)
      inner_module = container(:module, "Helper", [inner_func])

      outer_func =
        function_def("main", [], [function_call("Helper.helper", [])], visibility: :public)

      outer_module = container(:module, "App", [inner_module, outer_func])

      doc = %Document{ast: outer_module, language: :elixir, metadata: %{}}

      assert {:ok, meta} = Validator.validate(doc)
      assert meta.level == :extended
      assert meta.depth >= 4
    end
  end
end
