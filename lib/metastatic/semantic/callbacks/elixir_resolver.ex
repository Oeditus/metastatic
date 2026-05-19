defmodule Metastatic.Semantic.Callbacks.ElixirResolver do
  @moduledoc """
  Resolves Elixir `use` macros to discover which behaviours they inject.

  When `use SomeModule` appears inside a container, this resolver figures
  out which `@behaviour` attributes that `use` directive introduces, so
  that the enricher can annotate callback implementations.

  Two resolution strategies are tried in order:

  1. **Runtime query** (fast path): If the target module is compiled and
     loaded, expand `use Module` via ExPanda and scan the expanded AST
     for `@behaviour` attributes.

  2. **ExPanda expansion** (slow path): For source-only modules, expand
     the `use` call via `ExPanda.expand/1` and scan the resulting AST.

  Results are cached in `:persistent_term` to avoid re-expansion.

  ## Integration

  The enricher calls `resolve_behaviours/1` when it encounters an
  `:import` node with `import_type: :use` inside an Elixir container.
  Discovered behaviours are dynamically registered in the
  `Semantic.Callbacks` registry.
  """

  require Logger

  alias Metastatic.Semantic.Callbacks
  alias Metastatic.Semantic.Callbacks.BeamIntrospector

  @persistent_term_key {__MODULE__, :cache}

  @typedoc "A resolved behaviour: the module name string"
  @type behaviour_name :: String.t()

  @doc """
  Resolves which behaviours a `use Module` directive introduces.

  Returns a list of behaviour module name strings (e.g., `["GenServer"]`).
  For each discovered behaviour that defines callbacks, the callbacks are
  automatically registered in the `Semantic.Callbacks` registry.

  ## Examples

      iex> behaviours = ElixirResolver.resolve_behaviours("GenServer")
      iex> "GenServer" in behaviours
      true

      iex> ElixirResolver.resolve_behaviours("SomeUnknownModule")
      []
  """
  @spec resolve_behaviours(String.t()) :: [behaviour_name()]
  def resolve_behaviours(module_name) when is_binary(module_name) do
    cache = get_cache()

    case Map.get(cache, module_name) do
      nil ->
        behaviours = do_resolve(module_name)
        put_cache(Map.put(cache, module_name, behaviours))

        # Auto-register discovered behaviours
        for behaviour <- behaviours do
          register_discovered_behaviour(behaviour)
        end

        behaviours

      cached ->
        cached
    end
  end

  @doc """
  Clears the resolution cache. Primarily for testing.
  """
  @spec clear_cache() :: :ok
  def clear_cache do
    :persistent_term.put(@persistent_term_key, %{})
    :ok
  end

  # ----- Private: Resolution Strategies -----

  defp do_resolve(module_name) do
    case resolve_via_runtime(module_name) do
      {:ok, behaviours} when behaviours != [] ->
        behaviours

      _ ->
        case resolve_via_expansion(module_name) do
          {:ok, behaviours} -> behaviours
          _ -> []
        end
    end
  end

  # Strategy 1: Runtime query
  # Try to convert the module name to an atom, load it, and expand
  # `use Module` to discover @behaviour attributes.
  defp resolve_via_runtime(module_name) do
    case safe_to_module(module_name) do
      {:ok, module} ->
        if Code.ensure_loaded?(module) do
          # The module itself might be a behaviour
          own_behaviours =
            if function_exported?(module, :behaviour_info, 1) do
              [module_name]
            else
              []
            end

          # Expand `use Module` to find @behaviour attributes it injects
          expanded_behaviours = expand_use_for_behaviours(module)

          {:ok, Enum.uniq(own_behaviours ++ expanded_behaviours)}
        else
          {:error, :not_loaded}
        end

      {:error, _} ->
        {:error, :invalid_module}
    end
  end

  # Strategy 2: ExPanda expansion
  # Build a synthetic `use Module` AST and expand it.
  defp resolve_via_expansion(module_name) do
    ast = build_use_ast(module_name)

    case ExPanda.expand(ast) do
      {:ok, expanded} ->
        behaviours = extract_behaviours_from_ast(expanded)
        {:ok, behaviours}

      {:error, _reason} ->
        {:error, :expansion_failed}
    end
  rescue
    e ->
      Logger.debug("ElixirResolver expansion failed for #{module_name}: #{inspect(e)}")
      {:error, :expansion_error}
  end

  # Expand `use Module` via ExPanda and extract @behaviour attributes
  defp expand_use_for_behaviours(module) do
    ast = {:use, [line: 1], [{:__aliases__, [line: 1], module_to_aliases(module)}]}

    case ExPanda.expand(ast) do
      {:ok, expanded} ->
        extract_behaviours_from_ast(expanded)

      {:error, _} ->
        []
    end
  rescue
    _ -> []
  end

  # Walk expanded AST to find @behaviour attributes
  defp extract_behaviours_from_ast(ast) do
    {_, behaviours} =
      Macro.prewalk(ast, [], fn
        # @behaviour ModuleName
        {:@, _, [{:behaviour, _, [{:__aliases__, _, parts}]}]} = node, acc ->
          behaviour_name = parts |> Module.concat() |> Atom.to_string()
          {node, [behaviour_name | acc]}

        # @behaviour :erlang_module
        {:@, _, [{:behaviour, _, [atom_mod]}]} = node, acc when is_atom(atom_mod) ->
          {node, [Atom.to_string(atom_mod) | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.uniq(Enum.reverse(behaviours))
  end

  # Register a discovered behaviour and its callbacks
  defp register_discovered_behaviour(behaviour_name) do
    # Only register if not already known
    if behaviour_name not in Callbacks.behaviours_for_language(:elixir) do
      case safe_to_module(behaviour_name) do
        {:ok, module} ->
          BeamIntrospector.discover_and_register(module,
            language: :elixir,
            framework: behaviour_name_to_framework(behaviour_name),
            domain: nil
          )

        _ ->
          :ok
      end
    end
  end

  # Convert "GenServer" -> :genserver, "Phoenix.LiveView" -> :phoenix_live_view
  defp behaviour_name_to_framework(name) do
    name
    |> String.replace(".", "_")
    |> Macro.underscore()
    |> String.to_atom()
  end

  # Safely convert a string module name to an atom
  defp safe_to_module(name) when is_binary(name) do
    module =
      if String.starts_with?(name, ":") do
        name |> String.trim_leading(":") |> String.to_atom()
      else
        Module.concat([name])
      end

    {:ok, module}
  rescue
    _ -> {:error, :invalid_module}
  end

  # Build a use AST node from a module name string
  defp build_use_ast(module_name) do
    parts = String.split(module_name, ".") |> Enum.map(&String.to_atom/1)
    {:use, [line: 1], [{:__aliases__, [line: 1], parts}]}
  rescue
    _ -> {:use, [line: 1], [{:__aliases__, [line: 1], [String.to_atom(module_name)]}]}
  end

  # Convert module atom to alias parts for AST building
  defp module_to_aliases(module) when is_atom(module) do
    module
    |> Module.split()
    |> Enum.map(&String.to_atom/1)
  rescue
    # Erlang modules don't have Module.split
    _ -> [module]
  end

  # ----- Cache -----

  defp get_cache do
    :persistent_term.get(@persistent_term_key, %{})
  end

  defp put_cache(cache) do
    :persistent_term.put(@persistent_term_key, cache)
  end
end
