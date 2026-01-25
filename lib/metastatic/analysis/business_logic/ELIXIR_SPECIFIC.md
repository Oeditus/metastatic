# Elixir-Specific Business Logic Analyzers

This document outlines the approach for implementing Elixir/Phoenix/Ecto-specific analyzers from `oeditus_credo` that require language adapter support (Phase 2+).

## Overview

Many custom Credo checks are tightly coupled to Elixir's ecosystem:
- Phoenix framework (LiveView, Controllers, Plugs)
- Ecto (queries, schemas, preloading)
- Oban (background jobs)
- Elixir stdlib (Task, GenServer)

These cannot be directly translated to language-agnostic MetaAST constructs. Instead, they will use the `language_specific` escape hatch once the Elixir adapter is implemented.

## Strategy

### M2.3 Native Layer

Elixir-specific analyzers will:

1. **Detect language context** - Only activate when analyzing Elixir code
2. **Use `language_specific` nodes** - Embed Elixir AST when needed for fine-grained pattern detection
3. **Combine M2 and M1** - Use MetaAST for common patterns, drop to Elixir AST for specifics

### Example Pattern

```elixir
defmodule Metastatic.Analysis.BusinessLogic.Elixir.NPlusOneQuery do
  @behaviour Metastatic.Analysis.Analyzer
  
  @impl true
  def run_before(context) do
    # Skip if not Elixir
    if context.document.language != :elixir do
      {:skip, :not_elixir}
    else
      {:ok, context}
    end
  end
  
  @impl true
  def analyze({:collection_op, :map, _fn, collection}, context) do
    # Check collection source at M2 level
    case has_repo_call?(collection) do
      true -> 
        # Drop to M1 (Elixir AST) for detailed inspection
        case context.document.metadata[:elixir_ast] do
          {:language_specific, :elixir, native_ast} ->
            check_native_pattern(native_ast)
          _ ->
            []
        end
      false ->
        []
    end
  end
  
  defp has_repo_call?(ast) do
    # M2-level pattern detection
  end
  
  defp check_native_pattern(elixir_ast) do
    # M1-level (Elixir-specific) pattern detection
  end
end
```

## Planned Elixir-Specific Analyzers

### Ecto/Database Analyzers

#### NPlusOneQuery
**Pattern**: `Enum.map(collection, fn item -> Repo.get(...) end)`

Detection strategy:
- M2: Detect `collection_op` with `function_call` to Repo
- M1: Confirm Ecto.Repo module pattern
- Suggest: Use `preload/2` or batch queries

#### MissingPreload
**Pattern**: `User |> Repo.all()` without `preload(:association)`

Detection strategy:
- M2: Detect query chains without preload operation
- M1: Check for Ecto schema associations in metadata
- Suggest: Add `preload/2` for associations

#### InefficientFilter
**Pattern**: `users = Repo.all(User); Enum.filter(users, ...)`

Detection strategy:
- M2: Detect Repo call followed by collection filtering
- M1: Confirm consecutive statements in same scope
- Suggest: Move filter to `where/3` in query

#### DirectStructUpdate
**Pattern**: `%User{user | field: value}` instead of changesets

Detection strategy:
- M2: Detect map update on struct
- M1: Check if target is Ecto schema (struct with `__meta__`)
- Suggest: Use `changeset/2` and `Repo.update/1`

### Phoenix/LiveView Analyzers

#### BlockingInPlug
**Pattern**: Plug function calling blocking operations (Repo, HTTPoison, File)

Detection strategy:
- M2: Detect function with blocking calls
- M1: Check function name and conn parameter pattern
- Suggest: Move to controller or async operation

#### MissingHandleAsync
**Pattern**: `handle_event` with blocking operations without `start_async`

Detection strategy:
- M2: Detect blocking operations in handler function
- M1: Check function name is `handle_event` (LiveView callback)
- Suggest: Use `start_async/3` and `handle_async/3`

#### MissingTelemetryInLiveViewMount
**Pattern**: `mount/3` without telemetry instrumentation

Detection strategy:
- M2: Detect function body without telemetry calls
- M1: Check function name, arity, and LiveView module usage
- Suggest: Add `telemetry.execute/3` or `telemetry.span/3`

