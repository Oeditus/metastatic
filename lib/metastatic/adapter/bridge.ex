defmodule Metastatic.Adapter.Bridge do
  @moduledoc """
  Behaviour and shared decoding for out-of-process parser bridges.

  Most language adapters cannot parse their language in the BEAM and shell out
  to a parser written in that language (Python's `ast`, Babel, Ruby's
  `parser`, `sqlparser-rs`, GHC, …). Every one of those bridges speaks the
  same protocol:

  1. the adapter writes the input to a temp file (`Metastatic.Subprocess`),
  2. the bridge process reads it and writes **one JSON object** to stdout,
  3. a non-zero exit status is an error.

  This module formalises step 2 and 3. It exists because nine adapters had
  grown nine slightly different `decode/1` implementations, each handling a
  different subset of the response shapes below — so a bridge that returned
  `{"status": "ok"}` to a decoder expecting `{"ok": true}` failed with
  `"Unexpected parser output"` instead of anything useful.

  ## Response shapes

  All shapes seen in the wild are accepted by `decode/1`:

      # Canonical (Python, JavaScript, Ruby, Java, SQL, March, Cure)
      {"ok": true, "ast": {...}}
      {"ok": true, "source": "..."}
      {"ok": false, "error": "..."}
      {"ok": false, "error": {"type": "SyntaxError", "msg": "...", "line": 3}}

      # Legacy `status` envelope (Haskell, Agda)
      {"status": "ok", "ast": {...}}
      {"status": "error", "errorMessage": "..."}

  ## Writing a bridge

  Implementing the behaviour is optional — an adapter may call `decode/1`
  directly — but it documents the contract and lets `Bridge` provide the
  `run/4` plumbing:

      defmodule MyApp.Adapters.Rust.Bridge do
        @behaviour Metastatic.Adapter.Bridge

        @impl true
        def parse(source), do: run("parse", source, ".rs")

        @impl true
        def unparse(ast), do: run("unparse", encode!(ast), ".json")

        defp run(mode, input, ext) do
          executable = Metastatic.Priv.find_executable("metastatic-rust-bridge")
          script = Metastatic.Priv.parser_path("parsers/rust/bridge")

          with {:ok, executable} <- require_executable(executable),
               {:ok, output} <-
                 Metastatic.Subprocess.run(executable, [script, mode], input,
                   ext: ext,
                   prefix: "metastatic_rust"
                 ) do
            decode(output)
          end
        end
      end

  ## Error contract

  Neither `decode/1` nor `run/4` raises or hangs. A missing toolchain, a
  malformed response and a non-zero exit all come back as `{:error, reason}`
  with a human-readable `reason`, matching the rest of the library.
  """

  alias Metastatic.Subprocess

  @typedoc """
  A decoded bridge response: either the native AST (M1) or generated source.
  """
  @type response :: {:ok, term()} | {:error, String.t()}

  @doc """
  Parse source into the bridge's native AST (M1).

  Must return `{:error, reason}` — never raise — when the language toolchain
  is unavailable.
  """
  @callback parse(String.t()) :: {:ok, term()} | {:error, String.t()}

  @doc """
  Render a native AST (M1) back to source.

  Must return `{:error, reason}` — never raise — when the language toolchain
  is unavailable.
  """
  @callback unparse(term()) :: {:ok, String.t()} | {:error, String.t()}

  @optional_callbacks parse: 1, unparse: 1

  # ----- Decoding -----

  @doc """
  Decodes a bridge's stdout into `{:ok, value}` or `{:error, reason}`.

  Accepts every response shape documented in the module docs. The returned
  value is the `"ast"` or `"source"` payload, so callers do not need to
  destructure the envelope themselves.

  A response that is valid JSON but carries neither payload is treated as an
  error rather than silently returning `nil` — a bridge that emits
  `{"ok": true, "ast": null}` (Agda does this for empty input) must not look
  like a successful parse of the atom `nil`.

  ## Examples

      iex> Metastatic.Adapter.Bridge.decode(~s({"ok": true, "ast": {"type": "File"}}))
      {:ok, %{"type" => "File"}}

      iex> Metastatic.Adapter.Bridge.decode(~s({"ok": true, "source": "x + 5"}))
      {:ok, "x + 5"}

      iex> Metastatic.Adapter.Bridge.decode(~s({"ok": false, "error": "boom"}))
      {:error, "boom"}

      iex> Metastatic.Adapter.Bridge.decode(~s({"ok": false, "error": {"type": "SyntaxError", "msg": "bad", "line": 3}}))
      {:error, "SyntaxError at line 3: bad"}

      iex> Metastatic.Adapter.Bridge.decode(~s({"status": "ok", "ast": {"k": 1}}))
      {:ok, %{"k" => 1}}

      iex> Metastatic.Adapter.Bridge.decode(~s({"status": "error", "errorMessage": "nope"}))
      {:error, "nope"}

      iex> Metastatic.Adapter.Bridge.decode("not json")
      {:error, "JSON decode failed: " <> _}

      iex> Metastatic.Adapter.Bridge.decode(~s({"ok": true, "ast": null}))
      {:error, "Parser returned an empty AST"}
  """
  @spec decode(String.t()) :: response()
  def decode(output) when is_binary(output) do
    case Jason.decode(output) do
      {:ok, decoded} -> decode_map(decoded)
      {:error, reason} -> {:error, "JSON decode failed: #{inspect(reason)}"}
    end
  end

  defp decode_map(%{"ok" => false} = decoded) do
    {:error, format_error(Map.get(decoded, "error", "parser reported failure"))}
  end

  defp decode_map(%{"ok" => true} = decoded) do
    extract_payload(decoded)
  end

  defp decode_map(%{"status" => "error"} = decoded) do
    message = Map.get(decoded, "errorMessage") || Map.get(decoded, "error") || "parse error"
    {:error, format_error(message)}
  end

  defp decode_map(%{"status" => "ok"} = decoded) do
    extract_payload(decoded)
  end

  # A bridge may emit a bare payload with no envelope at all (Cure's CLI does).
  defp decode_map(%{"ast" => _} = decoded), do: extract_payload(decoded)
  defp decode_map(%{"source" => _} = decoded), do: extract_payload(decoded)

  defp decode_map(decoded) when is_binary(decoded), do: {:ok, decoded}

  defp decode_map(other) do
    {:error, "Unexpected parser output: #{inspect(other, limit: 5)}"}
  end

  defp extract_payload(%{"ast" => nil}), do: {:error, "Parser returned an empty AST"}
  defp extract_payload(%{"ast" => ast}), do: {:ok, ast}
  defp extract_payload(%{"source" => source}), do: {:ok, source}

  defp extract_payload(other) do
    {:error, "Parser response carried no AST or source: #{inspect(other, limit: 5)}"}
  end

  # ----- Formatting -----

  @doc """
  Formats a structured bridge error into a human-readable string.

  Bridges report errors as a plain string, or as a map with `"type"`, `"msg"`
  and an optional `"line"`/`"lineno"`. Both are normalised here so every
  adapter produces the same message for the same failure.

  ## Examples

      iex> Metastatic.Adapter.Bridge.format_error("boom")
      "boom"

      iex> Metastatic.Adapter.Bridge.format_error(%{"type" => "SyntaxError", "msg" => "bad", "line" => 3})
      "SyntaxError at line 3: bad"

      iex> Metastatic.Adapter.Bridge.format_error(%{"type" => "SyntaxError", "msg" => "bad"})
      "SyntaxError: bad"

      iex> Metastatic.Adapter.Bridge.format_error(%{"error" => "bad", "line" => 7})
      "bad at line 7"

      iex> Metastatic.Adapter.Bridge.format_error(:enoent)
      ":enoent"
  """
  @spec format_error(term()) :: String.t()
  def format_error(error) when is_binary(error), do: error
  def format_error(error) when is_atom(error), do: inspect(error)

  def format_error(%{} = error) do
    type = Map.get(error, "type")
    msg = Map.get(error, "msg") || Map.get(error, "error") || Map.get(error, "errorMessage")
    line = Map.get(error, "line") || Map.get(error, "lineno")

    cond do
      is_binary(type) and is_binary(msg) and not is_nil(line) -> "#{type} at line #{line}: #{msg}"
      is_binary(type) and is_binary(msg) -> "#{type}: #{msg}"
      is_binary(msg) and not is_nil(line) -> "#{msg} at line #{line}"
      is_binary(msg) -> msg
      true -> inspect(error)
    end
  end

  def format_error(error), do: inspect(error)

  # ----- Execution -----

  @doc """
  Runs a bridge executable and decodes its output.

  `args ++ [temp_file]` is the argv the child receives, matching the
  convention every existing bridge already uses. Temp-file creation, exit-code
  handling and cleanup are delegated to `Metastatic.Subprocess.run/4`, so a
  crash in the child cannot leak a temp file.

  ## Options

  Accepts everything `Metastatic.Subprocess.run/4` accepts (`:ext`, `:prefix`,
  `:cd`, `:env`).

  ## Examples

      iex> Metastatic.Adapter.Bridge.run("cat", [], ~s({"ok": true, "ast": 1}), ext: ".json")
      {:ok, 1}

      iex> Metastatic.Adapter.Bridge.run("/nonexistent/bridge", [], "x")
      {:error, "Failed to run bridge: " <> _}
  """
  @spec run(String.t(), [String.t()], String.t(), keyword()) :: response()
  def run(executable, args, input, opts \\ [])

  def run(executable, args, input, opts)
      when is_binary(executable) and is_list(args) and is_binary(input) do
    case Subprocess.run(executable, args, input, opts) do
      {:ok, output} ->
        decode(output)

      # `Subprocess.run/4` already prefixes its own failures ("Failed to run
      # …", "Exit code N: …"), so re-prefixing here produced the doubled
      # message "Bridge failed: Failed to run bridge: …".
      {:error, reason} ->
        {:error, reason}
    end
  rescue
    error -> {:error, "Failed to run bridge: #{Exception.message(error)}"}
  end

  @doc """
  Guards a bridge against a missing toolchain.

  Returns `{:ok, executable}` when it is a binary, or a uniform
  `{:error, reason}` naming the executable and the language, so every adapter
  fails with the same wording instead of nine different ones.

  ## Examples

      iex> Metastatic.Adapter.Bridge.require_executable("/bin/sh", :rust)
      {:ok, "/bin/sh"}

      iex> Metastatic.Adapter.Bridge.require_executable(nil, :rust)
      {:error, "rust parser unavailable: no rust executable found on PATH"}
  """
  @spec require_executable(String.t() | nil, atom()) :: {:ok, String.t()} | {:error, String.t()}
  def require_executable(executable, _language) when is_binary(executable),
    do: {:ok, executable}

  def require_executable(nil, language) when is_atom(language) do
    {:error, "#{language} parser unavailable: no #{language} executable found on PATH"}
  end

  @doc """
  Encodes a native AST (M1) for transmission to an unparser bridge.

  ## Examples

      iex> Metastatic.Adapter.Bridge.encode(%{"type" => "File"})
      {:ok, ~s({"type":"File"})}

      iex> {:error, "JSON encode failed: " <> _} = Metastatic.Adapter.Bridge.encode({:not, :encodable})
      iex> true
      true
  """
  @spec encode(term()) :: {:ok, String.t()} | {:error, String.t()}
  def encode(ast) do
    {:ok, Jason.encode!(ast)}
  rescue
    error -> {:error, "JSON encode failed: #{Exception.message(error)}"}
  end
end
