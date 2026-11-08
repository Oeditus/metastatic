defmodule Metastatic.Adapters.JavaTest do
  @moduledoc """
  Behavioural tests for the Java adapter.

  Java is parsed by the JDK's own tree API through a subprocess bridge, so the
  whole module is tagged `:java` and skips when no `java` executable is
  available. The structural contract (callbacks, extensions, discovery) is
  covered unconditionally by `Metastatic.AdapterContractTest`.
  """
  use ExUnit.Case, async: false

  alias Metastatic.Adapter
  alias Metastatic.Adapters.Java
  alias Metastatic.Adapters.Java.{FromMeta, Subprocess}
  alias Metastatic.AST
  alias Metastatic.Document

  @moduletag :java

  if Subprocess.java_executable() == nil do
    @moduletag skip: "no JDK available (install a JDK 11+ to run the Java adapter tests)"
  end

  describe "parse/1" do
    test "parses a class declaration" do
      assert {:ok, ast} = Java.parse("class Foo { }")
      assert ast["kind"] == "COMPILATION_UNIT"
      assert [%{"kind" => "CLASS", "name" => "Foo"}] = ast["types"]
    end

    test "parses a method with parameters" do
      source = """
      class Calc {
          int add(int a, int b) { return a + b; }
      }
      """

      assert {:ok, ast} = Java.parse(source)
      [class] = ast["types"]
      [method] = class["members"]

      assert method["kind"] == "METHOD"
      assert method["name"] == "add"
      assert [_, _] = method["params"]
    end

    test "parses imports and package" do
      source = """
      package com.example.app;

      import java.util.List;

      class Foo { }
      """

      assert {:ok, ast} = Java.parse(source)

      assert %{
               "kind" => "MEMBER_SELECT",
               "name" => "app",
               "expr" => %{
                 "name" => "example",
                 "expr" => %{"kind" => "IDENTIFIER", "name" => "com"}
               }
             } = ast["package"]

      assert [%{"kind" => "IMPORT"}] = ast["imports"]
    end

    test "reports syntax errors with a line number" do
      assert {:error, reason} = Java.parse("class {")
      assert is_binary(reason)
      assert reason =~ "line"
    end

    test "reports a missing JDK instead of raising" do
      previous = Map.take(System.get_env(), ["PATH", "JAVA_HOME", "HOME"])

      System.put_env(%{
        "PATH" => "/nonexistent",
        "JAVA_HOME" => "/nonexistent",
        "HOME" => "/nonexistent"
      })

      try do
        assert {:error, reason} = Subprocess.parse("class A {}")
        assert reason =~ "Java parser unavailable" or reason =~ "java"
      after
        for key <- ["PATH", "JAVA_HOME", "HOME"] do
          case previous[key] do
            nil -> System.delete_env(key)
            value -> System.put_env(key, value)
          end
        end
      end
    end
  end

  describe "to_meta/1" do
    test "maps literals and variables" do
      {:ok, ast} = Java.parse("class A { int f() { return 42; } }")
      {:ok, meta_ast, _meta} = Java.to_meta(ast)

      assert AST.conforms?(meta_ast)
      assert contains_node?(meta_ast, {:literal, [subtype: :integer], 42})
    end

    test "maps a class to a :container and a method to :function_def" do
      {:ok, ast} = Java.parse("class Greeter { String hello() { return \"hi\"; } }")
      {:ok, meta_ast, _meta} = Java.to_meta(ast)

      assert {:container, container_meta, body} = find_node(meta_ast, :container)
      assert container_meta[:name] == "Greeter"
      assert container_meta[:container_type] == :class

      assert {:function_def, func_meta, _body} = find_node(body, :function_def)
      assert func_meta[:name] == "hello"
      assert func_meta[:arity] == 0
      assert func_meta[:visibility] == :public
    end

    test "maps visibility modifiers" do
      {:ok, ast} = Java.parse("class A { private int secret() { return 1; } }")
      {:ok, meta_ast, _meta} = Java.to_meta(ast)

      assert {:function_def, meta, _} = find_node(meta_ast, :function_def)
      assert meta[:visibility] == :private
    end

    test "maps method invocations to :function_call with a qualified name" do
      source = """
      class A {
          void f() { System.out.println("hi"); }
      }
      """

      {:ok, ast} = Java.parse(source)
      {:ok, meta_ast, _meta} = Java.to_meta(ast)

      assert {:function_call, meta, _args} = find_node(meta_ast, :function_call)
      assert meta[:name] == "System.out.println"
    end

    test "maps a constructor call to a constructor :function_call" do
      {:ok, ast} = Java.parse("class A { Object f() { return new StringBuilder(); } }")
      {:ok, meta_ast, _meta} = Java.to_meta(ast)

      assert {:function_call, meta, _} = find_node(meta_ast, :function_call)
      assert meta[:constructor] == true
      assert meta[:name] == "StringBuilder"
    end

    test "maps control flow" do
      source = """
      class A {
          int f(int x) {
              if (x > 0) { return 1; }
              while (x < 10) { x = x + 1; }
              return 0;
          }
      }
      """

      {:ok, ast} = Java.parse(source)
      {:ok, meta_ast, _meta} = Java.to_meta(ast)

      assert {:conditional, _, _} = find_node(meta_ast, :conditional)
      assert {:loop, loop_meta, _} = find_node(meta_ast, :loop)
      assert loop_meta[:loop_type] == :while
    end

    test "maps unary operators to portable nodes" do
      assert {:ok, ast} = Java.parse("class A { boolean f(boolean x) { return !x; } }")
      assert {:ok, meta_ast, _metadata} = Java.to_meta(ast)

      assert {:unary_op, metadata, [{:variable, _, "x"}]} = find_node(meta_ast, :unary_op)
      assert metadata[:category] == :boolean
      assert metadata[:operator] == :not
    end

    test "maps try/catch to :exception_handling" do
      source = """
      class A {
          void f() {
              try { throw new RuntimeException(); }
              catch (RuntimeException e) { }
          }
      }
      """

      {:ok, ast} = Java.parse(source)
      {:ok, meta_ast, _meta} = Java.to_meta(ast)

      assert {:exception_handling, _, _} = find_node(meta_ast, :exception_handling)
      assert {:throw, _, _} = find_node(meta_ast, :throw)
    end

    test "maps enhanced for loops to :for_each" do
      source = """
      class A {
          void f(int[] xs) { for (int x : xs) { } }
      }
      """

      {:ok, ast} = Java.parse(source)
      {:ok, meta_ast, _meta} = Java.to_meta(ast)

      assert {:loop, meta, _} = find_node(meta_ast, :loop)
      assert meta[:loop_type] == :for_each
    end

    test "maps lambdas" do
      source = """
      class A {
          Runnable f() { return () -> System.out.println("hi"); }
      }
      """

      {:ok, ast} = Java.parse(source)
      {:ok, meta_ast, _meta} = Java.to_meta(ast)

      assert {:lambda, _, _} = find_node(meta_ast, :lambda)
    end

    test "keeps unsupported constructs in :language_specific" do
      source = """
      class A {
          boolean f(Object o) { return o instanceof String; }
      }
      """

      {:ok, ast} = Java.parse(source)
      {:ok, meta_ast, _meta} = Java.to_meta(ast)

      assert {:language_specific, meta, _} = find_node(meta_ast, :language_specific)
      assert meta[:language] == :java
      assert meta[:hint] == :instance_of
    end

    test "an empty class produces a conforming MetaAST" do
      {:ok, ast} = Java.parse("class Empty { }")
      {:ok, meta_ast, _meta} = Java.to_meta(ast)
      assert AST.conforms?(meta_ast)
    end
  end

  describe "from_meta/2" do
    test "reifies a simple expression into compilable source" do
      meta_ast =
        {:binary_op, [category: :arithmetic, operator: :+],
         [{:literal, [subtype: :integer], 1}, {:literal, [subtype: :integer], 2}]}

      assert {:ok, %{"source" => source}} = FromMeta.transform(meta_ast, %{})
      assert source =~ "1 + 2"
      assert {:ok, _ast} = Java.parse(source)
    end

    test "reifies a container with a method" do
      meta_ast =
        {:container, [container_type: :class, name: "Greeter"],
         [
           {:function_def, [name: "hello", params: [], return_type: "String"],
            [
              {:early_return, [kind: :return], [{:literal, [subtype: :string], "hi"}]}
            ]}
         ]}

      assert {:ok, %{"source" => source}} = FromMeta.transform(meta_ast, %{})
      assert source =~ "class Greeter"
      assert source =~ "String hello()"
      assert {:ok, _ast} = Java.parse(source)
    end

    test "refuses constructs with no Java analogue" do
      assert {:error, reason} = FromMeta.transform({:pipe, [], []}, %{})
      assert reason =~ "Unsupported MetaAST construct"
    end
  end

  describe "round trip" do
    test "class with a method survives Source -> M2 -> Source" do
      source = """
      class Calc {
          int add(int a, int b) {
              return a + b;
          }
      }
      """

      {:ok, ast} = Java.parse(source)
      {:ok, meta_ast, metadata} = Java.to_meta(ast)
      {:ok, %{"source" => regenerated}} = Java.from_meta(meta_ast, metadata)

      {:ok, ast2} = Java.parse(regenerated)
      {:ok, meta_ast2, _} = Java.to_meta(ast2)

      assert AST.canonicalize(meta_ast2) == AST.canonicalize(meta_ast)
    end

    test "arithmetic expression survives Source -> M2 -> Source" do
      {:ok, ast} = Java.parse("class A { int f() { return 2 * 3 + 4; } }")
      {:ok, meta_ast, metadata} = Java.to_meta(ast)
      {:ok, %{"source" => regenerated}} = Java.from_meta(meta_ast, metadata)

      {:ok, ast2} = Java.parse(regenerated)
      {:ok, meta_ast2, _} = Java.to_meta(ast2)

      assert AST.canonicalize(meta_ast2) == AST.canonicalize(meta_ast)
    end
  end

  describe "cross-language equivalence" do
    test "Java and Python agree on `1 + 2`" do
      {:ok, java} = Adapter.abstract(Java, "class A { int f() { return 1 + 2; } }", :java)

      {:ok, python} =
        Adapter.abstract(Metastatic.Adapters.Python, "x = 1 + 2", :python)

      java_expr = find_node(java.ast, :binary_op)
      python_expr = find_node(python.ast, :binary_op)

      assert AST.canonicalize(java_expr) == AST.canonicalize(python_expr)
    end

    test "Java and Elixir agree on `1 + 2`" do
      {:ok, java} = Adapter.abstract(Java, "class A { int f() { return 1 + 2; } }", :java)
      {:ok, elixir} = Adapter.abstract(Metastatic.Adapters.Elixir, "1 + 2", :elixir)

      assert AST.canonicalize(find_node(java.ast, :binary_op)) ==
               AST.canonicalize(find_node(elixir.ast, :binary_op))
    end
  end

  describe "document validation" do
    test "a parsed Java document passes MetaAST validation" do
      {:ok, ast} = Java.parse("class A { int f() { return 1; } }")
      {:ok, meta_ast, metadata} = Java.to_meta(ast)
      doc = Document.new(meta_ast, :java, metadata)

      assert {:ok, _} = Metastatic.Validator.validate(doc)
    end
  end

  # ----- Helpers -----

  defp find_node({type, _meta, _children} = node, type), do: node

  defp find_node({_type, _meta, children}, type) when is_list(children) do
    Enum.find_value(children, fn child -> find_node(child, type) end)
  end

  defp find_node({_type, meta, _value}, type) when is_list(meta) do
    # Metadata may carry nested nodes (e.g. :params); look there too.
    Enum.find_value(meta, fn
      {_key, value} when is_list(value) -> find_node(value, type)
      _ -> nil
    end)
  end

  defp find_node(list, type) when is_list(list) do
    Enum.find_value(list, fn child -> find_node(child, type) end)
  end

  defp find_node(_other, _type), do: nil

  defp contains_node?(ast, expected) do
    AST.canonicalize(ast) == AST.canonicalize(expected) or
      case ast do
        {_type, _meta, children} when is_list(children) ->
          Enum.any?(children, &contains_node?(&1, expected))

        _ ->
          false
      end
  end
end
