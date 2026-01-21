# TO_CONSIDER.md

This document captures architectural concerns, unverified ideas, and open questions that require further investigation or design decisions before implementation.

## ✅ Concern #1: Cross-Language MetaAST Support with External Libraries (RESOLVED)

**Status:** RESOLVED in Phase 2 (January 2026)

### Problem Statement

Some languages lack native constructs for certain MetaAST patterns, but third-party libraries provide equivalent functionality. The question is: how should Metastatic handle MetaAST constructs that are unsupported natively in a target language?

### Resolution

Implemented a comprehensive **Supplemental Module** system with the following components:

1. **Behaviour API** (`Metastatic.Supplemental`) - Defines contract for supplemental modules
2. **Registry System** (`Metastatic.Supplemental.Registry`) - GenServer-based registration with three-way indexing
3. **Transformer Helper** (`Metastatic.Supplemental.Transformer`) - Integration with adapter pipeline
4. **Error System** - Four error types with clear messages
5. **Official Modules** - Pykka (actors) and Asyncio for Python
6. **Documentation** - SUPPLEMENTAL_MODULES.md (602 lines) with full guide

**Results:**
- 66 tests for supplemental system (100% passing)
- 116 new tests total in Phase 2
- Zero regressions
- Community can create custom supplemental modules
- Opt-in complexity - users only add when needed

See SUPPLEMENTAL_MODULES.md and ROADMAP.md Phase 2 for complete details.

### Example Scenario

**Elixir Actor Model → Other Languages**

Elixir's concurrency primitives are first-class language features:
```elixir
GenServer.call(server, :get_state)
spawn(fn -> do_work() end)
receive do
  {:msg, data} -> handle(data)
end
```

These map to MetaAST concepts like:
- `{:actor_call, server, message, timeout}` for GenServer.call
- `{:spawn_process, lambda}` for spawn
- `{:receive_message, pattern_arms}` for receive

**Other Languages with Actor Libraries**

Python (via libraries):
```python
# Akka-like: pykka
actor_ref.ask({'type': 'get_state'})

# Async: asyncio actors
await actor.send_message({'type': 'get_state'})
```

JavaScript (via libraries):
```javascript
// comedy library
actor.sendRequest('get_state')

// nact library
dispatch(actor, { type: 'get_state' })
```

### Current Behavior

When transforming MetaAST `{:actor_call, ...}` to Python/JavaScript:
- The adapter encounters an unsupported construct
- Returns `{:error, "Unsupported MetaAST construct: {:actor_call, ...}"}`
- Transformation fails

### Proposed Solution

**Two-Tier Strategy:**

#### 1. Graceful Default Behavior (Fail-Safe)

By default, adapters should return a descriptive error when encountering unsupported constructs:

```elixir
def transform({:actor_call, server, message, _timeout}, _metadata) do
  {:error, """
  Actor model constructs are not natively supported in Python.
  
  Consider using a supplemental module:
  - pykka: for Akka-style actors
  - asyncio: for async/await actors
  
  See documentation on supplemental modules.
  """}
end
```

Benefits:
- Clear error messages guide users
- No silent failures or undefined behavior
- Maintains type safety and predictability

#### 2. Supplemental Modules (Opt-In)

Users can provide supplemental modules that map unsupported MetaAST constructs to library calls:

```elixir
# Example: Python with pykka
supplemental = %{
  actor_call: fn server, message, timeout ->
    # Generate: actor_ref.ask(message, timeout=timeout)
    {:ok, %{
      "_type" => "Call",
      "func" => %{
        "_type" => "Attribute",
        "value" => server,
        "attr" => "ask"
      },
      "args" => [message],
      "keywords" => [%{"arg" => "timeout", "value" => timeout}]
    }}
  end
}

# Use supplemental during transformation
{:ok, doc} = Builder.from_source(elixir_source, ElixirAdapter)
{:ok, python_ast} = Python.from_meta(doc.ast, doc.metadata, supplemental: supplemental)
```

### API Design

```elixir
defmodule Metastatic.Supplemental do
  @moduledoc """
  Supplemental modules provide mappings for MetaAST constructs that are not
  natively supported in target languages.
  """

  @type construct_handler :: (term() -> {:ok, ast_node} | {:error, String.t()})
  @type supplemental_map :: %{atom() => construct_handler}

  @doc """
  Register a supplemental module for an adapter.
  
  ## Example
  
      supplemental = Supplemental.new()
      |> Supplemental.register(:actor_call, &MyActorSupplemental.handle_actor_call/3)
      |> Supplemental.register(:spawn_process, &MyActorSupplemental.handle_spawn/1)
  """
  def new(), do: %{}
  
  def register(supplemental, construct_type, handler) do
    Map.put(supplemental, construct_type, handler)
  end
end
```

### Adapter Integration

Adapters check for supplemental handlers before failing:

```elixir
defmodule Metastatic.Adapters.Python.FromMeta do
  def transform({:actor_call, server, message, timeout}, metadata, opts \\ []) do
    supplemental = Keyword.get(opts, :supplemental, %{})
    
    case Map.get(supplemental, :actor_call) do
      nil ->
        {:error, "Actor model constructs not natively supported in Python"}
      
      handler ->
        handler.(server, message, timeout)
    end
  end
end
```

### Trade-offs

**Pros:**
- Graceful degradation with clear error messages
- Opt-in complexity - users only add supplemental modules when needed
- Extensible - community can build supplemental libraries
- Type-safe - errors caught at transformation time, not runtime

**Cons:**
- Additional API surface to maintain
- Users need to understand which constructs require supplemental modules
- Supplemental modules may produce non-idiomatic code in target language
- Testing burden increases (need to test with/without supplemental modules)

### Open Questions

1. **Discovery:** How do users discover which constructs need supplemental modules?
   - Static analysis tool?
   - Documentation with compatibility matrix?
   - Runtime warnings during validation?

2. **Standardization:** Should Metastatic provide "official" supplemental modules for common libraries?
   - `metastatic_python_actors` for pykka
   - `metastatic_js_actors` for nact/comedy
   - Community-maintained vs core-maintained?

3. **Composition:** How do supplemental modules compose?
   - User provides multiple supplemental modules for different concerns
   - Priority/precedence rules?

4. **Versioning:** How to handle library version compatibility?
   - Supplemental module declares: "supports pykka >= 3.0"
   - Version checking at transformation time?

5. **Validation:** Should MetaAST validator know about supplemental modules?
   - Validate with supplemental: allow {:actor_call, ...}
   - Validate without: reject {:actor_call, ...}

### Related Concerns

This connects to broader architectural questions:

- **M2 Minimalism:** Should M2 only include truly universal constructs?
- **Language Tiers:** Should we formalize language support levels (Tier 1: full native support, Tier 2: requires supplemental, Tier 3: unsupported)?
- **Adapter Contracts:** What guarantees should adapters provide about supported constructs?

### Implementation Summary

✅ **Completed:**
1. Surveyed language ecosystems (actor model, async patterns)
2. Prototyped and implemented full API
3. Created two official supplemental modules (Pykka, Asyncio)
4. Integrated with BEAM and Python adapters
5. Comprehensive documentation and testing
6. Zero impact on existing adapters (backward compatible)

---

## Future Concerns (Placeholders)

### Concern #2: TBD
<!-- Add additional concerns as they arise -->

### Concern #3: TBD
<!-- Add additional concerns as they arise -->

---

## Notes

- This document is **not** a roadmap or commitment
- Ideas here are **unverified** and require validation
- Some concerns may be resolved by saying "no" or "not now"
- Document updated: 2026-01-21
