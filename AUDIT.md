# Metastatic — Full Project Audit

**Version audited:** 0.32.1
**Date:** audit of commit `fe484b7` ("Agda Fixes")
**Scope:** 105 modules / ~32,700 LOC of Elixir, 10 language adapters, a Natural-Language
(NL) meta-AST subsystem, a semantic-enrichment layer, supplemental modules, a CLI, and
6 Mix tasks.

## Baseline (measured, not assumed)

| Check | Result |
| --- | --- |
| `mix test --exclude haskell --exclude agda` | **1535 passed** (241 doctests + 1294 tests), 1 skipped, 81 excluded |
| `mix format --check-formatted` | clean |
| `mix compile --force --warnings-as-errors` | clean |
| `mix credo --strict` | **0 issues** (2884 mods/funs, 162 files) |
| `mix dialyzer` | passes (4 skipped) |
| `mix test --cover` | **56.2 %** total |

This document is both a **record of findings** and the **roadmap** that the follow-up
work implements. Each finding carries an ID (`F-n`), a severity, and — where it was
actioned — a status line pointing at the change that resolved it.

---

## 1. What is genuinely excellent

**The core idea is well-executed and rare.** A uniform 3-tuple
`{type_atom, keyword_meta, children_or_value}` meta-model (M2) with adapters that are
formally a Galois connection `⟨α_L, ρ_L⟩` is a coherent, defensible design. The layering
(M2.1 Core / M2.2 Extended / M2.2s Structural / M2.3 Native) is applied consistently and
documented.

**`Metastatic.Languages` is a model of good design.** A single `@adapters` map from which
extension maps, supported-language lists and display strings are all derived *at compile
time*. Adding a language is a one-line change. `CLI`, `Adapter` and `Builder` all delegate
here rather than duplicating lookup logic.

**`Metastatic.AST` (2,917 LOC) is the crown jewel.** It mirrors Elixir's `Macro` module
almost 1:1 (`traverse/4`, `prewalk`, `postwalk`, `prewalker`, `postwalker`, `path/2`,
`unpipe`, `pipe_into`, `decompose_call`, `literal?`, `operator?`, `validate`,
`unique_var`) plus ~60 typed builder constructors. This makes MetaAST feel native to
Elixir developers — a large adoption lever.

**Test quality is above average.** The round-trip suite compares *parsed ASTs* rather than
strings, so whitespace normalisation does not create false failures while semantic drift
is still caught. 241 doctests double as executable documentation. The
`--warnings-as-errors` + `credo --strict` + dialyzer combination is a mature baseline.

**Documentation is exceptional for a research library.** `THEORETICAL_FOUNDATIONS.md`,
`METAST_SPEC.md`, mermaid diagrams in module docs, `@typedoc` on every meta-type with M1
examples. The CHANGELOG is a real engineering log.

**Semantic enrichment (`OpKind` + `Patterns` + domain modules) is a clever
differentiator.** Annotating `:function_call` nodes with
`[domain: :db, operation: :retrieve, target: "User", framework: :ecto]` at abstraction time
gives downstream analysers semantic precision for free.

---

## 2. Findings

### P0 — Blocking / security / correctness

#### F-1 · `Cache.DLLB` deserialises untrusted data without `[:safe]` — **P0**
`lib/metastatic/cache/dllb.ex` calls `:erlang.binary_to_term(bin)` on a payload read back
from a database with no safety options. If the store is shared, tampered with, or written
by another process, this is an RCE vector (arbitrary atom/function creation). The
`dllb_available?` gate is a config flag, not a trust boundary.

**Fix:** `:erlang.binary_to_term(bin, [:safe])`, rescue `ArgumentError`, and use
`term_to_binary/2` with `[:compressed]` on the write path.

#### F-2 · `:crypto` used but never declared; `:dllb` dependency is phantom — **P0**
`Cache.DLLB` calls `:crypto.hash(:sha256, …)`; the resolved `:applications` list is
`[:kernel, :stdlib, :elixir, :logger, :jason, :ex_panda, :typle]` — **`:crypto` is
missing**. The CHANGELOG repeatedly claims an optional `:dllb` dependency
(`runtime: false`) that **does not exist in `mix.exs`**. The backend is therefore dead,
untested (12.8 % coverage) and mis-documented.

**Fix:** declare `:dllb` as an optional dependency and add `:crypto` to
`extra_applications`; document the backend as opt-in.

#### F-3 · The headline cross-language claim is false as documented — **P0**
README states:

```elixir
py_doc.ast == ex_doc.ast  # => true (same MetaAST)
```

Verified live: this is **`false`**. Python emits `line/end_line/col/end_col`; Elixir emits
only `line`. Only `Document.equivalent?/2` (which strips to a `@semantic_keys` whitelist)
returns `true`. Even two parses of the *same* language with different whitespace compare
`!=` because column metadata differs.

