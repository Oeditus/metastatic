defmodule Metastatic.Languages.Discovery do
  @moduledoc """
  Compile-time discovery of language adapters.

  Scans `lib/metastatic/adapters/` for modules declaring
  `@behaviour Metastatic.Adapter` and returns `{language_atom, module}` pairs.

  This lives in its own module (rather than private functions on
  `Metastatic.Languages`) because `Metastatic.Languages` evaluates the registry
  in a module attribute, which runs *before* the module's own `defp`s are
  available. A separate module can be compiled and called first.

  The discovery is intentionally source-scanning rather than
  `Mix.Project`-based: `Mix` is not guaranteed to be available in every build
  context (releases, escripts), while the source files are always present at
  compile time.
  """

  @adapters_dir Path.expand("../adapters", __DIR__)

  @doc """
  Returns the list of `{language_atom, adapter_module}` pairs discovered under
  the adapters directory.

  The language atom is derived from the module's last segment, underscored and
  downcased (`Metastatic.Adapters.TypeScript` -> `:typescript`).
  """
  @spec discover() :: [{atom(), module()}]
  def discover do
    case File.ls(@adapters_dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".ex"))
        |> Enum.flat_map(&discover_file/1)
        |> Enum.uniq_by(fn {lang, _mod} -> lang end)

      {:error, _} ->
        []
    end
  end

  defp discover_file(file) do
    path = Path.join(@adapters_dir, file)

    case File.read(path) do
      {:ok, source} ->
        if String.contains?(source, "@behaviour Metastatic.Adapter") do
          module = module_name(source, file)
          [{language_for(module), module}]
        else
          []
        end

      {:error, _} ->
        []
    end
  end

  defp module_name(source, file) do
    case Regex.run(~r/defmodule\s+(Metastatic\.Adapters\.[A-Za-z0-9_.]+)\s+do/, source) do
      [_, name] -> Module.concat([name])
      _ -> Module.concat([Metastatic.Adapters, Macro.camelize(Path.rootname(file))])
    end
  end

  defp language_for(module) do
    module
    |> Module.split()
    |> List.last()
    |> String.downcase()
    |> String.to_atom()
  end
end
