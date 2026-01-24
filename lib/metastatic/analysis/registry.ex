defmodule Metastatic.Analysis.Registry do
  @moduledoc """
  Registry for analyzer plugins.

  Manages registration, discovery, and configuration of analyzers.
  Runs as a GenServer under the application supervision tree.

  ## Usage

      # Register an analyzer
      Registry.register(MyApp.Analysis.UnusedVariables)

      # Look up by name
      Registry.get_by_name(:unused_variables)

      # Look up by category
      Registry.list_by_category(:correctness)

      # List all
      Registry.list_all()

      # Configure analyzer
      Registry.configure(MyAnalyzer, %{threshold: 10})

  ## Configuration

  Auto-register analyzers at application startup:

      # config/config.exs
      config :metastatic, :analyzers,
        auto_register: [
          Metastatic.Analysis.UnusedVariables,
          Metastatic.Analysis.SimplifyConditional
        ],
        disabled: [:some_analyzer],
        config: %{
          unused_variables: %{ignore_prefix: "_"}
        }
  """

  use GenServer

  alias Metastatic.Analysis.Analyzer

  require Logger

  @type registry_state :: %{
          by_name: %{atom() => module()},
          by_category: %{atom() => [module()]},
          all: MapSet.t(module()),
          config: %{module() => map()}
        }

  # ----- Client API -----

  @doc """
  Starts the registry GenServer.

  Called automatically by the application supervision tree.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Registers an analyzer module.

  The module must implement the `Metastatic.Analysis.Analyzer` behaviour.
  Validates that no conflicts exist (another analyzer with same name).

  ## Examples

      iex> Registry.register(MyApp.Analysis.UnusedVariables)
      :ok

      iex> Registry.register(ConflictingAnalyzer)
      {:error, "Analyzer named :unused_variables already registered: ..."}
  """
  @spec register(module()) :: :ok | {:error, String.t()}
  def register(analyzer) do
    GenServer.call(__MODULE__, {:register, analyzer})
  end

  @doc """
  Unregisters an analyzer module.

  Removes the analyzer from the registry.

  ## Examples

      iex> Registry.unregister(MyApp.Analysis.UnusedVariables)
      :ok
  """
  @spec unregister(module()) :: :ok
  def unregister(analyzer) do
    GenServer.call(__MODULE__, {:unregister, analyzer})
  end

  @doc """
  Lists all registered analyzers.

  ## Examples

      iex> Registry.list_all()
      [MyApp.Analysis.UnusedVariables, MyApp.Analysis.SimplifyConditional]
  """
  @spec list_all() :: [module()]
  def list_all do
    GenServer.call(__MODULE__, :list_all)
  end

  @doc """
  Lists analyzers by category.

  ## Examples

      iex> Registry.list_by_category(:correctness)
      [MyApp.Analysis.UnusedVariables, MyApp.Analysis.DeadCode]
  """
  @spec list_by_category(atom()) :: [module()]
  def list_by_category(category) do
    GenServer.call(__MODULE__, {:list_by_category, category})
  end

  @doc """
  Gets analyzer by name.

  Returns `nil` if no analyzer is registered with that name.

  ## Examples

      iex> Registry.get_by_name(:unused_variables)
      MyApp.Analysis.UnusedVariables

      iex> Registry.get_by_name(:nonexistent)
      nil
  """
  @spec get_by_name(atom()) :: module() | nil
  def get_by_name(name) do
    GenServer.call(__MODULE__, {:get_by_name, name})
  end

  @doc """
  Lists all available categories.

  ## Examples

      iex> Registry.list_categories()
      [:correctness, :style, :refactoring, :maintainability]
  """
  @spec list_categories() :: [atom()]
  def list_categories do
    GenServer.call(__MODULE__, :list_categories)
  end

  @doc """
  Updates configuration for an analyzer.

  Merges the new config with existing config.

  ## Examples

      iex> Registry.configure(MyAnalyzer, %{threshold: 10})
      :ok
  """
  @spec configure(module(), map()) :: :ok
  def configure(analyzer, config) do
    GenServer.call(__MODULE__, {:configure, analyzer, config})
  end

  @doc """
  Gets configuration for an analyzer.

  Returns empty map if no configuration is set.

  ## Examples

      iex> Registry.get_config(MyAnalyzer)
      %{threshold: 10}
  """
  @spec get_config(module()) :: map()
  def get_config(analyzer) do
    GenServer.call(__MODULE__, {:get_config, analyzer})
  end

  @doc """
  Clears all registered analyzers.

  Primarily for testing purposes.
  """
  @spec clear() :: :ok
  def clear do
    GenServer.call(__MODULE__, :clear)
  end

  # ----- Server Callbacks -----

  @impl true
  def init(_opts) do
    state = %{
      by_name: %{},
      by_category: %{},
      all: MapSet.new(),
      config: %{}
    }

    # Auto-register configured analyzers
    auto_register_from_config()

    {:ok, state}
  end

  @impl true
  def handle_call({:register, analyzer}, _from, state) do
    case validate_and_register(analyzer, state) do
      {:ok, new_state} ->
        Logger.debug("Registered analyzer: #{inspect(analyzer)}")
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:unregister, analyzer}, _from, state) do
    new_state = do_unregister(analyzer, state)
    Logger.debug("Unregistered analyzer: #{inspect(analyzer)}")
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:list_all, _from, state) do
    analyzers = MapSet.to_list(state.all)
    {:reply, analyzers, state}
  end

  @impl true
  def handle_call({:list_by_category, category}, _from, state) do
    analyzers = Map.get(state.by_category, category, [])
    {:reply, analyzers, state}
  end

  @impl true
  def handle_call({:get_by_name, name}, _from, state) do
    analyzer = Map.get(state.by_name, name)
    {:reply, analyzer, state}
  end

  @impl true
  def handle_call(:list_categories, _from, state) do
    categories =
      state.by_category
      |> Map.keys()
      |> Enum.sort()

    {:reply, categories, state}
  end

  @impl true
  def handle_call({:configure, analyzer, config}, _from, state) do
    new_config =
      Map.update(state.config, analyzer, config, fn existing ->
        Map.merge(existing, config)
      end)

    {:reply, :ok, %{state | config: new_config}}
  end

  @impl true
  def handle_call({:get_config, analyzer}, _from, state) do
    config = Map.get(state.config, analyzer, %{})
    {:reply, config, state}
  end

  @impl true
  def handle_call(:clear, _from, _state) do
    new_state = %{
      by_name: %{},
      by_category: %{},
      all: MapSet.new(),
      config: %{}
    }

    {:reply, :ok, new_state}
  end

  # ----- Private Functions -----

  defp validate_and_register(analyzer, state) do
    with :ok <- validate_behaviour(analyzer),
         :ok <- validate_info(analyzer),
         :ok <- validate_no_conflicts(analyzer, state) do
      {:ok, do_register(analyzer, state)}
    end
  end

  defp validate_behaviour(analyzer) do
    if Analyzer.valid?(analyzer) do
      :ok
    else
      {:error, "Module #{inspect(analyzer)} does not implement Analyzer behaviour correctly"}
    end
  end

  defp validate_info(analyzer) do
    info = analyzer.info()

    required_keys = [:name, :category, :description, :severity, :explanation, :configurable]

    if Enum.all?(required_keys, &Map.has_key?(info, &1)) do
      :ok
    else
      {:error, "Module #{inspect(analyzer)} has invalid info (missing required keys)"}
    end
  end

  defp validate_no_conflicts(analyzer, state) do
    info = analyzer.info()
    name = info.name

    case Map.get(state.by_name, name) do
      nil ->
        :ok

      existing ->
        {:error, "Analyzer named #{inspect(name)} already registered: #{inspect(existing)}"}
    end
  end

  defp do_register(analyzer, state) do
    info = analyzer.info()
    name = info.name
    category = info.category

    # Update by_name index
    by_name = Map.put(state.by_name, name, analyzer)

    # Update by_category index
    by_category =
      Map.update(state.by_category, category, [analyzer], fn list ->
        [analyzer | list] |> Enum.uniq()
      end)

    # Update all set
    all = MapSet.put(state.all, analyzer)

    %{state | by_name: by_name, by_category: by_category, all: all}
  end

  defp do_unregister(analyzer, state) do
    if MapSet.member?(state.all, analyzer) do
      info = analyzer.info()
      name = info.name
      category = info.category

      # Remove from by_name index
      by_name = Map.delete(state.by_name, name)

      # Remove from by_category index
      by_category =
        Map.update(state.by_category, category, [], fn list ->
          List.delete(list, analyzer)
        end)

      # Remove from all set
      all = MapSet.delete(state.all, analyzer)

      # Remove config
      config = Map.delete(state.config, analyzer)

      %{state | by_name: by_name, by_category: by_category, all: all, config: config}
    else
      state
    end
  end

  defp auto_register_from_config do
    config = Application.get_env(:metastatic, :analyzers, [])
    auto_register = Keyword.get(config, :auto_register, [])
    disabled = Keyword.get(config, :disabled, [])
    analyzer_config = Keyword.get(config, :config, %{})

    Enum.each(auto_register, fn analyzer ->
      info = analyzer.info()

      unless info.name in disabled do
        case register(analyzer) do
          :ok ->
            # Apply config if present
            if Map.has_key?(analyzer_config, info.name) do
              configure(analyzer, Map.get(analyzer_config, info.name))
            end

            Logger.info("Auto-registered analyzer: #{inspect(analyzer)}")

          {:error, reason} ->
            Logger.warning("Failed to auto-register #{inspect(analyzer)}: #{inspect(reason)}")
        end
      end
    end)
  end
end
