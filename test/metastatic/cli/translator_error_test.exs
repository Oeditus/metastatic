defmodule Metastatic.CLI.TranslatorErrorTest do
  @moduledoc """
  Phase-2 item 9: `Translator` reports a missing file extension as an error
  tuple instead of raising.

  `extension_for_language/1` used to `raise "No extension known for language:
  ..."`, which is reachable from `translate_directory/4` for any language whose
  adapter declares no extension. Every other lookup in the library returns
  `{:error, reason}`; this one now does too.
  """

  use ExUnit.Case, async: true

  alias Metastatic.CLI.Translator

  @tmp Path.join(System.tmp_dir!(), "metastatic_translator_error_test")

  setup do
    File.mkdir_p!(@tmp)
    on_exit(fn -> File.rm_rf!(@tmp) end)
    :ok
  end

  test "translate_with_auto_output returns an error tuple for a language with no extension" do
    path = Path.join(@tmp, "hello.ex")
    File.write!(path, "x = 1")

    assert {:error, reason} =
             Translator.translate_with_auto_output(path, :elixir, :not_a_language)

    assert reason =~ "No file extension known"
  end

  test "translate_directory returns an error tuple for a source language with no extension" do
    assert {:error, reason} =
             Translator.translate_directory(@tmp, :not_a_language, :elixir, @tmp)

    assert reason =~ "No file extension known"
  end

  test "translate_directory returns an error tuple for a target language with no extension" do
    File.write!(Path.join(@tmp, "a.ex"), "x = 1")

    assert {:error, reason} =
             Translator.translate_directory(@tmp, :elixir, :not_a_language, @tmp)

    assert reason =~ "No file extension known"
  end

  test "does not raise for a missing source directory" do
    assert {:error, reason} =
             Translator.translate_directory("/nonexistent/dir", :elixir, :python, @tmp)

    assert reason =~ "No source files found"
  end
end
