defmodule Metastatic.Analysis.Duplication.FingerprintStructuralTest do
  use ExUnit.Case, async: true

  alias Metastatic.Analysis.Duplication.Fingerprint

  describe "exact fingerprints for structural types" do
    test "container with same name and structure produces same fingerprint" do
      ast1 = {:container, :module, "Math", nil, [], [], []}
      ast2 = {:container, :module, "Math", nil, [], [], []}

      assert Fingerprint.exact(ast1) == Fingerprint.exact(ast2)
    end

    test "container with different name produces different fingerprint" do
      ast1 = {:container, :module, "Math", nil, [], [], []}
      ast2 = {:container, :module, "Calc", nil, [], [], []}

      refute Fingerprint.exact(ast1) == Fingerprint.exact(ast2)
    end

    test "function_def with same signature produces same fingerprint" do
      ast1 = {:function_def, "add", ["x", "y"], nil, %{visibility: :public}, {:variable, "x"}}
      ast2 = {:function_def, "add", ["x", "y"], nil, %{visibility: :public}, {:variable, "x"}}

      assert Fingerprint.exact(ast1) == Fingerprint.exact(ast2)
    end

    test "function_def with different visibility produces different fingerprint" do
      ast1 = {:function_def, "add", ["x", "y"], nil, %{visibility: :public}, {:variable, "x"}}
      ast2 = {:function_def, "add", ["x", "y"], nil, %{visibility: :private}, {:variable, "x"}}

      refute Fingerprint.exact(ast1) == Fingerprint.exact(ast2)
    end

    test "attribute_access with same structure produces same fingerprint" do
      ast1 = {:attribute_access, {:variable, "obj"}, "field"}
      ast2 = {:attribute_access, {:variable, "obj"}, "field"}

      assert Fingerprint.exact(ast1) == Fingerprint.exact(ast2)
    end

    test "augmented_assignment with same operator produces same fingerprint" do
      ast1 = {:augmented_assignment, :+, {:variable, "x"}, {:literal, :integer, 5}}
      ast2 = {:augmented_assignment, :+, {:variable, "x"}, {:literal, :integer, 5}}

      assert Fingerprint.exact(ast1) == Fingerprint.exact(ast2)
    end

    test "property with same getters produces same fingerprint" do
      getter = {:function_def, "name", [], nil, %{visibility: :public}, {:variable, "@name"}}
      ast1 = {:property, "name", getter, nil, %{}}
      ast2 = {:property, "name", getter, nil, %{}}

      assert Fingerprint.exact(ast1) == Fingerprint.exact(ast2)
    end
  end

  describe "normalized fingerprints for structural types" do
    test "containers with different names produce same normalized fingerprint" do
      ast1 = {:container, :module, "Math", nil, [], [], []}
      ast2 = {:container, :module, "Calculator", nil, [], [], []}

      assert Fingerprint.normalized(ast1) == Fingerprint.normalized(ast2)
    end

    test "containers with same type and members structure produce same fingerprint" do
      func1 = {:function_def, "add", ["x", "y"], nil, %{visibility: :public}, {:variable, "x"}}
      func2 = {:function_def, "sum", ["a", "b"], nil, %{visibility: :public}, {:variable, "a"}}

      ast1 = {:container, :module, "Math", nil, [], [], [func1]}
      ast2 = {:container, :module, "Calc", nil, [], [], [func2]}

      assert Fingerprint.normalized(ast1) == Fingerprint.normalized(ast2)
    end

    test "function_defs with different names produce same normalized fingerprint" do
      ast1 = {:function_def, "add", ["x", "y"], nil, %{visibility: :public}, {:variable, "x"}}
      ast2 = {:function_def, "sum", ["a", "b"], nil, %{visibility: :public}, {:variable, "a"}}

      assert Fingerprint.normalized(ast1) == Fingerprint.normalized(ast2)
    end

    test "function_defs with different visibilities produce different fingerprints" do
      ast1 = {:function_def, "add", ["x"], nil, %{visibility: :public}, {:variable, "x"}}
      ast2 = {:function_def, "add", ["x"], nil, %{visibility: :private}, {:variable, "x"}}

      refute Fingerprint.normalized(ast1) == Fingerprint.normalized(ast2)
    end

    test "function_defs with pattern parameters normalize correctly" do
      ast1 =
        {:function_def, "first", [{:pattern, {:tuple, [{:variable, "x"}, :_]}}], nil,
         %{visibility: :public}, {:variable, "x"}}

      ast2 =
        {:function_def, "get", [{:pattern, {:tuple, [{:variable, "a"}, :_]}}], nil,
         %{visibility: :public}, {:variable, "a"}}

      assert Fingerprint.normalized(ast1) == Fingerprint.normalized(ast2)
    end

    test "function_defs with default parameters normalize correctly" do
      ast1 =
        {:function_def, "greet", [{:default, "name", {:literal, :string, "World"}}], nil,
         %{visibility: :public}, {:variable, "name"}}

      ast2 =
        {:function_def, "hello", [{:default, "who", {:literal, :string, "User"}}], nil,
         %{visibility: :public}, {:variable, "who"}}

      assert Fingerprint.normalized(ast1) == Fingerprint.normalized(ast2)
    end

    test "attribute_access with different attributes produce same fingerprint" do
      ast1 = {:attribute_access, {:variable, "user"}, "name"}
      ast2 = {:attribute_access, {:variable, "person"}, "email"}

      assert Fingerprint.normalized(ast1) == Fingerprint.normalized(ast2)
    end

    test "chained attribute_access normalize correctly" do
      ast1 =
        {:attribute_access, {:attribute_access, {:variable, "user"}, "profile"}, "name"}

      ast2 =
        {:attribute_access, {:attribute_access, {:variable, "obj"}, "data"}, "value"}

      assert Fingerprint.normalized(ast1) == Fingerprint.normalized(ast2)
    end

    test "augmented_assignments with same operator produce same fingerprint" do
      ast1 = {:augmented_assignment, :+, {:variable, "x"}, {:literal, :integer, 5}}
      ast2 = {:augmented_assignment, :+, {:variable, "count"}, {:literal, :integer, 10}}

      assert Fingerprint.normalized(ast1) == Fingerprint.normalized(ast2)
    end

    test "augmented_assignments with different operators produce different fingerprints" do
      ast1 = {:augmented_assignment, :+, {:variable, "x"}, {:literal, :integer, 5}}
      ast2 = {:augmented_assignment, :*, {:variable, "x"}, {:literal, :integer, 5}}

      refute Fingerprint.normalized(ast1) == Fingerprint.normalized(ast2)
    end

    test "properties with different names produce same fingerprint" do
      getter1 =
        {:function_def, "temperature", [], nil, %{visibility: :public}, {:variable, "_temp"}}

      getter2 = {:function_def, "value", [], nil, %{visibility: :public}, {:variable, "_val"}}

      ast1 = {:property, "temperature", getter1, nil, %{}}
      ast2 = {:property, "value", getter2, nil, %{}}

      assert Fingerprint.normalized(ast1) == Fingerprint.normalized(ast2)
    end

    test "properties with getter and setter normalize correctly" do
      getter = {:function_def, "x", [], nil, %{visibility: :public}, {:variable, "_x"}}

      setter =
        {:function_def, "x", ["v"], nil, %{visibility: :public},
         {:assignment, {:variable, "_x"}, {:variable, "v"}}}

      ast1 = {:property, "x", getter, setter, %{}}
      ast2 = {:property, "y", getter, setter, %{}}

      assert Fingerprint.normalized(ast1) == Fingerprint.normalized(ast2)
    end
  end

  describe "tokens extraction for structural types" do
    test "container tokens include type and member tokens" do
      func = {:function_def, "add", [], nil, %{visibility: :public}, {:literal, :integer, 0}}
      ast = {:container, :module, "Math", nil, [], [], [func]}

      tokens = Fingerprint.tokens(ast)

      assert :container in tokens
      assert :module in tokens
      assert :function_def in tokens
      assert :public in tokens
    end

    test "function_def tokens include visibility and parameter tokens" do
      ast =
        {:function_def, "helper", ["x", "y"], nil, %{visibility: :private},
         {:binary_op, :arithmetic, :+, {:variable, "x"}, {:variable, "y"}}}

      tokens = Fingerprint.tokens(ast)

      assert :function_def in tokens
      assert :private in tokens
      assert :param in tokens
      assert :binary_op in tokens
    end

    test "function_def with pattern parameters includes pattern tokens" do
      ast =
        {:function_def, "first", [{:pattern, {:tuple, [{:variable, "x"}, :_]}}], nil,
         %{visibility: :public}, {:variable, "x"}}

      tokens = Fingerprint.tokens(ast)

      assert :function_def in tokens
      assert :pattern_param in tokens
      assert :tuple in tokens
    end

    test "function_def with default parameters includes default tokens" do
      ast =
        {:function_def, "greet", [{:default, "name", {:literal, :string, "World"}}], nil,
         %{visibility: :public}, {:variable, "name"}}

      tokens = Fingerprint.tokens(ast)

      assert :function_def in tokens
      assert :default_param in tokens
      assert :literal in tokens
    end

    test "attribute_access tokens" do
      ast = {:attribute_access, {:variable, "obj"}, "field"}

      tokens = Fingerprint.tokens(ast)

      assert :attribute_access in tokens
      assert :variable in tokens
    end

    test "augmented_assignment tokens include operator" do
      ast = {:augmented_assignment, :+, {:variable, "x"}, {:literal, :integer, 5}}

      tokens = Fingerprint.tokens(ast)

      assert :augmented_assignment in tokens
      assert :+ in tokens
      assert :variable in tokens
      assert :literal in tokens
    end

    test "property tokens include getter and setter tokens" do
      getter = {:function_def, "x", [], nil, %{visibility: :public}, {:variable, "_x"}}

      setter =
        {:function_def, "x", ["v"], nil, %{visibility: :public},
         {:assignment, {:variable, "_x"}, {:variable, "v"}}}

      ast = {:property, "x", getter, setter, %{}}

      tokens = Fingerprint.tokens(ast)

      assert :property in tokens
      assert :function_def in tokens
      assert :assignment in tokens
    end
  end

  describe "complex structural scenarios" do
    test "nested containers normalize correctly" do
      inner_func =
        {:function_def, "inner", [], nil, %{visibility: :public}, {:literal, :integer, 42}}

      inner_container = {:container, :class, "Inner", nil, [], [], [inner_func]}
      outer_container = {:container, :module, "Outer", nil, [], [], [inner_container]}

      inner_func2 =
        {:function_def, "method", [], nil, %{visibility: :public}, {:literal, :integer, 99}}

      inner_container2 = {:container, :class, "Nested", nil, [], [], [inner_func2]}
      outer_container2 = {:container, :module, "Parent", nil, [], [], [inner_container2]}

      assert Fingerprint.normalized(outer_container) ==
               Fingerprint.normalized(outer_container2)
    end

    test "class with multiple methods" do
      add = {:function_def, "add", ["x", "y"], nil, %{visibility: :public}, {:variable, "x"}}
      sub = {:function_def, "subtract", ["x", "y"], nil, %{visibility: :public}, {:variable, "x"}}
      class1 = {:container, :class, "Calculator", nil, [], [], [add, sub]}

      plus = {:function_def, "plus", ["a", "b"], nil, %{visibility: :public}, {:variable, "a"}}
      minus = {:function_def, "minus", ["a", "b"], nil, %{visibility: :public}, {:variable, "a"}}
      class2 = {:container, :class, "Math", nil, [], [], [plus, minus]}

      assert Fingerprint.normalized(class1) == Fingerprint.normalized(class2)
    end

    test "function with complex body containing structural types" do
      attr_access = {:attribute_access, {:variable, "self"}, "value"}

      aug_assign =
        {:augmented_assignment, :+, {:attribute_access, {:variable, "self"}, "count"},
         {:literal, :integer, 1}}

      body = {:block, [attr_access, aug_assign]}
      func1 = {:function_def, "process", [], nil, %{visibility: :public}, body}

      attr_access2 = {:attribute_access, {:variable, "this"}, "data"}

      aug_assign2 =
        {:augmented_assignment, :+, {:attribute_access, {:variable, "this"}, "total"},
         {:literal, :integer, 2}}

      body2 = {:block, [attr_access2, aug_assign2]}
      func2 = {:function_def, "update", [], nil, %{visibility: :public}, body2}

      assert Fingerprint.normalized(func1) == Fingerprint.normalized(func2)
    end
  end
end
