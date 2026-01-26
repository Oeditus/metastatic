# Custom Analyzer Guide

Learn how to create custom analyzers that integrate with Metastatic's analyzer plugin system. Write analysis rules once and apply them across all supported languages.

## Anatomy of an Analyzer

Every analyzer is a module that implements the `Metastatic.Analysis.Analyzer` behaviour:

```elixir
defmodule MyApp.Analysis.MyAnalyzer do
  @behaviour Metastatic.Analysis.Analyzer
  
  alias Metastatic.Analysis.Analyzer
  
  # Required: Return metadata about this analyzer
  @impl true
  def info do
    %{
      name: :my_analyzer,
      category: :correctness,
      description: "Brief description",
      severity: :warning,
      explanation: "Detailed explanation...",
      configurable: false
    }
  end
  
  # Required: Analyze individual nodes
  @impl true
  def analyze(node, context) do
    # Return list of issues found in this node
    []
  end
  
  # Optional: Run before traversal starts
  # def run_before(context) do
  #   {:ok, context}
  # end
  
  # Optional: Run after traversal completes
  # def run_after(context, issues) do
  #   issues
  # end
end
```

## Step 1: Define Analyzer Metadata

The `info/0` function returns a map with required fields:

```elixir
@impl true
def info do
  %{
    name: :no_magic_numbers,                    # Unique identifier (atom)
    category: :style,                           # One of: readability, maintainability, performance, security, correctness, style, refactoring
    description: "Flags magic numbers",         # One-line summary
    severity: :warning,                         # One of: error, warning, info, refactoring_opportunity
    explanation: """
    Magic numbers (hardcoded literals) reduce readability and maintainability.
    Extract them to named constants instead.
    """,
    configurable: true                          # Whether analyzer accepts configuration
  }
end
```

## Step 2: Implement Node Analysis

The `analyze/2` callback is called for each AST node during traversal:

```elixir
@impl true
def analyze(node, context) do
  case node do
    {:literal, :integer, value} when value > 1000 ->
      [
        Analyzer.issue(
          analyzer: __MODULE__,
          category: :style,
          severity: :warning,
          message: "Magic number #{value} - extract to constant",
          node: node,
          suggestion: Analyzer.suggestion(
            type: :replace,
            replacement: {:variable, "CONSTANT_NAME"},
            message: "Replace with named constant"
          ),
          metadata: %{value: value}
        )
      ]
    
    _ ->
      []
  end
end
```

### Analyzer Context

The context passed to `analyze/2` contains:

```elixir
%{
  document: Metastatic.Document.t(),      # The document being analyzed
  config: map() | list(),                 # Analyzer configuration
  parent_stack: [meta_ast()],             # Stack of parent nodes
  depth: non_neg_integer(),               # Current depth in AST
  scope: map(),                           # Custom analyzer state (if using run_before)
  
  # Your custom fields from run_before:
  # custom_field: value
}
```

Use context to:
- Access the document and its language
- Check configuration options
- Traverse parent nodes
- Track depth
- Access analyzer-specific state

## Step 3: Optional - Setup and Teardown

For analyzers that need initialization or final processing:

### run_before/1: Initialize State

Called once before AST traversal:

```elixir
@impl true
def run_before(context) do
  # Initialize analyzer state
  context = Map.put(context, :defined_constants, MapSet.new())
  context = Map.put(context, :undefined_constants, MapSet.new())
  
  # Or skip this analyzer
  if context.document.language == :unsupported_language do
    {:skip, :unsupported_language}
  else
    {:ok, context}
  end
end
```

### run_after/2: Final Analysis

Called once after traversal with all collected issues:

```elixir
@impl true
def run_after(context, issues) do
  # Generate additional issues from collected state
  new_issues = Enum.map(context.undefined_constants, fn const ->
    Analyzer.issue(
      analyzer: __MODULE__,
      category: :correctness,
      severity: :error,
      message: "Constant #{const} used but not defined",
      node: {:variable, const},
      metadata: %{constant: const}
    )
  end)
  
  issues ++ new_issues
end
```

## Example 1: Simple Pattern Detector

Detect division by zero potential:

```elixir
defmodule MyApp.Analysis.DivisionByZero do
  @behaviour Metastatic.Analysis.Analyzer
  
  alias Metastatic.Analysis.Analyzer
  
  @impl true
  def info do
    %{
      name: :division_by_zero,
      category: :correctness,
      description: "Flags potential division by zero",
      severity: :warning,
      explanation: "Division by literals that are zero will always fail",
      configurable: false
    }
  end
  
  @impl true
  def analyze({:binary_op, :arithmetic, :/, _left, {:literal, :integer, 0}}, _context) do
    [
      Analyzer.issue(
        analyzer: __MODULE__,
        category: :correctness,
        severity: :error,
        message: "Division by zero",
        node: {:literal, :integer, 0}
      )
    ]
  end
  
  def analyze(_node, _context), do: []
end
```

## Example 2: Stateful Analysis

Detect inconsistent naming conventions:

```elixir
defmodule MyApp.Analysis.NamingConvention do
  @behaviour Metastatic.Analysis.Analyzer
  
  alias Metastatic.Analysis.Analyzer
  
  @impl true
  def info do
    %{
      name: :naming_convention,
      category: :style,
      description: "Checks naming conventions",
      severity: :info,
      explanation: "Variables should use snake_case",
      configurable: false
    }
  end
  
  @impl true
  def run_before(context) do
    context = Map.put(context, :variables, MapSet.new())
    {:ok, context}
  end
  
  @impl true
  def analyze({:variable, name}, context) do
    # Track variables
    context = update_in(context, [:variables], &MapSet.put(&1, name))
    
    # Check naming
    if String.contains?(name, "_") and String.match?(name, ~r/[A-Z]/) do
      [
        Analyzer.issue(
          analyzer: __MODULE__,
          category: :style,
          severity: :info,
          message: "Variable '#{name}' should be snake_case",
          node: {:variable, name},
          metadata: %{variable: name}
        )
      ]
    else
      []
    end
  end
  
  def analyze(_node, _context), do: []
  
  @impl true
  def run_after(_context, issues), do: issues
end
```

