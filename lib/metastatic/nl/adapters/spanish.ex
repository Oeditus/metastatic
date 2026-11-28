defmodule Metastatic.NL.Adapters.Spanish do
  @moduledoc """
  Metastatic language adapter for Spanish natural language and prose.
  """

  @behaviour Metastatic.Adapter

  alias Metastatic.NL.Adapters.Spanish.{FromMeta, ToMeta}

  @impl true
  def parse(source) when is_binary(source) do
    paragraphs =
      source
      |> String.split(~r/\n\s*\n/)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(fn para ->
        sentences =
          para
          |> String.split(~r/(?<=[.!?¡¿])\s+/)
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))
          |> Enum.map(&%{"type" => "sentence", "text" => &1, "children" => []})

        %{"type" => "paragraph", "children" => sentences}
      end)

    {:ok,
     %{"type" => "document", "language" => "es", "source" => source, "children" => paragraphs}}
  end

  def parse(other), do: {:error, "Spanish source must be a binary, got: #{inspect(other)}"}

  @impl true
  def to_meta(%{"source" => source}) when is_binary(source) do
    ToMeta.transform(source)
  end

  def to_meta(%{"type" => "document", "children" => _} = cst) do
    ToMeta.transform(cst)
  end

  def to_meta(source) when is_binary(source) do
    ToMeta.transform(source)
  end

  def to_meta(other), do: {:error, "Not a Spanish CST node: #{inspect(other)}"}

  @impl true
  def from_meta(meta_ast, metadata \\ %{}) do
    FromMeta.transform(meta_ast, metadata)
  end

  @impl true
  def unparse(%{"type" => _} = cst) do
    {:ok, FromMeta.to_source(cst)}
  end

  def unparse(%{"source" => source}) when is_binary(source) do
    {:ok, source}
  end

  def unparse({type, _meta, _children} = meta_ast) when is_atom(type) do
    {:ok, FromMeta.to_source(meta_ast)}
  end

  def unparse(other), do: {:error, "Cannot unparse to Spanish: #{inspect(other)}"}

  @impl true
  def file_extensions do
    [".es.md", ".es.txt"]
  end
end
