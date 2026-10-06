defmodule Metastatic.NL.Adapters.Spanish do
  @moduledoc """
  Metastatic language adapter for Spanish natural language and prose.
  """

  @behaviour Metastatic.Adapter

  alias Metastatic.NL.AST
  alias Metastatic.NL.Adapters.Spanish.ToMeta

  @impl true
  def parse(source) when is_binary(source) do
    {:ok, %{"type" => "document", "language" => "es", "source" => source}}
  end

  @impl true
  def to_meta(%{"source" => source}) do
    ToMeta.transform(source)
  end

  def to_meta(source) when is_binary(source) do
    ToMeta.transform(source)
  end

  @impl true
  def from_meta(meta_ast, _metadata \\ %{}) do
    {:ok, %{"type" => "document", "source" => AST.text(meta_ast)}}
  end

  @impl true
  def unparse(%{"source" => source}) do
    {:ok, source}
  end

  def unparse(meta_ast) do
    {:ok, AST.text(meta_ast)}
  end

  @impl true
  def file_extensions do
    [".es.md", ".es.txt"]
  end
end
