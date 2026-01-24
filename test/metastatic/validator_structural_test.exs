defmodule Metastatic.ValidatorStructuralTest do
  use ExUnit.Case, async: true

  alias Metastatic.{Document, Validator}

  describe "structural layer validation" do
    test "container validates as extended level" do
      ast = {:container, :module, "Math", %{}, []}
      doc = %Document{ast: ast, language: :elixir, metadata: %{}}

      assert {:ok, meta} = Validator.validate(doc)
      assert meta.level == :extended
      assert meta.native_constructs == 0
    end

    test "function_def validates as extended level" do
      ast = {:function_def, :public, "add", ["x", "y"], %{}, {:variable, "x"}}
      doc = %Document{ast: ast, language: :python, metadata: %{}}

      assert {:ok, meta} = Validator.validate(doc)
      assert meta.level == :extended
      assert meta.native_constructs == 0
    end

    test "attribute_access validates as extended level" do
      ast = {:attribute_access, {:variable, "obj"}, "field"}
      doc = %Document{ast: ast, language: :javascript, metadata: %{}}

      assert {:ok, meta} = Validator.validate(doc)
      assert meta.level == :extended
    end

    test "augmented_assignment validates as extended level" do
      ast = {:augmented_assignment, :+, {:variable, "x"}, {:literal, :integer, 5}}
      doc = %Document{ast: ast, language: :python, metadata: %{}}

      assert {:ok, meta} = Validator.validate(doc)
      assert meta.level == :extended
    end

    test "property validates as extended level" do
      getter = {:function_def, :public, "name", [], %{}, {:variable, "@name"}}
      ast = {:property, "name", getter, nil, %{}}
      doc = %Document{ast: ast, language: :ruby, metadata: %{}}

      assert {:ok, meta} = Validator.validate(doc)
      assert meta.level == :extended
    end

    test "container with core-only members validates as extended" do
      add_method =
        {:function_def, :public, "add", ["x", "y"], %{},
         {:binary_op, :arithmetic, :+, {:variable, "x"}, {:variable, "y"}}}

      ast = {:container, :class, "Calculator", %{}, [add_method]}
      doc = %Document{ast: ast, language: :python, metadata: %{}}

      assert {:ok, meta} = Validator.validate(doc)
      assert meta.level == :extended
    end

    test "container passes strict mode validation" do
      ast = {:container, :module, "Math", %{}, []}
      doc = %Document{ast: ast, language: :elixir, metadata: %{}}

      assert {:ok, meta} = Validator.validate(doc, mode: :strict)
      assert meta.level == :extended
      assert meta.native_constructs == 0
    end

    test "function_def passes strict mode validation" do
      ast = {:function_def, :public, "func", [], %{}, {:literal, :integer, 42}}
      doc = %Document{ast: ast, language: :elixir, metadata: %{}}

      assert {:ok, meta} = Validator.validate(doc, mode: :strict)
      assert meta.native_constructs == 0
    end
  end

  describe "variable extraction in validation" do
    test "extracts variables from container" do
      function_def =
        {:function_def, :public, "add", ["x", "y"], %{},
         {:binary_op, :arithmetic, :+, {:variable, "x"}, {:variable, "y"}}}

      container = {:container, :module, "Math", %{}, [function_def]}
      doc = %Document{ast: container, language: :elixir, metadata: %{}}

      assert {:ok, meta} = Validator.validate(doc)
      assert MapSet.equal?(meta.variables, MapSet.new(["x", "y"]))
    end

    test "extracts variables from function_def" do
      ast =
        {:function_def, :public, "func", ["param"], %{},
         {:function_call, "process", [{:variable, "param"}, {:variable, "global"}]}}

      doc = %Document{ast: ast, language: :python, metadata: %{}}

      assert {:ok, meta} = Validator.validate(doc)
      assert MapSet.equal?(meta.variables, MapSet.new(["param", "global"]))
    end

    test "extracts variables from attribute_access" do
      ast =
        {:attribute_access, {:attribute_access, {:variable, "user"}, "profile"}, "name"}

      doc = %Document{ast: ast, language: :javascript, metadata: %{}}

      assert {:ok, meta} = Validator.validate(doc)
      assert MapSet.member?(meta.variables, "user")
    end

    test "extracts variables from augmented_assignment" do
      ast = {:augmented_assignment, :+, {:variable, "counter"}, {:variable, "increment"}}
      doc = %Document{ast: ast, language: :python, metadata: %{}}

      assert {:ok, meta} = Validator.validate(doc)
      assert MapSet.equal?(meta.variables, MapSet.new(["counter", "increment"]))
    end

    test "extracts variables from property" do
      getter = {:function_def, :public, "value", [], %{}, {:variable, "_value"}}

      setter =
        {:function_def, :public, "value", ["v"], %{},
         {:assignment, {:variable, "_value"}, {:variable, "v"}}}

      ast = {:property, "value", getter, setter, %{}}
      doc = %Document{ast: ast, language: :python, metadata: %{}}

      assert {:ok, meta} = Validator.validate(doc)
      assert MapSet.equal?(meta.variables, MapSet.new(["_value", "v"]))
    end
  end

  describe "depth calculation for structural types" do
    test "container depth includes members" do
      inner_func = {:function_def, :public, "inner", [], %{}, {:literal, :integer, 1}}
      container = {:container, :module, "Outer", %{}, [inner_func]}
      doc = %Document{ast: container, language: :elixir, metadata: %{}}

      assert {:ok, meta} = Validator.validate(doc)
      assert meta.depth >= 3
    end

    test "function_def depth includes body" do
      nested_conditional =
        {:conditional, {:variable, "x"},
         {:conditional, {:variable, "y"}, {:literal, :integer, 1}, {:literal, :integer, 2}},
         {:literal, :integer, 3}}

      ast = {:function_def, :public, "nested", ["x", "y"], %{}, nested_conditional}
      doc = %Document{ast: ast, language: :python, metadata: %{}}

      assert {:ok, meta} = Validator.validate(doc)
      assert meta.depth >= 4
    end

    test "property depth includes getter and setter" do
      getter =
        {:function_def, :public, "temp", [], %{},
         {:conditional, {:variable, "_cached"}, {:variable, "_cached"},
          {:function_call, "calculate", []}}}

      setter = {:function_def, :public, "temp", ["v"], %{}, {:variable, "v"}}
      ast = {:property, "temp", getter, setter, %{}}
      doc = %Document{ast: ast, language: :python, metadata: %{}}

      assert {:ok, meta} = Validator.validate(doc)
      assert meta.depth >= 3
    end
  end

  describe "node counting for structural types" do
    test "container nodes include all members" do
      func1 = {:function_def, :public, "f1", [], %{}, {:literal, :integer, 1}}
      func2 = {:function_def, :public, "f2", [], %{}, {:literal, :integer, 2}}
      container = {:container, :module, "Math", %{}, [func1, func2]}
      doc = %Document{ast: container, language: :elixir, metadata: %{}}

      assert {:ok, meta} = Validator.validate(doc)
      # 1 container + 2 function_defs + 2 literals = 5 nodes minimum
      assert meta.node_count >= 5
    end

    test "function_def nodes include body" do
      body =
        {:block,
         [
           {:assignment, {:variable, "x"}, {:literal, :integer, 1}},
           {:assignment, {:variable, "y"}, {:literal, :integer, 2}},
           {:binary_op, :arithmetic, :+, {:variable, "x"}, {:variable, "y"}}
         ]}

      ast = {:function_def, :public, "func", [], %{}, body}
      doc = %Document{ast: ast, language: :python, metadata: %{}}

      assert {:ok, meta} = Validator.validate(doc)
      # 1 function_def + 1 block + 3 statements = 5+ nodes
      assert meta.node_count >= 5
    end

    test "property nodes include getter and setter" do
      getter = {:function_def, :public, "x", [], %{}, {:variable, "_x"}}

      setter =
        {:function_def, :public, "x", ["v"], %{},
         {:assignment, {:variable, "_x"}, {:variable, "v"}}}

      ast = {:property, "x", getter, setter, %{}}
      doc = %Document{ast: ast, language: :python, metadata: %{}}

      assert {:ok, meta} = Validator.validate(doc)
      # 1 property + 2 function_defs + other nodes
      assert meta.node_count >= 3
    end
  end

  describe "complex structural scenarios" do
    test "nested containers validate correctly" do
      inner_func = {:function_def, :public, "inner", [], %{}, {:literal, :integer, 42}}
      inner_container = {:container, :class, "Inner", %{}, [inner_func]}
      outer_func = {:function_def, :public, "outer", [], %{}, {:variable, "result"}}
      outer_container = {:container, :module, "Outer", %{}, [inner_container, outer_func]}
      doc = %Document{ast: outer_container, language: :python, metadata: %{}}

      assert {:ok, meta} = Validator.validate(doc)
      assert meta.level == :extended
      assert MapSet.member?(meta.variables, "result")
      assert meta.node_count >= 6
    end

    test "function with complex parameters validates" do
      params = [
        "simple",
        {:pattern, {:tuple, [{:variable, "x"}, {:variable, "y"}]}},
        {:default, "opt", {:literal, :integer, 0}}
      ]

      body = {:binary_op, :arithmetic, :+, {:variable, "x"}, {:variable, "y"}}
      ast = {:function_def, :public, "complex", params, %{}, body}
      doc = %Document{ast: ast, language: :elixir, metadata: %{}}

      assert {:ok, meta} = Validator.validate(doc)
      assert MapSet.equal?(meta.variables, MapSet.new(["simple", "x", "y", "opt"]))
    end

    test "class with methods and properties validates" do
      getter = {:function_def, :public, "name", [], %{}, {:variable, "_name"}}
      property = {:property, "name", getter, nil, %{}}

      method =
        {:function_def, :public, "greet", [], %{},
         {:function_call, "print", [{:variable, "_name"}]}}

      class_ast = {:container, :class, "Person", %{}, [property, method]}
      doc = %Document{ast: class_ast, language: :python, metadata: %{}}

      assert {:ok, meta} = Validator.validate(doc)
      assert meta.level == :extended
      assert MapSet.member?(meta.variables, "_name")
    end

    test "function with guards in metadata validates" do
      guard = {:binary_op, :comparison, :>, {:variable, "x"}, {:literal, :integer, 0}}

      ast =
        {:function_def, :public, "positive", ["x"], %{guards: guard}, {:literal, :boolean, true}}

      doc = %Document{ast: ast, language: :elixir, metadata: %{}}

      assert {:ok, meta} = Validator.validate(doc)
      assert MapSet.member?(meta.variables, "x")
    end

    test "container with decorators in metadata validates" do
      decorator = {:function_call, "decorator", [{:variable, "config"}]}
      container = {:container, :class, "Decorated", %{decorators: [decorator]}, []}
      doc = %Document{ast: container, language: :python, metadata: %{}}

      assert {:ok, meta} = Validator.validate(doc)
      assert MapSet.member?(meta.variables, "config")
    end
  end

  describe "validation with mixed M2 levels" do
    test "container with core and extended constructs" do
      # Core construct
      literal_assign = {:assignment, {:variable, "x"}, {:literal, :integer, 5}}

      # Extended construct
      loop_body = {:loop, :while, {:variable, "running"}, {:variable, "x"}}

      func = {:function_def, :public, "run", [], %{}, {:block, [literal_assign, loop_body]}}
      container = {:container, :module, "Runner", %{}, [func]}
      doc = %Document{ast: container, language: :elixir, metadata: %{}}

      assert {:ok, meta} = Validator.validate(doc)
      assert meta.level == :extended
    end

    test "function_def with lambda in body" do
      lambda =
        {:lambda, ["x"], [],
         {:binary_op, :arithmetic, :*, {:variable, "x"}, {:literal, :integer, 2}}}

      body = {:function_call, "map", [lambda, {:variable, "list"}]}
      ast = {:function_def, :public, "double_all", ["list"], %{}, body}
      doc = %Document{ast: ast, language: :python, metadata: %{}}

      assert {:ok, meta} = Validator.validate(doc)
      assert meta.level == :extended
      assert MapSet.equal?(meta.variables, MapSet.new(["x", "list"]))
    end

    test "container with native construct in member" do
      native_construct = {:language_specific, :python, %{construct: :list_comprehension}}

      func = {:function_def, :public, "native_func", [], %{}, native_construct}
      container = {:container, :class, "Mixed", %{}, [func]}
      doc = %Document{ast: container, language: :python, metadata: %{}}

      assert {:ok, meta} = Validator.validate(doc)
      assert meta.level == :native
      assert meta.native_constructs == 1
      assert Enum.member?(meta.warnings, {:native_constructs_present, 1})
    end

    test "structural with native fails strict mode" do
      native_construct = {:language_specific, :python, %{construct: :decorator}}
      func = {:function_def, :public, "func", [], %{}, native_construct}
      container = {:container, :module, "Module", %{}, [func]}
      doc = %Document{ast: container, language: :python, metadata: %{}}

      assert {:error, :native_constructs_not_allowed} = Validator.validate(doc, mode: :strict)
    end
  end

  describe "validation constraints" do
    test "respects max_depth constraint" do
      # Create deeply nested structure
      deep_body =
        Enum.reduce(1..15, {:literal, :integer, 0}, fn _, acc ->
          {:conditional, {:variable, "x"}, acc, acc}
        end)

      ast = {:function_def, :public, "deep", ["x"], %{}, deep_body}
      doc = %Document{ast: ast, language: :python, metadata: %{}}

      assert {:error, {:max_depth_exceeded, _, _}} = Validator.validate(doc, max_depth: 10)
    end

    test "respects max_variables constraint" do
      # Create function with many variables
      params = Enum.map(1..15, fn i -> "var#{i}" end)
      body = {:literal, :integer, 0}
      ast = {:function_def, :public, "many_params", params, %{}, body}
      doc = %Document{ast: ast, language: :python, metadata: %{}}

      assert {:error, {:too_many_variables, _, _}} = Validator.validate(doc, max_variables: 10)
    end

    test "container with many members respects node count warnings" do
      # Create container with many function members
      members =
        Enum.map(1..1500, fn i ->
          {:function_def, :public, "func#{i}", [], %{}, {:literal, :integer, i}}
        end)

      container = {:container, :module, "Large", %{}, members}
      doc = %Document{ast: container, language: :elixir, metadata: %{}}

      assert {:ok, meta} = Validator.validate(doc)

      assert Enum.any?(meta.warnings, fn
               {:large_ast, _} -> true
               _ -> false
             end)
    end
  end

  describe "validate_ast/2 with structural types" do
    test "validates container AST directly" do
      ast = {:container, :module, "Math", %{}, []}

      assert {:ok, meta} = Validator.validate_ast(ast)
      assert meta.level == :extended
    end

    test "validates function_def AST directly" do
      ast = {:function_def, :public, "add", ["x", "y"], %{}, {:variable, "x"}}

      assert {:ok, meta} = Validator.validate_ast(ast)
      assert meta.level == :extended
    end

    test "validates property AST directly" do
      getter = {:function_def, :public, "x", [], %{}, {:variable, "_x"}}
      ast = {:property, "x", getter, nil, %{}}

      assert {:ok, meta} = Validator.validate_ast(ast)
      assert meta.level == :extended
    end
  end

  describe "valid?/2 helper with structural types" do
    test "returns true for valid container" do
      ast = {:container, :module, "Math", %{}, []}
      doc = %Document{ast: ast, language: :elixir, metadata: %{}}

      assert Validator.valid?(doc)
    end

    test "returns true for valid function_def" do
      ast = {:function_def, :public, "func", [], %{}, {:literal, :integer, 42}}
      doc = %Document{ast: ast, language: :python, metadata: %{}}

      assert Validator.valid?(doc)
    end

    test "returns false for invalid structural type" do
      ast = {:container, :invalid_type, "Name", %{}, []}
      doc = %Document{ast: ast, language: :python, metadata: %{}}

      refute Validator.valid?(doc)
    end
  end
end
