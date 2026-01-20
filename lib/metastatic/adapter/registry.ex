defmodule Metastatic.Adapter.Registry do
  @moduledoc """
  Registry for language adapters.

  Provides a centralized registry for managing language adapters that implement
  the `Metastatic.Adapter` behaviour. Adapters can be registered dynamically
  or discovered automatically from the application.

  ## Meta-Modeling Context

  The registry maintains mappings between:
  - **Languages** (atoms like `:python`, `:javascript`) → **Adapter modules**
  - **File extensions** (strings like `".py"`) → **Languages**

  This enables automatic language detection and adapter selection for
  M1 ↔ M2 transformations.

  ## Usage

      # Register an adapter
      Registry.register(:python, Metastatic.Adapters.Python)

      # Get adapter for a language
      {:ok, adapter} = Registry.get(:python)

      # Detect language from filename
      {:ok, language} = Registry.detect_language("script.py")

      # List all registered adapters
      adapters = Registry.list()
  """

  use GenServer

  alias Metastatic.Adapter

  # Client API

  @doc """
  Start the registry.

  This is typically called by the application supervisor.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts ++ [name: __MODULE__])
  end

  @doc """
  Register a language adapter.

  ## Parameters

  - `language` - Language identifier (e.g., `:python`, `:javascript`)
  - `adapter` - Module implementing `Metastatic.Adapter` behaviour

  ## Examples

      iex> Registry.register(:python, Metastatic.Adapters.Python)
      :ok

      iex> Registry.register(:python, InvalidModule)
      {:error, :invalid_adapter}
  """
  @spec register(atom(), module()) :: :ok | {:error, :invalid_adapter}
  def register(language, adapter) do
    if Adapter.valid_adapter?(adapter) do
      GenServer.call(__MODULE__, {:register, language, adapter})
    else
      {:error, :invalid_adapter}
    end
  end

  @doc """
  Get the adapter module for a language.

  ## Examples

      iex> Registry.get(:python)
      {:ok, Metastatic.Adapters.Python}

      iex> Registry.get(:unknown)
      {:error, :not_found}
  """
  @spec get(atom()) :: {:ok, module()} | {:error, :not_found}
  def get(language) do
    GenServer.call(__MODULE__, {:get, language})
  end

  @doc """
  Unregister a language adapter.

  ## Examples

      iex> Registry.unregister(:python)
      :ok
  """
  @spec unregister(atom()) :: :ok
  def unregister(language) do
    GenServer.call(__MODULE__, {:unregister, language})
  end

  @doc """
  List all registered adapters.

  Returns a map of language atoms to adapter modules.

  ## Examples

      iex> Registry.list()
      %{python: Metastatic.Adapters.Python, javascript: Metastatic.Adapters.JavaScript}
  """
  @spec list() :: %{atom() => module()}
  def list do
    GenServer.call(__MODULE__, :list)
  end

  @doc """
  Detect language from filename based on extension.

  Uses the registered adapters' file extensions to determine the language.

  ## Examples

      iex> Registry.detect_language("script.py")
      {:ok, :python}

      iex> Registry.detect_language("app.js")
      {:ok, :javascript}

      iex> Registry.detect_language("unknown.xyz")
      {:error, :unknown_extension}
  """
  @spec detect_language(String.t()) :: {:ok, atom()} | {:error, :unknown_extension}
  def detect_language(filename) do
    GenServer.call(__MODULE__, {:detect_language, filename})
  end

  @doc """
  Check if a language is registered.

  ## Examples

      iex> Registry.registered?(:python)
      true

      iex> Registry.registered?(:unknown)
      false
  """
  @spec registered?(atom()) :: boolean()
  def registered?(language) do
    case get(language) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Validate that all registered adapters are still valid.

  Returns a list of invalid adapters (if any).

  ## Examples

      iex> Registry.validate_all()
      {:ok, []}

      iex> Registry.validate_all()
      {:error, [python: "Missing required callback: parse/1"]}
  """
  @spec validate_all() :: {:ok, []} | {:error, [{atom(), String.t()}]}
  def validate_all do
    GenServer.call(__MODULE__, :validate_all)
  end

  # Server Callbacks

  @impl true
  def init(:ok) do
    # State: %{adapters: %{language => module}, extensions: %{ext => language}}
    state = %{
      adapters: %{},
      extensions: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:register, language, adapter}, _from, state) do
    # Update adapters map
    new_adapters = Map.put(state.adapters, language, adapter)

    # Update extensions map
    extensions = adapter.file_extensions()

    new_extensions =
      Enum.reduce(extensions, state.extensions, fn ext, acc ->
        Map.put(acc, ext, language)
      end)

    new_state = %{state | adapters: new_adapters, extensions: new_extensions}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:get, language}, _from, state) do
    case Map.fetch(state.adapters, language) do
      {:ok, adapter} -> {:reply, {:ok, adapter}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:unregister, language}, _from, state) do
    new_adapters = Map.delete(state.adapters, language)

    # Remove all extensions associated with this language
    new_extensions =
      Enum.reject(state.extensions, fn {_ext, lang} -> lang == language end)
      |> Map.new()

    new_state = %{state | adapters: new_adapters, extensions: new_extensions}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:list, _from, state) do
    {:reply, state.adapters, state}
  end

  @impl true
  def handle_call({:detect_language, filename}, _from, state) do
    extension = Path.extname(filename)

    case Map.fetch(state.extensions, extension) do
      {:ok, language} -> {:reply, {:ok, language}, state}
      :error -> {:reply, {:error, :unknown_extension}, state}
    end
  end

  @impl true
  def handle_call(:validate_all, _from, state) do
    invalid =
      Enum.reduce(state.adapters, [], fn {language, adapter}, acc ->
        if Adapter.valid_adapter?(adapter) do
          acc
        else
          [{language, "Adapter does not implement all required callbacks"} | acc]
        end
      end)

    case invalid do
      [] -> {:reply, {:ok, []}, state}
      errors -> {:reply, {:error, Enum.reverse(errors)}, state}
    end
  end
end
