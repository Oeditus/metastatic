# Shopping Cart Example - MetaAST in Action

This example demonstrates **metastatic**'s core capabilities using a real-world shopping cart implementation. It showcases how metastatic transforms language-specific code into a universal MetaAST representation, enabling cross-language analysis and transformation tools.

## What This Example Demonstrates

This shopping cart implementation highlights metastatic's ability to represent:

1. **Core Layer (M2.1)** - Universal constructs present in ALL languages:
   - Arithmetic operations (`price * quantity`, `base_price - discount`)
   - Comparison operations (`stock >= quantity`, `quantity > 0`)
   - Boolean logic (`and`, `or`, negation)
   - Variables and literals
   - Function calls (`Product.available?()`, `Enum.reduce()`)
   - Conditionals (`if`, `cond`, `case`)
   - Binary operators in expressions

2. **Extended Layer (M2.2)** - Common patterns in MOST languages:
   - Pattern matching (function clauses, case statements)
   - Higher-order functions (`Enum.reduce`, `Map.update`)
   - Collection operations (map transformations)
   - Guard clauses (`when quantity > 0`)

3. **Native Layer (M2.3)** - Elixir-specific features (when needed):
   - Struct syntax (`%__MODULE__{}`)
   - Pipe operator (if used)
   - Macro calls (if used)

## The Shopping Cart Domain

### Modules

**Product** (`lib/product.ex`)
- Stock availability checking with boundary conditions
- Tiered bulk discount calculation (5%, 10%, 15%, 20%)
- Stock management operations
- Shipping weight calculations

**Cart** (`lib/cart.ex`)
- Item management with stock validation
- Subtotal calculation with bulk discounts
- Coupon system with minimum requirements
- Multi-step pricing calculations

### Key Business Logic

The example includes rich business logic perfect for demonstrating MetaAST:

```elixir
# Tiered discount logic - multiple comparison operators
discount_rate =
  cond do
    quantity >= 100 -> 0.20  # boundary: >= 100
    quantity >= 50 -> 0.15   # boundary: >= 50
    quantity >= 10 -> 0.10   # boundary: >= 10
    quantity >= 5 -> 0.05    # boundary: >= 5
    true -> 0.0
  end

# Multi-step arithmetic
base_price = price * quantity
discount = base_price * discount_rate
final_price = base_price - discount
```

This creates MetaAST structures like:

```elixir
{:conditional, :cond,
  [
    {
      {:binary_op, :comparison, :>=, {:variable, "quantity"}, {:literal, :integer, 100}},
      {:literal, :float, 0.20}
    },
    # ... more branches
  ],
  {:literal, :float, 0.0}  # default
}

{:binary_op, :arithmetic, :*, 
  {:variable, "price"}, 
  {:variable, "quantity"}}
```

## Why This Example Matters

### 1. Real-World Complexity

Unlike toy examples, this cart implementation includes:
- **Boundary conditions**: Critical for testing (`>=`, `<=`, `==`)
- **Multi-step calculations**: Realistic business logic
- **Validation logic**: Error paths and edge cases
- **Integration points**: Multiple functions working together

### 2. Cross-Language Applicability

The same cart logic could be written in:
- **Python**: classes, list comprehensions
- **JavaScript**: objects, Array.reduce()
- **Ruby**: blocks, Enumerable methods
- **Go**: structs, for loops
- **Rust**: Result types, iterators

**metastatic** can parse ALL of these into the SAME MetaAST representation, enabling universal tools.

### 3. Tool-Building Foundation

This example enables building tools that work across languages:

**Mutation Testing**
```elixir
# Original: quantity >= 100
# Mutant 1: quantity > 100   (boundary mutation)
# Mutant 2: quantity >= 99   (boundary mutation)
# Mutant 3: quantity <= 100  (relational mutation)
```

**Purity Analysis**
```elixir
# Pure function - same inputs always yield same outputs
Product.calculate_price(product, quantity)

# Detectable via MetaAST:
# - No I/O operations
# - No side effects
# - Deterministic calculations only
```

**Complexity Metrics**
```elixir
# Cyclomatic complexity from MetaAST
# Count: conditionals + loops + function exits
calculate_price/2: complexity = 5 (cond with 5 branches)
validate_coupon/2: complexity = 3 (cond with 3 branches)
```

## MetaAST Representation Examples

### Example 1: Stock Check (Comparison)

**Original Elixir:**
```elixir
def available?(%__MODULE__{stock: stock}, quantity) when quantity > 0 do
  stock >= quantity
end
```

**MetaAST (M2 Level):**
```elixir
{:binary_op, :comparison, :>=, 
  {:variable, "stock"}, 
  {:variable, "quantity"}}
```

**Equivalent Python (M1 Level):**
```python
def available(self, quantity):
    if quantity > 0:
        return self.stock >= quantity
```

**Equivalent JavaScript (M1 Level):**
```javascript
available(quantity) {
  if (quantity > 0) {
    return this.stock >= quantity;
  }
}
```

All three → **same MetaAST**.

