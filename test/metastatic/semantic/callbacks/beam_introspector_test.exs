defmodule Metastatic.Semantic.Callbacks.BeamIntrospectorTest do
  use ExUnit.Case, async: false

  alias Metastatic.Semantic.Callbacks
  alias Metastatic.Semantic.Callbacks.BeamIntrospector

  setup do
    Callbacks.clear()
    :ok
  end

  describe "discover_callbacks/1" do
    test "discovers GenServer callbacks" do
      assert {:ok, callbacks} = BeamIntrospector.discover_callbacks(GenServer)

      assert {:init, 1} in callbacks
      assert {:handle_call, 3} in callbacks
      assert {:handle_cast, 2} in callbacks
      assert {:handle_info, 2} in callbacks
      assert {:handle_continue, 2} in callbacks
      assert {:terminate, 2} in callbacks
      assert {:code_change, 3} in callbacks
    end

    test "discovers Supervisor callbacks" do
      assert {:ok, callbacks} = BeamIntrospector.discover_callbacks(Supervisor)
      assert {:init, 1} in callbacks
    end

    test "discovers Application callbacks" do
      assert {:ok, callbacks} = BeamIntrospector.discover_callbacks(Application)
      assert {:start, 2} in callbacks
      assert {:stop, 1} in callbacks
    end

    test "discovers Erlang :gen_statem callbacks" do
      assert {:ok, callbacks} = BeamIntrospector.discover_callbacks(:gen_statem)

      assert {:init, 1} in callbacks
      assert {:callback_mode, 0} in callbacks
    end

    test "discovers Erlang :gen_event callbacks" do
      assert {:ok, callbacks} = BeamIntrospector.discover_callbacks(:gen_event)
      assert {:init, 1} in callbacks
      assert {:handle_event, 2} in callbacks
    end

    test "returns :not_a_behaviour for non-behaviour modules" do
      assert {:error, :not_a_behaviour} = BeamIntrospector.discover_callbacks(String)
    end

    test "returns :not_loaded for non-existent modules" do
      assert {:error, :not_loaded} =
               BeamIntrospector.discover_callbacks(NonExistent.Module.That.Does.Not.Exist)
    end
  end

  describe "discover_and_register/2" do
    test "registers GenServer callbacks into the registry" do
      assert {:ok, count} =
               BeamIntrospector.discover_and_register(GenServer,
                 language: :elixir,
                 framework: :genserver
               )

      assert count >= 7

      assert {:ok, %{framework: :genserver}} =
               Callbacks.lookup(:elixir, "GenServer", "handle_call", 3)

      assert {:ok, %{framework: :genserver}} =
               Callbacks.lookup(:elixir, "GenServer", "init", 1)
    end

    test "registers Erlang gen_statem callbacks" do
      assert {:ok, count} =
               BeamIntrospector.discover_and_register(:gen_statem,
                 language: :erlang,
                 framework: :gen_statem
               )

      assert count >= 2

      assert {:ok, %{framework: :gen_statem}} =
               Callbacks.lookup(:erlang, "gen_statem", "init", 1)

      assert {:ok, %{framework: :gen_statem}} =
               Callbacks.lookup(:erlang, "gen_statem", "callback_mode", 0)
    end

    test "registers with domain when provided" do
      Callbacks.register(:elixir, "TestBehaviour", "run", 1, %{
        framework: :test,
        domain: :queue
      })

      assert {:ok, %{domain: :queue}} =
               Callbacks.lookup(:elixir, "TestBehaviour", "run", 1)
    end

    test "returns error for non-behaviour module" do
      assert {:error, :not_a_behaviour} =
               BeamIntrospector.discover_and_register(String,
                 language: :elixir,
                 framework: :string
               )
    end
  end

  describe "register_otp_behaviours/0" do
    test "registers all core OTP behaviours" do
      BeamIntrospector.register_otp_behaviours()

      # Elixir GenServer
      assert Callbacks.callback?(:elixir, "GenServer", "handle_call", 3)
      assert Callbacks.callback?(:elixir, "GenServer", "init", 1)

      # Elixir Supervisor
      assert Callbacks.callback?(:elixir, "Supervisor", "init", 1)

      # Elixir DynamicSupervisor
      assert Callbacks.callback?(:elixir, "DynamicSupervisor", "init", 1)

      # Elixir Application
      assert Callbacks.callback?(:elixir, "Application", "start", 2)
      assert Callbacks.callback?(:elixir, "Application", "stop", 1)

      # Erlang gen_statem
      assert Callbacks.callback?(:erlang, "gen_statem", "init", 1)
      assert Callbacks.callback?(:erlang, "gen_statem", "callback_mode", 0)

      # Erlang gen_event
      assert Callbacks.callback?(:erlang, "gen_event", "init", 1)
    end

    test "populates behaviours_for_language with auto-discovered modules" do
      BeamIntrospector.register_otp_behaviours()

      elixir_behaviours = Callbacks.behaviours_for_language(:elixir)
      assert "GenServer" in elixir_behaviours
      assert "Supervisor" in elixir_behaviours
      assert "DynamicSupervisor" in elixir_behaviours
      assert "Application" in elixir_behaviours

      erlang_behaviours = Callbacks.behaviours_for_language(:erlang)
      assert "gen_statem" in erlang_behaviours
      assert "gen_event" in erlang_behaviours
    end
  end

  describe "module_to_behaviour_name/1" do
    test "converts Elixir module to string without Elixir. prefix" do
      assert "GenServer" = BeamIntrospector.module_to_behaviour_name(GenServer)
      assert "Phoenix.LiveView" = BeamIntrospector.module_to_behaviour_name(Phoenix.LiveView)
    end

    test "converts Erlang module atom to string" do
      assert "gen_statem" = BeamIntrospector.module_to_behaviour_name(:gen_statem)
      assert "gen_event" = BeamIntrospector.module_to_behaviour_name(:gen_event)
    end
  end
end
