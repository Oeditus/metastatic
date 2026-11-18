## Unreleased

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

