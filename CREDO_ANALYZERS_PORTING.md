# Credo Analyzers Porting Status

This document tracks the porting of custom business-logic analyzers from `oeditus_credo` to Metastatic.

## Overview

Custom Credo analyzers from `../oeditus_credo/lib/credo/check/warning/` are being translated to work at the MetaAST (M2) level, making them language-agnostic where possible.

## Classification

Analyzers are classified into three categories based on the MetaAST layer they operate on:

- **M2.1 Core**: Universal constructs present in ALL languages (literals, variables, operators, conditionals)
- **M2.2 Extended**: Common patterns present in MOST languages (loops, lambdas, exception handling, pattern matching)
- **M2.3 Native**: Language-specific constructs requiring adapter support (Elixir/Phoenix/Ecto specific features)

## Porting Status

### Language-Agnostic Analyzers (Portable across all languages)

| Original Check | Status | MetaAST Layer | Module | Notes |
|----------------|--------|---------------|--------|-------|
| CallbackHell | ✅ PORTED | M2.1 Core | `Metastatic.Analysis.BusinessLogic.CallbackHell` | Detects deeply nested conditionals |
| MissingErrorHandling | ✅ PORTED | M2.2 Extended | `Metastatic.Analysis.BusinessLogic.MissingErrorHandling` | Pattern matching without error case |
| SilentErrorCase | ✅ PORTED | M2.1 Core | `Metastatic.Analysis.BusinessLogic.SilentErrorCase` | Conditionals with only success path |
| SwallowingException | ✅ PORTED | M2.2 Extended | `Metastatic.Analysis.BusinessLogic.SwallowingException` | Exception handling without logging |
| HardcodedValue | ✅ PORTED | M2.1 Core | `Metastatic.Analysis.BusinessLogic.HardcodedValue` | Hardcoded URLs/IPs in literals |

### Elixir/Phoenix-Specific Analyzers (Require language adapter)

These analyzers detect patterns specific to Elixir/Phoenix/Ecto ecosystem and require the Elixir adapter (Phase 2+):

| Original Check | Status | MetaAST Layer | Module | Notes |
|----------------|--------|---------------|--------|-------|
| BlockingInPlug | ⏳ PLANNED | M2.3 Native | - | Requires Plug/Conn pattern detection |
| DirectStructUpdate | ⏳ PLANNED | M2.3 Native | - | Requires Ecto struct detection |
| InefficientFilter | ⏳ PLANNED | M2.3 Native | - | Requires Repo/Enum pattern detection |
| InlineJavascript | ⏳ PLANNED | M2.3 Native | - | Template-specific (HEEX/LEEX) |
| MissingHandleAsync | ⏳ PLANNED | M2.3 Native | - | LiveView-specific |
| MissingPreload | ⏳ PLANNED | M2.3 Native | - | Ecto-specific |
| MissingTelemetryForExternalHttp | ⏳ PLANNED | M2.3 Native | - | HTTP client detection |
| MissingTelemetryInAuthPlug | ⏳ PLANNED | M2.3 Native | - | Plug-specific |
| MissingTelemetryInLiveViewMount | ⏳ PLANNED | M2.3 Native | - | LiveView-specific |
| MissingTelemetryInObanWorker | ⏳ PLANNED | M2.3 Native | - | Oban-specific |
| MissingThrottle | ⏳ PLANNED | M2.3 Native | - | Template-specific (HEEX/LEEX) |
| NPlusOneQuery | ⏳ PLANNED | M2.3 Native | - | Ecto-specific |
| SyncOverAsync | ⏳ PLANNED | M2.3 Native | - | LiveView/GenServer-specific |
| TelemetryInRecursiveFunction | 🔄 PARTIAL | M2.1/M2.3 | - | Recursive detection is M2.1, telemetry is M2.3 |
| UnmanagedTask | ⏳ PLANNED | M2.3 Native | - | Elixir Task-specific |

## Legend

- ✅ PORTED: Analyzer fully implemented and tested
- 🔄 PARTIAL: Partially portable (some aspects language-agnostic)
- ⏳ PLANNED: Awaiting Elixir adapter implementation (Phase 2+)
- ❌ NOT PORTABLE: Cannot be expressed at M2 level

## Usage in Ragex

The ported analyzers will be integrated into `../ragex` (the mutation testing framework) to provide:

1. **Language-agnostic business logic checks** that work across all supported languages
2. **Elixir-specific checks** once the Elixir adapter is implemented
3. **Consistent analysis interface** using the `Metastatic.Analysis.Analyzer` behaviour

## Implementation Notes

### Language-Agnostic Patterns

The successfully ported analyzers demonstrate that many "business logic" concerns are actually universal:

- **Callback Hell**: Nested conditionals exist in Python, JavaScript, Ruby, etc.
- **Missing Error Handling**: Pattern matching without error cases applies to Rust, Elixir, OCaml, etc.
- **Silent Error Case**: Single-branch conditionals without error handling are universal
- **Swallowing Exceptions**: Try/catch without logging appears in all languages with exceptions
- **Hardcoded Values**: String literals with URLs/IPs are a cross-language anti-pattern

### Elixir-Specific Challenges

Many checks are tightly coupled to Elixir/Phoenix ecosystem:
- Function naming conventions (e.g., `mount`, `perform`, `call`)
- Module patterns (e.g., `use Phoenix.LiveView`, `use Oban.Worker`)
- Ecto query composition patterns
- Template syntax (HEEX/LEEX)

These require the `language_specific` escape hatch and will only activate when analyzing Elixir code with the Elixir adapter.

## Future Work

1. **Phase 2**: Implement Elixir adapter to enable M2.3 analyzers
2. **Phase 3**: Port additional language-specific patterns as other language adapters are implemented
3. **Cross-language equivalents**: Identify similar patterns in other ecosystems (e.g., Django ORM N+1 queries, React hooks async patterns)

## References

- Original Credo checks: `../oeditus_credo/lib/credo/check/warning/`
- Metastatic analyzer behavior: `lib/metastatic/analysis/analyzer.ex`
- Ported analyzers: `lib/metastatic/analysis/business_logic/`
