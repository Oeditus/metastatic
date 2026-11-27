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

  defp emit({:variable, _meta, name}, _indent), do: to_string(name)

  defp emit({:binary_op, meta, [left, right]}, indent) do
    op = meta[:operator]
    "#{emit(left, indent)} #{op} #{emit(right, indent)}"
  end

  defp emit({:unary_op, meta, [operand]}, indent) do
    op = meta[:operator]
    "#{op}#{emit(operand, indent)}"
  end

  # A record construction (`Point{x: 0, y: 1}`) is a `:function_call` with
  # `record: true` whose arguments are `:pair` nodes carrying a `:field`.
  defp emit({:function_call, meta, args}, indent) do
    name = meta[:name]

    if meta[:record] do
      fields = Enum.map_join(args, ", ", &emit_record_field(&1, indent))
      "#{name}{#{fields}}"
    else
      arg_strs = Enum.map_join(args, ", ", &emit(&1, indent))
      "#{name}(#{arg_strs})"
    end
  end

  # `let` binding. Cure v0.19.0+ also spells `have name : Prop = expr`
  # inside proof blocks; the `:have` flag selects that surface form.
  defp emit({:assignment, meta, [pattern, value]}, indent) do
    keyword = if meta[:have], do: "have", else: "let"
    type = if meta[:type_annotation], do: " : #{emit(meta[:type_annotation], indent)}", else: ""
    "#{keyword} #{emit(pattern, indent)}#{type} = #{emit(value, indent)}"
  end

  # Cure has no `if`/`then`/`else`: `pickup` (v0.35.0+) replaced it. A
  # `:conditional` therefore only survives from hand-built MetaAST; render
  # it as the equivalent two-clause `pickup`.
  defp emit({:conditional, _meta, [cond_ast, then_ast, else_ast]}, indent) do
    inner = pad(indent + 2)

    [
      "pickup",
      "#{inner}#{emit(cond_ast, indent + 2)} -> #{emit(then_ast, indent + 2)}",
      "#{inner}else -> #{emit(else_ast, indent + 2)}"
    ]
    |> Enum.join("\n")
  end

  # A sequence of statements, one per line at `indent`. The first statement
  # is emitted inline (the caller has already placed the cursor); every
  # subsequent one is prefixed with the indent.
  #
  # Cure's parser emits a `mod Name` container as an *empty* node whose
  # declarations follow as flat siblings in the enclosing block. Reify that
  # layout by regrouping each container with the declarations that trail it.
  defp emit({:block, meta, exprs}, indent) do
    separator = if meta[:do], do: "\n#{pad(indent + 2)}", else: "\n#{pad(indent)}"

    case group_container_bodies(exprs) do
      [] -> ""
      grouped -> Enum.map_join(grouped, separator, &emit(&1, indent))
    end
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
    param_names = Enum.map_join(params, ", ", fn {:param, _, n} -> to_string(n) end)
    "fn(#{param_names}) -> #{emit(body, indent)}"
  end

  defp emit({:function_def, meta, body}, indent) do
    name = meta[:name]
    params = meta[:params] || []

    param_strs =
      Enum.map_join(params, ", ", fn
        {:param, pm, n} ->
          if pm[:type], do: "#{to_string(n)}: #{emit(pm[:type], indent)}", else: to_string(n)
      end)

    ret = if meta[:return_type], do: " -> #{emit(meta[:return_type], indent)}", else: ""
    vis = if meta[:visibility] == :private, do: "local ", else: ""

    # A `variant: true` function_def is an ADT constructor, not a function.
    if meta[:variant] do
      emit_variant({:function_def, meta, body})
    else
      emit_function_def(meta, body, indent, vis, name, param_strs, ret)
    end
  end

  defp emit({:container, meta, body}, indent) do
    case meta[:container_type] do
      :module ->
        emit_named_container("mod", meta, body, indent)

      :proof ->
        emit_named_container("proof", meta, body, indent)

      :fsm ->
        emit_fsm(meta, body, indent)

      :actor ->
        emit_actor(meta, body, indent)

      :supervisor ->
        emit_supervisor(meta, body, indent)

      :app ->
        emit_app(meta, body, indent)

      :struct ->
        tp =
          case meta[:type_params] do
            nil -> ""
            [] -> ""
            params -> "(#{Enum.join(params, ", ")})"
          end

        emit_named_container("rec", meta, body, indent, &emit_field(&1, indent + 2), tp)

      :enum ->
        variants = Enum.map_join(body, " | ", &emit_variant/1)

        type_params =
          if meta[:type_params], do: "(#{Enum.join(meta[:type_params], ", ")})", else: ""

        "type #{meta[:name]}#{type_params} = #{variants}"

      :protocol ->
        tp = if meta[:type_params], do: "(#{Enum.join(meta[:type_params], ", ")})", else: ""
        emit_named_container("proto", meta, body, indent, &emit(&1, indent + 2), tp)

      # Cure v0.36.0 renamed `proto`/`impl` to `interface`/`implementation`.
      # Both spellings remain accepted by the printer so legacy MetaAST
      # still round-trips.
      :interface ->
        emit_interface(meta, body, indent)

      :implementation ->
        emit_implementation(meta, body, indent)

      :primitive ->
        emit_named_container("primitive", meta, body, indent)

      other ->
        emit_named_container(to_string(other || "container"), meta, body, indent)
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

  defp emit({:child_spec, meta, []}, _indent) do
    kind = meta[:kind]
    module = meta[:module] || ""
    id = meta[:id] || ""

    prefix = if kind == :supervisor, do: "sup ", else: ""

    opts_keys = meta |> Keyword.drop([:module, :id, :kind, :line, :col])

    opts_str =
      if opts_keys == [] do
        ""
      else
        inner =
          Enum.map_join(opts_keys, ", ", fn {k, v} ->
            "#{k}: #{emit(v, 0)}"
          end)

        " (#{inner})"
      end

    "#{prefix}#{module} as #{id}#{opts_str}"
  end

  defp emit({:param, meta, name}, indent) do
    type = if meta[:type], do: ": #{emit(meta[:type], indent)}", else: ""
    "#{to_string(name)}#{type}"
  end

  defp emit({:macro_def, meta, rules}, indent) do
    name = meta[:name]
    pad = pad(indent + 2)

    header = "macro #{name}"

    case rules do
      [] ->
        header

      _ ->
        rules_str =
          Enum.map_join(rules, "\n#{pad}", fn
            rule when is_map(rule) ->
              emit_macro_rule(rule, indent + 2)

            ast ->
              emit(ast, indent + 2)
          end)

        "#{header}\n#{pad}#{rules_str}"
    end
  end

  defp emit({:precedencegroup, meta, _}, _indent) do
    name = Keyword.get(meta, :name)
    "precedencegroup #{name}"
  end

  defp emit({:fixity, meta, _}, _indent) do
    fixity = Keyword.get(meta, :fixity, "infix")
    op = Keyword.get(meta, :operator, "")
    group = Keyword.get(meta, :group, "")
    "#{fixity} `#{op}` : #{group}"
  end

  # --- Cure v0.21.0+ pattern & control-flow nodes -------------------------

  # `match scrutinee` followed by one indented arm per line.
  defp emit({:pattern_match, _meta, [scrutinee | arms]}, indent) do
    inner = pad(indent + 2)
    rendered = Enum.map_join(arms, "\n#{inner}", &emit(&1, indent + 2))

    case arms do
      [] -> "match #{emit(scrutinee, indent)}"
      _ -> "match #{emit(scrutinee, indent)}\n#{inner}#{rendered}"
    end
  end

  # `pattern [when guard] -> body`.
  defp emit({:match_arm, meta, body}, indent) do
    pattern = emit(meta[:pattern] || {:wildcard, [], nil}, indent)
    guard = if meta[:guard], do: " when #{emit(meta[:guard], indent)}", else: ""
    rendered_body = emit_body_inline(body, indent)

    case rendered_body do
      "\n" <> _ = multiline ->
        String.trim_trailing("#{pattern}#{guard} ->") <> multiline

      _ ->
        "#{pattern}#{guard} -> #{rendered_body}"
    end
  end

  # `with scrutinee` -- the Idris-style convoy pattern (Cure v0.36.0).
  defp emit({:with_abs, _meta, [scrutinee | arms]}, indent) do
    inner = pad(indent + 2)
    rendered = Enum.map_join(arms, "\n#{inner}", &emit(&1, indent + 2))

    case arms do
      [] -> "with #{emit(scrutinee, indent)}"
      _ -> "with #{emit(scrutinee, indent)}\n#{inner}#{rendered}"
    end
  end

  # `pickup` -- the predicate-dispatch construct that replaced `if`.
  defp emit({:pickup, _meta, clauses}, indent) do
    inner = pad(indent + 2)
    rendered = Enum.map_join(clauses, "\n#{inner}", &emit(&1, indent + 2))

    case clauses do
      [] -> "pickup"
      _ -> "pickup\n#{inner}#{rendered}"
    end
  end

  defp emit({:pickup_clause, _meta, [guard, body]}, indent) do
    "#{emit(guard, indent)} -> #{emit_body_inline([body], indent)}"
  end

  defp emit({:pickup_else, _meta, body}, indent) do
    "else -> #{emit_body_inline(body, indent)}"
  end

  # `try` / `catch` / `finally`. The final child is the finally body when
  # the parser recorded one; catch arms are `:match_arm` nodes.
  defp emit({:exception_handling, meta, [try_body | rest]}, indent) do
    inner = pad(indent + 2)
    has_catch = Enum.any?(rest, &match?({:match_arm, _, _}, &1))
    catch_arms = Enum.filter(rest, &match?({:match_arm, _, _}, &1))
    finally = Enum.find(rest, &(not match?({:match_arm, _, _}, &1)))

    catch_str =
      if has_catch do
        arms = Enum.map_join(catch_arms, "\n#{inner}", &emit(&1, indent + 2))
        "\n#{inner}catch\n#{inner}#{arms}"
      else
        ""
      end

    finally_str =
      if finally do
        "\n#{inner}finally\n#{inner}#{emit(finally, indent + 2)}"
      else
        ""
      end

    _ = meta
    "try\n#{inner}#{emit(try_body, indent + 2)}#{catch_str}#{finally_str}"
  end

  # `[expr for generator, ...]` (list comprehension).
  defp emit({:comprehension, _meta, [expr | qualifiers]}, indent) do
    quals = Enum.map_join(qualifiers, ", ", &emit(&1, indent))
    "[#{emit(expr, indent)} for #{quals}]"
  end

  # `x <- xs` inside a comprehension.
  defp emit({:generator, _meta, [pattern, source]}, indent) do
    "#{emit(pattern, indent)} <- #{emit(source, indent)}"
  end

  # `b <- buf` inside a binary comprehension.
  # `<<pattern <- source>>` inside a binary comprehension. The pattern is a
  # `:bytes` literal whose single `:bin_segment` holds the bound variable;
  # the whole `<- source` clause lives *inside* the `<<...>>`.
  defp emit({:binary_generator, _meta, [pattern, source]}, indent) do
    inner =
      case pattern do
        {:literal, _lm, [segment]} -> emit(segment, indent)
        other -> emit(other, indent)
      end

    "<<#{inner} <- #{emit(source, indent)}>>"
  end

  # A comprehension filter (a bare boolean expression).
  defp emit({:filter, _meta, [expr]}, indent), do: emit(expr, indent)

  # --- Cure v0.17.0+ dependent-type nodes --------------------------------

  # `{x: T | predicate}` -- refinement type.
  defp emit({:refinement_type, meta, [base, predicate]}, indent) do
    binder = meta[:binder] || "_"
    "{#{binder}: #{emit(base, indent)} | #{emit(predicate, indent)}}"
  end

  # `Sigma(x: T, U)` -- dependent pair.
  defp emit({:sigma_type, meta, [first, second]}, indent) do
    binder = meta[:binder]

    inner =
      if binder,
        do: "#{binder}: #{emit(first, indent)}, #{emit(second, indent)}",
        else: "#{emit(first, indent)}, #{emit(second, indent)}"

    "Sigma(#{inner})"
  end

  # `Pi(x: T) -> U` -- dependent function type.
  defp emit({:pi_type, meta, body}, indent) do
    binders = meta[:binders] || []
    {dom, cod} = split_pi(body)

    binder_str =
      case binders do
        [] -> emit(dom, indent)
        [single] -> "#{single}: #{emit(dom, indent)}"
        many -> Enum.map_join(many, ", ", &"#{&1}: #{emit(dom, indent)}")
      end

    "Pi(#{binder_str}) -> #{emit(cod, indent)}"
  end

  # `A -> B -> C` -- right-associative function-type chain.
  defp emit({:arrow_chain, _meta, parts}, indent) do
    Enum.map_join(parts, " -> ", &emit(&1, indent))
  end

  # `Tuple(A, B)` -- fixed-arity tuple type.
  defp emit({:tuple_type, _meta, elements}, indent) do
    "Tuple(#{Enum.map_join(elements, ", ", &emit(&1, indent))})"
  end

  # `A | B` -- union type.
  defp emit({:union_type, _meta, members}, indent) do
    Enum.map_join(members, " | ", &emit(&1, indent))
  end

  # A named domain binder (`xs: List(a)`) inside a Sigma / Pi telescope.
  defp emit({:named_dom, meta, [type]}, indent) do
    "#{meta[:name]}: #{emit(type, indent)}"
  end

  # An implicit domain binder (`{coefficients: List(Int)}`).
  defp emit({:implicit_dom, meta, [type]}, indent) do
    "{#{meta[:name]}: #{emit(type, indent)}}"
  end

  defp emit({:named_implicit_pat, meta, [type]}, indent) do
    "{#{meta[:name]}: #{emit(type, indent)}}"
  end

  # `y: T` -- a type-ascribed pattern.
  defp emit({:typed_pattern, _meta, [name, type]}, indent) do
    "#{name}: #{emit(type, indent)}"
  end

  # `interface Name(params) requires A, B` -- a top-level node in Cure
  # v0.36.0 (formerly the `proto` container).
  defp emit({:interface, meta, body}, indent) do
    emit_interface(meta, body, indent)
  end

  # `implementation Interface for Type [as Alias]` -- a top-level node in
  # Cure v0.36.0 (formerly the `impl` container).
  defp emit({:implementation, meta, body}, indent) do
    emit_implementation(meta, body, indent)
  end

  # `@decorator` applied to an indexed type declaration.
  defp emit({:indexed_type, meta, body}, indent) do
    name = meta[:name]
    params = meta[:params] || []

    params_str =
      case params do
        [] -> ""
        _ -> "(#{Enum.map_join(params, ", ", &emit_type_param(&1, indent))})"
      end

    indices_str =
      case Keyword.fetch(meta, :indices) do
        {:ok, []} ->
          " indices ()"

        {:ok, indices} ->
          " indices (#{Enum.map_join(indices, ", ", &emit_type_param(&1, indent))})"

        :error ->
          ""
      end

    header = "type #{name}#{params_str}#{indices_str}"

    decorator_str =
      case meta[:decorator] do
        nil -> ""
        dec -> emit(dec, indent) <> "\n"
      end

    case body do
      [] ->
        decorator_str <> header

      _ ->
        inner = pad(indent + 2)
        rendered = Enum.map_join(body, "\n#{inner}", &emit(&1, indent + 2))
        decorator_str <> header <> "\n" <> inner <> rendered
    end
  end

  # `Ctor : ResultType` -- a GADT constructor. Its body is an `:arrow_chain`
  # whose leading `:named_dom` / `:implicit_dom` entries are the constructor
  # parameters and whose final entry is the result type:
  #
  #     mk_pool : capacity: Int -> Pool(avail, in_use)
  #     bs : Below(n) -> Below(S(n))
  #
  # A chain with no named binders is a plain function type and keeps its
  # arrows.
  defp emit({:gadt_ctor, meta, body}, indent) do
    name = meta[:name]

    case body do
      [{:arrow_chain, _am, parts}] ->
        {params, [result]} =
          case Enum.split(parts, -1) do
            {ps, [r]} -> {ps, [r]}
            {ps, []} -> {ps, [{:variable, [], "Type"}]}
          end

        if params != [] and Enum.all?(params, &dom_binder?/1) do
          "#{name} : (#{Enum.map_join(params, ", ", &emit(&1, indent))}) -> #{emit(result, indent)}"
        else
          "#{name} : #{Enum.map_join(parts, " -> ", &emit(&1, indent))}"
        end

      _ ->
        args = Enum.map_join(body, " ", &emit(&1, indent))

        case args do
          "" -> name
          _ -> "#{name} : #{args}"
        end
    end
  end

  # `typealias Name = T`.
  defp emit({:type_annotation, meta, body}, _indent) do
    keyword = if meta[:typealias], do: "typealias", else: "type"
    variants = Enum.map_join(body, " | ", &emit_variant/1)
    "#{keyword} #{meta[:name]} = #{variants}"
  end

  # --- Cure v0.36.0 proof / tactic kernel --------------------------------

  # `proof chain` -- a sequence of equational steps.
  # `proof chain` -- a sequence of equational steps. The first child is the
  # starting left-hand side; each `:proof_step` compares the previous
  # expression to a new right-hand side and carries a justification.
  defp emit({:proof_chain, _meta, [first | steps]}, indent) do
    inner = pad(indent + 2)

    rendered =
      Enum.map_join(steps, "\n#{inner}", fn
        {:proof_step, _meta, [_prev, rhs, justification]} ->
          "#{emit(first, indent + 2)} == #{emit(rhs, indent + 2)}\n#{inner}because #{emit(justification, indent + 2)}"

        step ->
          emit(step, indent + 2)
      end)

    case steps do
      [] -> "proof chain\n#{inner}#{emit(first, indent + 2)}"
      _ -> "proof chain\n#{inner}#{rendered}"
    end
  end

  defp emit({:proof_chain, _meta, []}, _indent), do: "proof chain"

  # `lhs == rhs` followed by `because <justification>`.
  defp emit({:proof_step, _meta, [lhs, rhs, justification]}, indent) do
    "#{emit(lhs, indent)} == #{emit(rhs, indent)}\n#{pad(indent)}because #{emit(justification, indent)}"
  end

  # The implicit "previous step" reference that begins a proof chain.
  defp emit({:proof_chain_previous, _meta, _}, _indent), do: "_"

  # A justification block: `rewrite using h`, `simplify`, `apply ...`.
  defp emit({:proof_justification, _meta, commands}, indent) do
    inner = pad(indent + 2)
    rendered = Enum.map_join(commands, "\n#{inner}", &emit(&1, indent + 2))
    "\n#{inner}#{rendered}"
  end

  # `rewrite using h` / `rewrite backwards using h`.
  defp emit({:rewrite_command, meta, args}, indent) do
    direction = if meta[:direction] == :backward, do: "backwards ", else: ""
    target = if meta[:target] && meta[:target] != :goal, do: " in #{meta[:target]}", else: ""
    "rewrite #{direction}using #{Enum.map_join(args, ", ", &emit(&1, indent))}#{target}"
  end

  # `rewrite h into e` -- the expression-level eliminator.
  defp emit({:rewrite_expr, _meta, [hypothesis, target]}, indent) do
    "rewrite #{emit(hypothesis, indent)} into #{emit(target, indent)}"
  end

  defp emit({:simplify_command, _meta, args}, indent) do
    case args do
      [] -> "simplify"
      _ -> "simplify using #{Enum.map_join(args, ", ", &emit(&1, indent))}"
    end
  end

  defp emit({:solver_command, meta, args}, indent) do
    solver = meta[:solver] || :decide

    case args do
      [] -> "by #{solver}"
      _ -> "by #{solver} using #{Enum.map_join(args, ", ", &emit(&1, indent))}"
    end
  end

  # `apply h` / `exact h` -- a tactic application.
  defp emit({:proof_application, meta, args}, indent) do
    kind = meta[:kind] || :apply
    "#{kind} #{Enum.map_join(args, ", ", &emit(&1, indent))}"
  end

  # `induction x` followed by `case Ctor => ...` branches.
  defp emit({:induction, _meta, [scrutinee | cases]}, indent) do
    inner = pad(indent + 2)
    rendered = Enum.map_join(cases, "\n#{inner}", &emit(&1, indent + 2))

    case cases do
      [] -> "induction #{emit(scrutinee, indent)}"
      _ -> "induction #{emit(scrutinee, indent)}\n#{inner}#{rendered}"
    end
  end

  defp emit({:induction_case, meta, [name | body]}, indent) do
    impossible = if meta[:impossible], do: " (impossible)", else: ""
    inner = pad(indent + 2)
    rendered = Enum.map_join(body, "\n#{inner}", &emit(&1, indent + 2))
    "case #{emit(name, indent)}#{impossible} =>\n#{inner}#{rendered}"
  end

  # --- Cure v0.36.0 macro / quotation nodes ------------------------------

  # `quote <expr>` -- syntax construction.
  defp emit({:quoted_syntax, _meta, [expr]}, indent) do
    "quote #{emit(expr, indent)}"
  end

  # `$(e)` -- a single-position splice inside a quotation.
  defp emit({:splice, _meta, [expr]}, indent) do
    "$(#{emit(expr, indent)})"
  end

  # `$(e ...)` -- the list-flattening splice.
  defp emit({:splice_group, _meta, [expr]}, indent) do
    "$(#{emit(expr, indent)} ...)"
  end

  # A macro invocation's captured input (`actor Name ...`, `fsm Name ...`).
  #
  # `:macro_input` children are positional: scalars and family options form
  # the header line, while a repeated family group (a bare list) contributes
  # one indented line per element.
  defp emit({:macro_input, meta, args}, indent) do
    keyword = meta[:keyword] || ""
    {inline, repeated} = split_repeated(args)

    header =
      inline
      |> Enum.map(&emit(&1, indent))
      |> Enum.reject(&(&1 == ""))
      |> Enum.join(" ")

    head =
      case {keyword, header} do
        {"", ""} -> ""
        {"", _} -> header
        {_, ""} -> keyword
        _ -> "#{keyword} #{header}"
      end

    case repeated do
      [] ->
        head

      elements ->
        inner = pad(indent + 2)
        rendered = Enum.map_join(elements, "\n#{inner}", &emit(&1, indent + 2))
        "#{head}\n#{inner}#{rendered}"
    end
  end

  # A computed macro invocation (`fsm`, `sup`, `app`, `actor`, ...). The
  # node carries the expander function followed by the captured
  # `:macro_input`; only the latter is surface syntax.
  defp emit({:computed_use, meta, children}, indent) do
    case Enum.find(children, &match?({:macro_input, _, _}, &1)) do
      nil ->
        keyword = meta[:keyword] || "computed"
        keyword

      macro_input ->
        emit_macro_input(macro_input, meta, indent)
    end
  end

  # A syntax-family input: positional children, with absent options elided.
  # A nested bare list is a repeated family group; each element is rendered
  # on its own indented line.
  defp emit({:family_input, _meta, children}, indent) do
    {inline, repeated} = split_repeated(children)

    header =
      inline
      |> Enum.map(&emit(&1, indent))
      |> Enum.reject(&(&1 == ""))
      |> Enum.join(" ")

    case repeated do
      [] ->
        header

      elements ->
        inner = pad(indent + 2)
        rendered = Enum.map_join(elements, "\n#{inner}", &emit(&1, indent + 2))

        case header do
          "" -> rendered
          _ -> "#{header}\n#{inner}#{rendered}"
        end
    end
  end

  # `present: false` options contribute nothing to the surface form.
  defp emit({:family_option, meta, []}, _indent) do
    _ = meta
    ""
  end

  defp emit({:family_option, _meta, [value]}, indent), do: emit(value, indent)

  # --- Cure v0.36.0 misc nodes -------------------------------------------

  # `?goal` -- an unfilled hole.
  defp emit({:hole, meta, _}, _indent), do: "?#{meta[:name] || "_"}"

  # `declarations` -- an explicit declaration section inside a module.
  defp emit({:declarations_block, _meta, body}, indent) do
    inner = pad(indent + 2)
    rendered = Enum.map_join(body, "\n#{inner}", &emit(&1, indent + 2))

    case body do
      [] -> "declarations"
      _ -> "declarations\n#{inner}#{rendered}"
    end
  end

  # `send pid, msg` / `receive`.
  defp emit({:send, _meta, [pid, message]}, indent) do
    "send #{emit(pid, indent)}, #{emit(message, indent)}"
  end

  defp emit({:async_operation, _meta, children}, indent) do
    inner = pad(indent + 2)
    rendered = Enum.map_join(children, "\n#{inner}", &emit(&1, indent + 2))

    case children do
      [] -> "spawn"
      [{:match_arm, _, _} | _] -> "receive\n#{inner}#{rendered}"
      _ -> "spawn #{rendered}"
    end
  end

  # `unsafe { ... }` -- an unchecked escape hatch.
  defp emit({:unsafe_expression, _meta, [expr]}, indent) do
    "unsafe { #{emit(expr, indent)} }"
  end

  # A `:language_specific` node carries the original Cure node kind in
  # `:cure_kind`; render its children generically.
  defp emit({:language_specific, meta, children}, indent) do
    kind = meta[:cure_kind] || meta[:hint] || "node"

    case children do
      list when is_list(list) ->
        rendered = Enum.map_join(list, " ", &emit(&1, indent))
        "#{kind} #{rendered}"

      other ->
        to_string(other)
    end
  end

  defp emit({:wildcard, _meta, _}, _indent), do: "_"

  # `()` -- the unit value. Its third element is a keyword list, not a
  # child list, so it needs its own clause.
  defp emit({:unit_value, _meta, _}, _indent), do: "()"
  defp emit({:unit_value, _meta}, _indent), do: "()"

  # `case scrutinee` followed by indented arms (legacy spelling of `match`).
  defp emit({:case_block, _meta, [scrutinee | arms]}, indent) do
    inner = pad(indent + 2)
    rendered = Enum.map_join(arms, "\n#{inner}", &emit(&1, indent + 2))

    case arms do
      [] -> "case #{emit(scrutinee, indent)}"
      _ -> "case #{emit(scrutinee, indent)}\n#{inner}#{rendered}"
    end
  end

  # A bare list inside a `:family_input` is a positional group of child
  # nodes (a repeated family field). Render its members space-separated.
  defp emit(list, indent) when is_list(list) do
    list
    |> Enum.map(&emit(&1, indent))
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ")
  end

  defp emit(nil, _indent), do: ""

  defp emit(other, _indent), do: inspect(other)

  # --- Helpers -----------------------------------------------------------

  # A `when`/`update` continuation clause. The parser records the clause
  # body but not its keyword, so a tuple/map payload is labelled `update`
  # and a boolean expression `when`.
  defp emit_clause(nil, _indent), do: ""
  defp emit_clause({:tuple, _, _} = value, indent), do: "update #{emit(value, indent)}"
  defp emit_clause({:map, _, _} = value, indent), do: "update #{emit(value, indent)}"

  defp emit_clause({:record_update, _meta, _children} = value, indent),
    do: "update #{emit(value, indent)}"

  defp emit_clause(value, indent), do: "when #{emit(value, indent)}"

  defp emit_element_value({:payload, group}, indent) do
    Enum.map_join(group, ", ", &emit_payload(&1, indent))
  end

  defp emit_element_value({:payload_group, group}, indent) do
    Enum.map_join(group, ", ", &emit_payload(&1, indent))
  end

  defp emit_element_value(other, indent), do: emit(other, indent)
  defp field_label(nil), do: ""
  defp field_label(name), do: "#{name} "

  # The ordered field names of a family, from its distilled grammar.
  defp family_field_names(grammar, family) when is_map(grammar) do
    case Map.get(grammar, family) do
      %{fields: fields} ->
        fields

      _ ->
        grammar
        |> Map.values()
        |> Enum.flat_map(fn
          fields when is_map(fields) ->
            fields |> Map.values() |> Enum.flat_map(&field_names_of/1)

          _ ->
            []
        end)
    end
  end

  defp family_field_names(_grammar, _family), do: []

  # A distilled family field is `%{productions: [...], fields: [...]}`.
  defp field_names_of(%{fields: fields}) when is_list(fields), do: fields
  # A distilled family field is `%{productions: [...], fields: [...]}`.
  defp field_names_of(%{fields: fields}) when is_list(fields), do: fields
  defp field_names_of(_), do: []

  # The declared cardinality (`:required` / `:optional` / `:repeated` /
  # `:one_or_more`) of the field at `index` in the element's grammar.
  defp family_field_cardinality(grammar, family, index) when is_map(grammar) do
    grammar
    |> element_field_records(family)
    |> Enum.at(index)
    |> case do
      %{cardinality: cardinality} -> cardinality
      _ -> nil
    end
  end

  defp family_field_cardinality(_grammar, _family, _index), do: nil

  defp element_field_records(grammar, family) do
    case Map.get(grammar, family) do
      %{fields: fields} when is_list(fields) ->
        fields

      _ ->
        grammar
        |> Map.values()
        |> Enum.flat_map(fn
          fields when is_map(fields) ->
            fields |> Map.values() |> Enum.flat_map(&field_records_of/1)

          _ ->
            []
        end)
    end
  end

  defp field_records_of(%{fields: fields}) when is_list(fields), do: fields
  defp field_records_of(_), do: []
  # repeated family group (a bare list of nodes).
  defp split_repeated(args) do
    Enum.reduce(args, {[], []}, fn
      list, {inline, repeated} when is_list(list) ->
        {inline, repeated ++ list}

      arg, {inline, repeated} ->
        {inline ++ [arg], repeated}
    end)
  end

  defp dom_binder?({:named_dom, _, _}), do: true
  defp dom_binder?({:implicit_dom, _, _}), do: true
  defp dom_binder?(_), do: false

  # A record field inside `Name{field: value}`. The field name is either in
  # the `:pair` metadata (`:field`) or carried as the pair's key literal.
  defp emit_record_field({:pair, meta, [key, value]}, indent) do
    field = meta[:field] || field_name(key)
    "#{field}: #{emit(value, indent)}"
  end

  defp emit_record_field(other, indent), do: emit(other, indent)

  defp field_name({:literal, _meta, name}) when is_atom(name),
    do: name |> Atom.to_string() |> String.trim_leading(":")

  defp field_name({:literal, _meta, name}) when is_binary(name), do: name
  defp field_name({:variable, _meta, name}), do: to_string(name)
  defp field_name(nil), do: "_"
  defp field_name(other), do: inspect(other)

  # `head Name` followed by an indented body. When the body is empty the
  # header stands alone -- emitting a trailing blank indented line would
  # produce source the Cure parser rejects.
  defp emit_named_container(keyword, meta, body, indent, renderer \\ nil, suffix \\ "") do
    name = meta[:name]
    renderer = renderer || (&emit(&1, indent + 2))

    case body do
      [] ->
        "#{keyword} #{name}#{suffix}"

      _ ->
        inner = Enum.map_join(body, "\n#{pad(indent + 2)}", renderer)
        "#{keyword} #{name}#{suffix}\n#{pad(indent + 2)}#{inner}"
    end
  end

  # `interface Name(params) requires A, B` with the callback signatures.
  defp emit_interface(meta, body, indent) do
    name = meta[:name]
    params = meta[:params] || []

    params_str =
      case params do
        [] -> ""
        _ -> "(#{Enum.map_join(params, ", ", &emit_type_param(&1, indent))})"
      end

    requires_str =
      case meta[:requires] || [] do
        [] -> ""
        reqs -> " requires #{Enum.map_join(reqs, ", ", &emit_type_param(&1, indent))}"
      end

    header = "interface #{name}#{params_str}#{requires_str}"

    case body do
      [] ->
        header

      _ ->
        inner = pad(indent + 2)
        header <> "\n" <> inner <> Enum.map_join(body, "\n#{inner}", &emit(&1, indent + 2))
    end
  end

  # `implementation Interface for Type [as Alias]` (Cure v0.36.0).
  defp emit_implementation(meta, body, indent) do
    interface = meta[:interface]
    for_type = meta[:for_type] || meta[:for]
    as_str = if meta[:as], do: " as #{meta[:as]}", else: ""

    header = "implementation #{interface} for #{emit(for_type, indent)}#{as_str}"

    case body do
      [] ->
        header

      _ ->
        inner = pad(indent + 2)
        header <> "\n" <> inner <> Enum.map_join(body, "\n#{inner}", &emit(&1, indent + 2))
    end
  end

  # Cure's parser emits a `mod Name` (and `proof Name`) container as an
  # empty node whose declarations follow as flat siblings. Regroup them so
  # the printer can nest the declarations under their container again.
  #
  # A container with a non-empty body is already grouped and is left alone.
  defp group_container_bodies(exprs) do
    exprs
    |> Enum.map(fn
      {:container, meta, []} = container ->
        if container_body_container?(meta), do: {:container, meta, :open}, else: container

      other ->
        other
    end)
    |> attach_to_open_container([])
  end

  defp container_body_container?(meta) do
    Keyword.get(meta, :container_type) in [:module, :proof]
  end

  defp attach_to_open_container([], acc), do: Enum.reverse(acc)

  defp attach_to_open_container([{:container, meta, :open} | rest], acc) do
    {body, remaining} = collect_until_container(rest, [])
    attach_to_open_container(remaining, [{:container, meta, body} | acc])
  end

  defp attach_to_open_container([node | rest], acc) do
    attach_to_open_container(rest, [node | acc])
  end

  defp collect_until_container([{:container, meta, []} = node | rest], acc) do
    if container_body_container?(meta) do
      {Enum.reverse(acc), [node | rest]}
    else
      collect_until_container(rest, [node | acc])
    end
  end

  defp collect_until_container([node | rest], acc) do
    collect_until_container(rest, [node | acc])
  end

  defp collect_until_container([], acc), do: {Enum.reverse(acc), []}

  # --- Family-grammar-driven macro input rendering -----------------------

  # Render a `:macro_input` using the family grammar distilled by
  # `Metastatic.Adapters.Cure.ToMeta`. The grammar supplies the literal
  # separators (`--`, `-->`, `as`, ...) that the AST itself does not keep.
  defp emit_macro_input({:macro_input, meta, args}, computed_meta, indent) do
    keyword = meta[:keyword] || ""
    grammar = computed_meta[:family_grammar] || %{}
    header_segments = computed_meta[:header_segments]
    {inline, repeated} = split_repeated(args)

    head =
      case header_segments do
        segments when is_list(segments) and segments != [] ->
          render_header(segments, inline, grammar, keyword, indent)

        _ ->
          render_macro_header(keyword, inline, grammar, indent)
      end

    case repeated do
      [] ->
        head

      elements ->
        inner = pad(indent + 2)

        rendered =
          Enum.map_join(elements, "\n#{inner}", fn element ->
            emit_family_element(element, grammar, indent + 2)
          end)

        "#{head}\n#{inner}#{rendered}"
    end
  end

  defp render_macro_header(keyword, inline, grammar, indent) do
    header =
      inline
      |> Enum.map(&emit_macro_arg(&1, grammar, indent))
      |> Enum.reject(&(&1 == ""))
      |> Enum.join(" ")

    case {keyword, header} do
      {"", ""} -> ""
      {"", _} -> header
      {_, ""} -> keyword
      _ -> "#{keyword} #{header}"
    end
  end

  # Re-emit the header from the recorded `:header_segments`, substituting
  # the positional argument values into the `{:hole, _}` slots in order.
  # This restores keywords such as `with` that the argument AST omits.
  # Segments are joined with a single space between a literal keyword and
  # its neighbours (`fsm Name with Data`).
  defp render_header(segments, inline, grammar, keyword, indent) do
    {parts, _rest} =
      Enum.reduce(segments, {[], inline}, fn
        {:lit, lit}, {parts, rest} ->
          {[lit | parts], rest}

        {:hole, _name}, {parts, [arg | rest]} ->
          {[emit_macro_arg(arg, grammar, indent) | parts], rest}

        {:hole, _name}, {parts, []} ->
          {parts, []}

        {:family, _name}, {parts, [arg | rest]} ->
          {[emit_macro_arg(arg, grammar, indent) | parts], rest}

        {:family, _name}, {parts, []} ->
          {parts, []}
      end)

    rendered =
      parts
      |> Enum.reverse()
      |> Enum.reject(&(&1 == ""))
      |> Enum.join(" ")

    String.trim(if keyword == "", do: rendered, else: "#{keyword} #{rendered}")
  end

  # Render a single non-repeated macro argument. A `:family_input` in the
  # header position is a family *record* (e.g. supervisor settings);
  # render its present options space-separated.
  defp emit_macro_arg({:family_input, meta, children}, grammar, indent) do
    {values, repeated} = split_repeated(children)
    family = meta[:family]
    field_names = family_field_names(grammar, family)

    # Pair each positional option with the grammar's field name so a
    # structured record (`actor`, `app`, `sup`) renders as
    # `field value` lines rather than a bare value list.
    labelled =
      values
      |> Enum.with_index()
      |> Enum.flat_map(fn
        {{:family_option, [present: false], _}, _i} ->
          []

        {{:family_option, _om, [value]}, i} ->
          [{Enum.at(field_names, i), value, family_field_cardinality(grammar, family, i)}]

        {other, i} ->
          [{Enum.at(field_names, i), other, family_field_cardinality(grammar, family, i)}]
      end)

    # A `repeated` field (`repeated terminal Red`) is a bare-name row of its
    # own, not a value on the header line.
    {rows, labelled} = Enum.split_with(labelled, fn {_n, _v, card} -> card == :repeated end)

    {inline, blocks} = Enum.split_with(labelled, fn {_n, v, _c} -> not multiline?(v) end)

    header =
      inline
      |> Enum.map(fn {name, value, _c} -> render_header_value(name, value, indent) end)
      |> Enum.reject(&(&1 == ""))
      |> Enum.join(" ")

    blocks_str =
      Enum.map_join(blocks, "", fn {name, value, _c} ->
        "\n#{pad(indent + 2)}#{field_label(name)}#{emit(value, indent + 2)}"
      end)

    rows_str =
      Enum.map_join(rows, "", fn {name, value, _c} ->
        "\n#{pad(indent + 2)}#{field_label(name)}#{render_header_value(name, value, indent + 2)}"
      end)

    repeated_str =
      case repeated do
        [] ->
          ""

        elements ->
          inner = pad(indent + 2)

          Enum.map_join(elements, "", fn element ->
            "\n#{inner}#{emit_family_element(element, grammar, indent + 2, family)}"
          end)
      end

    header <> blocks_str <> rows_str <> repeated_str
  end

  # A module-name argument in a macro header (`fsm Cure.Main.T`) is carried as
  # a symbol literal but renders as a bare dotted name, matching Cure's own
  # formatter.
  defp emit_macro_arg({:literal, meta, name}, _grammar, indent) do
    if Keyword.get(meta, :subtype) == :symbol do
      case name do
        atom when is_atom(atom) -> atom |> Atom.to_string() |> String.trim_leading(":")
        other -> to_string(other)
      end
    else
      emit({:literal, meta, name}, indent)
    end
  end

  defp emit_macro_arg(other, _grammar, indent), do: emit(other, indent)

  # A header value that names a `Name` family field (the FSM's
  # `terminal Red` / `initial Idle` rows) is a bare name, not a call. Cure's
  # parser records it as a `:variable`; printing `Red` keeps the row a
  # declaration instead of turning it into `Red()`.
  defp render_header_value(_name, {:variable, _meta, name}, _indent) when is_binary(name),
    do: name

  defp render_header_value(_name, value, indent), do: emit(value, indent)

  # A value that renders across several lines (a `case`/`match`/`pickup`
  # block) must be placed on its own indented lines rather than joined onto
  # the macro header.
  defp multiline?({type, _meta, _})
       when type in [:case_block, :pattern_match, :pickup, :with_abs],
       do: true

  defp multiline?({:block, _meta, [_ | _]}), do: true
  defp multiline?(_), do: false

  # Render one repeated family element (e.g. a single FSM transition row)
  # by matching its present fields against the family's productions and
  # substituting the holes in the matching production's segment template.
  defp emit_family_element(element, grammar, indent, fallback_family \\ nil)

  defp emit_family_element({:family_input, meta, children}, grammar, indent, fallback_family) do
    family = meta[:family] || fallback_family

    # Within a family *element* a bare list is a positional payload group
    # (the `(Unlocked)` in `Locked --coin(Unlocked)--> Unlocked`), not the
    # repeated group that belongs to the enclosing record.
    values =
      Enum.flat_map(children, fn
        list when is_list(list) -> [{:payload_group, list}]
        other -> [other]
      end)

    fields = drop_absent_values(values)

    base =
      case match_production(grammar, family, fields) do
        nil -> Enum.map_join(fields, " ", &emit_element_value(&1, indent))
        {production, field_values} -> render_segments(production[:segments], field_values, indent)
      end

    clauses = continuation_clauses(fields, grammar, family)

    case clauses do
      [] ->
        base

      clauses ->
        inner = pad(indent + 2)
        base <> Enum.map_join(clauses, "", fn c -> "\n#{inner}#{emit_clause(c, indent + 2)}" end)
    end
  end

  defp emit_family_element(other, _grammar, indent, _fallback), do: emit(other, indent)

  # Drop the positional placeholders the parser keeps for absent optional
  # fields: an absent `:family_option` and an empty payload group
  # (`--Coin()-->`) are not surface syntax.
  defp drop_absent_values(values) do
    Enum.reject(values, &(absent_option?(&1) or empty_payload_group?(&1)))
  end

  # The trailing `when`/`update` continuation clauses of an element: the
  # last `continuation_clause_count/2` values, when they are present
  # options. The parser records the clause body but not its keyword, so the
  # printer labels it from the grammar.
  defp continuation_clauses(fields, grammar, family) do
    if continuation_clause_count(grammar, family) == 0 do
      []
    else
      # The parser records only the clause bodies it actually saw, so the
      # clauses are whichever trailing values are present options — never
      # the production fields that precede them.
      fields
      |> Enum.reverse()
      |> Enum.take_while(&match?({:family_option, _, [_]}, &1))
      |> Enum.map(&continuation_clause_value/1)
      |> Enum.reverse()
    end
  end

  defp absent_option?({:family_option, meta, []}), do: Keyword.get(meta, :present) == false
  defp absent_option?(_), do: false

  # An empty payload group (`--Coin()-->`) is no payload at all.
  defp empty_payload_group?({:payload_group, []}), do: true
  defp empty_payload_group?(_), do: false

  defp continuation_clause_value({:family_option, _meta, [value]}), do: value
  defp continuation_clause_value(other), do: other

  # How many trailing `Expression`-shaped optional fields the element's
  # grammar declares. Zero when the grammar is unknown.
  defp continuation_clause_count(nil, _family), do: 0

  defp continuation_clause_count(grammar, family) when is_map(grammar) do
    grammar
    |> Map.values()
    |> Enum.flat_map(fn
      fields when is_map(fields) -> fields |> Map.values() |> Enum.flat_map(&clause_fields_of/1)
      _ -> []
    end)
    |> case do
      [] ->
        grammar |> element_grammar(family) |> declared_clause_count()

      counts ->
        Enum.max(counts)
    end
  end

  defp continuation_clause_count(_grammar, _family), do: 0

  defp clause_fields_of(%{field_records: records}) when is_list(records) do
    [count_clause_records(records)]
  end

  defp clause_fields_of(%{fields: fields}) when is_list(fields) do
    [count_clause_records(fields)]
  end

  defp clause_fields_of(_), do: []

  defp declared_clause_count(%{field_records: records}) when is_list(records),
    do: count_clause_records(records)

  defp declared_clause_count(%{fields: fields}) when is_list(fields),
    do: count_clause_records(fields)

  defp declared_clause_count(_), do: 0

  defp count_clause_records(records) do
    Enum.count(records, fn
      %{shape: shape, cardinality: :optional} -> shape in ["Expression", "Code"]
      _ -> false
    end)
  end

  # The grammar record that describes the element's own fields (as opposed to
  # the enclosing record's field list).
  defp element_grammar(grammar, family) do
    grammar
    |> Map.values()
    |> Enum.find_value(fn
      %{fields: fields} = field when is_list(fields) ->
        nested =
          Enum.find_value(fields, fn
            %{grammar: %{name: ^family} = g} -> g
            _ -> nil
          end)

        nested || field

      _ ->
        nil
    end)
  end

  # Find the production whose `:fields` count matches, then zip the
  # production's field names with the supplied values.
  defp match_production(grammar, family, values) do
    productions = family_productions(grammar, family)
    count = length(values)

    case Enum.find(productions, fn p -> length(p[:fields]) == count end) do
      nil ->
        nil

      production ->
        {production, Enum.zip(production[:fields], values) |> Map.new()}
    end
  end

  # The distilled grammar is `%{family_name => %{field_name => [production]}}`.
  # Collect every production of the named family regardless of which field
  # declared it.
  defp family_productions(grammar, family) when is_map(grammar) do
    direct = Map.get(grammar, family)

    case extract_productions(direct) do
      [_ | _] = productions ->
        productions

      [] ->
        # The grammar is keyed by the *family* that owns the field (for
        # example "definition"), not by the element family itself, so the
        # element's productions live in a nested `grammar` record under one
        # of those fields. Collect every production from every field of
        # every family.
        grammar
        |> Map.values()
        |> Enum.flat_map(fn
          fields when is_map(fields) ->
            fields |> Map.values() |> Enum.flat_map(&extract_productions/1)

          _ ->
            []
        end)
    end
  end

  defp family_productions(_grammar, _family), do: []

  # A distilled family field is `%{productions: [...], fields: [...]}`.
  defp extract_productions(%{productions: productions}) when is_list(productions), do: productions
  defp extract_productions(_), do: []

  # Substitute `{:lit, text}` / `{:hole, name}` segments into source text.
  #
  # Cure's family productions record each punctuation character as its own
  # `:lit` segment, so consecutive literals are joined without spaces and
  # a hole is padded with a space on either side. A leading `*` marker
  # (wildcard-from) is emitted as-is.
  defp render_segments(segments, field_values, indent) do
    segments
    |> Enum.map(fn
      {:lit, text} -> {:lit, text}
      {:hole, name} -> {:hole, render_hole(Map.get(field_values, name), indent)}
    end)
    |> join_segments()
  end

  # Join substituted segments into source text.
  #
  # Cure records each punctuation character of a production as its own
  # `:lit` segment (`-`, `-`, `-`, `>`), so consecutive literals are first
  # coalesced into a single run (`--`, `-->`). A hole is then padded with a
  # space on both sides, except against a tight opener (`(`) or closer
  # (`)`, `,`). This reproduces Cure's own formatter output
  # (`Red --Timer--> Green`).
  defp join_segments(segments) do
    segments
    |> split_wildcard_marker()
    |> coalesce_lits()
    |> Enum.reduce({[], nil}, fn
      {:lit, text}, {acc, _prev} -> {[acc, lit_prefix(text) <> text], {:lit, text}}
      {:hole, text}, {acc, prev} -> {[acc, hole_prefix(prev, text) <> text], {:hole, text}}
    end)
    |> then(fn {acc, _} -> acc |> IO.iodata_to_binary() |> String.trim() end)
    |> separate_wildcard()
  end

  # `*` is a token of its own; the separator run that follows it must not be
  # glued on (`* --Emergency--> Red`, never `*-- Emergency--> Red`).
  defp separate_wildcard("*" <> rest) when rest != "", do: "* " <> String.trim_leading(rest)

  defp separate_wildcard(text), do: text

  # A leading wildcard `*` is a token of its own even when the grammar
  # records it glued to the separator run that follows (`*--`), so split it
  # back out before the literals are coalesced.
  defp split_wildcard_marker([{:lit, "*"} | tail]), do: [{:lit, "*"} | tail]

  defp split_wildcard_marker([{:lit, "*" <> rest} | tail]) when rest != "",
    do: [{:lit, "*"}, {:lit, rest} | tail]

  defp split_wildcard_marker(segments), do: segments

  # Fold consecutive `{:lit, _}` segments into one.
  defp coalesce_lits(segments) do
    segments
    |> Enum.reduce([], fn
      {:lit, text}, [{:lit, prev} | rest] -> [{:lit, prev <> text} | rest]
      seg, acc -> [seg | acc]
    end)
    |> Enum.reverse()
  end

  # A literal run that follows a hole is preceded by a space unless it
  # starts with tight punctuation (an opener or a closer) or is a *forward*
  # arrow run (`-->`, `->`), which binds to the preceding word.
  defp lit_prefix(text) do
    cond do
      String.starts_with?(text, ["(", ")", ",", "."]) -> ""
      arrow_run?(text) -> ""
      true -> " "
    end
  end

  # A hole is preceded by a space unless the previous literal is a tight
  # opener or a left-binding separator run (`--`, `=`). An arrow run
  # (`-->`, `->`) names the following hole, so it keeps a trailing space
  # (`Red --go--> Green`). A hole that renders to nothing (an absent
  # optional field) contributes nothing, so no separator is emitted for it.
  defp hole_prefix(_prev, ""), do: ""

  # A wildcard marker (`* --Emergency--> Red`) is its own token, so the
  # separator run that follows it keeps a leading space.
  defp hole_prefix({:lit, "*"}, hole) when hole != "", do: " "

  defp hole_prefix({:lit, text}, _hole) do
    cond do
      text in ["(", "."] -> ""
      arrow_run?(text) -> " "
      separator_run?(text) -> ""
      true -> " "
    end
  end

  defp hole_prefix(_prev, _hole), do: ""
  defp arrow_run?(text), do: Regex.match?(~r/\A[-=]*>\z/, text)
  defp separator_run?(text), do: Regex.match?(~r/\A[-=<>|:]+\z/, text)

  defp render_hole(nil, _indent), do: ""

  defp render_hole({:payload, group}, indent),
    do: Enum.map_join(group, ", ", &emit_payload(&1, indent))

  defp render_hole({:payload_group, group}, indent),
    do: Enum.map_join(group, ", ", &emit_payload(&1, indent))

  defp render_hole(value, indent), do: emit(value, indent)

  # A transition payload is a list of `:param` nodes; only the parameter
  # name is surface syntax (`--coin(Unlocked)-->`).
  defp emit_payload({:param, _meta, name}, _indent), do: to_string(name)
  defp emit_payload(other, indent), do: emit(other, indent)

  # A type parameter may be a bare name (interface/type-param lists) or a
  # full AST node (`indices (n: Nat)`). Render both.
  defp emit_type_param(name, _indent) when is_binary(name), do: name
  defp emit_type_param(name, _indent) when is_atom(name), do: to_string(name)
  defp emit_type_param(node, indent), do: emit(node, indent)

  # Cure spells operator-named and reserved-word functions with backticks
  # (`fn \`==\`(a, b)`, `fn \`not\`(a)`).
  @reserved_words ~w(
    fn mod rec fsm actor interface implementation type typealias primitive let
    pickup else match with when local use return throw try catch finally for in
    true false nil and or not spawn send receive after unsafe quote syntax
    becomes computed by end do
  )

  # A function body that renders across several lines (`match`, `pickup`,
  # `with`, a `case` block) starts on its own line after the `=`.
  defp multiline_body?({type, _meta, _})
       when type in [
              :pattern_match,
              :pickup,
              :with_abs,
              :case_block,
              :exception_handling,
              :proof_chain,
              :induction
            ],
       do: true

  defp multiline_body?({:block, _meta, [_ | _]}), do: true
  defp multiline_body?(_), do: false

  defp quote_name(name) when is_binary(name) do
    cond do
      name in @reserved_words -> "`#{name}`"
      Regex.match?(~r/\A[A-Za-z_][A-Za-z0-9_]*[?!]?\z/, name) -> name
      true -> "`#{name}`"
    end
  end

  defp quote_name(name) when is_atom(name), do: quote_name(to_string(name))
  defp quote_name(other), do: to_string(other)

  defp emit_function_def(_meta, body, indent, vis, name, param_strs, ret) do
    header = "#{vis}fn #{quote_name(name)}(#{param_strs})#{ret}"

    case body do
      [] ->
        header

      # A single `:block` body is the multi-statement form: render its
      # statements one per line, nested under the header.
      [{:block, _meta, []}] ->
        header

      [{:block, _meta, statements}] ->
        inner = pad(indent + 2)
        rendered = Enum.map_join(statements, "\n#{inner}", &emit(&1, indent + 2))
        "#{header} =\n#{inner}#{rendered}"

      [single] ->
        if multiline_body?(single) do
          inner = pad(indent + 2)
          "#{header} =\n#{inner}#{emit(single, indent + 2)}"
        else
          "#{header} = #{emit(single, indent)}"
        end

      statements ->
        inner = pad(indent + 2)
        rendered = Enum.map_join(statements, "\n#{inner}", &emit(&1, indent + 2))
        "#{header} =\n#{inner}#{rendered}"
    end
  end

  # Render a statement list inline (space-separated) for single-line
  # positions such as a `match` arm body.
  defp emit_body_inline([], _indent), do: ""

  # An arm body that is a single multi-statement `:block` renders one
  # statement per line beneath the arrow.
  defp emit_body_inline([{:block, _meta, [_ | _] = statements}], indent) do
    inner = pad(indent + 2)
    "\n#{inner}" <> Enum.map_join(statements, "\n#{inner}", &emit(&1, indent + 2))
  end

  defp emit_body_inline([single], indent), do: emit(single, indent)

  defp emit_body_inline(statements, indent) do
    Enum.map_join(statements, "; ", &emit(&1, indent))
  end

  # Split a `:pi_type` body into its domain and codomain.
  defp split_pi([dom, cod]), do: {dom, cod}
  defp split_pi([dom]), do: {dom, {:literal, [subtype: :symbol], :type}}
  defp split_pi(_), do: {{:variable, [], "_"}, {:literal, [subtype: :symbol], :type}}

  defp emit_macro_rule(%{kind: :syntax} = rule, indent) do
    keyword = rule[:keyword] || ""
    keyword_str = if keyword != "", do: " #{keyword}", else: ""
    contextual = if rule[:contextual], do: " contextual", else: ""

    target = rule[:template] || rule[:expander]

    if target do
      "syntax#{keyword_str}#{contextual} becomes #{emit(target, indent)}"
    else
      "syntax#{keyword_str}#{contextual}"
    end
  end

  defp emit_macro_rule(%{kind: :computed} = rule, indent) do
    keyword = rule[:keyword] || ""
    keyword_str = if keyword != "", do: " #{keyword} ", else: " "
    elab = rule[:elab] || rule[:template] || rule[:expander]
    verb = if rule[:direct_inputs], do: "computed directly by", else: "computed by"
    "syntax#{keyword_str}#{verb} #{emit(elab, indent)}"
  end

  defp emit_macro_rule(%{kind: :literal, template: template}, indent) do
    "literal becomes #{emit(template, indent)}"
  end

  defp emit_macro_rule(%{kind: :accepts, family: family}, _indent) do
    "accepts #{family}"
  end

  defp emit_macro_rule(%{kind: :expands_with, expander: expander}, indent) do
    "expands with #{emit(expander, indent)}"
  end

  defp emit_macro_rule(%{kind: :syntax_family, name: name}, _indent) do
    "syntax family #{name}"
  end

  defp emit_macro_rule(%{kind: :open_category, name: name}, _indent) do
    "open #{name}"
  end

  defp emit_macro_rule(%{kind: :fail, name: name}, _indent) do
    "fail #{name}"
  end

  defp emit_macro_rule(rule, _indent) when is_map(rule) do
    kind = Map.get(rule, :kind, "rule")
    "#{kind}"
  end

  defp emit_field({:param, meta, name}, indent) do
    type = if meta[:type], do: ": #{emit(meta[:type], indent)}", else: ""
    "#{to_string(name)}#{type}"
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

  defp emit_variant({:variable, _, name}), do: to_string(name)

  # A variant may be any type expression (a qualified name, an applied
  # constructor, a function-type payload, ...). Fall back to the general
  # emitter rather than crashing.
  defp emit_variant(other), do: emit(other, 0)

  # Actor container rendering (Cure v0.25.0+).
  # Emits `actor Name [with InitExpr]` followed by lifecycle callback blocks.
  # All callbacks live in meta (the body is always []).
  @actor_callback_keys [:on_start, :on_message, :on_stop]
  defp emit_actor(meta, _body, indent) do
    name = meta[:name]
    init = meta[:init]
    pad_inner = pad(indent + 2)

    init_str = if init, do: " with #{emit(init, indent)}", else: ""

    callbacks_str =
      Enum.map_join(@actor_callback_keys, "", fn cb ->
        case meta[cb] do
          clauses when is_list(clauses) and clauses != [] ->
            inner = Enum.map_join(clauses, "\n#{pad(indent + 4)}", &emit(&1, indent + 4))
            "\n#{pad_inner}#{cb}\n#{pad(indent + 4)}#{inner}"

          _ ->
            ""
        end
      end)

    "actor #{name}#{init_str}#{callbacks_str}"
  end

  # Supervisor container rendering (Cure v0.25.0+).
  # Emits `sup Name` followed by optional strategy settings and a
  # `children` block containing one line per child_spec in the body.
  @sup_setting_keys [:strategy, :intensity, :period]
  defp emit_supervisor(meta, body, indent) do
    name = meta[:name]
    pad_inner = pad(indent + 2)

    settings_str =
      Enum.map_join(@sup_setting_keys, "", fn key ->
        case meta[key] do
          nil -> ""
          val -> "\n#{pad_inner}#{key} = #{emit(val, indent)}"
        end
      end)

    children_str =
      if body == [] do
        ""
      else
        specs = Enum.map_join(body, "\n#{pad(indent + 4)}", &emit(&1, indent + 4))
        "\n#{pad_inner}children\n#{pad(indent + 4)}#{specs}"
      end

    "sup #{name}#{settings_str}#{children_str}"
  end

  # App container rendering (Cure v0.26.0+).
  # Emits `app Name` followed by all declarative settings and callbacks.
  # All content lives in meta (the body is always []).
  @app_setting_keys [
    :vsn,
    :description,
    :root,
    :applications,
    :included_applications,
    :env,
    :registered
  ]
  @app_callback_keys [:on_start, :on_stop]
  defp emit_app(meta, _body, indent) do
    name = meta[:name]
    pad_inner = pad(indent + 2)

    settings_str =
      Enum.map_join(@app_setting_keys, "", fn key ->
        case meta[key] do
          nil -> ""
          val -> "\n#{pad_inner}#{key} = #{emit(val, indent)}"
        end
      end)

    callbacks_str =
      Enum.map_join(@app_callback_keys, "", fn cb ->
        case meta[cb] do
          clauses when is_list(clauses) and clauses != [] ->
            inner = Enum.map_join(clauses, "\n#{pad(indent + 4)}", &emit(&1, indent + 4))
            "\n#{pad_inner}#{cb}\n#{pad(indent + 4)}#{inner}"

          _ ->
            ""
        end
      end)

    # on_phase entries: keyword list of [{phase_atom, [clauses]}]
    phase_entries =
      meta
      |> Keyword.get_values(:on_phase)
      |> List.flatten()

    phases_str =
      Enum.map_join(phase_entries, "", fn {phase, clauses} ->
        inner = Enum.map_join(clauses, "\n#{pad(indent + 4)}", &emit(&1, indent + 4))
        "\n#{pad_inner}on_phase :#{phase}\n#{pad(indent + 4)}#{inner}"
      end)

    "app #{name}#{settings_str}#{callbacks_str}#{phases_str}"
  end

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
