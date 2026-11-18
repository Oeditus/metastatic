defmodule Metastatic.Adapters.March do
  @moduledoc """
  March language adapter for MetaAST transformations.

  Bridges between March AST (M1) and MetaAST (M2), enabling cross-language
  code analysis and transformation for March source code.
  """

  @behaviour Metastatic.Adapter

  alias Metastatic.Adapters.March.{FromMeta, Subprocess, ToMeta}

  @impl true
  def parse(source) when is_binary(source) do
    Subprocess.parse(source)
  end

  @impl true
  def to_meta(march_ast) do
    march_ast
    |> ToMeta.transform()
    |> Metastatic.Adapter.enrich(:march)
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
