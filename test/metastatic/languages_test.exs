defmodule Metastatic.LanguagesTest do
  @moduledoc """
  Tests for the hybrid language registry.

  These lock in two contracts:

    1. **Built-in discovery** — every adapter module under
       `lib/metastatic/adapters/` that declares `@behaviour Metastatic.Adapter`
       is seeded automatically, NL-only adapters are excluded, and the derived
       lookups (extensions, adapters) agree with the descriptor list.

    2. **Runtime extension** — a language registered at runtime is visible to
       every query immediately, without recompiling Metastatic. This is the
       property that makes third-party adapters possible.

  `async: false` because the runtime-registration tests mutate the shared
  `Metastatic.Languages.Store` ETS tables.
  """

  use ExUnit.Case, async: false

  alias Metastatic.{Language, Languages}
  alias Metastatic.Languages.{Builtin, Discovery, Store}

  describe "built-in discovery" do
    test "registers every source-language adapter" do
      # These are the adapters that exist in lib/metastatic/adapters/ and are
      # source languages (not NL prose adapters).
      expected = [
        :agda,
        :cure,
        :elixir,
        :erlang,
        :gleam,
        :go,
        :haskell,
        :java,
        :javascript,
        :lfe,
        :march,
        :markdown,
        :python,
        :ruby,
        :rust,
        :sql,
        :typescript
      ]

      assert Builtin.languages() == expected
    end

    test "the live registry starts as exactly the built-ins" do
      assert Languages.supported_languages() == Builtin.languages()
    end

    test "excludes NL-only adapters (english, spanish)" do
      refute Languages.supported?(:english)
      refute Languages.supported?(:spanish)
    end

    test "derives language atoms by downcasing the module name" do
      # JavaScript -> :javascript (not :java_script), SQL -> :sql
      assert Languages.supported?(:javascript)
      assert Languages.supported?(:typescript)
      assert Languages.supported?(:sql)
    end

    test "every discovered language has a valid adapter module" do
      for lang <- Languages.supported_languages() do
        assert {:ok, adapter} = Languages.get_adapter(lang)
        assert Code.ensure_loaded?(adapter), "#{inspect(adapter)} is not loadable"
      end
    end

    test "tracks adapter sources for incremental recompilation" do
      # `@external_resource` now lives on `Builtin`, which is the module that
      # owns the compile-time scan. Paths are normalised because the attribute
      # records them relative to `__DIR__` (`languages/../adapters/x.ex`).
      resources =
        Builtin.__info__(:attributes)
        |> Keyword.get_values(:external_resource)
        |> Enum.map(fn [path] -> Path.expand(path) end)

      for {_language, adapter} <- Discovery.discover() do
        source = adapter.module_info(:compile)[:source] |> List.to_string()
        assert Path.expand(source) in resources
      end

      refute Builtin.__mix_recompile__?()
    end

    test "all/0 returns descriptors matching supported_languages/0" do
      assert Enum.map(Languages.all(), & &1.language) == Languages.supported_languages()
      assert Enum.all?(Languages.all(), &match?(%Language{}, &1))
    end
  end

  describe "extension derivation" do
    test "extension map round-trips through detect_language/1" do
      for lang <- Languages.supported_languages(),
          {:ok, adapter} = Languages.get_adapter(lang),
          ext <- adapter.file_extensions() do
        assert {:ok, ^lang} = Languages.detect_language("sample" <> ext)
      end
    end

    test "supported_extensions/0 covers every adapter extension" do
      for lang <- Languages.supported_languages(),
          {:ok, adapter} = Languages.get_adapter(lang),
          ext <- adapter.file_extensions() do
        assert ext in Languages.supported_extensions()
      end
    end

    test "extension_for_language/1 returns the primary extension" do
      assert {:ok, ".py"} = Languages.extension_for_language(:python)
      assert {:error, _} = Languages.extension_for_language(:brainfuck)
    end
  end

  describe "flags" do
    test "experimental languages are flagged" do
      assert Languages.experimental?(:agda)
      assert Languages.experimental?(:haskell)
      refute Languages.experimental?(:python)
    end

    test "documentation languages are flagged" do
      assert Languages.documentation?(:markdown)
      refute Languages.documentation?(:elixir)
      assert :markdown in Languages.documentation_languages()
    end
  end

  describe "lookup" do
    test "get/1 returns the descriptor or nil" do
      assert %Language{language: :python, adapter: Metastatic.Adapters.Python} =
               Languages.get(:python)

      assert Languages.get(:brainfuck) == nil
    end

    test "get_adapter/1 returns ok/error" do
      assert {:ok, Metastatic.Adapters.Python} = Languages.get_adapter(:python)
      assert {:error, msg} = Languages.get_adapter(:brainfuck)
      assert msg =~ "Unsupported language"
    end

    test "adapters/0 returns a language => module map" do
      adapters = Languages.adapters()
      assert adapters[:python] == Metastatic.Adapters.Python
      assert map_size(adapters) == length(Languages.supported_languages())
    end
  end

  describe "parse_language/1" do
    test "parses supported languages case-insensitively" do
      assert {:ok, :python} = Languages.parse_language("python")
      assert {:ok, :ruby} = Languages.parse_language("Ruby")
    end

    test "returns :none for nil" do
      assert Languages.parse_language(nil) == :none
    end

    test "returns error for unknown languages" do
      assert {:error, msg} = Languages.parse_language("brainfuck")
      assert msg =~ "Invalid language"
    end

    test "resolves a runtime-registered language by name" do
      # `String.to_existing_atom/1` would fail here because the atom is created
      # after `Languages` was loaded, so the lookup is by name.
      :ok = Languages.register(:parse_demo, Metastatic.Adapters.Elixir, extensions: [".pd"])
      on_exit(fn -> Languages.unregister(:parse_demo) end)

      assert {:ok, :parse_demo} = Languages.parse_language("parse_demo")
      assert {:ok, :parse_demo} = Languages.parse_language("PARSE_DEMO")
    end
  end

  describe "runtime registration (third-party plug-ins)" do
    setup do
      on_exit(fn ->
        for lang <- Languages.supported_languages(),
            not Enum.any?(Builtin.languages(), &(&1 == lang)) do
          Languages.unregister(lang)
        end
      end)

      :ok
    end

    test "a registered language is visible to every query immediately" do
      refute Languages.supported?(:pluglang)

      assert :ok =
               Languages.register(:pluglang, Metastatic.Adapters.Elixir, extensions: [".plug"])

      assert Languages.supported?(:pluglang)
      assert :pluglang in Languages.supported_languages()
      assert {:ok, Metastatic.Adapters.Elixir} = Languages.get_adapter(:pluglang)
      assert {:ok, :pluglang} = Languages.detect_language("example.plug")
      assert {:ok, ".plug"} = Languages.extension_for_language(:pluglang)
      assert ".plug" in Languages.supported_extensions()
      assert Languages.adapters()[:pluglang] == Metastatic.Adapters.Elixir
      assert %Language{language: :pluglang} = Languages.get(:pluglang)
    end

    test "registering does not disturb the built-ins" do
      before = Languages.supported_languages()
      :ok = Languages.register(:pluglang, Metastatic.Adapters.Elixir, extensions: [".plug"])

      for lang <- before do
        assert Languages.supported?(lang)
      end

      assert {:ok, Metastatic.Adapters.Python} = Languages.get_adapter(:python)
    end

    test "the language appears in the supported-languages error message" do
      :ok = Languages.register(:pluglang, Metastatic.Adapters.Elixir, extensions: [".plug"])

      assert {:error, message} = Languages.get_adapter(:nope)
      assert message =~ "pluglang"
    end

    test "flags are honoured" do
      :ok =
        Languages.register(:pluglang, Metastatic.Adapters.Elixir,
          extensions: [".plug"],
          experimental?: true,
          documentation?: true
        )

      assert Languages.experimental?(:pluglang)
      assert Languages.documentation?(:pluglang)
      assert :pluglang in Languages.experimental_languages()
      assert :pluglang in Languages.documentation_languages()
    end

    test "refuses to shadow a built-in language" do
      assert {:error, {:already_registered, :python, Metastatic.Adapters.Python}} =
               Languages.register(:python, Metastatic.Adapters.Elixir)
    end

    test "refuses an invalid adapter" do
      assert {:error, :invalid_adapter} = Languages.register(:pluglang, String)
      refute Languages.supported?(:pluglang)
    end

    test "unregister removes the language and its extensions" do
      :ok = Languages.register(:pluglang, Metastatic.Adapters.Elixir, extensions: [".plug"])
      assert {:ok, :pluglang} = Languages.detect_language("x.plug")

      assert :ok = Languages.unregister(:pluglang)

      refute Languages.supported?(:pluglang)
      assert {:error, _} = Languages.detect_language("x.plug")
      refute ".plug" in Languages.supported_extensions()
    end

    test "unregister refuses built-ins" do
      assert {:error, :builtin} = Languages.unregister(:python)
      assert Languages.supported?(:python)
    end
  end

  describe "Store" do
    test "delete only removes extensions still owned by the language" do
      :ok = Languages.register(:shared_a, Metastatic.Adapters.Elixir, extensions: [".shared"])
      :ok = Languages.register(:shared_b, Metastatic.Adapters.Elixir, extensions: [".shared"])

      # `:shared_b` won the extension; deleting `:shared_a` must not clear it.
      assert {:ok, :shared_b} = Store.detect(".shared")
      assert :ok = Languages.unregister(:shared_a)
      assert {:ok, :shared_b} = Store.detect(".shared")

      assert :ok = Languages.unregister(:shared_b)
      assert :error = Store.detect(".shared")
    end

    test "builtin/0 ignores runtime registrations" do
      :ok = Languages.register(:pluglang, Metastatic.Adapters.Elixir, extensions: [".plug"])
      on_exit(fn -> Languages.unregister(:pluglang) end)

      refute Enum.any?(Languages.builtin(), &(&1.language == :pluglang))
      assert Languages.supported?(:pluglang)
    end
  end
end