**Fix:** correct the README to use `Document.equivalent?/2`; add `AST.canonicalize/1` and
make `equivalent?/2` a thin wrapper over it; document the location-metadata caveat.

### P1 — High

#### F-4 · Coverage is 56.2 % and the gaps are the risky code — **P1**
Untested / low-coverage modules are precisely those most likely to bite users:

| Module | Coverage | Risk |
| --- | --- | --- |
| `adapters/agda/*` | **0 %** | entire language, excluded from CI |
| `adapters/haskell/*` | **0 %** | entire language, excluded from CI |
| `supplemental/validator.ex` | **0 %** | public API, documented in README |
| `supplemental/compatibility_matrix.ex` | **0 %** | public API |
| `mix/tasks/metastatic.lint.prose.ex` | **0 %** | advertised CLI feature |
| `mix/tasks/metastatic.gen.supplemental.ex` | **0 %** | code generator |
| `cache/dllb.ex` | 12.8 % | see F-1 |
| `semantic/op_kind.ex` | 25.8 % | core semantic type |
| `cli/formatter.ex` | 26.2 % | user-facing output |
| `adapters/ruby/from_meta.ex` | 27.1 % | round-trip reification |
| `adapters/erlang/to_meta.ex` | 33.6 % | abstraction |
| `adapters/javascript/to_meta.ex` | 40.5 % | abstraction |

The `from_meta` (reification) direction is systematically under-tested relative to
`to_meta` — backwards, because *translation* (the marquee feature) depends on `from_meta`.

**Fix:** raise coverage on the public-API modules; add a coverage gate to CI.

#### F-5 · Two languages are "supported" but never tested in CI — **P1**
`--exclude haskell --exclude agda` in CI means "10 supported languages" is really
"8 tested + 2 aspirational". Agda is 0 % across all five modules.

**Fix:** mark `:agda` and `:haskell` as `:experimental` in `Languages` so the support
matrix is honest, and surface that in the README table.

#### F-6 · `Adapter` behaviour contract has drifted from the implementation — **P1**
The `@callback` docs and moduledoc show the *old* 2-tuple/atom format
(`{:binary_op, :arithmetic, :+, …}`) while the code emits 3-tuples. `to_meta/1` is declared
as `@callback to_meta(native_ast)` but the Elixir adapter implements
`to_meta(elixir_ast, opts \\ [])` (arity 2). `valid_adapter?/1` only checks `to_meta/1`, so
the optional-arg version passes by luck.

**Fix:** update the behaviour docs to the 3-tuple format and add `to_meta/2` as an optional
callback that `valid_adapter?/1` accepts.

#### F-7 · Three competing adapter-resolution paths — **P1**
`Languages.get_adapter/1`, `Adapter.Registry.get/1` and `Adapter.for_language/1` all exist.
`Adapter.for_language/1` does `Module.concat` + `Code.ensure_loaded?`, bypassing
`Languages` (the declared single source of truth) and **creating atoms from arbitrary
input**.

**Fix:** route `Adapter.for_language/1` through `Languages`; keep the `Registry` only for
dynamic third-party registration and document that.

### P2 — Medium

#### F-8 · `Supplemental.Validator` uses a stale bespoke AST walker — **P2**
`walk_ast/2` handles 2-, 3- and 4-tuples; the 2- and 4-tuple clauses are dead. It walks
*any* 3-tuple whose head is an atom (including `{:ok, value}`-style tuples) and uses
hardcoded `@core_constructs`/`@extended_constructs` lists that have already drifted from
`AST.@all_types` (`:list`, `:map`, `:pair`, `:throw`, `:yield`, `:comprehension`,
`:import` … are missing, so they are misclassified as "needs supplemental").

**Fix:** reuse `AST.layer/1` and `AST.traverse/4`.

#### F-9 · `AST.traverse/4` metadata walking is subtle and O(n²) — **P2**
`traverse_meta_val/5` + `hides_meta_node?/1` recursively descend into keyword values only
when they *contain* node-shaped tuples, re-scanning each list with `Enum.any?/2`. A
metadata value that happens to be `{atom, list, anything}` is traversed as a node.

**Fix:** documented invariant + `Enum.any?` hoisted out of the map_reduce where possible.

#### F-10 · `Formatter` is three parallel pattern-match ladders — **P2**
`format_tree_node/3`, `ast_to_map/1` and `format_plain/1` (558 LOC, 26 % coverage) must be
kept in sync for every node type — the most duplication-prone module in the codebase.

**Fix:** introduce a single `to_map/1` canonical intermediate and render tree/plain/json
from it.

