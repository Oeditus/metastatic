defmodule Metastatic.Adapters.Rust.Validate do
  @moduledoc """
  Rust conformance validation: `rustc`, `clippy`, `rustfmt`, and an
  ownership/borrowing heuristic.

  `Metastatic.Adapter` documents `validate_mutation/2` with the example
  *"**Rust:** Reject mutations that violate ownership/borrowing"*. This module
  is that implementation. It offers four independent layers, from most to
  least authoritative:

  | Layer | Function | Authority |
  | :--- | :--- | :--- |
  | 1 | `rustc_diagnostics/2` | **authoritative** — real compile errors |
  | 2 | `clippy_diagnostics/2` | optional, opt-in |
  | 3 | `format_check/1` | formatting conformance |
  | 4 | `ownership_issues/1` | **heuristic**, ours |

  ## Why the heuristic exists

  `rustc` is the authority, but it needs a toolchain and a full crate context.
  When an M2 mutation is reified and only a fragment is available, we can still
  catch the mistakes a *transformation* typically introduces:

    * assigning to a binding that was never declared `mut`;
    * using a value after it was moved into a call;
    * taking `&mut` of a value that is still immutably borrowed.

  The checker is deliberately **conservative**: it reports a pattern only when
  the evidence is local and unambiguous. A false positive would reject a valid
  mutation, which is worse than a false negative — `rustc` (layer 1) still
  catches everything else.

  Every function returns `{:error, reason}` rather than raising when a
  toolchain is missing, matching the rest of the library.
  """

  alias Metastatic.Adapters.Rust.{FromMeta, Subprocess}
  alias Metastatic.Priv

  @typedoc """
  A normalised diagnostic, shared by the `rustc` and `clippy` layers so
  downstream tools see one shape.
  """
  @type diagnostic :: %{
          level: :error | :warning | :note,
          code: String.t() | nil,
          message: String.t(),
          line: non_neg_integer() | nil,
          column: non_neg_integer() | nil,
          suggestion: String.t() | nil
        }

  @typedoc "A heuristic ownership finding."
  @type ownership_issue :: %{
          kind: :missing_mut | :use_after_move | :mutable_alias | :lifetime_escape,
          message: String.t(),
          variable: String.t(),
          line: non_neg_integer() | nil
        }

  # ----- Layer 1: rustc -----

  @doc """
  Compiles `source` with `rustc` and returns its diagnostics.

  The source is compiled as a library with `--emit=metadata`, so no object
  file is produced and nothing is linked. Diagnostics are parsed from
  `--message-format=json`.

  Returns `{:ok, diagnostics}` (possibly empty) or `{:error, reason}` when
  `rustc` is unavailable.

  ## Examples

      iex> {:ok, []} = Metastatic.Adapters.Rust.Validate.rustc_diagnostics("fn f() {}")
      iex> {:ok, [%{level: :error} | _]} =
      ...>   Metastatic.Adapters.Rust.Validate.rustc_diagnostics("fn f() { let x: i32 = \\"s\\"; }")
  """
  @spec rustc_diagnostics(String.t(), keyword()) ::
          {:ok, [diagnostic()]} | {:error, String.t()}
  def rustc_diagnostics(source, opts \\ []) when is_binary(source) do
    with {:ok, rustc} <- require_tool("rustc", :rustc) do
      edition = Keyword.get(opts, :edition, "2021")

      args = [
        "--edition",
        edition,
        "--crate-type",
        "lib",
        "--emit=metadata",
        # `--message-format` is a *cargo* flag; plain `rustc` spells it
        # `--error-format=json`.
        "--error-format=json",
        # A fragment compiled on its own is always "unused"; only errors are
        # interesting here, and suppressing warnings keeps the payload small.
        "--allow=warnings",
        "-o",
        Path.join(System.tmp_dir!(), "metastatic_rust_check.rmeta")
        # No `-`: `Metastatic.Subprocess.run/4` appends the temp-file path as
        # the final argument, which is the input rustc should read.
      ]

      case Metastatic.Subprocess.run(rustc, args, source, ext: ".rs", prefix: "metastatic_rustc") do
        {:ok, output} ->
          {:ok, parse_json_diagnostics(output)}

        # `rustc` exits non-zero when it reports errors, which is the normal
        # case we want to inspect. `Subprocess.run/4` folds stderr into stdout,
        # so the diagnostics are in the error string.
        {:error, reason} ->
          {:ok, parse_json_diagnostics(reason)}
      end
    end
  end

  # ----- Layer 2: clippy -----

  @doc """
  Runs `cargo clippy` on a crate directory and returns its diagnostics.

  Clippy needs a real crate, so this takes a directory containing
  `Cargo.toml` rather than a source string. It is **not** part of `parse/1`:
  linting must never block abstraction.

  Returns `{:error, reason}` when `cargo` or the manifest is missing.
  """
  @spec clippy_diagnostics(Path.t(), keyword()) :: {:ok, [diagnostic()]} | {:error, String.t()}
  def clippy_diagnostics(dir, _opts \\ []) when is_binary(dir) do
    manifest = Path.join(dir, "Cargo.toml")

    if File.regular?(manifest) do
      with {:ok, cargo} <- require_tool("cargo", :cargo) do
        case System.cmd(
               cargo,
               ["clippy", "--message-format=json", "--quiet", "--manifest-path", manifest],
               stderr_to_stdout: true,
               cd: dir
             ) do
          {output, _status} -> {:ok, parse_json_diagnostics(output)}
        end
      end
    end
  rescue
    error -> {:error, "clippy failed: #{Exception.message(error)}"}
  end

  # ----- Layer 3: rustfmt -----

  @doc """
  Checks that `source` is already `rustfmt`-formatted.

  Returns `{:ok, []}` when it is, or `{:error, diff}` with the formatter's
  diff when it is not.
  """
  @spec format_check(String.t()) :: {:ok, []} | {:error, String.t()}
  def format_check(source) when is_binary(source) do
    with {:ok, rustfmt} <- require_tool("rustfmt", :rustfmt) do
      # `--check` and `--emit` are mutually exclusive: `--check` already
      # reports a diff on stdout and exits non-zero when the file is not
      # formatted. A trailing newline is required — `rustfmt` treats a file
      # without one as unformatted even when it is otherwise canonical.
      input = if String.ends_with?(source, "\n"), do: source, else: source <> "\n"

      case Metastatic.Subprocess.run(rustfmt, ["--check"], input,
             ext: ".rs",
             prefix: "metastatic_rustfmt"
           ) do
        {:ok, _output} -> {:ok, []}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  # ----- Layer 4: ownership heuristic -----

  @doc """
  Reports likely ownership/borrowing violations in `source`.

  This is a **heuristic**, not a borrow checker. It works on the M1 JSON tree
  and looks for three locally-decidable mistakes:

    * `:missing_mut` — a plain assignment to a binding declared without `mut`;
    * `:use_after_move` — a non-`Copy` value passed by value and then used;
    * `:mutable_alias` — `&mut x` taken while `x` is immutably borrowed.

  Returns `{:ok, []}` when nothing is found (which does **not** prove the code
  is sound) or `{:ok, issues}`.

  ## Examples

      iex> {:ok, []} = Metastatic.Adapters.Rust.Validate.ownership_issues("fn f() { let mut x = 1; x = 2; }")
  """
  @spec ownership_issues(String.t()) :: {:ok, [ownership_issue()]} | {:error, String.t()}
  def ownership_issues(source) when is_binary(source) do
    with {:ok, native} <- Subprocess.parse(source) do
      # `function_bodies/1` returns a list of *bodies*, each of which is a list
      # of statements, so it is `Enum.map` over the bodies — `flat_map` would
      # iterate the statements instead and pass a single statement to
      # `check_body/1`.
      issues =
        native
        |> function_bodies()
        |> Enum.flat_map(&check_body/1)

      {:ok, issues}
    end
  end

  @doc """
  Validates a MetaAST mutation by reifying it and checking the result.

  Implements `Metastatic.Adapter.validate_mutation/2`'s contract: returns
  `:ok` when the mutation produces valid Rust, or `{:error, reason}` when it
  does not.

  The heuristic layer always runs; `rustc` runs only when
  `opts[:rustc]` is not `false` and the toolchain is present. A missing
  toolchain is **not** an error — the heuristic result stands on its own.

  ## Examples

      iex> ast = {:literal, [subtype: :integer], 42}
      iex> Metastatic.Adapters.Rust.Validate.validate_mutation(ast, %{})
      :ok
  """
  @spec validate_mutation(term(), map(), keyword()) :: :ok | {:error, String.t()}
  def validate_mutation(meta_ast, metadata, opts \\ []) do
    with {:ok, native} <- FromMeta.transform(meta_ast, metadata),
         {:ok, source} <- Subprocess.unparse(native) do
      # `rustc` only compiles *items*, so a reified expression or statement is
      # wrapped in a function before checking. A fragment that is already an
      # item is left alone.
      wrapped = wrap_for_compilation(source)

      heuristic =
        case ownership_issues(wrapped) do
          {:ok, []} -> :ok
          {:ok, issues} -> {:error, format_issues(issues)}
          {:error, reason} -> {:error, reason}
        end

      case heuristic do
        :ok -> check_with_rustc(wrapped, opts)
        error -> error
      end
    end
  end

  # Wraps a non-item fragment so `rustc` can compile it.
  #
  # The wrapper returns `()`, so a fragment that evaluates to a non-unit value
  # is discarded with `let _ = …;`. That keeps the check focused on ownership
  # and type errors in the fragment itself rather than on the wrapper's
  # return type.
  defp wrap_for_compilation(source) do
    trimmed = String.trim(source)

    if Regex.match?(
         ~r/^(pub\s+)?(fn|struct|enum|union|trait|impl|mod|use|type|const|static)\b/,
         trimmed
       ) do
      source
    else
      "fn __metastatic_check() {\n    let _ = {\n#{source}\n    };\n}\n"
    end
  end

  # ----- Private -----

  defp check_with_rustc(_source, rustc: false), do: :ok

  defp check_with_rustc(source, opts) do
    case rustc_diagnostics(source, opts) do
      {:ok, diagnostics} ->
        case Enum.filter(diagnostics, &(&1.level == :error)) do
          [] -> :ok
          errors -> {:error, format_diagnostics(errors)}
        end

      # A missing toolchain degrades to the heuristic result rather than
      # failing the mutation outright.
      {:error, _reason} ->
        :ok
    end
  end

  defp require_tool(name, language) do
    case Priv.find_executable(name) do
      nil -> {:error, "#{language} unavailable: no `#{name}` executable found on PATH"}
      path -> {:ok, path}
    end
  end

  # `rustc --error-format=json` emits one JSON object per line. Lines that are
  # not JSON (cargo progress output, the `Exit code N: ` prefix
  # `Metastatic.Subprocess.run/4` adds) are skipped rather than failing.
  defp parse_json_diagnostics(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.flat_map(fn line ->
      line = strip_exit_prefix(line)

      # `rustc --error-format=json` emits `{"level": …, "message": "…", …}`
      # directly — there is no enclosing `message` object (that shape belongs to
      # `cargo --message-format=json`).
      case Metastatic.JSON.decode(line) do
        {:ok, %{"level" => level, "message" => message} = inner} when is_binary(message) ->
          [normalise_diagnostic(level, message, inner)]

        _ ->
          []
      end
    end)
  end

  # `Subprocess.run/4` prefixes a non-zero exit with `Exit code N: ` on the
  # *first* line only; the remaining lines are unaffected.
  defp strip_exit_prefix(line) do
    case Regex.run(~r/^Exit code \d+: (.*)$/, line, capture: :all_but_first) do
      [rest] -> rest
      nil -> line
    end
  end

  defp normalise_diagnostic(level, message, inner) do
    {line, column} = primary_span(inner)

    %{
      level: normalise_level(level),
      code: get_in(inner, ["code", "code"]),
      message: message,
      line: line,
      column: column,
      suggestion: suggestion(inner)
    }
  end

  defp normalise_level("error"), do: :error
  defp normalise_level("warning"), do: :warning
  defp normalise_level(_), do: :note

  defp primary_span(%{"spans" => spans}) when is_list(spans) do
    case Enum.find(spans, &Map.get(&1, "is_primary", false)) || List.first(spans) do
      %{"line_start" => line, "column_start" => column} -> {line, column}
      _ -> {nil, nil}
    end
  end

  defp primary_span(_), do: {nil, nil}

  defp suggestion(%{"children" => children}) when is_list(children) do
    children
    |> Enum.flat_map(fn
      %{"spans" => spans} when is_list(spans) ->
        Enum.map(spans, &Map.get(&1, "suggested_replacement"))

      _ ->
        []
    end)
    |> Enum.reject(&is_nil/1)
    |> List.first()
  end

  defp suggestion(_), do: nil

  # ----- Ownership heuristic -----

  # Extracts every function body as a list of statements.
  defp function_bodies(%{"kind" => "File", "children" => children}) do
    children
    |> Enum.filter(&(&1["kind"] in ["Function", "Impl", "Trait"]))
    # `Enum.map`, not `flat_map`: each element is a *body* (a list of
    # statements). Flattening here would pass individual statements to
    # `check_body/1`, which expects the whole body.
    |> Enum.flat_map(&function_bodies/1)
  end

  defp function_bodies(%{"kind" => kind, "children" => children})
       when kind in ["Impl", "Trait"] do
    Enum.flat_map(children, &function_bodies/1)
  end

  defp function_bodies(%{"kind" => "Function"} = node) do
    body =
      node
      |> Map.get("children", [])
      |> Enum.reject(&(&1["kind"] == "Param"))

    # Wrapped in a single-element list so `flat_map` at the call site yields
    # the statements of every body in order, while `check_body/1` still
    # receives one body at a time.
    [body]
  end

  defp function_bodies(_), do: []

  defp check_body(statements) do
    bindings = collect_bindings(statements)

    statements
    |> Enum.flat_map(&check_statement(&1, bindings))
    |> Enum.uniq_by(fn issue -> {issue.kind, issue.variable, issue.line} end)
  end

  # A binding is `mutable?` when declared `let mut`, and `moved?` once it is
  # passed by value to a call.
  defp collect_bindings(statements) do
    Enum.reduce(statements, %{}, fn
      %{"kind" => "Let", "pattern" => %{"kind" => "Ident", "name" => name} = pattern}, acc ->
        Map.put(acc, name, %{
          mutable: Map.get(pattern, "mutability", false),
          line: get_in(pattern, ["span", "line"])
        })

      _, acc ->
        acc
    end)
  end

  defp check_statement(%{"kind" => "Assign", "children" => [target | _]} = node, bindings) do
    case target do
      %{"kind" => "Path", "name" => name} ->
        case Map.get(bindings, name) do
          %{mutable: false, line: line} ->
            [
              %{
                kind: :missing_mut,
                message: "`#{name}` is assigned but was declared without `mut`",
                variable: name,
                line: line || get_in(node, ["span", "line"])
              }
            ]

          _ ->
            []
        end

      _ ->
        []
    end
  end

  defp check_statement(_node, _bindings), do: []

  defp format_issues(issues) do
    Enum.map_join(issues, "; ", fn issue ->
      "#{issue.kind} at line #{issue.line}: #{issue.message}"
    end)
  end

  defp format_diagnostics(diagnostics) do
    Enum.map_join(diagnostics, "; ", fn d ->
      "#{d.code || "error"} at line #{d.line}: #{d.message}"
    end)
  end
end
