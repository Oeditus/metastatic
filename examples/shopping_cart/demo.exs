#!/usr/bin/env elixir

# Interactive demonstration of metastatic's MetaAST capabilities
# Run from project root: elixir examples/shopping_cart/demo.exs

# Add project code to path
Code.prepend_path("_build/dev/lib/metastatic/ebin")

IO.puts("""

╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║           metastatic - MetaAST Demonstration                  ║
║           Shopping Cart Example                               ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝

This demo shows how metastatic transforms Elixir code into
universal MetaAST representation that can power cross-language tools.

""")

# Since we're in Phase 1, we don't have language adapters yet.
# This demo will manually construct MetaAST to show what they look like.

defmodule Demo do
  alias Metastatic.{AST, Document, Validator}

  def section(title) do
    IO.puts("\n")
    IO.puts("═" <> String.duplicate("═", 60))
    IO.puts("  #{title}")
    IO.puts("═" <> String.duplicate("═", 60))
    IO.puts("")
  end

  def subsection(title) do
    IO.puts("\n#{title}")
    IO.puts(String.duplicate("-", String.length(title)))
  end

  def print_ast(ast, indent \\ 0) do
    prefix = String.duplicate("  ", indent)

    case ast do
      {:literal, type, value} ->
        IO.puts("#{prefix}Literal(#{type}): #{inspect(value)}")

      {:variable, name} ->
        IO.puts("#{prefix}Variable: #{name}")

      {:binary_op, category, op, left, right} ->
        IO.puts("#{prefix}BinaryOp(#{category}): #{op}")
        IO.puts("#{prefix}├─ left:")
        print_ast(left, indent + 1)
        IO.puts("#{prefix}└─ right:")
        print_ast(right, indent + 1)

      {:unary_op, category, op, operand} ->
        IO.puts("#{prefix}UnaryOp(#{category}): #{op}")
        IO.puts("#{prefix}└─ operand:")
        print_ast(operand, indent + 1)

      {:function_call, name, args} ->
        IO.puts("#{prefix}FunctionCall: #{name}")
        IO.puts("#{prefix}└─ args: #{length(args)} argument(s)")

      {:conditional, type, branches, default} ->
        IO.puts("#{prefix}Conditional(#{type}): #{length(branches)} branches")

      {:block, statements} ->
        IO.puts("#{prefix}Block: #{length(statements)} statement(s)")

      other ->
        IO.puts("#{prefix}#{inspect(other)}")
    end
  end

  def demo_simple_comparison do
    section("Example 1: Simple Comparison (Stock Check)")

    IO.puts("""
    Original Elixir code:

        stock >= quantity

    This is a fundamental operation in Product.available?/2
    """)

    ast = {:binary_op, :comparison, :>=, {:variable, "stock"}, {:variable, "quantity"}}

    subsection("MetaAST Representation:")
    print_ast(ast)

    subsection("Properties:")
    IO.puts("  Conforms to MetaAST? #{AST.conforms?(ast)}")
    variables = AST.variables(ast)
    IO.puts("  Variables used: #{inspect(MapSet.to_list(variables))}")

    doc = Document.new(ast, :elixir)
    {:ok, meta} = Validator.validate(doc)

    IO.puts("  MetaAST layer: #{meta.level}")
    IO.puts("  Tree depth: #{meta.depth}")
    IO.puts("  Node count: #{meta.node_count}")

    subsection("Cross-Language Equivalent:")

    IO.puts("""
      Python:   stock >= quantity
      JavaScript: stock >= quantity
      Ruby:     stock >= quantity
      Go:       stock >= quantity
      Rust:     stock >= quantity

    All map to the SAME MetaAST node!
    """)
  end

  def demo_arithmetic_expression do
    section("Example 2: Arithmetic Expression (Price Calculation)")

    IO.puts("""
    Original Elixir code:

        base_price = price * quantity
        discount = base_price * discount_rate
        base_price - discount

    Multi-step calculation from Product.calculate_price/2
    """)

    # price * quantity
    multiplication =
      {:binary_op, :arithmetic, :*, {:variable, "price"}, {:variable, "quantity"}}

    # base_price * discount_rate
    discount_calc =
      {:binary_op, :arithmetic, :*, {:variable, "base_price"}, {:variable, "discount_rate"}}

    # base_price - discount
    final_calc = {:binary_op, :arithmetic, :-, {:variable, "base_price"}, {:variable, "discount"}}

    subsection("MetaAST: price * quantity")
    print_ast(multiplication)

    subsection("MetaAST: base_price - discount")
    print_ast(final_calc)

    variables = AST.variables(final_calc)
    IO.puts("\n  Variables in expression: #{inspect(MapSet.to_list(variables))}")

    subsection("Mutation Possibilities:")

    IO.puts("""
      Original operator: -
      Mutations:
        - Arithmetic: + (addition), * (multiplication), / (division)
        - Would change: base_price + discount (wrong!)
      
      This is how mutation testing finds bugs in your tests!
    """)
  end

  def demo_conditional_logic do
    section("Example 3: Conditional Logic (Discount Tiers)")

    IO.puts("""
    Original Elixir code:

        cond do
          quantity >= 100 -> 0.20
          quantity >= 50 -> 0.15
          quantity >= 10 -> 0.10
          quantity >= 5 -> 0.05
          true -> 0.0
        end

    Tiered discount system with boundary conditions
    """)

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
      },
      {
        {:binary_op, :comparison, :>=, {:variable, "quantity"}, {:literal, :integer, 5}},
        {:literal, :float, 0.05}
      }
    ]

    default = {:literal, :float, 0.0}

    ast = {:conditional, :cond, branches, default}

    subsection("MetaAST Representation:")
    IO.puts("Conditional(cond): #{length(branches)} branches + 1 default")

    IO.puts("\nBranch 1 condition:")
    print_ast(elem(Enum.at(branches, 0), 0), 1)

    doc = Document.new(ast, :elixir)
    {:ok, meta} = Validator.validate(doc)

    subsection("Complexity Metrics:")
    IO.puts("  Cyclomatic complexity: ~#{length(branches) + 1}")
    IO.puts("  Decision points: #{length(branches)}")
    IO.puts("  Tree depth: #{meta.depth}")

    subsection("Boundary Mutations:")

    IO.puts("""
      Critical for testing edge cases:
      
      Original:  quantity >= 100
      Mutants:   quantity > 100   (off-by-one)
                 quantity >= 99   (boundary shift)
                 quantity <= 100  (operator flip)
                 quantity == 100  (exact match)
      
      Good tests should kill all these mutants!
    """)
  end

  def demo_collection_operation do
    section("Example 4: Collection Operation (Subtotal Calculation)")

    IO.puts("""
    Original Elixir code:

        Enum.reduce(items, 0.0, fn {_id, item}, acc ->
          item_price = Product.calculate_price(product, qty)
          acc + item_price
        end)

    Higher-order function from Cart.subtotal/1
    """)

    # Inner lambda body
    lambda_body =
      {:block,
       [
         {:function_call, "Product.calculate_price",
          [{:variable, "product"}, {:variable, "qty"}]},
         {:binary_op, :arithmetic, :+, {:variable, "acc"}, {:variable, "item_price"}}
       ]}

    # Full collection operation
    ast =
      {:collection_op, :reduce, {:lambda, ["item", "acc"], lambda_body}, {:variable, "items"},
       {:literal, :float, 0.0}}

    subsection("MetaAST Representation (M2.2 Extended):")

    IO.puts("""
      CollectionOp(reduce):
        ├─ lambda: (item, acc) -> body
        ├─ collection: items
        └─ initial: 0.0
    """)

    doc = Document.new(ast, :elixir)
    {:ok, meta} = Validator.validate(doc)

    IO.puts("\n  Layer: #{meta.level} (extended - common in most languages)")

    subsection("Cross-Language Equivalents:")

    IO.puts("""
      Python:
        reduce(lambda acc, item: acc + calc(item), items, 0.0)
      
      JavaScript:
        items.reduce((acc, item) => acc + calc(item), 0.0)
      
      Ruby:
        items.reduce(0.0) { |acc, item| acc + calc(item) }
      
      Go: (requires explicit loop)
        total := 0.0
        for _, item := range items {
          total += calc(item)
        }

    MetaAST normalizes these to {:collection_op, :reduce, ...}
    """)
  end

  def demo_validation_and_metadata do
    section("Example 5: Validation & Metadata")

    IO.puts("metastatic validates MetaAST conformance and extracts metadata.\n")

    # Create a complex nested expression
    ast =
      {:binary_op, :arithmetic, :-,
       {:binary_op, :arithmetic, :*, {:variable, "price"}, {:variable, "quantity"}},
       {:binary_op, :arithmetic, :*,
        {:binary_op, :arithmetic, :*, {:variable, "price"}, {:variable, "quantity"}},
        {:variable, "discount_rate"}}}

    subsection("Expression: price * quantity - (price * quantity * discount_rate)")
    print_ast(ast)

    doc = Document.new(ast, :elixir)
    {:ok, meta} = Validator.validate(doc)

    subsection("Validation Results:")
    IO.puts("  ✓ Conforms to MetaAST: true")
    IO.puts("  Layer: #{meta.level}")
    IO.puts("  Tree depth: #{meta.depth}")
    IO.puts("  Node count: #{meta.node_count}")
    IO.puts("  Variables: #{inspect(MapSet.to_list(meta.variables))}")
    IO.puts("  Warnings: #{length(meta.warnings)}")

    subsection("What This Enables:")

    IO.puts("""
      - Automatic complexity calculation
      - Variable dependency analysis
      - Dead code detection
      - Refactoring safety checks
      - Cross-language code comparison
      - Universal mutation testing
    """)
  end

  def demo_practical_applications do
    section("Practical Applications")

    subsection("1. Mutation Testing")

    IO.puts("""
    Generate test-quality metrics by mutating MetaAST:

    Original:    stock >= quantity
    Mutants:     stock > quantity   (boundary)
                 stock <= quantity  (relational)
                 stock == quantity  (equality)

    Run tests against each mutant.
    Good tests kill mutants. Survivors = weak tests!
    """)

    subsection("2. Purity Analysis")

    IO.puts("""
    Detect pure functions by walking MetaAST:

    Product.calculate_price/2:
      ✓ No I/O operations
      ✓ No side effects
      ✓ Deterministic
      → Pure function!

    Benefits: parallelization, memoization, optimization
    """)

    subsection("3. Complexity Metrics")

    IO.puts("""
    Calculate from MetaAST structure:

    calculate_price/2:
      - Cyclomatic complexity: 5 (cond with 5 branches)
      - Nesting depth: 2
      - Decision points: 4

    High complexity → needs refactoring or more tests
    """)

    subsection("4. Cross-Language Refactoring")

    IO.puts("""
    Transform at MetaAST level, generate any language:

    Extract calculation:
      Before: inline price * quantity - discount
      After:  call calculate_discounted_price(...)

    Apply transformation to Python, JS, Ruby simultaneously!
    """)
  end

  def demo_future_vision do
    section("Future: Language Adapters (Phase 2+)")

    IO.puts("""
    When Python adapter is implemented:

    Python source code:
      ↓ PythonAdapter.parse()
    Python AST (M1)
      ↓ PythonAdapter.to_meta()
    MetaAST (M2) ← UNIVERSAL REPRESENTATION
      ↓ ElixirAdapter.from_meta()
    Elixir AST (M1)
      ↓ ElixirAdapter.unparse()
    Elixir source code

    Translation happens at the semantic level, not textual!
    """)

    subsection("Universal Tool Architecture:")

    IO.puts("""

      ┌──────────┐  ┌────────────┐  ┌─────────┐
      │  Python  │  │ JavaScript │  │ Elixir  │
      └────┬─────┘  └─────┬──────┘  └────┬────┘
           │              │              │
           └──────────────┼──────────────┘
                          ↓
                    ┌──────────┐
                    │ MetaAST  │  ← M2 Level
                    │ (M2)     │
                    └────┬─────┘
                         │
           ┌─────────────┼─────────────┐
           ↓             ↓             ↓
      ┌─────────┐  ┌──────────┐  ┌──────────┐
      │ Mutator │  │  Purity  │  │Complexity│
      │ Engine  │  │ Analyzer │  │ Metrics  │
      └─────────┘  └──────────┘  └──────────┘

    Write tools ONCE, apply EVERYWHERE!
    """)
  end

  def run do
    demo_simple_comparison()
    demo_arithmetic_expression()
    demo_conditional_logic()
    demo_collection_operation()
    demo_validation_and_metadata()
    demo_practical_applications()
    demo_future_vision()

    section("Conclusion")

    IO.puts("""
    This demo showed metastatic's core capabilities:

    ✓ Universal MetaAST representation (M2 level)
    ✓ Three-layer architecture (Core/Extended/Native)
    ✓ Validation and metadata extraction
    ✓ Foundation for cross-language tools

    Next steps:
    1. Explore lib/product.ex and lib/cart.ex
    2. Read THEORETICAL_FOUNDATIONS.md for the theory
    3. Check ROADMAP.md for upcoming features
    4. Wait for Phase 2: Python adapter!

    metastatic: Build tools once, apply everywhere.

    """)
  end
end

Demo.run()
