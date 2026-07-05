#!/usr/bin/env elixir

# Visualization of MetaAST tree structures
# Run from project root: elixir examples/shopping_cart/visualize_ast.exs

# Add project code to path
Code.prepend_path("_build/dev/lib/metastatic/ebin")

IO.puts("""

╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║           MetaAST Tree Visualization                          ║
║           Shopping Cart Example                               ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝

""")

defmodule TreeVisualizer do
  @moduledoc """
  Visualizes MetaAST structures as tree diagrams with detailed annotations.
  """

  alias Metastatic.{AST, Document, Validator}

  @doc """
  Prints a tree-style visualization of MetaAST with box drawing characters.
  """
  def visualize(ast, title \\ "MetaAST Tree") do
    IO.puts("\n" <> title)
    IO.puts(String.duplicate("=", String.length(title)))
    IO.puts("")
    print_tree(ast, "", true)

    # Print metadata
    if AST.conforms?(ast) do
      doc = Document.new(ast, :elixir)
      {:ok, meta} = Validator.validate(doc)

      IO.puts("\n")
      IO.puts("Metadata:")
      IO.puts("  Layer: #{meta.level}")
      IO.puts("  Depth: #{meta.depth}")
      IO.puts("  Nodes: #{meta.node_count}")
      IO.puts("  Variables: #{inspect(MapSet.to_list(meta.variables))}")

      if meta.warnings != [] do
        IO.puts("  Warnings: #{length(meta.warnings)}")
      end
    end

    IO.puts("")
  end

  defp print_tree(ast, prefix, is_last) do
    # Choose branch characters
    branch = if is_last, do: "└── ", else: "├── "
    extension = if is_last, do: "    ", else: "│   "

    case ast do
      {:literal, type, value} ->
        IO.puts("#{prefix}#{branch}Literal[#{type}]: #{inspect(value)}")

      {:variable, name} ->
        IO.puts("#{prefix}#{branch}Variable: \"#{name}\"")

      {:binary_op, category, op, left, right} ->
        IO.puts("#{prefix}#{branch}BinaryOp[#{category}]: #{op}")
        print_tree(left, prefix <> extension, false)
        print_tree(right, prefix <> extension, true)

      {:unary_op, category, op, operand} ->
        IO.puts("#{prefix}#{branch}UnaryOp[#{category}]: #{op}")
        print_tree(operand, prefix <> extension, true)

      {:function_call, name, args} ->
        IO.puts("#{prefix}#{branch}FunctionCall: #{name}")

        if args != [] do
          Enum.with_index(args, fn arg, idx ->
            is_last_arg = idx == length(args) - 1

            IO.puts(
              "#{prefix}#{extension}#{if is_last_arg, do: "└── ", else: "├── "}arg[#{idx}]:"
            )

            print_tree(
              arg,
              prefix <> extension <> if(is_last_arg, do: "    ", else: "│   "),
              true
            )
          end)
        end

      {:conditional, type, branches, default} ->
        IO.puts("#{prefix}#{branch}Conditional[#{type}]: #{length(branches)} branches")

        Enum.with_index(branches, fn {condition, body}, idx ->
          is_last_branch = idx == length(branches) - 1 and default == nil
          branch_prefix = prefix <> extension

          IO.puts("#{branch_prefix}#{if is_last_branch, do: "└── ", else: "├── "}Branch[#{idx}]:")

          condition_prefix = branch_prefix <> if is_last_branch, do: "    ", else: "│   "
          IO.puts("#{condition_prefix}├── condition:")
          print_tree(condition, condition_prefix <> "│   ", true)

          IO.puts("#{condition_prefix}└── body:")
          print_tree(body, condition_prefix <> "    ", true)
        end)

        if default != nil do
          IO.puts("#{prefix}#{extension}└── default:")
          print_tree(default, prefix <> extension <> "    ", true)
        end

      {:block, statements} ->
        IO.puts("#{prefix}#{branch}Block: #{length(statements)} statements")

        Enum.with_index(statements, fn stmt, idx ->
          is_last_stmt = idx == length(statements) - 1
          print_tree(stmt, prefix <> extension, is_last_stmt)
        end)

      {:collection_op, op, lambda, collection, initial} ->
        IO.puts("#{prefix}#{branch}CollectionOp[#{op}]")
        IO.puts("#{prefix}#{extension}├── lambda:")
        print_tree(lambda, prefix <> extension <> "│   ", true)
        IO.puts("#{prefix}#{extension}├── collection:")
        print_tree(collection, prefix <> extension <> "│   ", true)
        IO.puts("#{prefix}#{extension}└── initial:")
        print_tree(initial, prefix <> extension <> "    ", true)

      {:lambda, params, body} ->
        IO.puts("#{prefix}#{branch}Lambda: (#{Enum.join(params, ", ")})")
        print_tree(body, prefix <> extension, true)

      {:early_return, value} ->
        IO.puts("#{prefix}#{branch}EarlyReturn")
        print_tree(value, prefix <> extension, true)

      other ->
        IO.puts("#{prefix}#{branch}#{inspect(other)}")
    end
  end

  @doc """
  Compare two MetaAST structures side by side.
  """
  def compare(ast1, label1, ast2, label2) do
    IO.puts("\n")
    IO.puts("Comparison: #{label1} vs #{label2}")
    IO.puts(String.duplicate("=", 60))

    doc1 = Document.new(ast1, :elixir)
    {:ok, meta1} = Validator.validate(doc1)

    doc2 = Document.new(ast2, :elixir)
    {:ok, meta2} = Validator.validate(doc2)

    IO.puts("\n#{label1}:")

    IO.puts(
      "  Depth: #{meta1.depth}  |  Nodes: #{meta1.node_count}  |  Variables: #{MapSet.size(meta1.variables)}"
    )

    IO.puts("\n#{label2}:")

    IO.puts(
      "  Depth: #{meta2.depth}  |  Nodes: #{meta2.node_count}  |  Variables: #{MapSet.size(meta2.variables)}"
    )

    vars1 = meta1.variables
    vars2 = meta2.variables

    common = MapSet.intersection(vars1, vars2)
    unique1 = MapSet.difference(vars1, vars2)
    unique2 = MapSet.difference(vars2, vars1)

    IO.puts("\nVariable Analysis:")
    IO.puts("  Common: #{inspect(MapSet.to_list(common))}")

    if MapSet.size(unique1) > 0 do
      IO.puts("  Unique to #{label1}: #{inspect(MapSet.to_list(unique1))}")
    end

    if MapSet.size(unique2) > 0 do
      IO.puts("  Unique to #{label2}: #{inspect(MapSet.to_list(unique2))}")
    end

    IO.puts("")
  end
