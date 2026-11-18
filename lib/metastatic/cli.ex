defmodule Metastatic.CLI do
  @moduledoc """
  Shared utilities for Metastatic CLI commands.

  Provides common functionality for Mix tasks including:
  - Adapter lookup by language or file extension
  - File path handling
  - Error formatting
  - Success/error reporting
  """

  alias Metastatic.Languages

  @type language :: atom()
  @type file_path :: String.t()

  @doc """
  Get adapter for a given language.

  Delegates to `Metastatic.Languages.get_adapter/1`.

  ## Examples

      iex> Metastatic.CLI.get_adapter(:python)
      {:ok, Metastatic.Adapters.Python}

      iex> {:error, message} = Metastatic.CLI.get_adapter(:unknown)
      iex> message =~ "Unsupported language: unknown"
      true
  """
  @spec get_adapter(language()) :: {:ok, module()} | {:error, String.t()}
  defdelegate get_adapter(language), to: Languages

  @doc """
  Detect language from file extension.

  Delegates to `Metastatic.Languages.detect_language/1`.

  ## Examples

      iex> Metastatic.CLI.detect_language("foo.py")
      {:ok, :python}

      iex> Metastatic.CLI.detect_language("foo.ex")
      {:ok, :elixir}

      iex> Metastatic.CLI.detect_language("foo.erl")
      {:ok, :erlang}

      iex> Metastatic.CLI.detect_language("foo.rb")
      {:ok, :ruby}

      iex> Metastatic.CLI.detect_language("foo.txt")
      {:error, "Cannot detect language from extension: .txt"}
  """
  @spec detect_language(file_path()) :: {:ok, language()} | {:error, String.t()}
  defdelegate detect_language(path), to: Languages

  @doc """
  Parse a language string from CLI options into an atom.

  Delegates to `Metastatic.Languages.parse_language/1`.

  ## Examples

      iex> Metastatic.CLI.parse_language("python")
      {:ok, :python}

      iex> Metastatic.CLI.parse_language(nil)
      :none

      iex> {:error, message} = Metastatic.CLI.parse_language("brainfuck")
      iex> message =~ "Invalid language: brainfuck"
      true
  """
  @spec parse_language(String.t() | nil) :: {:ok, atom()} | {:error, String.t()} | :none
  defdelegate parse_language(lang_str), to: Languages

  @doc """
  Read file contents.

  ## Examples

      iex> path = Path.join(System.tmp_dir!(), "cli_read_file_doc.py")
      iex> File.write!(path, "print('hello')")
      iex> Metastatic.CLI.read_file(path)
      {:ok, "print('hello')"}
      iex> File.rm!(path)
      :ok

      iex> {:error, message} = Metastatic.CLI.read_file("nonexistent.py")
      iex> message =~ "Cannot read file nonexistent.py"
      true
  """
  @spec read_file(file_path()) :: {:ok, String.t()} | {:error, String.t()}
  def read_file(path) do
    case File.read(path) do
      {:ok, content} -> {:ok, content}
      {:error, reason} -> {:error, "Cannot read file #{path}: #{reason}"}
    end
  end

  @doc """
  Write file contents, creating directories if needed.

  ## Examples

      iex> base = Path.join(System.tmp_dir!(), "cli_write_file_doc")
      iex> path = Path.join(base, "nested/test.py")
      iex> Metastatic.CLI.write_file(path, "print('hello')")
      :ok
      iex> File.read!(path)
      "print('hello')"
      iex> File.rm_rf!(base) |> is_list()
      true
  """
  @spec write_file(file_path(), String.t()) :: :ok | {:error, String.t()}
  def write_file(path, content) do
    case File.mkdir_p(Path.dirname(path)) do
      :ok ->
        case File.write(path, content) do
          :ok -> :ok
          {:error, reason} -> {:error, "Cannot write file #{path}: #{reason}"}
        end

      {:error, reason} ->
        {:error, "Cannot create directory for #{path}: #{reason}"}
    end
  end

  @doc """
  Format error message for CLI output.

  Prefixes with red "Error: " for terminal output.
  """
  @spec format_error(String.t()) :: String.t()
  def format_error(message) do
    IO.ANSI.format([:red, :bright, "Error: ", :reset, message]) |> IO.iodata_to_binary()
  end

  @doc """
  Format success message for CLI output.

  Prefixes with green checkmark for terminal output.
  """
  @spec format_success(String.t()) :: String.t()
  def format_success(message) do
    IO.ANSI.format([:green, :bright, "✓ ", :reset, message]) |> IO.iodata_to_binary()
  end

  @doc """
  Format info message for CLI output.

  Prefixes with blue info icon for terminal output.
  """
  @spec format_info(String.t()) :: String.t()
  def format_info(message) do
    IO.ANSI.format([:blue, :bright, "→ ", :reset, message]) |> IO.iodata_to_binary()
  end

  @doc """
  Print a task's `@moduledoc` (its usage block) and abort with status 0.

  Every `mix metastatic.*` task accepts `--help`/`-h`; without this the only way
  to read the option list was to open the source or run the task with bad
  arguments and read the resulting error.

  """
  @spec help(module()) :: no_return()
  def help(task_module) do
    {:docs_v1, _, _, _, moduledoc, _, _} = Code.fetch_docs(task_module)
    text = Map.get(moduledoc, "en", "No documentation available.")

    Mix.shell().info(text)
    exit({:shutdown, 0})
  end

  @doc """
  Returns true when the argv contains `--help` or `-h`.

  ## Examples

      iex> Metastatic.CLI.help_requested?(["--help"])
      true

      iex> Metastatic.CLI.help_requested?(["file.py"])
      false
  """
  @spec help_requested?([String.t()]) :: boolean()
  def help_requested?(args), do: Enum.any?(args, &(&1 in ["--help", "-h"]))

  @doc """
  Render an error reason for human consumption.

  Adapters report errors as plain strings, as `{:error, string}` tuples, or as
  structured terms. Wrapping a readable string in `inspect/1` produced
  `{:error, "Syntax error at line 1"}` in CLI output — Erlang term syntax
  around an already-human message. This unwraps the common shapes and only
  falls back to `inspect/1` for genuinely opaque terms.

  ## Examples

      iex> Metastatic.CLI.format_reason("boom")
      "boom"

      iex> Metastatic.CLI.format_reason({:error, "boom"})
      "boom"

      iex> Metastatic.CLI.format_reason({:error, :enoent})
      ":enoent"

      iex> Metastatic.CLI.format_reason(%{code: 1})
      "%{code: 1}"
  """
  @spec format_reason(term()) :: String.t()
  def format_reason(reason) when is_binary(reason), do: reason
  def format_reason({:error, reason}), do: format_reason(reason)
  def format_reason(reason) when is_atom(reason), do: inspect(reason)
  def format_reason(reason), do: inspect(reason)

  @doc """
  Print an error and abort the current Mix task with a non-zero exit status.

  Uses `exit({:shutdown, code})` so that callers and tests can observe the
  failure via `catch_exit/1`, matching Mix's own task-failure convention.

  ## Exit codes

    * `1` (default) — the task ran but the operation failed
    * `2` — usage error: a bad flag, a missing argument, an unknown language

  Distinguishing the two lets a script tell "your input was wrong" from
  "the input was fine but the work failed".

  ## Examples

      iex> catch_exit(Metastatic.CLI.fatal("boom"))
      {:shutdown, 1}

      iex> catch_exit(Metastatic.CLI.fatal("boom", 2))
      {:shutdown, 2}
  """

  @spec fatal(String.t()) :: no_return()
  @spec fatal(String.t(), pos_integer()) :: no_return()
  def fatal(message, code \\ 1) do
    Mix.shell().error(format_error(message))
    exit({:shutdown, code})
  end
end
