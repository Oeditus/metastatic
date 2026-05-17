defmodule Metastatic.Semantic.CallbacksTest do
  use ExUnit.Case, async: false

  alias Metastatic.Semantic.Callbacks

  # Reset to built-in state before each test
  setup do
    Callbacks.clear()
    Callbacks.register_builtins()
    :ok
  end

  describe "register/5 and lookup/4" do
    test "registers and looks up a custom callback" do
      Callbacks.register(:elixir, "MyBehaviour", "handle_event", 2, %{
        framework: :custom,
        domain: nil
      })

      assert {:ok, %{framework: :custom, domain: nil}} =
               Callbacks.lookup(:elixir, "MyBehaviour", "handle_event", 2)
    end

    test "returns :no_match for unregistered callback" do
      assert :no_match = Callbacks.lookup(:elixir, "Unknown", "foo", 0)
    end

    test "wildcard arity matches any arity" do
      Callbacks.register(:ruby, "TestBase", "execute", nil, %{
        framework: :test,
        domain: nil
      })

      assert {:ok, %{framework: :test}} = Callbacks.lookup(:ruby, "TestBase", "execute", 0)
      assert {:ok, %{framework: :test}} = Callbacks.lookup(:ruby, "TestBase", "execute", 3)
      assert {:ok, %{framework: :test}} = Callbacks.lookup(:ruby, "TestBase", "execute", nil)
    end

    test "exact arity takes precedence over wildcard" do
      Callbacks.register(:elixir, "Multi", "do_it", nil, %{framework: :generic, domain: nil})
      Callbacks.register(:elixir, "Multi", "do_it", 2, %{framework: :specific, domain: nil})

      assert {:ok, %{framework: :specific}} = Callbacks.lookup(:elixir, "Multi", "do_it", 2)
      assert {:ok, %{framework: :generic}} = Callbacks.lookup(:elixir, "Multi", "do_it", 5)
    end
  end

  describe "callback?/4" do
    test "returns true for known Elixir callbacks" do
      assert Callbacks.callback?(:elixir, "Oban.Worker", "perform", 1)
      assert Callbacks.callback?(:elixir, "GenServer", "handle_call", 3)
      assert Callbacks.callback?(:elixir, "GenServer", "init", 1)
      assert Callbacks.callback?(:elixir, "Phoenix.LiveView", "mount", 3)
      assert Callbacks.callback?(:elixir, "Plug", "call", 2)
      assert Callbacks.callback?(:elixir, "Broadway", "handle_message", 3)
    end

    test "returns false for wrong arity on exact-arity registrations" do
      refute Callbacks.callback?(:elixir, "Oban.Worker", "perform", 0)
      refute Callbacks.callback?(:elixir, "Oban.Worker", "perform", 2)
    end

    test "returns false for unknown function on known behaviour" do
      refute Callbacks.callback?(:elixir, "Oban.Worker", "run", 1)
      refute Callbacks.callback?(:elixir, "GenServer", "execute", 2)
    end

    test "returns true for known Ruby callbacks (wildcard arity)" do
      assert Callbacks.callback?(:ruby, "ActiveJob::Base", "perform", 0)
      assert Callbacks.callback?(:ruby, "ActiveJob::Base", "perform", 5)
      assert Callbacks.callback?(:ruby, "Sidekiq::Worker", "perform", 2)
    end

    test "returns true for known Python callbacks" do
      assert Callbacks.callback?(:python, "celery.Task", "run", 0)
      assert Callbacks.callback?(:python, "celery.Task", "run", 3)
    end
  end

  describe "behaviours_for_language/1" do
    test "returns all Elixir behaviours" do
      behaviours = Callbacks.behaviours_for_language(:elixir)

      assert "Oban.Worker" in behaviours
      assert "GenServer" in behaviours
      assert "Phoenix.LiveView" in behaviours
      assert "Plug" in behaviours
      assert "Broadway" in behaviours
      assert "Supervisor" in behaviours
      assert "Application" in behaviours
    end

    test "returns all Ruby behaviours" do
      behaviours = Callbacks.behaviours_for_language(:ruby)

      assert "ActiveJob::Base" in behaviours
      assert "Sidekiq::Worker" in behaviours
      assert "Sidekiq::Job" in behaviours
    end

    test "returns all Python behaviours" do
      behaviours = Callbacks.behaviours_for_language(:python)

      assert "celery.Task" in behaviours
      assert "View" in behaviours
    end

    test "returns empty list for unknown language" do
      assert [] = Callbacks.behaviours_for_language(:cobol)
    end
  end

  describe "clear/0" do
    test "removes all registrations" do
      Callbacks.clear()

      assert :no_match = Callbacks.lookup(:elixir, "Oban.Worker", "perform", 1)
      assert [] = Callbacks.behaviours_for_language(:elixir)
    end

    test "register_builtins restores after clear" do
      Callbacks.clear()
      Callbacks.register_builtins()

      assert {:ok, %{framework: :oban}} =
               Callbacks.lookup(:elixir, "Oban.Worker", "perform", 1)
    end
  end

  describe "built-in Elixir registrations" do
    test "Oban.Worker perform/1" do
      assert {:ok, %{framework: :oban, domain: :queue}} =
               Callbacks.lookup(:elixir, "Oban.Worker", "perform", 1)
    end

    test "GenServer callbacks" do
      assert {:ok, %{framework: :genserver}} =
               Callbacks.lookup(:elixir, "GenServer", "handle_call", 3)

      assert {:ok, %{framework: :genserver}} =
               Callbacks.lookup(:elixir, "GenServer", "handle_cast", 2)

      assert {:ok, %{framework: :genserver}} =
               Callbacks.lookup(:elixir, "GenServer", "handle_info", 2)

      assert {:ok, %{framework: :genserver}} =
               Callbacks.lookup(:elixir, "GenServer", "terminate", 2)
    end

    test "Phoenix.LiveView callbacks" do
      assert {:ok, %{framework: :phoenix}} =
               Callbacks.lookup(:elixir, "Phoenix.LiveView", "mount", 3)

      assert {:ok, %{framework: :phoenix}} =
               Callbacks.lookup(:elixir, "Phoenix.LiveView", "handle_event", 3)

      assert {:ok, %{framework: :phoenix}} =
               Callbacks.lookup(:elixir, "Phoenix.LiveView", "render", 1)
    end

    test "Plug callbacks" do
      assert {:ok, %{framework: :plug}} = Callbacks.lookup(:elixir, "Plug", "init", 1)
      assert {:ok, %{framework: :plug}} = Callbacks.lookup(:elixir, "Plug", "call", 2)
    end

    test "Ecto.Migration callbacks" do
      assert {:ok, %{framework: :ecto, domain: :db}} =
               Callbacks.lookup(:elixir, "Ecto.Migration", "change", 0)

      assert {:ok, %{framework: :ecto, domain: :db}} =
               Callbacks.lookup(:elixir, "Ecto.Migration", "up", 0)
    end
  end

  describe "built-in Ruby registrations" do
    test "ActiveJob::Base perform" do
      assert {:ok, %{framework: :activejob, domain: :queue}} =
               Callbacks.lookup(:ruby, "ActiveJob::Base", "perform", 2)
    end

    test "Sidekiq::Worker perform" do
      assert {:ok, %{framework: :sidekiq, domain: :queue}} =
               Callbacks.lookup(:ruby, "Sidekiq::Worker", "perform", 1)
    end

    test "Rails controller actions" do
      for action <- ~w[index show create update destroy] do
        assert {:ok, %{framework: :rails, domain: :http}} =
                 Callbacks.lookup(:ruby, "ApplicationController", action, nil)
      end
    end
  end

  describe "built-in Python registrations" do
    test "Celery task run" do
      assert {:ok, %{framework: :celery, domain: :queue}} =
               Callbacks.lookup(:python, "celery.Task", "run", 0)
    end

    test "Django view methods" do
      assert {:ok, %{framework: :django, domain: :http}} =
               Callbacks.lookup(:python, "View", "get", 1)

      assert {:ok, %{framework: :django, domain: :http}} =
               Callbacks.lookup(:python, "View", "post", 2)
    end
  end
end
