defmodule Metastatic.Adapters.Java do
  @moduledoc """
  Java language adapter for MetaAST transformations.

  Bridges between Java AST (M1, produced by the JDK's own compiler API) and
  MetaAST (M2), enabling cross-language code analysis, transformation and
  round-trip code generation for Java source code.

  ## Java AST Structure (M1)

  Java is parsed by `com.sun.source.tree` -- the tree API that ships with every
  JDK -- and serialised to JSON. Every node is an object with a `"kind"` field
  naming its `Tree.Kind` and a `"pos"` field carrying source positions:

      %{"kind" => "BINARY", "pos" => %{"line" => 3, "col" => 8, "end_line" => 3, "end_col" => 13},
        "op" => "+", "left" => ..., "right" => ...}

  ### Examples

      # Integer literal
      %{"kind" => "INT_LITERAL", "value" => 42}

      # Variable
      %{"kind" => "IDENTIFIER", "name" => "x"}

      # Addition
      %{"kind" => "BINARY", "op" => "+",
        "left" => %{"kind" => "IDENTIFIER", "name" => "x"},
        "right" => %{"kind" => "INT_LITERAL", "value" => 5}}

      # Method call
      %{"kind" => "METHOD_INVOCATION", "name" => "foo", "args" => [...]}

  ## M1 <-> M2 Transformations

  ### Literals

      INT_LITERAL 42          -> {:literal, [subtype: :integer], 42}
      DOUBLE_LITERAL 3.14     -> {:literal, [subtype: :float], 3.14}
      STRING_LITERAL "hi"     -> {:literal, [subtype: :string], "hi"}
      BOOLEAN_LITERAL true    -> {:literal, [subtype: :boolean], true}
      NULL_LITERAL            -> {:literal, [subtype: :null], nil}

  ### Variables and Operators

      IDENTIFIER x            -> {:variable, [scope: :local], "x"}
      BINARY +                -> {:binary_op, [category: :arithmetic, operator: :+], [l, r]}
      UNARY !                 -> {:unary_op, [category: :boolean, operator: :not], [operand]}

  ### Calls

      METHOD_INVOCATION foo(...)      -> {:function_call, [name: "foo"], [...]}
      METHOD_INVOCATION obj.bar(...)  -> {:function_call, [name: "obj.bar"], [...]}
      NEW_CLASS_EXPR Foo(...)         -> {:function_call, [name: "Foo", constructor: true], [...]}

  ### Structure

      CLASS / INTERFACE / ENUM / RECORD -> {:container, [container_type: ..., name: ...], body}
      METHOD                            -> {:function_def, [name: ..., params: ...], body}
      IMPORT                            -> {:import, [source: ..., import_type: ...], []}

  ## Communication Strategy

  Java has no parser in the BEAM, so this adapter shells out to a small bridge
  program (`priv/parsers/java/parser.java`) compiled and executed by the JDK's
  single-file source launcher:

  1. **Parse**: write the source to a temp file, run the bridge, receive JSON
  2. **Unparse**: send the M1 JSON, receive source produced by `PrettyPrinter`

  The bridge needs **no external dependency** -- only a JDK 11+ (`java`) on the
  `PATH`. When it is missing, every callback returns a clear `{:error, reason}`
  instead of raising.

  ## Round-Trip Fidelity

  Java's tree API is lossy for formatting, so the target is *semantic*
  equivalence rather than byte-for-byte reproduction: comments and import
  ordering are not preserved, and source positions are carried in metadata
  only. The conformance suite compares canonicalised MetaAST, not text.

  ## Usage

      # Parse Java source
      {:ok, ast} = Metastatic.Adapters.Java.parse("class A { int f() { return 1 + 2; } }")

      # Transform to MetaAST
      {:ok, meta_ast, metadata} = Metastatic.Adapters.Java.to_meta(ast)

      # Transform back to Java AST
      {:ok, ast2} = Metastatic.Adapters.Java.from_meta(meta_ast, metadata)

      # Unparse to source
      {:ok, source} = Metastatic.Adapters.Java.unparse(ast2)
  """

  @behaviour Metastatic.Adapter

  alias Metastatic.Adapters.Java.{FromMeta, Subprocess, ToMeta}
  alias Metastatic.Semantic.Enricher

  @impl true
  def parse(source) when is_binary(source) do
    Subprocess.parse(source)
  end

  @impl true
  def to_meta(java_ast) do
    case ToMeta.transform(java_ast) do
      {:ok, meta_ast, metadata} ->
        # Enrich AST with semantic metadata (op_kind for JDBC/JPA operations, etc.)
        enriched_ast = Enricher.enrich_tree(meta_ast, :java)
        {:ok, enriched_ast, metadata}

      error ->
        error
    end
  end

  @impl true
  def from_meta(meta_ast, metadata) do
    FromMeta.transform(meta_ast, metadata)
  end

  @impl true
  def unparse(java_ast) do
    Subprocess.unparse(java_ast)
  end

  @impl true
  def file_extensions do
    [".java"]
  end
end
