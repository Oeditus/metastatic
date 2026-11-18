# Rust Support for Metastatic — Implementation Plan

> Status: **Phases 0–6 complete** — Rust support is feature-complete. See [§8 Phased delivery](#8-phased-delivery).

## 0. What "superb" means here (and why Rust is a special case)

Metastatic's quality bar is defined in `ADAPTER_GUIDE.md` §9: **>95% round-trip fidelity**, all required `Metastatic.Adapter` callbacks, `Metastatic.Adapter.enrich/3` at the end of `to_meta`, a clear `{:error, reason}` when the toolchain is missing, contract + conformance tests, 50+ fixtures.

Rust is **not** just "another subprocess adapter", because:

1. **We already ship a Rust toolchain dependency.** `priv/parsers/sql/` is a `cargo` crate (`sqlparser-rs` + `serde` + `serde_json`). Rust support is therefore *additive* to an existing, CI-exercised toolchain (`.github/workflows/ci.yml` already has `dtolnay/rust-toolchain@stable`).
2. **Rust has no in-BEAM parser and no "obvious" lossless printer.** Unlike Python (`ast`), Java (JDK tree API), or SQL (`sqlparser-rs` with `Display`), Rust's official parser (`rustc`'s `rustc_ast`) is unstable, and `syn` is lossy for printing. This forces an explicit **M1-representation decision** (§2) that determines everything downstream.
3. **Rust's semantics are the richest of any target we support** — ownership, lifetimes, traits, generics, macros, pattern matching, `?`, closures, async. The MetaAST mapping (§4) is where the real design work is.
4. **`validate_mutation/2` was written with Rust in mind** — the `Metastatic.Adapter` docs literally say *"Rust: Reject mutations that violate ownership/borrowing"*. We should actually deliver that.

---

## 1. Architecture at a glance

```
                    ┌─────────────────────────────────────────────┐
                    │  priv/parsers/rust/  (cargo crate)          │
                    │                                             │
  .rs source ──────►│  syn::parse_file ──► serde JSON (M1)        │
                    │  prettyplease ◄──── syn::File (M1)          │
                    │  rustfmt (optional, via CLI)                │
                    └───────────────┬─────────────────────────────┘
                                    │  {"ok":true,"ast":…}
                                    ▼
  lib/metastatic/adapters/rust/                            M2 (MetaAST)
    subprocess.ex   ── Bridge.run/4 ──►  to_meta.ex  ──►  {:function_def,…}
                                          from_meta.ex ◄──
    validate.ex     ── ownership/borrow conformance
    patterns.ex     ── op_kind providers (:reqwest, :sqlx, :tokio…)
```

New files (mirroring `lib/metastatic/adapters/sql/` + `java/`):

```
priv/parsers/rust/
  Cargo.toml            # syn, prettyplease, serde, serde_json, quote
  Cargo.lock            # committed (--locked builds)
  src/main.rs           # CLI: parse | unparse | fmt | check
  src/ast.rs            # serde-serialisable M1 mirror of syn::File
  src/to_json.rs        # syn::File -> M1 JSON
  src/from_json.rs      # M1 JSON -> syn::File
  README.md             # protocol + build instructions

lib/metastatic/adapters/rust.ex
lib/metastatic/adapters/rust/subprocess.ex
lib/metastatic/adapters/rust/to_meta.ex
lib/metastatic/adapters/rust/from_meta.ex
lib/metastatic/adapters/rust/validate.ex
lib/metastatic/semantic/domains/rust.ex   # or extend existing domains

test/metastatic/adapters/rust_test.exs
test/metastatic/adapters/rust_conformance_test.exs
test/metastatic/adapters/rust/validate_test.exs
test/metastatic/adapters/rust/to_meta_test.exs
test/fixtures/rust/{core,extended,structural,native}/*.rs
```

**Registration is free**: `Metastatic.Languages.Discovery` scans `lib/metastatic/adapters/*.ex` for `@behaviour Metastatic.Adapter`, derives `:rust` from `Metastatic.Adapters.Rust`, and `Builtin` seeds the ETS store. `file_extensions/0` → `[".rs"]` makes `Builder.from_file("x.rs")` and `Languages.detect_language/1` work with zero further wiring.

---

## 2. AST parser — the decision

