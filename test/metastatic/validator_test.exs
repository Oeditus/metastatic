defmodule Metastatic.ValidatorTest do
  use ExUnit.Case, async: true

  alias Metastatic.{Document, Validator}

  doctest Metastatic.Validator

  describe "validate/2 with M2.1 Core" do
    test "validates literal" do
      doc = Document.new({:literal, :integer, 42}, :python)

      assert {:ok, meta} = Validator.validate(doc)
      assert meta.level == :core
      assert meta.native_constructs == 0
      assert meta.warnings == []
      assert meta.depth == 1
      assert meta.node_count == 1
    end

    test "validates binary operation" do
      ast = {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}}
      doc = Document.new(ast, :python)

      assert {:ok, meta} = Validator.validate(doc)
      assert meta.level == :core
      assert meta.variables == MapSet.new(["x"])
      assert meta.depth == 2
    end

    test "validates nested expression" do
      # (x + 5) * 2
      ast =
        {:binary_op, :arithmetic, :*,
         {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}},
         {:literal, :integer, 2}}

      doc = Document.new(ast, :python)

      assert {:ok, meta} = Validator.validate(doc)
      assert meta.level == :core
      assert meta.depth == 3
    end
  end

  describe "validate/2 with M2.2 Extended" do
    test "validates loop" do
      ast =
        {:loop, :while, {:binary_op, :comparison, :>, {:variable, "x"}, {:literal, :integer, 0}},
         {:block, [{:variable, "x"}]}}

      doc = Document.new(ast, :python)

      assert {:ok, meta} = Validator.validate(doc)
      assert meta.level == :extended
      assert meta.native_constructs == 0
    end

    test "validates lambda" do
      ast =
        {:lambda, ["x"], [],
         {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 1}}}

      doc = Document.new(ast, :python)

      assert {:ok, meta} = Validator.validate(doc)
      assert meta.level == :extended
    end

    test "validates collection operation" do
      ast =
        {:collection_op, :map,
         {:lambda, ["x"], [],
          {:binary_op, :arithmetic, :*, {:variable, "x"}, {:literal, :integer, 2}}},
         {:variable, "list"}}

      doc = Document.new(ast, :python)

      assert {:ok, meta} = Validator.validate(doc)
      assert meta.level == :extended
    end
  end

  describe "validate/2 with M2.3 Native" do
    test "validates language-specific construct" do
      ast =
        {:language_specific, :python,
         %{construct: :list_comprehension, data: "[x for x in range(10)]"}}

      doc = Document.new(ast, :python)

      assert {:ok, meta} = Validator.validate(doc)
      assert meta.level == :native
      assert meta.native_constructs == 1
      assert {:native_constructs_present, 1} in meta.warnings
    end

    test "counts multiple native constructs" do
      ast =
        {:block,
         [
           {:language_specific, :python, %{construct: :decorator, data: "@property"}},
           {:language_specific, :python, %{construct: :walrus, data: ":="}}
         ]}

      doc = Document.new(ast, :python)

      assert {:ok, meta} = Validator.validate(doc)
      assert meta.level == :native
      assert meta.native_constructs == 2
    end
  end

  describe "validate/2 with validation modes" do
    test "strict mode rejects native constructs" do
      ast =
        {:language_specific, :python, %{construct: :list_comprehension, data: "..."}}

      doc = Document.new(ast, :python)

      assert {:error, :native_constructs_not_allowed} = Validator.validate(doc, mode: :strict)
    end

    test "strict mode accepts core constructs" do
      doc = Document.new({:literal, :integer, 42}, :python)

      assert {:ok, _} = Validator.validate(doc, mode: :strict)
    end

    test "strict mode accepts extended constructs" do
      ast = {:lambda, ["x"], [], {:variable, "x"}}
      doc = Document.new(ast, :python)

      assert {:ok, _} = Validator.validate(doc, mode: :strict)
    end

    test "standard mode accepts native constructs with warning" do
      ast =
        {:language_specific, :python, %{construct: :list_comprehension, data: "..."}}

      doc = Document.new(ast, :python)

      assert {:ok, meta} = Validator.validate(doc, mode: :standard)
      assert {:native_constructs_present, 1} in meta.warnings
    end

    test "permissive mode accepts everything" do
      ast =
        {:language_specific, :python, %{construct: :list_comprehension, data: "..."}}

      doc = Document.new(ast, :python)

      assert {:ok, _} = Validator.validate(doc, mode: :permissive)
    end
  end

  describe "validate/2 with constraints" do
    test "enforces max depth" do
      # Create deeply nested expression
      ast =
        Enum.reduce(1..15, {:literal, :integer, 0}, fn _, acc ->
          {:binary_op, :arithmetic, :+, acc, {:literal, :integer, 1}}
        end)

      doc = Document.new(ast, :python)

      assert {:error, {:max_depth_exceeded, depth, 10}} = Validator.validate(doc, max_depth: 10)
      assert depth > 10
    end

    test "enforces max variables" do
      # Create AST with many variables
      variables = for i <- 1..15, do: {:variable, "x#{i}"}
      ast = {:block, variables}

      doc = Document.new(ast, :python)

      assert {:error, {:too_many_variables, count, 10}} =
               Validator.validate(doc, max_variables: 10)

      assert count > 10
    end

    test "accepts within constraints" do
      ast = {:binary_op, :arithmetic, :+, {:variable, "x"}, {:variable, "y"}}
      doc = Document.new(ast, :python)

      assert {:ok, _} = Validator.validate(doc, max_depth: 10, max_variables: 10)
    end
  end

  describe "validate/2 warnings" do
    test "warns on deep nesting" do
      # Create expression with depth > 100
      ast =
        Enum.reduce(1..105, {:literal, :integer, 0}, fn _, acc ->
          {:binary_op, :arithmetic, :+, acc, {:literal, :integer, 1}}
        end)

      doc = Document.new(ast, :python)

      assert {:ok, meta} = Validator.validate(doc)
      assert Enum.any?(meta.warnings, &match?({:deep_nesting, _}, &1))
    end

    test "warns on large AST" do
      # Create AST with > 1000 nodes
      large_block = for i <- 1..1100, do: {:literal, :integer, i}
      ast = {:block, large_block}

      doc = Document.new(ast, :python)

      assert {:ok, meta} = Validator.validate(doc)
      assert Enum.any?(meta.warnings, &match?({:large_ast, _}, &1))
    end

    test "no warnings for simple AST" do
      doc = Document.new({:literal, :integer, 42}, :python)

      assert {:ok, meta} = Validator.validate(doc)
      assert meta.warnings == []
    end
  end

  describe "validate/2 invalid structures" do
    test "rejects invalid meta-type" do
      doc = %Document{
        ast: {:invalid_type, "data"},
        language: :python,
        metadata: %{}
      }

      assert {:error, {:invalid_structure, _}} = Validator.validate(doc)
    end

    test "rejects malformed binary_op" do
      doc = %Document{
        ast: {:binary_op, :+, {:variable, "x"}},
        language: :python,
        metadata: %{}
      }

      assert {:error, {:invalid_structure, _}} = Validator.validate(doc)
    end
  end

  describe "valid?/2" do
    test "returns true for valid document" do
      doc = Document.new({:literal, :integer, 42}, :python)

      assert Validator.valid?(doc)
    end

    test "returns false for invalid document" do
      doc = %Document{
        ast: {:invalid_type, "bad"},
        language: :python,
        metadata: %{}
      }

      refute Validator.valid?(doc)
    end
  end

  describe "validate_ast/2" do
    test "validates AST directly without Document wrapper" do
      ast = {:literal, :integer, 42}

      assert {:ok, meta} = Validator.validate_ast(ast)
      assert meta.level == :core
    end

    test "rejects invalid AST" do
      ast = {:invalid_type, "bad"}

      assert {:error, {:invalid_structure, _}} = Validator.validate_ast(ast)
    end
  end
end
