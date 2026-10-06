defmodule Metastatic.Adapters.English do
  @moduledoc """
  Top-level English adapter forwarding to `Metastatic.NL.Adapters.English`.
  """

  @behaviour Metastatic.Adapter

  alias Metastatic.NL.Adapters.English, as: NLAdapter

  @impl true
  def parse(source, opts \\ []), do: NLAdapter.parse(source, opts)

  @impl true
  def to_meta(cst), do: NLAdapter.to_meta(cst)

  @impl true
  def from_meta(meta_ast, metadata \\ %{}), do: NLAdapter.from_meta(meta_ast, metadata)

  @impl true
  def unparse(cst), do: NLAdapter.unparse(cst)

  @impl true
  def file_extensions, do: NLAdapter.file_extensions()
end
