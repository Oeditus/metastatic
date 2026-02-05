defmodule Metastatic.MixProject do
  use Mix.Project

  @app :metastatic
  @version "0.8.4"
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
        Metastatic.Analysis,
        Metastatic.Analysis.BusinessLogic,
        Metastatic.Analysis.Cohesion,
        Metastatic.Analysis.Complexity,
        Metastatic.Analysis.ControlFlow,
        Metastatic.Analysis.DeadCode,
        Metastatic.Analysis.Duplication,
        Metastatic.Analysis.Encapsulation,
        Metastatic.Analysis.Purity,
        Metastatic.Analysis.Security,
        Metastatic.Analysis.Smells,
        Metastatic.Analysis.StateManagement,
        Metastatic.Analysis.Taint,
        Metastatic.Analysis.UnusedVariables,
        Metastatic.CLI,
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
      "lib/metastatic/analysis/ANALYZER_PLUGIN_SYSTEM.md": [title: "Analyzer Plugin System"],
      "lib/metastatic/analysis/ANALYZER_PLUGIN_DESIGN.md": [title: "Analyzer Plugin Design"],
      "lib/metastatic/analysis/CUSTOM_ANALYZER_GUIDE.md": [title: "Custom Analyzer Guide"],
      "METAST_SPEC.md": [title: "MetaAST Informal Specification"],
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
      CLI: [
        Metastatic.CLI,
        Metastatic.CLI.Formatter,
        Metastatic.CLI.Inspector,
        Metastatic.CLI.Translator
      ],
      Analysis: [
        Metastatic.Analysis.Analyzer,
        Metastatic.Analysis.ApiSurface,
        Metastatic.Analysis.BusinessLogic.BlockingInPlug,
        Metastatic.Analysis.BusinessLogic.CallbackHell,
        Metastatic.Analysis.BusinessLogic.DirectStructUpdate,
        Metastatic.Analysis.BusinessLogic.HardcodedValue,
        Metastatic.Analysis.BusinessLogic.InefficientFilter,
        Metastatic.Analysis.BusinessLogic.InlineJavascript,
        Metastatic.Analysis.BusinessLogic.MissingErrorHandling,
        Metastatic.Analysis.BusinessLogic.MissingHandleAsync,
        Metastatic.Analysis.BusinessLogic.MissingPreload,
        Metastatic.Analysis.BusinessLogic.MissingTelemetryForExternalHttp,
        Metastatic.Analysis.BusinessLogic.MissingTelemetryInAuthPlug,
        Metastatic.Analysis.BusinessLogic.MissingTelemetryInLiveviewMount,
        Metastatic.Analysis.BusinessLogic.MissingTelemetryInObanWorker,
        Metastatic.Analysis.BusinessLogic.MissingThrottle,
        Metastatic.Analysis.BusinessLogic.NPlusOneQuery,
        Metastatic.Analysis.BusinessLogic.SilentErrorCase,
        Metastatic.Analysis.BusinessLogic.SwallowingException,
        Metastatic.Analysis.BusinessLogic.SyncOverAsync,
        Metastatic.Analysis.BusinessLogic.TelemetryInRecursiveFunction,
        Metastatic.Analysis.BusinessLogic.UnmanagedTask,
        Metastatic.Analysis.Cohesion,
        Metastatic.Analysis.Cohesion.Formatter,
        Metastatic.Analysis.Cohesion.Result,
        Metastatic.Analysis.Complexity,
        Metastatic.Analysis.Complexity.Cognitive,
        Metastatic.Analysis.Complexity.Cyclomatic,
        Metastatic.Analysis.Complexity.Formatter,
        Metastatic.Analysis.Complexity.FunctionMetrics,
        Metastatic.Analysis.Complexity.Halstead,
        Metastatic.Analysis.Complexity.LoC,
        Metastatic.Analysis.Complexity.Nesting,
        Metastatic.Analysis.Complexity.Result,
        Metastatic.Analysis.ControlFlow,
        Metastatic.Analysis.ControlFlow.Result,
        Metastatic.Analysis.Coupling,
        Metastatic.Analysis.DeadCode,
        Metastatic.Analysis.DeadCodeAnalyzer,
        Metastatic.Analysis.DeadCode.Result,
        Metastatic.Analysis.Duplication,
        Metastatic.Analysis.Duplication.Fingerprint,
        Metastatic.Analysis.Duplication.Reporter,
        Metastatic.Analysis.Duplication.Result,
        Metastatic.Analysis.Duplication.Similarity,
        Metastatic.Analysis.Duplication.Types,
        Metastatic.Analysis.Encapsulation,
        Metastatic.Analysis.Encapsulation.Formatter,
        Metastatic.Analysis.Encapsulation.Result,
        Metastatic.Analysis.NestingDepth,
        Metastatic.Analysis.Purity,
        Metastatic.Analysis.Purity.Effects,
        Metastatic.Analysis.Purity.Formatter,
        Metastatic.Analysis.Purity.Result,
        Metastatic.Analysis.Registry,
        Metastatic.Analysis.Runner,
        Metastatic.Analysis.Security,
        Metastatic.Analysis.Security.Result,
        Metastatic.Analysis.SimplifyConditional,
        Metastatic.Analysis.Smells,
        Metastatic.Analysis.Smells.Result,
        Metastatic.Analysis.StateManagement,
        Metastatic.Analysis.StateManagement.Formatter,
        Metastatic.Analysis.StateManagement.Result,
        Metastatic.Analysis.Taint,
        Metastatic.Analysis.Taint.Result,
        Metastatic.Analysis.UnusedVariables,
        Metastatic.Analysis.UnusedVariables.Result
      ],
      "Language Adapters": [
        Metastatic.Adapter,
        Metastatic.Adapter.Registry,
        Metastatic.Adapters.Elixir,
        Metastatic.Adapters.Elixir.FromMeta,
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
