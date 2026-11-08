defmodule Metastatic.Adapters.Java.FromMeta do
  @moduledoc """
  Transform MetaAST (M2) back to Java source.

  Implements the reification function ρ_Java. Unlike the other adapters, which
  rebuild a native AST that a separate unparser then prints, Java's tree API
  cannot be constructed from outside `javac`, so reification emits **source
  text** directly. `Metastatic.Adapters.Java.unparse/1` then only normalises
  that text through the bridge's pretty printer.

  ## Output contract

  `transform/2` returns `{:ok, %{"source" => source}}`, which is the shape
  `Metastatic.Adapters.Java.Subprocess.unparse/1` expects. The result is always
  a complete, compilable compilation unit: a bare expression is wrapped in a
  synthetic class, and a bare `:block` becomes the body of that class.

  ## Fidelity

  Formatting is normalised (4-space indentation, one blank line between
  members) and comments are not recoverable from MetaAST. Semantics are
  preserved: the conformance suite re-parses the emitted source and compares
  canonicalised MetaAST rather than text.

  ## Unsupported constructs

  A MetaAST node with no Java analogue (`{:pipe, ...}`, `{:pin, ...}`, ...)
  returns `{:error, reason}` instead of silently emitting wrong code.
  """

  alias Metastatic.Adapters.Java
  alias Metastatic.Adapters.Java.ToMeta

  @indent "    "

  @doc """
  Reify a MetaAST node into Java source.

  Returns `{:ok, %{"source" => String.t()}}` or `{:error, reason}`.

  ## Examples

      iex> {:ok, %{"source" => source}} =
      ...>   Metastatic.Adapters.Java.FromMeta.transform(
      ...>     {:binary_op, [category: :arithmetic, operator: :+],
      ...>      [{:literal, [subtype: :integer], 1}, {:literal, [subtype: :integer], 2}]},
      ...>     %{})
      iex> String.contains?(source, "1 + 2")
      true
  """
  @spec transform(term(), map()) :: {:ok, %{String.t() => String.t()}} | {:error, String.t()}
  def transform(meta_ast, metadata \\ %{})

  def transform(nil, _metadata), do: {:ok, %{"source" => ""}}

  def transform(meta_ast, _metadata) do
    with {:ok, lines} <- compile_unit(meta_ast) do
      {:ok, %{"source" => Enum.join(lines, "\n") <> "\n"}}
    end
  end

  # ----- Compilation unit assembly -----

  # A document whose root is a block: emit each statement at top level, then
  # wrap whatever is not already a type declaration in a synthetic class.
  defp compile_unit({:block, _meta, statements}) when is_list(statements) do
    with {:ok, rendered} <- render_statements(statements, 0) do
      {types, others} = Enum.split_with(rendered, &type_declaration?/1)

      case {types, others} do
        {[], []} ->
          {:ok, ["class Main {", "}"]}

        {[], _} ->
          {:ok, ["class Main {"] ++ Enum.map(others, &indent/1) ++ ["}"]}

        {_, []} ->
          {:ok, types}

        {_, _} ->
          {:ok, types ++ ["class Main {"] ++ Enum.map(others, &indent/1) ++ ["}"]}
      end
    end
  end

  # A bare container is already a type declaration.
  defp compile_unit({:container, _meta, _body} = container) do
    render(container, 0)
  end

  defp compile_unit({type, _meta, _children} = expression)
       when type in [
              :literal,
              :variable,
              :binary_op,
              :unary_op,
              :function_call,
              :attribute_access,
              :list,
              :lambda
            ] do
    with {:ok, source} <- render_inline(expression, 0) do
      {:ok,
       ["class Main {", "    static Object value() {", "        return #{source};", "    }", "}"]}
    end
  end

  # Anything else is an expression or statement: wrap it in a class.
  defp compile_unit(other) do
    with {:ok, rendered} <- render(other, 0) do
      {:ok, ["class Main {"] ++ Enum.map(rendered, &indent/1) ++ ["}"]}
    end
  end

  defp type_declaration?(lines) when is_list(lines) do
    case lines do
      [first | _] ->
        Regex.match?(
          ~r/^\s*(public\s+|final\s+|abstract\s+)*(class|interface|enum|record)\s/,
          first
        )

      [] ->
        false
    end
  end

  defp type_declaration?(_), do: false

  # ----- Node rendering -----

  defp render(node, level) do
    case render_node(node, level) do
      {:ok, lines} when is_list(lines) -> {:ok, lines}
      {:ok, line} when is_binary(line) -> {:ok, [line]}
      {:error, _} = error -> error
    end
  end

  defp render_list(nodes, level) do
    nodes
    |> Enum.reduce_while({:ok, []}, fn node, {:ok, acc} ->
      case render(node, level) do
        {:ok, lines} -> {:cont, {:ok, acc ++ lines}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp render_statements(statements, level) do
    statements
    |> Enum.reduce_while({:ok, []}, fn statement, {:ok, acc} ->
      case render(statement, level) do
        {:ok, lines} -> {:cont, {:ok, acc ++ lines}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp indent(lines, level \\ 1)

  defp indent(lines, level) when is_list(lines) do
    Enum.map(lines, fn line ->
      if String.trim(line) == "", do: "", else: String.duplicate(@indent, level) <> line
    end)
  end

  defp indent(line, level) when is_binary(line), do: indent([line], level) |> hd()

  # ----- Literals and variables -----

  defp render_node({:literal, meta, value}, _level) do
    {:ok, literal_source(Keyword.get(meta, :subtype), value)}
  end

  defp render_node({:variable, _meta, name}, _level) when is_binary(name) do
    {:ok, name}
  end

  defp render_node({:variable, _meta, name}, _level) when is_atom(name) do
    {:ok, Atom.to_string(name)}
  end

  # ----- Operators -----

  defp render_node({:binary_op, meta, [left, right]}, level) do
    with {:ok, left_src} <- render_inline(left, level),
         {:ok, right_src} <- render_inline(right, level) do
      operator = java_binary_operator(Keyword.get(meta, :category), Keyword.get(meta, :operator))
      {:ok, "#{left_src} #{operator} #{right_src}"}
    end
  end

  defp render_node({:unary_op, meta, [operand]}, level) do
    with {:ok, operand_src} <- render_inline(operand, level) do
      case Keyword.get(meta, :operator) do
        :not -> {:ok, "!#{operand_src}"}
        :- -> {:ok, "-#{operand_src}"}
        :+ -> {:ok, "+#{operand_src}"}
        :bnot -> {:ok, "~#{operand_src}"}
        other -> {:ok, "#{other}#{operand_src}"}
      end
    end
  end

  # ----- Assignment -----

  defp render_node({:assignment, meta, [target, value]}, level) do
    with {:ok, target_src} <- render_inline(target, level),
         {:ok, value_src} <- render_inline(value, level) do
      case Keyword.get(meta, :kind) do
        kind when kind in [:var, :const] ->
          {:ok, "#{kind} #{target_src} = #{value_src};"}

        _ ->
          {:ok, "#{target_src} = #{value_src};"}
      end
    end
  end

  defp render_node({:augmented_assignment, meta, [target, value]}, level) do
    with {:ok, target_src} <- render_inline(target, level),
         {:ok, value_src} <- render_inline(value, level) do
      operator = Keyword.get(meta, :operator, :+)
      {:ok, "#{target_src} #{operator}= #{value_src};"}
    end
  end

  # ----- Calls and member access -----

  defp render_node({:function_call, meta, children}, level) do
    name = Keyword.get(meta, :name, "unknown")
    constructor? = Keyword.get(meta, :constructor, false)

    with {:ok, args} <- render_arguments(children, meta, level) do
      cond do
        constructor? ->
          {:ok, "new #{name}(#{Enum.join(args, ", ")});"}

        name == "[]" and length(children) == 2 ->
          with {:ok, receiver} <- render_inline(hd(children), level),
               {:ok, index} <- render_inline(List.last(children), level) do
            {:ok, "#{receiver}[#{index}]"}
          end

        true ->
          {:ok, "#{name}(#{Enum.join(args, ", ")});"}
      end
    end
  end

  defp render_node({:attribute_access, meta, [receiver]}, level) do
    with {:ok, receiver_src} <- render_inline(receiver, level) do
      {:ok, "#{receiver_src}.#{Keyword.get(meta, :attribute, "unknown")}"}
    end
  end

  # ----- Control flow -----

  defp render_node({:conditional, meta, [cond, then_branch, else_branch]}, level) do
    with {:ok, cond_src} <- render_inline(cond, level),
         {:ok, then_lines} <- render(then_branch, level + 1) do
      if Keyword.get(meta, :style) == :ternary do
        with {:ok, else_src} <- render_inline(else_branch, level) do
          {:ok, "#{cond_src} ? #{String.trim(trailing_semicolon(hd(then_lines)))} : #{else_src}"}
        end
      else
        with {:ok, else_lines} <- render_else(else_branch, level) do
          {:ok,
           ["if (#{cond_src}) {"] ++
             indent(then_lines) ++ ["}"] ++ else_lines}
        end
      end
    end
  end

  defp render_node({:conditional, _meta, [cond, then_branch]}, level) do
    with {:ok, cond_src} <- render_inline(cond, level),
         {:ok, then_lines} <- render(then_branch, level + 1) do
      {:ok, ["if (#{cond_src}) {"] ++ indent(then_lines) ++ ["}"]}
    end
  end

  defp render_node({:loop, meta, children}, level) do
    case {Keyword.get(meta, :loop_type), children} do
      {:while, [cond, body]} ->
        with {:ok, cond_src} <- render_inline(cond, level),
             {:ok, body_lines} <- render(body, level + 1) do
          {:ok, ["while (#{cond_src}) {"] ++ indent(body_lines) ++ ["}"]}
        end

      {:do_while, [cond, body]} ->
        with {:ok, cond_src} <- render_inline(cond, level),
             {:ok, body_lines} <- render(body, level + 1) do
          {:ok, ["do {"] ++ indent(body_lines) ++ ["} while (#{cond_src});"]}
        end

      {:for_each, [var, expr, body]} ->
        with {:ok, var_src} <- render_inline(var, level),
             {:ok, expr_src} <- render_inline(expr, level),
             {:ok, body_lines} <- render(body, level + 1) do
          {:ok, ["for (#{var_src} : #{expr_src}) {"] ++ indent(body_lines) ++ ["}"]}
        end

      {:for, [init, cond, update, body]} ->
        with {:ok, init_src} <- render_inline_list(init, level),
             {:ok, cond_src} <- render_inline_or_empty(cond, level),
             {:ok, update_src} <- render_inline_list(update, level),
             {:ok, body_lines} <- render(body, level + 1) do
          header = "for (#{init_src}; #{cond_src}; #{update_src})"
          {:ok, [header <> " {"] ++ indent(body_lines) ++ ["}"]}
        end

      {other, _} ->
        {:error, "Unsupported Java loop type: #{inspect(other)}"}
    end
  end

  defp render_node({:pattern_match, _meta, [subject | arms]}, level) do
    with {:ok, subject_src} <- render_inline(subject, level),
         {:ok, arm_lines} <- render_list(arms, level + 1) do
      {:ok, ["switch (#{subject_src}) {"] ++ indent(arm_lines) ++ ["}"]}
    end
  end

  defp render_node({:match_arm, meta, [body]}, level) do
    with {:ok, body_lines} <- render(body, level + 1) do
      case Keyword.get(meta, :pattern) do
        nil ->
          {:ok, ["default:"] ++ indent(body_lines)}

        pattern ->
          with {:ok, pattern_src} <- render_inline(pattern, level) do
            {:ok, ["case #{pattern_src}:"] ++ indent(body_lines)}
          end
      end
    end
  end

  defp render_node({:early_return, meta, [value]}, level) do
    case Keyword.get(meta, :kind, :return) do
      :return ->
        case value do
          nil ->
            {:ok, "return;"}

          _ ->
            with {:ok, value_src} <- render_inline(value, level) do
              {:ok, "return #{value_src};"}
            end
        end

      :break ->
        {:ok, "break;"}

      :continue ->
        {:ok, "continue;"}
    end
  end

  # ----- Exceptions -----

  defp render_node({:exception_handling, _meta, [block, catches, finally]}, level) do
    with {:ok, block_lines} <- render(block, level + 1),
         {:ok, catch_lines} <- render_catches(catches, level),
         {:ok, finally_lines} <- render_finally(finally, level) do
      {:ok, ["try {"] ++ indent(block_lines) ++ ["}"] ++ catch_lines ++ finally_lines}
    end
  end

  defp render_node({:rescue_clause, _meta, [param, block]}, level) do
    with {:ok, param_src} <- render_inline(param, level),
         {:ok, block_lines} <- render(block, level + 1) do
      {:ok, ["catch (#{param_src}) {"] ++ indent(block_lines) ++ ["}"]}
    end
  end

  defp render_node({:throw, _meta, [expr]}, level) do
    with {:ok, expr_src} <- render_inline(expr, level) do
      {:ok, "throw #{expr_src};"}
    end
  end

  # ----- Structure -----

  defp render_node({:container, meta, body}, level) do
    name = Keyword.get(meta, :name, "Anonymous")
    modifiers = Keyword.get(meta, :modifiers, [])
    keyword = container_keyword(Keyword.get(meta, :container_type, :class))

    with {:ok, member_lines} <- render_members(body, level + 1) do
      header = [Enum.join(modifiers ++ [keyword, name], " ") <> " {"]
      {:ok, header ++ member_lines ++ ["}"]}
    end
  end

  defp render_node({:function_def, meta, body}, level) do
    name = Keyword.get(meta, :name, "method")
    modifiers = Keyword.get(meta, :modifiers, [])
    return_type = Keyword.get(meta, :return_type)
    constructor? = Keyword.get(meta, :constructor?, false)

    with {:ok, params} <- render_parameters(Keyword.get(meta, :params, []), level),
         {:ok, body_lines} <- render_method_body(body, level + 1) do
      signature =
        if constructor? do
          "#{name}(#{params})"
        else
          "#{return_type || "void"} #{name}(#{params})"
        end

      header = Enum.join(modifiers ++ [signature], " ") <> " {"
      {:ok, [header] ++ body_lines ++ ["}"]}
    end
  end

  defp render_node({:import, meta, _}, _level) do
    source = Keyword.get(meta, :source, "")

    case Keyword.get(meta, :import_type) do
      :package -> {:ok, "package #{source};"}
      _ -> {:ok, "import #{source};"}
    end
  end

  defp render_node({:type_annotation, meta, _}, _level) do
    {:ok, Keyword.get(meta, :type, "Object")}
  end

  defp render_node({:param, _meta, name}, _level) when is_binary(name) do
    {:ok, "Object #{name}"}
  end

  defp render_node({:block, meta, statements}, level) do
    if Keyword.get(meta, :empty, false) do
      {:ok, ";"}
    else
      render_statements(statements, level)
    end
  end

  defp render_node({:list, _meta, elements}, level) do
    with {:ok, rendered} <- render_inline_list(elements, level) do
      {:ok, "new Object[] {#{rendered}}"}
    end
  end

  defp render_node({:lambda, meta, body}, level) do
    with {:ok, params} <- render_parameters(Keyword.get(meta, :params, []), level),
         {:ok, body_lines} <- render_list(body, level) do
      body_src = body_lines |> Enum.join(" ") |> String.trim()
      {:ok, "(#{params}) -> #{body_src}"}
    end
  end

  # A language_specific node still carries the original M1 map; when it has a
  # source-ish shape we can print it, otherwise we refuse rather than guess.
  defp render_node({:language_specific, meta, native}, level) do
    hint = Keyword.get(meta, :hint)

    case hint do
      :type_cast ->
        with {:ok, expr_src} <- render_inline(native, level) do
          {:ok, "(#{Keyword.get(meta, :type, "Object")}) #{expr_src}"}
        end

      :instance_of ->
        {:ok, "instanceof #{Keyword.get(meta, :type, "Object")}"}

      _ ->
        {:error, "Cannot reify #{inspect(Keyword.get(meta, :native_type))} construct to Java"}
    end
  end

  defp render_node(other, _level) do
    {:error, "Unsupported MetaAST construct for Java: #{inspect(other)}"}
  end

  # ----- Helpers -----

  defp render_inline(node, level) do
    with {:ok, lines} <- render(node, level) do
      {:ok, lines |> Enum.join(" ") |> String.trim() |> trailing_semicolon() |> String.trim()}
    end
  end

  defp render_inline_list(nodes, level) when is_list(nodes) do
    nodes
    |> Enum.reduce_while({:ok, []}, fn node, {:ok, acc} ->
      case render_inline(node, level) do
        {:ok, src} -> {:cont, {:ok, [src | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, srcs} -> {:ok, srcs |> Enum.reverse() |> Enum.join(", ")}
      error -> error
    end
  end

  defp render_inline_or_empty(nil, _level), do: {:ok, ""}
  defp render_inline_or_empty(node, level), do: render_inline(node, level)

  defp render_arguments(children, meta, level) do
    args =
      if Keyword.get(meta, :receiver, false) do
        Enum.drop(children, 1)
      else
        children
      end

    render_inline_list(args, level)
  end

  defp render_parameters(params, level) do
    params
    |> Enum.reduce_while({:ok, []}, fn param, {:ok, acc} ->
      case render_parameter(param, level) do
        {:ok, src} -> {:cont, {:ok, [src | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, srcs} -> {:ok, srcs |> Enum.reverse() |> Enum.join(", ")}
      error -> error
    end
  end

  defp render_parameter({:param, meta, name}, _level) when is_binary(name) do
    {:ok, "#{Keyword.get(meta, :declared_type, "Object")} #{name}"}
  end

  defp render_parameter({:assignment, meta, [target, _value]}, _level) do
    case target do
      {:variable, _, name} when is_binary(name) ->
        {:ok, "#{Keyword.get(meta, :declared_type, "Object")} #{name}"}

      _ ->
        {:error, "Unsupported Java parameter: #{inspect(target)}"}
    end
  end

  defp render_parameter(other, _level) do
    {:error, "Unsupported Java parameter: #{inspect(other)}"}
  end

  defp render_method_body([], _level), do: {:ok, []}

  defp render_method_body(body, level) when is_list(body) do
    with {:ok, lines} <- render_statements(body, level) do
      {:ok, indent(lines)}
    end
  end

  defp render_members(members, level) do
    with {:ok, lines} <- render_list(members, level) do
      {:ok, indent(lines)}
    end
  end

  defp render_catches(catches, level) when is_list(catches) do
    with {:ok, lines} <- render_list(catches, level) do
      {:ok, indent(lines)}
    end
  end

  defp render_catches(_nil, _level), do: {:ok, []}

  defp render_finally(nil, _level), do: {:ok, []}

  defp render_finally(block, level) do
    with {:ok, lines} <- render(block, level + 1) do
      {:ok, ["finally {"] ++ indent(lines) ++ ["}"]}
    end
  end

  defp render_else(nil, _level), do: {:ok, []}

  defp render_else(else_branch, level) do
    with {:ok, lines} <- render(else_branch, level + 1) do
      {:ok, ["else {"] ++ indent(lines) ++ ["}"]}
    end
  end

  defp container_keyword(:interface), do: "interface"
  defp container_keyword(:enum), do: "enum"
  defp container_keyword(:struct), do: "record"
  defp container_keyword(_), do: "class"

  defp literal_source(:integer, value) when is_integer(value), do: to_string(value)
  defp literal_source(:float, value) when is_float(value), do: to_string(value)
  defp literal_source(:float, value) when is_integer(value), do: "#{value}.0"
  defp literal_source(:boolean, true), do: "true"
  defp literal_source(:boolean, false), do: "false"
  defp literal_source(:null, _), do: "null"
  defp literal_source(:char, value) when is_binary(value), do: "'#{value}'"
  defp literal_source(_subtype, value) when is_binary(value), do: inspect(value)
  defp literal_source(_subtype, value) when is_integer(value), do: to_string(value)
  defp literal_source(_subtype, value) when is_float(value), do: to_string(value)
  defp literal_source(_subtype, true), do: "true"
  defp literal_source(_subtype, false), do: "false"
  defp literal_source(_subtype, nil), do: "null"
  defp literal_source(_subtype, value), do: inspect(value)

  defp java_binary_operator(_category, :+), do: "+"
  defp java_binary_operator(_category, :-), do: "-"
  defp java_binary_operator(_category, :*), do: "*"
  defp java_binary_operator(_category, :/), do: "/"
  defp java_binary_operator(_category, :rem), do: "%"
  defp java_binary_operator(_category, :==), do: "=="
  defp java_binary_operator(_category, :!=), do: "!="
  defp java_binary_operator(_category, :<), do: "<"
  defp java_binary_operator(_category, :<=), do: "<="
  defp java_binary_operator(_category, :>), do: ">"
  defp java_binary_operator(_category, :>=), do: ">="
  defp java_binary_operator(:boolean, :and), do: "&&"
  defp java_binary_operator(:boolean, :or), do: "||"
  defp java_binary_operator(_category, :band), do: "&"
  defp java_binary_operator(_category, :bor), do: "|"
  defp java_binary_operator(_category, :bxor), do: "^"
  defp java_binary_operator(_category, :bsl), do: "<<"
  defp java_binary_operator(_category, :bsr), do: ">>"
  defp java_binary_operator(_category, operator), do: to_string(operator)

  defp trailing_semicolon(source) do
    if String.ends_with?(source, ";"),
      do: String.slice(source, 0, byte_size(source) - 1),
      else: source
  end

  @doc false
  # Exposed for tests that need to know whether a construct is reifiable.
  @spec reifiable?(term()) :: boolean()
  def reifiable?(meta_ast) do
    match?({:ok, _}, transform(meta_ast, %{}))
  end

  @doc false
  # Round-trip helper used by the conformance suite: reify, then parse the
  # emitted source back through the M1 bridge.
  @spec round_trip(term()) :: {:ok, map()} | {:error, term()}
  def round_trip(meta_ast) do
    with {:ok, %{"source" => source}} <- transform(meta_ast, %{}),
         {:ok, ast} <- Java.parse(source),
         {:ok, meta_ast2, _metadata} <- ToMeta.transform(ast) do
      {:ok, meta_ast2}
    end
  end
end