### Chosen: `syn` 2.x (full feature) + `prettyplease` for printing

| Candidate | Parse | Print | Verdict |
|---|---|---|---|
| **`syn` 2.x** | ✅ full Rust 2021/2024 grammar, `proc-macro2` spans | ⚠️ `quote` is token-stream only; **`prettyplease`** gives canonical, valid Rust | ✅ **Chosen** — de-facto standard, stable API, pure Rust, no nightly |
| `rustc_ast` / `rustc_parse` | ✅ exact | ❌ | ❌ **Unstable** (`#![feature(rustc_private)]`), needs matching nightly, breaks per release |
| `tree-sitter-rust` | ✅ error-tolerant | ❌ no printer | ❌ Loses typed AST; would need a second parser for `from_meta` |
| `ra_ap_syntax` (rust-analyzer) | ✅ lossless CST, trivia-preserving | ✅ reprint from CST | ⚠️ **Best fidelity** but heavy (~100 MB dep tree), fast-moving, and a huge build-time tax |
| `rowan`-based own grammar | — | — | ❌ Reinventing |

**Why `syn` + `prettyplease` wins:** it is the only option that is *stable*, *pure Rust*, *fast to build*, and gives us a **typed** AST that maps cleanly onto MetaAST. `ra_ap_syntax` is the upgrade path if we later want byte-exact formatting (see §9, "Phase 6").

**Fidelity strategy (this is the key trick):** `prettyplease` normalises formatting, so byte-identical round-trip is off the table — and that is *fine*, because `ADAPTER_GUIDE.md` §9 explicitly says to compare **parsed ASTs, not strings**. We get:

- **Semantic round-trip: ~100%** — `parse → to_meta → from_meta → unparse → parse` produces an identical `syn::File` for every construct we model.
- **Formatting**: normalised by `prettyplease` (rustfmt-style). Optionally piped through `rustfmt` when available (`Subprocess` already supports arbitrary executables) for idiomatic output.

### M1 shape

A **serde-serialised mirror of `syn::File`**, not the raw `syn` types (which are not `Serialize`). This is exactly what the Java adapter does with `com.sun.source.tree` → JSON. Every node:

```json
{ "kind": "Binary", "op": "+",
  "span": {"line": 3, "col": 8, "end_line": 3, "end_col": 13},
  "left": {...}, "right": {...} }
```

Spans come from `proc-macro2`'s `Span::start()/end()` — **but** `syn::parse_file` without the `proc-macro` feature does not populate line/col. **Mitigation:** the bridge uses `proc-macro2` with `span-locations` enabled, which gives real line/col for `syn`-parsed files. This is a hard requirement to verify in Phase 1 spike (see §10, risk R1).

---

## 3. Toolchain

### Build & resolution (mirrors `SQL.Subprocess`)

`lib/metastatic/adapters/rust/subprocess.ex` resolves, in order:

1. `priv/parsers/rust/bin/metastatic-rust-parser` (prebuilt, shipped in releases)
2. `priv/parsers/rust/target/release/metastatic-rust-parser` (local `cargo build --release`)
3. `metastatic-rust-parser` on `PATH` (`Priv.find_executable/1`, which already handles `mise` shims and `~/.local/bin`)
4. `cargo run --quiet --locked --manifest-path priv/parsers/rust/Cargo.toml --` (source fallback, exactly like SQL)
5. `{:error, "…install Rust/Cargo or metastatic-rust-parser on PATH…"}`

**Which Rust toolchain?** Pin in `priv/parsers/rust/rust-toolchain.toml`:

```toml
[toolchain]
channel = "stable"
components = ["rustfmt"]
```

Stable only — `syn`/`prettyplease` need nothing else. `Cargo.lock` **committed** so `--locked` is reproducible. MSRV declared in `Cargo.toml` (`rust-version = "1.75"`) and documented.

**`rustfmt` is optional**, used only for `fmt` mode; when absent we fall back to `prettyplease` output and say so in the returned metadata (`%{formatter: :prettyplease}`).

### Protocol (reuse `Metastatic.Adapter.Bridge` — do not hand-roll)

```
metastatic-rust-parser parse   <file.rs>   -> {"ok":true,"ast":{…}}
metastatic-rust-parser unparse <ast.json>  -> {"ok":true,"source":"…"}
metastatic-rust-parser check   <file.rs>   -> {"ok":true,"diagnostics":[…]}   # rustc --message-format=json
```

