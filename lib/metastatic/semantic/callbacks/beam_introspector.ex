defmodule Metastatic.Semantic.Callbacks.BeamIntrospector do
  @moduledoc """
  Discovers behaviour callbacks from compiled BEAM modules.

  Uses `behaviour_info(:callbacks)` at runtime to extract the list of
  callback functions defined by a behaviour module. This works for all
  OTP behaviours and any Elixir/Erlang module that defines `@callback`
  attributes, as long as the module is compiled and loaded.

  This module is used exclusively by the Elixir and Erlang adapters.

  ## Examples

      iex> {:ok, callbacks} = BeamIntrospector.discover_callbacks(GenServer)
      iex> {:handle_call, 3} in callbacks
      true

      iex> BeamIntrospector.discover_callbacks(NonExistentModule)
      {:error, :not_loaded}
  """

  alias Metastatic.Semantic.Callbacks

  @typedoc "A callback definition: `{function_name, arity}`"
  @type callback_def :: {atom(), non_neg_integer()}

  @typedoc "Options for `discover_and_register/2`"
  @type register_opts :: [
          language: :elixir | :erlang,
          framework: atom(),
          domain: atom() | nil
        ]

  @doc """
  Discovers all callbacks defined by a behaviour module.

  Calls `module.behaviour_info(:callbacks)` to retrieve the list of
  `{function_name, arity}` pairs. Returns `{:error, :not_loaded}` if
  the module is not available, or `{:error, :not_a_behaviour}` if it
  does not export `behaviour_info/1`.

  ## Examples

      iex> {:ok, callbacks} = BeamIntrospector.discover_callbacks(GenServer)
      iex> {:init, 1} in callbacks
      true

      iex> BeamIntrospector.discover_callbacks(String)
      {:error, :not_a_behaviour}
  """
  @spec discover_callbacks(module()) :: {:ok, [callback_def()]} | {:error, atom()}
  def discover_callbacks(module) when is_atom(module) do
    if Code.ensure_loaded?(module) do
      if function_exported?(module, :behaviour_info, 1) do
        callbacks = module.behaviour_info(:callbacks)
        {:ok, callbacks}
      else
        {:error, :not_a_behaviour}
      end
    else
      {:error, :not_loaded}
    end
  end

  @doc """
  Discovers callbacks for a module and registers them in the
  `Semantic.Callbacks` registry.

  Accepts a module atom and options specifying language, framework name,
  and optional domain. Both Elixir module names (`GenServer`) and bare
  Erlang module atoms (`:gen_statem`) are supported.

  ## Options

  - `:language` - `:elixir` or `:erlang` (required)
  - `:framework` - framework atom for the callback spec (required)
  - `:domain` - domain atom or `nil` (default: `nil`)

  Returns `{:ok, count}` with the number of callbacks registered, or
  an error tuple if the module could not be introspected.

  ## Examples

      iex> {:ok, count} = BeamIntrospector.discover_and_register(GenServer, language: :elixir, framework: :genserver)
      iex> count >= 7
      true
  """
  @spec discover_and_register(module(), register_opts()) ::
          {:ok, non_neg_integer()} | {:error, atom()}
  def discover_and_register(module, opts) when is_atom(module) and is_list(opts) do
    language = Keyword.fetch!(opts, :language)
    framework = Keyword.fetch!(opts, :framework)
    domain = Keyword.get(opts, :domain)

    behaviour_name = module_to_behaviour_name(module)
    spec = %{framework: framework, domain: domain}

    case discover_callbacks(module) do
      {:ok, callbacks} ->
        for {func, arity} <- callbacks do
          Callbacks.register(language, behaviour_name, Atom.to_string(func), arity, spec)
        end

        {:ok, length(callbacks)}

      error ->
        error
    end
  end

  @doc """
  Registers all known OTP behaviours from the Erlang/OTP and Elixir
  standard library.

  Discovers callbacks at runtime rather than hardcoding them, ensuring
  the registry stays in sync with the installed OTP/Elixir version.

  Modules that are not available (e.g., optional applications) are
  silently skipped.
  """
  @spec register_otp_behaviours() :: :ok
  def register_otp_behaviours do
    # Elixir wrappers for OTP behaviours
    elixir_behaviours = [
      {GenServer, :genserver, nil},
      {Supervisor, :supervisor, nil},
      {DynamicSupervisor, :dynamic_supervisor, nil},
      {Application, :application, nil},
      {Task, :task, nil}
    ]

    for {module, framework, domain} <- elixir_behaviours do
      discover_and_register(module,
        language: :elixir,
        framework: framework,
        domain: domain
      )
    end

    # Raw Erlang OTP behaviours
    erlang_behaviours = [
      {:gen_server, :gen_server, nil},
      {:gen_statem, :gen_statem, nil},
      {:gen_event, :gen_event, nil},
      {:supervisor, :supervisor, nil}
    ]

    for {module, framework, domain} <- erlang_behaviours do
      discover_and_register(module,
        language: :erlang,
        framework: framework,
        domain: domain
      )
    end

    # Optional Elixir ecosystem behaviours (may not be compiled)
    optional_behaviours = [
      {Phoenix.Channel, :elixir, :phoenix, nil},
      {Phoenix.Presence, :elixir, :phoenix, nil},
      {Phoenix.Socket, :elixir, :phoenix, nil},
      {Plug.Conn.Adapter, :elixir, :plug, nil}
    ]

    for {module, language, framework, domain} <- optional_behaviours do
      discover_and_register(module,
        language: language,
        framework: framework,
        domain: domain
      )
    end

    :ok
  end

  # Converts a module atom to the string form used as the behaviour key
  # in the Callbacks registry.
  # Elixir modules: `GenServer` -> "GenServer"
  # Erlang modules: `:gen_statem` -> "gen_statem"
  @doc false
  @spec module_to_behaviour_name(module()) :: String.t()
  def module_to_behaviour_name(module) when is_atom(module) do
    name = Atom.to_string(module)

    if String.starts_with?(name, "Elixir.") do
      String.replace_leading(name, "Elixir.", "")
    else
      name
    end
  end
end
