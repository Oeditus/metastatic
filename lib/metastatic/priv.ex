defmodule Metastatic.Priv do
  @moduledoc """
  Utilities for resolving parser assets in `priv/` and locating runtime executables
  (including `mise` shims and global tool installations) across development,
  dependency, and OTP release environments.

  ## Third-party adapters

  A language adapter shipped from a *host* application (rather than compiled
  into Metastatic) keeps its parser scripts in **its own** `priv/` directory.
  `parser_path/1` therefore searches the host application's `priv` as well:

    * the `:metastatic` application `priv`
    * the compile-time source `priv` (so the library works from `deps/`)
    * any directory listed in `config :metastatic, :priv_dirs`
    * the `:ragex` application `priv`, when Ragex is loaded
    * **the host application's `priv`**, when `:metastatic` is a dependency
    * the current working directory's `priv`

  The host application is discovered from the `:metastatic` dependency's
  `mix.exs`-recorded parent, so an adapter can call
  `Priv.parser_path("parsers/rust/parser")` and get
  `my_app/priv/parsers/rust/parser` with no configuration.

  Hosts that need to point at a non-standard location (a release, a mounted
  volume, a build artefact) can always set `config :metastatic, :priv_dirs`.
  """

  @compile_time_priv Path.expand("../../priv", __DIR__)

  @doc """
  Resolves a path relative to `priv/` (such as `"parsers/javascript/parser.js"`
  or `"priv/parsers/javascript/parser.js"`).

  Searches the candidate `priv` directories documented in the module
  documentation and returns the first existing match. When nothing exists,
  returns the first candidate anyway so that the caller's `File.exists?/1`
  check produces an error message naming a real, predictable path.
  """
  @spec parser_path(String.t()) :: String.t()
  def parser_path(relative_path) when is_binary(relative_path) do
    rel = String.replace_prefix(relative_path, "priv/", "")

    candidates =
      priv_dir_candidates()
      |> Enum.map(&Path.join(&1, rel))

    Enum.find(
      candidates,
      List.first(candidates) || Path.join(File.cwd!(), relative_path),
      &File.exists?/1
    )
  end

  @doc """
  Finds an executable by name, checking `System.find_executable/1` as well as
  standard `mise` shim and user-local binary directories.
  """
  @spec find_executable(String.t()) :: String.t() | nil
  def find_executable(name) when is_binary(name) do
    case System.find_executable(name) do
      path when is_binary(path) ->
        path

      nil ->
        home = System.user_home() || ""

        [
          Path.join([home, ".local", "share", "mise", "shims", name]),
          Path.join([home, ".local", "bin", name]),
          Path.join(["/usr", "local", "bin", name]),
          Path.join(["/usr", "bin", name])
        ]
        |> Enum.find(&(File.exists?(&1) and not File.dir?(&1)))
    end
  end

  @doc """
  Builds environment variables for subprocess execution.

  By default this augments `PATH` with the `mise` shims directory and
  `~/.local/bin`, and `NODE_PATH` with the `mise` global `node_modules`.
  These defaults exist to make the subprocess bridges work out of the box on
  developer machines that use `mise`.

  Host applications can override or replace this entirely with:

      config :metastatic, :subprocess_env, [{"PATH", "/my/path"}]

  When `:subprocess_env` is configured, it is used **verbatim** (the caller's
  `extra` entries are still merged on top).
  """
  @spec subprocess_env([{String.t(), String.t()}]) :: [{String.t(), String.t()}]
  def subprocess_env(extra \\ []) when is_list(extra) do
    base_env =
      case Application.get_env(:metastatic, :subprocess_env) do
        nil -> default_subprocess_env()
        configured when is_list(configured) -> configured
      end

    Enum.reduce(extra, base_env, fn {k, v}, acc ->
      List.keystore(acc, k, 0, {k, v})
    end)
  end

  defp default_subprocess_env do
    home = System.user_home() || ""
    mise_shims = Path.join([home, ".local", "share", "mise", "shims"])
    local_bin = Path.join([home, ".local", "bin"])
    current_path = System.get_env("PATH") || "/usr/local/bin:/usr/bin:/bin"

    augmented_path =
      [mise_shims, local_bin, current_path]
      |> Enum.reject(&(&1 == ""))
      |> Enum.join(":")

    mise_node_modules =
      Path.join([
        home,
        ".local",
        "share",
        "mise",
        "installs",
        "node",
        "latest",
        "lib",
        "node_modules"
      ])

    current_node_path = System.get_env("NODE_PATH")

    node_path_parts =
      [current_node_path, mise_node_modules]
      |> Enum.reject(&(is_nil(&1) or &1 == ""))

    base_env = [{"PATH", augmented_path}]

    case node_path_parts do
      [] -> base_env
      parts -> [{"NODE_PATH", Enum.join(parts, ":")} | base_env]
    end
  end

  defp priv_dir_candidates do
    # `Application.get_env/2` can legitimately return `nil` (a config file that
    # sets the key to nil, or a test that restores a previous nil), so this
    # must not assume a list.
    configured =
      case Application.get_env(:metastatic, :priv_dirs) do
        dirs when is_list(dirs) -> dirs
        _ -> []
      end

    ([app_priv_dir(:metastatic), @compile_time_priv] ++
       configured ++
       [app_priv_dir(:ragex), host_app_priv_dir(), Path.join(File.cwd!(), "priv")])
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  # The `priv` directory of the application that depends on `:metastatic`.
  #
  # `:code.priv_dir/1` needs an *application* name, and a third-party adapter
  # has no way to tell us which application it belongs to. Instead we read the
  # `:metastatic` dependency entry that Mix records in the host's own
  # application spec: `Application.spec(:my_app, :applications)` lists
  # `:metastatic` exactly when `my_app` depends on it. The first such
  # application (excluding Metastatic and Ragex themselves) is the host.
  #
  # This is deliberately best-effort: in a release, an escript, or a bare
  # `elixir -pa` invocation there may be no host application at all, in which
  # case we simply contribute no candidate and the other directories win.
  defp host_app_priv_dir do
    :metastatic
    |> Application.spec(:applications)
    |> List.wrap()
    |> Enum.reject(&(&1 in [:kernel, :stdlib, :elixir, :metastatic, :ragex]))
    |> Enum.find_value(fn app ->
      case app_priv_dir(app) do
        nil -> nil
        dir -> if File.dir?(dir), do: dir, else: nil
      end
    end)
  end

  defp app_priv_dir(app) do
    case :code.priv_dir(app) do
      {:error, _} -> nil
      dir when is_list(dir) -> List.to_string(dir)
    end
  end
end
