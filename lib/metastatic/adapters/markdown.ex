defmodule Metastatic.Adapters.Markdown do
  @moduledoc """
  Top-level Markdown adapter forwarding to `Metastatic.NL.Adapters.Markdown`.

  Exists for symmetry with the other programming-language adapters
  (`Metastatic.Adapters.Python`, `Metastatic.Adapters.SQL`, …): the
  implementation lives in the NL namespace because Markdown produces
  NL-MetaAST, while this facade is what `Metastatic.Languages` registers
  under the `:markdown` language atom.

  ## Examples

      iex> {:ok, cst} = Metastatic.Adapters.Markdown.parse("# Title")
      iex> {:ok, ast, _metadata} = Metastatic.Adapters.Markdown.to_meta(cst)
      iex> Metastatic.NL.AST.type(ast)
      :document
  """

  @behaviour Metastatic.Adapter

  alias Metastatic.NL.Adapters.Markdown, as: NLAdapter

  @impl true
  def parse(source), do: NLAdapter.parse(source)

  @impl true
  def to_meta(cst), do: NLAdapter.to_meta(cst)

  @impl true
  def from_meta(meta_ast, metadata \\ %{}), do: NLAdapter.from_meta(meta_ast, metadata)

  @impl true
  def unparse(native), do: NLAdapter.unparse(native)

  @impl true
  def file_extensions, do: NLAdapter.file_extensions()
end
