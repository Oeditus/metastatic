defmodule Metastatic.CLI.Formatter do
  @moduledoc """
  Output formatting utilities for Metastatic CLI.

  Supports three output formats, all rendered from a single canonical
  intermediate representation produced by `to_map/1`:

  - `:tree` (default) -- human-readable, indented tree
  - `:json` -- machine-readable JSON
  - `:plain` -- compact single-line text

  ## Why a single intermediate

  Historically each format had its own pattern-match ladder over MetaAST
  nodes, so adding or changing a node type meant editing three functions in
  lockstep. `to_map/1` now normalises every node into one shape:

      %{type: atom, meta: keyword, children: [map] | value, label: String.t()}

  - `type`     -- the MetaAST node type atom
  - `meta`     -- the node's metadata keyword list
  - `children` -- normalised child maps (or the raw leaf value)
  - `label`    -- a format-independent short description used by the tree
                  and plain renderers (e.g. `"binary_op (arithmetic: +)"`)

  Tree, JSON and plain renderers then only need to *walk* this one shape,
  never to re-interpret MetaAST again.
  """

  alias Metastatic.{AST, Document}

  @type format :: :tree | :json | :plain
  @type meta_ast :: AST.meta_ast()

  @typedoc "Canonical intermediate node consumed by every renderer."
  @type node_map :: %{
          type: atom(),
          meta: keyword(),
          children: [node_map()] | term(),
          label: String.t()
        }

  @doc """
  Format a MetaAST node for display.

  Uses 3-tuple format: {type, meta, children_or_value}

  ## Examples

      iex> format({:literal, [subtype: :integer], 42}, :plain)
      "literal(integer, 42)"

      iex> format({:binary_op, [category: :arithmetic, operator: :+], [{:variable, [], "x"}, {:literal, [subtype: :integer], 5}]}, :tree)
      "binary_op (arithmetic: +)\\n  variable: x\\n  literal (integer): 5"
  """
  @spec format(meta_ast(), format()) :: String.t()
  def format(ast, :tree), do: ast |> to_map() |> render_tree(0)
  def format(ast, :json), do: ast |> to_map() |> render_json()
  def format(ast, :plain), do: ast |> to_map() |> render_plain()

  @doc """
  Format a Document for display.

  Includes metadata about language, validation status, etc.
  """
  @spec format_document(Document.t(), format()) :: String.t()
  def format_document(%Document{} = doc, format) do
    header = [
      "Language: #{doc.language}",
      "AST:"
    ]

    ast_output = format(doc.ast, format)

    Enum.join(header, "\n") <> "\n" <> ast_output
  end

  # ----- Canonical intermediate -----

  @doc """
  Normalise a MetaAST node into the canonical `node_map` shape.

  Every renderer consumes this, so node-type knowledge lives in exactly one
  place. Leaf nodes keep their raw value in `children`; composite nodes carry
  a list of normalised child maps.

  ## Examples

      iex> m = Metastatic.CLI.Formatter.to_map({:literal, [subtype: :integer], 42})
      iex> {m.type, m.label}
      {:literal, "literal (integer)"}
  """
  @spec to_map(meta_ast() | term()) :: node_map()
  def to_map({:literal, meta, value}) when is_list(meta) do
    subtype = Keyword.get(meta, :subtype, :unknown)
    %{type: :literal, meta: meta, children: value, label: "literal (#{subtype})"}
  end

  def to_map({:variable, meta, name}) when is_list(meta) do
    %{type: :variable, meta: meta, children: name, label: "variable: #{name}"}
  end

  def to_map({:list, meta, elements}) when is_list(meta) and is_list(elements) do
    %{type: :list, meta: meta, children: map_children(elements), label: "list"}
  end

  def to_map({:map, meta, pairs}) when is_list(meta) and is_list(pairs) do
    # Pairs are normalised as `:pair` nodes; a bare `{k, v}` tuple is coerced
    # into one so downstream renderers see a uniform shape.
    normalised_pairs =
      Enum.map(pairs, fn
        {:pair, _pair_meta, [k, v]} ->
          %{type: :pair, meta: [], children: [to_map(k), to_map(v)], label: "pair"}

        {k, v} ->
          %{type: :pair, meta: [], children: [to_map(k), to_map(v)], label: "pair"}
      end)

    %{type: :map, meta: meta, children: normalised_pairs, label: "map"}
  end

  def to_map({:binary_op, meta, [left, right]}) when is_list(meta) do
    category = Keyword.get(meta, :category, :unknown)
    operator = Keyword.get(meta, :operator, :unknown)

    %{
      type: :binary_op,
      meta: meta,
      children: [to_map(left), to_map(right)],
      label: "binary_op (#{category}: #{operator})"
    }
  end

  def to_map({:unary_op, meta, [operand]}) when is_list(meta) do
    category = Keyword.get(meta, :category, :unknown)
    operator = Keyword.get(meta, :operator, :unknown)

    %{
      type: :unary_op,
      meta: meta,
      children: [to_map(operand)],
      label: "unary_op (#{category}: #{operator})"
    }
  end

  def to_map({:function_call, meta, args}) when is_list(meta) and is_list(args) do
    name = Keyword.get(meta, :name, "unknown")

    %{
      type: :function_call,
      meta: meta,
      children: map_children(args),
      label: "function_call: #{name}"
    }
  end

  def to_map({:conditional, meta, children}) when is_list(meta) and is_list(children) do
    {condition, then_branch, else_branch} =
      case children do
        [c, t, e] -> {c, t, e}
        [c, t] -> {c, t, nil}
      end

    mapped =
      [
        %{type: :role, meta: [], children: to_map(condition), label: "condition"},
        %{type: :role, meta: [], children: to_map(then_branch), label: "then"}
      ]

    mapped =
      if else_branch do
        mapped ++ [%{type: :role, meta: [], children: to_map(else_branch), label: "else"}]
      else
        mapped
      end

    %{type: :conditional, meta: meta, children: mapped, label: "conditional"}
  end

  def to_map({:block, meta, statements}) when is_list(meta) and is_list(statements) do
    %{type: :block, meta: meta, children: map_children(statements), label: "block"}
  end

  def to_map({:early_return, meta, children}) when is_list(meta) do
    kind = Keyword.get(meta, :kind, :return)
    value = if is_list(children) and children != [], do: hd(children), else: nil

    %{
      type: :early_return,
      meta: meta,
      children: if(value, do: [to_map(value)], else: []),
      label: "early_return (#{kind})"
    }
  end

  def to_map({:loop, meta, children}) when is_list(meta) do
    loop_type = Keyword.get(meta, :loop_type, :unknown)
    {label, mapped} = map_loop(loop_type, children)
    %{type: :loop, meta: meta, children: mapped, label: label}
  end

  def to_map({:lambda, meta, children}) when is_list(meta) do
    params = Keyword.get(meta, :params, [])
    captures = Keyword.get(meta, :captures, [])
    body = if is_list(children) and children != [], do: List.last(children), else: nil
    param_str = Enum.map_join(params, ", ", &format_param/1)

    mapped =
      if body do
        [%{type: :role, meta: [], children: to_map(body), label: "body"}]
      else
        []
      end

    %{
      type: :lambda,
      meta: meta,
      children: mapped,
      label: "lambda (#{param_str})",
      captures: captures
    }
  end

  def to_map({:collection_op, meta, children}) when is_list(meta) do
    op = Keyword.get(meta, :op, :unknown)
    {label, mapped} = map_collection_op(op, children)
    %{type: :collection_op, meta: meta, children: mapped, label: label}
  end

  def to_map({:exception_handling, meta, children}) when is_list(meta) and is_list(children) do
    %{
      type: :exception_handling,
      meta: meta,
      children: map_exception(children),
      label: "exception_handling"
    }
  end

  def to_map({:language_specific, meta, _native_ast}) when is_list(meta) do
    language = Keyword.get(meta, :language, :unknown)
    hint = Keyword.get(meta, :hint)

    %{
      type: :language_specific,
      meta: meta,
      children: nil,
      label: "language_specific (#{language}, hint: #{inspect(hint)})"
    }
  end

  # Fallback for any other 3-tuple node type.
  def to_map({type, meta, children}) when is_atom(type) and is_list(meta) do
    mapped = if is_list(children), do: map_children(children), else: children
    %{type: type, meta: meta, children: mapped, label: to_string(type)}
  end

  def to_map(other) do
    %{type: :unknown, meta: [], children: other, label: inspect(other)}
  end

  # ----- Tree renderer -----

  @spec render_tree(node_map(), non_neg_integer()) :: String.t()
  defp render_tree(%{type: :role, label: label, children: child}, depth) do
    indent = String.duplicate("  ", depth)
    "#{indent}#{label}:\n" <> render_tree(child, depth + 1)
  end

  defp render_tree(%{type: :pair, children: [key, value]}, depth) do
    indent = String.duplicate("  ", depth)

    "#{indent}key:\n" <>
      render_tree(key, depth + 1) <> "\n" <> "#{indent}value:\n" <> render_tree(value, depth + 1)
  end

  defp render_tree(%{type: :lambda, label: label, captures: captures, children: children}, depth) do
    indent = String.duplicate("  ", depth)
    head = "#{indent}#{label}\n#{indent}  captures: #{inspect(captures)}"
    render_tree_children(head, children, depth)
  end

  defp render_tree(%{type: :literal, meta: meta, children: value}, depth) do
    indent = String.duplicate("  ", depth)
    "#{indent}literal (#{Keyword.get(meta, :subtype, :unknown)}): #{inspect(value)}"
  end

  defp render_tree(%{type: :variable, children: name}, depth) do
    indent = String.duplicate("  ", depth)
    "#{indent}variable: #{name}"
  end

  defp render_tree(%{label: label, children: children}, depth) do
    indent = String.duplicate("  ", depth)
    render_tree_children("#{indent}#{label}", children, depth)
  end

  defp render_tree_children(head, children, depth) when is_list(children) do
    case Enum.map(children, &render_tree(&1, depth + 1)) do
      [] -> head
      lines -> Enum.join([head | lines], "\n")
    end
  end

  defp render_tree_children(head, value, _depth), do: "#{head}: #{inspect(value)}"

  # ----- JSON renderer -----

  @spec render_json(node_map()) :: String.t()
  defp render_json(node_map) do
    node_map
    |> json_map()
    |> Jason.encode!(pretty: true)
  end

  defp json_map(%{type: :literal, meta: meta, children: value}) do
    %{type: "literal", semantic_type: Keyword.get(meta, :subtype, :unknown), value: value}
  end

  defp json_map(%{type: :variable, children: name}) do
    %{type: "variable", name: name}
  end

  defp json_map(%{type: :list, children: elements}) do
    %{type: "list", elements: Enum.map(elements, &json_map/1)}
  end

  defp json_map(%{type: :map, children: pairs}) do
    %{type: "map", pairs: Enum.map(pairs, &json_pair/1)}
  end

  defp json_map(%{type: :binary_op, meta: meta, children: [left, right]}) do
    %{
      type: "binary_op",
      category: Keyword.get(meta, :category, :unknown),
      operator: Keyword.get(meta, :operator, :unknown),
      left: json_map(left),
      right: json_map(right)
    }
  end

  defp json_map(%{type: :unary_op, meta: meta, children: [operand]}) do
    %{
      type: "unary_op",
      category: Keyword.get(meta, :category, :unknown),
      operator: Keyword.get(meta, :operator, :unknown),
      operand: json_map(operand)
    }
  end

  defp json_map(%{type: :function_call, meta: meta, children: args}) do
    %{
      type: "function_call",
      name: Keyword.get(meta, :name, "unknown"),
      args: Enum.map(args, &json_map/1)
    }
  end

  defp json_map(%{type: :conditional, children: roles}) do
    by_label = Map.new(roles, fn %{label: label, children: child} -> {label, child} end)

    %{
      type: "conditional",
      condition: json_map(by_label["condition"]),
      then_branch: json_map(by_label["then"]),
      else_branch: if(by_label["else"], do: json_map(by_label["else"]), else: nil)
    }
  end

  defp json_map(%{type: :block, children: statements}) do
    %{type: "block", statements: Enum.map(statements, &json_map/1)}
  end

  defp json_map(%{type: :language_specific, meta: meta}) do
    %{
      type: "language_specific",
      language: Keyword.get(meta, :language, :unknown),
      hint: Keyword.get(meta, :hint)
    }
  end

  defp json_map(%{type: type, meta: meta, children: children}) do
    %{type: to_string(type), meta: Map.new(meta), children: json_children(children)}
  end

  defp json_pair(%{type: :pair, children: [key, value]}) do
    %{key: json_map(key), value: json_map(value)}
  end

  defp json_children(children) when is_list(children), do: Enum.map(children, &json_map/1)
  defp json_children(value), do: value

  # ----- Plain renderer -----

  @spec render_plain(node_map()) :: String.t()
  defp render_plain(%{type: :literal, meta: meta, children: value}) do
    "literal(#{Keyword.get(meta, :subtype, :unknown)}, #{inspect(value)})"
  end

  defp render_plain(%{type: :variable, children: name}) do
    "variable(#{name})"
  end

  defp render_plain(%{type: :binary_op, meta: meta, children: [left, right]}) do
    category = Keyword.get(meta, :category, :unknown)
    operator = Keyword.get(meta, :operator, :unknown)
    "binary_op(#{category}, #{operator}, #{render_plain(left)}, #{render_plain(right)})"
  end

  defp render_plain(%{type: :unary_op, meta: meta, children: [operand]}) do
    category = Keyword.get(meta, :category, :unknown)
    operator = Keyword.get(meta, :operator, :unknown)
    "unary_op(#{category}, #{operator}, #{render_plain(operand)})"
  end

  defp render_plain(%{type: :function_call, meta: meta, children: args}) do
    name = Keyword.get(meta, :name, "unknown")
    args_str = Enum.map_join(args, ", ", &render_plain/1)
    "function_call(#{name}, [#{args_str}])"
  end

  defp render_plain(%{type: type}) when is_atom(type), do: to_string(type)

  defp render_plain(%{children: value}), do: inspect(value)

  # ----- Shared helpers -----

  defp map_children(children) when is_list(children), do: Enum.map(children, &to_map/1)

  defp map_loop(loop_type, children) do
    case {loop_type, children} do
      {:while, [condition, body]} ->
        {"loop (while)",
         [
           %{type: :role, meta: [], children: to_map(condition), label: "condition"},
           %{type: :role, meta: [], children: to_map(body), label: "body"}
         ]}

      {kind, [iterator, collection, body]} when kind in [:for, :for_each] ->
        {"loop (#{kind})",
         [
           %{type: :role, meta: [], children: to_map(iterator), label: "iterator"},
           %{type: :role, meta: [], children: to_map(collection), label: "collection"},
           %{type: :role, meta: [], children: to_map(body), label: "body"}
         ]}

      _ ->
        {"loop (#{loop_type})", []}
    end
  end

  defp map_collection_op(op, children) do
    case {op, children} do
      {op, [lambda, collection]} when op in [:map, :filter] ->
        {"collection_op (#{op})",
         [
           %{type: :role, meta: [], children: to_map(lambda), label: "lambda"},
           %{type: :role, meta: [], children: to_map(collection), label: "collection"}
         ]}

      {:reduce, [lambda, collection, initial]} ->
        {"collection_op (reduce)",
         [
           %{type: :role, meta: [], children: to_map(lambda), label: "lambda"},
           %{type: :role, meta: [], children: to_map(collection), label: "collection"},
           %{type: :role, meta: [], children: to_map(initial), label: "initial"}
         ]}

      _ ->
        {"collection_op (#{op})", []}
    end
  end

  defp map_exception(children) do
    {body, rescue_clauses, finally_clause} =
      case children do
        [b, r, f] -> {b, r, f}
        [b, r] -> {b, r, nil}
        [b] -> {b, [], nil}
      end

    rescue_list = if is_list(rescue_clauses), do: rescue_clauses, else: []

    rescue_roles =
      Enum.map(rescue_list, fn
        {:catch_clause, _, [_type, _var, handler]} ->
          %{type: :role, meta: [], children: to_map(handler), label: "handler"}

        {:rescue, _, [pattern, handler]} ->
          %{
            type: :role,
            meta: [],
            children: [to_map(pattern), to_map(handler)],
            label: "rescue"
          }

        other ->
          %{type: :role, meta: [], children: other, label: inspect(other)}
      end)

    base = [%{type: :role, meta: [], children: to_map(body), label: "body"}]

    tail =
      if finally_clause do
        [%{type: :role, meta: [], children: to_map(finally_clause), label: "finally"}]
      else
        []
      end

    base ++ rescue_roles ++ tail
  end

  # 3-tuple params: {:param, [pattern: pattern, default: default], name}
  defp format_param({:param, meta, name}) when is_binary(name) do
    pattern = Keyword.get(meta, :pattern)
    default = Keyword.get(meta, :default)
    parts = [name]

    parts =
      if pattern do
        parts ++ [" (pattern: #{inspect(pattern)})"]
      else
        parts
      end

    parts =
      if default do
        parts ++ [" = #{inspect(default)}"]
      else
        parts
      end

    Enum.join(parts, "")
  end

  # Handle string params (e.g. from Python lambda)
  defp format_param(name) when is_binary(name), do: name
  defp format_param(other), do: inspect(other)
end
