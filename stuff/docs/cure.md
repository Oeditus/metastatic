# Cure Language Integration Plan for Metastatic

## Overview
This document outlines the architecture and implementation for first-class support of the **Cure** programming language (`:cure`) in `metastatic`.

Cure (https://github.com/cure-lang/cure-lang) is a dependently-typed programming language for the BEAM virtual machine with one kernel-checked compiler pipeline and first-class OTP concurrency.

Cure uses MetaAST as its internal AST model (M1 $\equiv$ M2), which makes abstraction and reification direct, zero-loss, and high-fidelity.

---

## 1. Domain & AST Mapping (M1 $\leftrightarrow$ M2)

Because Cure natively targets MetaAST 3-tuples, Cure AST nodes conform directly to MetaAST nodes.

### Construct Mapping Table

| Cure Construct (M1) | MetaAST Representation (M2) | Metadata & Category |
| :--- | :--- | :--- |
| `mod ModuleName \n ...` | `{:container, meta, body}` | `container_type: :module`, `name: "ModuleName"` |
| `actor ActorName with Init \n ...` | `{:container, meta, []}` | `container_type: :actor`, `name: "ActorName"`, `init: Init`, lifecycle callback clauses in meta |
| `sup SupName \n ...` | `{:container, meta, specs}` | `container_type: :supervisor`, `name: "SupName"`, child specs in body |
| `app AppName \n ...` | `{:container, meta, []}` | `container_type: :app`, `name: "AppName"`, vsn/description/callbacks in meta |
| `fsm FsmName with Payload \n ...` | `{:container, meta, transitions}` | `container_type: :fsm`, `name: "FsmName"`, payload/timer/callbacks in meta |
| `rec StructName \n ...` | `{:container, meta, fields}` | `container_type: :struct`, `name: "StructName"` |
| `type EnumName = Variant1 \| ...` | `{:container, meta, variants}` | `container_type: :enum`, `name: "EnumName"` |
| `proto ProtoName \n ...` | `{:container, meta, functions}` | `container_type: :protocol`, `name: "ProtoName"` |
| `use Source as Alias` | `{:import, meta, []}` | `import_type: :use`, `source: "Source"`, `alias: "Alias"` |
| `fn name(params) -> Ret = body` | `{:function_def, meta, body}` | `name: "name"`, `params: params`, `return_type: Ret` |
| `let pattern = val` | `{:assignment, meta, [pattern, val]}` | `pattern`, `value` |
| `if cond then t else e` | `{:conditional, meta, [cond, t, e]}` | `condition`, `then`, `else` |
| `fn(params) -> body` | `{:lambda, meta, [body]}` | `params: params` |
| `^expr` | `{:pin, meta, [expr]}` | pin operator |
| `assert_type expr : Type` | `{:assert_type, meta, [expr, type]}` | type assertion |
| `<<segment::spec>>` | `{:literal, meta, [bin_segment]}` | `subtype: :bytes` |
| `# comment` | `{:comment, meta, text}` | `comment_kind: :line`, `:doc`, or `:block` |

---

## 2. Parser Architecture

Metastatic interfaces with the Cure compiler directly in-process via `Cure.Compiler.Lexer` and `Cure.Compiler.Parser`. When Metastatic runs as a standalone library, the adapter dynamically locates Cure BEAM artifacts or extracts them from the installed `cure` executable (`cure-lang/setup-cure` in CI).

```
Cure Source (.cure)
      │
      ▼
Metastatic.Adapters.Cure.parse/1
      │
      ▼
Cure.Compiler.Lexer & Cure.Compiler.Parser (In-Memory / Dynamic Compiler)
      │
      ▼
Metastatic.Adapters.Cure.ToMeta (M1 -> M2 normalization)
      │
      ▼
Metastatic.Semantic.Enricher (semantic metadata injection)
      │
      ▼
MetaAST Document (%Metastatic.Document{language: :cure})
      │
      ▼
Metastatic.Adapters.Cure.FromMeta (M2 -> M1 reification into source code)
```

---

## 3. Implementation Modules

1. **`Metastatic.Adapters.Cure`** (`lib/metastatic/adapters/cure.ex`)
   Main adapter module implementing `Metastatic.Adapter`.
2. **`Metastatic.Adapters.Cure.ToMeta`** (`lib/metastatic/adapters/cure/to_meta.ex`)
   Transforms/normalizes Cure AST (M1) to MetaAST 3-tuples (M2). Includes dynamic Cure compiler loader.
3. **`Metastatic.Adapters.Cure.FromMeta`** (`lib/metastatic/adapters/cure/from_meta.ex`)
   Reifies MetaAST 3-tuples (M2) into Cure source code strings.
4. **Language Registry Integration** (`lib/metastatic/languages.ex`)
   Registers `cure: Metastatic.Adapters.Cure` in `@adapters`.
5. **CI Integration** (`.github/workflows/ci.yml`)
   Includes `cure-lang/setup-cure@v1` for automated testing in GHA.
6. **Test Suite** (`test/metastatic/adapters/cure_test.exs`)
   Comprehensive tests for parsing, M1 $\leftrightarrow$ M2 transformation, language registration, and round-tripping.
