defmodule Metastatic.MixProject do
  use Mix.Project

  @app :metastatic
  @version "0.1.0"
  @source_url "https://github.com/Oeditus/metastatic"

  def project do
    [
      app: @app,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      consolidate_protocols: Mix.env() not in [:dev, :test],
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      aliases: aliases(),
      test_coverage: [tool: ExCoveralls],
      dialyzer: [
        plt_file: {:no_warn, ".dialyzer/dialyzer.plt"},
        plt_add_deps: :app_tree,
        plt_add_apps: [:mix],
        plt_core_path: ".dialyzer",
        list_unused_filters: true,
        ignore_warnings: ".dialyzer/ignore.exs"
      ],
      name: "Metastatic",
      source_url: @source_url
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(:dev), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:logger],
      mod: {Metastatic.Application, []}
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.json": :test
      ]
    ]
  end

  defp deps do
    [
      # Core dependency
      {:jason, "~> 1.4"},

      # Development and documentation
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18", only: :test, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      quality: ["format", "credo --strict"],
      "quality.ci": [
        "format --check-formatted",
        "credo --strict"
      ]
    ]
  end

  defp description do
    """
    Cross-language code analysis library using unified MetaAST representation.
    Build mutation operators, purity analyzers, and complexity metrics once in Elixir
    and apply them across Python, JavaScript, Elixir, Ruby, Go, Rust, and more.
    """
  end

  defp package do
    [
      name: @app,
      files: ~w(
        lib
        .formatter.exs
        mix.exs
        README.md
        GETTING_STARTED.md
        CHANGELOG.md
        RESEARCH.md
        THEORETICAL_FOUNDATIONS.md
        SUPPLEMENTAL_MODULES.md
        LICENSE
      ),
      licenses: ["GPL-3.0", "CC-BY-SA-4.0"],
      maintainers: ["Aleksei Matiushkin"],
      links: %{
        "GitHub" => @source_url,
        "Documentation" => "https://hexdocs.pm/#{@app}"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      logo: "stuff/img/logo-48x48.png",
      assets: %{"stuff/img" => "assets"},
      extras: extras(),
      extra_section: "GUIDES",
      source_url: @source_url,
      source_ref: "v#{@version}",
      formatters: ["html", "epub"],
      groups_for_modules: groups_for_modules(),
      nest_modules_by_prefix: [Metastatic.Adapters],
      authors: ["Aleksei Matiushkin"],
      canonical: "https://hexdocs.pm/#{@app}",
      skip_undefined_reference_warnings_on: []
    ]
  end

  defp extras do
    [
      "README.md",
      "GETTING_STARTED.md": [title: "Getting Started"],
      "RESEARCH.md": [title: "Architecture & Research"],
      "THEORETICAL_FOUNDATIONS.md": [title: "Theoretical Foundations"],
      "SUPPLEMENTAL_MODULES.md": [title: "Supplemental Modules"],
      "CHANGELOG.md": [title: "Changelog"]
    ]
  end

  defp groups_for_modules do
    [
      "Core Components": [
        Metastatic.AST,
        Metastatic.Document,
        Metastatic.Builder,
        Metastatic.Validator
      ],
      "Language Adapters": [
        Metastatic.Adapter
      ]
    ]
  end
end
