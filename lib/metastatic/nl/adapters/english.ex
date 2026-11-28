defmodule Metastatic.NL.Adapters.English do
  @moduledoc """
  Metastatic language adapter for English natural language and prose.

  Implements the `Metastatic.Adapter` behaviour to bridge English prose (M1)
  with NL-MetaAST (M2).
  """

  @behaviour Metastatic.Adapter

  alias Metastatic.NL.Adapters.English.{FromMeta, Subprocess, ToMeta}

  @impl true
  def parse(source, opts \\ [])

  def parse(source, opts) when is_binary(source) and is_list(opts) do
    Subprocess.parse(source, opts)
  end

  def parse(other, _opts), do: {:error, "English source must be a binary, got: #{inspect(other)}"}

  @impl true
  def to_meta(%{"type" => _} = cst) do
    ToMeta.transform(cst)
  end

  def to_meta(other), do: {:error, "Not an English CST node: #{inspect(other)}"}

  @impl true
  def from_meta(meta_ast, metadata \\ %{}) do
    FromMeta.transform(meta_ast, metadata)
  end

  @impl true
  def unparse(%{"type" => _} = cst) do
    {:ok, FromMeta.to_source(cst)}
  end

  def unparse({type, _meta, _children} = node) when is_atom(type) do
    {:ok, FromMeta.to_source(node)}
  end

  def unparse(other), do: {:error, "Cannot unparse to English: #{inspect(other)}"}

  @impl true
  def file_extensions do
    [".md", ".markdown", ".txt", ".rst"]
  end
end
