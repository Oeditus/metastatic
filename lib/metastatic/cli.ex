defmodule Metastatic.CLI do
  @moduledoc """
  Shared utilities for Metastatic CLI commands.

  Provides common functionality for Mix tasks including:
  - Adapter lookup by language or file extension
  - File path handling
  - Error formatting
  - Success/error reporting
  """

  @type language :: atom()
  @type file_path :: String.t()

  @doc """
  Get adapter for a given language.

  ## Examples

      iex> Metastatic.CLI.get_adapter(:python)
      {:ok, Metastatic.Adapters.Python}

      iex> Metastatic.CLI.get_adapter(:unknown)
      {:error, "Unsupported language: unknown"}
  """
  @spec get_adapter(language()) :: {:ok, module()} | {:error, String.t()}
  def get_adapter(:python), do: {:ok, Metastatic.Adapters.Python}
  def get_adapter(:elixir), do: {:ok, Metastatic.Adapters.Elixir}
  def get_adapter(:erlang), do: {:ok, Metastatic.Adapters.Erlang}

  def get_adapter(lang) do
    {:error, "Unsupported language: #{lang}. Supported: python, elixir, erlang"}
  end

  @doc """
  Detect language from file extension.

  ## Examples

      iex> Metastatic.CLI.detect_language("foo.py")
      {:ok, :python}

      iex> Metastatic.CLI.detect_language("foo.ex")
      {:ok, :elixir}

      iex> Metastatic.CLI.detect_language("foo.erl")
      {:ok, :erlang}

      iex> Metastatic.CLI.detect_language("foo.txt")
      {:error, "Cannot detect language from extension: .txt"}
  """
  @spec detect_language(file_path()) :: {:ok, language()} | {:error, String.t()}
  def detect_language(path) do
    case Path.extname(path) do
      ".py" -> {:ok, :python}
      ".ex" -> {:ok, :elixir}
      ".exs" -> {:ok, :elixir}
      ".erl" -> {:ok, :erlang}
      ".hrl" -> {:ok, :erlang}
      ext -> {:error, "Cannot detect language from extension: #{ext}"}
    end
  end

  @doc """
  Read file contents.

  ## Examples

      iex> Metastatic.CLI.read_file("test.py")
      {:ok, "print('hello')"}

      iex> Metastatic.CLI.read_file("nonexistent.py")
      {:error, "Cannot read file test.py: enoent"}
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

      iex> Metastatic.CLI.write_file("output/test.py", "print('hello')")
      :ok
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
  Print error and exit with status code 1.
  """
  @spec fatal(String.t()) :: no_return()
  def fatal(message) do
    Mix.shell().error(format_error(message))
    exit({:shutdown, 1})
  end
end
