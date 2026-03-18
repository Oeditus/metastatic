defmodule Metastatic.Document.Analyzer do
  @moduledoc false

  @callback handle_analyze(Metastatic.Document.t(), keyword()) ::
              {:ok, term()} | {:error, term()}

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
      @spec analyze(Metastatic.Document.t()) :: {:ok, term()} | {:error, term()}
      def analyze(%Metastatic.Document{ast: nil}), do: {:error, :invalid_ast}
      def analyze(%Metastatic.Document{} = doc), do: handle_analyze(doc, [])

      @doc false
      @spec analyze(Metastatic.Document.t(), keyword()) :: {:ok, term()} | {:error, term()}
      @spec analyze(Metastatic.language(), term()) :: {:ok, term()} | {:error, term()}
      def analyze(%Metastatic.Document{ast: nil}, _opts), do: {:error, :invalid_ast}
      def analyze(%Metastatic.Document{} = doc, opts), do: handle_analyze(doc, opts)

      def analyze(language, source_or_ast) when is_atom(language) do
        with {:ok, doc} <- Metastatic.Document.normalize({language, source_or_ast}),
             do: handle_analyze(doc, [])
      end

      @doc false
      @spec analyze(Metastatic.language(), term(), keyword()) :: {:ok, term()} | {:error, term()}
      def analyze(language, source_or_ast, opts) when is_atom(language) do
        with {:ok, doc} <- Metastatic.Document.normalize({language, source_or_ast}),
             do: handle_analyze(doc, opts)
      end

      @doc doc <> "\n\nUnlike not-banged version, this one either returns a result or raises"
      @spec analyze!(Metastatic.Document.t()) :: term()
      def analyze!(%Metastatic.Document{} = doc) do
        case analyze(doc) do
          {:ok, result} ->
            result

          {:error, reason} ->
            raise "Analysis by #{inspect(__MODULE__)} failed: #{inspect(reason)}"
        end
      end

      @doc false
      @spec analyze!(Metastatic.Document.t(), keyword()) :: term()
      @spec analyze!(Metastatic.language(), term()) :: term()
      def analyze!(%Metastatic.Document{} = doc, opts) do
        case analyze(doc, opts) do
          {:ok, result} ->
            result

          {:error, reason} ->
            raise "Analysis by #{inspect(__MODULE__)} failed: #{inspect(reason)}"
        end
      end

      def analyze!(language, source_or_ast) when is_atom(language) do
        case analyze(language, source_or_ast) do
          {:ok, result} ->
            result

          {:error, reason} ->
            raise "Analysis by #{inspect(__MODULE__)} failed: #{inspect(reason)}"
        end
      end

      @doc false
      @spec analyze!(Metastatic.language(), term(), keyword()) :: term()
      def analyze!(language, source_or_ast, opts) when is_atom(language) do
        case analyze(language, source_or_ast, opts) do
          {:ok, result} ->
            result

          {:error, reason} ->
            raise "Analysis by #{inspect(__MODULE__)} failed: #{inspect(reason)}"
        end
      end
    end
  end
end
