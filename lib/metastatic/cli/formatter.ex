defmodule Metastatic.CLI.Formatter do
  @moduledoc """
  Output formatting utilities for Metastatic CLI.

  Supports multiple output formats:
  - Tree format (default) - Human-readable tree structure
  - JSON format - Machine-readable JSON
  - Plain format - Simple text representation
  """

  alias Metastatic.{AST, Document}

  @type format :: :tree | :json | :plain
  @type meta_ast :: AST.meta_ast()

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
  def format(ast, :tree), do: format_tree(ast, 0)
  def format(ast, :json), do: format_json(ast)
  def format(ast, :plain), do: format_plain(ast)

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

  # Tree format - human-readable with tree structure
  # 3-tuple format: {type, meta, children_or_value}

  @spec format_tree(meta_ast(), non_neg_integer()) :: String.t()
  defp format_tree(ast, depth) do
    indent = String.duplicate("  ", depth)
    format_tree_node(ast, indent, depth)
  end

  # 3-tuple: {:literal, [subtype: type], value}
  defp format_tree_node({:literal, meta, value}, indent, _depth) when is_list(meta) do
    type = Keyword.get(meta, :subtype, :unknown)
    "#{indent}literal (#{type}): #{inspect(value)}"
  end

  # 3-tuple: {:variable, meta, name}
  defp format_tree_node({:variable, _meta, name}, indent, _depth) do
    "#{indent}variable: #{name}"
  end

  # 3-tuple: {:list, meta, elements}
  defp format_tree_node({:list, _meta, elements}, indent, depth) when is_list(elements) do
    element_lines = Enum.map(elements, &format_tree(&1, depth + 1))
    lines = ["#{indent}list" | element_lines]
    Enum.join(lines, "\n")
  end

  # 3-tuple: {:map, meta, pairs}
  defp format_tree_node({:map, _meta, pairs}, indent, depth) when is_list(pairs) do
    pair_lines =
      Enum.flat_map(pairs, fn
        {:pair, _, [key, value]} ->
          [
            "#{indent}  key:",
            format_tree(key, depth + 2),
            "#{indent}  value:",
            format_tree(value, depth + 2)
          ]

        {key, value} ->
          [
            "#{indent}  key:",
            format_tree(key, depth + 2),
            "#{indent}  value:",
            format_tree(value, depth + 2)
          ]
      end)

    lines = ["#{indent}map" | pair_lines]
    Enum.join(lines, "\n")
  end

  # 3-tuple: {:binary_op, [category: cat, operator: op], [left, right]}
  defp format_tree_node({:binary_op, meta, [left, right]}, indent, depth) when is_list(meta) do
    category = Keyword.get(meta, :category, :unknown)
    op = Keyword.get(meta, :operator, :unknown)

    lines = [
      "#{indent}binary_op (#{category}: #{op})",
      format_tree(left, depth + 1),
      format_tree(right, depth + 1)
    ]

    Enum.join(lines, "\n")
  end

  # 3-tuple: {:unary_op, [category: cat, operator: op], [operand]}
  defp format_tree_node({:unary_op, meta, [operand]}, indent, depth) when is_list(meta) do
    category = Keyword.get(meta, :category, :unknown)
    op = Keyword.get(meta, :operator, :unknown)

    lines = [
      "#{indent}unary_op (#{category}: #{op})",
      format_tree(operand, depth + 1)
    ]

    Enum.join(lines, "\n")
  end

  # 3-tuple: {:function_call, [name: name], args}
  defp format_tree_node({:function_call, meta, args}, indent, depth) when is_list(meta) do
    name = Keyword.get(meta, :name, "unknown")
    arg_lines = Enum.map(args, &format_tree(&1, depth + 1))

    lines = ["#{indent}function_call: #{name}" | arg_lines]

    Enum.join(lines, "\n")
  end

  # 3-tuple: {:conditional, meta, [condition, then_branch, else_branch?]}
  defp format_tree_node({:conditional, _meta, children}, indent, depth) when is_list(children) do
    {condition, then_branch, else_branch} =
      case children do
        [c, t, e] -> {c, t, e}
        [c, t] -> {c, t, nil}
      end

    lines = [
      "#{indent}conditional",
      "#{indent}  condition:",
      format_tree(condition, depth + 2),
      "#{indent}  then:",
      format_tree(then_branch, depth + 2)
    ]

    lines =
      if else_branch do
        lines ++
          [
            "#{indent}  else:",
            format_tree(else_branch, depth + 2)
          ]
      else
        lines
      end

    Enum.join(lines, "\n")
  end

  # 3-tuple: {:block, meta, statements}
  defp format_tree_node({:block, _meta, statements}, indent, depth) when is_list(statements) do
    statement_lines = Enum.map(statements, &format_tree(&1, depth + 1))
    lines = ["#{indent}block" | statement_lines]
    Enum.join(lines, "\n")
  end

  # 3-tuple: {:early_return, meta, [value]}
  defp format_tree_node({:early_return, meta, children}, indent, depth) when is_list(meta) do
    kind = Keyword.get(meta, :kind, :return)
    value = if is_list(children) and children != [], do: hd(children), else: nil

    lines = [
      "#{indent}early_return (#{kind})"
    ]

    lines =
      if value do
        lines ++ [format_tree(value, depth + 1)]
      else
        lines
      end

    Enum.join(lines, "\n")
  end

  # 3-tuple: {:loop, [loop_type: :while], [condition, body]}
  defp format_tree_node({:loop, meta, children}, indent, depth) when is_list(meta) do
    loop_type = Keyword.get(meta, :loop_type, :unknown)

    case {loop_type, children} do
      {:while, [condition, body]} ->
        lines = [
          "#{indent}loop (while)",
          "#{indent}  condition:",
          format_tree(condition, depth + 2),
          "#{indent}  body:",
          format_tree(body, depth + 2)
        ]

        Enum.join(lines, "\n")

      {kind, [iterator, collection, body]} when kind in [:for, :for_each] ->
        lines = [
          "#{indent}loop (#{kind})",
          "#{indent}  iterator:",
          format_tree(iterator, depth + 2),
          "#{indent}  collection:",
          format_tree(collection, depth + 2),
          "#{indent}  body:",
          format_tree(body, depth + 2)
        ]

        Enum.join(lines, "\n")

      _ ->
        "#{indent}loop (#{loop_type})"
    end
  end

  # 3-tuple: {:lambda, [params: params, captures: caps], [body]}
  defp format_tree_node({:lambda, meta, children}, indent, depth) when is_list(meta) do
    params = Keyword.get(meta, :params, [])
    captures = Keyword.get(meta, :captures, [])
    body = if is_list(children) and children != [], do: List.last(children), else: nil
    param_str = Enum.map_join(params, ", ", &format_param/1)

    lines = [
      "#{indent}lambda (#{param_str})",
      "#{indent}  captures: #{inspect(captures)}"
    ]

    lines =
      if body do
        lines ++ ["#{indent}  body:", format_tree(body, depth + 2)]
      else
        lines
      end

    Enum.join(lines, "\n")
  end

  # 3-tuple: {:collection_op, [op: :map|:filter], [lambda, collection]}
  defp format_tree_node({:collection_op, meta, children}, indent, depth) when is_list(meta) do
    op = Keyword.get(meta, :op, :unknown)

    case {op, children} do
      {op, [lambda, collection]} when op in [:map, :filter] ->
        lines = [
          "#{indent}collection_op (#{op})",
          "#{indent}  lambda:",
          format_tree(lambda, depth + 2),
          "#{indent}  collection:",
          format_tree(collection, depth + 2)
        ]

        Enum.join(lines, "\n")

      {:reduce, [lambda, collection, initial]} ->
        lines = [
          "#{indent}collection_op (reduce)",
          "#{indent}  lambda:",
          format_tree(lambda, depth + 2),
          "#{indent}  collection:",
          format_tree(collection, depth + 2),
          "#{indent}  initial:",
          format_tree(initial, depth + 2)
        ]

        Enum.join(lines, "\n")

      _ ->
        "#{indent}collection_op (#{op})"
    end
  end

  # 3-tuple: {:exception_handling, meta, [body, rescue_clauses, finally]}
  defp format_tree_node({:exception_handling, _meta, children}, indent, depth)
       when is_list(children) do
    {body, rescue_clauses, finally_clause} =
      case children do
        [b, r, f] -> {b, r, f}
        [b, r] -> {b, r, nil}
        [b] -> {b, [], nil}
      end

    lines = [
      "#{indent}exception_handling",
      "#{indent}  body:",
      format_tree(body, depth + 2),
      "#{indent}  rescue:"
    ]

    rescue_list = if is_list(rescue_clauses), do: rescue_clauses, else: []

    rescue_lines =
      Enum.flat_map(rescue_list, fn
        {:catch_clause, _, [_type, _var, handler]} ->
          [
            "#{indent}    handler:",
            format_tree(handler, depth + 3)
          ]

        {:rescue, _, [pattern, handler]} ->
          [
            "#{indent}    pattern:",
            format_tree(pattern, depth + 3),
            "#{indent}    handler:",
            format_tree(handler, depth + 3)
          ]

        other ->
          ["#{indent}    #{inspect(other)}"]
      end)

    lines = lines ++ rescue_lines

    lines =
      if finally_clause do
        lines ++
          [
            "#{indent}  finally:",
            format_tree(finally_clause, depth + 2)
          ]
      else
        lines
      end

    Enum.join(lines, "\n")
  end

  # 3-tuple: {:language_specific, [language: lang, hint: hint], native_ast}
  defp format_tree_node({:language_specific, meta, _native_ast}, indent, _depth)
       when is_list(meta) do
    language = Keyword.get(meta, :language, :unknown)
    hint = Keyword.get(meta, :hint)
    "#{indent}language_specific (#{language}, hint: #{inspect(hint)})"
  end

  # Fallback for any unrecognized 3-tuple
  defp format_tree_node({type, meta, _children}, indent, _depth)
       when is_atom(type) and is_list(meta) do
    "#{indent}#{type}"
  end

  defp format_tree_node(ast, indent, _depth) do
    "#{indent}#{inspect(ast)}"
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

  # JSON format - machine-readable
  # 3-tuple format: {type, meta, children_or_value}

  @spec format_json(meta_ast()) :: String.t()
  defp format_json(ast) do
    ast
    |> ast_to_map()
    |> Jason.encode!(pretty: true)
  end

  # 3-tuple: {:literal, [subtype: type], value}
  defp ast_to_map({:literal, meta, value}) when is_list(meta) do
    type = Keyword.get(meta, :subtype, :unknown)
    %{type: "literal", semantic_type: type, value: value}
  end

  # 3-tuple: {:variable, meta, name}
  defp ast_to_map({:variable, _meta, name}) do
    %{type: "variable", name: name}
  end

  # 3-tuple: {:list, meta, elements}
  defp ast_to_map({:list, _meta, elements}) when is_list(elements) do
    %{type: "list", elements: Enum.map(elements, &ast_to_map/1)}
  end

  # 3-tuple: {:map, meta, pairs}
  defp ast_to_map({:map, _meta, pairs}) when is_list(pairs) do
    %{
      type: "map",
      pairs:
        Enum.map(pairs, fn
          {:pair, _, [k, v]} -> %{key: ast_to_map(k), value: ast_to_map(v)}
          {k, v} -> %{key: ast_to_map(k), value: ast_to_map(v)}
        end)
    }
  end

  # 3-tuple: {:binary_op, [category: cat, operator: op], [left, right]}
  defp ast_to_map({:binary_op, meta, [left, right]}) when is_list(meta) do
    category = Keyword.get(meta, :category, :unknown)
    op = Keyword.get(meta, :operator, :unknown)

    %{
      type: "binary_op",
      category: category,
      operator: op,
      left: ast_to_map(left),
      right: ast_to_map(right)
    }
  end

  # 3-tuple: {:unary_op, [category: cat, operator: op], [operand]}
  defp ast_to_map({:unary_op, meta, [operand]}) when is_list(meta) do
    category = Keyword.get(meta, :category, :unknown)
    op = Keyword.get(meta, :operator, :unknown)

    %{
      type: "unary_op",
      category: category,
      operator: op,
      operand: ast_to_map(operand)
    }
  end

  # 3-tuple: {:function_call, [name: name], args}
  defp ast_to_map({:function_call, meta, args}) when is_list(meta) do
    name = Keyword.get(meta, :name, "unknown")

    %{
      type: "function_call",
      name: name,
      args: Enum.map(args, &ast_to_map/1)
    }
  end

  # 3-tuple: {:conditional, meta, [condition, then_branch, else_branch?]}
  defp ast_to_map({:conditional, _meta, children}) when is_list(children) do
    {condition, then_branch, else_branch} =
      case children do
        [c, t, e] -> {c, t, e}
        [c, t] -> {c, t, nil}
      end

    %{
      type: "conditional",
      condition: ast_to_map(condition),
      then_branch: ast_to_map(then_branch),
      else_branch: if(else_branch, do: ast_to_map(else_branch), else: nil)
    }
  end

  # 3-tuple: {:block, meta, statements}
  defp ast_to_map({:block, _meta, statements}) when is_list(statements) do
    %{
      type: "block",
      statements: Enum.map(statements, &ast_to_map/1)
    }
  end

  # 3-tuple: {:language_specific, [language: lang, hint: hint], native_ast}
  defp ast_to_map({:language_specific, meta, _native_ast}) when is_list(meta) do
    language = Keyword.get(meta, :language, :unknown)
    hint = Keyword.get(meta, :hint)

    %{
      type: "language_specific",
      language: language,
      hint: hint
    }
  end

  # Fallback for other 3-tuple types
  defp ast_to_map({type, meta, children}) when is_atom(type) and is_list(meta) do
    %{type: to_string(type), meta: Map.new(meta), children: format_children(children)}
  end

  defp ast_to_map(ast) do
    %{type: "unknown", data: inspect(ast)}
  end

  defp format_children(children) when is_list(children) do
    Enum.map(children, &ast_to_map/1)
  end

  defp format_children(value), do: value

  # Plain format - simple text representation
  # 3-tuple format: {type, meta, children_or_value}

  @spec format_plain(meta_ast()) :: String.t()

  # 3-tuple: {:literal, [subtype: type], value}
  defp format_plain({:literal, meta, value}) when is_list(meta) do
    type = Keyword.get(meta, :subtype, :unknown)
    "literal(#{type}, #{inspect(value)})"
  end

  # 3-tuple: {:variable, meta, name}
  defp format_plain({:variable, _meta, name}) do
    "variable(#{name})"
  end

  # 3-tuple: {:binary_op, [category: cat, operator: op], [left, right]}
  defp format_plain({:binary_op, meta, [left, right]}) when is_list(meta) do
    category = Keyword.get(meta, :category, :unknown)
    op = Keyword.get(meta, :operator, :unknown)
    "binary_op(#{category}, #{op}, #{format_plain(left)}, #{format_plain(right)})"
  end

  # 3-tuple: {:unary_op, [category: cat, operator: op], [operand]}
  defp format_plain({:unary_op, meta, [operand]}) when is_list(meta) do
    category = Keyword.get(meta, :category, :unknown)
    op = Keyword.get(meta, :operator, :unknown)
    "unary_op(#{category}, #{op}, #{format_plain(operand)})"
  end

  # 3-tuple: {:function_call, [name: name], args}
  defp format_plain({:function_call, meta, args}) when is_list(meta) do
    name = Keyword.get(meta, :name, "unknown")
    args_str = Enum.map_join(args, ", ", &format_plain/1)
    "function_call(#{name}, [#{args_str}])"
  end

  # Fallback for other 3-tuples
  defp format_plain({type, _meta, _children}) when is_atom(type) do
    to_string(type)
  end

  defp format_plain(ast) do
    inspect(ast)
  end
end
