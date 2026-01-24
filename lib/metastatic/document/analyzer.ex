defmodule Metastatic.Document.Analyzer do
  @moduledoc false

  @callback handle_analyze(Metastatic.Document.t(), keyword()) ::
              {:ok, map()} | {:error, term()}

  defmacro __using__(opts \\ []) do
    quote location: :keep, generated: true do
      @behaviour Metastatic.Document.Analyzer

      doc =
        Keyword.get(
          unquote(opts),
          :doc,
          "Analyzes a document for #{inspect(__MODULE__)}, raising on error."
        )

      @doc doc
      @spec analyze(Metastatic.Document.t()) :: {:ok, map()} | {:error, term()}
      @spec analyze(Metastatic.Document.t(), keyword()) :: {:ok, map()} | {:error, term()}
      @spec analyze(Metastatic.language(), term(), keyword()) :: {:ok, map()} | {:error, term()}
      def analyze(language_or_doc, source_or_ast_or_opts \\ [], opts \\ [])

      def analyze(language, source_or_ast, opts) when is_atom(language) do
        with {:ok, doc} <- Metastatic.Document.normalize({language, source_or_ast}),
             do: analyze(doc, opts, opts)
      end

      def analyze(%Metastatic.Document{ast: nil}, _, _),
        do: {:error, :invalid_ast}

      def analyze(%Metastatic.Document{ast: _} = doc, opts, _),
        do: handle_analyze(doc, opts)

      @doc doc <> "\n\nUnlike not-banged version, this one either returns a result or raises"
      @spec analyze!(Metastatic.Document.t()) :: Result.t()
      @spec analyze!(Metastatic.Document.t(), keyword()) :: Result.t()
      @spec analyze!(Metastatic.language(), term(), keyword()) :: Result.t()
      def analyze!(language_or_doc, source_or_ast_or_opts \\ [], opts \\ []) do
        case analyze(language_or_doc, source_or_ast_or_opts, opts) do
          {:ok, result} ->
            result

          {:error, reason} ->
            raise "Analysis by #{inspect(__MODULE__)} failed: #{inspect(reason)}"
        end
      end
    end
  end
end
