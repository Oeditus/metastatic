# March Language Integration Plan for Metastatic

## Overview
This document outlines the architecture and implementation plan for adding first-class support for the **March** programming language (`:march`) in `metastatic`.

March (https://march-lang.org/, https://github.com/march-language/march) is a statically typed functional programming language built in OCaml. It features algebraic data types, pattern matching, capability-tracked side effects (`needs IO.Console`), reference counting with in-place reuse (Perceus / FBIP), private functions (`pfn`), string concatenation (`++`), and a BEAM-inspired **Actor Model** (`actor`, `state`, `init`, `on` handlers, `spawn`, `send`).

---

## 1. Domain & AST Mapping (M1 $\leftrightarrow$ M2)

### Construct Mapping Table

| March Construct (M1) | MetaAST Representation (M2) | Metadata & Category |
| :--- | :--- | :--- |
| `mod ModuleName do ... end` | `{:container, meta, body}` | `container_type: :module`, `subtype: :module`, `name: "ModuleName"` |
| `actor Counter do ... end` | `{:container, meta, []}` | `container_type: :actor`, `subtype: :actor`, `name: "Counter"`, carrying `state`, `init`, `on_message` callbacks |
| `needs IO.Console` | `{:import, meta, []}` | `import_type: :needs`, `source: "IO.Console"`, `capability: "IO.Console"` |
| `use Std.String` | `{:import, meta, []}` | `import_type: :use`, `source: "Std.String"` |
| `pfn name(param: Type) : Ret do ...` | `{:function_def, meta, [params, body]}` | `name: "name"`, `visibility: :private`, `return_type: "Ret"` |
| `fn name(param: Type) : Ret do ...` | `{:function_def, meta, [params, body]}` | `name: "name"`, `visibility: :public`, `return_type: "Ret"` |
| `on Message(x: Int) do ... end` | `{:function_def, meta, [params, body]}` | `name: "on:Message"`, `callback_for: "on_message"` |
| `let x = val` / `{ state with count: n }` | `{:assignment, meta, [var, val]}` / `{:record_update, meta, [target, updates]}` | `subtype: :let` or `:record_update` |
| `type Shape = Circle(Float) \| ...` | `{:container, meta, arms}` | `subtype: :enum` |
| `match expr do Variant(x) -> ... end` | `{:pattern_match, meta, [expr \| arms]}` | `match_arm` nodes for clauses |
| `"a" ++ "b"` | `{:binary_op, meta, [l, r]}` | `category: :string`, `operator: :++` |
| `spawn(Actor, Init)` / `send(pid, msg)` | `{:function_call, meta, args}` | `name: "spawn"` / `name: "send"`, tagged with `op_kind: :concurrency` |
| Literals & Expressions | `{:literal, meta, val}`, `{:variable, meta, name}`, `{:binary_op, meta, [l, r]}` | `subtype: :integer`, `:string`, etc. |

---

## 2. Parsing & IPC Subprocess Architecture

Metastatic interfaces with March using pure OCaml executables compiled via Dune.

```
Source Code (.march)
      │
      ▼
priv/parsers/march/_build/default/bin/parser.exe (Native OCaml CLI)
      │  (JSON AST stdout)
      ▼
Metastatic.Adapters.March.Subprocess
      │
      ▼
Metastatic.Adapters.March.ToMeta (M1 -> M2)
      │
      ▼
Metastatic.Semantic.Enricher (injects concurrency op_kinds)
      │
      ▼
MetaAST Document (%Metastatic.Document{language: :march})
```

---

## 3. Implementation Modules

1. **`Metastatic.Adapters.March`** (`lib/metastatic/adapters/march.ex`)
   Main adapter module implementing `Metastatic.Adapter`.
2. **`Metastatic.Adapters.March.ToMeta`** (`lib/metastatic/adapters/march/to_meta.ex`)
   Transforms March AST maps/nodes (M1) to MetaAST 3-tuples (M2).
3. **`Metastatic.Adapters.March.FromMeta`** (`lib/metastatic/adapters/march/from_meta.ex`)
   Reifies MetaAST 3-tuples (M2) into March AST maps/nodes (M1).
4. **`Metastatic.Adapters.March.Subprocess`** (`lib/metastatic/adapters/march/subprocess.ex`)
   Subprocess helper executing the native OCaml parser/unparser binaries.
5. **Language Registry Integration** (`lib/metastatic/languages.ex`)
   Register `march: Metastatic.Adapters.March` in `@adapters`.
6. **Pure OCaml Parser Toolchain** (`priv/parsers/march/`)
   Standalone Dune OCaml project compiling `parser.exe` and `unparser.exe`.
7. **Test Suite** (`test/metastatic/adapters/march_test.exs`)
   Comprehensive tests for parsing, M1 $\leftrightarrow$ M2 transformation, capabilities, actor handlers, private functions, operators, and round-tripping.
