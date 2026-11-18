defmodule MyLisp do
  @moduledoc """
  Demonstrates the whole plug-in pipeline for the `:lisp` language.

  Everything here goes through Metastatic's ordinary public API — nothing in
  this module reaches into Metastatic internals.
  """

  alias Metastatic.{Builder, Languages}

  @doc """
  Runs the end-to-end demonstration and prints a report.

  ## Examples

      iex> MyLisp.demo() |> Map.keys() |> Enum.sort()
      [:cross_language, :enriched, :languages, :round_trip]
  """
  def demo do
    results = %{
      languages: language_report(),
      round_trip: round_trip_report(),
      enriched: enrichment_report(),
      cross_language: cross_language_report()
    }

    print_report(results)
    results
  end

  defp language_report do
    %{
      registered: Languages.supported?(:lisp),
      extensions: Languages.get(:lisp).extensions,
      detected: Languages.detect_language("program.lisp"),
      experimental: Languages.experimental?(:lisp)
    }
  end

  defp round_trip_report do
    source = "(+ 1 (* 2 3))"

    with {:ok, doc} <- Builder.from_source(source, :lisp),
         {:ok, rendered} <- Builder.to_source(doc) do
      %{source: source, meta_ast: doc.ast, rendered: rendered}
    end
  end

  defp enrichment_report do
    with {:ok, doc} <- Builder.from_source("(db-find User)", :lisp) do
      %{meta_ast: doc.ast, op_kind: op_kind_of(doc.ast)}
    end
  end

  defp op_kind_of({:function_call, meta, _args}), do: Keyword.get(meta, :op_kind)
  defp op_kind_of(_), do: nil

  defp cross_language_report do
    # The same MetaAST reified as another language: the point of M2.
    with {:ok, doc} <- Builder.from_source("(+ 1 2)", :lisp),
         {:ok, elixir_source} <- Builder.to_source(doc, :elixir) do
      %{lisp: "(+ 1 2)", meta_ast: doc.ast, elixir: elixir_source}
    end
  end

  defp print_report(results) do
    IO.puts("\n=== :lisp plug-in demo ===\n")

    IO.puts("Registered language:")
    IO.inspect(results.languages, label: "  ")

    IO.puts("\nRound trip:")
    IO.inspect(results.round_trip, label: "  ")

    IO.puts("\nSemantic enrichment (via config :metastatic, :semantic):")
    IO.inspect(results.enriched.op_kind, label: "  op_kind")

    IO.puts("\nCross-language translation:")
    IO.inspect(results.cross_language, label: "  ")
    IO.puts("")
  end
end
