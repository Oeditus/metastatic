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

  def parse(other), do: {:error, "March source must be a binary, got: #{inspect(other)}"}

  @impl true
  def to_meta(march_ast, opts \\ []) do
    march_ast
    |> ToMeta.transform()
    |> Metastatic.Adapter.enrich(:march, Keyword.take(opts, [:enrich]))
  end

  @impl true
  def from_meta(meta_ast, metadata \\ %{}) do
    FromMeta.transform(meta_ast, metadata)
  end

  @impl true
  def unparse(march_ast) when is_map(march_ast) do
    Subprocess.unparse(march_ast)
  end

  def unparse(other), do: {:error, "Invalid March AST: #{inspect(other)}"}

  @impl true
  def file_extensions do
    [".march", ".mch"]
  end

  @impl true
  def available? do
    Subprocess.available?()
  end
end
