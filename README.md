# Metastatic

**Cross-language code analysis through unified MetaAST representation**

Metastatic is a library that provides a unified MetaAST (Meta-level Abstract Syntax Tree) intermediate representation for parsing, transforming, and analyzing code across multiple programming languages using a three-layer meta-model architecture.

## Vision

Build tools once, apply them everywhere. Create a universal meta-model for program syntax that enables cross-language code analysis, transformation, and tooling.

**Metastatic provides the foundation** - the MetaAST meta-model and language adapters. Tools that leverage this foundation (mutation testing, purity analysis, complexity metrics) are built separately.

## Key Features

- **Layered Architecture**: Three-layer MetaAST design (M2.1 Core, M2.2 Extended, M2.3 Native)
- **Language Adapters**: Bidirectional M1 ↔ M2 transformations for multiple languages
- **Round-Trip Fidelity**: Transform source → MetaAST → source with >90% accuracy
- **Meta-Model Foundation**: MOF-based meta-modeling (M2 level) for universal AST representation
- **Cross-Language Equivalence**: Semantically equivalent code produces identical MetaAST across languages
- **Code Duplication Detection**: Find code clones across different programming languages (Type I-IV clones)
- **Advanced Analysis**: 9 built-in analyzers (purity, complexity, security, dead code, taint, smells, CFG, unused vars)

## Scope

**What Metastatic Provides:**
- MetaAST meta-model (M2 level) with three layers
- Language adapters (Python, Elixir, Erlang, Ruby, Haskell)
- Parsing, transformation, and unparsing infrastructure
- Cross-language semantic equivalence validation
- Code duplication detection (Type I-IV clones across languages)
- Comprehensive static analysis suite (9 analyzers)

