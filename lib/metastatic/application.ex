defmodule Metastatic.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  alias Metastatic.Languages.Store

  @impl true
  def start(_type, _args) do
    Metastatic.Cache.init()

    # Register the semantic pattern/callback tables deterministically rather
    # than relying on module-load side effects, which do not re-run across a
    # VM restart and are wiped by `Patterns.clear_all/0`. Host applications
    # can extend the tables with `config :metastatic, :semantic`.
    Metastatic.Semantic.ensure_registered()

    # Create the language store before the registry seeds it. Reads fall back
    # to the compile-time built-ins when the tables are absent, so this is an
    # ordering convenience rather than a correctness requirement.
    Store.init()

    children = [
      # Adapter registry for managing language adapters
      Metastatic.Adapter.Registry,
      # Supplemental module registry
      Metastatic.Supplemental.Registry
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Metastatic.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
