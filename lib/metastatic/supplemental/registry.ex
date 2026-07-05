defmodule Metastatic.Supplemental.Registry do
  @moduledoc """
  Registry for supplemental modules.

  Manages registration and lookup of supplemental modules that extend
  language adapter capabilities. Runs as a GenServer under the application
  supervision tree.

  ## Usage

      # Register a supplemental module
      Registry.register(MyApp.Supplemental.Python.Pykka)

      # Look up by language
      Registry.list_for_language(:python)

      # Look up by construct
      Registry.get_for_construct(:python, :actor_call)

      # List all available constructs for a language
      Registry.available_constructs(:python)

  ## Configuration

  Auto-register supplementals at application startup:

      # config/config.exs
      config :metastatic, :supplementals,
        auto_register: [Metastatic.Supplemental.Python.Pykka],
        disabled: [:some_supplemental]
  """

  use GenServer

  alias Metastatic.Supplemental.{Error.ConflictError, Info}

  require Logger

  @type construct_key :: {language :: atom(), construct :: atom()}
  @type registry_state :: %{
          by_construct: %{construct_key() => module()},
          by_language: %{atom() => [module()]},
          all: MapSet.t(module())
        }

  # Client API

  @doc """
  Starts the registry GenServer.

  Called automatically by the application supervision tree.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Registers a supplemental module.

  The module must implement the `Metastatic.Supplemental` behaviour.
  Validates that no conflicts exist (another supplemental already handles
  the same constructs for the same language).

  ## Examples

      iex> Registry.register(MyApp.Supplemental.Python.Pykka)
      :ok

      iex> Registry.register(ConflictingModule)
      {:error, %ConflictError{}}
  """
  @spec register(module()) :: :ok | {:error, Exception.t()}
  def register(module) do
    GenServer.call(__MODULE__, {:register, module})
  end

  @doc """
  Unregisters a supplemental module.

  Removes the module from the registry.

  ## Examples

      iex> Registry.unregister(MyApp.Supplemental.Python.Pykka)
      :ok
  """
  @spec unregister(module()) :: :ok
  def unregister(module) do
    GenServer.call(__MODULE__, {:unregister, module})
  end

  @doc """
  Lists all supplemental modules registered for a language.

  ## Examples

      iex> Registry.list_for_language(:python)
      [MyApp.Supplemental.Python.Pykka, MyApp.Supplemental.Python.Asyncio]
  """
  @spec list_for_language(atom()) :: [module()]
  def list_for_language(language) do
    GenServer.call(__MODULE__, {:list_for_language, language})
  end

  @doc """
  Gets the supplemental module that handles a specific construct for a language.

  Returns `nil` if no supplemental is registered.

  ## Examples

      iex> Registry.get_for_construct(:python, :actor_call)
      MyApp.Supplemental.Python.Pykka

      iex> Registry.get_for_construct(:python, :unsupported_construct)
      nil
  """
  @spec get_for_construct(atom(), atom()) :: module() | nil
  def get_for_construct(language, construct) do
    GenServer.call(__MODULE__, {:get_for_construct, language, construct})
  end

  @doc """
  Lists all constructs that have supplemental support for a language.

  ## Examples

      iex> Registry.available_constructs(:python)
      [:actor_call, :actor_cast, :spawn_actor]
  """
  @spec available_constructs(atom()) :: [atom()]
  def available_constructs(language) do
    GenServer.call(__MODULE__, {:available_constructs, language})
  end

  @doc """
  Lists all registered supplemental modules.

  ## Examples

      iex> Registry.list_all()
      [MyApp.Supplemental.Python.Pykka]
  """
  @spec list_all() :: [module()]
  def list_all do
    GenServer.call(__MODULE__, :list_all)
  end

  @doc """
  Clears all registered supplementals.

  Primarily for testing purposes.
  """
  @spec clear() :: :ok
  def clear do
    GenServer.call(__MODULE__, :clear)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    state = %{
      by_construct: %{},
      by_language: %{},
      all: MapSet.new()
    }

    # Auto-register configured supplementals
    auto_register_from_config()

    {:ok, state}
  end

  @impl true
  def handle_call({:register, module}, _from, state) do
    case validate_and_register(module, state) do
      {:ok, new_state} ->
        Logger.debug("Registered supplemental: #{inspect(module)}")
        {:reply, :ok, new_state}

      {:error, error} ->
        {:reply, {:error, error}, state}
    end
  end

  @impl true
  def handle_call({:unregister, module}, _from, state) do
    new_state = do_unregister(module, state)
    Logger.debug("Unregistered supplemental: #{inspect(module)}")
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:list_for_language, language}, _from, state) do
    modules = Map.get(state.by_language, language, [])
    {:reply, modules, state}
  end

  @impl true
  def handle_call({:get_for_construct, language, construct}, _from, state) do
    key = {language, construct}
    module = Map.get(state.by_construct, key)
    {:reply, module, state}
  end

  @impl true
  def handle_call({:available_constructs, language}, _from, state) do
    constructs =
      state.by_construct
      |> Enum.filter(fn {{lang, _construct}, _module} -> lang == language end)
      |> Enum.map(fn {{_lang, construct}, _module} -> construct end)
      |> Enum.sort()

    {:reply, constructs, state}
  end

  @impl true
  def handle_call(:list_all, _from, state) do
    modules = MapSet.to_list(state.all)
    {:reply, modules, state}
  end

  @impl true
  def handle_call(:clear, _from, _state) do
    new_state = %{
      by_construct: %{},
      by_language: %{},
      all: MapSet.new()
    }

    {:reply, :ok, new_state}
  end

  # Private Functions

  defp validate_and_register(module, state) do
    with :ok <- validate_behaviour(module),
         :ok <- validate_info(module),
         :ok <- validate_no_conflicts(module, state) do
      {:ok, do_register(module, state)}
    end
  end

  defp validate_behaviour(module) do
    if function_exported?(module, :info, 0) and function_exported?(module, :transform, 3) do
      :ok
    else
      {:error, "Module #{inspect(module)} does not implement Supplemental behaviour"}
    end
  end

  defp validate_info(module) do
    info = module.info()

    if Info.valid?(info) do
      :ok
    else
      {:error, "Module #{inspect(module)} has invalid info"}
    end
  end

  defp validate_no_conflicts(module, state) do
    info = module.info()
    language = info.language

    conflicts =
      Enum.reduce_while(info.constructs, [], fn construct, acc ->
        key = {language, construct}

        case Map.get(state.by_construct, key) do
          nil ->
            {:cont, acc}

          existing_module ->
            {:halt, [{construct, existing_module} | acc]}
        end
      end)

    case conflicts do
      [] ->
        :ok

      [{construct, existing_module} | _] ->
        error =
          ConflictError.exception(
            construct: construct,
            language: language,
            modules: [existing_module, module]
          )

        {:error, error}
    end
  end

  defp do_register(module, state) do
    info = module.info()
    language = info.language

    # Update by_construct index
    by_construct =
      Enum.reduce(info.constructs, state.by_construct, fn construct, acc ->
        Map.put(acc, {language, construct}, module)
      end)

    # Update by_language index
    by_language =
      Map.update(state.by_language, language, [module], fn modules ->
        [module | modules] |> Enum.uniq()
      end)

    # Update all set
    all = MapSet.put(state.all, module)

    %{state | by_construct: by_construct, by_language: by_language, all: all}
  end

  defp do_unregister(module, state) do
    if MapSet.member?(state.all, module) do
      info = module.info()
      language = info.language

      # Remove from by_construct index
      by_construct =
        Enum.reduce(info.constructs, state.by_construct, fn construct, acc ->
          Map.delete(acc, {language, construct})
        end)

      # Remove from by_language index
      by_language =
        Map.update(state.by_language, language, [], fn modules ->
          List.delete(modules, module)
        end)

      # Remove from all set
      all = MapSet.delete(state.all, module)

      %{state | by_construct: by_construct, by_language: by_language, all: all}
    else
      state
    end
  end

  defp auto_register_from_config do
    config = Application.get_env(:metastatic, :supplementals, [])
    auto_register = Keyword.get(config, :auto_register, [])
    disabled = Keyword.get(config, :disabled, [])

    Enum.each(auto_register, fn module ->
      info = module.info()

      unless info.name in disabled do
        case register(module) do
          :ok ->
            Logger.info("Auto-registered supplemental: #{inspect(module)}")

          {:error, error} ->
            Logger.warning("Failed to auto-register #{inspect(module)}: #{inspect(error)}")
        end
      end
    end)
  end
end
