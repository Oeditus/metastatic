defmodule Metastatic.Adapters.Cure do
  @moduledoc """
  Metastatic adapter for the Cure programming language.

  Transforms Cure source code to/from MetaAST representation using
  Cure's lexer and parser pipeline.
  """

  @behaviour Metastatic.Adapter

  alias Metastatic.{
    Adapters.Cure.FromMeta,
    Adapters.Cure.Subprocess,
    Adapters.Cure.ToMeta,
    Document
  }

  @impl true
  def parse(source) when is_binary(source) do
    case ToMeta.from_source(source, preserve_comments: true) do
      {:ok, ast, _meta} -> {:ok, ast}
      {:error, reason} -> {:error, reason}
    end
  end

  def parse(other), do: {:error, "Cure source must be a binary, got: #{inspect(other)}"}

  @impl true
  def to_meta(cure_ast, opts \\ []) do
    {:ok, ToMeta.from_ast(cure_ast), %{language: :cure}}
    |> Metastatic.Adapter.enrich(:cure, Keyword.take(opts, [:enrich]))
  end

  @impl true
  def from_meta(meta_ast, metadata \\ %{}) do
    _ = metadata
    {:ok, meta_ast}
  end

  @impl true
  def unparse(cure_ast) when is_tuple(cure_ast) or is_list(cure_ast) do
    {:ok, FromMeta.to_source(cure_ast)}
  rescue
    e -> {:error, "Cure unparse failed: #{Exception.message(e)}"}
  end

  def unparse(other), do: {:error, "Invalid Cure AST: #{inspect(other)}"}

  @impl true
  def file_extensions do
    [".cure"]
  end

  @impl true
  def available? do
    Code.ensure_loaded?(Cure.Compiler.Lexer) or Subprocess.available?()
  end

  @doc "Parse Cure source code into a MetaAST Document."
  @spec abstract(String.t(), atom(), keyword()) :: {:ok, Document.t()} | {:error, term()}
  def abstract(source, language \\ :cure, opts \\ [])

  def abstract(source, _language, opts) when is_binary(source) and is_list(opts) do
    with {:ok, ast, metadata} <- ToMeta.from_source(source, opts),
         {:ok, enriched, metadata} <-
           Metastatic.Adapter.enrich({:ok, ast, metadata}, :cure, Keyword.take(opts, [:enrich])) do
      {:ok, Document.new(enriched, :cure, metadata, source)}
    end
  end

  @doc "Convert a Cure MetaAST Document back to Cure source."
  @spec reify(Document.t()) :: {:ok, String.t()} | {:error, term()}
  def reify(%Document{language: :cure} = doc), do: Metastatic.Adapter.reify(__MODULE__, doc)
  def reify(_), do: {:error, "Not a Cure document"}

  @doc "Round-trip: parse source to MetaAST, then back to source."
  @spec round_trip(String.t()) :: {:ok, String.t()} | {:error, term()}
  def round_trip(source), do: Metastatic.Adapter.round_trip(__MODULE__, source)
end
