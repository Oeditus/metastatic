# `metastatic-rust-parser` — the Rust AST bridge

The subprocess bridge that lets Metastatic parse Rust source into MetaAST (M2)
and print it back. It is the Rust analogue of `priv/parsers/sql/`, and it speaks
the same protocol, so `Metastatic.Adapter.Bridge` decodes its output with no
bespoke handling.

## Why a subprocess bridge

Rust has no parser on the BEAM, so — like Python, JavaScript, Ruby, Java and SQL
— the adapter shells out. The design decision that matters is **which parser**:

| Candidate | Verdict |
| :--- | :--- |
| `syn` 2.x | ✅ **Chosen.** Stable, pure Rust, complete grammar, typed AST, no nightly |
| `rustc_ast` / `rustc_parse` | ❌ Unstable (`rustc_private`), needs a matching nightly, breaks per release |
| `tree-sitter-rust` | ❌ No printer, loses the typed AST |
| `ra_ap_syntax` | ⚠️ Higher fidelity (lossless CST) but a ~100 MB dependency tree; kept as a future backend |

Printing uses **`prettyplease`**, which normalises formatting to rustfmt style.
Byte-identical round-trips are therefore not attempted — the goal is
**semantic** round-trip, which is what `ADAPTER_GUIDE.md` §9 asks for: compare
parsed ASTs, not strings.

## Protocol

The bridge reads a file path as its last argument and writes exactly **one**
JSON object to stdout. **Stdin is never read** — `Metastatic.Subprocess.run/4`
writes the payload to a temp file and appends it as the last argument, so a
missing path is a usage error rather than an implicit `-`. This keeps a
misconfigured caller from blocking forever on a pipe that will never close.

```text
metastatic-rust-parser parse   <file.rs>    -> {"ok":true,"ast":{...}}
metastatic-rust-parser unparse <ast.json>   -> {"ok":true,"source":"..."}
metastatic-rust-parser fmt     <file.rs>    -> {"ok":true,"source":"..."}
metastatic-rust-parser selftest             -> {"ok":true,"ast":{...}}
```

A *reported* failure (bad syntax, bad JSON) exits **0** and carries
`{"ok":false,"error":{...}}`, because the Elixir side treats a non-zero exit as
"the bridge could not run". Only usage errors and unreadable input exit non-zero.

`selftest` takes no input at all and short-circuits before any file access, so
it can never block. `unparse` and `fmt` also return
`"meta":{"formatter":"prettyplease"}` so callers can tell which printer
produced the text.

## Building

```bash
cargo build --release --locked
# -> target/release/metastatic-rust-parser
```

The toolchain is pinned by `rust-toolchain.toml` (stable + `rustfmt`). `Cargo.lock`
is committed so `--locked` builds are reproducible. MSRV is declared in
`Cargo.toml` (`rust-version = "1.75"`).

`Metastatic.Adapters.Rust.Subprocess` looks for the binary in this order:

1. `priv/parsers/rust/bin/metastatic-rust-parser` (prebuilt, shipped in releases)
2. `priv/parsers/rust/target/release/metastatic-rust-parser` (local build)
3. `metastatic-rust-parser` on `PATH`
4. `cargo run --quiet --locked --manifest-path …/Cargo.toml --` (source fallback)
5. otherwise a clear `{:error, reason}` — never a raise, never a hang

## The M1 shape

`src/ast.rs` defines a serde-serialisable mirror of `syn`'s AST — the same
strategy the Java adapter uses for `com.sun.source.tree`. Every node is:

```json
{ "kind": "Binary", "name": "+",
  "span": {"line": 3, "col": 8, "end_line": 3, "end_col": 13},
  "children": [ ... ] }
```

`kind` is the discriminant the Elixir `ToMeta` matches on. Optional fields are
omitted from the JSON rather than emitted as `null`.

### Fields that are load-bearing

Three pieces of information are easy to drop and silently change the program.
They are recorded explicitly:

| Field | Why it matters |
| :--- | :--- |
| `semi` on a statement | `x + y` is a block's value; `x + y;` discards it |
| `semi` on an enum/struct | `syn` keeps the trailing comma as part of the AST |
| `semi` on an `Ident` pattern | `let mut total` vs `let total` |
| `Paren` node kind | `(a + b) * 2` is not `a + b * 2` |

### The escape hatch

Constructs outside the modelled set (see `RUST_IMPL.md` §4) become
`{"kind":"Unsupported","source":"<original text>"}`. The Elixir side maps those
to `:language_specific`, and `unparse` re-parses the preserved text — so
unsupported syntax still round-trips exactly. This is the same trick the SQL
adapter uses with `original_ast`.

## Source spans

`src/span.rs` reads positions from `proc-macro2`. This requires the
**`span-locations`** feature (enabled in `Cargo.toml`); without it every
`Span::start()` returns line 0 and the whole AST loses its positions. This was
risk **R1** in `RUST_IMPL.md` and is verified by `span::tests` and by the
`selftest` mode.

Columns are normalised to 1-based to agree with the `:col` convention the other
Metastatic adapters use.

## Testing

```bash
cargo test                 # 44 unit tests
cargo clippy --release     # zero warnings
```

### `selftest` — the Phase 0 exit gate

`RUST_IMPL.md` §8 defines Phase 0's exit criterion as *"byte-identical
`syn::File` on round-trip; spans populated"*. `src/selftest.rs` turns that into
an executable check over a corpus covering every §4 mapping row. For each
snippet it asserts:

1. **Spans are populated** — no node reports line 0 (risk R1).
2. **The AST survives the JSON hop** — `to_json` → `from_json` is identity.
3. **The printed form re-parses** to the same tree (risk R2).

The Elixir side can shell out to `metastatic-rust-parser selftest` in CI to
verify the exact bridge binary it is about to use.

### Structural comparison

`src/compare.rs` strips `syn`'s byte offsets (`span: bytes(4..7)`,
`apostrophe: bytes(228..229)`) before comparing two trees. Comparing raw `Debug`
output compares *positions*, not structure, and produced a false failure during
the spike.

## Phase 0 findings

The gate caught six real fidelity bugs that would otherwise have shipped into
`ToMeta`/`FromMeta`:

1. `Response` — a derived `untagged` enum decoded every failure as an empty
   success, because all `Success` fields are optional. Replaced with an explicit
   `ok`-dispatching implementation.
2. `Expr::Paren` was unwrapped, changing `(a + b) * 2` into `a + b * 2`.
3. Trailing semicolons on expression statements were dropped, turning tail
   expressions into value-discarding statements.
4. Function return types were not carried, so every signature lost its `-> T`.
5. `let mut` lost its mutability.
6. Trailing commas on enums and structs were lost, and `match` arms were emitted
   without the separator `syn` expects.

All six are fixed and covered by tests.
