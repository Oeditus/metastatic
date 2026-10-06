defmodule Metastatic.NL.Adapters.English do
  @moduledoc """
  Metastatic language adapter for English natural language and prose.

  Implements the `Metastatic.Adapter` behaviour to bridge English prose (M1)
  with NL-MetaAST (M2).
  """

  @behaviour Metastatic.Adapter

  alias Metastatic.NL.Adapters.English.{FromMeta, Subprocess, ToMeta}

  @impl true
  def parse(source) when is_binary(source) do
    Subprocess.parse(source)
  end

  @impl true
  def to_meta(cst) do
    ToMeta.transform(cst)
  end

  @impl true
  def from_meta(meta_ast, metadata \\ %{}) do
    FromMeta.transform(meta_ast, metadata)
  end

  @impl true
  def unparse(cst) do
    {:ok, FromMeta.to_source(cst)}
  end

  @impl true
  def file_extensions do
    [".md", ".markdown", ".txt", ".rst"]
  end
end
