import Config

# The host-side semantic provider hook added in Phase 1. Metastatic calls
# `MyLisp.Semantic.Patterns.register_all/0` at boot and before the first
# abstraction, so a Lisp `(db-find ...)` gets an `op_kind` annotation.
config :metastatic, :semantic,
  pattern_providers: [MyLisp.Semantic.Patterns]
