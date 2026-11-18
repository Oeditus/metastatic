defmodule Metastatic.SemanticTest do
  @moduledoc """
  Tests for deterministic semantic-table registration.

  The failure this module guards against is silent: if the pattern tables are
  empty, `Enricher.enrich_tree/2` returns the tree unannotated and no error is
  raised anywhere. These tests assert the tables are actually populated after
  `ensure_registered/0`, including after the `clear_all/0` that the test suite
  performs.
  """

  # `async: false` because these tests mutate global `:persistent_term` state
  # shared with every other semantic test.
  use ExUnit.Case, async: false

  alias Metastatic.Semantic
  alias Metastatic.Semantic.{Callbacks, Patterns}

  describe "ensure_registered/0" do
    setup do
      # Restore global state for the rest of the suite regardless of outcome.
      on_exit(fn -> Semantic.ensure_registered() end)
      :ok
    end

    test "populates the pattern tables after clear_all/0" do
      Patterns.clear_all()
      assert Patterns.get_patterns(:db, :elixir) == []

      assert :ok = Semantic.ensure_registered()

      refute Patterns.get_patterns(:db, :elixir) == []
      refute Patterns.get_patterns(:db, :python) == []
    end

    test "populates the callback table after clear/0" do
      Callbacks.clear()
      refute Callbacks.callback?(:elixir, "Oban.Worker", "perform", 1)

      assert :ok = Semantic.ensure_registered()

      assert Callbacks.callback?(:elixir, "Oban.Worker", "perform", 1)
    end

    test "is idempotent — repeated calls do not duplicate patterns" do
      Patterns.clear_all()
      Semantic.ensure_registered()
      first = Patterns.get_patterns(:db, :elixir)

      Semantic.ensure_registered()
      Semantic.ensure_registered()

      assert Patterns.get_patterns(:db, :elixir) == first
    end

    test "is idempotent for callbacks" do
      Callbacks.clear()
      Semantic.ensure_registered()
      first = Callbacks.behaviours_for_language(:elixir)

      Semantic.ensure_registered()

      assert Callbacks.behaviours_for_language(:elixir) == first
    end
  end

  describe "provider discovery" do
    test "lists every built-in pattern provider" do
      providers = Semantic.builtin_pattern_providers()

      assert Metastatic.Semantic.Domains.Database in providers
      assert Metastatic.Semantic.Domains.Auth in providers
      assert Metastatic.Semantic.Domains.Http in providers
      assert Metastatic.Semantic.Domains.Cache in providers
      assert Metastatic.Semantic.Domains.Queue in providers
      assert Metastatic.Semantic.Domains.File in providers
      assert Metastatic.Semantic.Domains.ExternalApi in providers
    end

    test "every built-in provider exports register_all/0" do
      for provider <- Semantic.builtin_pattern_providers() do
        assert function_exported?(provider, :register_all, 0),
               "#{inspect(provider)} does not export register_all/0"
      end
    end

    test "configured providers default to an empty list" do
      assert Semantic.configured_pattern_providers() == []
      assert Semantic.configured_callback_providers() == []
    end
  end

  describe "configured providers" do
    defmodule GoodProvider do
      @moduledoc false
      def register_all do
        Metastatic.Semantic.Patterns.register(:db, :testlang, [
          {"TestRepo.get", %{operation: :retrieve, framework: :test, extract_target: :first_arg}}
        ])
      end
    end

    defmodule ExplodingProvider do
      @moduledoc false
      def register_all, do: raise("provider is broken")
    end

    defmodule NotAProvider do
      @moduledoc false
      def something_else, do: :ok
    end

    setup do
      previous = Application.get_env(:metastatic, :semantic)
      on_exit(fn -> Application.put_env(:metastatic, :semantic, previous) end)
      :ok
    end

    test "registers patterns from a configured host provider" do
      Application.put_env(:metastatic, :semantic, pattern_providers: [GoodProvider])

      assert GoodProvider in Semantic.configured_pattern_providers()
      assert :ok = Semantic.ensure_registered()

      assert [{"TestRepo.get", _spec}] = Patterns.get_patterns(:db, :testlang)
    end

    test "a raising provider does not break registration" do
      Application.put_env(:metastatic, :semantic, pattern_providers: [ExplodingProvider])

      assert :ok = Semantic.ensure_registered()

      # Built-ins still registered despite the broken provider.
      refute Patterns.get_patterns(:db, :elixir) == []
    end

    test "a module without register_all/0 is skipped" do
      Application.put_env(:metastatic, :semantic, pattern_providers: [NotAProvider])

      assert :ok = Semantic.ensure_registered()
      refute Patterns.get_patterns(:db, :elixir) == []
    end
  end

  describe "Patterns.register/3 idempotence" do
    setup do
      Patterns.clear_all()
      on_exit(fn -> Semantic.ensure_registered() end)
      :ok
    end

    test "registering the same list twice does not duplicate" do
      patterns = [{"A.b", %{operation: :retrieve, framework: :f, extract_target: :none}}]

      Patterns.register(:db, :idem, patterns)
      Patterns.register(:db, :idem, patterns)

      assert Patterns.get_patterns(:db, :idem) == patterns
    end

    test "an overlapping registration keeps the first spec for a key" do
      Patterns.register(:db, :idem, [
        {"A.b", %{operation: :retrieve, framework: :first, extract_target: :none}}
      ])

      Patterns.register(:db, :idem, [
        {"A.b", %{operation: :create, framework: :second, extract_target: :none}},
        {"A.c", %{operation: :create, framework: :second, extract_target: :none}}
      ])

      patterns = Patterns.get_patterns(:db, :idem)

      assert [{"A.b", first}, {"A.c", _}] = patterns
      assert first.framework == :first
    end

    test "preserves registration order" do
      Patterns.register(:db, :idem, [{"A.1", %{operation: :retrieve, framework: :f}}])
      Patterns.register(:db, :idem, [{"A.2", %{operation: :retrieve, framework: :f}}])

      assert [{"A.1", _}, {"A.2", _}] = Patterns.get_patterns(:db, :idem)
    end
  end
end
