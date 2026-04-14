defmodule Metastatic.Adapters.Cure do
  @moduledoc """
  Metastatic adapter for the Cure programming language.

  Transforms Cure source code to/from MetaAST representation using
  Cure's lexer and parser pipeline.

  ## Usage

      {:ok, doc} = Metastatic.Adapter.abstract(Metastatic.Adapters.Cure, source, :cure)
      {:ok, source} = Metastatic.Adapter.reify(Metastatic.Adapters.Cure, doc)
  """

  # NOTE: Does not declare @behaviour Metastatic.Adapter because the Cure
  # compiler modules live in a separate Mix project and are not available
  # at Metastatic compile time. The adapter is used at runtime only.

  alias Cure.Compiler.{Lexer, Parser}
  alias Metastatic.{Adapters.Cure.FromMeta, Document}

  @doc "Parse Cure source code into a MetaAST Document."
  @spec abstract(String.t(), atom()) :: {:ok, Document.t()} | {:error, term()}
  case {Code.ensure_compiled(Lexer), Code.ensure_compiled(Parser)} do
    {{:module, _}, {:module, _}} ->
      def abstract(source, _language) when is_binary(source) do
        with {:ok, tokens} <- Lexer.tokenize(source, emit_events: false),
             {:ok, ast} <- Parser.parse(tokens, emit_events: false) do
          doc = Document.new(ast, :cure)
          {:ok, doc}
        end
      end

    _ ->
      def abstract(source, _language) when is_binary(source) do
        {:error, :cure_not_available}
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
    with {:ok, doc} <- abstract(source, :cure), do: reify(doc)
  end
end