#### InlineJavascript
**Pattern**: `onclick="..."` in HEEX templates

Detection strategy:
- This is template-level, may require separate template analyzer
- M1: Parse HEEX/LEEX as language_specific content
- Suggest: Use `phx-click` and LiveView event handlers

#### MissingThrottle
**Pattern**: `phx-change` without `phx-debounce` or `phx-throttle`

Detection strategy:
- Template-level analyzer
- M1: Parse HEEX/LEEX attributes
- Suggest: Add `phx-debounce="300"`

### Concurrency/Task Analyzers

#### UnmanagedTask
**Pattern**: `Task.async/1` instead of supervised tasks

Detection strategy:
- M2: Detect function calls to Task module
- M1: Verify exact module alias and function name
- Suggest: Use `Task.Supervisor.async_nolink/2`

#### SyncOverAsync
**Pattern**: Blocking operations in GenServer/LiveView callbacks

Detection strategy:
- M2: Detect blocking calls in callback functions
- M1: Check function name matches callback pattern
- Suggest: Use async operations or background jobs

### Observability Analyzers

#### MissingTelemetryForExternalHttp
**Pattern**: HTTP client calls without telemetry wrapper

Detection strategy:
- M2: Detect function calls to HTTP libraries
- M1: Check module names (Req, HTTPoison, Finch, Tesla)
- Suggest: Wrap with `telemetry.span/3`

#### MissingTelemetryInAuthPlug
**Pattern**: Auth plugs without telemetry events

Detection strategy:
- M2: Detect module with plug behavior
- M1: Check module name contains "auth" keywords, verify `call/2` implementation
- Suggest: Add telemetry events for auth attempts

#### MissingTelemetryInObanWorker
**Pattern**: `perform/1` in Oban.Worker without telemetry

Detection strategy:
- M2: Detect function without telemetry calls
- M1: Check module uses Oban.Worker, function is `perform/1`
- Suggest: Wrap work with `telemetry.span/3`

#### TelemetryInRecursiveFunction
**Pattern**: Recursive function emitting telemetry on each iteration

Detection strategy:
- M2: Detect recursive function (calls itself) with telemetry
- M1: Verify exact function name and arity match
- Suggest: Wrap entire recursive operation with single telemetry call

## Implementation Timeline

### Phase 2: Elixir Adapter
- Implement Elixir adapter with `parse/1`, `to_meta/1`, `from_meta/2`
- Support `language_specific` nodes in Document metadata
- Enable access to both M2 and M1 representations

### Phase 3: Elixir-Specific Analyzers
1. **Tier 1** (High Value, Clear Patterns):
   - NPlusOneQuery
   - InefficientFilter
   - UnmanagedTask
   - DirectStructUpdate

2. **Tier 2** (Moderate Complexity):
   - MissingPreload
   - BlockingInPlug
   - SyncOverAsync
   - MissingTelemetryForExternalHttp

3. **Tier 3** (Complex, Context-Dependent):
   - MissingHandleAsync
   - MissingTelemetryInLiveViewMount
   - MissingTelemetryInObanWorker
   - TelemetryInRecursiveFunction

4. **Tier 4** (Template Analysis):
   - InlineJavascript
   - MissingThrottle

## Testing Strategy

Each Elixir-specific analyzer will include:

1. **M2 Pattern Tests**: Verify detection at MetaAST level
2. **M1 Pattern Tests**: Verify Elixir-specific pattern matching
3. **Integration Tests**: Real Elixir code → Adapter → MetaAST → Analyzer
4. **False Positive Tests**: Ensure non-Elixir code doesn't trigger
5. **Edge Cases**: Complex nesting, macros, metaprogramming

## Open Questions

1. **Macro Expansion**: Should analyzers work on expanded or unexpanded AST?
2. **Type Information**: Can we leverage Dialyzer/typespecs for better analysis?
3. **Cross-File Analysis**: How to detect N+1 queries across module boundaries?
4. **Template Handling**: Should HEEX/LEEX have separate adapter or be part of Elixir adapter?

## References

- Original implementations: `../../../../../oeditus_credo/lib/credo/check/warning/`
- MetaAST specification: `../../../../THEORETICAL_FOUNDATIONS.md`
- Adapter specification: `../../../../lib/metastatic/adapter.ex`
