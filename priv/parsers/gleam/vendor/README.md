# Vendored Gleam crates

These are the gleam-lang/gleam crates the Metastatic Gleam bridge links
against, copied here so the bridge builds from a Hex package with **no
network access and no `gleam` toolchain at runtime**.

They are refreshed by `../vendor.sh`; do not edit them by hand.

```bash
./vendor.sh /path/to/gleam-checkout [git-ref]
```

## What is copied

| Crate | Why |
| :--- | :--- |
| `compiler-core` | `parse::parse_module/3` (the parser), the untyped AST, `ModuleExtra` |
| `format` | `pretty/3` — the reference printer behind `gleam format` |
| `src-span` | `SrcSpan`, the byte-offset position type |
| `pretty-arena` | `format`'s document arena |
| `erlang-generation` | a `compiler-core` dependency |
| `erlang-term-format` | an `erlang-generation` dependency |
| `hexpm` | **trimmed** — see below |

`compiler-core/templates` is *not* excluded even though it is 460 KB: `askama`
resolves `#[template(path = "gleam@@main.erl")]` and `docs.rs` `include_str!`s
its CSS/JS/fonts at **compile** time, so removing it makes the crate fail to
build. `.vendor-excludes` lists what *is* dropped (test fixtures, snapshots,
the JavaScript and Erlang backends the bridge never calls).

## What is generated rather than copied

### `Cargo.toml`

The upstream crates inherit dependency versions from the gleam workspace root
(`xxhash-rust.workspace = true`, `num-bigint.workspace = true`, …). Outside
that workspace Cargo refuses to load them at all:

```text
error inheriting `async-trait` from workspace root manifest's
`workspace.dependencies.async-trait`: failed to find a workspace root
```

`vendor.sh` therefore writes a workspace root here: the members list is fixed,
and the dependency table is copied out of upstream's `[workspace.dependencies]`
and filtered to the keys the vendored crates actually reference. A version bump
is therefore a one-command operation, and the vendored code resolves to exactly
the versions `gleam build` resolves to.

### `hexpm/`

Upstream `hexpm` is a full Hex API client: HTTP, protobuf payloads, RSA
signature verification, OAuth. `gleam-core` names only:

* `hexpm::version::{Version, Range, Identifier, LowestVersion}` — the version
  algebra behind manifests, requirements and the "wrong compiler version"
  diagnostic;
* `hexpm::ApiError` — a variant list `gleam_core::error::Error` matches
  exhaustively;
* a handful of data types (`Package`, `Release`, `Dependency`, `Config`, …) and
  the `api_*_request`/`api_*_response` functions `gleam_core::hex` builds.

Keeping the whole crate would pull in `ring`, `prost` and a `build.rs` — a
build-time toolchain dependency for a parser that never talks to Hex. So:

* `hexpm/src/version.rs` and `hexpm/src/version/{lexer,parser}.rs` are copied
  **verbatim** (minus their `#[cfg(test)] mod tests` declarations, whose files
  are not copied);
* `hexpm/src/lib.rs` and `hexpm/Cargo.toml` are **hand-maintained** and
  preserved verbatim across a refresh. They reproduce the data types, the
  `ApiError` variant list and the request builders, and drop the network stack.
  The tarball checksum is verified with a 40-line SHA-256 rather than a crypto
  crate.

After a version bump, re-check those two files against upstream
`hexpm/src/lib.rs`. A new `ApiError` variant or a changed field is a **compile
error in `gleam-core`**, which is exactly the tripwire that keeps the shim
honest — the bridge cannot silently drift from the compiler it parses for.

## This directory is optional at packaging time

Everything above describes the **default** build, which links these crates and
is what a normal `mix hex.build` ships.

`HEX_BUILD=1` produces a *source-only* package that omits this directory
entirely (7.7 MB → 3.0 MB). That build uses `Cargo.source-only.toml` instead of
`Cargo.toml`, because Cargo resolves a `path` dependency's manifest even when
the feature enabling it is off:

```text
error: no matching package named `gleam-core` found
location searched: vendor/compiler-core
```

So a package without `vendor/` must also ship a manifest that does not name it.
`mix metastatic.package.gleam --source-only` performs the swap and restores the
original afterwards.

The source-only build has no parser: it formats and unparses via
`gleam format --stdin` and reports that `parse` is unsupported. See
`Metastatic.Adapters.Gleam` for why that cannot be closed later — `gleam-core`
is not on crates.io, and the `gleam` CLI exposes no AST.

## Why the whole compiler is vendored (and not a trimmed parser)

The obvious question is why 4.3 MB of `compiler-core` ships when only the
parser is used. It was measured, and the answer is that there is no smaller
unit to take.

The dependency closure of `parse` + `ast` reaches **21 of the crate's 26
modules**, and the blocker is structural: `gleam_core::ast` names types from
the *type checker* —

```rust
type_::Type, type_::ModuleInterface, type_::error::VariableOrigin,
type_::expression::{Implementations, Purity}, type_::printer::Names,
type_::{FieldMap, HasType}
```

— because the untyped AST still carries `type_: ()` slots and references
`Type` in `Pattern::Variable`, `ClauseGuard::Constant` and friends. `type_/` is
16,825 lines. Dropping `build/` (5,446 lines) was also tried: `ast.rs` needs
`Located`, `ExpressionPosition`, `Target` and `UnqualifiedImport` from it, and
`Located` is an enum over `TypedExpr`/`TypedPattern`, so stubbing it means
stubbing the type checker too.

The floor is therefore `parse` + `ast` + `type_` ≈ 35,700 lines before `error`,
`exhaustiveness`, `warning` and `reference`. Stripping the backends and package
manager saves roughly 15% for a patch set that has to be re-verified on every
upstream bump — not a trade worth making.

Upstream ships no parser-only crate, and `gleam-core` is not on crates.io, so
this directory is the only way to get a real Gleam AST. The alternative is the
`HEX_BUILD=1` package, which omits it entirely and loses `parse`.

## Licence

The vendored crates are Apache-2.0, © the Gleam contributors; see `LICENCE`.