end

# Example visualizations

IO.puts("═" <> String.duplicate("═", 60))
IO.puts("  Example 1: Simple Stock Check")
IO.puts("═" <> String.duplicate("═", 60))

ast1 = {:binary_op, :comparison, :>=, {:variable, "stock"}, {:variable, "quantity"}}
TreeVisualizer.visualize(ast1, "stock >= quantity")

IO.puts("\n" <> String.duplicate("─", 62))

# Mutated version
ast1_mutant = {:binary_op, :comparison, :>, {:variable, "stock"}, {:variable, "quantity"}}
TreeVisualizer.visualize(ast1_mutant, "MUTANT: stock > quantity")

TreeVisualizer.compare(ast1, "Original", ast1_mutant, "Mutant")

IO.puts("\n\n")
IO.puts("═" <> String.duplicate("═", 60))
IO.puts("  Example 2: Multi-Step Price Calculation")
IO.puts("═" <> String.duplicate("═", 60))

ast2 =
  {:binary_op, :arithmetic, :-,
   {:binary_op, :arithmetic, :*, {:variable, "price"}, {:variable, "quantity"}},
   {:binary_op, :arithmetic, :*,
    {:binary_op, :arithmetic, :*, {:variable, "price"}, {:variable, "quantity"}},
    {:variable, "discount_rate"}}}

TreeVisualizer.visualize(ast2, "price * quantity - (price * quantity * discount_rate)")

IO.puts("\n\n")
IO.puts("═" <> String.duplicate("═", 60))
IO.puts("  Example 3: Conditional with Multiple Branches")
IO.puts("═" <> String.duplicate("═", 60))

branches = [
  {
    {:binary_op, :comparison, :>=, {:variable, "quantity"}, {:literal, :integer, 100}},
    {:literal, :float, 0.20}
  },
  {
    {:binary_op, :comparison, :>=, {:variable, "quantity"}, {:literal, :integer, 50}},
    {:literal, :float, 0.15}
  },
  {
    {:binary_op, :comparison, :>=, {:variable, "quantity"}, {:literal, :integer, 10}},
    {:literal, :float, 0.10}
  }
]

default = {:literal, :float, 0.0}
ast3 = {:conditional, :cond, branches, default}

