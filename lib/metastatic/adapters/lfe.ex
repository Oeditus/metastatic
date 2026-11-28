defmodule Metastatic.Adapters.Lfe do
  @moduledoc """
  LFE (Lisp-Flavoured Erlang) language adapter for MetaAST transformations.

  Bridges between LFE sexprs (M1) and MetaAST (M2), enabling cross-language
  code analysis and transformation for LFE source code.

  ## Why LFE is a native-BEAM adapter

  LFE ships its own reader and compiler as Erlang modules (`lfe_scan`,
  `lfe_parse`, `lfe_io`, `lfe_comp`). Unlike Rust, Haskell, Python or
  JavaScript, no subprocess bridge is needed: parsing is a function call and
  printing is `lfe_io:prettyprint1/1`. That makes this the cheapest adapter in
  the library — no temp files, no JSON wire format, no process spawn — and it
  is the "A. Native BEAM" strategy from `ADAPTER_GUIDE.md` §4.

  Those modules are **not** part of OTP, so `Metastatic.Adapters.Lfe.Reader`
  is the single gate that decides whether LFE is usable and returns a clear
  `{:error, reason}` (never an exception) when it is not.

  ## LFE AST Structure (M1)

  LFE's reader produces plain Erlang terms:

      # Integer / float / string
      42
      3.14
      "text"

      # Symbols and variables
      :atom            # a symbol
      :x               # a variable (lexically identical to a symbol)

      # Lists and tuples
      [1, 2, 3]        # a list
      {:tuple, [1, 2]} # the tuple #(1 2)

      # Calls — a non-empty list whose head is a symbol
      [:defun, :add, [:a, :b], [:"+", :a, :b]]

  The reader returns a list of `{Sexpr, Line}` pairs, one per top-level form.

  ### The call-versus-data rule

  A Lisp reader erases the distinction between `(f a b)` and a three-element
  list — both are Erlang lists. `Metastatic.Adapters.Lfe.ToMeta` therefore
  threads an explicit `:expr` / `:data` context: in `:expr` position a
  non-empty list with a symbol head is a call; in `:data` position a list is
  data. This is the single most important design decision in the adapter.

  ## M1 ↔ M2 Transformations

  See `Metastatic.Adapters.Lfe.ToMeta` for the full mapping. In summary:

  - literals → `{:literal, [subtype: …], value}`
  - symbols / variables → `{:literal, [subtype: :symbol]}` / `{:variable, …}`
  - operators → `{:binary_op, …}`, `{:unary_op, …}`
  - calls → `{:function_call, [name: …], args}` (Erlang interop names keep
    their `io:format` form, so `op_kind` detection works unchanged)
  - `defun` / `defmodule` / `defmacro` → `{:function_def, …}`,
    `{:container, …}`, `{:macro_def, …}`
  - `if` / `case` / `let` / `lambda` / `lc` / `try` → the matching M2.1/M2.2
    nodes
  - anything else → `{:language_specific, [language: :lfe, hint: …], sexpr}`,
    preserving the original sexpr so `FromMeta` restores it exactly

  ## Macro expansion (`expand_macros: true`)

  LFE is a Lisp: `defun`, `let`, `case`, `lc` and friends are macros over a
  small core. Analysing the surface sexpr therefore misses calls written
  inside macro bodies. `to_meta/2` accepts `expand_macros: true`, which runs
  the forms through `lfe_comp:forms(…, [to_core, return])` and returns the
  expanded **Core Erlang** module alongside the surface MetaAST.

  Core Erlang is a compiler IR, not a MetaAST layer, and `lfe_comp` adds
  compiler-generated functions (`__info__/1`, `module_info/0,1`,
  `LFE-EXPAND-EXPORTED-MACRO/3`). It is offered as a *second* view for
  semantic detection only — the surface view remains the round-trippable one.
  When expansion fails (code that does not compile) the adapter falls back to
  the surface forms rather than failing the parse, exactly as the Elixir
  adapter does when ExPanda fails.

  ## Round-Trip Fidelity

  `unparse/1` prints with `lfe_io:prettyprint1/1`, so formatting normalises
  (blank lines between forms are not preserved) while semantics do not
  change. The target is *semantic* equivalence: the re-parsed sexpr must
  equal the original.

  ## Usage

      # Parse LFE source
      {:ok, forms} = Metastatic.Adapters.Lfe.parse("(defun add (a b) (+ a b))")

      # Transform to MetaAST
      {:ok, meta_ast, metadata} = Metastatic.Adapters.Lfe.to_meta(forms)

      # Transform back to LFE forms
      {:ok, forms2} = Metastatic.Adapters.Lfe.from_meta(meta_ast, metadata)

      # Unparse to source
      {:ok, source} = Metastatic.Adapters.Lfe.unparse(forms2)

  ## Availability

  LFE is flagged `experimental` in the built-in registry: its toolchain is
  not part of OTP. It is installed as a development/test dependency, so CI
  exercises the adapter. Host applications must provide LFE themselves;
  the conformance suite skips rather than fails when LFE is absent.
  """

  @behaviour Metastatic.Adapter

  alias Metastatic.Adapters.Lfe.{FromMeta, MacroExpander, Printer, Reader, ToMeta}

  @impl true
  def parse(source) when is_binary(source) do
    Reader.parse(source)
  end

  def parse(other), do: {:error, "LFE source must be a binary, got: #{inspect(other)}"}

  @doc """
  Transform LFE forms to MetaAST, optionally expanding macros.

  ## Options

    * `:expand_macros` — when `true`, also runs the forms through LFE's
      compiler and records the expanded Core Erlang module in the returned
      metadata under `:core`. The MetaAST itself is always built from the
      surface forms, which is the round-trippable representation. When
      expansion fails the metadata carries `:expansion_error` and the
      surface AST is returned unchanged.
    * `:enrich` — forwarded to `Metastatic.Adapter.enrich/3`; `false` skips
      semantic enrichment.

  ## Examples

      iex> {:ok, forms} = Metastatic.Adapters.Lfe.parse("(defun add (a b) (+ a b))")
      iex> {:ok, meta, metadata} = Metastatic.Adapters.Lfe.to_meta(forms, expand_macros: true)
      iex> elem(meta, 0)
      :block
      iex> elem(metadata.core, 0)
      :c_module
  """
  @impl true
  def to_meta(forms, opts \\ []) do
    enrich_opts = Keyword.take(opts, [:enrich])

    forms
    |> ToMeta.transform()
    |> annotate_expansion(forms, opts)
    |> Metastatic.Adapter.enrich(:lfe, enrich_opts)
  end

  @impl true
  def from_meta(meta_ast, metadata \\ %{}) do
    FromMeta.transform(meta_ast, metadata)
  end

  @impl true
  def unparse(ref) when is_reference(ref) or is_pid(ref) or is_port(ref) do
    {:error, "Invalid LFE AST: #{inspect(ref)}"}
  end

  def unparse(forms) do
    Printer.print(forms)
  end

  @impl true
  def file_extensions do
    [".lfe"]
  end

  @doc """
  Extracts children from an LFE `:language_specific` payload.

  Implements the optional `Metastatic.Adapter.extract_children/1` callback so
  analyzers can traverse into constructs the adapter preserves verbatim
  (`receive`, records, binaries) instead of treating them as opaque leaves.

  ## Examples

      iex> Metastatic.Adapters.Lfe.extract_children([:receive, [[:msg, [:do_something]]]])
      [[[:msg, [:do_something]]]]
  """
  @impl true
  def extract_children(sexpr) when is_list(sexpr) do
    case sexpr do
      [_head | args] -> Enum.filter(args, &is_list/1)
      [] -> []
    end
  end

  def extract_children({:tuple, elements}) when is_list(elements), do: elements
  def extract_children(_), do: []

  @doc """
  Expands every macro in `forms` and returns the Core Erlang module.

  Exposed for callers that want the expanded program directly rather than
  through `to_meta/2`'s metadata.

  ## Examples

      iex> {:ok, core} = Metastatic.Adapters.Lfe.expand_macros([{[:defun, :f, [], [1]], 1}])
      iex> elem(core, 0)
      :c_module
  """
  @spec expand_macros([{term(), integer()}] | term(), keyword()) ::
          {:ok, term()} | {:error, String.t()}
  def expand_macros(forms, opts \\ []) do
    MacroExpander.expand(forms, opts)
  end

  @doc """
  Returns `true` when the LFE toolchain is usable in this VM.

  ## Examples

      iex> is_boolean(Metastatic.Adapters.Lfe.available?())
      true
  """
  @impl true
  @spec available?() :: boolean()
  def available?, do: Reader.available?()

  @doc """
  Returns `true` when LFE's compiler (and therefore `expand_macros`) is usable.

  ## Examples

      iex> is_boolean(Metastatic.Adapters.Lfe.expansion_available?())
      true
  """
  @spec expansion_available?() :: boolean()
  def expansion_available?, do: MacroExpander.available?()

  # ----- Private -----

  # `expand_macros: true` adds the expanded Core module to the metadata. It
  # never changes the MetaAST: Core Erlang is a compiler IR, not an M2 layer,
  # and mixing it into the tree would make round-tripping impossible.
  defp annotate_expansion({:ok, meta_ast, metadata}, forms, opts) do
    if Keyword.get(opts, :expand_macros, false) do
      case MacroExpander.expand(forms) do
        {:ok, core} -> {:ok, meta_ast, Map.put(metadata, :core, core)}
        {:error, reason} -> {:ok, meta_ast, Map.put(metadata, :expansion_error, reason)}
      end
    else
      {:ok, meta_ast, metadata}
    end
  end

  defp annotate_expansion(error, _forms, _opts), do: error
end
