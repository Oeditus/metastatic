defmodule Metastatic.Subprocess do
  @moduledoc """
  Shared plumbing for the external-parser bridges.

  Every adapter that shells out (Python, JavaScript, Ruby, Java, March, SQL,
  Cure, Agda, Haskell) needs the same four steps:

  1. write the input to a uniquely named temp file,
  2. run the executable with that file as its last argument,
  3. treat a non-zero exit as an error,
  4. delete the temp file — **on every path, including exceptions**.

  Nine copies of that logic had drifted apart: some returned
  `inspect(error)` where others returned `"Type: message"`, some wrapped the
  call in `try/rescue` and some did not, and the temp-file prefix differed per
  adapter. This module is the single implementation.

  It deliberately does **not** decode JSON — the wire format differs per
  bridge (Python returns `{"ok": true, "ast": ...}`, Ruby returns a bare AST,
  March returns `{"ok": true, "source": ...}`), so decoding stays with the
  adapter.
  """

  @typedoc "Options accepted by `run/4`."
  @type option ::
          {:ext, String.t()}
          | {:cd, Path.t()}
          | {:env, [{String.t(), String.t()}]}
          | {:prefix, String.t()}

  @typedoc "A unique temp-file path plus the cleanup function for it."
  @type temp_file :: {Path.t(), (-> :ok)}

  @doc """
  Writes `input` to a unique temp file and returns its path.

  The caller is responsible for deleting it; prefer `with_temp_file/3`, which
  guarantees cleanup.

  ## Options

    * `:ext` — file extension (default `".tmp"`)
    * `:prefix` — filename prefix (default `"metastatic"`)

  ## Examples

      iex> path = Metastatic.Subprocess.write_temp_file("x + 1", ext: ".py")
      iex> File.read!(path)
      "x + 1"
      iex> File.rm(path)
      :ok
  """
  @spec write_temp_file(String.t(), keyword()) :: Path.t()
  def write_temp_file(input, opts \\ []) when is_binary(input) do
    ext = Keyword.get(opts, :ext, ".tmp")
    prefix = Keyword.get(opts, :prefix, "metastatic")

    path =
      Path.join(
        System.tmp_dir!(),
        "#{prefix}_#{System.unique_integer([:positive, :monotonic])}#{ext}"
      )

    File.write!(path, input)
    path
  end

  @doc """
  Runs `fun` with a fresh temp file and always removes it afterwards.

  ## Examples

      iex> Metastatic.Subprocess.with_temp_file("data", [], fn path ->
      ...>   {File.read!(path), File.exists?(path)}
      ...> end)
      {"data", true}
  """
  @spec with_temp_file(String.t(), keyword(), (Path.t() -> result)) :: result when result: term()
  def with_temp_file(input, opts, fun) when is_binary(input) and is_function(fun, 1) do
    path = write_temp_file(input, opts)

    try do
      fun.(path)
    after
      File.rm(path)
    end
  end

  @doc """
  Runs `executable` with `args ++ [temp_file]` and returns its stdout.

  A non-zero exit status is reported as `{:error, reason}` — never raised.
  `stderr` is folded into `stdout` so parser diagnostics reach the caller.

  ## Options

    * `:ext` — temp-file extension (default `".tmp"`)
    * `:prefix` — temp-file prefix (default `"metastatic"`)
    * `:cd` — working directory for the child process
    * `:env` — environment overrides (defaults to `Metastatic.Priv.subprocess_env/0`)

  ## Examples

      iex> Metastatic.Subprocess.run("cat", [], "hello", ext: ".txt")
      {:ok, "hello"}
  """
  @spec run(String.t(), [String.t()], String.t(), keyword()) ::
          {:ok, String.t()} | {:error, String.t()}
  def run(executable, args, input, opts \\ [])
      when is_binary(executable) and is_list(args) and is_binary(input) do
    with_temp_file(input, opts, fn path ->
      cmd_opts =
        [
          stderr_to_stdout: true,
          env: Keyword.get_lazy(opts, :env, &Metastatic.Priv.subprocess_env/0)
        ]
        |> maybe_put(:cd, Keyword.get(opts, :cd))

      case System.cmd(executable, args ++ [path], cmd_opts) do
        {output, 0} -> {:ok, output}
        {output, code} -> {:error, "Exit code #{code}: #{String.trim(output)}"}
      end
    end)
  rescue
    error -> {:error, "Failed to run #{Path.basename(executable)}: #{Exception.message(error)}"}
  end

  @doc """
  Formats a `%{"type" => ..., "msg" => ..., "lineno" => ...}` parser error.

  Bridges that report structured errors (Python, JavaScript, Java) share this
  shape; using one formatter keeps the messages identical across languages.

  ## Examples

      iex> Metastatic.Subprocess.format_error(%{"type" => "SyntaxError", "msg" => "bad", "lineno" => 3})
      "SyntaxError at line 3: bad"

      iex> Metastatic.Subprocess.format_error(%{"type" => "SyntaxError", "msg" => "bad"})
      "SyntaxError: bad"

      iex> Metastatic.Subprocess.format_error("plain")
      "plain"
  """
  @spec format_error(term()) :: String.t()
  def format_error(%{"type" => type, "msg" => msg, "lineno" => line}) when not is_nil(line) do
    "#{type} at line #{line}: #{msg}"
  end

  def format_error(%{"type" => type, "msg" => msg}), do: "#{type}: #{msg}"
  def format_error(error) when is_binary(error), do: error
  def format_error(error), do: inspect(error)

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