## Example 3: Configurable Analyzer

Create an analyzer that respects configuration:

```elixir
defmodule MyApp.Analysis.MaxLineLengthChecker do
  @behaviour Metastatic.Analysis.Analyzer
  
  alias Metastatic.Analysis.Analyzer
  
  @impl true
  def info do
    %{
      name: :max_line_length,
      category: :readability,
      description: "Checks maximum line length",
      severity: :warning,
      explanation: "Lines exceeding max length reduce readability",
      configurable: true
    }
  end
  
  @impl true
  def analyze(_node, context) do
    max_length = get_max_length(context.config)
    
    # Note: MetaAST doesn't include line info, this is pseudocode
    # In real analyzers, you'd track or estimate line length differently
    []
  end
  
  defp get_max_length(config) do
    cond do
      is_list(config) -> Keyword.get(config, :max_length, 80)
      is_map(config) -> Map.get(config, :max_length, 80)
      true -> 80
    end
  end
end
```

## Testing Your Analyzer

```elixir
defmodule MyApp.Analysis.MyAnalyzerTest do
  use ExUnit.Case, async: true
  
  alias Metastatic.{Document, Analysis.Runner}
  alias MyApp.Analysis.MyAnalyzer
  
  describe "info/0" do
    test "returns valid metadata" do
      info = MyAnalyzer.info()
      
      assert info.name == :my_analyzer
      assert info.category in [:readability, :maintainability, :performance, :security, :correctness, :style, :refactoring]
      assert info.severity in [:error, :warning, :info, :refactoring_opportunity]
    end
  end
  
  describe "analyze/2" do
    test "detects problematic pattern" do
      ast = {:literal, :integer, 42}
      doc = Document.new(ast, :python)
      context = %{
        document: doc,
        config: %{},
        parent_stack: [],
        depth: 0,
        scope: %{}
      }
      
      issues = MyAnalyzer.analyze(ast, context)
      
      assert length(issues) >= 0
      Enum.each(issues, fn issue ->
        assert issue.analyzer == MyAnalyzer
        assert issue.category == :style
      end)
    end
  end
  
  describe "integration with Runner" do
    test "works as plugin" do
      ast = {:literal, :integer, 42}
      doc = Document.new(ast, :python)
      
      {:ok, report} = Runner.run(doc, analyzers: [MyAnalyzer])
      
      assert is_list(report.issues)
      Enum.each(report.issues, fn issue ->
        assert issue.analyzer == MyAnalyzer
      end)
    end
  end
end
```

## Registering Your Analyzer

### Runtime Registration

```elixir
alias Metastatic.Analysis.Registry

Registry.register(MyApp.Analysis.MyAnalyzer)
```

### Application Configuration

```elixir
# config/config.exs
config :metastatic, :analyzers,
  auto_register: [
    MyApp.Analysis.MyAnalyzer,
    MyApp.Analysis.MyOtherAnalyzer
  ],
  config: %{
    my_analyzer: %{option: value},
    my_other_analyzer: %{threshold: 10}
  }
```

## Working with MetaAST Nodes

Common node patterns to match:

```elixir
# Literals
{:literal, :integer, 42}
{:literal, :string, "hello"}
{:literal, :boolean, true}

# Variables
{:variable, "name"}

# Binary operations
{:binary_op, :arithmetic, :+, left, right}
{:binary_op, :comparison, :>, left, right}

# Control flow
{:conditional, condition, then_branch, else_branch}
{:loop, :while, condition, body}

# Functions
{:function_call, "name", [arg1, arg2]}
{:lambda, [param1, param2], body}

# Blocks
{:block, [stmt1, stmt2]}

# Assignment
{:assignment, {:variable, "x"}, value}
{:early_return, value}
```

See the MetaAST documentation for the complete node specification.

## Best Practices

1. **Be Specific** - Match specific patterns, not overly broad ones
2. **Provide Suggestions** - Include actionable refactoring suggestions when possible
3. **Use Metadata** - Include analyzer-specific data in metadata for filtering
4. **Handle Edge Cases** - Consider nil values, empty collections, etc.
5. **Document Configuration** - Clearly document all configuration options
6. **Test Thoroughly** - Test normal cases, edge cases, and error conditions
7. **Consider Performance** - Avoid expensive operations in `analyze/2`
8. **Use run_before/1 for Setup** - Do expensive initialization once, not per-node
9. **Maintain State Immutably** - Use update_in or Map.put for state updates
10. **Be Language Agnostic** - Avoid language-specific assumptions

## Common Mistakes

1. **Modifying context** - Create new maps, don't mutate
2. **Not handling nil** - Always handle nil values safely
3. **Complex analyze/2** - Keep per-node analysis simple, use hooks for complexity
4. **Over-matching** - Be specific with patterns to avoid false positives
5. **Missing tests** - Test with real AST structures
6. **Assuming location info** - MetaAST doesn't always include line/column data
7. **Not closing issues properly** - Ensure every branch returns a list

## Integration Examples

See the `examples/` directory for complete working examples of:
- Running all analyzers on a module
- Creating and registering custom analyzers
- Processing and filtering analysis results
- Building custom report formatters