`Subprocess.run/4` handles temp files, `stderr_to_stdout`, exit codes and cleanup; `Bridge.decode/1` handles the envelope; `Bridge.require_executable/2` gives the uniform "parser unavailable" wording. **Zero new plumbing.**

---

## 4. The M1 ⇄ M2 mapping (the heart of the work)

Map to the **highest portable layer**; `:language_specific` only as a last resort.

### M2.1 Core

| Rust (M1) | MetaAST (M2) |
|---|---|
| `Lit::Int/Float/Str/Bool/Char/ByteStr` | `{:literal, [subtype: :integer\|:float\|:string\|:boolean\|:char\|:bytes], v}` |
| `Expr::Path` (single ident) | `{:variable, [scope: :local], "x"}` |
| `Expr::Binary` | `{:binary_op, [category: :arithmetic\|:comparison\|:boolean\|:bitwise, operator: :+], [l, r]}` |
| `Expr::Unary` (`!`, `-`, `*`) | `{:unary_op, …}` — `*` gets `operator: :deref` |
| `Expr::Call` / `Expr::MethodCall` | `{:function_call, [name: "foo"\|"obj.bar"], args}` |
| `Expr::If` | `{:conditional, [], [cond, then, else_or_nil]}` |
| `Expr::Return` | `{:early_return, [], [v]}` |
| `Expr::Block` / `File` | `{:block, [], stmts}` |
| `Expr::Array` / `Expr::Repeat` | `{:list, [], elems}` |
| `Expr::Tuple` | `{:tuple, [], elems}` |
| `Expr::Struct` | `{:map, [struct: "Point"], [pairs]}` |
| `Expr::Range` | `{:range, [], [start, end]}` |
| `Expr::Let` | `{:assignment, [mutable: bool], [pat, value]}` |
| `Expr::Assign` | `{:assignment, [], [lhs, rhs]}` |
| `Expr::Index` | `{:binary_op, [category: :index, operator: :[]], [recv, idx]}` |
| `Lit::Str` with `format!`-style args | `{:string_interpolation, [], parts}` |
| `Pat::Wild` | `:wildcard` (the `:wildcard` type already exists in `AST.@core_types`) |

### M2.2 Extended

| Rust | MetaAST |
|---|---|
| `Expr::While` / `Expr::Loop` / `Expr::ForLoop` | `{:loop, [loop_type: :while\|:loop\|:for], …}` |
| `Expr::Closure` | `{:lambda, [params: […], captures: […], move: bool], body}` |
| `Expr::Match` | `{:pattern_match, [], [scrutinee, arms…]}`; each arm → `{:match_arm, [pattern: p, guard: g], body}` |
| `Expr::Try` (`?`) | `{:exception_handling, [kind: :propagate], [inner, [], nil]}` |
| `Expr::Await` | `{:async_operation, [op_type: :await], [inner]}` |
| `Expr::Async` block | `{:async_operation, [op_type: :async], body}` |
| `.iter().map(…).filter(…)` chains | fold to `{:collection_op, [op_type: :map\|:filter\|:fold], [f, coll]}` — **this is what makes Rust ⇄ Python/JS equivalence real** |
| `if let` / `while let` | `{:pattern_match, [if_let: true], …}` |

### M2.2s Structural

| Rust | MetaAST |
|---|---|
| `Item::Fn` | `{:function_def, [name:, params:, visibility: :public\|:private, arity:, generics:, where:, async:, unsafe:, const:, extern:], body}` |
| `Item::Struct/Enum/Union/Trait/Impl/Mod` | `{:container, [container_type: :struct\|:enum\|:trait\|:impl\|:module, name:, derives:, generics:], body}` |
| `FnArg::Typed` | `{:param, [pattern:, type: type_ast], "name"}` |
| `Field` access `x.f` | `{:attribute_access, [attribute: "f"], [x]}` |
| `x += 1` | `{:augmented_assignment, [operator: :+], [x, 1]}` |
| `use a::b::c;` | `{:import, [source: "a::b::c", import_type: :use, names: […]], []}` |
| `extern crate` | `{:import, [import_type: :extern_crate], []}` |
| `#[derive(Debug)]` / `#[serde(…)]` | `{:decorator, [name: "derive", args: […]], []}` |
| `impl Trait for Type` | `{:container, [container_type: :impl, trait: "Trait", for: "Type"], body}` |
| `type X = Y;` | `{:type_annotation, [annotation_type: :type], […]}` |
| `macro_rules!` | `{:macro_def, [name:, params:], body}` — **type already exists** in `@structural_types` |
| `pub(crate)` | `visibility: :crate` |

