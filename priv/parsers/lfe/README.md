# LFE parser assets

LFE (Lisp-Flavoured Erlang) is parsed **in-process**: its reader and compiler
are ordinary Erlang modules, so this directory holds no bridge script and no
compiled artefact. It exists to document how the adapter finds the toolchain.

## Required modules

| Module | Used for |
| :--- | :--- |
| `lfe_io` | `parse_file/2` (reading) and `prettyprint1/1` (printing) |
| `lfe_scan` | tokenising (used by `lfe_io`) |
| `lfe_parse` | the reader grammar (used by `lfe_io`) |
| `lfe_comp` | `forms/2` — macro expansion for `expand_macros: true` |

None of these are part of OTP.

## Resolution order

`Metastatic.Adapters.Lfe.Reader.ensure_loaded/0` tries, in order:

1. `:lfe_io` already loadable — the normal case for a project that depends on
   LFE, or a shell started with `-pa /path/to/lfe/ebin`;
2. `priv/parsers/lfe/ebin` (this directory) — a vendored copy of LFE's `ebin`,
   added with `Code.prepend_path/1`;
3. the `:lfe` application's own `ebin` via `:code.lib_dir/1`.

When none work, every callback returns `{:error, reason}` naming the missing
modules and how to install LFE. Nothing raises.

## Installing LFE

```bash
git clone https://github.com/lfe/lfe.git
cd lfe
make
# then either put it on the code path:
elixir -pa /path/to/lfe/ebin ...
# or vendor it:
cp -r /path/to/lfe/ebin your_app/priv/parsers/lfe/ebin
```

## Why LFE is flagged experimental

LFE is listed in `Metastatic.Languages.Builtin.@default_experimental`
alongside Agda and Haskell because its toolchain is not part of OTP.
This repository installs LFE as a development/test dependency, so Dialyzer
and CI exercise the real toolchain. Host applications must supply LFE
themselves; the conformance and fixture suites skip when it is absent.
