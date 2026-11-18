# Adapters that need an external toolchain (GHC for Haskell, Agda for Agda)
# are excluded only when that toolchain is genuinely absent. Previously this
# was a static `exclude: [:haskell, :agda]`, which silently skipped 81 tests on
# every machine — including the ones that do have GHC and Agda installed.
#
# Run them explicitly with `mix test --include haskell --include agda` to
# override the detection.

toolchain_present? = fn executables ->
  Enum.any?(executables, &(System.find_executable(&1) != nil))
end

maybe_exclude = fn acc, tag, missing? ->
  if missing?, do: [tag | acc], else: acc
end

excluded =
  []
  |> maybe_exclude.(:haskell, not toolchain_present?.(["stack", "ghc"]))
  |> maybe_exclude.(:agda, not toolchain_present?.(["agda"]))

ExUnit.start(exclude: excluded)
