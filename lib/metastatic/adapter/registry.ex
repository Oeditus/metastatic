defmodule Metastatic.Adapter.Registry do
  @moduledoc """
  Registry for language adapters.

  Owns the runtime language registry: it seeds `Metastatic.Languages.Store`
  with the built-in adapters and serialises every subsequent registration.
  Adapters can be registered dynamically, supplied through the child-spec
  `:plugins` option, or discovered automatically.

  ## Meta-Modeling Context

  The registry maintains mappings between:
  - **Languages** (atoms like `:python`, `:javascript`) → **Adapter modules**
  - **File extensions** (strings like `".py"`) → **Languages**

  This enables automatic language detection and adapter selection for
  M1 ↔ M2 transformations.

  ## Registering a plug-in

  A third-party adapter is registered at boot, without editing Metastatic:

      # my_app/lib/my_app/application.ex
      children = [
        {Metastatic.Adapter.Registry, plugins: [MyApp.Adapters.Rust]}
      ]

  Each plug-in module may declare its descriptor through `__using__`
  (`Metastatic.Adapter.Plugin`) or simply implement `Metastatic.Adapter`; in
  the latter case the language atom is derived from the module name the same
  way built-in discovery does it (`MyApp.Adapters.Rust` → `:rust`).

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

  alias Metastatic.{Adapter, Language, Languages.Builtin, Languages.Store}

  @type plugin :: module() | {atom(), module()} | {atom(), module(), keyword()}

  # Client API

  @doc """
  Start the registry.

  This is typically called by the application supervisor.

  ## Options

    * `:plugins` — adapters to register at start. Each entry is a module, a
      `{language, module}` pair, or a `{language, module, opts}` triple.
    * `:name` — the process name (default `__MODULE__`), as with any GenServer.

  ## Examples

      iex> {:ok, pid} = Metastatic.Adapter.Registry.start_link(name: :registry_doc_demo)
      iex> is_pid(pid)
      true
      iex> GenServer.stop(pid)
      :ok
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    {plugins, opts} = Keyword.pop(opts, :plugins, [])
    GenServer.start_link(__MODULE__, %{plugins: plugins}, opts ++ [name: name])
  end

  @doc """
  Register a language adapter.

  ## Parameters

  - `language` - Language identifier (e.g., `:python`, `:javascript`)
  - `adapter` - Module implementing `Metastatic.Adapter` behaviour
  - `opts` - descriptor options: `:experimental?`, `:documentation?`,
    `:extensions`

  ## Examples

      iex> Registry.register(:python, Metastatic.Adapters.Python)
      :ok

      iex> Registry.register(:python, InvalidModule)
      {:error, :invalid_adapter}

      # Re-registering a *different* adapter for an occupied language is refused
      # => {:error, {:already_registered, :python, Metastatic.Adapters.Python}}
  """
  @spec register(atom(), module(), keyword()) ::
          :ok | {:error, :invalid_adapter} | {:error, {:already_registered, atom(), module()}}
  def register(language, adapter, opts \\ []) do
    if Adapter.valid_adapter?(adapter) do
      GenServer.call(__MODULE__, {:register, language, adapter, plugin_opts(adapter, opts)})
    else
      {:error, :invalid_adapter}
    end
  end

  @doc """
  Registers a batch of plug-ins at runtime.

  Use this when Metastatic's own supervisor has already started the registry —
  the common case for a host application, since `:metastatic` is started as a
  dependency before the host's `start/2` runs. The `:plugins` child-spec option
  is only available when *you* start the registry.

  Returns `:ok`, or `{:error, failures}` listing every entry that could not be
  registered, so one bad plug-in does not hide the others.

  ## Examples

      iex> Metastatic.Adapter.Registry.install([{MyApp.Adapters.Rust, extensions: [".rs"]}])
      :ok
  """
  @spec install([plugin()]) :: :ok | {:error, list()}
  def install(plugins) when is_list(plugins) do
    GenServer.call(__MODULE__, {:install, plugins})
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
  Unconditionally installs `adapter` for `language`, replacing any existing
  registration — including a built-in one.

  This is deliberately separate from `register/3`, which refuses to shadow an
  occupied language. Replacing `:python` with a fake changes what every other
  caller in the VM sees, so it must be an explicit, greppable act.

  Intended for tests that need a deterministic adapter without the real
  toolchain, and for hosts that intentionally override a built-in.

  ## Examples

      iex> Registry.replace(:python, Metastatic.Adapters.Elixir, extensions: [".py"])
      :ok
      iex> Registry.get(:python)
      {:ok, Metastatic.Adapters.Elixir}
  """
  @spec replace(atom(), module(), keyword()) :: :ok | {:error, :invalid_adapter}
  def replace(language, adapter, opts \\ []) do
    if Adapter.valid_adapter?(adapter) do
      GenServer.call(__MODULE__, {:replace, language, adapter, opts})
    else
      {:error, :invalid_adapter}
    end
  end

  @doc """
  Unregister a language adapter.

  Built-in languages cannot be unregistered — they are re-seeded at boot, so
  removing one would only desynchronise the store from the library's contract.

  ## Examples

      iex> Registry.unregister(:python)
      {:error, :builtin}
  """
  @spec unregister(atom()) :: :ok | {:error, :builtin}
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
  """
  @spec validate_all() :: {:ok, []} | {:error, [{atom(), String.t()}]}
  def validate_all do
    GenServer.call(__MODULE__, :validate_all)
  end

  # Server Callbacks

  @impl true
  def init(%{plugins: plugins}) do
    Store.init()
    Store.seed(Builtin.all())

    # Plug-ins are written straight to the store: `register/3` is a
    # `GenServer.call/3` to *this* process, which cannot be answered while
    # `init/1` is still running.
    case install_plugins(plugins) do
      :ok ->
        {:ok, %{}}

      {:error, failures} ->
        # A bad plug-in is a programming error in the host application, and
        # starting with a half-registered language set would fail later in a
        # much more confusing place.
        {:stop, {:invalid_plugins, failures}}
    end
  end

  @impl true
  def handle_call({:install, plugins}, _from, state) do
    failures =
      plugins
      |> Enum.map(&install_plugin/1)
      |> Enum.reject(&(&1 == :ok))

    case failures do
      [] -> {:reply, :ok, state}
      _ -> {:reply, {:error, failures}, state}
    end
  end

  @impl true
  def handle_call({:register, language, adapter, opts}, _from, state) do
    case Store.get(language) do
      %Language{adapter: ^adapter} ->
        # Idempotent re-registration of the same adapter.
        {:reply, :ok, state}

      %Language{adapter: existing} ->
        # Refuse to silently replace one adapter with a different one.
        {:reply, {:error, {:already_registered, language, existing}}, state}

      nil ->
        descriptor = Language.new(language, adapter, opts)
        Store.put(descriptor)
        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call({:replace, language, adapter, opts}, _from, state) do
    Store.put(Language.new(language, adapter, opts))
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:get, language}, _from, state) do
    case Store.get(language) do
      %Language{adapter: adapter} -> {:reply, {:ok, adapter}, state}
      nil -> {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:unregister, language}, _from, state) do
    if builtin?(language) do
      {:reply, {:error, :builtin}, state}
    else
      Store.delete(language)
      {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call(:list, _from, state) do
    adapters = Map.new(Store.all(), fn lang -> {lang.language, lang.adapter} end)
    {:reply, adapters, state}
  end

  @impl true
  def handle_call({:detect_language, filename}, _from, state) do
    case Store.detect(Path.extname(filename)) do
      {:ok, language} -> {:reply, {:ok, language}, state}
      :error -> {:reply, {:error, :unknown_extension}, state}
    end
  end

  @impl true
  def handle_call(:validate_all, _from, state) do
    invalid =
      Enum.reduce(Store.all(), [], fn %Language{language: language, adapter: adapter}, acc ->
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

  # ----- Private -----

  defp builtin?(language) do
    Enum.any?(Builtin.all(), &(&1.language == language))
  end

  # A module built with `Metastatic.Adapter.Plugin` declares its descriptor
  # (extensions, flags); use it as the default so `register(:lang, Mod)` is
  # enough. Explicit options still win, which is what lets a test override
  # extensions for a mock.
  defp plugin_opts(adapter, opts) do
    Code.ensure_loaded(adapter)

    if function_exported?(adapter, :__metastatic_plugin_opts__, 0) do
      Keyword.merge(adapter.__metastatic_plugin_opts__(), opts)
    else
      opts
    end
  end

  # Registers every plug-in, collecting failures instead of crashing on the
  # first one so the operator sees the whole list.
  defp install_plugins(plugins) do
    failures =
      plugins
      |> Enum.map(&install_plugin/1)
      |> Enum.reject(&(&1 == :ok))

    case failures do
      [] -> :ok
      _ -> {:error, failures}
    end
  end

  # Normalises and installs one plug-in entry, returning `:ok` or a failure
  # tuple naming the entry and the reason. Mirrors the checks in
  # `handle_call({:register, …})` without the round-trip through the server.
  defp install_plugin(entry) do
    with {:ok, language, adapter, opts} <- normalise_plugin(entry),
         :ok <- validate_plugin(language, adapter) do
      Store.put(Language.new(language, adapter, plugin_opts(adapter, opts)))
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_plugin(language, adapter) do
    if Adapter.valid_adapter?(adapter) do
      case Store.get(language) do
        %Language{adapter: ^adapter} ->
          :ok

        %Language{adapter: existing} ->
          {:error, {language, adapter, {:already_registered, language, existing}}}

        nil ->
          :ok
      end
    else
      {:error, {language, adapter, :invalid_adapter}}
    end
  end

  # A module built with `Metastatic.Adapter.Plugin` carries its descriptor, so
  # the language atom, extensions and flags are read rather than guessed. A
  # bare `Metastatic.Adapter` implementation falls back to deriving the atom
  # from the module name, and its extensions from `file_extensions/0`.
  defp normalise_plugin(module) when is_atom(module) do
    Code.ensure_loaded(module)

    if function_exported?(module, :__metastatic_language__, 0) do
      {:ok, module.__metastatic_language__(), module, module.__metastatic_plugin_opts__()}
    else
      {:ok, language_from_module(module), module, []}
    end
  end

  defp normalise_plugin({language, module}) when is_atom(language) and is_atom(module) do
    {:ok, language, module, []}
  end

  defp normalise_plugin({language, module, opts})
       when is_atom(language) and is_atom(module) and is_list(opts) do
    {:ok, language, module, opts}
  end

  defp normalise_plugin(other), do: {:error, {:invalid_plugin, other}}

  # Mirrors `Metastatic.Languages.Discovery`'s derivation so a plug-in module
  # named `MyApp.Adapters.Rust` becomes `:rust` without extra configuration.
  defp language_from_module(module) do
    module
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
    |> String.to_atom()
  end
end
