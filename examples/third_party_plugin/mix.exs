defmodule MyLisp.MixProject do
  use Mix.Project

  @moduledoc """
  Worked example: a third-party language plug-in for Metastatic.

  This project lives *outside* Metastatic's source tree and depends on it as an
  ordinary Hex/path dependency. It adds the `:lisp` language — a small s-expression
  dialect — without editing a single file in Metastatic.

  Run it:

      cd examples/third_party_plugin
      mix deps.get
      mix test
      mix run -e 'MyLisp.demo()'
  """

  def project do
    [
      app: :my_lisp,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {MyLisp.Application, []}
    ]
  end

  defp deps do
    [
      # A real third-party consumer depends on the published package. The path
      # dependency keeps the example runnable from a checkout.
      {:metastatic, path: "../.."}
    ]
  end
end