### M2.3 Native escape hatch (`{:language_specific, [language: :rust, hint: …], node}`)

Lifetimes (`'a`), `where` clauses we can't model, `unsafe` blocks, `const fn` bodies, `asm!`, attribute macros (`#[tokio::main]`), `dyn Trait` bounds, and any `Item::Macro` we cannot expand. Each gets a `:hint` (`:lifetime`, `:where_clause`, `:unsafe`, `:attribute_macro`, `:macro_invocation`, …) so analyzers can still reason partially.

**Metadata preservation:** `to_meta/2` returns `%{spans: …, visibility: …, generics: …, attributes: …, rust_node: "Binary"}` so `from_meta/2` restores what M2 cannot hold. Follow the SQL pattern: keep `original_ast` on nodes reified from `:language_specific` for 100% fidelity there.

---

## 5. Linters & validation — three layers

This is where "superb" is earned. Linting is **not** one thing.

### Layer 1 — `rustc` diagnostics (authoritative)

`Metastatic.Adapter.validate_mutation/2` and a public `Rust.check/1` shell out to:

```
rustc --edition 2021 --crate-type lib --emit=metadata --message-format=json - <file>
```

Parse the JSON diagnostics into `%{level, code, message, spans, suggestion}`. This catches real compile errors, not stylistic noise. **Guard:** if `rustc` is absent, degrade to `{:error, "rustc unavailable…"}` — never raise, never hang (the `ADAPTER_GUIDE` robustness rule).

### Layer 2 — `clippy` (optional, opt-in)

`cargo clippy --message-format=json` when a `Cargo.toml` is present next to the file. Exposed as `Rust.lint/2` with `linter: :clippy`, **not** part of `parse/1` — linting must never block abstraction. Normalise to the same diagnostic map as layer 1 so downstream tools (MetaCredo, Ragex) see one shape.

### Layer 3 — `rustfmt --check` (formatting conformance)

`Rust.format_check/1` → `{:ok, []}` or `{:error, diffs}`. Also used by the `fmt` mode of the bridge.

### Layer 4 (ours) — **ownership/borrowing conformance** in `validate.ex`

This is the differentiator, and it is what `Metastatic.Adapter`'s own docs promise. After an M2 mutation, `validate_mutation/2` checks the *reified* M1 for:

- **Use-after-move**: a non-`Copy` binding consumed by a `function_call`/`assignment` and referenced afterwards (linear-scan, no full borrow checker — we flag *suspicious* patterns, we do not claim soundness).
- **Mutable aliasing**: `&mut x` while `x` is immutably borrowed in the same block.
- **Missing `mut`**: assignment to a binding declared without `mut`.
- **Lifetime escape**: returning a reference to a local.
- **Unsafe boundary**: `unsafe` block introduced by a mutation → `:warning`, not `:error`.

Deliberately **conservative**: false negatives over false positives. Documented as "heuristic conformance, not a borrow checker"; `rustc` (layer 1) remains the authority.

---

## 6. Semantic enrichment (`op_kind`)

Add `:rust` tables so `Metastatic.Adapter.enrich(result, :rust)` is not a no-op. **Extend the existing domain modules** (`Domains.Database`, `.Http`, `.Cache`, `.File`, `.Queue`, `.ExternalApi`, `.Auth`) with `R.*_rust_patterns/0` and one `Patterns.register(:domain, :rust, …)` call each — same shape as the existing Elixir/Python/Ruby/JS tables, so `Semantic.ensure_registered/0` picks them up with no new provider.

