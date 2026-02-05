defmodule Metastatic.Analysis.Duplication.FingerprintStructuralTest do
  use ExUnit.Case, async: true

  alias Metastatic.Analysis.Duplication.Fingerprint

  # Helper functions for 3-tuple AST construction
  defp literal(subtype, value), do: {:literal, [subtype: subtype], value}
  defp variable(name), do: {:variable, [], name}

  defp binary_op(category, operator, left, right) do
    {:binary_op, [category: category, operator: operator], [left, right]}
  end

  defp assignment(target, value), do: {:assignment, [], [target, value]}

  defp container(type, name, body, opts \\ []) do
    {:container, [container_type: type, name: name] ++ opts, body}
  end

  defp function_def(name, params, body, opts) do
    {:function_def, [name: name, params: params] ++ opts, [body]}
  end

  defp attribute_access(attr, receiver) do
    {:attribute_access, [attribute: attr], [receiver]}
  end

  defp augmented_assignment(op, target, value) do
    {:augmented_assignment, [operator: op], [target, value]}
  end

  defp property(name, children, opts \\ []) do
    {:property, [name: name] ++ opts, children}
  end

  describe "exact fingerprints for structural types" do
    test "container with same name and structure produces same fingerprint" do
      ast1 = container(:module, "Math", [])
      ast2 = container(:module, "Math", [])

      assert Fingerprint.exact(ast1) == Fingerprint.exact(ast2)
    end

    test "container with different name produces different fingerprint" do
      ast1 = container(:module, "Math", [])
      ast2 = container(:module, "Calc", [])

      refute Fingerprint.exact(ast1) == Fingerprint.exact(ast2)
    end

    test "function_def with same signature produces same fingerprint" do
      ast1 = function_def("add", ["x", "y"], variable("x"), visibility: :public)
      ast2 = function_def("add", ["x", "y"], variable("x"), visibility: :public)

      assert Fingerprint.exact(ast1) == Fingerprint.exact(ast2)
    end

    test "function_def with different visibility produces different fingerprint" do
      ast1 = function_def("add", ["x", "y"], variable("x"), visibility: :public)
      ast2 = function_def("add", ["x", "y"], variable("x"), visibility: :private)

      refute Fingerprint.exact(ast1) == Fingerprint.exact(ast2)
    end

    test "attribute_access with same structure produces same fingerprint" do
      ast1 = attribute_access("field", variable("obj"))
      ast2 = attribute_access("field", variable("obj"))

      assert Fingerprint.exact(ast1) == Fingerprint.exact(ast2)
    end

    test "augmented_assignment with same operator produces same fingerprint" do
      ast1 = augmented_assignment(:+, variable("x"), literal(:integer, 5))
      ast2 = augmented_assignment(:+, variable("x"), literal(:integer, 5))

      assert Fingerprint.exact(ast1) == Fingerprint.exact(ast2)
    end

    test "property with same getters produces same fingerprint" do
      getter = function_def("name", [], variable("@name"), visibility: :public)
      ast1 = property("name", [getter, nil])
      ast2 = property("name", [getter, nil])

      assert Fingerprint.exact(ast1) == Fingerprint.exact(ast2)
    end
  end

  describe "normalized fingerprints for structural types" do
    test "containers with different names produce same normalized fingerprint" do
      ast1 = container(:module, "Math", [])
      ast2 = container(:module, "Calculator", [])

      assert Fingerprint.normalized(ast1) == Fingerprint.normalized(ast2)
    end

    test "containers with same type and members structure produce same fingerprint" do
      func1 = function_def("add", ["x", "y"], variable("x"), visibility: :public)
      func2 = function_def("sum", ["a", "b"], variable("a"), visibility: :public)

      ast1 = container(:module, "Math", [func1])
      ast2 = container(:module, "Calc", [func2])

      assert Fingerprint.normalized(ast1) == Fingerprint.normalized(ast2)
    end

    test "function_defs with different names produce same normalized fingerprint" do
      ast1 = function_def("add", ["x", "y"], variable("x"), visibility: :public)
      ast2 = function_def("sum", ["a", "b"], variable("a"), visibility: :public)

      assert Fingerprint.normalized(ast1) == Fingerprint.normalized(ast2)
    end

    test "function_defs with different visibilities produce different fingerprints" do
      ast1 = function_def("add", ["x"], variable("x"), visibility: :public)
      ast2 = function_def("add", ["x"], variable("x"), visibility: :private)

      refute Fingerprint.normalized(ast1) == Fingerprint.normalized(ast2)
    end

    test "function_defs with pattern parameters normalize correctly" do
      # With same body structure
      ast1 = function_def("first", ["x"], variable("x"), visibility: :public)
      ast2 = function_def("get", ["a"], variable("a"), visibility: :public)

      assert Fingerprint.normalized(ast1) == Fingerprint.normalized(ast2)
    end

    test "function_defs with default parameters normalize correctly" do
      # Functions with same param count normalize similarly
      ast1 = function_def("greet", ["name"], variable("name"), visibility: :public)
      ast2 = function_def("hello", ["who"], variable("who"), visibility: :public)

      assert Fingerprint.normalized(ast1) == Fingerprint.normalized(ast2)
    end

    test "attribute_access with different attributes produce same fingerprint" do
      ast1 = attribute_access("name", variable("user"))
      ast2 = attribute_access("email", variable("person"))

      assert Fingerprint.normalized(ast1) == Fingerprint.normalized(ast2)
    end

    test "chained attribute_access normalize correctly" do
      ast1 = attribute_access("name", attribute_access("profile", variable("user")))
      ast2 = attribute_access("value", attribute_access("data", variable("obj")))

      assert Fingerprint.normalized(ast1) == Fingerprint.normalized(ast2)
    end

    test "augmented_assignments with same operator produce same fingerprint" do
      ast1 = augmented_assignment(:+, variable("x"), literal(:integer, 5))
      ast2 = augmented_assignment(:+, variable("count"), literal(:integer, 10))

      assert Fingerprint.normalized(ast1) == Fingerprint.normalized(ast2)
    end

    test "augmented_assignments with different operators produce different fingerprints" do
      ast1 = augmented_assignment(:+, variable("x"), literal(:integer, 5))
      ast2 = augmented_assignment(:*, variable("x"), literal(:integer, 5))

      refute Fingerprint.normalized(ast1) == Fingerprint.normalized(ast2)
    end

    test "properties with different names produce same fingerprint" do
      getter1 = function_def("temperature", [], variable("_temp"), visibility: :public)
      getter2 = function_def("value", [], variable("_val"), visibility: :public)

      ast1 = property("temperature", [getter1, nil])
      ast2 = property("value", [getter2, nil])

      assert Fingerprint.normalized(ast1) == Fingerprint.normalized(ast2)
    end

    test "properties with getter and setter normalize correctly" do
      getter = function_def("x", [], variable("_x"), visibility: :public)

      setter =
        function_def("x", ["v"], assignment(variable("_x"), variable("v")), visibility: :public)

      ast1 = property("x", [getter, setter])
      ast2 = property("y", [getter, setter])

      assert Fingerprint.normalized(ast1) == Fingerprint.normalized(ast2)
    end
  end

  describe "tokens extraction for structural types" do
    test "container tokens include type and member tokens" do
      func = function_def("add", [], literal(:integer, 0), visibility: :public)
      ast = container(:module, "Math", [func])

      tokens = Fingerprint.tokens(ast)

      assert :container in tokens
      assert :module in tokens
      assert :function_def in tokens
      assert :public in tokens
    end

    test "function_def tokens include visibility and parameter tokens" do
      ast =
        function_def(
          "helper",
          ["x", "y"],
          binary_op(:arithmetic, :+, variable("x"), variable("y")),
          visibility: :private
        )

      tokens = Fingerprint.tokens(ast)

      assert :function_def in tokens
      assert :private in tokens
      assert :param in tokens
      assert :binary_op in tokens
    end

    test "attribute_access tokens" do
      ast = attribute_access("field", variable("obj"))
      tokens = Fingerprint.tokens(ast)

      assert :attribute_access in tokens
      assert :variable in tokens
    end

    test "augmented_assignment tokens" do
      ast = augmented_assignment(:+, variable("x"), literal(:integer, 5))
      tokens = Fingerprint.tokens(ast)

      assert :augmented_assignment in tokens
      assert :+ in tokens
      assert :variable in tokens
      assert :literal in tokens
    end

    test "property tokens" do
      getter = function_def("name", [], variable("_name"), visibility: :public)
      ast = property("name", [getter, nil])
      tokens = Fingerprint.tokens(ast)

      assert :property in tokens
      assert :function_def in tokens
    end
  end

  describe "complex structural scenarios" do
    test "class with methods produces deterministic fingerprint" do
      method1 =
        function_def("initialize", ["name"], assignment(variable("@name"), variable("name")),
          visibility: :public
        )

      method2 = function_def("greet", [], variable("@name"), visibility: :public)
      ast = container(:class, "Person", [method1, method2])

      fp1 = Fingerprint.exact(ast)
      fp2 = Fingerprint.exact(ast)

      assert fp1 == fp2
    end

    test "nested containers produce unique fingerprints" do
      inner = container(:class, "Inner", [])
      outer = container(:module, "Outer", [inner])

      tokens = Fingerprint.tokens(outer)

      assert :container in tokens
      assert :module in tokens
      assert :class in tokens
    end

    test "method with conditional body" do
      body =
        {:conditional, [],
         [
           variable("x"),
           literal(:integer, 1),
           literal(:integer, 0)
         ]}

      method = function_def("check", ["x"], body, visibility: :public)
      tokens = Fingerprint.tokens(method)

      assert :function_def in tokens
      assert :conditional in tokens
    end
  end
end
