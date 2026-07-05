defmodule Metastatic.Adapters.JavaScript do
  @moduledoc """
  JavaScript/TypeScript language adapter for MetaAST transformations.

  Converts JS/TS source directly into MetaAST 3-tuples using regex-based
  line-by-line scanning. This is a BEAM-native adapter that does NOT require
  a subprocess or external parser.

  ## M1 Representation

  The "native AST" (M1) for this adapter IS the MetaAST itself — we perform
  a single-pass translation directly from source text to MetaAST rather than
  going through an intermediate language-specific AST. This means `parse/1`
  returns the MetaAST tuple and `to_meta/1` is an identity pass.

  ## MetaAST Nodes Produced

  - `{:container, meta, children}` — ES6 classes and the file-level module
  - `{:function_def, meta, body}` — `function` declarations, arrow functions,
    class methods, and object-literal methods
  - `{:function_call, meta, args}` — call expressions found on each line
  - `{:import, meta, []}` — `import … from` and `require(…)` statements
  - `{:param, meta, name}` — function parameters

  ## Limitations

  - Read-only adapter (analysis only, no code generation)
  - Computed / anonymous method names are skipped
  - TypeScript type annotations are stripped (parameter count preserved)
  - Generic/template types are ignored
  - Complex destructured parameter lists use param-count approximation
  """

  @behaviour Metastatic.Adapter

  alias Metastatic.Adapters.JavaScript.ToMeta

  @impl true
  def file_extensions, do: [".js", ".jsx", ".ts", ".tsx", ".mjs", ".cjs"]

  @doc """
  Parse JS/TS source into a MetaAST (the M1 representation for this adapter).
  """
  @impl true
  def parse(source) when is_binary(source) do
    ToMeta.parse(source)
  end

  @doc """
  Identity pass — M1 *is* the MetaAST for this adapter.
  Returns `{:ok, meta_ast, %{}}`.
  """
  @impl true
  def to_meta(meta_ast) do
    {:ok, meta_ast, %{}}
  end

  @doc """
  Not implemented — this adapter is read-only (analysis only).
  """
  @impl true
  def from_meta(_meta_ast, _metadata), do: {:error, :not_implemented}

  @doc """
  Not implemented — this adapter is read-only (analysis only).
  """
  @impl true
  def unparse(_native_ast), do: {:error, :not_implemented}
end
