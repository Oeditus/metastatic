defmodule Metastatic.MixProject do
  use Mix.Project

  @app :metastatic
  @version "0.33.0"
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
      # `:crypto` backs the DLLB cache key digest (`:crypto.hash/2`).
      extra_applications: [:logger, :crypto],
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

      # NOTE: the optional `Dllb` cache backend (see `Metastatic.Cache.DLLB`)
      # is *not* a Hex dependency. It is provided by the host application and
      # detected at runtime via `Code.ensure_loaded?/1`. Enable it with
      # `config :dllb, :enabled, true` and `config :metastatic, :cache, :dllb`.

      # Development and documentation
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18", only: :test, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:benchee, "~> 1.3", only: [:dev, :test], runtime: false},
      {:benchee_html, "~> 1.0", only: [:dev, :test], runtime: false},
      {:stream_data, "~> 1.4", only: [:test], runtime: false}
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
        priv/parsers/agda/Makefile
        priv/parsers/agda/Parser.hs
        priv/parsers/english/parser.js
        priv/parsers/haskell/Parser.hs
        priv/parsers/haskell/README.md
        priv/parsers/haskell/metastatic-haskell-parser.cabal
        priv/parsers/haskell/package.yaml
        priv/parsers/haskell/stack.yaml
        priv/parsers/haskell/stack.yaml.lock
        priv/parsers/javascript/package.json
        priv/parsers/javascript/package-lock.json
        priv/parsers/javascript/parser.js
        priv/parsers/javascript/unparser.js
        priv/parsers/march/dune-project
        priv/parsers/march/march_parser.opam
        priv/parsers/march/bin
        priv/parsers/march/lib
        priv/parsers/python/parser.py
        priv/parsers/python/requirements.txt
        priv/parsers/python/unparser.py
        priv/parsers/ruby/Gemfile
        priv/parsers/ruby/Gemfile.lock
        priv/parsers/ruby/parser.rb
        priv/parsers/ruby/unparser.rb
        .formatter.exs
        mix.exs
        README.md
        GETTING_STARTED.md
        CHANGELOG.md
        THEORETICAL_FOUNDATIONS.md
        SUPPLEMENTAL_MODULES.md
        METAST_SPEC.md
        METAST_NL_SPEC.md
        RESEARCH.md
        CONTRIBUTING_SUPPLEMENTALS.md
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
        Metastatic.NL,
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
        Metastatic.Priv,
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
        Metastatic.Semantic.Callbacks,
        Metastatic.Semantic.Callbacks.BeamIntrospector,
        Metastatic.Semantic.Callbacks.ElixirResolver,
        Metastatic.Semantic.Callbacks.PythonResolver,
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
        Metastatic.Adapters.Agda,
        Metastatic.Adapters.Agda.FromMeta,
        Metastatic.Adapters.Agda.Subprocess,
        Metastatic.Adapters.Agda.ToMeta,
        Metastatic.Adapters.Agda.Unparser,
        Metastatic.Adapters.Cure,
        Metastatic.Adapters.Cure.FromMeta,
        Metastatic.Adapters.Cure.Subprocess,
        Metastatic.Adapters.Cure.ToMeta,
        Metastatic.Adapters.Elixir,
        Metastatic.Adapters.Elixir.FromMeta,
        Metastatic.Adapters.Elixir.MacroExpander,
        Metastatic.Adapters.Elixir.ToMeta,
        Metastatic.Adapters.Erlang,
        Metastatic.Adapters.Erlang.FromMeta,
        Metastatic.Adapters.Erlang.ToMeta,
        Metastatic.Adapters.JavaScript,
        Metastatic.Adapters.JavaScript.FromMeta,
        Metastatic.Adapters.JavaScript.Subprocess,
        Metastatic.Adapters.JavaScript.ToMeta,
        Metastatic.Adapters.Python,
        Metastatic.Adapters.Python.FromMeta,
        Metastatic.Adapters.Python.Subprocess,
        Metastatic.Adapters.Python.ToMeta,
        Metastatic.Adapters.Haskell,
        Metastatic.Adapters.Haskell.FromMeta,
        Metastatic.Adapters.Haskell.Subprocess,
        Metastatic.Adapters.Haskell.ToMeta,
        Metastatic.Adapters.Haskell.Unparser,
        Metastatic.Adapters.March,
        Metastatic.Adapters.March.FromMeta,
        Metastatic.Adapters.March.Subprocess,
        Metastatic.Adapters.March.ToMeta,
        Metastatic.Adapters.Ruby,
        Metastatic.Adapters.Ruby.FromMeta,
        Metastatic.Adapters.Ruby.Subprocess,
        Metastatic.Adapters.Ruby.ToMeta,
        Metastatic.Adapters.TypeScript,
        Metastatic.Adapters.English,
        Metastatic.Adapters.Spanish
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
      NL: [
        Metastatic.NL.AST,
        Metastatic.NL.Adapters.English,
        Metastatic.NL.Adapters.English.FromMeta,
        Metastatic.NL.Adapters.English.Subprocess,
        Metastatic.NL.Adapters.English.ToMeta,
        Metastatic.NL.Adapters.English.Tokenizer,
        Metastatic.NL.Adapters.Spanish,
        Metastatic.NL.Adapters.Spanish.ToMeta,
        Metastatic.NL.Adapters.Spanish.Tokenizer,
        Metastatic.NL.Lint.Issue,
        Metastatic.NL.Lint.Rule,
        Metastatic.NL.Lint.Rules.AvoidPassiveVoice,
        Metastatic.NL.Lint.Rules.AvoidWeaselWords,
        Metastatic.NL.Lint.Rules.SentenceLength,
        Metastatic.NL.Lint.Rules.TerminologyConsistency,
        Metastatic.NL.Lint.Runner,
        Metastatic.NL.Semantic.Enricher,
        Metastatic.NL.Semantic.Readability,
        Metastatic.NL.Validator
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
