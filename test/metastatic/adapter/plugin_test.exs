defmodule Metastatic.Adapter.PluginTest do
  @moduledoc """
  End-to-end test for third-party language adapters.

  This is the acceptance test for the plug-in architecture: a module that
  lives *outside* `lib/metastatic/adapters/`, built with
  `Metastatic.Adapter.Plugin`, registered at runtime, and then used through the
  ordinary public API (`Metastatic.quote/2`, `Builder`, `Languages`).

  The sample language is deliberately trivial — it parses `N` as an integer
  literal — because the point is the *wiring*, not the mapping.
  """

  use ExUnit.Case, async: false

  alias Metastatic.{Adapter, Builder, Languages}

  defmodule SampleAdapter do
    @moduledoc false
    use Metastatic.Adapter.Plugin,
      language: :sample_lang,
      extensions: [".sample", ".smp"],
      experimental?: true

    @impl true
    def parse(source) do
      case Integer.parse(String.trim(source)) do
        {value, ""} -> {:ok, value}
        _ -> {:error, "not an integer"}
      end
    end

    @impl true
    def to_meta(value) when is_integer(value) do
      {:ok, {:literal, [subtype: :integer], value}, %{}}
    end

    @impl true
    def from_meta({:literal, [subtype: :integer], value}, _metadata), do: {:ok, value}
    def from_meta(_other, _metadata), do: {:error, "unsupported node"}

    @impl true
    def unparse(value) when is_integer(value), do: {:ok, Integer.to_string(value)}
  end

  # A bare `Metastatic.Adapter` implementation with no Plugin macro, to prove
  # the registry can derive its language from the module name.
  defmodule BareAdapter do
    @moduledoc false
    @behaviour Metastatic.Adapter

    @impl true
    def parse(source), do: {:ok, String.trim(source)}
    @impl true
    def to_meta(text), do: {:ok, {:literal, [subtype: :string], text}, %{}}
    @impl true
    def from_meta({:literal, [subtype: :string], text}, _), do: {:ok, text}
    @impl true
    def unparse(text), do: {:ok, text}
    @impl true
    def file_extensions, do: [".barelang"]
  end

  setup do
    on_exit(fn ->
      for lang <- [:sample_lang, :bareadapter] do
        Languages.unregister(lang)
      end
    end)

    :ok
  end

  describe "the `use` macro" do
    test "injects the adapter behaviour" do
      assert Adapter.valid_adapter?(SampleAdapter)
    end

    test "injects file_extensions/0" do
      assert SampleAdapter.file_extensions() == [".sample", ".smp"]
    end

    test "exposes the descriptor" do
      assert %{
               language: :sample_lang,
               adapter: SampleAdapter,
               extensions: [".sample", ".smp"],
               experimental?: true,
               documentation?: false
             } = SampleAdapter.__metastatic_plugin__()

      assert SampleAdapter.__metastatic_language__() == :sample_lang
      assert SampleAdapter.__metastatic_plugin_opts__()[:extensions] == [".sample", ".smp"]
    end

    test "rejects a non-atom language at compile time" do
      assert_raise ArgumentError, ~r/:language to be an atom/, fn ->
        Code.compile_string("""
        defmodule BadLanguagePlugin do
          use Metastatic.Adapter.Plugin, language: "rust", extensions: [".rs"]
        end
        """)
      end
    end

    test "rejects non-dot-prefixed extensions at compile time" do
      assert_raise ArgumentError, ~r/dot-prefixed extensions/, fn ->
        Code.compile_string("""
        defmodule BadExtensionsPlugin do
          use Metastatic.Adapter.Plugin, language: :rust, extensions: ["rs"]
        end
        """)
      end
    end

    test "rejects an empty extension list at compile time" do
      assert_raise ArgumentError, ~r/non-empty list/, fn ->
        Code.compile_string("""
        defmodule EmptyExtensionsPlugin do
          use Metastatic.Adapter.Plugin, language: :rust, extensions: []
        end
        """)
      end
    end
  end

  describe "registration" do
    test "a plugin module registers under its declared language" do
      assert :ok = Languages.register(:sample_lang, SampleAdapter)

      assert Languages.supported?(:sample_lang)
      assert {:ok, SampleAdapter} = Languages.get_adapter(:sample_lang)
      assert {:ok, :sample_lang} = Languages.detect_language("x.sample")
      assert {:ok, :sample_lang} = Languages.detect_language("x.smp")
    end

    test "the descriptor flags are carried through" do
      :ok =
        Languages.register(
          :sample_lang,
          SampleAdapter,
          SampleAdapter.__metastatic_plugin_opts__()
        )

      assert Languages.experimental?(:sample_lang)
      refute Languages.documentation?(:sample_lang)
    end

    test "a bare adapter derives its language from the module name" do
      assert :ok = Languages.register(:bareadapter, BareAdapter)

      assert {:ok, :bareadapter} = Languages.detect_language("x.barelang")
    end
  end

  describe "the pipeline" do
    setup do
      :ok = Languages.register(:sample_lang, SampleAdapter)
      :ok
    end

    test "Metastatic.quote/2 parses through the plugin" do
      assert {:ok, {:literal, [subtype: :integer], 42}} = Metastatic.quote("42", :sample_lang)
    end

    test "Metastatic.unquote/2 generates through the plugin" do
      ast = {:literal, [subtype: :integer], 42}

      assert {:ok, "42"} = Metastatic.unquote(ast, :sample_lang)
    end

    test "Builder round-trips through the plugin" do
      assert {:ok, "7"} = Builder.round_trip("7", :sample_lang)
    end

    test "Builder.from_file/2 auto-detects the plugin's extension" do
      path =
        Path.join(System.tmp_dir!(), "plugin_demo_#{System.unique_integer([:positive])}.sample")

      File.write!(path, "123")
      on_exit(fn -> File.rm(path) end)

      assert {:ok, doc} = Builder.from_file(path)
      assert doc.language == :sample_lang
      assert doc.ast == {:literal, [subtype: :integer], 123}
    end

    test "a parse failure is reported, not raised" do
      assert {:error, _reason} = Metastatic.quote("not a number", :sample_lang)
    end

    test "the plugin appears in supported_languages/0 metadata" do
      info =
        Builder.supported_languages() |> Enum.find(fn lang -> lang.language == :sample_lang end)

      assert info.adapter == SampleAdapter
      assert info.extensions == [".sample", ".smp"]
      assert info.experimental == true
      assert info.loaded == true
    end
  end

  describe "child-spec :plugins option" do
    test "registers plugins at start" do
      # {System.unique_integer([:positive])}
      name = :plugin_registry_test_

      # Start a throwaway registry so the shared one is untouched. It seeds the
      # same store, so the plugin becomes visible globally.
      {:ok, pid} = Adapter.Registry.start_link(name: name, plugins: [SampleAdapter])

      try do
        assert Languages.supported?(:sample_lang)
        assert {:ok, :sample_lang} = Languages.detect_language("x.sample")
      after
        Languages.unregister(:sample_lang)
        GenServer.stop(pid)
      end
    end

    test "accepts {language, module} and {language, module, opts} entries" do
      # {System.unique_integer([:positive])}
      name = :plugin_registry_pair_

      {:ok, pid} =
        Adapter.Registry.start_link(
          name: name,
          plugins: [{:pair_lang, BareAdapter, extensions: [".pair"]}]
        )

      try do
        assert {:ok, :pair_lang} = Languages.detect_language("x.pair")
      after
        Languages.unregister(:pair_lang)
        GenServer.stop(pid)
      end
    end

    test "refuses to start with an invalid plugin" do
      # {System.unique_integer([:positive])}
      name = :plugin_registry_bad_

      # `start_link` links, so a failing init would exit this test process.
      # `start/3` is the non-linking form, which is what a supervisor uses.
      assert {:error, {:invalid_plugins, [error: {:bad_lang, String, :invalid_adapter}]}} =
               GenServer.start(Adapter.Registry, %{plugins: [{:bad_lang, String}]}, name: name)
    end
  end
end
