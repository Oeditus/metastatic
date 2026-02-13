# Business Logic Analyzers

This directory contains business logic analyzers ported from `oeditus_credo` and adapted to work at the MetaAST (M2) level.

## Overview

These analyzers detect common code quality issues and anti-patterns that transcend language boundaries. By operating on the MetaAST representation, they can analyze code in any supported language (Python, JavaScript, Elixir, Rust, Go, etc.) without modification.

### Detection Modes: Semantic vs Heuristic

Analyzers use a **semantic-first, heuristic-fallback** approach powered by the OpKind metadata system:

**1. Semantic Detection (Preferred)**
- Uses `OpKind` metadata attached to `:function_call` nodes
- OpKind captures semantic meaning: domain (`:db`, `:http`, `:file`, etc.) and operation (`:retrieve`, `:create`, `:query`, etc.)
- Framework-aware: recognizes patterns from Ecto, Django, Sequelize, ActiveRecord, etc.
- Highly accurate with no false positives when semantic enrichment is available
- Example: `{:function_call, [name: "Repo.get", op_kind: [domain: :db, operation: :retrieve, target: "User"]], [args...]}`

**2. Heuristic Detection (Fallback)**
- Pattern matching on function names when `op_kind` metadata is not available
- Maintains backward compatibility with code that hasn't been semantically enriched
- May produce false positives for ambiguous function names

**Analyzers Using OpKind:**
- `BlockingInPlug`: Checks OpKind domain for blocking operations (`:db`, `:http`, `:file`, `:cache`, `:external_api`, `:queue`)
- `MissingTelemetryForExternalHttp`: Uses `OpKind.http?()` for HTTP operation detection
- `SyncOverAsync`: Identifies blocking operations via OpKind domain
- `InefficientFilter`: Detects fetch-all operations (`domain: :db`, `operation: :retrieve_all/:query`)
- `TOCTOU`: Identifies file check/use operations via OpKind
- `MissingPreload`: Detects database collection queries
- `NPlusOneQuery`: Identifies database operations in loops

## Available Analyzers

### Language-Agnostic Analyzers (✅ Implemented)

These analyzers work across ALL languages:

#### CallbackHell
- **Layer**: M2.1 Core
- **Category**: Readability
- **Detection**: Deeply nested conditional statements
- **Applies to**: Python, JavaScript, Elixir, Rust, Go, Java, C#, Ruby, etc.
- **Configurable**: Yes (`max_nesting`, default: 2)

**Example (any language)**:
```
Bad: if x { if y { if z { ... } } }
Good: Use early returns, flatten logic, extract functions
```

#### MissingErrorHandling
- **Layer**: M2.2 Extended
- **Category**: Correctness
- **Detection**: Pattern matching on success without error handling
- **Applies to**: Elixir, Rust, OCaml, Haskell, Scala (any language with Result/Option types)
- **Configurable**: No

**Example**:
```
Bad (Elixir): {:ok, value} = operation()
Good: case operation() do {:ok, value} -> ...; {:error, e} -> ... end

Bad (Rust): let v = result.unwrap();
Good: match result { Ok(v) => ..., Err(e) => ... }
```

#### SilentErrorCase
- **Layer**: M2.1 Core
- **Category**: Correctness
- **Detection**: Conditionals with only success branch
- **Applies to**: All languages with conditionals
- **Configurable**: No

**Example (any language)**:
```
Bad: if success { handle_success(); }  // What about failures?
Good: if success { ... } else { handle_error(); }
```

#### SwallowingException
- **Layer**: M2.2 Extended
- **Category**: Correctness
- **Detection**: Exception handling without logging or re-raising
- **Applies to**: Python, JavaScript, Java, C#, Ruby, Elixir, etc.
- **Configurable**: No

**Example (any language)**:
```
Bad: try { risky(); } catch (e) { return null; }  // Exception hidden!
Good: try { risky(); } catch (e) { log(e); throw e; }
```