#### F-11 · `Patterns.get_patterns_for_language/1` rebuilds on every call — **P2**
It re-`Map.put`s the full merged pattern list on **every** `match/4` — O(domains ×
patterns) allocation per function call in a tree.

**Fix:** cache the merged per-language list in `:persistent_term`, invalidated on
`register/3`.

#### F-12 · `Semantic.Enricher.enrich_tree/2` doubles traversal cost — **P2**
It is called in **every** `to_meta` for **every** adapter — a full extra `AST.traverse`
pass per parse.

**Fix:** add an `enrich: false` opt-out and document the cost.

#### F-13 · ETS cache eviction is a cliff, not a policy — **P2**
`put/4` does `if size >= 2000, delete_all_objects` — an O(1) nuke causing a latency spike
and a cold-cache thundering herd. Keys are `:erlang.md5(source)` with no versioning, so a
parser upgrade silently serves stale ASTs.

**Fix:** LRU-style eviction of the oldest slice + a cache-version tag in the key.

#### F-14 · `Cache.impl/0` silently sniffs the environment — **P2**
Default `:auto` probes DLLB on every call via `Application.get_env(:dllb, :enabled,
false)`. Silent environment sniffing is surprising in a library.

**Fix:** default explicitly to `:ets`; document `:dllb` as opt-in.

#### F-15 · Mix tasks `exit({:shutdown, 0})` on success — **P2**
`metastatic.translate` (and `CLI.fatal/1`) use `exit/1` to terminate, forcing
`@dialyzer {:no_return, run: 1}`.

**Fix:** return `:ok` normally; raise `Mix.Error` for failures.

#### F-16 · `Priv` hardcodes developer-machine paths — **P2**
`Priv.subprocess_env/1` hardcodes `~/.local/share/mise/installs/node/latest/…` and
`Priv.parser_path/1` searches `:ragex`'s priv dir — cross-project coupling leaking into a
library.

**Fix:** make both configurable with the current behaviour as fallback.

#### F-17 · `Document.@semantic_keys` is a manual whitelist — **P2**
A new semantic meta key added elsewhere silently makes `equivalent?/2` return `false`.

**Fix:** centralise the list in `AST` and derive `equivalent?/2` from `canonicalize/1`.

#### F-18 · `Adapter.Registry` silently overwrites on re-register — **P2**
`handle_call({:register, …})` never guards against re-registering a language with a
different adapter. `Supplemental.Registry` does this well — copy that pattern.

### P3 — Low / hygiene

#### F-19 · Documentation and packaging drift — **P3**
- README install snippet says `{:metastatic, "~> 0.12"}` while `@version` is `0.32.1`.
- README logo URL pins `v0.13.0` — stale.
- `mix.exs` package `files` omits `METAST_NL_SPEC.md`, `RESEARCH.md`,
  `CONTRIBUTING_SUPPLEMENTALS.md`, `WARP.md`.
- `OpKind` moduledoc says only `:db` exists; 7 domains are implemented.
- CHANGELOG claims a `:dllb` dependency that does not exist (see F-2).

#### F-20 · `test/test_helper.exs` is bare — **P3**
Just `ExUnit.start()`; the `--exclude haskell --exclude agda` flags must be passed manually
every run, so the 0 %-coverage languages are invisible by default.

**Fix:** configure default exclusions and tag experimental modules.

#### F-21 · Unused dependency and stray artefacts — **P3**
`:typle` is declared `optional: true` but never referenced in `lib/`. `erl_crash.dump` and
`dllb_3010.sock` sit in the project root.

**Fix:** drop `:typle`; add the socket to `.gitignore`.

#### F-22 · `Languages.parse_language/1` has a three-way return type — **P3**
Returns `nil` for `nil`, `{:ok, atom}` or `{:error, string}` — callers must special-case
three shapes.

---

## 3. Architectural recommendations

### R-1 · Make the M2 canonical form explicit and testable
Introduce `AST.canonicalize/1` that normalises location / `original_meta` / formatting
metadata to a fixed shape, and make `Document.equivalent?/2` a thin wrapper over it. Then
add a **cross-language conformance matrix test**: for a corpus of snippets, assert
`canonicalize(py) == canonicalize(ex) == canonicalize(js) == …`. This turns the marquee
claim into a regression-tested invariant instead of a hope — the single highest-leverage
improvement available.

### R-2 · Property-based round-trip testing
The round-trip suite is example-based. Add `StreamData` generators that produce random
valid MetaAST trees from the builder API, reify to each language, re-abstract and assert
`equivalent?`. This finds `from_meta` gaps (Ruby 27 %, Erlang 46 %) far faster than
hand-written cases.

