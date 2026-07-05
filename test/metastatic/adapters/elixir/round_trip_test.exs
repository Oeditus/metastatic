defmodule Metastatic.Adapters.Elixir.RoundTripTest do
  use ExUnit.Case, async: true

  alias Metastatic.{Adapters.Elixir.ToMeta, Builder}

  @moduledoc """
  Round-trip fidelity tests for the Elixir adapter.

  Each test verifies that `source -> M1 -> M2 -> M1 -> source` produces
  semantically equivalent Elixir code. Formatting differences (whitespace,
  newlines) are acceptable; semantic drift is not.
  """

  # Helper: round-trip through MetaAST and normalize whitespace for comparison.
  # Parses both original and round-tripped code, then compares ASTs.
  defp assert_round_trip(source) do
    assert {:ok, result} = Builder.round_trip(source, :elixir),
           "Round-trip failed for: #{source}"

    # Parse both to compare ASTs (ignoring metadata like line numbers)
    {:ok, original_ast} = Code.string_to_quoted(source)
    {:ok, result_ast} = Code.string_to_quoted(result)

    assert strip_meta(original_ast) == strip_meta(result_ast),
           """
           Semantic drift detected.
           Original:    #{source}
           Round-trip:  #{result}
           Original AST:  #{inspect(strip_meta(original_ast))}
           Result AST:    #{inspect(strip_meta(result_ast))}
           """

    result
  end

  # Strip all metadata from AST for structural comparison
  defp strip_meta(ast) do
    Macro.postwalk(ast, fn
      {form, _meta, args} when is_atom(form) -> {form, [], args}
      other -> other
    end)
  end

  # ---- P0.1: Module Attributes (assignment) ----

  describe "P0.1: module attribute round-trip" do
    test "@moduledoc false" do
      assert_round_trip("@moduledoc false")
    end

    test "@moduledoc with string" do
      assert_round_trip(~S|@moduledoc "A module"|)
    end

    test "@doc with string" do
      assert_round_trip(~S|@doc "A function"|)
    end

    test "@behaviour attribute" do
      assert_round_trip("@behaviour GenServer")
    end

    test "plain assignment" do
      assert_round_trip("x = 42")
    end

    test "destructuring assignment" do
      assert_round_trip("{a, b} = {1, 2}")
    end
  end

  # ---- P0.2: Guard Clauses ----

  describe "P0.2: guard clause round-trip" do
    test "simple guard with is_integer" do
      assert_round_trip("def foo(x) when is_integer(x), do: x")
    end

    test "guard with is_binary" do
      assert_round_trip("def greet(name) when is_binary(name), do: name")
    end

    test "compound guard with and" do
      assert_round_trip("def positive(x) when is_integer(x) and x > 0, do: x")
    end

    test "private function with guard" do
      assert_round_trip("defp bar(x) when is_atom(x), do: x")
    end
  end

  # ---- P0.3: Multi-clause Anonymous Functions ----

  describe "P0.3: multi-clause anonymous function round-trip" do
    test "simple multi-clause fn with atoms" do
      assert_round_trip("fn :a -> 1; :b -> 2 end")
    end

    test "multi-clause fn with variables" do
      assert_round_trip("fn 0 -> :zero; n -> n end")
    end

    test "single-clause fn" do
      assert_round_trip("fn x -> x + 1 end")
    end
  end

  # ---- P0.4: Exception Handling ----

  describe "P0.4: exception handling round-trip" do
    test "try/rescue with bare variable" do
      assert_round_trip("try do 1 / 0 rescue e -> e end")
    end

    test "try/rescue with exception type" do
      assert_round_trip("try do risky() rescue e in RuntimeError -> e end")
    end

    test "try/rescue/after" do
      assert_round_trip("try do risky() rescue e -> e after cleanup() end")
    end

    test "try with after only" do
      assert_round_trip("try do work() after cleanup() end")
    end
  end

  # ---- P1.4: Range Literals ----

  describe "P1.4: range literal round-trip" do
    test "simple range 1..10" do
      assert_round_trip("1..10")
    end

    test "range with step 1..10//2" do
      assert_round_trip("1..10//2")
    end

    test "range with variables" do
      assert_round_trip("a..b")
    end
  end

  # ---- P1.1: With Expressions ----

  describe "P1.1: with expression round-trip" do
    test "simple with two clauses" do
      assert_round_trip("with {:ok, a} <- fetch_a(), {:ok, b} <- fetch_b(), do: a + b")
    end

    test "with single clause" do
      assert_round_trip("with {:ok, x} <- get(), do: x")
    end
  end

  # ---- P1.2: Cond Expressions ----

  describe "P1.2: cond expression round-trip" do
    test "cond with three clauses" do
      assert_round_trip("cond do x > 0 -> :positive; x < 0 -> :negative; true -> :zero end")
    end

    test "cond with two clauses" do
      assert_round_trip("cond do x == 1 -> :one; true -> :other end")
    end
  end

  # ---- P1.3: String Interpolation ----

  describe "P1.3: string interpolation round-trip" do
    test "simple interpolation" do
      assert_round_trip(~S|"hello #{name}"|)
    end

    test "interpolation with expression" do
      assert_round_trip(~S|"result: #{x + 1}"|)
    end
  end

  # ---- Existing constructs (regression) ----

  describe "regression: existing round-trip constructs" do
    test "case expression" do
      assert_round_trip("case x do :a -> 1; :b -> 2 end")
    end

    test "if/else" do
      assert_round_trip("if true, do: 1, else: 2")
    end

    test "binary arithmetic" do
      assert_round_trip("x + 5")
    end

    test "function call" do
      assert_round_trip("foo(1, 2)")
    end

    test "list literal" do
      assert_round_trip("[1, 2, 3]")
    end

    test "map literal" do
      assert_round_trip("%{a: 1, b: 2}")
    end

    test "tuple literal" do
      assert_round_trip("{:ok, value}")
    end

    test "pattern match with =" do
      assert_round_trip("{:ok, result} = fetch()")
    end
  end

  # ---- P2.1: Range as dedicated type ----

  describe "P2.1: range type round-trip" do
    test "simple integer range" do
      assert_round_trip("1..10")
    end

    test "range with step" do
      assert_round_trip("1..10//2")
    end

    test "variable range" do
      assert_round_trip("start..stop")
    end

    test "range with variable step" do
      assert_round_trip("start..stop//step")
    end

    test "range in Enum.to_list" do
      assert_round_trip("Enum.to_list(1..5)")
    end
  end

  # ---- P2.2: String Interpolation as dedicated type ----

  describe "P2.2: string_interpolation type round-trip" do
    test "simple variable interpolation" do
      assert_round_trip(~S|"hello #{name}"|)
    end

    test "expression interpolation" do
      assert_round_trip(~S|"result: #{x + 1}"|)
    end

    test "multiple interpolations" do
      assert_round_trip(~S|"#{first} #{last}"|)
    end

    test "interpolation with function call" do
      assert_round_trip(~S|"count: #{length(items)}"|)
    end
  end

  # ---- P2.3: Comprehension as dedicated type ----

  describe "P2.3: comprehension type round-trip" do
    test "simple for comprehension" do
      assert_round_trip("for x <- [1, 2, 3], do: x * 2")
    end

    test "comprehension with filter" do
      assert_round_trip("for x <- [1, 2, 3], x > 1, do: x")
    end

    test "comprehension with multiple generators" do
      assert_round_trip("for x <- [1, 2], y <- [3, 4], do: {x, y}")
    end

    test "comprehension with pattern match generator" do
      assert_round_trip("for {:ok, x} <- results, do: x")
    end
  end

  # ---- P2.4: Type Annotation as dedicated type ----

  describe "P2.4: type_annotation round-trip" do
    test "@spec with single arg" do
      assert_round_trip("@spec foo(integer()) :: integer()")
    end

    test "@spec with multiple args" do
      assert_round_trip("@spec add(integer(), integer()) :: integer()")
    end

    test "@spec with no args" do
      assert_round_trip("@spec name() :: String.t()")
    end

    test "@type annotation" do
      assert_round_trip("@type name :: String.t()")
    end

    test "@callback annotation" do
      assert_round_trip("@callback handle(term()) :: :ok")
    end
  end

  # ---- P3.1: Variable scope metadata ----

  describe "P3.1: variable scope metadata" do
    test "local variables carry scope: :local" do
      {:ok, ast} = Code.string_to_quoted("x")
      {:ok, meta_ast, _} = ToMeta.transform(ast)
      assert {:variable, meta, "x"} = meta_ast
      assert Keyword.get(meta, :scope) == :local
    end

    test "module attribute getter carries scope: :module_attribute" do
      {:ok, ast} = Code.string_to_quoted("@timeout")
      {:ok, meta_ast, _} = ToMeta.transform(ast)
      assert {:variable, meta, "@timeout"} = meta_ast
      assert Keyword.get(meta, :scope) == :module_attribute
    end

    test "module attribute setter target carries scope: :module_attribute" do
      {:ok, ast} = Code.string_to_quoted("@timeout 5000")
      {:ok, meta_ast, _} = ToMeta.transform(ast)
      assert {:assignment, _meta, [{:variable, var_meta, "@timeout"}, _value]} = meta_ast
      assert Keyword.get(var_meta, :scope) == :module_attribute
    end

    test "local variable round-trip" do
      assert_round_trip("x = 42")
    end

    test "module attribute round-trip" do
      assert_round_trip("@moduledoc false")
    end
  end

  # ---- P3.2: String operator category ----

  describe "P3.2: string operator category" do
    test "<> operator uses :string category" do
      {:ok, ast} = Code.string_to_quoted("a <> b")
      {:ok, meta_ast, _} = ToMeta.transform(ast)
      assert {:binary_op, meta, _children} = meta_ast
      assert Keyword.get(meta, :category) == :string
      assert Keyword.get(meta, :operator) == :<>
    end

    test "string concatenation round-trip" do
      assert_round_trip(~s|"hello" <> " world"|)
    end

    test "variable string concatenation round-trip" do
      assert_round_trip("prefix <> suffix")
    end
  end
end