### Example 2: Price Calculation (Arithmetic + Conditionals)

**Original Elixir:**
```elixir
def calculate_price(%__MODULE__{price: price}, quantity) when quantity > 0 do
  base_price = price * quantity
  
  discount_rate = cond do
    quantity >= 100 -> 0.20
    quantity >= 50 -> 0.15
    quantity >= 10 -> 0.10
    quantity >= 5 -> 0.05
    true -> 0.0
  end
  
  discount = base_price * discount_rate
  base_price - discount
end
```

**MetaAST (M2 Level - Simplified):**
```elixir
{:block, [
  {:variable_assign, "base_price",
    {:binary_op, :arithmetic, :*, 
      {:variable, "price"}, 
      {:variable, "quantity"}}},
  
  {:variable_assign, "discount_rate",
    {:conditional, :cond, [
      {
        {:binary_op, :comparison, :>=, {:variable, "quantity"}, {:literal, :integer, 100}},
        {:literal, :float, 0.20}
      },
      # ... more branches
    ], {:literal, :float, 0.0}}},
  
  {:variable_assign, "discount",
    {:binary_op, :arithmetic, :*,
      {:variable, "base_price"},
      {:variable, "discount_rate"}}},
  
  {:binary_op, :arithmetic, :-,
    {:variable, "base_price"},
    {:variable, "discount"}}
]}
```

**Why This Matters:**
- **Language-agnostic**: Same structure works for if/elif (Python), switch (JS), etc.
- **Tool-friendly**: Easy to identify mutation points (operators, boundaries)
- **Analyzable**: Can compute complexity, extract variables, detect patterns

### Example 3: Collection Operation (Higher-Order Function)

**Original Elixir:**
```elixir
def subtotal(%__MODULE__{items: items}) do
  Enum.reduce(items, 0.0, fn {_id, %{product: product, quantity: qty}}, acc ->
    item_price = Product.calculate_price(product, qty)
    acc + item_price
  end)
end
```

**MetaAST (M2 Level):**
```elixir
{:collection_op, :reduce,
  {:lambda, ["_id", "item", "acc"],
    {:block, [
      {:variable_assign, "item_price",
        {:function_call, "Product.calculate_price", 
          [{:variable, "product"}, {:variable, "qty"}]}},
      {:binary_op, :arithmetic, :+,
        {:variable, "acc"},
        {:variable, "item_price"}}
    ]}},
  {:variable, "items"},
  {:literal, :float, 0.0}}
```

**Cross-Language Equivalents:**

**Python:**
```python
def subtotal(self):
    return reduce(
        lambda acc, item: acc + Product.calculate_price(item['product'], item['quantity']),
        self.items.values(),
        0.0
    )
```

**JavaScript:**
```javascript
subtotal() {
  return Object.values(this.items).reduce((acc, item) => {
    const itemPrice = Product.calculatePrice(item.product, item.quantity);
    return acc + itemPrice;
  }, 0.0);
}
```

All map to the **same `:collection_op` MetaAST node**.

## Building Cross-Language Tools

### Use Case 1: Mutation Testing Engine

A mutation testing tool built on metastatic works across ALL languages:

```elixir
# Define mutations at M2 level
defmodule Mutator.Arithmetic do
  def mutate({:binary_op, :arithmetic, :+, left, right}) do
    [
      {:binary_op, :arithmetic, :-, left, right},  # + → -
      {:binary_op, :arithmetic, :*, left, right},  # + → *
      {:binary_op, :arithmetic, :/, left, right}   # + → /
    ]
  end
end

defmodule Mutator.Boundary do
  def mutate({:binary_op, :comparison, :>=, left, right}) do
    [
      {:binary_op, :comparison, :>, left, right},   # >= → >
      {:binary_op, :comparison, :==, left, right},  # >= → ==
      {:binary_op, :comparison, :<=, left, right}   # >= → ≤
    ]
  end
end
```

**Apply to ANY language:**
```elixir
# Parse Python code
python_ast = PythonAdapter.parse(python_source)
meta_ast = PythonAdapter.to_meta(python_ast)

# Apply mutations at M2 level
mutants = Mutator.generate_mutations(meta_ast)

# Convert back to Python
mutant_sources = Enum.map(mutants, fn mutant ->
  python_ast = PythonAdapter.from_meta(mutant)
  PythonAdapter.unparse(python_ast)
end)
```

### Use Case 2: Purity Analyzer

Detect pure functions by analyzing MetaAST:

```elixir
defmodule PurityAnalyzer do
  def pure?(meta_ast) do
    has_no_side_effects?(meta_ast) and
    has_no_io?(meta_ast) and
    has_no_state_mutation?(meta_ast)
  end
  
  defp has_no_side_effects?(ast) do
    # Check for assignment to external state
    # Walk MetaAST looking for impure operations
    not contains_impure_ops?(ast)
  end
  
  defp contains_impure_ops?({:function_call, name, _args}) do
    # Check if function is known to be impure (I/O, random, time)
    name in ["IO.puts", "File.write", "System.get_env", ":rand.uniform"]
  end
  
  defp contains_impure_ops?({:block, statements}) do
    Enum.any?(statements, &contains_impure_ops?/1)
  end
  
  defp contains_impure_ops?(_), do: false
end

# Works on ANY language's MetaAST
PurityAnalyzer.pure?(python_meta_ast)   # true/false
PurityAnalyzer.pure?(javascript_meta_ast)  # true/false
PurityAnalyzer.pure?(elixir_meta_ast)   # true/false
```

