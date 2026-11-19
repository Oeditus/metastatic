defmodule Metastatic.Adapters.Lfe.Reader do
  @moduledoc """
  Source ⇄ sexpr for LFE, using the LFE toolchain in-process.

  LFE (Lisp-Flavoured Erlang) ships its own reader as Erlang modules
  (`lfe_scan`, `lfe_parse`, `lfe_io`). They are **not** part of OTP, so this
  module is the single gate that decides whether LFE parsing is possible in
  the current VM, and the single place that knows how to reach them.

  ## Why a reader module at all

  Every other non-BEAM adapter needs a subprocess bridge (see
  `Metastatic.Adapter.Bridge`). LFE does not: its reader is ordinary BEAM
  code, so parsing is a function call. That makes this adapter the cheapest
  one in the library — no temp files, no JSON, no process spawn — but it also
  means the "toolchain missing" failure mode has to be handled explicitly
  here, because there is no `System.find_executable/1` to return `nil`.

  ## Resolution order

  `ensure_loaded/0` tries, in order:

    1. `:lfe_io` already loadable (LFE is on the code path — the normal case
       for a project that depends on LFE, or for a shell started with
       `-pa /path/to/lfe/ebin`);
    2. `Metastatic.Priv.parser_path("parsers/lfe/ebin")`, added with
       `Code.add_patha/1` — this is how a vendored copy of LFE is found
       without configuration;
    3. the `:lfe` application's own `priv`/`ebin` via `:code.lib_dir/1`.

  When none of those work the caller gets `{:error, reason}` naming the
  missing module and how to install LFE. Nothing raises.

  ## The M1 shape

  `lfe_io:parse_file/2` is the entry point. It returns a list of
  `{Sexpr, Line}` pairs — one per top-level form — which is exactly the M1
  shape `Metastatic.Adapters.Lfe.ToMeta` expects:

      [{[defmodule, demo, [export, [add, 2]]], 1},
       {[defun, add, [a, b], ['+', a, b]], 4}]

  A sexpr is a plain Erlang term: numbers and binaries are literals, atoms
  are symbols, and **lists are either calls or data** — the distinction is
  made by `ToMeta`, not here. Keeping the reader faithful to LFE's own terms
  is what makes the `:language_specific` escape hatch exact.

  ## Parsing from a string

  `lfe_io:parse_file/2` takes a path, so `parse/1` writes the source to a
  temp file through `Metastatic.Subprocess.with_temp_file/3`, which removes
  it on every path including exceptions.
  """

  alias Metastatic.Subprocess

  # LFE is an optional runtime toolchain, checked by ensure_loaded/0.
  @compile {:no_warn_undefined, {:lfe_io, :parse_file, 2}}

  @lfe_ebin_rel "parsers/lfe/ebin"
  @required_modules [:lfe_io, :lfe_scan, :lfe_parse, :lfe_comp]

  @typedoc "One parsed form: the sexpr and the line it started on."
  @type form :: {term(), pos_integer()}

  @doc """
  Parses LFE source into a list of `{sexpr, line}` forms.

  ## Examples

      iex> {:ok, [{[:defun, :add, [:a, :b], [:"+", :a, :b]], 1}]} =
      ...>   Metastatic.Adapters.Lfe.Reader.parse("(defun add (a b) (+ a b))")
      iex> true
      true

      iex> {:error, "LFE" <> _} = Metastatic.Adapters.Lfe.Reader.parse("(defun")
      iex> true
      true
  """
  @spec parse(String.t()) :: {:ok, [form()]} | {:error, String.t()}
  def parse(source) when is_binary(source) do
    with :ok <- ensure_loaded() do
      Subprocess.with_temp_file(source, [ext: ".lfe", prefix: "metastatic_lfe"], &do_parse/1)
    end
  end

  @doc """
  Returns `true` when the LFE reader is usable in this VM.

  ## Examples

      iex> is_boolean(Metastatic.Adapters.Lfe.Reader.available?())
      true
  """
  @spec available?() :: boolean()
  def available?, do: match?(:ok, ensure_loaded())

  @doc """
  Makes the LFE modules loadable, or explains why they are not.

  Idempotent: the happy path is `Code.ensure_loaded?/1` on an already-loaded
  module, which is a cheap ETS lookup.

  ## Examples

      iex> Metastatic.Adapters.Lfe.Reader.ensure_loaded()
      :ok
  """
  @spec ensure_loaded() :: :ok | {:error, String.t()}
  def ensure_loaded do
    if loaded?() do
      :ok
    else
      with :ok <- add_vendored_ebin() do
        if loaded?(), do: :ok, else: {:error, missing_message()}
      end
    end
  end

  # ----- Private -----

  defp loaded? do
    Enum.all?(@required_modules, &Code.ensure_loaded?/1)
  end

  defp add_vendored_ebin do
    path = Metastatic.Priv.parser_path(@lfe_ebin_rel)

    if File.dir?(path) do
      # `Code.prepend_path/1` returns `:ok` or `{:error, :bad_directory}`.
      # A failure is not fatal: LFE may already be on the code path.
      _ = Code.prepend_path(path)
      :ok
    else
      # Not vendored — fine, LFE may still be on the code path already.
      :ok
    end
  rescue
    _ -> :ok
  end

  defp do_parse(path) do
    # `lfe_io:parse_file/2` accepts a charlist path and a starting line number.
    # It returns `{:ok, Forms}` on success and `{:error, Reason}` otherwise.
    case :lfe_io.parse_file(String.to_charlist(path), 1) do
      {:ok, forms} when is_list(forms) -> {:ok, normalize_forms(forms)}
      {:error, reason} -> {:error, format_error(reason)}
    end
  catch
    # LFE's reader throws on some malformed inputs rather than returning an
    # error tuple (e.g. an unbalanced `#(`). A throw must not escape.
    {:lfe_error, reason} -> {:error, format_error(reason)}
    error -> {:error, "LFE reader crashed: #{inspect(error, limit: 5)}"}
  end

  # LFE returns `[{Sexpr, Line}]`; anything else (a bare sexpr from a
  # different entry point) is wrapped so the rest of the adapter sees one
  # uniform shape.
  defp normalize_forms([{_sexpr, line} | _] = forms) when is_integer(line), do: forms
  defp normalize_forms(forms), do: Enum.map(forms, &{&1, 1})

  defp format_error({line, module, description}) when is_integer(line) do
    "LFE parse error at line #{line}: #{describe(module, description)}"
  end

  defp format_error({module, description}) when is_atom(module) do
    "LFE parse error: #{describe(module, description)}"
  end

  defp format_error(reason), do: "LFE parse error: #{inspect(reason, limit: 5)}"

  # `lfe_parse:format_error/1` renders the reader's error descriptions in
  # English ("unexpected end of input", ...). Fall back to `inspect/1` when
  # the module cannot describe the reason.
  defp describe(module, description) do
    if is_atom(module) and Code.ensure_loaded?(module) and
         function_exported?(module, :format_error, 1) do
      module.format_error(description) |> to_string()
    else
      inspect(description, limit: 5)
    end
  rescue
    _ -> inspect(description, limit: 5)
  end

  defp missing_message do
    missing =
      @required_modules
      |> Enum.reject(&Code.ensure_loaded?/1)
      |> Enum.map_join(", ", &inspect/1)

    """
    LFE toolchain unavailable: #{missing} not loadable.

    LFE is not part of OTP. Install it with one of:

        git clone https://github.com/lfe/lfe.git && cd lfe && make
        rebar3 as prod compile            # in an LFE project

    then put its `ebin` on the code path (`elixir -pa /path/to/lfe/ebin`), or
    vendor it at `priv/parsers/lfe/ebin` inside the host application.
    """
    |> String.trim()
  end
end