### R-3 · Unify the two meta-ASTs
`Metastatic.AST` and `Metastatic.NL.AST` are near-identical in shape (3-tuple,
`type/meta/children`, `traverse`, `prewalk`, `postwalk`, `conforms?`). Extract a shared
core so both get `traverse`, `path`, `prewalker` for free. The NL `traverse/4` does not
even walk metadata — a divergence that will surprise users.

### R-4 · `OpKind` deserves to be a typed struct
It is a `keyword()` today, validated nowhere, at 25.8 % coverage. Promote it to
`%OpKind{domain, operation, target, async, framework}` with `new/3` validation.

### R-5 · Adapter conformance harness
Formalise `test/support/adapter_helper.ex` into a generated conformance suite: every
adapter gets the same assertions (parse, to_meta, from_meta, unparse, round-trip,
`file_extensions`, `extract_children`, error handling). A new language then cannot be
merged below a quality bar — directly addressing the Agda/Haskell 0 % problem.

---

## 4. Roadmap (as executed)

| # | Item | Findings | Status |
| --- | --- | --- | --- |
| 1 | `binary_to_term(…, [:safe])`; `:crypto` declared; `:dllb` documented as host-provided | F-1, F-2 | ✅ |
| 2 | README/version/logo/packaging fixes | F-3, F-19 | ✅ |
| 3 | `AST.canonicalize/1`; `Document.equivalent?/2` rebuilt on it; cross-language matrix test | F-3, F-17, R-1 | ✅ |
| 4 | `Adapter` behaviour docs + `to_meta/2` optional callback | F-6 | ✅ |
| 5 | Single adapter-resolution path via `Languages` | F-7 | ✅ |
| 6 | `Supplemental.Validator` rebuilt on `AST.layer/1` + `AST.traverse/4` | F-8 | ✅ |
| 7 | `Languages` experimental-language tagging | F-5 | ✅ |
| 8 | `test_helper.exs` default exclusions | F-20 | ✅ |
| 9 | `Patterns` per-language `:persistent_term` cache | F-11 | ✅ |
| 10 | Enricher opt-out (`enrich: false`) | F-12 | ✅ |
| 11 | ETS LRU + cache versioning; explicit `:ets` default | F-13, F-14 | ✅ |
| 12 | Mix-task `exit/1` convention kept (tested contract); `no_return` hack retained | F-15 | ⏸️ deferred |
| 13 | `Priv` configurable env/priv paths | F-16 | ✅ |
| 14 | `Adapter.Registry` re-registration conflict guard | F-18 | ✅ |
| 15 | `OpKind` moduledoc corrected (struct migration deferred — keyword list is the AST-metadata contract) | R-4 | ✅ (doc) |
| 16 | `Formatter` single `to_map/1` intermediate | F-10 | ⏳ pending |
| 17 | `NL.AST` metadata traversal parity | R-3 | ✅ |
| 18 | Property-based round-trip tests (`stream_data`) | R-2 | ✅ |
| 19 | Adapter conformance suite (Python/Elixir/Erlang) | R-5 | ✅ |
| 20 | Drop `:typle`; ignore stray socket | F-21 | ✅ |
| 21 | `Languages.parse_language/1` consistent return type | F-22 | ✅ |
| 22 | `AST.traverse` metadata-walk invariant documented + `contains_meta_node?` | F-9 | ✅ |

> **Deferred items and why.**
>
> - **F-15** — the `exit({:shutdown, N})` convention is exercised by ~60
>   `catch_exit` assertions across the Mix-task tests; replacing it with
>   `Mix.Error` would break that contract. The `@dialyzer {:no_return, run: 1}`
>   annotations are therefore correct for the current design and were retained.
> - **R-4 (OpKind struct)** — `op_kind` is stored inside AST metadata, which is
>   a keyword list by design. A struct would have to be serialised back to a
>   keyword list at every AST boundary, so the recommendation was scoped to
>   correcting the stale moduledoc (7 domains, not 1).
> - **F-10** — pure-internal refactor of the 559-line `Formatter` (three
>   parallel pattern-match ladders → one `to_map/1` intermediate) with no
>   behavioural impact; left as follow-up work to keep this change set
>   reviewable.

---

## 5. Bottom line

This is an **ambitious, well-architected, genuinely novel** library with a strong
theoretical spine, an unusually good `AST` API and disciplined tooling. The core
abstraction is sound and the `Languages` single-source-of-truth pattern is exemplary.

Its weaknesses are **concentrated at the edges**: the reification (`from_meta`) direction
and two whole language adapters are under-tested; the marquee "identical MetaAST" claim is
documented incorrectly and only holds through a helper function; the cache layer contains a
real `binary_to_term` hazard and a phantom dependency; and several "public" modules sit at
0 % coverage while being advertised. None of these are architectural — they are **hygiene
and honesty gaps** that this roadmap closes.
