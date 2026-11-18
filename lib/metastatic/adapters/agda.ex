defmodule Metastatic.Adapters.Agda do
  @moduledoc """
  Agda language adapter for Metastatic.

  This adapter provides bidirectional transformation between Agda source code
  and MetaAST (M2) representation using a Haskell-based parser bridge.

  ## Architecture

  - `parse/1` - Agda source → Agda AST (via Agda compiler parser bridge)
  - `to_meta/1` - Agda AST → MetaAST (M2 abstraction)
  - `from_meta/2` - MetaAST → Agda AST (M2 reification)
  - `unparse/1` - Agda AST → Agda source

  ## Examples

      iex> {:ok, ast} = Metastatic.Adapters.Agda.parse("1 + 2")
      iex> {:ok, meta_ast, _metadata} = Metastatic.Adapters.Agda.ToMeta.transform(ast)
      iex> meta_ast
      {:binary_op, [category: :arithmetic, operator: :+],
       [{:literal, [subtype: :integer], 1}, {:literal, [subtype: :integer], 2}]}

  """

  @behaviour Metastatic.Adapter

  alias Metastatic.Adapters.Agda.{FromMeta, Subprocess, ToMeta, Unparser}

  @impl true
  def parse(source) when is_binary(source) do
    Subprocess.parse(source)
  end

  @impl true
  def to_meta(agda_ast) do
    agda_ast
    |> ToMeta.transform()
    |> Metastatic.Adapter.enrich(:agda)
  end

  @impl true
  def from_meta(meta_ast, metadata \\ %{}) do
    FromMeta.transform(meta_ast, metadata)
  end

  @impl true
  def unparse(agda_ast) when is_map(agda_ast) do
    Unparser.unparse(agda_ast)
  end

  def unparse(_agda_ast) do
    {:error, "Invalid Agda AST"}
  end

  @impl true
  def file_extensions do
    [".agda", ".lagda"]
  end
end
