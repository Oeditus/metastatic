defmodule Metastatic.Adapters.SQL do
  @moduledoc """
  SQL language adapter for MetaAST transformations via `sqlparser-rs`.

  Bridges between SQL AST (M1) and MetaAST (M2), enabling cross-language
  code analysis, linting, and semantic querying across ANSI, PostgreSQL, MySQL,
  SQLite, and other SQL dialects.

  ## M1 <-> M2 Transformations

  - Literals (numbers, strings, booleans, null) -> `{:literal, ...}`
  - Identifiers and column references -> `{:variable, ...}`
  - Qualified identifiers (`table.column`) -> `{:attribute_access, ...}`
  - Expressions and binary/unary operators -> `{:binary_op, ...}`, `{:unary_op, ...}`
  - SQL functions (`COUNT`, `LOWER`, etc.) -> `{:function_call, ...}`
  - Queries (`SELECT`, `INSERT`, `UPDATE`, `DELETE`) -> `{:function_call, [op_kind: ...], ...}`
    enriched with `:db` semantic operation metadata.
  """

  @behaviour Metastatic.Adapter

  alias Metastatic.Adapters.SQL.{FromMeta, Subprocess, ToMeta}

  @impl true
  def parse(source) when is_binary(source) do
    Subprocess.parse(source)
  end

  @doc """
  Parse SQL source code with optional dialect configuration.

  Returns `{:ok, ast}` on full success, or `{:ok, ast, metadata}` when the
  script contained statements the underlying parser could not model. In the
  latter case `metadata.unsupported` lists the skipped statements as
  `%{"source" => sql, "reason" => reason}` maps.

  ## Examples

      iex> {:ok, _ast} = Metastatic.Adapters.SQL.parse("SELECT 1", dialect: :postgres)

      iex> {:ok, _ast, %{unsupported: [_ | _]}} =
      ...>   Metastatic.Adapters.SQL.parse(
      ...>     "GRANT SELECT ON t TO r;\nALTER DEFAULT PRIVILEGES GRANT SELECT ON TABLES TO r;",
      ...>     dialect: :postgres
      ...>   )
  """
  @spec parse(String.t(), keyword()) ::
          {:ok, term()} | {:ok, term(), map()} | {:error, String.t()}
  def parse(source, opts) when is_binary(source) and is_list(opts) do
    Subprocess.parse(source, opts)
  end

  @impl true
  def to_meta(sql_ast) do
    to_meta(sql_ast, [])
  end

  @doc """
  Transform SQL AST to MetaAST with options.
  """
  @impl true
  @spec to_meta(term(), keyword()) :: {:ok, term(), map()} | {:error, String.t()}
  def to_meta(sql_ast, opts) when is_list(opts) do
    ToMeta.transform(sql_ast, opts)
  end

  @impl true
  def from_meta(meta_ast, metadata \\ %{}) do
    FromMeta.transform(meta_ast, metadata)
  end

  @impl true
  def unparse(sql_ast) do
    Subprocess.unparse(sql_ast)
  end

  @impl true
  def file_extensions do
    [".sql"]
  end
end
