# Analyzer Plugin System

The Analyzer Plugin System provides a unified, extensible framework for code analysis in Metastatic. Write custom analysis rules once and apply them across all supported programming languages through the unified MetaAST representation.

## Quick Start

```elixir
alias Metastatic.{Document, Analysis.Runner}

# Create a document from code
ast = {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}}
doc = Document.new(ast, :python)

# Run analyzers
{:ok, report} = Runner.run(doc)

# Check results
IO.puts("Found #{report.summary.total} issues")
Enum.each(report.issues, fn issue ->
  IO.puts("[#{issue.severity}] #{issue.message}")
end)
```

## Core Concepts

### Analyzer Behaviour

An analyzer is a module that implements the `Metastatic.Analysis.Analyzer` behaviour:

- **`info/0`** - Returns metadata about the analyzer
- **`analyze/2`** - Called for each AST node during traversal
- **`run_before/1`** (optional) - Called before traversal starts
- **`run_after/2`** (optional) - Called after traversal completes

### Registry

The `Metastatic.Analysis.Registry` manages analyzer discovery and configuration:

```elixir
alias Metastatic.Analysis.Registry

# Register an analyzer
Registry.register(MyCustomAnalyzer)

# List all registered analyzers
Registry.list_all()

# List by category
Registry.list_by_category(:correctness)

# Configure an analyzer
Registry.configure(MyAnalyzer, %{threshold: 10})
```

### Runner

The `Metastatic.Analysis.Runner` executes analyzers on documents:

```elixir
alias Metastatic.Analysis.Runner

# Run all registered analyzers
{:ok, report} = Runner.run(doc)

# Run specific analyzers
{:ok, report} = Runner.run(doc, analyzers: [UnusedVariables, SimplifyConditional])

# With configuration
{:ok, report} = Runner.run(doc,
  analyzers: :all,
  config: %{
    nesting_depth: %{max_depth: 4},
    unused_variables: %{ignore_prefix: "_"}
  }
)
```

## Using Built-in Analyzers

### Business-logic Analyzers

#### 1. Pure MetaAST (9 analyzers)

Language-agnostic patterns using only M2.1/M2.2 constructs:

1. **CallbackHell** - Detects deeply nested conditionals (callback hell pattern)
2. **MissingErrorHandling** - Pattern matching without error case handling
3. **SilentErrorCase** - Conditionals with only success path
4. **SwallowingException** - Exception handling without logging
5. **HardcodedValue** - Hardcoded URLs/IPs in string literals
6. **NPlusOneQuery** - Database queries in collection operations
7. **InefficientFilter** - Fetch-all then filter anti-pattern
8. **UnmanagedTask** - Unsupervised async operations
9. **TelemetryInRecursiveFunction** - Metrics emission in recursive functions

#### 2. Function Name Heuristics (4 analyzers)

Detection based on function name patterns:

10. **MissingTelemetryForExternalHttp** - HTTP calls without telemetry/observability
11. **SyncOverAsync** - Blocking operations in async contexts
12. **DirectStructUpdate** - Struct/object updates bypassing validation
13. **MissingHandleAsync** - Fire-and-forget async operations without supervision

#### 3. Naming Conventions (4 analyzers)

Detection based on function/module naming conventions:

14. **BlockingInPlug** - Blocking I/O operations in HTTP middleware
15. **MissingTelemetryInAuthPlug** - Authentication/authorization without audit logging
16. **MissingTelemetryInLiveviewMount** - Component lifecycle methods without telemetry
17. **MissingTelemetryInObanWorker** - Background job processing without metrics

#### 4. Content Analysis (3 analyzers)

Pattern detection through string content analysis:

18. **MissingPreload** - Database queries without eager loading (N+1 risk)
19. **InlineJavascript** - Inline executable code in strings (XSS vulnerability)
20. **MissingThrottle** - Expensive operations without rate limiting

### Generic Analyzers

#### SimplifyConditional

Suggests simplification of redundant conditionals:

```elixir
# Detects patterns like:
# if x then true else false  →  x
# if x then false else true  →  not x

{:ok, report} = Runner.run(doc, analyzers: [SimplifyConditional])
```

**Configuration:** None (not configurable)

#### DeadCodeAnalyzer

Detects unreachable and dead code:

```elixir
# Detects:
# - Code after return statements
# - Branches in constant conditionals

{:ok, report} = Runner.run(doc,
  analyzers: [DeadCodeAnalyzer],
  config: %{dead_code: [min_confidence: :high]}
)
```

**Configuration:**
- `:min_confidence` - `:low` (all), `:medium`, `:high` (only definite)

#### NestingDepth

Detects excessive nesting depth:

```elixir
# Warns when nesting exceeds thresholds

{:ok, report} = Runner.run(doc,
  analyzers: [NestingDepth],
  config: %{nesting_depth: [max_depth: 4, warn_threshold: 3]}
)
```

**Configuration:**
- `:max_depth` - Maximum allowed depth (default: 5)
- `:warn_threshold` - Warning threshold (default: 4)

#### UnusedVariables

Detects unused variables:

```elixir
# Finds assigned but never used variables

{:ok, report} = Runner.run(doc,
  analyzers: [UnusedVariables],
  config: %{unused_variables: [ignore_prefix: "_"]}
)
```

**Configuration:**
- `:ignore_underscore` - Ignore variables starting with underscore (default: true)

## Understanding Reports

The runner returns a report with:

```elixir
{:ok, report} = Runner.run(doc)

# Report structure:
%{
  document: Document.t(),           # The analyzed document
  analyzers_run: [module()],        # Which analyzers ran
  issues: [Analyzer.issue()],       # All issues found
  summary: %{                       # Aggregated statistics
    total: integer(),
    by_severity: %{atom() => integer()},
    by_category: %{atom() => integer()},
    by_analyzer: %{atom() => integer()}
  },
  timing: %{total_ms: float()} | nil # Performance info
}
```

### Issue Structure

Each issue contains:

```elixir
%{
  analyzer: module(),               # Which analyzer found it
  category: atom(),                 # Category (:correctness, :style, etc.)
  severity: atom(),                 # :error, :warning, :info, :refactoring_opportunity
  message: String.t(),              # Human-readable message
  node: Metastatic.AST.meta_ast(),  # The problematic node
  location: %{                      # Location info
    line: non_neg_integer() | nil,
    column: non_neg_integer() | nil,
    path: Path.t() | nil
  },
  suggestion: %{                    # Optional refactoring suggestion
    type: :replace | :remove | :insert_before | :insert_after,
    replacement: meta_ast() | nil,
    message: String.t()
  } | nil,
  metadata: map()                   # Analyzer-specific data
}
```

## Common Patterns

### Filter by Severity

```elixir
errors = Enum.filter(report.issues, &(&1.severity == :error))
warnings = Enum.filter(report.issues, &(&1.severity == :warning))
refactoring = Enum.filter(report.issues, &(&1.severity == :refactoring_opportunity))
```

### Filter by Category

```elixir
correctness_issues = Enum.filter(report.issues, &(&1.category == :correctness))
style_issues = Enum.filter(report.issues, &(&1.category == :style))
```

### Group by Analyzer

```elixir
by_analyzer = Enum.group_by(report.issues, & &1.analyzer)

Enum.each(by_analyzer, fn {analyzer, issues} ->
  IO.puts("#{analyzer}: #{length(issues)} issues")
end)
```

### Get Refactoring Suggestions

```elixir
refactorings = 
  report.issues
  |> Enum.filter(&(&1.severity == :refactoring_opportunity))
  |> Enum.filter(&(&1.suggestion != nil))

Enum.each(refactorings, fn issue ->
  IO.puts("#{issue.message}")
  IO.puts("Suggestion: #{issue.suggestion.message}")
end)
```

### Track Timing

```elixir
{:ok, report} = Runner.run(doc, track_timing: true)

if report.timing do
  IO.puts("Analysis took #{report.timing.total_ms}ms")
end
```

## Application Configuration

Configure analyzers at the application level:

```elixir
# config/config.exs
config :metastatic, :analyzers,
  auto_register: [
    Metastatic.Analysis.UnusedVariables,
    Metastatic.Analysis.SimplifyConditional,
    Metastatic.Analysis.DeadCodeAnalyzer,
    Metastatic.Analysis.NestingDepth
  ],
  disabled: [],  # Disable specific analyzers
  config: %{
    unused_variables: %{ignore_prefix: "_"},
    nesting_depth: %{max_depth: 4},
    dead_code: %{min_confidence: :high}
  }
```

Then use:

```elixir
# Runs all registered analyzers with configured settings
{:ok, report} = Runner.run(doc)
```

## Best Practices

1. **Use Specific Analyzers When Possible** - Running fewer analyzers is faster
2. **Configure Thresholds** - Adjust defaults to match your project standards
3. **Process Issues by Severity** - Handle errors before warnings before info
4. **Cache Registry Lookups** - Don't repeatedly query the registry
5. **Use run_before/1 for Expensive Setup** - Heavy computation in lifecycle hooks
6. **Combine with Other Tools** - Use with formatter and type checker
7. **Review Suggestions** - Don't blindly apply refactoring suggestions
8. **Monitor Performance** - Use `track_timing: true` for performance-critical code

## Performance Considerations

- **Single-pass traversal:** Multiple analyzers run in a single AST traversal
- **Lazy evaluation:** Analysis only runs when explicitly called
- **Configurable depth:** Limit analysis with `max_issues` option
- **Language agnostic:** Same analyzers work across all languages

## Troubleshooting

### Analyzer Not Found

```elixir
# Register it first
Registry.register(MyAnalyzer)

# Or pass explicitly
Runner.run(doc, analyzers: [MyAnalyzer])
```

### No Issues Found

- Verify the AST contains the patterns the analyzer looks for
- Check analyzer configuration
- Run with specific analyzer to verify it's registered

### Performance Issues

- Reduce number of analyzers
- Use `max_issues` to stop early
- Profile with `track_timing: true`
- Consider language-specific analyzers if available

## Next Steps

- See CUSTOM_ANALYZER_GUIDE.md to create your own analyzers
- See BUILTIN_ANALYZERS.md for detailed reference
- Check examples/ directory for working code samples
