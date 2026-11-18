defmodule Metastatic.Semantic do
  @moduledoc """
  Deterministic (re-)registration of the semantic analysis tables.

  ## Why this module exists

  `Metastatic.Semantic.Patterns` and `Metastatic.Semantic.Callbacks` store
  their tables in `:persistent_term`, populated by a module-load side effect
  at the bottom of each provider module:

      # lib/metastatic/semantic/domains/database.ex
      Metastatic.Semantic.Domains.Database.register_all()

  That works exactly once per VM, and only if the module happens to be loaded
  before the first parse. It breaks in three situations that all matter once
  language adapters can live outside this library:

    1. **Restart.** `:persistent_term` does not survive a VM restart, and
       module-load side effects do not re-run for already-loaded modules.
    2. **Clearing.** `Patterns.clear_all/0` and `Callbacks.clear/0` (used by
       the test suite) leave the tables empty with no supported way back.
    3. **Load order.** A third-party adapter's `to_meta/1` may run before the
       domain modules that give it `op_kind` metadata have been loaded.

  In each case the failure is *silent*: `Enricher.enrich_tree/2` simply finds
  no patterns and returns the tree unannotated.

  `ensure_registered/0` is the supported answer. It is idempotent — calling it
  on every parse would be wasteful but not incorrect — and it also registers
  any providers declared by the host application:

      config :metastatic, :semantic,
        pattern_providers: [MyApp.Semantic.RustPatterns],
        callback_providers: [MyApp.Semantic.RustCallbacks]

  A provider is any module exporting `register_all/0` (patterns) or
  `register_builtins/0` (callbacks). Providers are called **after** the
  built-ins, so a host can override or extend a built-in table.

  ## Usage

  Normally you do not call this yourself: `Metastatic.Application` calls it at
  boot, and `Metastatic.Adapter.abstract/3` calls it lazily before the first
  enrichment. Call it directly after clearing the tables:

      Metastatic.Semantic.Patterns.clear_all()
      Metastatic.Semantic.ensure_registered()

  See `Metastatic.Semantic.Patterns.register/3` for the idempotence contract
  that makes repeated registration safe.
  """

  alias Metastatic.Semantic.{Callbacks, Patterns}

  require Logger
  # The domain modules that own the built-in pattern tables. Listed explicitly
  # rather than discovered so that a missing module is a compile-time-visible
  # omission rather than a silently skipped provider.
  @builtin_pattern_providers [
    Metastatic.Semantic.Domains.Database,
    Metastatic.Semantic.Domains.Auth,
    Metastatic.Semantic.Domains.Http,
    Metastatic.Semantic.Domains.Cache,
    Metastatic.Semantic.Domains.Queue,
    Metastatic.Semantic.Domains.File,
    Metastatic.Semantic.Domains.ExternalApi
  ]

  @doc """
  Registers every built-in and host-configured semantic provider.

  Idempotent: safe to call repeatedly, and safe to call after
  `Patterns.clear_all/0` or `Callbacks.clear/0`. Returns `:ok` even when a
  provider is missing or raises, so a broken third-party provider cannot take
  down application boot — failures are reported through telemetry instead.

  ## Examples

      iex> Metastatic.Semantic.ensure_registered()
      :ok

      iex> Metastatic.Semantic.Patterns.clear_all()
      iex> Metastatic.Semantic.ensure_registered()
      :ok
      iex> Metastatic.Semantic.Patterns.get_patterns(:db, :elixir) != []
      true
  """
  @spec ensure_registered() :: :ok
  def ensure_registered do
    register_pattern_providers(builtin_pattern_providers() ++ configured_pattern_providers())
    register_callback_providers([Callbacks | configured_callback_providers()])
    :ok
  end

  @doc """
  Registers the semantic tables only if they are empty.

  This is the variant `Metastatic.Adapter.abstract/3` calls before every
  abstraction. `ensure_registered/0` would be correct but not *safe* there: it
  unconditionally re-runs every built-in provider, and a test that deliberately
  replaced the callback registry with a partial one (then parsed some code)
  would have its state silently overwritten mid-test.

  Registering only when the table is empty gives the recovery the lazy path
  needs — a VM restart or a `clear_all/0` leaves it empty, so it is repopulated
  — without clobbering a deliberately narrowed registry.

  ## Examples

      iex> Metastatic.Semantic.ensure_registered()
      :ok
      iex> Metastatic.Semantic.ensure_registered_if_empty()
      :ok
  """
  @spec ensure_registered_if_empty() :: :ok
  def ensure_registered_if_empty do
    if Patterns.empty?() do
      register_pattern_providers(builtin_pattern_providers() ++ configured_pattern_providers())
    else
      # The built-ins are present, but a host provider may not be: a caller can
      # register one domain and leave the rest empty, or `clear_all/0` can be
      # followed by a partial re-registration. Re-running the *configured*
      # providers is cheap and idempotent (`Patterns.register/3` deduplicates),
      # and it is the only way a host's patterns come back without the caller
      # having to know about the ordering.
      register_pattern_providers(configured_pattern_providers())
    end

    if Callbacks.empty?() do
      register_callback_providers([Callbacks | configured_callback_providers()])
    end

    :ok
  end

  @doc """
  Returns the built-in pattern provider modules, in registration order.

  Exposed so tests and diagnostics can assert that every domain module is
  accounted for without duplicating the list.

  ## Examples

      iex> Metastatic.Semantic.Domains.Database in Metastatic.Semantic.builtin_pattern_providers()
      true
  """
  @spec builtin_pattern_providers() :: [module()]
  def builtin_pattern_providers, do: @builtin_pattern_providers

  @doc """
  Returns the pattern providers configured by the host application.

  ## Examples

      iex> is_list(Metastatic.Semantic.configured_pattern_providers())
      true
  """
  @spec configured_pattern_providers() :: [module()]
  def configured_pattern_providers do
    semantic_config()
    |> Keyword.get(:pattern_providers, [])
    |> Enum.filter(&is_atom/1)
  end

  @doc """
  Returns the callback providers configured by the host application.

  ## Examples

      iex> is_list(Metastatic.Semantic.configured_callback_providers())
      true
  """
  @spec configured_callback_providers() :: [module()]
  def configured_callback_providers do
    semantic_config()
    |> Keyword.get(:callback_providers, [])
    |> Enum.filter(&is_atom/1)
  end

  # `Application.get_env/3` returns whatever the host put there — including
  # `nil` when a config file sets the key to nil, which is common in test
  # suites that toggle it. Normalise to a keyword list so the accessors below
  # can rely on `Keyword.get/3`.
  defp semantic_config do
    case Application.get_env(:metastatic, :semantic) do
      config when is_list(config) -> config
      _ -> []
    end
  end

  # ----- Private -----

  defp register_pattern_providers(providers) do
    Enum.each(providers, &call_provider(&1, :register_all, :pattern_provider_failed))
  end

  defp register_callback_providers(providers) do
    Enum.each(providers, &call_provider(&1, :register_builtins, :callback_provider_failed))
  end

  # A provider that is missing or raises must not break boot or a parse. The
  # whole point of `ensure_registered/0` is that it always leaves the system
  # in a usable state; a broken third-party provider degrades to "no extra
  # patterns" rather than an exception in the middle of a tree traversal.
  defp call_provider(module, fun, event) do
    if Code.ensure_loaded?(module) and function_exported?(module, fun, 0) do
      apply(module, fun, [])
    else
      :ok
    end
  rescue
    error ->
      Logger.warning(
        "Metastatic semantic provider #{inspect(module)}.#{fun}/0 failed " <>
          "(#{event}): #{Exception.message(error)}"
      )

      :ok
  end
end