**Results for our cart:**
- `Product.calculate_price/2`: **Pure** (no side effects, deterministic)
- `Product.reduce_stock/2`: **Pure** (returns new struct, doesn't mutate)
- `Cart.subtotal/1`: **Pure** (calculation only)
- `Cart.apply_coupon/2`: **Pure** (returns new struct)

### Use Case 3: Complexity Analyzer

Calculate cyclomatic complexity from MetaAST:

```elixir
defmodule ComplexityAnalyzer do
  def cyclomatic_complexity(meta_ast) do
    1 + count_decision_points(meta_ast)
  end
  
  defp count_decision_points({:conditional, _type, branches, _default}) do
    length(branches) + Enum.sum(Enum.map(branches, fn {_cond, body} ->
      count_decision_points(body)
    end))
  end
  
  defp count_decision_points({:binary_op, :boolean, _op, left, right}) do
    1 + count_decision_points(left) + count_decision_points(right)
  end
  
  defp count_decision_points({:block, statements}) do
    Enum.sum(Enum.map(statements, &count_decision_points/1))
  end
  
  defp count_decision_points(_), do: 0
end
```

**Complexity scores for our functions:**
- `Product.available?/2`: **2** (1 guard + 1 comparison)
- `Product.calculate_price/2`: **5** (cond with 5 branches)
- `Cart.validate_coupon/2`: **4** (case + cond)
- `Cart.add_item/3`: **3** (if + nested if)

Same analysis works on Python, JavaScript, Ruby, etc.

## Running the Demos

### Prerequisites

```bash
cd /opt/Proyectos/Oeditus/metastatic

# Ensure dependencies are installed
mix deps.get
```

### Demo 1: MetaAST Operations

Run the interactive demo showing MetaAST transformations:

```bash
elixir examples/shopping_cart/demo.exs
```

This demonstrates:
- Parsing Elixir code to MetaAST
- Walking the AST tree
- Extracting variables
- Validating conformance
- Generating mutations

### Demo 2: AST Visualization

Visualize the MetaAST structure:

```bash
elixir examples/shopping_cart/visualize_ast.exs
```

Shows:
- Tree structure of MetaAST nodes
- Node types and metadata
- Depth and complexity metrics

## Key Takeaways

### 1. Universal Abstraction
MetaAST provides a common representation across languages. Write your analysis tool once, apply it everywhere.

### 2. Semantic Preservation
M2 preserves the semantics while normalizing syntax. `if/else`, `cond`, and `case` all become `:conditional` nodes, but their meaning is retained.

### 3. Fidelity Through Layers
- **M2.1 Core**: Universal, works everywhere
- **M2.2 Extended**: Common patterns, normalized with hints
- **M2.3 Native**: Language-specific escape hatch when needed

### 4. Practical Applications
This isn't academic - real tools benefit:
- **Mutation testing**: One engine, all languages
- **Static analysis**: Cross-language linters
- **Code metrics**: Universal complexity/maintainability scores
- **Refactoring tools**: Language-agnostic transformations
- **Learning tools**: See how concepts translate between languages

## Next Steps

### Explore the Code
1. Read `lib/product.ex` - simple examples of operators and conditions
2. Read `lib/cart.ex` - complex calculations and higher-order functions
3. Run the demos to see MetaAST in action

### Experiment
1. Add new functions to Product or Cart
2. Run the demo to see their MetaAST representation
3. Try creating simple mutations or analyses

### Learn More
- **README.md**: Project overview and quick start
- **GETTING_STARTED.md**: Developer guide
- **THEORETICAL_FOUNDATIONS.md**: Meta-modeling theory
- **RESEARCH.md**: Design decisions and architecture

## Vision: Build Once, Apply Everywhere

The ultimate goal of metastatic is to enable a new generation of cross-language development tools:

```
┌─────────────┐
│   Python    │──┐
└─────────────┘  │
┌─────────────┐  │   ┌──────────────┐   ┌──────────────────┐
│ JavaScript  │──┼──▶│   MetaAST    │──▶│  Universal Tools │
└─────────────┘  │   │   (M2 Level) │   │  - Mutation      │
┌─────────────┐  │   └──────────────┘   │  - Purity        │
│   Elixir    │──┘                       │  - Complexity    │
└─────────────┘                          │  - Refactoring   │
                                          └──────────────────┘
```

**This shopping cart example proves the concept works.**

The same MetaAST tools can analyze Python web apps, JavaScript frontends, Elixir backends, Go microservices, and Rust systems code - all using the same core analysis engine.

That's the power of meta-modeling.
