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

  ## Examples

      iex> format({:literal, :integer, 42}, :plain)
      "literal(integer, 42)"

      iex> format({:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}}, :tree)
      "binary_op (arithmetic: +)\\n├─ variable: x\\n└─ literal (integer): 5"
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

  @spec format_tree(meta_ast(), non_neg_integer()) :: String.t()
  defp format_tree(ast, depth) do
    indent = String.duplicate("  ", depth)
    format_tree_node(ast, indent, depth)
  end

  defp format_tree_node({:literal, type, value}, indent, _depth) do
    "#{indent}literal (#{type}): #{inspect(value)}"
  end

  defp format_tree_node({:variable, name}, indent, _depth) do
    "#{indent}variable: #{name}"
  end

  defp format_tree_node({:list, elements}, indent, depth) do
    element_lines = Enum.map(elements, &format_tree(&1, depth + 1))
    lines = ["#{indent}list" | element_lines]
    Enum.join(lines, "\n")
  end

  defp format_tree_node({:map, pairs}, indent, depth) do
    pair_lines =
      Enum.flat_map(pairs, fn {key, value} ->
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

  defp format_tree_node({:binary_op, category, op, left, right}, indent, depth) do
    lines = [
      "#{indent}binary_op (#{category}: #{op})",
      format_tree(left, depth + 1),
      format_tree(right, depth + 1)
    ]

    Enum.join(lines, "\n")
  end

  defp format_tree_node({:unary_op, category, op, operand}, indent, depth) do
    lines = [
      "#{indent}unary_op (#{category}: #{op})",
      format_tree(operand, depth + 1)
    ]

    Enum.join(lines, "\n")
  end

  defp format_tree_node({:function_call, name, args}, indent, depth) do
    arg_lines = Enum.map(args, &format_tree(&1, depth + 1))

    lines = ["#{indent}function_call: #{name}" | arg_lines]

    Enum.join(lines, "\n")
  end

  defp format_tree_node({:conditional, condition, then_branch, else_branch}, indent, depth) do
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

  defp format_tree_node({:block, statements}, indent, depth) do
    statement_lines = Enum.map(statements, &format_tree(&1, depth + 1))
    lines = ["#{indent}block" | statement_lines]
    Enum.join(lines, "\n")
  end

  defp format_tree_node({:early_return, kind, value}, indent, depth) do
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

  defp format_tree_node({:loop, :while, condition, body}, indent, depth) do
    lines = [
      "#{indent}loop (while)",
      "#{indent}  condition:",
      format_tree(condition, depth + 2),
      "#{indent}  body:",
      format_tree(body, depth + 2)
    ]

    Enum.join(lines, "\n")
  end

  defp format_tree_node({:loop, kind, iterator, collection, body}, indent, depth)
       when kind in [:for, :for_each] do
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
  end

  defp format_tree_node({:lambda, params, captures, body}, indent, depth) do
    param_str = Enum.map_join(params, ", ", &format_param/1)

    lines = [
      "#{indent}lambda (#{param_str})",
      "#{indent}  captures: #{inspect(captures)}",
      "#{indent}  body:",
      format_tree(body, depth + 2)
    ]

    Enum.join(lines, "\n")
  end

  defp format_tree_node({:collection_op, op, lambda, collection}, indent, depth)
       when op in [:map, :filter] do
    lines = [
      "#{indent}collection_op (#{op})",
      "#{indent}  lambda:",
      format_tree(lambda, depth + 2),
      "#{indent}  collection:",
      format_tree(collection, depth + 2)
    ]

    Enum.join(lines, "\n")
  end

  defp format_tree_node({:collection_op, :reduce, lambda, collection, initial}, indent, depth) do
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
  end

  defp format_tree_node(
         {:exception_handling, body, rescue_clauses, finally_clause},
         indent,
         depth
       ) do
    lines = [
      "#{indent}exception_handling",
      "#{indent}  body:",
      format_tree(body, depth + 2),
      "#{indent}  rescue:"
    ]

    rescue_lines =
      Enum.flat_map(rescue_clauses, fn {:rescue, pattern, handler} ->
        [
          "#{indent}    pattern:",
          format_tree(pattern, depth + 3),
          "#{indent}    handler:",
          format_tree(handler, depth + 3)
        ]
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

  defp format_tree_node({:language_specific, language, _native_ast, hint}, indent, _depth) do
    "#{indent}language_specific (#{language}, hint: #{inspect(hint)})"
  end

  defp format_tree_node(ast, indent, _depth) do
    "#{indent}#{inspect(ast)}"
  end

  defp format_param({:param, name, type_hint, default}) do
    parts = [name]

    parts =
      if type_hint do
        parts ++ [": #{type_hint}"]
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

  @spec format_json(meta_ast()) :: String.t()
  defp format_json(ast) do
    ast
    |> ast_to_map()
    |> Jason.encode!(pretty: true)
  end

  defp ast_to_map({:literal, type, value}) do
    %{type: "literal", semantic_type: type, value: value}
  end

  defp ast_to_map({:variable, name}) do
    %{type: "variable", name: name}
  end

  defp ast_to_map({:list, elements}) do
    %{type: "list", elements: Enum.map(elements, &ast_to_map/1)}
  end

  defp ast_to_map({:map, pairs}) do
    %{
      type: "map",
      pairs: Enum.map(pairs, fn {k, v} -> %{key: ast_to_map(k), value: ast_to_map(v)} end)
    }
  end

  defp ast_to_map({:binary_op, category, op, left, right}) do
    %{
      type: "binary_op",
      category: category,
      operator: op,
      left: ast_to_map(left),
      right: ast_to_map(right)
    }
  end

  defp ast_to_map({:unary_op, category, op, operand}) do
    %{
      type: "unary_op",
      category: category,
      operator: op,
      operand: ast_to_map(operand)
    }
  end

  defp ast_to_map({:function_call, name, args}) do
    %{
      type: "function_call",
      name: name,
      args: Enum.map(args, &ast_to_map/1)
    }
  end

  defp ast_to_map({:conditional, condition, then_branch, else_branch}) do
    %{
      type: "conditional",
      condition: ast_to_map(condition),
      then_branch: ast_to_map(then_branch),
      else_branch: if(else_branch, do: ast_to_map(else_branch), else: nil)
    }
  end

  defp ast_to_map({:block, statements}) do
    %{
      type: "block",
      statements: Enum.map(statements, &ast_to_map/1)
    }
  end

  defp ast_to_map({:language_specific, language, _native_ast, hint}) do
    %{
      type: "language_specific",
      language: language,
      hint: hint
    }
  end

  defp ast_to_map(ast) do
    %{type: "unknown", data: inspect(ast)}
  end

  # Plain format - simple text representation

  @spec format_plain(meta_ast()) :: String.t()
  defp format_plain({:literal, type, value}) do
    "literal(#{type}, #{inspect(value)})"
  end

  defp format_plain({:variable, name}) do
    "variable(#{name})"
  end

  defp format_plain({:binary_op, category, op, left, right}) do
    "binary_op(#{category}, #{op}, #{format_plain(left)}, #{format_plain(right)})"
  end

  defp format_plain({:unary_op, category, op, operand}) do
    "unary_op(#{category}, #{op}, #{format_plain(operand)})"
  end

  defp format_plain({:function_call, name, args}) do
    args_str = Enum.map_join(args, ", ", &format_plain/1)
    "function_call(#{name}, [#{args_str}])"
  end

  defp format_plain(ast) do
    inspect(ast)
  end
end
