defmodule Metastatic.Adapters.Haskell do
  @moduledoc """
  Haskell language adapter for Metastatic.

  This adapter provides bidirectional transformation between Haskell source code
  and MetaAST (M2) representation.

  ## Architecture

  - `parse/1` - Haskell source → Haskell AST (via haskell-src-exts)
  - `to_meta/1` - Haskell AST → MetaAST (M2 abstraction)
  - `from_meta/2` - MetaAST → Haskell AST (M2 reification)
  - `unparse/1` - Haskell AST → Haskell source (via haskell-src-exts)

  ## Example

      iex> {:ok, ast} = Metastatic.Adapters.Haskell.parse("1 + 2")
      iex> {:ok, meta_ast, _metadata} = Metastatic.Adapters.Haskell.ToMeta.transform(ast)
      iex> meta_ast
      {:binary_op, :arithmetic, :+, {:literal, :integer, 1}, {:literal, :integer, 2}}

  """

  @behaviour Metastatic.Adapter

  alias Metastatic.Adapters.Haskell.{FromMeta, Subprocess, ToMeta}

  @impl true
  def parse(source) when is_binary(source) do
    Subprocess.parse(source)
  end

  @impl true
  def to_meta(haskell_ast) do
    ToMeta.transform(haskell_ast)
  end

  @impl true
  def from_meta(meta_ast, metadata \\ %{}) do
    FromMeta.transform(meta_ast, metadata)
  end

  @impl true
  def unparse(_haskell_ast) do
    {:error, "Unparsing not yet implemented for Haskell"}
  end

  @impl true
  def file_extensions do
    [".hs", ".lhs"]
  end
end
