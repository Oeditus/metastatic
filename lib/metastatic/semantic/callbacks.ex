defmodule Metastatic.Semantic.Callbacks do
  @moduledoc """
  Registry of known behaviour/base-class callbacks per language.

  Maps `{language, behaviour_module, function_name, arity}` tuples to
  callback specs, enabling the enricher to annotate `:function_def` nodes
  with `callback_for:` metadata when the enclosing container uses/inherits
  a registered behaviour.

  Storage uses `:persistent_term` (same strategy as `Semantic.Patterns`).

  ## Built-in Registrations

  The module ships with callbacks for common frameworks:

  - **Elixir:** Oban.Worker, GenServer, Phoenix.LiveView, Plug, Broadway
  - **Ruby:** ActiveJob::Base, Sidekiq::Worker, Resque
  - **Python:** celery.Task, RQ Worker, Dramatiq

  ## Usage

      # Check if a function is a known callback
      Callbacks.lookup(:elixir, "Oban.Worker", "perform", 1)
      #=> {:ok, %{framework: :oban, domain: :queue}}

      # Register a custom callback
      Callbacks.register(:elixir, "MyBehaviour", "handle_event", 2,
        %{framework: :custom, domain: nil})

  ## Integration

  The enricher calls `lookup/4` during tree traversal. When a `:container`
  node declares a behaviour (via `:import` children or `:parent` metadata),
  its `:function_def` children are checked against this registry.
  """

  @typedoc "Callback specification describing the framework and domain"
  @type callback_spec :: %{framework: atom(), domain: atom() | nil}

  @typedoc "Registry key: {language, behaviour_module, function_name, arity_or_nil}"
  @type callback_key :: {atom(), String.t(), String.t(), non_neg_integer() | nil}

  @persistent_term_key {__MODULE__, :registry}

  # ----- Public API -----

  @doc """
  Registers a callback for a behaviour in a specific language.

  When `arity` is `nil`, the callback matches any arity for that function name.

  ## Parameters

  - `language` - Source language atom (`:elixir`, `:ruby`, `:python`, etc.)
  - `behaviour` - The behaviour/base-class module name (e.g., `"Oban.Worker"`)
  - `function_name` - The callback function name (e.g., `"perform"`)
  - `arity` - Expected arity, or `nil` for any arity
  - `spec` - A `%{framework: atom(), domain: atom() | nil}` map

  ## Examples

      iex> Callbacks.register(:elixir, "Oban.Worker", "perform", 1, %{framework: :oban, domain: :queue})
      :ok
  """
  @spec register(atom(), String.t(), String.t(), non_neg_integer() | nil, callback_spec()) :: :ok
  def register(language, behaviour, function_name, arity, spec)
      when is_atom(language) and is_binary(behaviour) and is_binary(function_name) and
             is_map(spec) do
    registry = get_registry()
    key = {language, behaviour, function_name, arity}
    :persistent_term.put(@persistent_term_key, Map.put(registry, key, spec))
    :ok
  end

  @doc """
  Looks up a callback by language, behaviour, function name, and arity.

  Tries an exact arity match first, then falls back to a wildcard (nil arity)
  match.

  ## Examples

      iex> Callbacks.lookup(:elixir, "Oban.Worker", "perform", 1)
      {:ok, %{framework: :oban, domain: :queue}}

      iex> Callbacks.lookup(:elixir, "Oban.Worker", "unknown", 0)
      :no_match
  """
  @spec lookup(atom(), String.t(), String.t(), non_neg_integer() | nil) ::
          {:ok, callback_spec()} | :no_match
  def lookup(language, behaviour, function_name, arity) do
    registry = get_registry()

    # Try exact arity match first
    case Map.get(registry, {language, behaviour, function_name, arity}) do
      nil ->
        # Fall back to wildcard arity
        case Map.get(registry, {language, behaviour, function_name, nil}) do
          nil -> :no_match
          spec -> {:ok, spec}
        end

      spec ->
        {:ok, spec}
    end
  end

  @doc """
  Checks whether a function in a given behaviour is a known callback.

  ## Examples

      iex> Callbacks.callback?(:elixir, "Oban.Worker", "perform", 1)
      true

      iex> Callbacks.callback?(:elixir, "Oban.Worker", "unknown", 0)
      false
  """
  @spec callback?(atom(), String.t(), String.t(), non_neg_integer() | nil) :: boolean()
  def callback?(language, behaviour, function_name, arity) do
    match?({:ok, _}, lookup(language, behaviour, function_name, arity))
  end

  @doc """
  Returns all registered behaviours for a language.

  ## Examples

      iex> behaviours = Callbacks.behaviours_for_language(:elixir)
      iex> "Oban.Worker" in behaviours
      true
  """
  @spec behaviours_for_language(atom()) :: [String.t()]
  def behaviours_for_language(language) do
    get_registry()
    |> Map.keys()
    |> Enum.filter(fn {lang, _, _, _} -> lang == language end)
    |> Enum.map(fn {_, behaviour, _, _} -> behaviour end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  Clears all registered callbacks. Primarily for testing.
  """
  @spec clear() :: :ok
  def clear do
    :persistent_term.put(@persistent_term_key, %{})
    :ok
  end

  @doc """
  Registers all built-in callbacks for all supported languages.

  Called during application startup. Can also be called manually to
  re-register after `clear/0`.

  OTP and Elixir standard library behaviours are discovered automatically
  via BEAM introspection (see `Metastatic.Semantic.Callbacks.BeamIntrospector`).
  Third-party framework callbacks that may not be compiled are registered
  manually.
  """
  @spec register_builtins() :: :ok
  def register_builtins do
    register_elixir_builtins()
    register_ruby_builtins()
    register_python_builtins()
    :ok
  end

  # ----- Private -----

  defp get_registry do
    :persistent_term.get(@persistent_term_key, %{})
  end

  # ----- Elixir Built-ins -----

  defp register_elixir_builtins do
    alias Metastatic.Semantic.Callbacks.BeamIntrospector

    # Auto-discover OTP/stdlib behaviours from BEAM files.
    # This replaces the previous manual callback lists for GenServer,
    # Supervisor, Application, Task, etc.
    BeamIntrospector.register_otp_behaviours()

    # Third-party frameworks -- registered manually since they may not
    # be compiled in the current environment.

    # Oban.Worker
    register(:elixir, "Oban.Worker", "perform", 1, %{framework: :oban, domain: :queue})

    # Phoenix.LiveView
    for {func, arity} <- [
          {"mount", 3},
          {"handle_event", 3},
          {"handle_info", 2},
          {"handle_params", 3},
          {"render", 1}
        ] do
      register(:elixir, "Phoenix.LiveView", func, arity, %{framework: :phoenix, domain: nil})
    end

    # Phoenix.Component
    register(:elixir, "Phoenix.Component", "render", 1, %{framework: :phoenix, domain: nil})

    # Plug
    register(:elixir, "Plug", "init", 1, %{framework: :plug, domain: nil})
    register(:elixir, "Plug", "call", 2, %{framework: :plug, domain: nil})

    # Broadway
    register(:elixir, "Broadway", "handle_message", 3, %{framework: :broadway, domain: :queue})
    register(:elixir, "Broadway", "handle_batch", 4, %{framework: :broadway, domain: :queue})

    # Ecto.Migration
    register(:elixir, "Ecto.Migration", "change", 0, %{framework: :ecto, domain: :db})
    register(:elixir, "Ecto.Migration", "up", 0, %{framework: :ecto, domain: :db})
    register(:elixir, "Ecto.Migration", "down", 0, %{framework: :ecto, domain: :db})
  end

  # ----- Ruby Built-ins -----

  defp register_ruby_builtins do
    # ActiveJob::Base
    register(:ruby, "ActiveJob::Base", "perform", nil, %{framework: :activejob, domain: :queue})

    # Sidekiq::Worker
    register(:ruby, "Sidekiq::Worker", "perform", nil, %{framework: :sidekiq, domain: :queue})

    # Sidekiq::Job (alias for Sidekiq::Worker in newer versions)
    register(:ruby, "Sidekiq::Job", "perform", nil, %{framework: :sidekiq, domain: :queue})

    # Resque
    register(:ruby, "Resque", "perform", nil, %{framework: :resque, domain: :queue})

    # ApplicationController (Rails)
    for action <- ~w[index show new create edit update destroy] do
      register(:ruby, "ApplicationController", action, nil, %{
        framework: :rails,
        domain: :http
      })
    end

    # ActionController::Base
    for action <- ~w[index show new create edit update destroy] do
      register(:ruby, "ActionController::Base", action, nil, %{
        framework: :rails,
        domain: :http
      })
    end

    # Ruby stdlib modules (included via `include`)
    register(:ruby, "Comparable", "<=>", nil, %{framework: :ruby, domain: nil})
    register(:ruby, "Enumerable", "each", nil, %{framework: :ruby, domain: nil})

    # ActiveModel::Validations
    register(:ruby, "ActiveModel::Validations", "validate", nil, %{
      framework: :rails,
      domain: nil
    })

    # ActiveRecord::Callbacks
    for callback <-
          ~w[before_validation after_validation before_save after_save before_create after_create before_update after_update before_destroy after_destroy] do
      register(:ruby, "ActiveRecord::Callbacks", callback, nil, %{
        framework: :rails,
        domain: :db
      })
    end

    # ActiveSupport::Concern
    register(:ruby, "ActiveSupport::Concern", "included", nil, %{
      framework: :rails,
      domain: nil
    })

    register(:ruby, "ActiveSupport::Concern", "class_methods", nil, %{
      framework: :rails,
      domain: nil
    })

    # Devise modules
    for mod <-
          ~w[DatabaseAuthenticatable Registerable Recoverable Rememberable Validatable Confirmable Lockable Timeoutable Trackable Omniauthable] do
      register(:ruby, "Devise::#{mod}", "devise", nil, %{framework: :devise, domain: :auth})
    end
  end

  # ----- Python Built-ins -----

  defp register_python_builtins do
    alias Metastatic.Semantic.Callbacks.PythonResolver

    # Register all base class callbacks (Django views, Flask, DRF, etc.)
    PythonResolver.register_base_class_callbacks()

    # RQ Worker (not covered by PythonResolver)
    register(:python, "rq.Worker", "perform_job", nil, %{framework: :rq, domain: :queue})
  end
end

# Register built-in callbacks when module is loaded
Metastatic.Semantic.Callbacks.register_builtins()
