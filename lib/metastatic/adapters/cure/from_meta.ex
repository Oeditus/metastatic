defmodule Metastatic.Adapters.Cure.FromMeta do
  @moduledoc """
  Transform MetaAST (M2) back to Cure source code.

  This is the reification function for the Cure adapter, producing
  human-readable Cure source from MetaAST nodes.
  """

  @doc "Convert a MetaAST node to Cure source string."
  @spec to_source(Metastatic.AST.meta_ast()) :: String.t()
  def to_source(ast), do: emit(ast, 0)

  defp emit({:literal, meta, value}, indent) do
    case meta[:subtype] do
      :integer ->
        to_string(value)

      :float ->
        to_string(value)

      :string ->
        ~s("#{value}")

      :boolean ->
        to_string(value)

      :null ->
        "nil"

      :symbol ->
        ":#{value}"

      :char ->
        "'#{<<value::utf8>>}'"

      :regex ->
        {body, flags} = value
        "~r/#{body}/#{flags}"

      :bytes ->
        emit_bytes_literal(value, indent)

      _ ->
        inspect(value)
    end
  end

  defp emit({:variable, _meta, name}, _indent), do: name

  defp emit({:binary_op, meta, [left, right]}, indent) do
    op = meta[:operator]
    "#{emit(left, indent)} #{op} #{emit(right, indent)}"
  end

  defp emit({:unary_op, meta, [operand]}, indent) do
    op = meta[:operator]
    "#{op}#{emit(operand, indent)}"
  end

  defp emit({:function_call, meta, args}, indent) do
    name = meta[:name]
    arg_strs = Enum.map_join(args, ", ", &emit(&1, indent))
    "#{name}(#{arg_strs})"
  end

  defp emit({:assignment, _meta, [pattern, value]}, indent) do
    "let #{emit(pattern, indent)} = #{emit(value, indent)}"
  end

  defp emit({:conditional, _meta, [cond_ast, then_ast, else_ast]}, indent) do
    "if #{emit(cond_ast, indent)} then #{emit(then_ast, indent)} else #{emit(else_ast, indent)}"
  end

  defp emit({:block, _meta, exprs}, indent) do
    Enum.map_join(exprs, "\n#{pad(indent)}", &emit(&1, indent))
  end

  defp emit({:list, meta, elems}, indent) do
    if meta[:cons] do
      [h, t] = elems
      "[#{emit(h, indent)} | #{emit(t, indent)}]"
    else
      inner = Enum.map_join(elems, ", ", &emit(&1, indent))
      "[#{inner}]"
    end
  end

  defp emit({:tuple, _meta, elems}, indent) do
    inner = Enum.map_join(elems, ", ", &emit(&1, indent))
    "%[#{inner}]"
  end

  defp emit({:map, _meta, pairs}, indent) do
    inner = Enum.map_join(pairs, ", ", &emit(&1, indent))
    "%{#{inner}}"
  end

  defp emit({:pair, _meta, [key, value]}, indent) do
    "#{emit(key, indent)} => #{emit(value, indent)}"
  end

  defp emit({:lambda, meta, [body]}, indent) do
    params = meta[:params] || []
    param_names = Enum.map_join(params, ", ", fn {:param, _, n} -> n end)
    "fn(#{param_names}) -> #{emit(body, indent)}"
  end

  defp emit({:function_def, meta, body}, indent) do
    name = meta[:name]
    params = meta[:params] || []

    param_strs =
      Enum.map_join(params, ", ", fn
        {:param, pm, n} ->
          if pm[:type], do: "#{n}: #{emit(pm[:type], indent)}", else: n
      end)

    ret = if meta[:return_type], do: " -> #{emit(meta[:return_type], indent)}", else: ""
    vis = if meta[:visibility] == :private, do: "local ", else: ""

    case body do
      [single] -> "#{vis}fn #{name}(#{param_strs})#{ret} = #{emit(single, indent)}"
      [] -> "#{vis}fn #{name}(#{param_strs})#{ret}"
      _ -> "#{vis}fn #{name}(#{param_strs})#{ret} = ..."
    end
  end

  defp emit({:container, meta, body}, indent) do
    case meta[:container_type] do
      :module ->
        body_str = Enum.map_join(body, "\n#{pad(indent + 2)}", &emit(&1, indent + 2))
        "mod #{meta[:name]}\n#{pad(indent + 2)}#{body_str}"

      :proof ->
        body_str = Enum.map_join(body, "\n#{pad(indent + 2)}", &emit(&1, indent + 2))
        "proof #{meta[:name]}\n#{pad(indent + 2)}#{body_str}"

      :fsm ->
        emit_fsm(meta, body, indent)

      :struct ->
        fields = Enum.map_join(body, "\n#{pad(indent + 2)}", &emit_field(&1, indent + 2))
        "rec #{meta[:name]}\n#{pad(indent + 2)}#{fields}"

      :enum ->
        variants = Enum.map_join(body, " | ", &emit_variant/1)

        type_params =
          if meta[:type_params], do: "(#{Enum.join(meta[:type_params], ", ")})", else: ""

        "type #{meta[:name]}#{type_params} = #{variants}"

      :protocol ->
        body_str = Enum.map_join(body, "\n#{pad(indent + 2)}", &emit(&1, indent + 2))
        tp = if meta[:type_params], do: "(#{Enum.join(meta[:type_params], ", ")})", else: ""
        "proto #{meta[:name]}#{tp}\n#{pad(indent + 2)}#{body_str}"

      _ ->
        inspect(meta)
    end
  end

  defp emit({:import, meta, _}, _indent) do
    source = meta[:source]
    items = meta[:items]
    alias_name = meta[:alias]

    cond do
      items && items != [] -> "use #{source}.{#{Enum.join(items, ", ")}}"
      alias_name -> "use #{source} as #{alias_name}"
      true -> "use #{source}"
    end
  end

  defp emit({:string_interpolation, _meta, parts}, indent) do
    inner =
      Enum.map_join(parts, "", fn
        {:literal, [{:subtype, :string} | _], s} -> s
        other -> "\#{#{emit(other, indent)}}"
      end)

    ~s("#{inner}")
  end

  defp emit({:early_return, _meta, [expr]}, indent), do: "return #{emit(expr, indent)}"
  defp emit({:throw, _meta, [expr]}, indent), do: "throw #{emit(expr, indent)}"
  defp emit({:yield, _meta, [expr]}, indent), do: "yield #{emit(expr, indent)}"

  # Pin operator (Cure v0.18.0+): ^inner
  defp emit({:pin, _meta, [inner]}, indent), do: "^#{emit(inner, indent)}"

  # Compile-time type assertion (Cure v0.19.0+): assert_type expr : T
  defp emit({:assert_type, _meta, [expr, type_ast]}, indent) do
    "assert_type #{emit(expr, indent)} : #{emit(type_ast, indent)}"
  end

  # Functional record update (Cure v0.15.0+): Name{base | field: val, ...}
  defp emit({:record_update, meta, [base | fields]}, indent) do
    name = meta[:name]
    base_str = emit(base, indent)
    fields_str = Enum.map_join(fields, ", ", &emit(&1, indent))
    "#{name}{#{base_str} | #{fields_str}}"
  end

  defp emit({:range, meta, [l, r]}, indent) do
    op = if meta[:inclusive], do: "..=", else: ".."
    "#{emit(l, indent)}#{op}#{emit(r, indent)}"
  end

  # Bitstring segment (Cure v0.20.0+). Rendered as `value` or
  # `value::spec1-spec2-...` depending on which meta keys are present.
  defp emit({:bin_segment, meta, [value]}, indent) do
    emit_bin_segment(value, meta, indent)
  end

  # Trivia comment (Cure v0.20.0+). Rendered as a `# text` or `## text`
  # line depending on `:comment_kind`. Callers (block, container) are
  # responsible for placing the result at the correct column; this helper
  # returns only the leading marker and the payload text.
  defp emit({:comment, meta, text}, _indent) when is_binary(text) do
    case meta[:comment_kind] do
      :doc -> "## #{text}"
      :block -> "/* #{text} */"
      _ -> "# #{text}"
    end
  end

  defp emit({:attribute_access, meta, [obj]}, indent) do
    "#{emit(obj, indent)}.#{meta[:attribute]}"
  end

  defp emit({:property, meta, _}, _indent), do: "@#{meta[:name]}"

  defp emit({:decorator, meta, args}, indent) do
    arg_strs = Enum.map_join(args, ", ", &emit(&1, indent))
    "@#{meta[:name]}(#{arg_strs})"
  end

  defp emit(other, _indent), do: inspect(other)

  defp emit_field({:param, meta, name}, indent) do
    type = if meta[:type], do: ": #{emit(meta[:type], indent)}", else: ""
    "#{name}#{type}"
  end

  defp emit_variant({:function_def, meta, _}) do
    params = meta[:params] || []

    if params == [] do
      meta[:name]
    else
      param_strs = Enum.map_join(params, ", ", &emit(&1, 0))
      "#{meta[:name]}(#{param_strs})"
    end
  end

  defp emit_variant({:variable, _, name}), do: name

  # FSM container rendering (Cure v0.7.0+).
  # Emits `fsm Name [with Payload]` followed by indented transition lines
  # and any annotation/callback metadata carried on the container.
  @fsm_callback_keys [:on_transition, :on_enter, :on_exit, :on_failure, :on_timer]
  defp emit_fsm(meta, body, indent) do
    name = meta[:name]
    payload = meta[:payload]
    timer = meta[:timer]
    pad_inner = pad(indent + 2)

    payload_str =
      case payload do
        nil -> ""
        ast -> " with #{emit(ast, indent)}"
      end

    transitions_str = Enum.map_join(body, "\n#{pad_inner}", &emit(&1, indent + 2))

    timer_str = if timer, do: "\n#{pad_inner}@timer #{timer}", else: ""

    callbacks_str =
      Enum.map_join(@fsm_callback_keys, "", fn cb ->
        case meta[cb] do
          clauses when is_list(clauses) and clauses != [] ->
            inner = Enum.map_join(clauses, "\n#{pad(indent + 4)}", &emit(&1, indent + 4))
            "\n#{pad_inner}#{cb}\n#{pad(indent + 4)}#{inner}"

          _ ->
            ""
        end
      end)

    "fsm #{name}#{payload_str}\n#{pad_inner}#{transitions_str}#{timer_str}#{callbacks_str}"
  end

  defp pad(n), do: String.duplicate(" ", n)

  # Render a `{:literal, [subtype: :bytes], _}` payload.
  # Accepts both legacy binary form (`<<1, 2, 3>>`) and the Cure v0.20.0
  # segment-list form (`<<x::utf8, rest::binary>>`).
  defp emit_bytes_literal(value, _indent) when is_binary(value) do
    inner =
      value
      |> :binary.bin_to_list()
      |> Enum.map_join(", ", &Integer.to_string/1)

    "<<#{inner}>>"
  end

  defp emit_bytes_literal(segments, indent) when is_list(segments) do
    inner = Enum.map_join(segments, ", ", &emit(&1, indent))
    "<<#{inner}>>"
  end

  defp emit_bytes_literal(other, _indent), do: inspect(other)

  # Render a single bin_segment specifier chain.
  defp emit_bin_segment(value, meta, indent) do
    specifiers =
      [
        meta[:type],
        meta[:signedness],
        meta[:endianness]
      ]
      |> Enum.filter(& &1)
      |> Enum.map(&Atom.to_string/1)

    specifiers =
      case meta[:size] do
        nil -> specifiers
        size_ast -> specifiers ++ ["size(#{emit(size_ast, indent)})"]
      end

    specifiers =
      case meta[:unit] do
        nil -> specifiers
        unit when is_integer(unit) -> specifiers ++ ["unit(#{unit})"]
      end

    case specifiers do
      [] -> emit(value, indent)
      chain -> "#{emit(value, indent)}::#{Enum.join(chain, "-")}"
    end
  end
end
