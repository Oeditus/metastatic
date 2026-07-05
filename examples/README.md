# metastatic Examples

This directory contains practical examples demonstrating metastatic's capabilities.

## Shopping Cart Example

**Location:** `examples/shopping_cart/`

A comprehensive, real-world example using an e-commerce shopping cart to demonstrate:

- MetaAST representation of business logic
- Cross-language semantic equivalence
- Universal tool foundations (mutation testing, purity analysis, complexity metrics)
- Three-layer architecture (Core/Extended/Native)

### Quick Start

```bash
# From the project root directory

# 1. Compile the project
mix compile

# 2. Run the interactive demo
elixir examples/shopping_cart/demo.exs

# 3. Visualize MetaAST tree structures
elixir examples/shopping_cart/visualize_ast.exs

# 4. Read the comprehensive guide
cat examples/shopping_cart/README.md
```

### What You'll Learn

1. **How MetaAST works** - See real Elixir code transformed to universal representation
2. **Cross-language equivalence** - Understand how Python, JavaScript, Ruby, Go, and Rust map to same MetaAST
3. **Tool building** - Learn how mutation testing, purity analysis, and complexity metrics work at M2 level
4. **Meta-modeling theory** - Practical application of MOF-based three-layer architecture

### Files

- **README.md** - Comprehensive guide (500+ lines) with detailed examples
- **lib/product.ex** - Simplified product management module
- **lib/cart.ex** - Shopping cart with pricing and discount logic
- **demo.exs** - Interactive demonstration of MetaAST operations
- **visualize_ast.exs** - Tree visualization with annotations

## Coming Soon

As metastatic evolves through its development phases:

**Phase 2 (Months 5-7):** Python Adapter Example
- Parse real Python code to MetaAST
- Round-trip transformations
- Cross-language mutation testing demo

**Phase 3 (Months 8-10):** JavaScript & Elixir Adapters
- Full multi-language examples
- Universal refactoring tools
- Cross-language code comparison

**Phase 4 (Months 11-12):** Advanced Tools
- Complete mutation testing engine
- Purity analyzer with side-effect detection
- Complexity analyzer with recommendations

## Contributing Examples

Have an interesting use case? Contributions welcome!

Examples should:
- Use real-world scenarios (not toy problems)
- Demonstrate specific metastatic capabilities
- Include clear documentation and expected output
- Work with the current development phase

See `GETTING_STARTED.md` for contribution guidelines.
