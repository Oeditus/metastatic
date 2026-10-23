# Exclude adapters that require an external toolchain (GHC / Agda) which is
# not part of the default local or CI environment. Run them explicitly with
# `mix test --include haskell --include agda` once the toolchain is available.
ExUnit.start(exclude: [:haskell, :agda])
