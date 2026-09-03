defmodule Metastatic.Adapters.Cure do
  @moduledoc """
  Metastatic adapter for the Cure programming language.

  Transforms Cure source code to/from MetaAST representation using
  Cure's lexer and parser pipeline.
  """

  @behaviour Metastatic.Adapter

  alias Metastatic.{Adapters.Cure.FromMeta, Adapters.Cure.ToMeta, Document}
  alias Metastatic.Semantic.Enricher

  @impl true
  def parse(source) when is_binary(source) do
    case ToMeta.from_source(source) do
      {:ok, ast, _meta} -> {:ok, ast}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def to_meta(cure_ast) do
    meta_ast = ToMeta.from_ast(cure_ast)
    enriched_ast = Enricher.enrich_tree(meta_ast, :cure)
    {:ok, enriched_ast, %{language: :cure}}
  end

  @impl true
  def from_meta(meta_ast, metadata \\ %{}) do
    _ = metadata
    {:ok, meta_ast}
  end

  @impl true
  def unparse(cure_ast) do
    {:ok, FromMeta.to_source(cure_ast)}
  end

  @impl true
  def file_extensions do
    [".cure"]
  end

  @doc "Parse Cure source code into a MetaAST Document."
  @spec abstract(String.t(), atom(), keyword()) :: {:ok, Document.t()} | {:error, term()}
  def abstract(source, language \\ :cure, opts \\ [])

  def abstract(source, _language, opts) when is_binary(source) and is_list(opts) do
    with {:ok, ast, metadata} <- ToMeta.from_source(source, opts) do
      {:ok, Document.new(ast, :cure, metadata, source)}
    end
  end

  @doc "Convert a Cure MetaAST Document back to Cure source."
  @spec reify(Document.t()) :: {:ok, String.t()} | {:error, term()}
  def reify(%Document{ast: ast, language: :cure}) do
    source = FromMeta.to_source(ast)
    {:ok, source}
  end

  def reify(_), do: {:error, "Not a Cure document"}

  @doc "Round-trip: parse source to MetaAST, then back to source."
  @spec round_trip(String.t()) :: {:ok, String.t()} | {:error, term()}
  def round_trip(source) do
    with {:ok, ast} <- parse(source),
         {:ok, meta_ast, metadata} <- to_meta(ast),
         {:ok, ast2} <- from_meta(meta_ast, metadata) do
      unparse(ast2)
    end
  end
end
