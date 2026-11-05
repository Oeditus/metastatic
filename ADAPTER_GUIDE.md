# Writing a Language Adapter for Metastatic

This guide walks through building a **fully-fledged language adapter** — the
module that teaches Metastatic how to parse a language into MetaAST and
generate it back. By the end you will have a language that:

- is discovered automatically by the registry (no edits to core files),
- round-trips source ⇄ MetaAST with high fidelity,
- participates in cross-language translation, validation and semantic analysis,
- integrates with Ragex (validators, native fallback analysis, SCIP, file
  discovery) with no Ragex changes required.

> **TL;DR** — Drop a module in `lib/metastatic/adapters/` that implements
> `@behaviour Metastatic.Adapter`, give it a `file_extensions/0`, and you're
> registered. The rest of this guide is about doing it *well*.

---

## Table of contents

1. [How adapters fit in](#1-how-adapters-fit-in)
2. [The plug-in registry](#2-the-plug-in-registry)
3. [The adapter contract](#3-the-adapter-contract)
4. [Choosing a parsing strategy](#4-choosing-a-parsing-strategy)
5. [Step-by-step: building an adapter](#5-step-by-step-building-an-adapter)
6. [The M1 ⇄ M2 mapping](#6-the-m1--m2-mapping)
7. [Semantic enrichment (OpKind)](#7-semantic-enrichment-opkind)
8. [Testing your adapter](#8-testing-your-adapter)
9. [Round-trip fidelity](#9-round-trip-fidelity)
10. [Ragex integration](#10-ragex-integration)
11. [Checklist](#11-checklist)
12. [Reference: a complete skeleton](#12-reference-a-complete-skeleton)

---

## 1. How adapters fit in

Metastatic works at two levels:

- **M1 — native AST.** The language-specific parse tree (Python's `ast` dicts,
  Elixir's quoted forms, Babel's JSON AST, …).
- **M2 — MetaAST.** A uniform, language-independent tree of 3-tuples:

      {type_atom, keyword_metadata, children_or_value}

An adapter is the pair of functions that move between them:

```
        parse/1            to_meta/1
Source ─────────► M1 ─────────────────► M2 (MetaAST)
   ▲                                     │
   │ unparse/1        from_meta/2        │
   └─────── M1 ◄─────────────────────────┘
```

Formally the adapter is a Galois connection `⟨α_L, ρ_L⟩` where `α_L` is
`to_meta/1` (abstraction) and `ρ_L` is `from_meta/2` (reification). The whole
point is that *equivalent code in different languages produces the same M2
tree*, which is what makes cross-language analysis and translation possible.

---

## 2. The plug-in registry

You do **not** register your adapter by hand. `Metastatic.Languages` discovers
adapters at compile time:

- It scans `lib/metastatic/adapters/*.ex`.
- Every module that declares `@behaviour Metastatic.Adapter` is registered.
- The language atom is derived from the module's last name segment,
  **downcased**: `Metastatic.Adapters.Rust` → `:rust`,
  `Metastatic.Adapters.TypeScript` → `:typescript`.

Everything else — the extension map, `supported_languages/0`, the
`supported_languages_string/0` used in error messages, `detect_language/1` —
is derived from your adapter's `file_extensions/0` automatically.

### Exclusions and overrides

A few adapters are structural but not *source languages* (natural-language
adapters such as `english`/`spanish`) and are excluded in
`Metastatic.Languages` via `@excluded`. You should not need this.

If you need to adjust discovery (e.g. ship an adapter from a host app, or mark
a language experimental), use config — no core edits:

```elixir
config :metastatic, :languages,
  exclude: [:some_internal_lang],
  include: [%{language: :mylang, adapter: MyApp.Adapters.MyLang}],
  experimental: [:mylang],
  documentation: [:mylang]
```

| Key | Meaning |
| :--- | :--- |
| `:exclude` | language atoms to drop from discovery |
| `:include` | extra `%{language: atom, adapter: module}` entries |
| `:experimental` | languages needing an external toolchain outside CI |
| `:documentation` | document languages (no callable entities, e.g. Markdown) |

---

## 3. The adapter contract

See `Metastatic.Adapter` for the full documentation. The required callbacks:

| Callback | Direction | Purpose |
| :--- | :--- | :--- |
| `parse/1` | Source → M1 | Parse source into the native AST |
| `to_meta/1` (or `to_meta/2`) | M1 → M2 | Abstract to MetaAST; returns `{:ok, ast, metadata}` |
| `from_meta/2` | M2 → M1 | Reify MetaAST back to the native AST |
| `unparse/1` | M1 → Source | Print the native AST as source |
| `file_extensions/0` | — | Dot-prefixed extensions, e.g. `[".rs"]` |

Optional callbacks:

| Callback | Purpose |
| :--- | :--- |
| `validate_mutation/2` | Reject M2 mutations that would be invalid in this language |
| `extract_children/1` | Let analyzers traverse `:language_specific` nodes |
| `to_meta/2` | Configurable abstraction (e.g. `expand_macros: true`) |

`Metastatic.Adapter.valid_adapter?/1` treats `to_meta/1` **or** `to_meta/2` as
satisfying the contract, so implement whichever fits.

`Metastatic.Adapter.Registry` is seeded from the discovered languages at
application start, so `Registry.get(:mylang)` and `Languages.get_adapter(:mylang)`
agree out of the box.

---

## 4. Choosing a parsing strategy

There are three patterns in the existing adapters. Pick the one that matches
your language's tooling:

### A. Native BEAM (best, zero IPC)

Use when the language can be parsed with Elixir/Erlang itself — Elixir
(`Code.string_to_quoted/2`), Erlang (`:erl_scan`/`:erl_parse`), or an in-process
compiler (Cure). Fastest and simplest; no external dependency.

```elixir
def parse(source), do: Code.string_to_quoted(source)
def unparse(ast), do: {:ok, Macro.to_string(ast)}
```

### B. Subprocess bridge (most common)

Use when the language has a mature parser in another runtime (Python `ast`,
Babel, Ruby `parser`, `sqlparser-rs`, GHC). You ship a small parser script in
`priv/parsers/<lang>/` that reads source on stdin (or a file) and emits JSON,
and an unparser for the reverse direction.

Resolve the script and executable through `Metastatic.Priv`:

```elixir
script = Metastatic.Priv.parser_path("parsers/rust/parser.rs_bridge")
bin    = Metastatic.Priv.find_executable("cargo")
env    = Metastatic.Priv.subprocess_env()
```

`Priv.parser_path/1` searches the app `priv`, the compile-time source `priv`,
Ragex's `priv`, and `priv/` under the CWD, so the bridge works in dev, as a
dependency, and in a release. `Priv.subprocess_env/0` augments `PATH`/`NODE_PATH`
for `mise` users and is overridable via `config :metastatic, :subprocess_env`.

### C. Hybrid

Try in-process first, fall back to a subprocess (Cure does this: native
compiler modules when linked, CLI bridge otherwise). Good for optional
toolchains.

> **Robustness rule:** a missing toolchain must degrade to a clear
> `{:error, reason}` — never raise, never hang. See how the Python bridge
> checks `File.exists?` and `find_executable` before spawning.

---

## 5. Step-by-step: building an adapter

Let's build a hypothetical `:rust` adapter using a subprocess bridge.

### Step 1 — create the module

`lib/metastatic/adapters/rust.ex`:

```elixir
defmodule Metastatic.Adapters.Rust do
  @moduledoc """
  Rust adapter: bridges Rust source (M1, via a subprocess bridge) and
  MetaAST (M2).
  """

  @behaviour Metastatic.Adapter

  alias Metastatic.Adapters.Rust.{FromMeta, Subprocess, ToMeta}
  alias Metastatic.Semantic.Enricher

  @impl true
  def parse(source) when is_binary(source), do: Subprocess.parse(source)

  @impl true
  def to_meta(rust_ast) do
    case ToMeta.transform(rust_ast) do
      {:ok, meta_ast, metadata} ->
        enriched = Enricher.enrich_tree(meta_ast, :rust)
        {:ok, enriched, metadata}

      error ->
        error
    end
  end

  @impl true
  def from_meta(meta_ast, metadata), do: FromMeta.transform(meta_ast, metadata)

  @impl true
  def unparse(rust_ast), do: Subprocess.unparse(rust_ast)

  @impl true
  def file_extensions, do: [".rs"]
end
```

That's the whole registration. `Metastatic.Languages` now reports `:rust` and
`.rs`.

### Step 2 — the subprocess bridge

`lib/metastatic/adapters/rust/subprocess.ex` — parse and unparse via JSON over
stdin/stdout. Mirror `Metastatic.Adapters.Python.Subprocess`:

```elixir
defmodule Metastatic.Adapters.Rust.Subprocess do
  @moduledoc "Subprocess bridge to the Rust parser/unparser."

  alias Metastatic.Priv

  @parser_path "parsers/rust/parser"

  @spec parse(String.t()) :: {:ok, map()} | {:error, String.t()}
  def parse(source) do
    with {:ok, json} <- run(@parser_path, source),
         {:ok, %{"ok" => true, "ast" => ast}} <- Jason.decode(json) do
      {:ok, ast}
    else
      {:ok, %{"ok" => false, "error" => err}} -> {:error, err}
      {:error, reason} -> {:error, "Rust parser failed: #{inspect(reason)}"}
    end
  end

  def unparse(ast), do: # ... symmetric: send JSON, receive source

  defp run(rel, source) do
    path = Priv.parser_path(rel)

    cond do
      not File.exists?(path) -> {:error, "parser unavailable at #{path}"}
      (bin = Priv.find_executable("rust-bridge")) == nil -> {:error, "rust-bridge not found"}
      true -> do_cmd(bin, [path], source)
    end
  end

  defp do_cmd(bin, args, input) do
    port = Port.open({:spawn_executable, bin}, [:binary, :exit_status, args: args])
    Port.command(port, input)
    # ... collect output, return {:ok, output} or {:error, ...}
  end
end
```

Ship the actual parser under `priv/parsers/rust/`. Follow the existing
convention: the bridge must output `{"ok": true, "ast": ...}` on success and
`{"ok": false, "error": "..."}` on failure.

### Step 3 — abstraction (`ToMeta`)

`lib/metastatic/adapters/rust/to_meta.ex` — pattern-match the native AST and
emit MetaAST 3-tuples. See [§6](#6-the-m1--m2-mapping).

### Step 4 — reification (`FromMeta`)

`lib/metastatic/adapters/rust/from_meta.ex` — the inverse. Use the metadata
captured in `to_meta` to restore language-specific details.

### Step 5 — tests, fixtures, docs

See [§8](#8-testing-your-adapter).

---

## 6. The M1 ⇄ M2 mapping

MetaAST layers, from most to least portable:

| Layer | Contents | Example nodes |
| :--- | :--- | :--- |
| **M2.1 Core** | Universal constructs | `:literal`, `:variable`, `:binary_op`, `:unary_op`, `:function_call`, `:conditional`, `:block`, `:early_return` |
| **M2.2 Extended** | Common patterns | `:loop`, `:lambda`, `:collection_op`, `:pattern_match`, `:exception_handling`, `:comprehension` |
| **M2.2s Structural** | Organisation | `:container`, `:function_def`, `:param`, `:import`, `:type_annotation`, `:decorator` |
| **M2.3 Native** | Escape hatch | `:language_specific` |

**Always map to the highest (most portable) layer you can.** Only fall back to
`:language_specific` for constructs with no cross-language analogue.

### Worked example

Rust `x + 5` parses (M1) to something like
`%{"kind" => "Binary", "op" => "+", "lhs" => ..., "rhs" => ...}`. Map it to the
**same** M2 node that Python/Elixir/JS produce:

```elixir
{:binary_op, [category: :arithmetic, operator: :+],
 [{:variable, [], "x"}, {:literal, [subtype: :integer], 5}]}
```

That equality is the whole game — it's what lets `Metastatic.unquote(rust_ast, :python)`
emit valid Python.

### Metadata preservation

Return a `metadata` map from `to_meta/2` capturing anything M2 can't hold but
`from_meta/2` needs (line numbers, original node types, formatting hints):

```elixir
{:ok, meta_ast, %{line: 12, rust_node: "Binary", source_span: {0, 5}}}
```

---

## 7. Semantic enrichment (OpKind)

MetaAST nodes can carry an `:op_kind` annotation describing the *operation* —
database, HTTP, cache, queue, file, external API, auth. Ragex's semantic
analysis and MetaCredo consume these. The domains live in
`Metastatic.Semantic.Domains.*` and register pattern tables.

Call `Metastatic.Semantic.Enricher.enrich_tree/2` in `to_meta/2` (as the Python
adapter does) so your language gets semantic analysis for free:

```elixir
enriched = Metastatic.Semantic.Enricher.enrich_tree(meta_ast, :rust)
```

If your language has library idioms worth recognising (e.g. `reqwest::get`),
add patterns to the relevant domain module and register them. This is optional
but is what makes an adapter *fully-fledged* rather than merely parseable.

> **Note for Ragex:** Metastatic registers its OpKind tables from a
> module-level side effect that only runs at compile time. Ragex calls
> `Ragex.LanguageSupport.ensure_semantic_patterns/0` at startup to re-register
> them; you don't need to do anything special.

---

## 8. Testing your adapter

### Structural contract (automatic)

`test/metastatic/adapter_contract_test.exs` enumerates **every** discovered
language and asserts the contract holds. Your adapter is covered the moment it
exists — a missing callback fails this test. Run it:

```bash
mix test test/metastatic/adapter_contract_test.exs
```

### Behavioural conformance (write these)

Use `Metastatic.Test.AdapterConformance` (see `test/support/`) to test
`parse` → `to_meta` → `from_meta` → round-trip on real source. Create
`test/metastatic/adapters/rust_conformance_test.exs`:

```elixir
defmodule Metastatic.Adapters.RustConformanceTest do
  use ExUnit.Case, async: true
  use Metastatic.Test.AdapterConformance,
    adapter: Metastatic.Adapters.Rust,
    language: :rust,
    # A snippet the adapter can parse...
    sample: "1 + 2",
    # ...and a MetaAST it can reify back to source.
    sample_ast: {:binary_op, [category: :arithmetic, operator: :+],
                 [{:literal, [subtype: :integer], 1},
                  {:literal, [subtype: :integer], 2}]}
end
```

The macro generates the uniform assertions (behaviour, extensions,
discoverability, parse valid/invalid, `to_meta` conformance, `from_meta`,
`unparse`, round-trip).

### Fixtures

Add 50+ representative snippets under `test/fixtures/rust/` covering the
constructs you claim to support. The cross-language suite
(`cross_language_conformance_test.exs`) checks that equivalent snippets in
different languages produce equivalent MetaAST — include your language there
where it makes sense.

### Excluding a slow/external language from CI

If your adapter needs a toolchain not present in CI (like GHC/Agda), tag its
tests and mark the language experimental via config so the default matrix skips
it while it stays usable locally.

---

## 9. Round-trip fidelity

The quality bar is **Source → M1 → M2 → M1 → Source** producing semantically
equivalent output (formatting may normalise). Targets:

| Rating | Fidelity | Notes |
| :--- | :--- | :--- |
| Superb | > 95% | Production-ready |
| Good | 90–95% | Usable, some lossy constructs |
| Experimental | < 90% | Document the limitations |

Measure it:

```elixir
{:ok, doc} = Metastatic.Builder.from_source(source, :rust)
{:ok, out} = Metastatic.Builder.to_source(doc)
# compare ASTs (not strings) for semantic equivalence
```

Prefer comparing *parsed ASTs* over raw strings — whitespace and formatting
legitimately differ.

---

## 10. Ragex integration

Once the adapter exists, Ragex sees the language automatically because
`Ragex.Languages` derives from `Metastatic.Languages`. What you get for free:

- **File discovery** — `LanguageSupport.find_source_files/2` picks up your
  extensions.
- **Analysis** — `Ragex.Analyzers.Metastatic` parses via your adapter.
- **Detection** — `LanguageSupport.detect_language/1` returns your atom.

To make it *fully* integrated, add entries to the Ragex-local overlay in
`lib/ragex/languages.ex` (these are concerns Metastatic doesn't model):

```elixir
@validators %{ ..., rust: Ragex.Editor.Validators.Rust }
@native_analyzers %{ ..., rust: Ragex.Analyzers.Rust }
```

- **Validator** — implement `Ragex.Editor.Validator`. If your validation is
  "run an external tool and parse `line:col:msg`", you don't need a bespoke
  module: use `Ragex.Editor.Validators.Subprocess` with a spec (see
  `validators/python.ex`, `ruby.ex`, `javascript.ex` for examples).
- **Native analyzer** — only needed if you want a fallback when Metastatic
  parsing fails. Most languages don't need one.
- **SCIP** — if you'd rather index via SCIP than parse natively, add the
  language to `@scip_languages` instead; it then appears in
  `Ragex.Analyzers.SCIP.Registry` automatically.

---

## 11. Checklist

Before opening a PR:

- [ ] Module in `lib/metastatic/adapters/<lang>.ex` with `@behaviour Metastatic.Adapter`
- [ ] All required callbacks: `parse/1`, `to_meta/1` (or `/2`), `from_meta/2`, `unparse/1`, `file_extensions/0`
- [ ] Dot-prefixed extensions (`[".rs"]`, not `["rs"]`)
- [ ] Maps to the highest MetaAST layer possible; `:language_specific` only as a last resort
- [ ] `Enricher.enrich_tree/2` called in `to_meta` (semantic support)
- [ ] Missing-toolchain path returns `{:error, reason}` — never raises or hangs
- [ ] `mix test test/metastatic/adapter_contract_test.exs` passes
- [ ] Conformance test with real snippets
- [ ] 50+ fixtures under `test/fixtures/<lang>/`
- [ ] Round-trip fidelity measured and documented
- [ ] `@moduledoc` explains the M1 shape and the mapping strategy
- [ ] (Optional) Ragex overlay entries for validator / native analyzer / SCIP

---

## 12. Reference: a complete skeleton

```
lib/metastatic/adapters/rust.ex
lib/metastatic/adapters/rust/subprocess.ex
lib/metastatic/adapters/rust/to_meta.ex
lib/metastatic/adapters/rust/from_meta.ex
priv/parsers/rust/parser        # the bridge binary/script
test/metastatic/adapters/rust_conformance_test.exs
test/fixtures/rust/*.rs
```

```elixir
# lib/metastatic/adapters/rust.ex
defmodule Metastatic.Adapters.Rust do
  @moduledoc """
  Rust ⇄ MetaAST adapter.

  M1: a JSON AST emitted by `priv/parsers/rust/parser`.
  Mapping: statements → `:block`, `let` → `:variable`/`:type_annotation`,
  `fn` → `:function_def`, expressions → core/extended nodes.
  """

  @behaviour Metastatic.Adapter

  alias Metastatic.Adapters.Rust.{FromMeta, Subprocess, ToMeta}
  alias Metastatic.Semantic.Enricher

  @impl true
  def parse(source) when is_binary(source), do: Subprocess.parse(source)

  @impl true
  def to_meta(ast) do
    case ToMeta.transform(ast) do
      {:ok, meta_ast, metadata} ->
        {:ok, Enricher.enrich_tree(meta_ast, :rust), metadata}

      error ->
        error
    end
  end

  @impl true
  def from_meta(meta_ast, metadata), do: FromMeta.transform(meta_ast, metadata)

  @impl true
  def unparse(ast), do: Subprocess.unparse(ast)

  @impl true
  def file_extensions, do: [".rs"]
end
```

That's it — Metastatic discovers it, derives `.rs` → `:rust`, and the whole
pipeline (translate, validate, inspect, semantic analysis) works. See
`Metastatic.Adapter` for the formal contract and the existing adapters for
production examples.
