[
  # `:dllb` is an optional, test-only dependency, so `Dllb` is not part of the
  # PLT in the `:dev` environment. Every call site in
  # `lib/metastatic/cache/dllb.ex` is guarded by `Code.ensure_loaded?(Dllb)`
  # and wrapped in `try/rescue/catch`, and the module already declares
  # `@compile {:no_warn_undefined, Dllb}` for the compiler.
  {"lib/metastatic/cache/dllb.ex", "Function Dllb.query/1 does not exist."}
]
