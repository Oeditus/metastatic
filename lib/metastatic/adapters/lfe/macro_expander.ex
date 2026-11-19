defmodule Metastatic.Adapters.Lfe.MacroExpander do
  @moduledoc """
  Macro expansion for the LFE adapter, using LFE's own compiler.

  LFE is a Lisp, so essentially every construct above a function call —
  `defun`, `defmodule`, `let`, `case`, `lc`, `receive`, `try` — is a macro
  that expands into a small core language. Analysing the *surface* sexpr
  therefore sees `[:defun, …]` where the program actually contains a
  `lambda` bound with `set`, and an `op_kind`-bearing call written inside a
  `let` body is invisible to a naive walk.

  `expand/2` runs the surface forms through `lfe_comp:forms/2` with
  `[to_core, return]` and returns the resulting **Core Erlang** module. That
  is the fully expanded program: every macro resolved, every `let`/`case`/
  comprehension lowered.

  ## What Core Erlang is, and is not

  Core Erlang is *not* a MetaAST layer and must never be used as one. It is
  a compiler IR, and `lfe_comp` adds compiler-generated functions
  (`__info__/1`, `module_info/0,1`, `LFE-EXPAND-EXPORTED-MACRO/3`) that have
  no source counterpart. The module documentation of
  `Metastatic.Adapters.Lfe` explains the intended use: `expand_macros: true`
  gives analyzers a *second, lossy* view for semantic detection, while the
  default surface view remains the round-trippable one.

  ## Failure is not fatal

  Expansion fails for code that does not compile (an undefined function, a
  missing `include-file`). The adapter treats that as "no expansion
  available" and falls back to the surface forms — the same discipline
  `Metastatic.Adapters.Elixir` uses when ExPanda fails.

  ## Examples

      iex> {:ok, core} = Metastatic.Adapters.Lfe.MacroExpander.expand([{[:defun, :f, [], [1]], 1}])
      iex> elem(core, 0)
      :c_module

      iex> {:error, _} = Metastatic.Adapters.Lfe.MacroExpander.expand([{[:defun, :f], 1}])
      iex> true
      true
  """

  alias Metastatic.Adapters.Lfe.Reader

  # LFE is optional; expansion checks availability before invoking its compiler.
  @compile {:no_warn_undefined, {:lfe_comp, :forms, 2}}

  @doc """
  Expands every macro in `forms`, returning the Core Erlang module.

  `forms` is the reader's output: a list of `{sexpr, line}` pairs. Returns
  `{:ok, core_module}` or `{:error, reason}`; it never raises.

  ## Options

    * `:module` — module name to use when the forms contain no `defmodule`
      (default: `:metastatic_lfe_expansion`). LFE requires a module name to
      build a Core module, and a bare expression has none.

  ## Examples

      iex> {:ok, core} = Metastatic.Adapters.Lfe.MacroExpander.expand([{[:defun, :f, [], [1]], 1}], module: :demo)
      iex> elem(core, 2)
      {:c_literal, [], :demo}
  """
  @spec expand([{term(), integer()}] | term(), keyword()) ::
          {:ok, term()} | {:error, String.t()}
  def expand(forms, opts \\ [])

  def expand([{_sexpr, line} | _] = forms, opts) when is_integer(line) do
    sexprs = Enum.map(forms, fn {sexpr, _line} -> sexpr end)
    do_expand(sexprs, opts)
  end

  def expand(sexpr, opts), do: do_expand(List.wrap(sexpr), opts)

  @doc """
  Returns `true` when LFE's compiler is usable in this VM.

  ## Examples

      iex> is_boolean(Metastatic.Adapters.Lfe.MacroExpander.available?())
      true
  """
  @spec available?() :: boolean()
  def available? do
    match?(:ok, Reader.ensure_loaded()) and Code.ensure_loaded?(:lfe_comp)
  end

  # ----- Private -----

  defp do_expand(sexprs, opts) do
    with :ok <- ensure_available() do
      module = Keyword.get(opts, :module, :metastatic_lfe_expansion)
      run_compiler(ensure_module(sexprs, module))
    end
  end

  defp ensure_available do
    if available?() do
      :ok
    else
      {:error, "LFE compiler unavailable: :lfe_comp is not loadable"}
    end
  end

  # `lfe_comp:forms/2` needs the forms to declare a module. A file without a
  # `defmodule` (a bare expression, a snippet) gets a synthetic one so the
  # compiler has somewhere to put the code.
  #
  # The `export` list must be the third element of `defmodule` itself — that
  # is the only shape `lfe_comp` accepts. A standalone `(export …)` form is
  # rejected with `unknown_form`.
  #
  # The sentinel body is the integer `1`, not the atom `:ok`: a bare atom in
  # function-body position is read by LFE as a zero-arity *call* (`(ok)`),
  # which fails with `function ok/0 undefined`.
  defp ensure_module(sexprs, module) do
    if Enum.any?(sexprs, &match?([:defmodule | _], &1)) do
      sexprs
    else
      [
        [:defmodule, module, [:export, [:__metastatic_expansion__, 0]]],
        [:defun, :__metastatic_expansion__, [], 1]
        | sexprs
      ]
    end
  end

  # `lfe_comp:forms/2` returns:
  # `lfe_comp:forms/2` returns:
  #
  #     {:ok, [{:ok, Module, Core, Warnings} | …], Warnings}   # success
  #     {:error, Errors, Warnings, []}                         # compile failure
  #
  # Both are matched explicitly: the per-module success element is a 4-tuple
  # and the error tuple is a 4-tuple, so neither matches a plain
  # `{:ok, x}` / `{:error, x}`.
  defp run_compiler(sexprs) do
    case :lfe_comp.forms(sexprs, [:to_core, :return]) do
      {:ok, [{:ok, _module, core, _mod_warnings} | _], _warnings} -> {:ok, core}
      {:ok, [], _warnings} -> {:error, "LFE compiler produced no module"}
      {:error, errors, _warnings, _} -> {:error, format_errors(errors)}
      other -> {:error, "LFE compiler returned an unexpected value: #{inspect(other, limit: 5)}"}
    end
  catch
    kind, reason -> {:error, "LFE compiler crashed: #{inspect({kind, reason}, limit: 5)}"}
  end

  defp format_errors(errors) when is_list(errors) do
    errors
    |> Enum.map_join("; ", &format_error/1)
    |> case do
      "" -> "LFE compilation failed"
      text -> "LFE compilation failed: #{text}"
    end
  end

  defp format_errors(reason), do: "LFE compilation failed: #{inspect(reason, limit: 5)}"

  # Each error is `{:error, Errors, Warnings}` where `Errors` is a list of
  # `{File, [{Loc, Module, Description}]}` pairs.
  defp format_error({:error, errors, _warnings}), do: format_error(errors)

  defp format_error({file, errors}) when is_list(errors) do
    _ = file
    format_error(errors)
  end

  defp format_error({loc, module, desc}) when is_atom(module) do
    describe(module, loc, desc)
  end

  defp format_error(errors) when is_list(errors) do
    Enum.map_join(errors, ", ", &format_error/1)
  end

  defp format_error(other), do: inspect(other, limit: 5)

  defp describe(module, loc, desc) do
    if Code.ensure_loaded?(module) and function_exported?(module, :format_error, 1) do
      "#{inspect(loc)}: #{module.format_error(desc)}"
    else
      "#{inspect(loc)}: #{inspect(desc, limit: 3)}"
    end
  rescue
    _ -> "#{inspect(loc)}: #{inspect(desc, limit: 3)}"
  end
end