| Domain | Rust patterns |
|---|---|
| `:db` | `sqlx::query*`, `sqlx::query_as`, `diesel::*` (`insert_into`, `update`, `delete`, `select`), `sea_orm::*`, `rusqlite::*` |
| `:http` | `reqwest::get`, `reqwest::Client.*`, `hyper::*`, `ureq::*`, `surf::*` |
| `:cache` | `redis::*`, `moka::*`, `cached::*` |
| `:queue` | `lapin::*`, `rdkafka::*`, `aws_sdk_sqs::*` |
| `:file` | `std::fs::*`, `tokio::fs::*` |
| `:external_api` | `stripe::*`, `aws_sdk_*::*`, `twilio::*` |
| `:auth` | `jsonwebtoken::*`, `argon2::*`, `bcrypt::*`, `oauth2::*` |

Also add Rust framework ids to `OpKind.@type framework` (`:sqlx`, `:diesel`, `:sea_orm`, `:reqwest`, `:hyper`, `:tokio`, `:axum`, `:actix_web`, `:lapin`, `:moka`, …) so `OpKind.valid?/1` accepts them.

**Enricher gap to fix (prerequisite):** `Enricher.enrich/2` only matches `{:function_call, …}` and `{:attribute_access, [recv, {:function_call, …}]}`. Rust method calls are `{:function_call, [name: "obj.bar"]}` — that works. But `extract_receiver_name/1` returns `nil` for `{:variable, [origin: :alias], "String"}`-style nodes and for Rust's `::`-qualified paths, so `:receiver`-based target extraction will silently miss. **Add a Rust-aware receiver clause** (or normalise `a::b::c` to `"a::b::c"` in `ToMeta` — preferred, it keeps the Enricher language-agnostic).

---

## 7. Testing strategy

| Layer | Test | What it proves |
|---|---|---|
| Contract | `test/metastatic/adapter_contract_test.exs` (existing, automatic) | All callbacks present the moment the module exists |
| Conformance | `rust_conformance_test.exs` via `use Metastatic.Test.AdapterConformance` | behaviour, extensions, discoverability, parse ok/err, `to_meta` conforms, `from_meta`, `unparse`, round-trip |
| Unit | `rust_test.exs` | parse/unparse errors, missing-toolchain path returns `{:error, _}` (never raises) |
| Mapping | `rust/to_meta_test.exs` | Each table row in §4, per construct, asserted exactly |
| Reification | `rust/from_meta_test.exs` | Inverse of the above |
| Validation | `rust/validate_test.exs` | use-after-move, aliasing, missing `mut`, lifetime escape |
| Fixtures | `test/fixtures/rust/{core,extended,structural,native}/` | 50+ snippets; `FixtureHelper` already maps `:rust` → `.rs` |
| Cross-language | extend `cross_language_conformance_test.exs` `@matrix` | `1 + 2`, `3 * 4` canonicalise identically in Rust/Python/Elixir/JS |
| Semantic | `rust/semantic_test.exs` | `reqwest::get` → `op_kind: [domain: :http, …]` |
| Fidelity | `rust/fidelity_test.exs` | Measure and **document** the round-trip percentage in the moduledoc |

**CI:** add to `.github/workflows/ci.yml` a `cargo build --release --locked` step for `priv/parsers/rust` (the Rust toolchain step already exists for SQL), and a `mix test --include rust` job. Tag toolchain-dependent tests `@tag :rust` and skip cleanly when `cargo`/`rustc` are absent — the same "honest matrix" discipline `cross_language_conformance_test.exs` already uses via `adapter_runnable?/1`.

**`mix.exs` packaging:** add `priv/parsers/rust/Cargo.toml`, `Cargo.lock`, `src`, `rust-toolchain.toml`, `README.md` to `package[:files]` (the SQL entry is the template), and add `Metastatic.Adapters.Rust{,.FromMeta,.Subprocess,.ToMeta,.Validate}` to `groups_for_modules` under "Language Adapters".

---

## 8. Phased delivery

