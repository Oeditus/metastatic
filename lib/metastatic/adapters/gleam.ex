defmodule Metastatic.Adapters.Gleam do
  @moduledoc """
  Gleam language adapter for MetaAST transformations.

  Bridges between Gleam's untyped AST (M1, produced by the Gleam compiler's own
  parser) and MetaAST (M2), enabling cross-language code analysis,
  transformation and round-trip code generation for Gleam source.

  ## Why the compiler's own parser

  Gleam has no parser on the BEAM, so this adapter shells out to
  `metastatic-gleam-parser`, a small Rust CLI built from `priv/parsers/gleam/`.
  Unlike the other subprocess adapters, that bridge does **not** hand-write a
  parser: it links against `gleam_core::parse::parse_module/3` and
  `gleam_format::pretty/3`, the exact crates `gleam build` and `gleam format`
  use, vendored under `priv/parsers/gleam/vendor/`.

  Two things follow from that, and they are the reason for the design:

    * **Syntax coverage is the compiler's, not ours.** A Gleam release that
      adds a construct is parsed the day the vendored crates are refreshed, not
      the day this adapter is taught about it. The bridge's `to_json` module has
      no wildcard arm on any AST enum, so a refresh that adds a variant fails to
      *compile* rather than silently mis-parsing.
    * **Printing is `gleam format`'s.** `unparse/1` runs the reified tree
      through the reference printer, so output is valid Gleam by construction
      and formatted the way a Gleam developer would format it.

  ## Gleam AST Structure (M1)

  The bridge emits a shallow, tagged mirror of the compiler's AST — every node
  is an object with a `kind` discriminator, a `span`, and kind-specific fields:

      %{"kind" => "Module", "span" => %{...}, "comments" => [...],
        "children" => [...]}

      %{"kind" => "Fn", "name" => "add", "public" => true,
        "span" => %{"line" => 3, "col" => 8, "end_line" => 3, "end_col" => 20},
        "children" => [args..., body...],
        "type_node" => %{"kind" => "TypeConstructor", "name" => "Int", ...},
        "extra" => %{"publicity" => "public", "purity" => "pure", ...}}

      %{"kind" => "BinOp", "name" => "+",
        "extra" => %{"operator" => "AddInt"},
        "children" => [left, right]}

  Spans are 1-based on both axes; `gleam_core` reports byte offsets, which the
  bridge converts once so every adapter in Metastatic speaks the same position
  language.

  ## M1 ↔ M2 Transformations

  See `Metastatic.Adapters.Gleam.ToMeta` for the full mapping. In summary:

  | Gleam (M1) | MetaAST (M2) |
  | :--- | :--- |
  | `Int` / `Float` / `String` | `{:literal, [subtype: …], value}` |
  | `Var` | `{:variable, …}` |
  | `BinOp` / `NegateInt` / `NegateBool` | `{:binary_op, …}` / `{:unary_op, …}` |
  | `Call` | `{:function_call, …}` |
  | `Case` / `Clause` | `{:pattern_match, …}` / `{:match_arm, …}` |
  | `Fn` (declaration) | `{:function_def, …}` |
  | `FnLiteral` | `{:lambda, …}` |
  | `Let` / `Use` / `Assert` | `{:assignment, …}` / `{:block, …}` / `{:assert, …}` |
  | `Pipeline` | `{:pipeline, …}` |
  | `CustomType` / `TypeAlias` | `{:container, …}` / `{:type_annotation, …}` |
  | `Import` | `{:import, …}` |
  | `ModuleConstant` | `{:constant, …}` |
  | `List` / `Tuple` / `BitArray` | `{:list, …}` / `{:tuple, …}` / `{:bit_array, …}` |
  | `Todo` / `Panic` | `{:raise, …}` / `{:raise, …}` |

  Constructs with no cross-language analogue — `echo`, clause guards, record
  updates, string-prefix patterns — become `:language_specific` nodes carrying
  the M1 payload, which is what makes reification lossless.

  ## Round-Trip Fidelity

  `unparse/1` runs the reified tree through `gleam format`'s printer, so
  formatting normalises (import lists are sorted, blank lines are collapsed)
  while semantics do not change. The target is *semantic* equivalence: the
  re-parsed MetaAST must equal the original, which the bridge's `selftest` mode
  and the fixture suite both verify.

  ## Usage

      # Parse Gleam source
      {:ok, ast} = Metastatic.Adapters.Gleam.parse("pub fn main() { 1 }")

      # Transform to MetaAST
      {:ok, meta_ast, metadata} = Metastatic.Adapters.Gleam.to_meta(ast)

      # Transform back to a Gleam AST
      {:ok, ast2} = Metastatic.Adapters.Gleam.from_meta(meta_ast, metadata)

      # Unparse to source
      {:ok, source} = Metastatic.Adapters.Gleam.unparse(ast2)

  ## Availability

  The bridge needs a Rust toolchain (`cargo`) the first time, or a prebuilt
  `metastatic-gleam-parser` on `PATH`. The bundled sources are compiled once
  into the user's cache directory, not into the installed package, so a
  read-only deployment should prebuild the binary.

  When no toolchain is available every callback returns a clear
  `{:error, reason}` instead of raising, and the conformance suites skip rather
  than fail.

  ## Two package builds

  The package ships in two configurations, distinguished by
  `Subprocess.build/0`:

    * `:vendored` (default) — full support. `parse/1` produces a MetaAST.
    * `:external_gleam` (`HEX_BUILD=1`) — the package is ~4.9 MB smaller
      because it carries no vendored compiler crates. `format/1` and
      `unparse/1` still work (they delegate to `gleam format --stdin`), but
      `parse/1` returns `{:error, reason}` explaining that a MetaAST needs the
      full package. Callers that must parse can check `available?/0` /
      `Subprocess.build/0` up front.

  This is deliberate: a source-only build that silently produced a *partial*
  MetaAST would be worse than one that says what it cannot do.
  """

  @behaviour Metastatic.Adapter

  alias Metastatic.Adapters.Gleam.{FromMeta, Subprocess, ToMeta}

  @impl true
  def parse(source) when is_binary(source) do
    # The `external-gleam` build has no parser at all. Failing here, with a
    # message that names the build, beats letting the bridge start up to return
    # the same thing — and it keeps `parse/1` honest about what it can do.
    if Subprocess.vendored?() do
      Subprocess.parse(source)
    else
      {:error,
       "Gleam parsing requires the full Metastatic package: this build ships the " <>
         "bridge without the vendored Gleam compiler crates, so it cannot produce " <>
         "a MetaAST. `format/1` and `unparse/1` still work. Install the package " <>
         "built without HEX_BUILD=1, or put a full metastatic-gleam-parser on PATH."}
    end
  end

  @doc """
  Abstracts the bridge's M1 JSON into MetaAST, with semantic enrichment.

  ## Examples

      iex> {:ok, ast} = Metastatic.Adapters.Gleam.parse("pub fn main() { 1 }")
      iex> {:ok, {kind, _, _}, _} = Metastatic.Adapters.Gleam.to_meta(ast)
      iex> kind
      :block
  """
  @impl true
  def to_meta(ast) do
    ast
    |> ToMeta.transform()
    |> Metastatic.Adapter.enrich(:gleam)
  end

  @impl true
  def from_meta(meta_ast, metadata) do
    FromMeta.transform(meta_ast, metadata)
  end

  @impl true
  def unparse(ast) do
    Subprocess.unparse(ast)
  end

  @doc """
  Returns the Gleam source file extension.

  ## Examples

      iex> Metastatic.Adapters.Gleam.file_extensions()
      [".gleam"]
  """
  @impl true
  def file_extensions do
    [".gleam"]
  end

  @doc """
  Extracts children from a `:language_specific` payload.

  Implements the optional `Metastatic.Adapter.extract_children/1` callback so
  analyzers can traverse into constructs the adapter preserves verbatim
  (clause guards, record updates, string-prefix patterns) instead of treating
  them as opaque leaves.

  ## Examples

      iex> Metastatic.Adapters.Gleam.extract_children(%{"kind" => "Guard", "children" => [1, 2]})
      [1, 2]

      iex> Metastatic.Adapters.Gleam.extract_children(%{"kind" => "Var", "name" => "x"})
      []
  """
  @impl true
  def extract_children(%{"children" => children}) when is_list(children), do: children
  def extract_children(%{"pattern" => pattern}) when not is_nil(pattern), do: [pattern]
  def extract_children(_), do: []

  @doc """
  Normalises Gleam source formatting without changing its semantics.

  Uses `gleam format`'s own printer, so the output is byte-identical to what
  `gleam format` would produce.

  ## Examples

      iex> {:ok, source} = Metastatic.Adapters.Gleam.format("pub fn  main( ){1}")
      iex> String.contains?(source, "pub fn main()")
      true
  """
  @spec format(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def format(source) when is_binary(source) do
    Subprocess.format(source)
  end

  @doc """
  Runs the bridge's built-in self-test against the binary in use.

  ## Examples

      iex> {:ok, report} = Metastatic.Adapters.Gleam.selftest()
      iex> report["status"]
      "ok"
  """
  @spec selftest() :: {:ok, map()} | {:error, String.t()}
  def selftest do
    Subprocess.selftest()
  end

  @doc """
  Returns `true` when Gleam *parsing* is available in this environment.

  A `HEX_BUILD=1` package returns `false` even though `format/1` works: the
  question this answers is "can I get a MetaAST?", which is what a caller
  branching on it actually wants to know.

  ## Examples

      iex> is_boolean(Metastatic.Adapters.Gleam.available?())
      true
  """
  @spec available?() :: boolean()
  def available? do
    Subprocess.vendored?() and Subprocess.available?()
  end
end