**What Metastatic Does NOT Provide:**
- Code quality auditing (see Oeditus ecosystem at https://oeditus.com)

Metastatic is a **foundation library** that other tools build upon.

## Quick Start

### CLI Tools

MetASTatic provides command-line tools for cross-language translation, AST inspection, and semantic analysis:

```bash
# Cross-language translation
mix metastatic.translate --from python --to elixir hello.py
mix metastatic.translate --from elixir --to python lib/module.ex --output py_output/

# AST inspection (tree format)
mix metastatic.inspect hello.py

# AST inspection (JSON format)
mix metastatic.inspect --format json hello.py

# Filter by layer
mix metastatic.inspect --layer core hello.py

# Extract variables only
mix metastatic.inspect --variables hello.py

# Analyze MetaAST metrics
mix metastatic.analyze hello.py

# Validate with strict mode
mix metastatic.analyze --validate strict hello.py

# Check semantic equivalence
mix metastatic.validate_equivalence hello.py hello.ex

# Show detailed differences
mix metastatic.validate_equivalence --verbose file1.py file2.ex

# Cross-language code duplication detection
mix metastatic.detect_duplicates file1.py file2.ex
mix metastatic.detect_duplicates --dir lib/ --format json
```

### Using Language Adapters

Metastatic currently supports 5 language adapters: Python, Elixir, Erlang, Ruby, and Haskell.

#### Elixir & Erlang

```elixir
alias Metastatic.Adapters.{Elixir, Erlang}
alias Metastatic.{Adapter, Document}

# Parse Elixir source code
{:ok, doc} = Adapter.abstract(Elixir, "x + 5", :elixir)
doc.ast  # => {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}}

# Parse Erlang source code
{:ok, doc} = Adapter.abstract(Erlang, "X + 5.", :erlang)
doc.ast  # => {:binary_op, :arithmetic, :+, {:variable, "X"}, {:literal, :integer, 5}}

# Round-trip transformation
source = "x + y * 2"
{:ok, result} = Adapter.round_trip(Elixir, source)
result == source  # => true

# Convert back to source
{:ok, source} = Adapter.reify(Elixir, doc)

# Cross-language equivalence
elixir_source = "x + 5"
erlang_source = "X + 5."

{:ok, elixir_doc} = Adapter.abstract(Elixir, elixir_source, :elixir)
{:ok, erlang_doc} = Adapter.abstract(Erlang, erlang_source, :erlang)

# Both produce semantically equivalent MetaAST!
# (only variable naming differs: "x" vs "X")
```

#### Python

```elixir
alias Metastatic.Adapters.Python

# Parse Python arithmetic
{:ok, doc} = Adapter.abstract(Python, "x + 5", :python)
doc.ast  # => {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}}

# Parse Python class
source = """
class Calculator:
    def __init__(self, value=0):
        self.value = value
    
    def add(self, x):
        self.value += x
        return self
"""
{:ok, doc} = Adapter.abstract(Python, source, :python)
# doc.ast contains {:language_specific, :python, ...} for class definition
```

#### Ruby

```elixir
alias Metastatic.Adapters.Ruby

# Parse Ruby code
{:ok, doc} = Adapter.abstract(Ruby, "x + 5", :ruby)
doc.ast  # => {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}}

# Parse Ruby class with method chaining
source = """
class Calculator
  attr_reader :value
  
  def initialize(initial = 0)
    @value = initial
  end
  
  def add(x)
    @value += x
    self
  end
end
"""
{:ok, doc} = Adapter.abstract(Ruby, source, :ruby)
# doc.ast contains {:language_specific, :ruby, ...} for class definition
```

#### Haskell

```elixir
alias Metastatic.Adapters.Haskell

# Parse Haskell arithmetic
{:ok, doc} = Adapter.abstract(Haskell, "x + 5", :haskell)
doc.ast  # => {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}}

# Parse Haskell function with type signature
source = """
factorial :: Int -> Int
factorial 0 = 1
factorial n = n * factorial (n - 1)
"""
{:ok, doc} = Adapter.abstract(Haskell, source, :haskell)
# doc.ast contains {:language_specific, :haskell, ...} for type signature and function

# Parse data type definition
source = "data Maybe a = Nothing | Just a"
{:ok, doc} = Adapter.abstract(Haskell, source, :haskell)
# doc.ast contains {:language_specific, :haskell, ...} for algebraic data type
```

### Working with MetaAST Directly

```elixir
alias Metastatic.{AST, Document, Validator}

# Create a MetaAST document
ast = {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}}
doc = Document.new(ast, :elixir)

# Validate conformance
{:ok, meta} = Validator.validate(doc)
meta.level  # => :core
meta.variables  # => MapSet.new(["x"])

# Extract variables
AST.variables(ast)  # => MapSet.new(["x"])

# Check conformance
AST.conforms?(ast)  # => true
```

### Supplemental Modules

Supplemental modules extend MetaAST with library-specific integrations, enabling cross-language transformations:

```elixir
alias Metastatic.Supplemental.Transformer

# Transform actor patterns to Python Pykka library calls
ast = {:actor_call, {:variable, "worker"}, "process", [data]}
{:ok, python_ast} = Transformer.transform(ast, :python)
# Result: {:function_call, "worker.ask", [{:literal, :string, "process"}, data]}

# Check what supplementals are available for a language
Transformer.supported_constructs(:python)
# => [:actor_call, :actor_cast, :spawn_actor, :async_await, :async_context, :gather]

# Validate what supplementals a document needs
alias Metastatic.Supplemental.Validator
{:ok, analysis} = Validator.validate(doc)
analysis.required_supplementals  # => [:pykka, :asyncio]
```

**Available supplementals:**
- **Python.Pykka** - Actor model support (`:actor_call`, `:actor_cast`, `:spawn_actor`)
- **Python.Asyncio** - Async/await patterns (`:async_await`, `:async_context`, `:gather`)

See **[Supplemental Modules](SUPPLEMENTAL_MODULES.md)** for comprehensive guide on using and creating supplementals.

### Code Duplication Detection

Detect code clones across same or different programming languages using unified MetaAST representation:

```bash
# Detect duplicates (note: requires language adapters, Phase 2+)
mix metastatic.detect_duplicates file1.py file2.ex

# Scan entire directory
mix metastatic.detect_duplicates --dir lib/

# JSON output with custom threshold
mix metastatic.detect_duplicates file1.py file2.ex --format json --threshold 0.85

# Save detailed report
mix metastatic.detect_duplicates --dir lib/ --format detailed --output report.txt
```

```elixir
alias Metastatic.{Document, Analysis.Duplication}
alias Metastatic.Analysis.Duplication.Reporter

# Detect duplication between two documents
ast1 = {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}}
ast2 = {:binary_op, :arithmetic, :+, {:variable, "y"}, {:literal, :integer, 5}}
doc1 = Document.new(ast1, :python)
doc2 = Document.new(ast2, :elixir)

{:ok, result} = Duplication.detect(doc1, doc2)

result.duplicate?         # => true
result.clone_type         # => :type_ii (renamed clone)
result.similarity_score   # => 1.0

# Format results
Reporter.format(result, :text)
# "Duplicate detected: Type II (Renamed Clone)
#  Similarity score: 1.0
#  ..."

# Detect across multiple documents
ast3 = {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}}
doc3 = Document.new(ast3, :elixir)

{:ok, groups} = Duplication.detect_in_list([doc1, doc2, doc3])
length(groups)  # => 1 (all three form a clone group)

# Format clone groups
Reporter.format_groups(groups, :detailed)
```

**Clone Types Detected:**
- **Type I**: Exact clones (identical AST across languages)
- **Type II**: Renamed clones (same structure, different identifiers)
- **Type III**: Near-miss clones (similar structure above threshold)
- **Type IV**: Semantic clones (implicit in cross-language Type I-III)

**Features:**
- Cross-language detection (Python ↔ Elixir ↔ Erlang, etc.)
- Configurable similarity threshold (0.0-1.0, default 0.8)
- Multiple output formats (text, JSON, detailed)
- Batch detection with clone grouping
- Structural and token-based similarity metrics

**Based on:**
- Ira Baxter et al. “Clone Detection Using Abstract Syntax Trees” (1998)
- Chanchal K. Roy and James R. Cordy “A Survey on Software Clone Detection Research” (2007)

### Purity Analysis

Analyze code for side effects and functional purity across all supported languages:

```bash
# Check if code is pure
mix metastatic.purity_check my_file.py
# Output: PURE or IMPURE: [effects]

# Detailed analysis
mix metastatic.purity_check my_file.ex --format detailed

# JSON output for CI/CD
mix metastatic.purity_check my_file.erl --format json
```

```elixir
alias Metastatic.{Document, Analysis.Purity}

# Pure arithmetic
ast = {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}}
doc = Document.new(ast, :python)
{:ok, result} = Purity.analyze(doc)

result.pure?              # => true
result.effects            # => []
result.confidence         # => :high

# Impure with I/O
ast = {:function_call, "print", [{:literal, :string, "hello"}]}
doc = Document.new(ast, :python)
{:ok, result} = Purity.analyze(doc)

result.pure?              # => false
result.effects            # => [:io]
result.summary            # => "Function is impure due to I/O operations"
```

**Detected Effects:**
- I/O operations (print, file access, network, database)
- Mutations (assignments in loops)
- Random operations (random, rand)
- Time operations (time, date, now)
- Exception handling (try/catch)
- Unknown function calls (low confidence)

#### Direct Native AST Input

All analyzers accept native language AST directly as `{language, native_ast}` tuples for integration with existing tooling:

```elixir
alias Metastatic.Analysis.Purity

# Python native AST (from Python's ast module)
python_ast = %{"_type" => "Constant", "value" => 42}
{:ok, result} = Purity.analyze({:python, python_ast})
result.pure?  # => true

# Elixir native AST  
elixir_ast = {:+, [], [{:x, [], nil}, 5]}
{:ok, result} = Purity.analyze({:elixir, elixir_ast})
result.pure?  # => true

# Supports all analyzers
alias Metastatic.Analysis.Complexity
{:ok, result} = Complexity.analyze({:python, python_ast})

# Error handling for unsupported languages
{:error, {:unsupported_language, _}} = Purity.analyze({:unsupported, :some_ast})
```

This enables seamless integration with language-specific parsers and build tools without requiring Document struct creation.

### Complexity Analysis

Analyze code complexity with six comprehensive metrics that work uniformly across all supported languages:

```bash
# Analyze complexity
mix metastatic.complexity my_file.py

# JSON output
mix metastatic.complexity my_file.ex --format json

# Detailed report with recommendations
mix metastatic.complexity my_file.erl --format detailed

# Custom thresholds
mix metastatic.complexity my_file.py --max-cyclomatic 15 --max-cognitive 20
```

```elixir
alias Metastatic.{Document, Analysis.Complexity}

# Analyze all metrics
ast = {:conditional, {:variable, "x"}, 
  {:conditional, {:variable, "y"}, {:literal, :integer, 1}, {:literal, :integer, 2}},
  {:literal, :integer, 3}}
doc = Document.new(ast, :python)
{:ok, result} = Complexity.analyze(doc)

result.cyclomatic      # => 3 (McCabe complexity)
result.cognitive       # => 3 (with nesting penalties)
result.max_nesting     # => 2
result.halstead.volume # => 45.6 (program volume)
result.loc.logical     # => 2
result.warnings        # => []
result.summary         # => "Code has low complexity"
```

**Available Metrics:**
- **Cyclomatic Complexity** - McCabe metric measuring decision points
- **Cognitive Complexity** - Measures understandability with nesting penalties
- **Nesting Depth** - Maximum nesting level
- **Halstead Metrics** - Volume, difficulty, and effort calculations
- **Lines of Code** - Physical, logical, and comment line counts
- **Function Metrics** - Statement count, return points, variable count

**Default Thresholds:**
- Cyclomatic: 10 (warning), 20 (error)
- Cognitive: 15 (warning), 30 (error)
- Nesting: 3 (warning), 5 (error)
- Logical LoC: 50 (warning), 100 (error)

### Advanced Analysis Features

Metastatic provides six additional static analysis capabilities that work uniformly across all supported languages:

#### Dead Code Detection

Identify unreachable code paths and constant conditional branches:

```bash
# Detect dead code
mix metastatic.dead_code my_file.py

# JSON output
mix metastatic.dead_code my_file.ex --format json

# Filter by confidence level
mix metastatic.dead_code my_file.rb --confidence high
```

```elixir
alias Metastatic.{Document, Analysis.DeadCode}

# Code after return statement
ast = {:block, [
  {:early_return, {:literal, :integer, 42}},
  {:function_call, "print", [{:literal, :string, "unreachable"}]}
]}
doc = Document.new(ast, :python)
{:ok, result} = DeadCode.analyze(doc)

result.has_dead_code?  # => true
result.issues          # => [{:code_after_return, :high, ...}]
result.summary         # => "1 dead code issue detected"
```

**Detects:**
- Code after return/break/continue statements
- Constant conditional branches (always true/false)
- Unreachable exception handlers

#### Unused Variables

Track variable definitions and usage with scope-aware analysis:

```bash
# Find unused variables
mix metastatic.unused_vars my_file.py

# Ignore underscore-prefixed variables
mix metastatic.unused_vars my_file.ex --ignore-underscore

# JSON output
mix metastatic.unused_vars my_file.erl --format json
```

```elixir
alias Metastatic.Analysis.UnusedVariables

ast = {:block, [
  {:assignment, {:variable, "x"}, {:literal, :integer, 5}},
  {:assignment, {:variable, "y"}, {:literal, :integer, 10}},
  {:variable, "y"}
]}
doc = Document.new(ast, :python)
{:ok, result} = UnusedVariables.analyze(doc)

result.has_unused?     # => true
result.unused          # => MapSet.new(["x"])
result.summary         # => "1 unused variable: x"
```

**Features:**
- Symbol table with scope tracking
- Distinguishes reads from writes
- Handles nested scopes (blocks, loops, conditionals)

#### Control Flow Graph

Generate control flow graphs with multiple export formats:

```bash
# Generate CFG in DOT format (for Graphviz)
mix metastatic.control_flow my_file.py --format dot

# Generate D3.js JSON for interactive visualization
mix metastatic.control_flow my_file.ex --format d3 --output cfg.json

# Text representation
mix metastatic.control_flow my_file.rb --format text
```

```elixir
alias Metastatic.Analysis.ControlFlow

ast = {:conditional, {:variable, "x"}, 
  {:early_return, {:literal, :integer, 1}},
  {:literal, :integer, 2}
}
doc = Document.new(ast, :python)
{:ok, result} = ControlFlow.analyze(doc)

result.node_count      # => 5
result.edge_count      # => 4
result.has_cycles?     # => false
result.to_dot()        # => "digraph CFG { ... }"
result.to_d3_json()    # => %{nodes: [...], links: [...]}
```

**Export Formats:**
- DOT format for Graphviz rendering
- D3.js JSON for web visualization
- Plain text representation
- Elixir map structure

**Features:**
- Cycle detection
- Entry/exit node identification
- Branch and merge point tracking

#### Taint Analysis

Track data flow from untrusted sources to sensitive operations:

```bash
# Check for taint vulnerabilities
mix metastatic.taint_check my_file.py

# JSON output
mix metastatic.taint_check my_file.ex --format json
```

```elixir
alias Metastatic.Analysis.Taint

# Dangerous pattern: eval(input())
ast = {:function_call, "eval", [
  {:function_call, "input", []}
]}
doc = Document.new(ast, :python)
{:ok, result} = Taint.analyze(doc)

result.has_vulnerabilities?  # => true
result.vulnerabilities       # => [{:code_injection, ...}]
result.summary               # => "1 taint vulnerability detected"
```

**Detects:**
- Code injection (eval, exec with untrusted input)
- Command injection (system, shell commands)
- SQL injection patterns
- Path traversal vulnerabilities

**Note:** Current implementation detects direct flows. Variable tracking and interprocedural analysis planned for future releases.

#### Security Vulnerability Detection

Pattern-based security scanning with CWE identifiers:

```bash
# Scan for security issues
mix metastatic.security_scan my_file.py

# JSON output with CWE details
mix metastatic.security_scan my_file.ex --format json
```

```elixir
alias Metastatic.Analysis.Security

# Hardcoded password
ast = {:assignment, {:variable, "password"}, {:literal, :string, "admin123"}}
doc = Document.new(ast, :python)
{:ok, result} = Security.analyze(doc)

result.has_vulnerabilities?  # => true
result.vulnerabilities[0].type       # => :hardcoded_secret
result.vulnerabilities[0].severity   # => :high
result.vulnerabilities[0].cwe        # => "CWE-798"
```

**Vulnerability Categories:**
- Dangerous functions (eval, exec, pickle.loads)
- Hardcoded secrets (passwords, API keys, tokens)
- Weak cryptography (MD5, SHA1, DES)
- Insecure protocols (HTTP for sensitive data)
- SQL injection patterns
- Command injection patterns

**Severity Levels:** Critical, High, Medium, Low

#### Code Smell Detection

Identify maintainability issues and anti-patterns:

```bash
# Detect code smells
mix metastatic.code_smells my_file.py

# Detailed report
mix metastatic.code_smells my_file.ex --format detailed

# JSON output
mix metastatic.code_smells my_file.rb --format json
```

```elixir
alias Metastatic.Analysis.Smells

# Long function with deep nesting
ast = {:block, [
  # ... 25+ statements with nesting depth 6
]}
doc = Document.new(ast, :python)
{:ok, result} = Smells.analyze(doc)

result.has_smells?     # => true
result.smells          # => [:long_function, :deep_nesting]
result.severity        # => :high
```

**Detected Smells:**
- Long functions (>20 statements)
- Deep nesting (>4 levels)
- High cyclomatic complexity (>10)
- High cognitive complexity (>15)
- Magic numbers (unexplained literals)
- Complex conditionals (>3 boolean operators)

**Integration:** Leverages existing complexity metrics for detection.

## Documentation

- **[Theoretical Foundations](THEORETICAL_FOUNDATIONS.md)** - Formal meta-modeling theory and proofs
- **[Supplemental Modules](SUPPLEMENTAL_MODULES.md)** - Guide to using and creating supplemental modules
- **API Documentation** - Generate with `mix docs`

## Architecture

### Three-Layer MetaAST

**Layer 1: Core (M2.1)** - Universal concepts (ALL languages)  
Common constructs: literals, variables, operators, conditionals, function calls, assignments

**Layer 2: Extended (M2.2)** - Common patterns (MOST languages)  
Control flow: loops, lambdas, collection operations, pattern matching, exception handling

**Layer 2s: Structural/Organizational (M2.2s)** - Top-level constructs (MOST languages)  
Organizational: containers (modules/classes/namespaces), function definitions, properties, attribute access, augmented assignments

**Layer 3: Native (M2.3)** - Language-specific escape hatches  
Language-specific: lifetimes, async models, advanced type systems, metaprogramming

## Examples

### Shopping Cart Example

A comprehensive real-world example demonstrating metastatic's capabilities using an e-commerce shopping cart:

```bash
# From project root
mix compile

# Run interactive demo
elixir examples/shopping_cart/demo.exs

# Visualize MetaAST tree structures
elixir examples/shopping_cart/visualize_ast.exs
```

**What you'll learn:**
- How MetaAST represents real business logic (pricing, discounts, validation)
- Cross-language semantic equivalence (same logic in Python, JavaScript, Elixir, etc.)
- Foundation for universal tools (mutation testing, purity analysis, complexity metrics)
- Three-layer architecture in practice (Core/Extended/Native)

**Files:**
- `examples/shopping_cart/README.md` - Comprehensive 500-line guide
- `examples/shopping_cart/lib/` - Product and Cart modules with rich business logic
- `examples/shopping_cart/demo.exs` - Interactive MetaAST operations demo
- `examples/shopping_cart/visualize_ast.exs` - Tree visualization with annotations

See [examples/README.md](examples/README.md) for more details.

## Use Cases

### Foundation for Cross-Language Tools
Metastatic provides the MetaAST foundation that other tools build upon:

```elixir
# Mutation testing (in muex library, NYI)
Muex.mutate_file("src/calculator.py", :python)
Muex.mutate_file("src/calculator.js", :javascript)
# Both use Metastatic's MetaAST under the hood!
```

### Cross-Language Code Transformation
Transform code between languages (for supported constructs):

```elixir
# Parse Python
{:ok, doc} = Metastatic.Builder.from_source(python_source, :python)

# Transform to Elixir (with supplemental modules for unsupported constructs)
{:ok, elixir_source} = Metastatic.Builder.to_source(doc, :elixir)
```

### Semantic Equivalence Validation
Verify that code across languages has identical semantics:

```elixir
{:ok, py_doc} = Metastatic.Builder.from_source("x + 5", :python)
{:ok, ex_doc} = Metastatic.Builder.from_source("x + 5", :elixir)

py_doc.ast == ex_doc.ast  # => true (same MetaAST)
```

### AST Analysis Infrastructure
Build language-agnostic analysis tools:

```elixir
# Extract all variables from any supported language
{:ok, doc} = Metastatic.Builder.from_source(source, language)
variables = Metastatic.AST.variables(doc.ast)
```

## Contributing

This project is currently in the research/foundation phase. Contributions welcome!

## Research Background

Metastatic is inspired by research from:
- **muex** - Multi-language mutation testing analysis
- **propwise** - Property-based testing candidate identification

## Credits

Created as part of the Oeditus code quality tooling ecosystem.

Research synthesis from muex and propwise multi-language analysis projects.

## Installation

```elixir
def deps do
  [
    {:metastatic, "~> 0.1"}
  ]
end
```

[Documentation](https://hexdocs.pm/metastatic).

