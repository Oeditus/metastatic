defmodule Metastatic.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Adapter registry for managing language adapters
      Metastatic.Adapter.Registry,
      # Supplemental module registry
      Metastatic.Supplemental.Registry,
      # Analyzer registry for managing analysis plugins
      Metastatic.Analysis.Registry
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Metastatic.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
