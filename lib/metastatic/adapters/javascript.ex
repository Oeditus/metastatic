defmodule Metastatic.Adapters.JavaScript do
  @moduledoc """
  JavaScript language adapter for MetaAST transformations.

  Bridges between JavaScript AST (M1 via Babel) and MetaAST (M2), enabling cross-language
  code analysis, transformation, and round-trip code generation for JS/ES6+/JSX source code.
  """

  @behaviour Metastatic.Adapter

  alias Metastatic.Adapters.JavaScript.{FromMeta, Subprocess, ToMeta}

  @impl true
  def parse(source) when is_binary(source) do
    Subprocess.parse(source)
  end

  @impl true
  def to_meta(js_ast) do
    js_ast
    |> ToMeta.transform()
    |> Metastatic.Adapter.enrich(:javascript)
  end

  @impl true
  def from_meta(meta_ast, metadata) do
    FromMeta.transform(meta_ast, metadata)
  end

  @impl true
  def unparse(js_ast) do
    Subprocess.unparse(js_ast)
  end

  @impl true
  def file_extensions do
    [".js", ".mjs", ".cjs", ".jsx"]
  end
end
