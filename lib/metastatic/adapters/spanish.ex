defmodule Metastatic.Adapters.Spanish do
  @moduledoc """
  Top-level Spanish adapter forwarding to `Metastatic.NL.Adapters.Spanish`.
  """

  @behaviour Metastatic.Adapter

  alias Metastatic.NL.Adapters.Spanish, as: NLAdapter

  @impl true
  def parse(source), do: NLAdapter.parse(source)

  @impl true
  def to_meta(cst), do: NLAdapter.to_meta(cst)

  @impl true
  def from_meta(meta_ast, metadata \\ %{}), do: NLAdapter.from_meta(meta_ast, metadata)

  @impl true
  def unparse(cst), do: NLAdapter.unparse(cst)

  @impl true
  def file_extensions, do: NLAdapter.file_extensions()
end
