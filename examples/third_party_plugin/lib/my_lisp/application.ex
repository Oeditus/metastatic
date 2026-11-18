defmodule MyLisp.Application do
  @moduledoc """
  Starts the host application and registers the `:lisp` plug-in.

  Metastatic is started automatically as a dependency, *before* this
  application's `start/2` runs, so its registry is already up. That means the
  `:plugins` child-spec option is not available here — it only applies when you
  start the registry yourself. `Registry.install/1` is the runtime equivalent,
  and is what a real host application should use.
  """

  use Application

  @impl true
  def start(_type, _args) do
    :ok = install_language_plugins()

    children = []

    Supervisor.start_link(children, strategy: :one_for_one, name: MyLisp.Supervisor)
  end

  defp install_language_plugins do
    case Metastatic.Adapter.Registry.install([MyLisp.Adapters.Lisp]) do
      :ok ->
        :ok

      {:error, failures} ->
        # A bad plug-in is a configuration error; failing loudly at boot is
        # better than a language that silently does not exist.
        raise "failed to install language plugins: #{inspect(failures)}"
    end
  end
end