#### HardcodedValue
- **Layer**: M2.1 Core
- **Category**: Security
- **Detection**: Hardcoded URLs and IP addresses in string literals
- **Applies to**: All languages
- **Configurable**: Yes (`exclude_localhost`, `exclude_local_ips`)

**Example (any language)**:
```
Bad: url = "https://api.example.com"; host = "192.168.1.100";
Good: url = env.get("API_URL"); host = env.get("DB_HOST");
```

## Usage

### Basic Usage

```elixir
alias Metastatic.Analysis.BusinessLogic.CallbackHell
alias Metastatic.Document

# Create a document with MetaAST
ast = {:conditional, cond, then_branch, else_branch}
document = Document.new(ast, :python)

# Set up context
context = %{
  document: document,
  config: %{max_nesting: 2},  # Optional configuration
  parent_stack: [],
  depth: 0,
  scope: %{}
}

# Run analyzer
{:ok, context} = CallbackHell.run_before(context)
issues = CallbackHell.analyze(ast, context)
```

### With Analysis Runner (when implemented)

```elixir
alias Metastatic.Analysis.Runner
alias Metastatic.Analysis.BusinessLogic

analyzers = [
  BusinessLogic.CallbackHell,
  BusinessLogic.MissingErrorHandling,
  BusinessLogic.SilentErrorCase,
  BusinessLogic.SwallowingException,
  BusinessLogic.HardcodedValue
]

config = %{
  callback_hell: %{max_nesting: 3},
  hardcoded_value: %{exclude_localhost: true}
}

issues = Runner.run(document, analyzers, config)
```

## Implementation Details

### MetaAST Layer Compliance

All analyzers strictly operate on MetaAST nodes:

- **M2.1 Core**: Universal constructs (literals, variables, conditionals, operators)
- **M2.2 Extended**: Common patterns (pattern matching, exception handling)
- **M2.3 Native**: Language-specific (not yet implemented, requires adapters)

### Testing

Each analyzer includes comprehensive tests covering:
- Metadata validation
- Detection logic across various nesting levels
- Configuration options
- Cross-language pattern examples
- Edge cases

Run tests:
```bash
mix test test/metastatic/analysis/business_logic/
```

### Adding New Analyzers

To add a new business logic analyzer:

1. Create module in this directory implementing `@behaviour Metastatic.Analysis.Analyzer`
2. Implement required callbacks: `info/0`, `analyze/2`
3. Optionally implement: `run_before/1`, `run_after/2`
4. Add comprehensive tests
5. Update `CREDO_ANALYZERS_PORTING.md` tracking document
6. Document cross-language applicability

Example skeleton:

```elixir
defmodule Metastatic.Analysis.BusinessLogic.MyAnalyzer do
  @moduledoc """
  Brief description.
  
  ## Cross-Language Applicability
  - Python: ...
  - JavaScript: ...
  - etc.
  """
  
  @behaviour Metastatic.Analysis.Analyzer
  
  alias Metastatic.Analysis.Analyzer
  
  @impl true
  def info do
    %{
      name: :my_analyzer,
      category: :correctness,  # or :readability, :performance, etc.
      description: "One-line description",
      severity: :warning,
      explanation: "Detailed explanation...",
      configurable: false
    }
  end
  
  @impl true
  def analyze(node, context) do
    # Detection logic
    []  # Return list of issues
  end
end
```

## Future Work

### Phase 2: Elixir-Specific Analyzers (Requires Elixir Adapter)

The following analyzers from `oeditus_credo` require language-specific features and will be implemented once the Elixir adapter is available (Phase 2+):

- BlockingInPlug
- DirectStructUpdate
- InefficientFilter
- MissingPreload
- NPlusOneQuery
- And others (see `CREDO_ANALYZERS_PORTING.md`)

These will use the `language_specific` MetaAST node type to embed Elixir-specific patterns.

## References

- Original Credo analyzers: `../../../../../oeditus_credo/lib/credo/check/warning/`
- Analyzer behavior: `../analyzer.ex`
- Porting status: `../../../../CREDO_ANALYZERS_PORTING.md`
- MetaAST specification: `../../../../THEORETICAL_FOUNDATIONS.md`
