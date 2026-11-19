# Haskell Parser for Metastatic

This directory contains the Haskell parser infrastructure for the Metastatic project.

## Setup

### Install Stack (Haskell build tool)

```bash
curl -sSL https://get.haskellstack.org/ | sh
```

Or on Ubuntu/Debian:
```bash
wget -qO- https://get.haskellstack.org/ | sh
```

### Build the Parser

```bash
cd priv/parsers/haskell
stack setup  # Downloads GHC if needed (first time only)
stack build
```

### Test the Parser

```bash
echo "1 + 2" | stack exec parser
```

Expected output:
```json
{"status":"ok","ast":{"type":"infix","left":{"type":"literal","value":{"literalType":"int","value":1}},"operator":"+","right":{"type":"literal","value":{"literalType":"int","value":2}}},"errorMessage":null}
```

## Development

The parser uses:
- `haskell-src-exts` for parsing Haskell syntax
- `aeson` for JSON serialization
- Stack for dependency management

To add new AST node support, edit `Parser.hs` and add cases to `exprToJson`.

## Supported AST Constructs

The parser emits a JSON node for each Haskell AST form. The Elixir side
(`Metastatic.Adapters.Haskell.ToMeta`) maps every emitted node to a MetaAST
node, so a construct is only "supported" when **both** sides handle it.

### Expressions

| Haskell (`haskell-src-exts`) | JSON `type` | MetaAST |
|---|---|---|
| `Lit` | `literal` | `:literal` |
| `Var` / `Con` | `var` / `con` | `:variable` / `:literal` (`:constructor`) |
| `App` | `app` | `:function_call` (curried) |
| `InfixApp` | `infix` | `:binary_op` or `:function_call` |
| `NegApp` | `negate` | `:unary_op` |
| `Lambda` | `lambda` | `:lambda` |
| `Let` | `let` | `:block` (`construct: :let`) |
| `If` | `if` | `:conditional` |
| `Case` | `case` | `:pattern_match` |
| `List` / `Tuple` | `list` / `tuple` | `:list` / `:tuple` |
| `ListComp` | `list_comp` | `:comprehension` |
| `Do` | `do` | `:block` (`construct: :do_notation`) |
| `ExpTypeSig` | `expr_type_sig` | `:type_annotation` (`annotation_type: :hint`) |
| `RecConstr` | `record_constr` | `:map` (`record: true`) |
| `RecUpdate` | `record_update` | `:language_specific` (`hint: :record_update`) |
| `LeftSection` / `RightSection` | `left_section` / `right_section` | `:language_specific` |
| `EnumFromTo` | `enum_from_to` | `:range` (`range_type: :enum`) |
| `EnumFrom` / `EnumFromThen` | `enum_from` / `enum_from_then` | `:language_specific` |

### Patterns

| Haskell (`haskell-src-exts`) | JSON `type` | MetaAST |
|---|---|---|
| `PVar` | `var_pat` | `:variable` |
| `PLit` | `lit_pat` | `:literal` |
| `PWildCard` | `wildcard` | `:_` |
| `PApp` | `con_pat` | `:function_call` (`pattern: true`) |
| `PParen` | *(unwrapped)* | — |
| `PTuple` | `tuple_pat` | `:tuple` (`pattern: true`) |
| `PList` | `list_pat` | `:list` (`pattern: true`) |
| `PInfixApp` | `infix_pat` | `:binary_op` (`category: :pattern`) |
| `PAsPat` | `as_pat` | `:language_specific` (`hint: :as_pattern`) |
| `PIrrPat` / `PBangPat` | *(unwrapped)* | — |
| `PRec` | `record_pat` | `:map` (`record: true`) |

Constructs that are still not modelled (e.g. `ArithSeq` inside patterns,
`Do`/`MDo` variants, TH quotes) fall back to `unsupported` /
`unsupported_pat` nodes, which `ToMeta` rejects with an explicit error.

## Dogfooding

Both of Metastatic's own Haskell parsers are used as dogfooding fixtures:

- `priv/parsers/haskell/Parser.hs`
- `priv/parsers/agda/Parser.hs`

`test/metastatic/adapters/haskell_test.exs` parses and abstracts both files
and asserts they produce a full `:container` (`container_type: :module`)
without any `unsupported` construct. If a change to the parser introduces a
new AST form, these tests fail first — extend `Parser.hs` and `ToMeta`
together.

## CI Setup

For GitHub Actions, add the following step before running tests:

```yaml
- name: Set up Haskell
  uses: haskell-actions/setup@v2
  with:
    ghc-version: '9.6'
    enable-stack: true
    stack-version: 'latest'

- name: Build Haskell parser
  run: |
    cd priv/parsers/haskell
    stack setup
    stack build
```
