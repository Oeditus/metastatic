defmodule Metastatic.Adapters.Rust.FromMeta do
  @moduledoc """
  Transform MetaAST (M2) back to a Rust AST for `syn` (M1).

  Reifies universal AST nodes back into the M1 mirror the bridge understands.
  Nodes that originated as `:language_specific` are restored **verbatim** from
  their preserved M1 payload, which is what makes unsupported Rust constructs
  round-trip exactly.

  ## Strategy

  Every `:language_specific` node carries its original M1 map, so reification
  of those is an identity. Everything else is rebuilt from the MetaAST shape.
  When a node cannot be reified (an M2 construct Rust has no syntax for), the
  transform returns `{:error, reason}` rather than emitting something invalid.
  """

  @doc """
  Transform MetaAST back to a Rust AST map.

  Returns `{:ok, rust_ast}` on success or `{:error, reason}` on failure.

  ## Examples

      iex> ast = {:binary_op, [category: :arithmetic, operator: :+],
      ...>   [{:literal, [subtype: :integer], 1}, {:literal, [subtype: :integer], 2}]}
      iex> {:ok, %{"kind" => "Binary"}} = Metastatic.Adapters.Rust.FromMeta.transform(ast, %{})
  """
  @spec transform(term(), map()) :: {:ok, term()} | {:error, String.t()}
  def transform(meta_ast, metadata \\ %{})

  # Preserved native payloads are restored exactly.
  def transform({:language_specific, _meta, native_ast}, _metadata) when is_map(native_ast) do
    {:ok, native_ast}
  end

  # Parentheses wrap an *already abstracted* node, so they are reified by
  # recursing into the child rather than by restoring a native payload.
  def transform({:language_specific, meta, inner}, metadata)
      when is_list(meta) and is_tuple(inner) do
    if Keyword.get(meta, :hint) == :paren do
      with {:ok, inner_node} <- transform(inner, metadata) do
        {:ok, %{"kind" => "Paren", "span" => span(meta), "children" => [inner_node]}}
      end
    else
      {:error, "Cannot reify language-specific Rust node: #{inspect(inner, limit: 3)}"}
    end
  end

  def transform({:block, meta, statements}, metadata) when is_list(statements) do
    with {:ok, children} <- transform_list(statements, metadata) do
      # The top-level `:block` is the file; a nested one is a block expression.
      # `to_meta` marks the former with `scope: :module`.
      kind = if Keyword.get(meta, :scope) == :module, do: "File", else: "Block"

      {:ok, %{"kind" => kind, "span" => span(meta), "children" => children}}
    end
  end

  def transform({type, meta, children}, metadata) when is_atom(type) and is_list(meta) do
    transform_node(type, meta, children, metadata)
  end

  def transform(other, _metadata) do
    {:error, "Cannot reify MetaAST to Rust: #{inspect(other, limit: 5)}"}
  end

  # ----- Node Transformers -----

  defp transform_node(:literal, meta, value, _metadata) do
    subtype = Keyword.get(meta, :subtype, :string)

    literal =
      case {subtype, value} do
        {:integer, number} when is_integer(number) ->
          %{"subtype" => "integer", "value" => number}

        {:integer, text} when is_binary(text) ->
          %{"subtype" => "big_integer", "value" => text}

        {:float, number} when is_number(number) ->
          %{"subtype" => "float", "value" => number * 1.0}

        {:boolean, flag} when is_boolean(flag) ->
          %{"subtype" => "boolean", "value" => flag}

        {:char, text} when is_binary(text) ->
          %{"subtype" => "char", "value" => text}

        {:bytes, binary} when is_binary(binary) ->
          %{"subtype" => "bytes", "value" => :binary.bin_to_list(binary)}

        {_other, text} when is_binary(text) ->
          %{"subtype" => "string", "value" => text}

        {_other, other} ->
          %{"subtype" => "string", "value" => to_string(other)}
      end

    {:ok, %{"kind" => "Literal", "span" => span(meta), "value" => literal}}
  end

  defp transform_node(:variable, meta, name, _metadata) when is_binary(name) do
    kind = if Keyword.get(meta, :scope) == :field, do: "FieldName", else: "Path"
    {:ok, %{"kind" => kind, "span" => span(meta), "name" => name}}
  end

  defp transform_node(:wildcard, meta, _value, _metadata) do
    {:ok, %{"kind" => "Wild", "span" => span(meta)}}
  end

  defp transform_node(:binary_op, meta, [left, right], metadata) do
    with {:ok, left_node} <- transform(left, metadata),
         {:ok, right_node} <- transform(right, metadata) do
      operator = Keyword.get(meta, :operator, :+)

      {:ok,
       %{
         "kind" => "Binary",
         "span" => span(meta),
         "name" => binary_operator_to_rust(operator),
         "children" => [left_node, right_node]
       }}
    end
  end

  defp transform_node(:unary_op, meta, [operand], metadata) do
    with {:ok, operand_node} <- transform(operand, metadata) do
      operator = Keyword.get(meta, :operator, :-)

      # `&x` / `&mut x` is modelled as a unary op with `operator: :ref`.
      if operator == :ref do
        node = %{"kind" => "Reference", "span" => span(meta), "children" => [operand_node]}

        node =
          if Keyword.get(meta, :mutable, false),
            do: Map.put(node, "mutability", true),
            else: node

        {:ok, node}
      else
        {:ok,
         %{
           "kind" => "Unary",
           "span" => span(meta),
           "name" => unary_operator_to_rust(operator),
           "children" => [operand_node]
         }}
      end
    end
  end

  defp transform_node(:function_call, meta, args, metadata) when is_list(args) do
    with {:ok, arg_nodes} <- transform_list(args, metadata) do
      name = Keyword.get(meta, :name, "call")

      case {name, arg_nodes} do
        # `[]` is the modelled form of Rust's indexing operator (see `ToMeta`).
        {"[]", [collection, index]} ->
          {:ok,
           %{
             "kind" => "Index",
             "span" => span(meta),
             "children" => [collection, index]
           }}

        {_, _} ->
          transform_call(name, arg_nodes, meta)
      end
    end
  end

  defp transform_node(:conditional, meta, children, metadata) when is_list(children) do
    # A `nil` else branch must be dropped *before* transformation: `transform/2`
    # has no clause for `nil` and would fail the whole node.
    with {:ok, nodes} <- transform_list(Enum.reject(children, &is_nil/1), metadata) do
      {:ok, %{"kind" => "If", "span" => span(meta), "children" => nodes}}
    end
  end

  defp transform_node(:early_return, meta, children, metadata) when is_list(children) do
    with {:ok, nodes} <- transform_list(children, metadata) do
      {:ok, %{"kind" => "Return", "span" => span(meta), "children" => nodes}}
    end
  end

  defp transform_node(:block, meta, statements, metadata) when is_list(statements) do
    with {:ok, children} <- transform_list(statements, metadata) do
      {:ok, %{"kind" => "Block", "span" => span(meta), "children" => children}}
    end
  end

  defp transform_node(:list, meta, elements, metadata) when is_list(elements) do
    with {:ok, children} <- transform_list(elements, metadata) do
      {:ok, %{"kind" => "Array", "span" => span(meta), "children" => children}}
    end
  end

  defp transform_node(:tuple, meta, elements, metadata) when is_list(elements) do
    with {:ok, children} <- transform_list(elements, metadata) do
      {:ok, %{"kind" => "Tuple", "span" => span(meta), "children" => children}}
    end
  end

  defp transform_node(:range, meta, bounds, metadata) when is_list(bounds) do
    # A padded bound is `nil` (see `ToMeta`), meaning the range is half-open.
    with {:ok, children} <- transform_list(Enum.reject(bounds, &is_nil/1), metadata) do
      {:ok, %{"kind" => "Range", "span" => span(meta), "children" => children}}
    end
  end

  defp transform_node(:assignment, meta, [target, value], metadata) do
    with {:ok, value_node} <- transform(value, metadata) do
      # `ToMeta` records whether the source was a `let` binding, which is the
      # only reliable discriminator: `self.value = x` and `let value = x` both
      # have a `:variable`-shaped target once abstracted.
      if Keyword.get(meta, :rust_kind) == "Let" do
        # The target is a *pattern* here, so it must go through
        # `transform_pattern/2`: `transform/2` would emit a tuple expression.
        with {:ok, pattern} <- transform_pattern(target, metadata) do
          {:ok,
           %{
             "kind" => "Let",
             "span" => span(meta),
             "pattern" => pattern,
             "children" => [value_node]
           }}
        end
      else
        with {:ok, target_node} <- transform(target, metadata) do
          {:ok,
           %{
             "kind" => "Assign",
             "span" => span(meta),
             "children" => [target_node, value_node]
           }}
        end
      end
    end
  end

  defp transform_node(:loop, meta, children, metadata) when is_list(children) do
    with {:ok, nodes} <- transform_list(children, metadata) do
      case {Keyword.get(meta, :loop_type), nodes} do
        {:while, [condition, body]} ->
          {:ok, %{"kind" => "While", "span" => span(meta), "children" => [condition, body]}}

        {:for, [pattern, iterable, body]} ->
          {:ok,
           %{
             "kind" => "ForLoop",
             "span" => span(meta),
             "pattern" => pattern,
             "children" => [iterable, body]
           }}

        {:infinite, [body]} ->
          {:ok, %{"kind" => "Loop", "span" => span(meta), "children" => [body]}}

        {_other, nodes} ->
          {:ok, %{"kind" => "Loop", "span" => span(meta), "children" => nodes}}
      end
    end
  end

  defp transform_node(:pattern_match, meta, children, metadata) when is_list(children) do
    with {:ok, nodes} <- transform_list(children, metadata) do
      {:ok, %{"kind" => "Match", "span" => span(meta), "children" => nodes}}
    end
  end

  defp transform_node(:match_arm, meta, body, metadata) when is_list(body) do
    with {:ok, body_nodes} <- transform_list(body, metadata),
         {:ok, pattern} <- transform_pattern(Keyword.get(meta, :pattern), metadata) do
      {:ok,
       %{
         "kind" => "MatchArm",
         "span" => span(meta),
         "pattern" => pattern,
         "children" => body_nodes
       }}
    end
  end

  defp transform_node(:lambda, meta, body, metadata) when is_list(body) do
    with {:ok, body_nodes} <- transform_list(body, metadata) do
      {:ok, %{"kind" => "Closure", "span" => span(meta), "children" => body_nodes}}
    end
  end

  defp transform_node(:async_operation, meta, children, metadata) when is_list(children) do
    with {:ok, nodes} <- transform_list(children, metadata) do
      kind = if Keyword.get(meta, :op_type) == :async, do: "Async", else: "Await"
      {:ok, %{"kind" => kind, "span" => span(meta), "children" => nodes}}
    end
  end

  # `if let` / `while let` scrutinee.
  defp transform_node(:inline_match, meta, [pattern, value], metadata) do
    with {:ok, pattern_node} <- transform_pattern(pattern, metadata),
         {:ok, value_node} <- transform(value, metadata) do
      {:ok,
       %{
         "kind" => "LetExpr",
         "span" => span(meta),
         "pattern" => pattern_node,
         "children" => [value_node]
       }}
    end
  end

  defp transform_node(:exception_handling, meta, [inner | _rest], metadata) do
    with {:ok, inner_node} <- transform(inner, metadata) do
      {:ok, %{"kind" => "Try", "span" => span(meta), "children" => [inner_node]}}
    end
  end

  defp transform_node(:attribute_access, meta, [receiver], metadata) do
    with {:ok, receiver_node} <- transform(receiver, metadata) do
      {:ok,
       %{
         "kind" => "FieldAccess",
         "span" => span(meta),
         "name" => Keyword.get(meta, :attribute, "field"),
         "children" => [receiver_node]
       }}
    end
  end

  defp transform_node(:map, meta, pairs, metadata) when is_list(pairs) do
    with {:ok, fields} <- transform_list(pairs, metadata) do
      {:ok,
       %{
         "kind" => "StructExpr",
         "span" => span(meta),
         "name" => Keyword.get(meta, :struct, "Struct"),
         "children" => fields
       }}
    end
  end

  defp transform_node(:pair, meta, [key, value], metadata) do
    with {:ok, key_node} <- transform(key, metadata),
         {:ok, value_node} <- transform(value, metadata) do
      name =
        case key_node do
          %{"name" => name} when is_binary(name) -> name
          _ -> "field"
        end

      {:ok,
       %{
         "kind" => "StructField",
         "span" => span(meta),
         "name" => name,
         "children" => [value_node]
       }}
    end
  end

  defp transform_node(:function_def, meta, body, metadata) when is_list(body) do
    with {:ok, body_nodes} <- transform_list(body, metadata),
         {:ok, param_nodes} <- transform_list(Keyword.get(meta, :params, []), metadata) do
      node = %{
        "kind" => "Function",
        "span" => span(meta),
        "name" => Keyword.get(meta, :name, "anonymous"),
        "children" => param_nodes ++ body_nodes
      }

      # The declared return type is carried separately from the body so the
      # signature survives the round-trip; `nil` means "no `-> T`".
      node =
        case Keyword.get(meta, :return_type) do
          nil -> node
          type -> Map.put(node, "type_node", %{"kind" => "Type", "name" => type})
        end

      {:ok, node}
    end
  end

  defp transform_node(:container, meta, body, metadata) when is_list(body) do
    with {:ok, body_nodes} <- transform_list(body, metadata) do
      kind =
        case Keyword.get(meta, :rust_kind) do
          nil ->
            case Keyword.get(meta, :container_type) do
              :struct -> "Struct"
              :enum -> "Enum"
              :trait -> "Trait"
              _ -> "Module"
            end

          rust_kind ->
            rust_kind
        end

      {:ok,
       %{
         "kind" => kind,
         "span" => span(meta),
         "name" => Keyword.get(meta, :name, "anonymous"),
         "children" => body_nodes
       }}
    end
  end

  defp transform_node(:import, meta, _children, _metadata) do
    {:ok,
     %{
       "kind" => "Use",
       "span" => span(meta),
       "name" => Keyword.get(meta, :source, "")
     }}
  end

  defp transform_node(:type_annotation, meta, _children, _metadata) do
    {:ok,
     %{
       "kind" => "TypeAlias",
       "span" => span(meta),
       "name" => Keyword.get(meta, :name, "type"),
       "type_node" => %{
         "kind" => "Type",
         "span" => span(meta),
         "name" => Keyword.get(meta, :type_name) || "()"
       }
     }}
  end

  defp transform_node(:param, meta, name, metadata) when is_binary(name) do
    type_name = Keyword.get(meta, :type_name)

    # A `:param` reached from a Rust `Field` is a struct field declaration, not
    # a function parameter. `ToMeta` records the original kind so the two are
    # distinguishable here.
    case Keyword.get(meta, :rust_kind) do
      "Field" ->
        {:ok,
         %{
           "kind" => "Field",
           "span" => span(meta),
           "name" => name,
           "type_node" => %{"kind" => "Type", "span" => span(meta), "name" => type_name || "()"}
         }}

      _ ->
        # The pattern is preserved by `ToMeta`; rebuilding it as an `Ident`
        # would lose `self` receivers and destructured parameters.
        with {:ok, pattern} <- transform_pattern(Keyword.get(meta, :pattern), metadata) do
          {:ok,
           %{
             "kind" => "Param",
             "span" => span(meta),
             "pattern" => pattern,
             "type_node" => %{"kind" => "Type", "span" => span(meta), "name" => type_name || "()"}
           }}
        end
    end
  end

  # A `:param` inside a `:container` is a struct field declaration, not a
  # function parameter: `to_meta` maps `Field` onto `:param` because a named,
  # typed slot is the closest cross-language analogue.
  defp transform_node(type, _meta, _children, _metadata) do
    {:error, "Cannot reify MetaAST type `#{type}` to Rust"}
  end

  # Splits a call name into receiver/method when it is dotted. `ToMeta` sets
  # `rust_kind: "MethodCall"` so a method call is recovered even when the
  # receiver is not a simple path (e.g. a chained call).
  defp transform_call(name, arg_nodes, meta) do
    if Keyword.get(meta, :rust_kind) == "MethodCall" do
      method = Keyword.get(meta, :method, name)

      {receiver_node, rest} =
        case arg_nodes do
          [first | tail] -> {first, tail}
          [] -> {%{"kind" => "Path", "span" => span(meta), "name" => name}, []}
        end

      {:ok,
       with_semi(
         %{
           "kind" => "MethodCall",
           "span" => span(meta),
           "name" => method,
           "children" => [receiver_node | rest]
         },
         meta
       )}
    else
      {:ok,
       with_semi(
         %{"kind" => "Call", "span" => span(meta), "name" => name, "children" => arg_nodes},
         meta
       )}
    end
  end

  # ----- Patterns -----

  defp transform_pattern(nil, _metadata), do: {:ok, %{"kind" => "Wild"}}

  defp transform_pattern({:wildcard, meta, _}, _metadata) do
    {:ok, %{"kind" => "Wild", "span" => span(meta)}}
  end

  defp transform_pattern({:variable, meta, name}, _metadata) when is_binary(name) do
    # Receivers round-trip through their original kind (`Self`, `RefSelf`, …).
    case Keyword.get(meta, :receiver) do
      nil ->
        node = %{"kind" => "Ident", "span" => span(meta), "name" => name}

        node =
          if Keyword.get(meta, :mutable, false),
            do: Map.put(node, "mutability", true),
            else: node

        {:ok, node}

      receiver ->
        {:ok, %{"kind" => receiver, "span" => span(meta), "name" => name}}
    end
  end

  defp transform_pattern({:tuple, meta, elements}, metadata) when is_list(elements) do
    with {:ok, children} <- transform_pattern_list(elements, metadata) do
      {:ok, %{"kind" => "TuplePat", "span" => span(meta), "children" => children}}
    end
  end

  defp transform_pattern(other, metadata), do: transform(other, metadata)

  defp transform_pattern_list(elements, metadata) do
    Enum.reduce_while(elements, {:ok, []}, fn element, {:ok, acc} ->
      case transform_pattern(element, metadata) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      error -> error
    end
  end

  # ----- Helpers -----

  defp transform_list(items, metadata) when is_list(items) do
    Enum.reduce_while(items, {:ok, []}, fn item, {:ok, acc} ->
      case transform(item, metadata) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      error -> error
    end
  end

  defp span(meta) when is_list(meta) do
    case {Keyword.get(meta, :line), Keyword.get(meta, :col)} do
      {line, col} when is_integer(line) and line > 0 ->
        %{"line" => line, "col" => col || 1, "end_line" => line, "end_col" => col || 1}

      _ ->
        %{"line" => 0, "col" => 0, "end_line" => 0, "end_col" => 0}
    end
  end

  defp span(_), do: %{"line" => 0, "col" => 0, "end_line" => 0, "end_col" => 0}

  # Attaches the recorded statement terminator to a reified node.
  defp with_semi(node, meta) when is_map(node) and is_list(meta) do
    if Keyword.get(meta, :semi, false), do: Map.put(node, "semi", true), else: node
  end

  defp binary_operator_to_rust(op) do
    case op do
      :+ -> "+"
      :- -> "-"
      :* -> "*"
      :/ -> "/"
      :% -> "%"
      :== -> "=="
      :!= -> "!="
      :> -> ">"
      :>= -> ">="
      :< -> "<"
      :<= -> "<="
      :and -> "&&"
      :or -> "||"
      :& -> "&"
      :| -> "|"
      :^ -> "^"
      :lshift -> "<<"
      :rshift -> ">>"
      :.. -> ".."
      :range_inclusive -> "..="
      _ -> "+"
    end
  end

  defp unary_operator_to_rust(op) do
    case op do
      :not -> "!"
      :- -> "-"
      :deref -> "*"
      :ref -> "&"
      _ -> "-"
    end
  end
end