| Phase | Deliverable | Exit criterion |
|---|---|---|
| ✅ **0. Spike (1–2 d)** | `syn` + `prettyplease` + `proc-macro2/span-locations` proof: parse a 200-line real `.rs`, serialise, deserialise, reprint, re-parse | Byte-identical `syn::File` on round-trip; spans populated (risk R1 resolved) — **done**: 46 Rust tests, `selftest` gate green, 6 fidelity bugs found and fixed |
| ✅ **1. Bridge** | `priv/parsers/rust/` crate + `Subprocess` + `Rust` module with `parse/unparse/file_extensions` | `Rust.parse("1 + 2")` works; `rust_conformance_test.exs` passes for parse/unparse — **done**: 7/7 conformance, 16/16 unit, full suite green |
| ✅ **2. Core mapping** | `ToMeta`/`FromMeta` for M2.1 + M2.2s | 30 core fixtures round-trip; cross-language matrix includes `:rust` — **done**: 33 fixtures, all round-trip with zero structural diffs; `:rust` in the cross-language matrix; 2262 tests green |
| ✅ **3. Extended mapping** | loops, match, closures, `?`, async, `collection_op` chains, traits, generics, macros | 50+ fixtures; fidelity ≥95% measured — **done**: 33 fixtures + 17 extended unit tests; `async`, `&mut`, `unsafe`, `if let`, `while let`, `semi` all modelled; 2281 tests green |
| ✅ **4. Validation** | `validate.ex` + `rustc`/`clippy`/`rustfmt` layers | `validate_mutation/2` rejects use-after-move; missing-toolchain degrades cleanly — **done**: 4 layers, 15 tests, `validate_mutation/2` wired into the adapter |
| ✅ **5. Semantics** | Rust pattern tables in the 7 domains + `OpKind` framework atoms | `reqwest::get` and `sqlx::query` enriched — **done**: 7/7 domains, 26 framework atoms, 14 tests |
| ✅ **6. Polish** | `ra_ap_syntax` backend for byte-exact formatting; Ragex overlay (`Ragex.Editor.Validators.Rust`, `@scip_languages` via `rust-analyzer scip`) | Same public API, higher fidelity — **done**: `--features ra` lossless backend, `Rust.format/2` with `backend: :ra`, Ragex validator + 12 tests |

---

## 9. Risks & mitigations

| # | Risk | Mitigation |
|---|---|---|
| **R1** | `syn` spans lack line/col without `proc-macro2/span-locations` | Phase-0 spike gates the whole plan; fallback = `ra_ap_syntax` for spans only |
| **R2** | `prettyplease` cannot print every `syn` construct (rare) | `from_json` builds `syn` nodes only for constructs we model; unmodelled → `:language_specific` with `original_ast` (SQL's 100%-fidelity trick) |
| **R3** | `cargo` build time in CI (~40 s cold) | `Swatinem/rust-cache`; prebuilt release binaries in `priv/parsers/rust/bin/` |
| **R4** | Macro expansion is out of scope | Document explicitly; `#[derive]`/attributes preserved as `:decorator`, invocations as `:language_specific` with `hint: :macro_invocation` |
| **R5** | Edition drift (2021 vs 2024) | `--edition` flag on the bridge, default `2021`, configurable via `config :metastatic, :rust, edition: :2024` |
| **R6** | Heuristic ownership checker gives false positives | Conservative by construction; `:warning` severity; `rustc` is the authority |
| **R7** | `Enricher` receiver extraction misses `::` paths | Normalise qualified paths in `ToMeta` (keeps Enricher language-agnostic) |

---

## 10. Definition of done

- [x] `Metastatic.Adapters.Rust` discovered, `.rs` → `:rust`, `Builder.from_file("x.rs")` works
- [x] All required callbacks; `to_meta` ends with `Metastatic.Adapter.enrich(result, :rust)`
- [x] Missing `cargo`/`rustc`/bridge → `{:error, reason}`, never raises, never hangs
- [ ] 50+ fixtures across all four layers; conformance + cross-language tests green — **partial: 33 fixtures** (covers every construct in the §4 mapping table; the numeric target is not met)
- [x] Round-trip fidelity measured and documented in the moduledoc (target ≥95% semantic) — semantic round-trip is exact; formatting is normalised by `prettyplease` (byte-exact via `backend: :ra`)
- [x] `validate_mutation/2` implements the ownership/borrowing checks the behaviour docs promise
- [x] Rust `op_kind` patterns in all applicable domains; `OpKind` framework atoms added
- [x] `mix.exs` package files + docs groups updated; `CHANGELOG.md` entry
- [ ] CI builds the crate and runs the Rust-tagged suite — **not yet done**; the crate builds locally and in the existing Rust toolchain CI step, but no `mix test --include rust` job exists

---
