defmodule Metastatic.Adapters.TypeScript do
  @moduledoc """
  TypeScript language adapter for MetaAST transformations.

  Bridges between TypeScript AST (M1 via Babel TS) and MetaAST (M2), preserving
  type annotations in metadata while enabling cross-language code analysis.
  """

  @behaviour Metastatic.Adapter

  alias Metastatic.Adapters.JavaScript.{FromMeta, Subprocess, ToMeta}
  alias Metastatic.Semantic.Enricher

  @impl true
  def parse(source) when is_binary(source) do
    Subprocess.parse(source)
  end

  @impl true
  def to_meta(ts_ast) do
    case ToMeta.transform(ts_ast) do
      {:ok, meta_ast, metadata} ->
        enriched_ast = Enricher.enrich_tree(meta_ast, :typescript)
        {:ok, enriched_ast, metadata}

      error ->
        error
    end
  end

  @impl true
  def from_meta(meta_ast, metadata) do
    FromMeta.transform(meta_ast, metadata)
  end

  @impl true
  def unparse(ts_ast) do
    Subprocess.unparse(ts_ast)
  end

  @impl true
  def file_extensions do
    [".ts", ".tsx"]
  end
end
