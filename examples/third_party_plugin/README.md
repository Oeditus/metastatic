# Third-party language plug-in (worked example)

A **separate Mix application** that adds a language to Metastatic without
editing a single file in Metastatic.

This is the acceptance test for the plug-in architecture. If `mix test` here
passes, "a third-party adapter can be added without compiling it into
`metastatic`" is true — not just claimed.

```bash
cd examples/third_party_plugin
mix deps.get
mix test          # 24 tests
mix run -e 'MyLisp.demo()'
```

## What it adds

The `:lisp` language — a small s-expression dialect — with:

| Piece | File |
| :--- | :--- |
| Adapter (M1 ⇄ M2) | `lib/my_lisp/adapters/lisp.ex` |
| M1 reader | `lib/my_lisp/reader.ex` |
| Semantic patterns | `lib/my_lisp/semantic/patterns.ex` |
| Registration | `lib/my_lisp/application.ex` |
| Config hook | `config/config.exs` |

## The three integration points

### 1. The adapter — `use Metastatic.Adapter.Plugin`

```elixir
defmodule MyLisp.Adapters.Lisp do
  use Metastatic.Adapter.Plugin,
    language: :lisp,
    extensions: [".lisp", ".lsp"],
    experimental?: true

  @impl true
  def parse(source), do: MyLisp.Reader.read(source)

  @impl true
  def to_meta(native_ast) do
    native_ast
    |> to_meta_node()
    |> Metastatic.Adapter.enrich(:lisp)     # op_kind / callback_for
  end

  @impl true
  def from_meta(meta_ast, _metadata), do: from_meta_node(meta_ast)

  @impl true
  def unparse(native_ast), do: {:ok, render(native_ast)}
end
```

The macro injects `@behaviour Metastatic.Adapter`, `file_extensions/0`, and the
descriptor callbacks the registry reads. It validates `:language` and
`:extensions` **at compile time of the plug-in**, where the mistake is.

### 2. Registration — one line at boot

Metastatic is started as a dependency *before* the host's `start/2`, so its
registry already exists. `Registry.install/1` is the runtime entry point:

```elixir
def start(_type, _args) do
  :ok = Metastatic.Adapter.Registry.install([MyLisp.Adapters.Lisp])
  Supervisor.start_link([], strategy: :one_for_one)
end
```

If you start the registry yourself, the `:plugins` child-spec option is
equivalent:

```elixir
{Metastatic.Adapter.Registry, plugins: [MyLisp.Adapters.Lisp]}
```

### 3. Semantic patterns — config, no code change

```elixir
config :metastatic, :semantic,
  pattern_providers: [MyLisp.Semantic.Patterns]
```

`Metastatic.Semantic.ensure_registered/0` calls `register_all/0` at boot and
again before the first abstraction, so the patterns survive a VM restart and a
`Patterns.clear_all/0` in a test suite. Without this, enrichment would silently
find nothing.

## What the tests prove

| Claim | Test |
| :--- | :--- |
| Registered at boot, visible to every query | `registration` |
| Extensions detected by `Builder.from_file/2` | `registration`, `reification` |
| Built-ins unaffected | `the built-ins are untouched` |
| Satisfies the `Metastatic.Adapter` contract | `the adapter satisfies the contract` |
| Parses to portable MetaAST | `parsing and abstraction` |
| Round-trips | `reification` |
| **Translates to Elixir and Python** | `cross-language translation` |
| Semantic enrichment via config hook | `semantic enrichment` |
| Survives `clear_all/0` | `enrichment survives a clear_all/0` |

The cross-language test is the payoff:

```elixir
{:ok, doc} = Builder.from_source("(+ 1 2)", :lisp)
{:ok, "1 + 2"} = Builder.to_source(doc, :elixir)
{:ok, "3 * 4"} = Builder.to_source(Builder.from_source!("(* 3 4)", :lisp), :python)
```

Lisp maps to `{:binary_op, [category: :arithmetic, operator: :+], [...]}` — the
same node Python and Elixir produce — so reification works in both directions
with no Lisp-specific knowledge in the target adapters.

## Writing your own

1. `use Metastatic.Adapter.Plugin, language: ..., extensions: [...]`
2. Implement `parse/1`, `to_meta/1`, `from_meta/2`, `unparse/1`
3. End `to_meta/1` with `Metastatic.Adapter.enrich(..., :your_lang)`
4. Register at boot with `Registry.install/1`
5. (Optional) Ship a pattern provider and list it in
   `config :metastatic, :semantic, pattern_providers:`

See `ADAPTER_GUIDE.md` at the repository root for the full contract, the
`Metastatic.Adapter.Bridge` protocol for subprocess parsers, and the round-trip
fidelity targets.
