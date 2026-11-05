defmodule Metastatic.LanguagesTest do
  @moduledoc """
  Tests for the plug-in language registry.

  These lock in the discovery contract: every adapter module under
  `lib/metastatic/adapters/` that declares `@behaviour Metastatic.Adapter` is
  registered automatically, NL-only adapters are excluded, and the derived
  maps (extensions, adapters) agree with the descriptor list.
  """

  use ExUnit.Case, async: true

  alias Metastatic.{Language, Languages}

  describe "discovery" do
    test "registers every source-language adapter" do
      # These are the adapters that exist in lib/metastatic/adapters/ and are
      # source languages (not NL prose adapters).
      expected = [
        :agda,
        :cure,
        :elixir,
        :erlang,
        :haskell,
        :javascript,
        :march,
        :markdown,
        :python,
        :ruby,
        :sql,
        :typescript
      ]

      assert Languages.supported_languages() == expected
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
  end
end
