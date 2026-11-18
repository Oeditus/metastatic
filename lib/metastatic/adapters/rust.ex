defmodule Metastatic.Adapters.Rust do
  @moduledoc """
  Rust language adapter for MetaAST transformations.

  Bridges between Rust AST (M1, produced by `syn` via a subprocess bridge) and
  MetaAST (M2), enabling cross-language code analysis, transformation and
  round-trip code generation for Rust source code.

  ## Rust AST Structure (M1)

  Rust has no parser on the BEAM, so this adapter shells out to
  `metastatic-rust-parser`, a small Rust CLI built from `priv/parsers/rust/`.
  It parses with [`syn`](https://docs.rs/syn) and prints with
  [`prettyplease`](https://docs.rs/prettyplease).

  The bridge serialises a serde mirror of `syn`'s AST (see the bridge's
  `README.md`). Every node is an object with a `kind` discriminator, a `span`,
  and kind-specific fields:

      %{"kind" => "Binary", "name" => "+",
        "span" => %{"line" => 3, "col" => 8, "end_line" => 3, "end_col" => 13},
        "children" => [left, right]}

  ### Examples

      # Integer literal
      %{"kind" => "Literal", "value" => %{"subtype" => "integer", "value" => 42}}

      # Path / variable
      %{"kind" => "Path", "name" => "x"}

      # Addition
      %{"kind" => "Binary", "name" => "+",
        "children" => [%{"kind" => "Path", "name" => "x"},
                       %{"kind" => "Literal", "value" => %{"subtype" => "integer", "value" => 5}}]}

      # Function definition
      %{"kind" => "Function", "name" => "add",
        "children" => [params..., body...]}

  ## M1 <-> M2 Transformations

  See `Metastatic.Adapters.Rust.ToMeta` for the full mapping. In summary:

  - Literals -> `{:literal, [subtype: ...], value}`
  - Paths and identifiers -> `{:variable, ...}`
  - Operators -> `{:binary_op, ...}`, `{:unary_op, ...}`
  - Calls and method calls -> `{:function_call, ...}`
  - `fn` -> `{:function_def, ...}`; `struct`/`enum`/`trait`/`impl`/`mod` ->
    `{:container, ...}`
  - `use` -> `{:import, ...}`
  - Constructs with no cross-language analogue -> `{:language_specific, ...}`

  ## Communication Strategy

  1. **Parse**: write the source to a temp file, run the bridge, receive JSON
  2. **Unparse**: send the M1 JSON, receive source produced by `prettyplease`

  The bridge needs no third-party runtime -- only a Rust toolchain (`cargo`) to
  build it, or a prebuilt `metastatic-rust-parser` on `PATH`. When neither is
  available, every callback returns a clear `{:error, reason}` instead of
  raising.

  ## Round-Trip Fidelity

  `prettyplease` normalises formatting to rustfmt style, so byte-identical
  round-trips are not attempted. The target is *semantic* equivalence: the
  re-parsed AST must equal the original, which the bridge's `selftest` mode
  verifies over a corpus covering every mapped construct.

  ## Usage

      # Parse Rust source
      {:ok, ast} = Metastatic.Adapters.Rust.parse("fn main() {}")

      # Transform to MetaAST
      {:ok, meta_ast, metadata} = Metastatic.Adapters.Rust.to_meta(ast)

      # Transform back to a Rust AST
      {:ok, ast2} = Metastatic.Adapters.Rust.from_meta(meta_ast, metadata)

      # Unparse to source
      {:ok, source} = Metastatic.Adapters.Rust.unparse(ast2)
  """

  @behaviour Metastatic.Adapter

  alias Metastatic.Adapters.Rust.{FromMeta, Subprocess, ToMeta, Validate}

  @impl true
  def parse(source) when is_binary(source) do
    Subprocess.parse(source)
  end

  @impl true
  def to_meta(rust_ast) do
    rust_ast
    |> ToMeta.transform()
    |> Metastatic.Adapter.enrich(:rust)
  end

  @impl true
  def from_meta(meta_ast, metadata) do
    FromMeta.transform(meta_ast, metadata)
  end

  @impl true
  def unparse(rust_ast) do
    Subprocess.unparse(rust_ast)
  end

  @doc """
  Validates that a MetaAST mutation produces valid Rust.

  Implements the optional `Metastatic.Adapter.validate_mutation/2` callback.
  The ownership heuristic always runs; `rustc` runs when it is available and
  `opts[:rustc]` is not `false`. A missing toolchain degrades to the heuristic
  result rather than failing the mutation.

  See `Metastatic.Adapters.Rust.Validate`.

  ## Examples

      iex> Metastatic.Adapters.Rust.validate_mutation({:literal, [subtype: :integer], 42}, %{})
      :ok
  """
  @impl true
  def validate_mutation(meta_ast, metadata) do
    Validate.validate_mutation(meta_ast, metadata)
  end

  @impl true
  def file_extensions do
    [".rs"]
  end

  @doc """
  Normalise Rust source formatting without changing its semantics.

  ## Options

    * `:backend` — `:prettyplease` (default) normalises to rustfmt style;
      `:ra` round-trips the source **byte for byte**, preserving comments and
      original whitespace. `:ra` needs a bridge built with `--features ra`;
      otherwise the bridge falls back to `:prettyplease` and reports
      `lossless: false` in its metadata.

  ## Examples

      iex> {:ok, source} = Metastatic.Adapters.Rust.format("fn  main( ){let x=1;}")
      iex> String.contains?(source, "fn main()")
      true

      iex> {:ok, source} = Metastatic.Adapters.Rust.format("fn  main( ){}", backend: :ra)
      iex> source
      "fn  main( ){}"
  """
  @spec format(String.t(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def format(source, opts \\ []) when is_binary(source) do
    Subprocess.format(source, opts)
  end

  @doc """
  Runs the bridge's built-in self-test against the binary in use.

  ## Examples

      iex> {:ok, report} = Metastatic.Adapters.Rust.selftest()
      iex> report["status"]
      "ok"
  """
  @spec selftest() :: {:ok, map()} | {:error, String.t()}
  def selftest do
    Subprocess.selftest()
  end

  @doc """
  Returns `true` when Rust parsing is available in this environment.
  """
  @spec available?() :: boolean()
  def available? do
    Subprocess.available?()
  end
end
