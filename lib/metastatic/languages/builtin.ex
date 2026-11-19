defmodule Metastatic.Languages.Builtin do
  @moduledoc """
  Compile-time discovery of the language adapters that ship inside Metastatic.

  This module is the *seed* half of the hybrid registry. It scans
  `lib/metastatic/adapters/` once at compile time and produces the
  `%Metastatic.Language{}` descriptors for the built-in languages. At runtime
  those descriptors are loaded into `Metastatic.Languages.Store`, which host
  applications can extend with their own adapters.

  ## Why compile-time for built-ins

  Scanning the source tree at compile time gives two things a runtime scan
  cannot:

    * `@external_resource`, so adding or removing an adapter file triggers a
      recompile of this module (and therefore of the seed list);
    * zero startup cost — the descriptors are a compile-time constant.

  Third-party adapters do not need either: they are registered explicitly at
  boot (see `Metastatic.Adapter.Registry`), so nothing has to be discovered.

  ## Discovery contract

  A module under `lib/metastatic/adapters/` is registered when its source
  declares `@behaviour Metastatic.Adapter`. The language atom is the module's
  last name segment, downcased: `Metastatic.Adapters.TypeScript` becomes
  `:typescript`.

  ### Exclusions

  Some adapter modules are language adapters only in the structural sense but
  are not *source languages* for the code pipeline. These are listed in
  `@excluded` and skipped:

    * `english`, `spanish` — NL adapters (natural-language prose), reachable
      through `Metastatic.NL.Adapters.*` instead.

  ### Config overrides

  Discovery can be adjusted at compile time through application config:

      config :metastatic, :languages,
        exclude: [:spanish],
        include: [%{language: :mylang, adapter: MyApp.Adapters.MyLang}],
        experimental: [:mylang],
        documentation: [:markdown]

    * `:exclude` — language atoms to drop from the discovered set
    * `:include` — extra `%{language: atom, adapter: module}` entries to add
    * `:experimental` — language atoms to flag as experimental
    * `:documentation` — language atoms to flag as document languages

  `:include` still works, but a host application no longer needs it: prefer
  `Metastatic.Adapter.Registry.register/2` (or the `:plugins` option on the
  registry's child spec), which does not require recompiling Metastatic.
  """

  alias Metastatic.Language

  # Adapters that are structurally `Metastatic.Adapter` implementations but are
  # not source languages for the code pipeline. Kept here (not in the adapter
  # modules) so that discovery stays purely name-driven.
  @excluded [:english, :spanish]

  # Languages whose adapters require non-OTP toolchains (GHC/Agda/LFE).
  # They remain usable but are advertised as experimental.
  #
  # `:lfe` is here because LFE's reader/compiler (`lfe_scan`, `lfe_io`,
  # `lfe_comp`) are not part of OTP. The development/test dependency makes
  # them available in CI, but host applications still provide LFE themselves.
  @default_experimental [:agda, :haskell, :lfe]

  # Languages that describe documents rather than executable code. They are
  # fully parseable and analyzable, but carry no callable entities.
  @default_documentation [:markdown]

  # ── Discovery ───────────────────────────────────────────────────────

  @discovered_modules Metastatic.Languages.Discovery.discover()

  @adapter_sources Path.wildcard(Path.join(__DIR__, "../adapters/*.ex"))
  for source <- @adapter_sources do
    @external_resource source
  end

  @doc false
  @spec __mix_recompile__?() :: boolean()
  def __mix_recompile__? do
    Path.wildcard(Path.join(__DIR__, "../adapters/*.ex")) != @adapter_sources
  end

  # Config-driven overrides. `Application.compile_env/3` is evaluated at compile
  # time so the seed list stays a compile-time constant.
  @config_overrides Application.compile_env(:metastatic, :languages, [])
  @config_exclude Keyword.get(@config_overrides, :exclude, [])
  @config_include Keyword.get(@config_overrides, :include, [])
  @config_experimental Keyword.get(@config_overrides, :experimental, [])
  @config_documentation Keyword.get(@config_overrides, :documentation, [])

  @experimental Enum.uniq(@default_experimental ++ @config_experimental)
  @documentation Enum.uniq(@default_documentation ++ @config_documentation)

  # Build the final list of `%Metastatic.Language{}` descriptors.
  @languages (
               discovered =
                 @discovered_modules
                 |> Enum.reject(fn {lang, _mod} ->
                   lang in @excluded or lang in @config_exclude
                 end)

               included =
                 Enum.map(@config_include, fn
                   %{language: lang, adapter: mod} -> {lang, mod}
                   {lang, mod} -> {lang, mod}
                 end)

               (discovered ++ included)
               |> Enum.uniq_by(fn {lang, _mod} -> lang end)
               |> Enum.sort_by(fn {lang, _mod} -> lang end)
               |> Enum.map(fn {lang, mod} ->
                 Language.new(lang, mod,
                   experimental?: lang in @experimental,
                   documentation?: lang in @documentation
                 )
               end)
             )

  @doc """
  Returns the built-in language descriptors, sorted by language atom.

  These are the adapters compiled into Metastatic. Host applications extend
  this set at runtime rather than by editing it.

  ## Examples

      iex> Enum.map(Metastatic.Languages.Builtin.all(), & &1.language) |> Enum.member?(:python)
      true

      iex> Enum.all?(Metastatic.Languages.Builtin.all(), &match?(%Metastatic.Language{}, &1))
      true
  """
  @spec all() :: [Language.t()]
  def all, do: @languages

  @doc """
  Returns the language atoms of the built-in adapters, sorted.

  ## Examples

      iex> :python in Metastatic.Languages.Builtin.languages()
      true
  """
  @spec languages() :: [atom()]
  def languages, do: Enum.map(@languages, & &1.language)

  @doc """
  Returns the language atoms flagged as experimental.

  ## Examples

      iex> :agda in Metastatic.Languages.Builtin.experimental_languages()
      true
  """
  @spec experimental_languages() :: [atom()]
  def experimental_languages, do: @experimental

  @doc """
  Returns the language atoms flagged as documentation languages.

  ## Examples

      iex> :markdown in Metastatic.Languages.Builtin.documentation_languages()
      true
  """
  @spec documentation_languages() :: [atom()]
  def documentation_languages, do: @documentation

  @doc """
  Returns the `{language, adapter}` pairs discovered by the source scan,
  before exclusions and config overrides are applied.

  Exposed for diagnostics and for the discovery tests.

  ## Examples

      iex> is_list(Metastatic.Languages.Builtin.discovered_modules())
      true
  """
  @spec discovered_modules() :: [{atom(), module()}]
  def discovered_modules, do: @discovered_modules
end
