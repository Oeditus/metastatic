defmodule Metastatic.Adapters.Go do
  @moduledoc """
  Go language adapter backed by the Go standard library.

  `go/parser` parses source into an M1 JSON tree, which is translated to the
  uniform MetaAST representation. `go/format` prints reified trees. Go-specific
  constructs without a portable equivalent retain their native M1 payload.

  Accepts complete Go files and bare expressions. Requires a Go toolchain
  (Go 1.21 or newer), or `metastatic-go-parser` on PATH. The bundled bridge has
  no third-party Go dependencies and is compiled into a user cache, not into
  the installed package. Read-only deployments can preinstall the executable.
  """

  @behaviour Metastatic.Adapter

  alias Metastatic.Adapters.Go.{FromMeta, Subprocess, ToMeta}

  @doc """
  Parses a complete Go file or bare expression into its native AST.

  ## Examples

      iex> {:ok, ast} = Metastatic.Adapters.Go.parse("1 + 2")
      iex> ast["kind"]
      "BinaryExpr"
  """
  @impl true
  @spec parse(String.t()) :: {:ok, map()} | {:error, String.t()}
  def parse(source) when is_binary(source), do: Subprocess.parse(source)
  def parse(other), do: {:error, "Go source must be a binary, got: #{inspect(other)}"}

  @doc """
  Abstracts a native Go AST into MetaAST with semantic enrichment.

  ## Examples

      iex> {:ok, ast} = Metastatic.Adapters.Go.parse("1 + 2")
      iex> {:ok, {kind, _, _}, _} = Metastatic.Adapters.Go.to_meta(ast)
      iex> kind
      :binary_op
  """
  @impl true
  @spec to_meta(map(), keyword()) :: {:ok, Metastatic.AST.meta_ast(), map()} | {:error, String.t()}
  def to_meta(ast, opts \\ []) do
    ast
    |> ToMeta.transform()
    |> Metastatic.Adapter.enrich(:go, Keyword.take(opts, [:enrich]))
  end

  @doc """
  Reifies MetaAST into a native Go AST.

  ## Examples

      iex> {:ok, ast} = Metastatic.Adapters.Go.from_meta({:literal, [subtype: :integer], 42}, %{})
      iex> ast["kind"]
      "BasicLit"
  """
  @impl true
  @spec from_meta(Metastatic.AST.meta_ast(), map()) :: {:ok, map()} | {:error, String.t()}
  def from_meta(ast, metadata \\ %{}), do: FromMeta.transform(ast, metadata)

  @doc """
  Prints a native Go AST using `go/format`.

  ## Examples

      iex> {:ok, ast} = Metastatic.Adapters.Go.parse("1+2")
      iex> Metastatic.Adapters.Go.unparse(ast)
      {:ok, "1 + 2"}
  """
  @impl true
  @spec unparse(map()) :: {:ok, String.t()} | {:error, String.t()}
  def unparse(ast) when is_map(ast), do: Subprocess.unparse(ast)
  def unparse(other), do: {:error, "Invalid Go AST: #{inspect(other)}"}

  @doc """
  Returns the Go source file extension.

  ## Examples

      iex> Metastatic.Adapters.Go.file_extensions()
      [".go"]
  """
  @impl true
  @spec file_extensions() :: [String.t()]
  def file_extensions, do: [".go"]

  @doc """
  Returns `true` when Go parsing is available in this environment.
  """
  @impl true
  @spec available?() :: boolean()
  def available?, do: Subprocess.available?()
end
