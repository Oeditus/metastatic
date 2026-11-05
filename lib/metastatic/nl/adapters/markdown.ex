defmodule Metastatic.NL.Adapters.Markdown do
  @moduledoc """
  Metastatic language adapter for Markdown documents.

  Markdown is treated as a **first-class citizen**: it has its own
  `Metastatic.Adapter` implementation, its own M1 CST, and a full
  M1 ↔ M2 pipeline into NL-MetaAST, so every M2-level facility (validation,
  prose linting, readability, semantic enrichment, translation) applies to
  Markdown documents without special-casing.

  ## Pipeline

  ```mermaid
  graph LR
      MD["Markdown source (M0)"] -->|"parse/1"| CST["CST map (M1)"]
      CST -->|"to_meta/1"| M2["NL-MetaAST (M2)"]
      M2 -->|"from_meta/2"| CST2["CST map (M1)"]
      CST2 -->|"unparse/1"| MD2["Markdown source (M0)"]
  ```

  ## What is modelled

  - **Blocks:** headings (ATX + setext), paragraphs, fenced and indented
    code, block quotes, bullet/ordered/nested lists, GitHub task lists,
    GFM tables with alignment, thematic breaks, footnotes and link
    reference definitions.
  - **Inline:** emphasis, strong, strikethrough, inline code, links,
    images, reference links, autolinks and hard line breaks.
  - **Prose structure:** paragraph, list-item, heading and table-cell text
    is chunked into sentences → clauses → phrases, so prose linting rules
    (`Metastatic.NL.Lint.Runner`) work on Markdown unchanged. Code blocks
    and inline code stay opaque so source code is never treated as prose.

  ## Usage

      # Parse and abstract a Markdown document
      {:ok, cst} = Markdown.parse("# Title\\n\\nSome *prose*.")
      {:ok, ast, metadata} = Markdown.to_meta(cst)

      # Reify back to Markdown
      {:ok, cst2} = Markdown.from_meta(ast, metadata)
      {:ok, source} = Markdown.unparse(cst2)

  The adapter is registered as `:markdown` in `Metastatic.Languages`, so
  `Metastatic.quote/2`, `Metastatic.unquote/2`, `Metastatic.Builder` and the
  CLI mix tasks all accept it.
  """

  @behaviour Metastatic.Adapter

  alias Metastatic.NL.Adapters.Markdown.{FromMeta, Parser, ToMeta}

  @doc """
  Parses Markdown source into the M1 CST map.

  ## Examples

      iex> {:ok, %{"type" => "document", "language" => "markdown"}} =
      ...>   Metastatic.NL.Adapters.Markdown.parse("# Title")
  """
  @impl true
  @spec parse(String.t()) :: {:ok, map()} | {:error, String.t()}
  def parse(source) when is_binary(source) do
    Parser.parse(source)
  end

  def parse(other) do
    {:error, "Markdown source must be a binary, got: #{inspect(other)}"}
  end

  @doc """
  Transforms the M1 CST into NL-MetaAST (M2).

  ## Examples

      iex> {:ok, cst} = Metastatic.NL.Adapters.Markdown.parse("Hello world.")
      iex> {:ok, ast, %{language: :markdown}} = Metastatic.NL.Adapters.Markdown.to_meta(cst)
      iex> Metastatic.NL.AST.type(ast)
      :document
  """
  @impl true
  @spec to_meta(map()) :: {:ok, Metastatic.NL.AST.nl_node(), map()} | {:error, String.t()}
  def to_meta(%{"type" => _} = cst) do
    ToMeta.transform(cst)
  end

  def to_meta(other) do
    {:error, "Not a Markdown CST node: #{inspect(other)}"}
  end

  @doc """
  Reifies NL-MetaAST (M2) back into a Markdown CST (M1).
  """
  @impl true
  @spec from_meta(Metastatic.NL.AST.nl_node(), map()) :: {:ok, map()} | {:error, String.t()}
  def from_meta(meta_ast, metadata \\ %{}) do
    FromMeta.transform(meta_ast, metadata)
  end

  @doc """
  Unparses an M1 CST (or an M2 NL-MetaAST) into Markdown source.

  ## Examples

      iex> doc = Metastatic.NL.AST.document([
      ...>   Metastatic.NL.AST.heading(1, [Metastatic.NL.AST.token("Title")])
      ...> ])
      iex> Metastatic.NL.Adapters.Markdown.unparse(doc)
      {:ok, "# Title"}
  """
  @impl true
  @spec unparse(map() | Metastatic.NL.AST.nl_node()) :: {:ok, String.t()} | {:error, String.t()}
  def unparse(%{"type" => _} = cst) do
    {:ok, FromMeta.to_source(cst)}
  end

  def unparse({type, _meta, _children} = node) when is_atom(type) do
    {:ok, FromMeta.to_source(node)}
  end

  def unparse(other) do
    {:error, "Cannot unparse to Markdown: #{inspect(other)}"}
  end

  @doc """
  File extensions handled by this adapter.

  `.md` and `.markdown` are the canonical Markdown extensions. `.mdx`
  (Markdown + JSX) is deliberately *not* claimed: its embedded JSX is not
  Markdown and would be mis-parsed.
  """
  @impl true
  @spec file_extensions() :: [String.t()]
  def file_extensions, do: [".md", ".markdown"]
end
