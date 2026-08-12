defmodule Metastatic.MixProject do
  use Mix.Project

  @app :metastatic
  @version "0.28.0"
  @source_url "https://github.com/Oeditus/metastatic"

  def project do
    [
      app: @app,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      consolidate_protocols: Mix.env() not in [:dev, :test],
      test_ignore_filters: [~r"/fixtures/", ~r"/benchmarks/"],
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      aliases: aliases(),
      test_coverage: [tool: ExCoveralls],
      dialyzer: [
        plt_file: {:no_warn, ".dialyzer/dialyzer.plt"},
        plt_add_deps: :app_tree,
        plt_add_apps: [:mix, :ex_unit],
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
      # Core dependencies
      {:jason, "~> 1.4"},
      {:ex_panda, "~> 0.2"},
      {:typle, "~> 0.3", optional: true},

      # Development and documentation
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18", only: :test, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:benchee, "~> 1.3", only: [:dev, :test], runtime: false},
      {:benchee_html, "~> 1.0", only: [:dev, :test], runtime: false}
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
    Cross-language code meta-model library using unified MetaAST representation.
    Parse, transform, and translate code across Python, Elixir, Ruby, Erlang,
    Haskell, and more via a shared three-tuple AST format.
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
        THEORETICAL_FOUNDATIONS.md
        SUPPLEMENTAL_MODULES.md
        METAST_SPEC.md
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
      nest_modules_by_prefix: [
        Metastatic.Adapters,
        Metastatic.CLI,
        Metastatic.Semantic,
        Metastatic.Semantic.Domains,
        Metastatic.Supplemental
      ],
      authors: ["Aleksei Matiushkin"],
      canonical: "https://hexdocs.pm/#{@app}",
      skip_undefined_reference_warnings_on: [],
      before_closing_body_tag: &before_closing_body_tag/1
    ]
  end

  defp extras do
    [
      "README.md",
      "GETTING_STARTED.md": [title: "Getting Started"],
      "THEORETICAL_FOUNDATIONS.md": [title: "Theoretical Foundations"],
      "SUPPLEMENTAL_MODULES.md": [title: "Supplemental Modules"],
      "METAST_SPEC.md": [title: "MetaAST Informal Specification"],
      "CHANGELOG.md": [title: "Changelog"]
    ]
  end

  defp groups_for_modules do
    [
      # Metastatic
      # Metastatic.Languages

      "Core Components": [
        Metastatic.AST,
        Metastatic.Document,
        Metastatic.Builder,
        Metastatic.Validator,
        Metastatic.Cache,
        Metastatic.Cache.ETS,
        Metastatic.Cache.DLLB
      ],
      CLI: [
        Metastatic.CLI,
        Metastatic.CLI.Formatter,
        Metastatic.CLI.Inspector,
        Metastatic.CLI.Translator
      ],
      Semantic: [
        Metastatic.Semantic.Domains.Auth,
        Metastatic.Semantic.Domains.Cache,
        Metastatic.Semantic.Domains.Database,
        Metastatic.Semantic.Domains.ExternalApi,
        Metastatic.Semantic.Domains.File,
        Metastatic.Semantic.Domains.Http,
        Metastatic.Semantic.Domains.Queue,
        Metastatic.Semantic.Enricher,
        Metastatic.Semantic.OpKind,
        Metastatic.Semantic.Patterns
      ],
      "Language Adapters": [
        Metastatic.Adapter,
        Metastatic.Adapter.Registry,
        Metastatic.Adapters.Cure,
        Metastatic.Adapters.Cure.FromMeta,
        Metastatic.Adapters.Cure.ToMeta,
        Metastatic.Adapters.Elixir,
        Metastatic.Adapters.Elixir.FromMeta,
        Metastatic.Adapters.Elixir.MacroExpander,
        Metastatic.Adapters.Elixir.ToMeta,
        Metastatic.Adapters.Erlang,
        Metastatic.Adapters.Erlang.FromMeta,
        Metastatic.Adapters.Erlang.ToMeta,
        Metastatic.Adapters.Python,
        Metastatic.Adapters.Python.FromMeta,
        Metastatic.Adapters.Python.Subprocess,
        Metastatic.Adapters.Python.ToMeta,
        Metastatic.Adapters.Haskell,
        Metastatic.Adapters.Haskell.FromMeta,
        Metastatic.Adapters.Haskell.Subprocess,
        Metastatic.Adapters.Haskell.ToMeta,
        Metastatic.Adapters.Ruby,
        Metastatic.Adapters.Ruby.FromMeta,
        Metastatic.Adapters.Ruby.Subprocess,
        Metastatic.Adapters.Ruby.ToMeta
      ],
      Supplemental: [
        Metastatic.Supplemental,
        Metastatic.Supplemental.CompatibilityMatrix,
        Metastatic.Supplemental.Error,
        Metastatic.Supplemental.Info,
        Metastatic.Supplemental.Python.Asyncio,
        Metastatic.Supplemental.Python.Pykka,
        Metastatic.Supplemental.Registry,
        Metastatic.Supplemental.Transformer,
        Metastatic.Supplemental.Validator
      ],
      Internals: [
        Metastatic.Test.AdapterHelper,
        Metastatic.Test.FixtureHelper
      ]
    ]
  end

  defp before_closing_body_tag(:html) do
    """
    <script src="https://cdn.jsdelivr.net/npm/mermaid@10.9.0/dist/mermaid.min.js"></script>
    <script>
      document.addEventListener("DOMContentLoaded", function () {
        mermaid.initialize({
          startOnLoad: true,
          theme: "default",
          flowchart: {
            useMaxWidth: true,
            htmlLabels: true,
            curve: "basis"
          }
        });
        window.mermaid = mermaid;
      });
    </script>
    """
  end

  defp before_closing_body_tag(_), do: ""
end
