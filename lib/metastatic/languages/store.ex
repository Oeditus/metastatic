defmodule Metastatic.Languages.Store do
  @moduledoc """
  ETS-backed storage for the language registry.

  This is the single place that answers "which languages exist?" at runtime.
  It is written by two paths:

    * **compile-time seeds** — `Metastatic.Languages.Builtin`, the adapters
      that ship inside Metastatic;
    * **runtime registrations** — host applications adding their own adapters
      through `Metastatic.Adapter.Registry.register/2` or `Metastatic.Languages.register/2`.

  ## Why ETS rather than module attributes

  Module attributes are frozen when *Metastatic* is compiled, which is before
  a host application exists. A third-party adapter could therefore never be
  seen by `detect_language/1` or `supported_languages/0`. ETS gives one
  authoritative table that both paths write to, while keeping the hot path
  (`detect_language/1`, called once per file during directory translation) a
  single `:ets.lookup/2` with `read_concurrency: true` — no `GenServer.call`.

  ## Tables

  | Table | Key | Value |
  | :--- | :--- | :--- |
  | `:metastatic_languages` | language atom | `%Metastatic.Language{}` |
  | `:metastatic_extensions` | extension (`".py"`) | language atom |

  Both are `:public` so readers never block on the owning process. Writers go
  through `Metastatic.Adapter.Registry`, which serialises them.

  ## Lifecycle

  `init/0` creates the tables if they do not exist and is safe to call
  concurrently and repeatedly. Reads fall back to the compile-time seeds when
  the tables are absent, so a caller that runs before the application starts
  (a Mix task, a script, a doctest) still sees the built-in languages.
  """

  alias Metastatic.{Language, Languages.Builtin}

  @languages_table :metastatic_languages
  @extensions_table :metastatic_extensions

  @doc """
  Creates the ETS tables if they are missing. Idempotent and concurrency-safe.

  ## Examples

      iex> Metastatic.Languages.Store.init()
      :ok
  """
  @spec init() :: :ok
  def init do
    ensure_table(@languages_table, [:set, :public, :named_table, read_concurrency: true])
    ensure_table(@extensions_table, [:set, :public, :named_table, read_concurrency: true])
    :ok
  end

  @doc """
  Seeds the tables with the compile-time built-in languages.

  Idempotent: re-seeding overwrites each descriptor in place, so a language
  registered at runtime under the same atom is *replaced* by the built-in one.
  That is deliberate — the built-ins are the library's own contract and a host
  should not be able to shadow `:python`. To add a language, use a new atom.

  ## Examples

      iex> Metastatic.Languages.Store.seed(Metastatic.Languages.Builtin.all())
      :ok
  """
  @spec seed([Language.t()]) :: :ok
  def seed(languages) when is_list(languages) do
    init()
    Enum.each(languages, &put/1)
  end

  @doc """
  Inserts or replaces a language descriptor and its extensions.

  ## Examples

      iex> lang = Metastatic.Language.new(:demo, Metastatic.Adapters.Elixir, extensions: [".demo"])
      iex> Metastatic.Languages.Store.put(lang)
      :ok
      iex> Metastatic.Languages.Store.get(:demo).language
      :demo
  """
  @spec put(Language.t()) :: :ok
  def put(%Language{} = language) do
    init()
    :ets.insert(@languages_table, {language.language, language})

    Enum.each(language.extensions, fn ext ->
      :ets.insert(@extensions_table, {ext, language.language})
    end)

    :ok
  end

  @doc """
  Removes a language and every extension it claimed.

  Extensions are only removed when they still point at `language`, so
  unregistering a language cannot silently break another one that shares an
  extension.

  ## Examples

      iex> lang = Metastatic.Language.new(:demo, Metastatic.Adapters.Elixir, extensions: [".demo"])
      iex> :ok = Metastatic.Languages.Store.put(lang)
      iex> Metastatic.Languages.Store.delete(:demo)
      :ok
      iex> Metastatic.Languages.Store.get(:demo)
      nil
  """
  @spec delete(atom()) :: :ok
  def delete(language) when is_atom(language) do
    init()

    case :ets.lookup(@languages_table, language) do
      [{^language, %Language{extensions: exts}}] ->
        Enum.each(exts, fn ext ->
          case :ets.lookup(@extensions_table, ext) do
            [{^ext, ^language}] -> :ets.delete(@extensions_table, ext)
            _ -> :ok
          end
        end)

        :ets.delete(@languages_table, language)
        :ok

      [] ->
        :ok
    end
  end

  @doc """
  Returns the descriptor for a language, or `nil`.

  Falls back to the compile-time built-ins when the tables have not been
  created yet.

  ## Examples

      iex> Metastatic.Languages.Store.get(:python).language
      :python

      iex> Metastatic.Languages.Store.get(:brainfuck)
      nil
  """
  @spec get(atom()) :: Language.t() | nil
  def get(language) when is_atom(language) do
    case lookup(@languages_table, language) do
      {:ok, descriptor} -> descriptor
      :error -> if table_absent?(@languages_table), do: builtin_get(language)
    end
  end

  @doc """
  Returns every descriptor, sorted by language atom.

  ## Examples

      iex> is_list(Metastatic.Languages.Store.all())
      true
  """
  @spec all() :: [Language.t()]
  def all do
    case tab2list(@languages_table) do
      {:ok, entries} -> entries |> Enum.map(fn {_lang, descriptor} -> descriptor end) |> sort()
      :error -> builtin_all()
    end
  end

  @doc """
  Resolves a file extension (dot-prefixed) to a language atom.

  ## Examples

      iex> Metastatic.Languages.Store.detect(".py")
      {:ok, :python}

      iex> Metastatic.Languages.Store.detect(".nope")
      :error
  """
  @spec detect(String.t()) :: {:ok, atom()} | :error
  def detect(extension) when is_binary(extension) do
    case lookup(@extensions_table, extension) do
      {:ok, language} -> {:ok, language}
      :error -> if table_absent?(@extensions_table), do: builtin_detect(extension), else: :error
    end
  end

  @doc """
  Returns every registered extension, sorted.

  ## Examples

      iex> ".py" in Metastatic.Languages.Store.extensions()
      true
  """
  @spec extensions() :: [String.t()]
  def extensions do
    case tab2list(@extensions_table) do
      {:ok, entries} -> entries |> Enum.map(fn {ext, _lang} -> ext end) |> Enum.sort()
      :error -> builtin_extensions()
    end
  end

  @doc """
  Returns `true` when the store has been initialised in this VM.

  ## Examples

      iex> is_boolean(Metastatic.Languages.Store.initialized?())
      true
  """
  @spec initialized?() :: boolean()
  def initialized? do
    :ets.info(@languages_table) != :undefined
  end

  # ----- Private -----

  defp ensure_table(name, options) do
    # `:ets.new/2` raises if the table exists, and a concurrent caller can
    # create it between the check and the call, so the race is handled rather
    # than avoided.
    if :ets.info(name) == :undefined do
      :ets.new(name, options)
    end

    :ok
  rescue
    ArgumentError -> :ok
  end

  defp lookup(table, key) do
    case :ets.lookup(table, key) do
      [{^key, value}] -> {:ok, value}
      [] -> :error
    end
  rescue
    ArgumentError -> :error
  end

  defp tab2list(table) do
    {:ok, :ets.tab2list(table)}
  rescue
    ArgumentError -> :error
  end

  defp table_absent?(table), do: :ets.info(table) == :undefined

  defp sort(descriptors), do: Enum.sort_by(descriptors, & &1.language)

  # Compile-time fallbacks. Used only before `init/0` has run (a Mix task that
  # does not start the application, a doctest, a script). Keeping them here
  # rather than in `Languages` means the public module has exactly one source
  # of truth at runtime.
  defp builtin_get(language) do
    Enum.find(Builtin.all(), &(&1.language == language))
  end

  defp builtin_all, do: Builtin.all()

  defp builtin_detect(extension) do
    case Enum.find(Builtin.all(), &(extension in &1.extensions)) do
      nil -> :error
      descriptor -> {:ok, descriptor.language}
    end
  end

  defp builtin_extensions do
    Builtin.all()
    |> Enum.flat_map(& &1.extensions)
    |> Enum.uniq()
    |> Enum.sort()
  end
end
