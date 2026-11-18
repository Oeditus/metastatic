## Unreleased

### Added — Rust language adapter (Phases 0–1)

Rust is now a first-class source language: `.rs` files are discovered, parsed,
abstracted to MetaAST and printed back. The parser is
[`syn`](https://docs.rs/syn) (stable, pure Rust, complete grammar) and the
printer is [`prettyplease`](https://docs.rs/prettyplease), driven by a small
bridge CLI in `priv/parsers/rust/`.

- **`priv/parsers/rust/`** — a `cargo` crate (`metastatic-rust-parser`) that
  speaks the same JSON protocol as every other bridge, so
  `Metastatic.Adapter.Bridge` decodes it with no bespoke handling. Modes:
  `parse`, `unparse`, `fmt`, `selftest`.
- **`Metastatic.Adapters.Rust`** — `parse/1`, `to_meta/1`, `from_meta/2`,
  `unparse/1`, `file_extensions/0` (`[".rs"]`), plus `format/1`, `selftest/0`
  and `available?/0`. Discovered automatically by `Languages.Builtin`.
- **`Metastatic.Adapters.Rust.Subprocess`** — toolchain resolution mirroring the
  SQL adapter: prebuilt binary, local release build, `PATH`, then a `cargo run`
  source fallback. A missing toolchain is a clear `{:error, reason}` — never a
  raise, never a hang.
- **`Metastatic.Adapters.Rust.ToMeta` / `.FromMeta`** — the M1 ⇄ M2 mapping:
  literals, operators, calls, `fn`/`struct`/`enum`/`trait`/`impl`/`mod`,
  `use`, `match`, loops, closures, `?`, `.await`, and patterns. Constructs with
  no cross-language analogue are preserved as `:language_specific` carrying the
  original M1 node, so they round-trip exactly.

### Notes

- **Semantic round-trip, not byte-identical.** `prettyplease` normalises
  formatting to rustfmt style, so the target is a re-parsed AST equal to the
  original — which the bridge's `selftest` mode verifies over a corpus covering
  every mapped construct.
- **Bare expressions are accepted.** `syn::parse_file` only accepts items, so the
  bridge retries a failed file parse as an expression; `1 + 2` works, as it does
  for every other adapter.
- **Stdin is never read.** The Elixir side always passes a temp-file path, and a
  missing path is a usage error, so a misconfigured caller fails fast instead of
  blocking on a pipe that will never close.
- Rust-tagged tests (`@tag :rust`) skip cleanly when no toolchain is present.

## v0.38.0

### Added — third-party language plugins (complete)

A host application can now add a language to Metastatic without editing a
single file in Metastatic's source. `examples/third_party_plugin/` is the
worked example and the acceptance test: a separate Mix application that adds
the `:lisp` language, registered at boot, used through the ordinary public API,
and translated to Elixir and Python.

- **Hybrid language registry.** `Metastatic.Languages` is now a façade over
  `Metastatic.Languages.Store` (ETS) instead of a set of compile-time module
  attributes. Built-ins are seeded from `Metastatic.Languages.Builtin` (the
existing source scan, moved and renamed); plug-ins are registered at runtime.
  Every query — `supported_languages/0`, `detect_language/1`, `get_adapter/1`,
  `supported_extensions/0` — sees a runtime registration immediately.
  `detect_language/1` remains a single `:ets.lookup/2` on a
  `read_concurrency: true` table, so the per-file hot path is unchanged.
- **`Metastatic.Languages.register/3` / `unregister/1`.** Registers an adapter
  at runtime with optional `:extensions`, `:experimental?` and
  `:documentation?`. Refuses to shadow an occupied language; `unregister/1`
  refuses the built-ins.
- **`Metastatic.Adapter.Registry.install/1`** and the `:plugins` child-spec
  option. `install/1` is the entry point for a host application, because
  Metastatic's supervisor starts the registry *before* the host's `start/2`
  runs, so the child-spec option is not reachable from there. Failures are
  reported as a list rather than crashing on the first bad entry.
- **`Metastatic.Adapter.Registry.replace/3`.** Unconditionally installs an
  adapter, including over a built-in. Explicit and greppable, for tests that
  need a deterministic adapter without the real toolchain.
- **`Metastatic.Adapter.Plugin`** — a `use` macro that injects
  `@behaviour Metastatic.Adapter`, `file_extensions/0`, and the descriptor
  callbacks the registry reads. It validates `:language` and `:extensions` at
  compile time of the plug-in, where the mistake is.
- **`Metastatic.Adapter.enrich/3`** — the shared "transform then enrich" step.
  All eleven built-in adapters now delegate to it instead of repeating the same
  `case ToMeta.transform(...)` block, so a third-party adapter cannot silently
  omit enrichment.

### Changed

- **`Builder.supported_languages/0` reports `:loaded` honestly**
  (`Code.ensure_loaded?/1`) instead of hard-coding `true`, and includes
  runtime-registered plug-ins.
- **`Languages.parse_language/1` resolves by name** rather than
  `String.to_existing_atom/1`, so a language whose atom was created after
  `Languages` loaded still parses.
- **`Languages.unregister/1` returns `{:error, :builtin}`** for a built-in
  language instead of silently desynchronising the store.

### Fixed

- **`Metastatic.Semantic.ensure_registered_if_empty/0`** — the lazy path called
  by `Adapter.abstract/3`. Calling the unconditional `ensure_registered/0`
  there re-ran every built-in provider, so a test that had deliberately
  narrowed the callback registry had its state overwritten mid-test. The lazy
  path now recovers an empty table and re-applies host-configured providers
  (idempotently) without clobbering a populated one.
- **`Registry.init/1` deadlock.** Plug-ins were installed through
  `register/3`, a `GenServer.call/3` to the process still inside `init/1`.
  They are now written to the store directly.
- **`Registry.normalise_plugin/1` ignored the plug-in's declared language**
  and derived the atom from the module name instead, so
  `MyApp.Adapters.Lisp` registered as `:lisp` only by coincidence and
  `SampleAdapter` registered as `:sample_adapter`.
- **`Registry.register/3` now applies a plug-in's declared descriptor**
  (extensions and flags) by default, so `register(:lang, Mod)` is enough.

### Added — third-party language plugins, phase 0 & 1
Groundwork for shipping language adapters from a host application rather than
compiling them into Metastatic. Two of the four couplings identified in the
architecture review are removed here; registration itself is unchanged.

- **`Metastatic.Adapter.Bridge` — one protocol for every subprocess parser.**
  Nine adapters had grown nine slightly different `decode/1` implementations,
  each accepting a different subset of the response shapes. A bridge emitting
  `{"status": "ok"}` to a decoder expecting `{"ok": true}` failed with
  `"Unexpected parser output"` instead of anything actionable. `decode/1` now
  accepts every shape in use (canonical `ok`/`ast`/`source`/`error`, the legacy
  `status` envelope used by Haskell and Agda, and envelope-less payloads), and
  `run/4`, `encode/1`, `require_executable/2` and `format_error/1` are shared.
  The behaviour (`parse/1`, `unparse/1`, both optional) documents the contract
  for new bridges.
- **`Metastatic.Semantic.ensure_registered/0` — deterministic semantic tables.**
  The OpKind pattern tables and callback registry were populated by a
  module-load side effect, which does not re-run across a VM restart and is
  wiped by `Patterns.clear_all/0`. The failure was silent: `Enricher` simply
  found no patterns and returned the tree unannotated. The new entry point is
  idempotent, runs at boot and lazily before the first abstraction, and calls
  host-configured providers:

      config :metastatic, :semantic,
        pattern_providers: [MyApp.Semantic.RustPatterns],
        callback_providers: [MyApp.Semantic.RustCallbacks]

  A provider that is missing or raises is logged and skipped, so it cannot
  break boot or a parse.
- **`Metastatic.Priv.parser_path/1` searches the host application's `priv/`.**
  A third-party adapter keeps its bridge in its own `priv/`; it is now found
  without configuration (the host is derived from `:metastatic`'s application
  spec). `config :metastatic, :priv_dirs` still overrides.

### Changed

- **`Metastatic.Semantic.Patterns.register/3` is idempotent.** It deduplicated
  nothing before: calling `register_all/0` twice duplicated every pattern and
  changed match precedence. Registration now merges by match key, keeping the
  first spec for a key so a more specific provider registered earlier still
  wins, and preserves registration order.
- All subprocess adapters (Python, JavaScript, Ruby, Java, SQL, March, Cure,
  Haskell, Agda) delegate response decoding to `Metastatic.Adapter.Bridge`.
  Adapter-specific shapes are preserved where the protocol genuinely differs:
  Ruby translates `{"status": "ok", "ast": null}` to
  `"Parse error: syntax error"`, and SQL keeps its `{:ok, ast, %{unsupported: …}}`
  three-tuple for partially-parseable scripts.

### Fixed

- **`Application.get_env/2` returning `nil`.** `Metastatic.Semantic` and
  `Metastatic.Priv` assumed a list for `:semantic` and `:priv_dirs`, so a config
  file (or a test restoring a previous `nil`) crashed them with a
  `FunctionClauseError` in `Keyword.get/3` and `++/2`.
- **`Bridge.run/4` double-prefixed its error message** (`"Bridge failed: Failed
  to run bridge: …"`) because `Subprocess.run/4` already prefixes its own
  failures.

### Fixed — audit remediation, phase 1 (defects)
Eighteen defects found in the 2026-11-18 end-to-end audit. The first six were
**silent semantic changes**: the code compiled, but meant something different.

- **`case` arms: `nil` and `_` no longer collapse into each other.** The
  Elixir reifier used `if pattern, do: ..., else: :_`, so a `nil` pattern
  reified to `:_` — an atom pattern that matches only the atom `:_`. `_`
  likewise became `:_` because it fell through to the symbol-literal clause.
  `_` now has its own `:wildcard` node type, and `nil` is preserved as a real
  pattern. (`lib/metastatic/adapters/elixir/{to,from}_meta.ex`)
- **Empty clause bodies reify to `nil`, not `{:__block__, [], []}`.** A
  `_ -> nil` arm used to unparse as `_ ->` with nothing on the right-hand
  side, which re-parses with a compiler warning and a different meaning.
- **`%{map | key: value}` keeps its update semantics.** The abstraction pass
  rewrote the update into `Map.merge(map, Map.new(...))`, which silently adds
  keys the update form forbids, and nothing restored it. The map is now
  preserved as a `:language_specific` node with `hint: :map_update` and
  reified back to the surface syntax.
- **`nil` is a legal MetaAST child.** `AST.conforms?/1` rejected it, so
  `Validator.validate/2` rejected documents the library itself produces (an
  `if` without `else`, an empty `case` arm).
- **`Metastatic.Adapter.round_trip/2`** now merges the adapter's parse
  metadata into the metadata handed to `from_meta/2` instead of discarding it,
  and its `@spec`/`@doc` match the body (the doctest previously referenced a
  non-existent `MyAdapter`).
- **Elixir adapter: malformed `:fn` fallback.** The "unexpected structure"
  branch returned `{{{:fn, ...}}, ctx}` — a 1-tuple wrapping the AST.
- **Elixir adapter: map-update logging.** A `|` pair logged via
  `Logger.warning/1` and used its `:ok` return value as the pair, producing a
  bogus `{:literal, :symbol, :ok}` child.

Tooling and scaffolding defects:

- **`mix metastatic.gen.supplemental`** emitted `target_language:` and
  `dependencies:`, which are not fields of `Metastatic.Supplemental.Info`, so
  every generated module failed to compile. It now emits `name:`, `language:`,
  `constructs:`, `requires:` and `description:`.
- **Generated tests no longer pass silently.** Scaffolded tests had comment-only
  bodies; they now `flunk/1` until implemented.
- **`mix metastatic.validate-equivalence`** delegates to `AST.canonicalize/1`
  instead of a hand-maintained location-key strip, so adapter bookkeeping
  (`:original_meta`, `:origin`, `:desugar`) no longer makes two semantically
  identical files compare as different.
- **`Metastatic.Supplemental.Validator`** only reports a construct as
  "required" when a registered supplemental claims it. Previously *every*
  unknown node type was reported, so `mix metastatic.supplemental_check` cried
  wolf on ordinary code.
- **`Metastatic.CLI.Inspector`** delegates layer classification to
  `AST.layer/1` (its local copy omitted the whole `:structural` layer) and
  understands canonical `{:pair, meta, [k, v]}` nodes, so maps are no longer
  under-counted.
- **`Metastatic.CLI.Formatter`** no longer raises `CaseClauseError` on a
  conditional with anything other than 2–3 children.
- **`Metastatic.Builder.supported_languages/0`** derives from
  `Metastatic.Languages.all/0` rather than reading a runtime GenServer copy.
- **CI**: `mix credo --strict` and `mix deps.unlock --check-unused` no longer
  run behind `|| true` / `continue-on-error`, and the `quality` alias now
  includes `dialyzer` so local and CI agree.
- **Tests**: `test/support/adapter_helper_test.exs` (300+ lines, previously
  never collected) moved to `test/metastatic/test/`; the Ruby Rails test uses a
  checked-in fixture instead of a path on one developer's disk; `:haskell` and
  `:agda` are excluded only when their toolchain is actually missing.

### Fixed — audit remediation, phase 2 (Elixir adapter fidelity)

A new fixture-corpus round-trip test (`test/metastatic/adapters/elixir/fixture_round_trip_test.exs`)
reifies every file under `test/fixtures/elixir/` and asserts the output
re-parses to a structurally identical AST. It immediately found three more
silent reification bugs:

- **Non-variable function-head patterns were flattened to `_`.**
  `def factorial(0)` round-tripped to `def factorial(_)` — a different
  function with different dispatch. The original pattern is now kept in the
  `:param` metadata under `:pattern` and reified verbatim, so
  `def f(0)`, `def f([])` and `def f({a, b})` all survive.
- **Multi-clause functions emitted only their first clause.**
  `ToMeta.group_function_clauses/1` collapses same-name/same-arity clauses
  into one node carrying `:clauses`, but `FromMeta` ignored that key and
  emitted only the first body — `def factorial(n) when n > 0` vanished
  entirely. Each clause is now reified as its own `def`.
- **Pipes and `with`/`else` lost their surface form.** `x |> f(a)` came back
  as `f(x, a)` and `with ... else ...` came back as a `with` whose body
  contained a synthetic `case _with_result`. Both are now restored from the
  metadata the abstraction pass already recorded (`pipe: true`,
  `original_form: :with_else`).

### Changed — audit remediation, phase 2 (structure)

- **`Metastatic.Subprocess`** — new module owning the "write temp file, shell
  out, always delete the temp file" logic that nine adapter bridges had each
  copied (and drifted apart). All nine bridges now delegate to it, so cleanup
  is guaranteed on every path (including exceptions) and error formatting is
  identical across languages.
- **`Metastatic.Adapter.Registry`** no longer keeps a second extension →
  language map. Detection delegates to `Metastatic.Languages`, whose map is
  derived at compile time; the registry stores adapter overrides only.
- **`Metastatic.Validator`** classifies node types through `AST.layer/1`
  instead of a local copy of the type lists, which had already drifted
  (`:container` was `:extended` there and `:structural` in `AST`).
- **`Metastatic.CLI.Translator`** returns `{:error, reason}` for a language
  with no known extension instead of raising.
- **`mix metastatic.gen.supplemental`** validates construct names instead of
  calling `String.to_atom/1` on arbitrary CLI input.

### Added

- `:wildcard` MetaAST node type (core layer) for the `_` pattern.
- `Metastatic.NL.AST.text/2` with an `include_code:` option. `text/1` keeps its
  existing behaviour (code omitted) so prose linting never sees source code.
- `Metastatic.Subprocess` with `run/4`, `with_temp_file/3`, `write_temp_file/2`
  and `format_error/1`.

