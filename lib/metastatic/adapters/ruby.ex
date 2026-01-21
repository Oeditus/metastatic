defmodule Metastatic.Adapters.Ruby do
  @moduledoc """
  Ruby language adapter for MetaAST transformations.

  Bridges between Ruby AST (M1) and MetaAST (M2), enabling cross-language
  code analysis and transformation for Ruby source code.

  ## Ruby AST Structure (M1)

  Ruby uses the parser gem which represents AST as nodes with:
  - `type` - Symbol representing the syntactic construct
  - `children` - List of child nodes or values
  - `location` - Source location information

  ### Examples

      # Variable assignment
      %{type: "lvasgn", children: ["x", %{type: "int", children: [42]}]}

      # Method call
      %{type: "send", children: [receiver, :method_name, args...]}

      # Binary operation
      %{type: "send", children: [left, :+, right]}

  ## M1 ↔ M2 Transformations

  This adapter performs bidirectional transformations between Ruby AST (M1)
  and MetaAST (M2):

  ### Literals

      # M1 → M2
      %{type: "int", children: [42]}     → {:literal, :integer, 42}
      %{type: "float", children: [3.14]} → {:literal, :float, 3.14}
      %{type: "str", children: ["hello"]} → {:literal, :string, "hello"}
      %{type: "true"}                     → {:literal, :boolean, true}
      %{type: "nil"}                      → {:literal, :null, nil}
      %{type: "sym", children: [:foo]}    → {:literal, :symbol, :foo}

  ### Variables

      %{type: "lvar", children: [:x]}     → {:variable, "x"}
      %{type: "ivar", children: [:@x]}    → {:variable, "@x"}

  ### Binary Operations

      # x + 5
      %{type: "send", children: [x_node, :+, five_node]} → {:binary_op, :arithmetic, :+, left, right}

  ## Round-Trip Fidelity

  The adapter achieves >95% round-trip fidelity for M2.1 (Core) constructs.
  Metadata preserves information like:
  - Line numbers and columns
  - Variable scopes (local, instance, class, global)
  - Original syntax variants

  ## Usage

      # Parse Ruby source
      {:ok, ast} = Metastatic.Adapters.Ruby.parse("x = 42")

      # Transform to MetaAST
      {:ok, meta_ast, metadata} = Metastatic.Adapters.Ruby.to_meta(ast)

      # Transform back to Ruby AST
      {:ok, ast2} = Metastatic.Adapters.Ruby.from_meta(meta_ast, metadata)

      # Unparse to source
      {:ok, source} = Metastatic.Adapters.Ruby.unparse(ast2)
  """

  @behaviour Metastatic.Adapter

  alias Metastatic.Adapters.Ruby.{FromMeta, ToMeta}

  @parser_script Path.join([
                   :code.priv_dir(:metastatic),
                   "parsers",
                   "ruby",
                   "parser.rb"
                 ])

  @unparser_script Path.join([
                     :code.priv_dir(:metastatic),
                     "parsers",
                     "ruby",
                     "unparser.rb"
                   ])

  @impl true
  def parse(source) when is_binary(source) do
    case System.cmd("bundle", ["exec", "ruby", @parser_script],
           cd: Path.dirname(@parser_script),
           input: source,
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        case Jason.decode(output) do
          {:ok, %{"status" => "ok", "ast" => ast}} ->
            {:ok, ast}

          {:ok, %{"status" => "error", "error" => error}} ->
            {:error, "Parse error: #{error}"}

          {:error, reason} ->
            {:error, "JSON decode error: #{inspect(reason)}"}
        end

      {output, _exit_code} ->
        {:error, "Ruby parser failed: #{output}"}
    end
  end

  @impl true
  def to_meta(ruby_ast) do
    ToMeta.transform(ruby_ast)
  end

  @impl true
  def from_meta(meta_ast, metadata) do
    FromMeta.transform(meta_ast, metadata)
  end

  @impl true
  def unparse(ruby_ast) do
    json_input = Jason.encode!(%{ast: ruby_ast})

    case System.cmd("bundle", ["exec", "ruby", @unparser_script],
           cd: Path.dirname(@unparser_script),
           input: json_input,
           stderr_to_stdout: true
         ) do
      {source, 0} ->
        {:ok, source}

      {output, _exit_code} ->
        {:error, "Ruby unparser failed: #{output}"}
    end
  end

  @impl true
  def file_extensions do
    [".rb"]
  end
end
