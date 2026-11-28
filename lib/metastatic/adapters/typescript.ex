defmodule Metastatic.Adapters.TypeScript do
  @moduledoc """
  TypeScript language adapter for MetaAST transformations.

  Bridges between TypeScript AST (M1 via Babel's `typescript` plugin) and
  MetaAST (M2), preserving type annotations in metadata while enabling
  cross-language code analysis.

  ## Relationship to the JavaScript adapter

  TypeScript is its own language (`:typescript`, extensions `.ts` / `.tsx`)
  sharing the `JavaScript.ToMeta` / `JavaScript.FromMeta` translation pair with
  JavaScript. Keeping them separate matters at the *parse* boundary: the
  TypeScript grammar accepts type syntax and reserves identifiers that plain
  JavaScript rejects. See `Metastatic.Adapters.JavaScript` for the full
  rationale.

  ## Type information

  TypeScript-only declarations (`interface`, `type`, `enum`) are preserved as
  `:language_specific` nodes with `language: :typescript` and a `:ts_kind`
  hint, carrying the original M1 node so they round-trip losslessly. Type
  annotations on values travel as `ts_type: true` metadata on the annotated
  node rather than being dropped.
  """

  @behaviour Metastatic.Adapter

  alias Metastatic.Adapters.JavaScript.{FromMeta, Subprocess, ToMeta}

  @impl true
  def parse(source) when is_binary(source) do
    Subprocess.parse(source, :typescript)
  end

  def parse(other), do: {:error, "TypeScript source must be a binary, got: #{inspect(other)}"}

  @impl true
  def to_meta(ts_ast, opts \\ []) do
    ts_ast
    |> ToMeta.transform()
    |> Metastatic.Adapter.enrich(:typescript, Keyword.take(opts, [:enrich]))
  end

  @impl true
  def from_meta(meta_ast, metadata \\ %{}) do
    FromMeta.transform(meta_ast, metadata)
  end

  @impl true
  def unparse(ts_ast) when is_map(ts_ast) do
    Subprocess.unparse(ts_ast)
  end

  def unparse(other), do: {:error, "Invalid TypeScript AST: #{inspect(other)}"}

  @impl true
  def file_extensions do
    [".ts", ".tsx"]
  end

  @impl true
  def available? do
    Subprocess.available?()
  end
end
