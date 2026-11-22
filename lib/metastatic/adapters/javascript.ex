defmodule Metastatic.Adapters.JavaScript do
  @moduledoc """
  JavaScript language adapter for MetaAST transformations.

  Bridges between JavaScript AST (M1 via Babel) and MetaAST (M2), enabling
  cross-language code analysis, transformation, and round-trip code generation
  for JS/ES2022+/JSX source code.

  ## Relationship to the TypeScript adapter

  JavaScript and TypeScript are two separate languages (`:javascript` and
  `:typescript`) that share the `JavaScript.ToMeta` / `JavaScript.FromMeta`
  translation pair. They are deliberately *not* merged into one adapter:

    * the Babel plugin sets are disjoint — `typescript` and `flow` cannot be
      enabled together, and enabling `typescript` for JavaScript changes the
      grammar;
    * the TypeScript grammar reserves identifiers and accepts type syntax that
      plain JavaScript must reject, so a single plugin set would silently
      accept `let x: number = 1` in a `.js` file.

  The dialect is selected at parse time (`Subprocess.parse/2`), so each adapter
  gets exactly the grammar it needs. Both accept bare expressions (`1 + 2`),
  matching every other adapter.

  ## Coverage

  Literals, operators, calls, member access, functions (declarations,
  expressions, arrows, generators, async), classes (methods, fields, private
  members, static blocks), destructuring, spread/rest, `switch`, labels, the
  comma operator, template and tagged-template literals, `try`/`catch`/
  `finally`, ES modules, and JSX. Constructs with no cross-language analogue
  (JSX, private names, static blocks) are preserved as `:language_specific`
  carrying the original M1 node, so they round-trip exactly.
  """

  @behaviour Metastatic.Adapter

  alias Metastatic.Adapters.JavaScript.{FromMeta, Subprocess, ToMeta}

  @impl true
  def parse(source) when is_binary(source) do
    Subprocess.parse(source, :javascript)
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