TreeVisualizer.visualize(ast3, "Tiered Discount (cond)")

IO.puts("\n\n")
IO.puts("═" <> String.duplicate("═", 60))
IO.puts("  Example 4: Block with Multiple Statements")
IO.puts("═" <> String.duplicate("═", 60))

ast4 =
  {:block,
   [
     {:binary_op, :arithmetic, :*, {:variable, "price"}, {:variable, "quantity"}},
     {:binary_op, :arithmetic, :*,
      {:binary_op, :arithmetic, :*, {:variable, "price"}, {:variable, "quantity"}},
      {:variable, "discount_rate"}},
     {:binary_op, :arithmetic, :-,
      {:binary_op, :arithmetic, :*, {:variable, "price"}, {:variable, "quantity"}},
      {:variable, "discount"}}
   ]}

TreeVisualizer.visualize(ast4, "Price Calculation Block")

IO.puts("\n\n")
IO.puts("═" <> String.duplicate("═", 60))
IO.puts("  Example 5: Higher-Order Function (Collection Op)")
IO.puts("═" <> String.duplicate("═", 60))

lambda_body =
  {:binary_op, :arithmetic, :+, {:variable, "acc"},
   {:function_call, "calculate_price", [{:variable, "product"}, {:variable, "qty"}]}}

ast5 =
  {:collection_op, :reduce, {:lambda, ["item", "acc"], lambda_body}, {:variable, "items"},
   {:literal, :float, 0.0}}

TreeVisualizer.visualize(ast5, "Subtotal Calculation (reduce)")

IO.puts("\n\n")
IO.puts("═" <> String.duplicate("═", 60))
IO.puts("  Example 6: Nested Conditionals")
IO.puts("═" <> String.duplicate("═", 60))

inner_cond =
  {:conditional, :if,
   [
     {
       {:binary_op, :comparison, :>, {:variable, "stock"}, {:literal, :integer, 0}},
       {:literal, :atom, :ok}
     }
   ], {:literal, :atom, :error}}

outer_cond =
  {:conditional, :if,
   [
     {
       {:binary_op, :comparison, :>, {:variable, "quantity"}, {:literal, :integer, 0}},
       inner_cond
     }
   ], {:literal, :atom, :invalid}}

TreeVisualizer.visualize(outer_cond, "Nested Validation Checks")

IO.puts("\n\n")
IO.puts("═" <> String.duplicate("═", 60))
IO.puts("  Mutation Comparison Examples")
IO.puts("═" <> String.duplicate("═", 60))

IO.puts("\n")
IO.puts("Boundary Mutation: >= becomes >")
IO.puts(String.duplicate("-", 40))

original = {:binary_op, :comparison, :>=, {:variable, "x"}, {:literal, :integer, 10}}
boundary = {:binary_op, :comparison, :>, {:variable, "x"}, {:literal, :integer, 10}}
TreeVisualizer.compare(original, "x >= 10", boundary, "x > 10")

IO.puts("\n")
IO.puts("Arithmetic Mutation: + becomes -")
IO.puts(String.duplicate("-", 40))

add_op = {:binary_op, :arithmetic, :+, {:variable, "a"}, {:variable, "b"}}
sub_op = {:binary_op, :arithmetic, :-, {:variable, "a"}, {:variable, "b"}}
TreeVisualizer.compare(add_op, "a + b", sub_op, "a - b")

IO.puts("\n\n")
IO.puts("═" <> String.duplicate("═", 60))
IO.puts("  Summary")
IO.puts("═" <> String.duplicate("═", 60))

IO.puts("""

These visualizations demonstrate:

1. Tree Structure: MetaAST is a hierarchical tree of nodes
2. Node Types: Literals, variables, operators, conditionals, etc.
3. Metadata: Depth, node count, variables extracted automatically
4. Mutations: Small changes to operators create distinct mutants
5. Cross-Language: Same structure represents equivalent code in any language

Key Insights:

- Simple expressions (x >= y) have shallow trees (depth 2-3)
- Complex logic (nested conds) creates deeper trees (depth 5+)
- Variables are extracted automatically for dependency analysis
- Mutations change structure minimally but semantically significantly
- All languages map to these same fundamental structures

This enables universal tools: mutation testing, complexity analysis,
purity detection, and refactoring - all working at the MetaAST level,
independent of source language.

Next: Read examples/shopping_cart/README.md for detailed guide
      Run: elixir examples/shopping_cart/demo.exs for interactive demo

""")
