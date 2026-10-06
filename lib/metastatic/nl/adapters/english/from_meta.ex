defmodule Metastatic.NL.Adapters.English.FromMeta do
  @moduledoc """
  Transforms NL-MetaAST (M2) back to English CST (M1).
  """

  alias Metastatic.NL.AST

  @doc """
  Transforms NL-MetaAST to CST map representation.
  """
  @spec transform(AST.nl_node(), map()) :: {:ok, map()}
  def transform({:document, _meta, paragraphs}, _metadata) do
    cst_paras = Enum.map(paragraphs, &transform_paragraph/1)
    {:ok, %{"type" => "document", "language" => "en", "children" => cst_paras}}
  end

  def transform({:paragraph, _meta, sentences}, _metadata) do
    {:ok, transform_paragraph({:paragraph, [], sentences})}
  end

  def transform({:sentence, _meta, _children} = sent, _metadata) do
    {:ok, transform_sentence(sent)}
  end

  def transform(other, _metadata) do
    {:ok, %{"type" => "fragment", "text" => AST.text(other)}}
  end

  defp transform_paragraph({:paragraph, _meta, sentences}) do
    cst_sents = Enum.map(sentences, &transform_sentence/1)
    %{"type" => "paragraph", "children" => cst_sents}
  end

  defp transform_sentence({:sentence, _meta, _children} = sent) do
    text = AST.text(sent)

    tokens =
      AST.tokens(sent)
      |> Enum.map(fn {:token, meta, val} ->
        %{
          "type" => "word",
          "value" => val,
          "line" => Keyword.get(meta, :line),
          "col" => Keyword.get(meta, :col)
        }
      end)

    %{"type" => "sentence", "text" => text, "children" => tokens}
  end

  @doc """
  Reifies NL-MetaAST directly into English source text.
  """
  @spec to_source(AST.nl_node() | map()) :: String.t()
  def to_source(%{"type" => "document", "children" => paras}) do
    Enum.map_join(paras, "\n\n", fn %{"children" => sents} ->
      Enum.map_join(sents, " ", & &1["text"])
    end)
  end

  def to_source({:document, _meta, paragraphs}) do
    Enum.map_join(paragraphs, "\n\n", fn {:paragraph, _meta, sentences} ->
      Enum.map_join(sentences, " ", &AST.text/1)
    end)
  end

  def to_source(node) do
    AST.text(node)
  end
end
