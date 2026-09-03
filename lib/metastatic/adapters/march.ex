defmodule Metastatic.Adapters.March do
  @moduledoc """
  March language adapter for MetaAST transformations.

  Bridges between March AST (M1) and MetaAST (M2), enabling cross-language
  code analysis and transformation for March source code.
  """

  @behaviour Metastatic.Adapter

  alias Metastatic.Adapters.March.{FromMeta, Subprocess, ToMeta}
  alias Metastatic.Semantic.Enricher

  @impl true
  def parse(source) when is_binary(source) do
    Subprocess.parse(source)
  end

  @impl true
  def to_meta(march_ast) do
    case ToMeta.transform(march_ast) do
      {:ok, meta_ast, metadata} ->
        enriched_ast = Enricher.enrich_tree(meta_ast, :march)
        {:ok, enriched_ast, metadata}

      error ->
        error
    end
  end

  @impl true
  def from_meta(meta_ast, metadata \\ %{}) do
    FromMeta.transform(meta_ast, metadata)
  end

  @impl true
  def unparse(march_ast) when is_map(march_ast) do
    Subprocess.unparse(march_ast)
  end

  @impl true
  def file_extensions do
    [".march", ".mch"]
  end
end
