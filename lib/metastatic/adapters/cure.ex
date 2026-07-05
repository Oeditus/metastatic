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

  alias Metastatic.{Adapters.Cure.FromMeta, Adapters.Cure.ToMeta, Document}

  @doc "Parse Cure source code into a MetaAST Document."
  @spec abstract(String.t(), atom(), keyword()) :: {:ok, Document.t()} | {:error, term()}
  @dialyzer {:nowarn_function, abstract: 3}
  def abstract(source, language \\ :cure, opts \\ [])

  def abstract(source, _language, opts) when is_binary(source) and is_list(opts) do
    # The `{:ok, ...}` branch is only reachable when the Cure compiler
    # is linked in at runtime; `with` sidesteps the Elixir type system
    # complaining about the (compile-time only) fallback arm in
    # `ToMeta.from_source/2`.
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

  @dialyzer {:nowarn_function, round_trip: 1}
  @doc "Round-trip: parse source to MetaAST, then back to source."
  @spec round_trip(String.t()) :: {:ok, String.t()} | {:error, term()}
  def round_trip(source) do
    with {:ok, doc} <- abstract(source, :cure), do: reify(doc)
  end
end
