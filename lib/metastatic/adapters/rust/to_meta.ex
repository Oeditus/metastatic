defmodule Metastatic.Adapters.Rust.ToMeta do
  @moduledoc """
  Transform Rust AST from `syn` (M1) to MetaAST (M2).

  Transforms items, statements, expressions, patterns and literals into uniform
  MetaAST 3-tuples: `{type_atom, keyword_meta, children_or_value}`.

  ## Mapping strategy

  Every node is mapped to the highest (most portable) MetaAST layer it can
  reach; `:language_specific` is used only for constructs with no
  cross-language analogue.

  ### M2.1 Core

  | Rust (M1) | MetaAST (M2) |
  | :--- | :--- |
  | `Literal` | `{:literal, [subtype: ...], value}` |
  | `Path` (single segment) | `{:variable, [scope: :local], name}` |
  | `Binary` | `{:binary_op, [category: ..., operator: ...], [l, r]}` |
  | `Unary` | `{:unary_op, [category: ..., operator: ...], [operand]}` |
  | `Call` / `MethodCall` | `{:function_call, [name: ...], args}` |
  | `If` | `{:conditional, [], [cond, then, else]}` |
  | `Return` | `{:early_return, [], [value]}` |
  | `Block` / `File` | `{:block, [], statements}` |
  | `Array` | `{:list, [], elements}` |
  | `Tuple` | `{:tuple, [], elements}` |
  | `Let` / `Assign` | `{:assignment, [mutable: ...], [pattern, value]}` |
  | `Range` | `{:range, [], [start, end]}` |
  | `Paren` | unwrapped (grouping only) |

  ### M2.2 Extended

  | Rust | MetaAST |
  | :--- | :--- |
  | `While` / `Loop` / `ForLoop` | `{:loop, [loop_type: ...], ...}` |
  | `Match` | `{:pattern_match, [], [scrutinee, arms...]}` |
  | `Closure` | `{:lambda, [params: ...], body}` |
  | `Await` | `{:async_operation, [op_type: :await], [inner]}` |
  | `Try` (`?`) | `{:exception_handling, [kind: :propagate], [inner]}` |

  ### M2.2s Structural

  | Rust | MetaAST |
  | :--- | :--- |
  | `Function` | `{:function_def, [name:, params:, visibility:, arity:], body}` |
  | `Struct` / `Enum` / `Trait` / `Impl` / `Module` | `{:container, [container_type:, name:], body}` |
  | `Param` | `{:param, [type: ...], name}` |
  | `Field` | `{:attribute_access, [attribute: name], [receiver]}` |
  | `Use` | `{:import, [source:, import_type: :use], []}` |
  | `TypeAlias` | `{:type_annotation, [annotation_type: :type], [...]}` |

  ### M2.3 Native

  Anything else becomes `{:language_specific, [language: :rust, hint: ...], node}`,
  preserving the original M1 node so `FromMeta` can restore it exactly.
  """

  alias Metastatic.AST

  @doc """
  Transform a Rust AST (M1) to MetaAST.

  Returns `{:ok, meta_ast, metadata}` on success or `{:error, reason}` on
  failure.

  ## Examples

      iex> {:ok, ast} = Metastatic.Adapters.Rust.Subprocess.parse("1 + 2")
      iex> {:ok, meta, _} = Metastatic.Adapters.Rust.ToMeta.transform(ast)
      iex> elem(meta, 0)
      :binary_op
  """
  @spec transform(term()) :: {:ok, term(), map()} | {:error, String.t()}
  def transform(%{"kind" => "File"} = file) do
    with {:ok, statements} <- transform_children(file) do
      {:ok, {:block, [scope: :module] ++ location(file), statements}, %{}}
    end
  end

  def transform(%{"kind" => _} = node) do
    with {:ok, meta_node} <- transform_node(node) do
      {:ok, meta_node, %{}}
    end
  end

  def transform(other) do
    {:error, "Unsupported Rust AST: #{inspect(other, limit: 5)}"}
  end

  # ----- Items -----

  defp transform_node(%{"kind" => "Function"} = node) do
    {params, body} = split_params(node)

    with {:ok, param_nodes} <- transform_params(params),
         {:ok, body_nodes} <- transform_children_list(body) do
      meta = [
        name: Map.get(node, "name", "anonymous"),
        params: param_nodes,
        visibility: :public,
        arity: length(param_nodes),
        return_type: type_name(Map.get(node, "type_node"))
      ]

      {:ok, {:function_def, meta ++ location(node), body_nodes}}
    end
  end

  defp transform_node(%{"kind" => kind} = node)
       when kind in ["Struct", "Enum", "Trait", "Impl", "Module"] do
    with {:ok, body} <- transform_children(node) do
      meta = [
        container_type: container_type(kind),
        name: Map.get(node, "name", "anonymous"),
        # `:impl` is not a MetaAST container type, so it is stored here for
        # `FromMeta` to recover the original Rust item kind.
        rust_kind: kind,
        language: :rust
      ]

      {:ok, {:container, meta ++ location(node), body}}
    end
  end

  defp transform_node(%{"kind" => "Field"} = node) do
    # A struct field declaration is a named, typed slot. `:param` is the closest
    # cross-language analogue (a named binding with a type), and it keeps a
    # container's children as nodes rather than bare lists.
    type_node = Map.get(node, "type_node")

    with {:ok, type_ast} <- transform_optional(type_node) do
      meta = [
        type: type_ast,
        type_name: type_name(type_node),
        visibility: :public,
        rust_kind: "Field"
      ]

      {:ok, {:param, meta ++ location(node), Map.get(node, "name", "field")}}
    end
  end

  defp transform_node(%{"kind" => "Variant"} = node) do
    # A bare enum variant is a named constant; model it as a variable so it
    # participates in cross-language analysis rather than becoming opaque.
    {:ok, {:variable, [scope: :module] ++ location(node), Map.get(node, "name", "_")}}
  end

  defp transform_node(%{"kind" => "Use"} = node) do
    source = Map.get(node, "name", "")
    meta = [source: normalise_path(source), import_type: :use, language: :rust]
    {:ok, {:import, meta ++ location(node), []}}
  end

  defp transform_node(%{"kind" => "TypeAlias"} = node) do
    name = Map.get(node, "name", "type")
    # The right-hand side is the whole point of a type alias; dropping it
    # turned `type Table = HashMap<..>` into `type Table = ();`.
    meta = [annotation_type: :type, name: name, type_name: type_name(node["type_node"])]
    {:ok, {:type_annotation, meta ++ location(node), []}}
  end

  defp transform_node(%{"kind" => "MacroInvocation"} = node) do
    hint = :macro_invocation
    {:ok, {:language_specific, [language: :rust, hint: hint] ++ location(node), node}}
  end

  # ----- Statements -----

  defp transform_node(%{"kind" => "Let"} = node) do
    pattern = Map.get(node, "pattern")
    value = node |> Map.get("children", []) |> List.first()

    with {:ok, pattern_node} <- transform_pattern(pattern),
         {:ok, value_node} <- transform_optional(value) do
      # `rust_kind` distinguishes a `let` binding from a reassignment; the
      # abstracted target shape alone cannot.
      meta = [mutable: mutable_pattern?(pattern), rust_kind: "Let"]
      {:ok, {:assignment, meta ++ location(node), [pattern_node, value_node]}}
    end
  end

  # ----- Expressions -----

  defp transform_node(%{"kind" => "Literal"} = node) do
    {:ok, literal_node(node)}
  end

  defp transform_node(%{"kind" => "Path"} = node) do
    {:ok,
     {:variable, [scope: :local] ++ location(node), normalise_path(Map.get(node, "name", "_"))}}
  end

  defp transform_node(%{"kind" => "Binary"} = node) do
    with {:ok, [left, right]} <- transform_two_children(node) do
      {category, operator} = map_binary_op(Map.get(node, "name", "+"))
      meta = [category: category, operator: operator]
      {:ok, {:binary_op, meta ++ location(node), [left, right]}}
    end
  end

  defp transform_node(%{"kind" => "Unary"} = node) do
    with {:ok, [operand]} <- transform_children(node) do
      {category, operator} = map_unary_op(Map.get(node, "name", "-"))
      meta = [category: category, operator: operator]
      {:ok, {:unary_op, meta ++ location(node), [operand]}}
    end
  end

  defp transform_node(%{"kind" => "Call"} = node) do
    with {:ok, args} <- transform_children(node) do
      meta = [name: normalise_path(Map.get(node, "name", "call"))]
      {:ok, {:function_call, meta ++ location(node), args}}
    end
  end

  defp transform_node(%{"kind" => "MethodCall"} = node) do
    children = Map.get(node, "children", [])
    {receiver, args} = List.pop_at(children, 0)

    with {:ok, receiver_node} <- transform_optional(receiver),
         {:ok, arg_nodes} <- transform_children_list(args) do
      # The receiver is folded into the name, matching the convention the other
      # adapters use (`"user.save"`), and kept as the first argument so the
      # semantic enricher can extract a target from it.
      method = Map.get(node, "name", "call")
      name = receiver_name(receiver, method)
      # `rust_kind` records that this was a method call even when the receiver
      # is not a simple path, so `FromMeta` does not have to re-derive it from
      # the name.
      meta = [name: name, rust_kind: "MethodCall", method: method]
      {:ok, {:function_call, meta ++ location(node), [receiver_node | arg_nodes]}}
    end
  end

  defp transform_node(%{"kind" => "FieldAccess"} = node) do
    with {:ok, [base]} <- transform_children(node) do
      meta = [attribute: Map.get(node, "name", "field")]
      {:ok, {:attribute_access, meta ++ location(node), [base]}}
    end
  end

  # Rust's `v[i]` has no `:binary_op` category, so it is modelled as a call on
  # the indexing operator. That keeps the node conforming and still lets
  # analyzers see both the collection and the index.
  defp transform_node(%{"kind" => "Index"} = node) do
    with {:ok, children} <- transform_children(node) do
      {:ok, {:function_call, [name: "[]"] ++ location(node), children}}
    end
  end

  defp transform_node(%{"kind" => "If"} = node) do
    children = Map.get(node, "children", [])

    with {:ok, nodes} <- transform_children_list(children) do
      case nodes do
        [condition, then_branch] ->
          {:ok, {:conditional, location(node), [condition, then_branch, nil]}}

        [condition, then_branch, else_branch] ->
          {:ok, {:conditional, location(node), [condition, then_branch, else_branch]}}

        _ ->
          {:ok, {:language_specific, [language: :rust, hint: :if], node}}
      end
    end
  end

  defp transform_node(%{"kind" => "Return"} = node) do
    with {:ok, children} <- transform_children(node) do
      {:ok, {:early_return, location(node), children}}
    end
  end

  defp transform_node(%{"kind" => "Block"} = node) do
    with {:ok, statements} <- transform_children(node) do
      {:ok, {:block, location(node), statements}}
    end
  end

  defp transform_node(%{"kind" => "While"} = node) do
    with {:ok, [condition, body]} <- transform_two_children(node) do
      {:ok, {:loop, [loop_type: :while] ++ location(node), [condition, body]}}
    end
  end

  defp transform_node(%{"kind" => "ForLoop"} = node) do
    pattern = Map.get(node, "pattern")
    children = Map.get(node, "children", [])

    with {:ok, pattern_node} <- transform_pattern(pattern),
         {:ok, nodes} <- transform_children_list(children) do
      case nodes do
        [iterable, body] ->
          {:ok, {:loop, [loop_type: :for] ++ location(node), [pattern_node, iterable, body]}}

        _ ->
          {:ok, {:language_specific, [language: :rust, hint: :for], node}}
      end
    end
  end

  defp transform_node(%{"kind" => "Loop"} = node) do
    with {:ok, [body]} <- transform_children(node) do
      # MetaAST spells a condition-less loop `:infinite`; `:loop` is not a
      # recognised `loop_type`.
      {:ok, {:loop, [loop_type: :infinite] ++ location(node), [body]}}
    end
  end

  defp transform_node(%{"kind" => "Match"} = node) do
    children = Map.get(node, "children", [])
    {scrutinee, arms} = List.pop_at(children, 0)

    with {:ok, scrutinee_node} <- transform_optional(scrutinee),
         {:ok, arm_nodes} <- transform_children_list(arms) do
      {:ok, {:pattern_match, location(node), [scrutinee_node | arm_nodes]}}
    end
  end

  defp transform_node(%{"kind" => "MatchArm"} = node) do
    pattern = Map.get(node, "pattern")

    with {:ok, pattern_node} <- transform_pattern(pattern),
         {:ok, body} <- transform_children(node) do
      meta = [pattern: pattern_node, guard: nil]
      {:ok, {:match_arm, meta ++ location(node), body}}
    end
  end

  defp transform_node(%{"kind" => "Closure"} = node) do
    with {:ok, body} <- transform_children(node) do
      {:ok, {:lambda, [params: [], captures: []] ++ location(node), body}}
    end
  end

  defp transform_node(%{"kind" => "Array"} = node) do
    with {:ok, elements} <- transform_children(node) do
      {:ok, {:list, location(node), elements}}
    end
  end

  defp transform_node(%{"kind" => "Tuple"} = node) do
    with {:ok, elements} <- transform_children(node) do
      {:ok, {:tuple, location(node), elements}}
    end
  end

  defp transform_node(%{"kind" => "Assign"} = node) do
    with {:ok, [left, right]} <- transform_two_children(node) do
      {:ok, {:assignment, location(node), [left, right]}}
    end
  end

  defp transform_node(%{"kind" => "Range"} = node) do
    with {:ok, bounds} <- transform_children(node) do
      # `:range` is defined as `[start, stop]`. Rust allows a half-open range
      # (`0..`), which carries a single bound; pad it so the node stays
      # conforming instead of being rejected by the validator.
      padded = bounds ++ List.duplicate(nil, max(0, 2 - length(bounds)))
      {:ok, {:range, location(node), Enum.take(padded, 2)}}
    end
  end

  defp transform_node(%{"kind" => "Await"} = node) do
    with {:ok, [inner]} <- transform_children(node) do
      {:ok, {:async_operation, [op_type: :await] ++ location(node), [inner]}}
    end
  end

  defp transform_node(%{"kind" => "Async"} = node) do
    with {:ok, body} <- transform_children(node) do
      {:ok, {:async_operation, [op_type: :async] ++ location(node), body}}
    end
  end

  # `&x` / `&mut x`. Modelled as a unary operation so the borrow is visible to
  # analyzers; the mutability is kept for `FromMeta`.
  defp transform_node(%{"kind" => "Reference"} = node) do
    with {:ok, [inner]} <- transform_children(node) do
      mutable = Map.get(node, "mutability", false)

      {:ok,
       {:unary_op, [category: :arithmetic, operator: :ref, mutable: mutable] ++ location(node),
        [inner]}}
    end
  end

  # `unsafe { ... }` has no cross-language analogue.
  defp transform_node(%{"kind" => "Unsafe"} = node) do
    {:ok, {:language_specific, [language: :rust, hint: :unsafe] ++ location(node), node}}
  end

  # `let Some(x) = expr` in `if let` / `while let` position.
  defp transform_node(%{"kind" => "LetExpr"} = node) do
    with {:ok, pattern} <- transform_pattern(Map.get(node, "pattern")),
         {:ok, [value]} <- transform_children(node) do
      {:ok, {:inline_match, location(node), [pattern, value]}}
    end
  end

  defp transform_node(%{"kind" => "Try"} = node) do
    with {:ok, [inner]} <- transform_children(node) do
      # `expr?` propagates the error to the caller: the closest cross-language
      # analogue is a try/catch that re-raises.
      meta = [kind: :propagate]
      {:ok, {:exception_handling, meta ++ location(node), [inner, [], nil]}}
    end
  end

  defp transform_node(%{"kind" => "StructExpr"} = node) do
    with {:ok, fields} <- transform_children(node) do
      meta = [struct: normalise_path(Map.get(node, "name", "Struct"))]
      {:ok, {:map, meta ++ location(node), fields}}
    end
  end

  defp transform_node(%{"kind" => "StructField"} = node) do
    with {:ok, [value]} <- transform_children(node) do
      key = {:variable, [scope: :field], Map.get(node, "name", "field")}
      {:ok, {:pair, location(node), [key, value]}}
    end
  end

  # Grouping only: `(a + b) * 2` and `a + b * 2` are different programs, but the
  # Parentheses are semantically transparent, but dropping them loses the
  # grouping that the *printer* needs: `(a + b) * c` and `a + b * c` produce
  # different trees, so unwrapping on the way in would silently change
  # precedence on the way back out. The inner expression is kept as the only
  # child and `FromMeta` re-emits the parentheses.
  defp transform_node(%{"kind" => "Paren"} = node) do
    with {:ok, [inner]} <- transform_children(node) do
      {:ok, {:language_specific, [language: :rust, hint: :paren] ++ location(node), inner}}
    end
  end

  defp transform_node(%{"kind" => "Const"} = node) do
    with {:ok, children} <- transform_children(node) do
      meta = [name: Map.get(node, "name", "CONST"), visibility: :public]
      {:ok, {:function_def, meta ++ location(node), children}}
    end
  end

  defp transform_node(%{"kind" => "Unsupported"} = node) do
    {:ok, {:language_specific, [language: :rust, hint: :unsupported] ++ location(node), node}}
  end

  defp transform_node(%{"kind" => kind} = node) do
    # Unknown but well-formed: preserve it rather than failing the whole parse.
    {:ok, {:language_specific, [language: :rust, hint: hint_for(kind)] ++ location(node), node}}
  end

  # ----- Patterns -----

  defp transform_pattern(nil), do: {:ok, {:wildcard, [], nil}}

  defp transform_pattern(%{"kind" => "Wild"} = node) do
    {:ok, {:wildcard, location(node), nil}}
  end

  defp transform_pattern(%{"kind" => "Ident"} = node) do
    # `semi` is a statement terminator, not a mutability flag; mutability lives
    # on the pattern's own `mutability` key.
    meta = [scope: :local, mutable: Map.has_key?(node, "mutability")]
    {:ok, {:variable, meta ++ location(node), Map.get(node, "name", "_")}}
  end

  # `self`, `&self`, `&mut self` and `mut self` are receivers. They are kept as
  # distinct variables so `FromMeta` can restore the exact receiver form.
  defp transform_pattern(%{"kind" => kind} = node)
       when kind in ["Self", "RefSelf", "RefMutSelf", "MutSelf"] do
    {:ok, {:variable, [scope: :receiver, receiver: kind] ++ location(node), "self"}}
  end

  defp transform_pattern(%{"kind" => "PathPat"} = node) do
    {:ok,
     {:variable, [scope: :local] ++ location(node), normalise_path(Map.get(node, "name", "_"))}}
  end

  defp transform_pattern(%{"kind" => "TuplePat"} = node) do
    with {:ok, elements} <- transform_pattern_children(node) do
      {:ok, {:tuple, location(node), elements}}
    end
  end

  defp transform_pattern(node) when is_map(node), do: transform_node(node)

  defp transform_pattern(other),
    do: {:ok, {:language_specific, [language: :rust, hint: :pattern], other}}

  defp transform_pattern_children(node) do
    node
    |> Map.get("children", [])
    |> reduce_ok(&transform_pattern/1)
  end

  # ----- Literals -----

  defp literal_node(node) do
    loc = location(node)
    value = Map.get(node, "value") || %{}
    subtype = Map.get(value, "subtype", "string")
    raw = Map.get(value, "value")

    case {subtype, raw} do
      {"integer", number} when is_integer(number) ->
        {:literal, [subtype: :integer] ++ loc, number}

      {"big_integer", text} when is_binary(text) ->
        {:literal, [subtype: :integer] ++ loc, text}

      {"float", number} when is_number(number) ->
        {:literal, [subtype: :float] ++ loc, number * 1.0}

      {"string", text} ->
        {:literal, [subtype: :string] ++ loc, text}

      {"boolean", flag} when is_boolean(flag) ->
        {:literal, [subtype: :boolean] ++ loc, flag}

      {"char", text} ->
        {:literal, [subtype: :char] ++ loc, text}

      {"bytes", bytes} when is_list(bytes) ->
        {:literal, [subtype: :bytes] ++ loc, :binary.list_to_bin(bytes)}

      {_other, text} when is_binary(text) ->
        {:literal, [subtype: :string] ++ loc, text}

      _ ->
        {:literal, [subtype: :null] ++ loc, nil}
    end
  end

  # ----- Helpers -----

  defp transform_children(node) do
    node
    |> Map.get("children", [])
    |> transform_children_list()
  end

  defp transform_children_list(children) when is_list(children) do
    reduce_ok(children, &transform_node/1)
  end

  defp transform_children_list(_), do: {:ok, []}

  defp transform_two_children(node) do
    case transform_children(node) do
      {:ok, [_, _] = pair} -> {:ok, pair}
      {:ok, other} -> {:error, "expected two children, got #{length(other)}"}
      error -> error
    end
  end

  defp transform_optional(nil), do: {:ok, nil}

  defp transform_optional(node), do: transform_node(node)

  defp transform_params(params) do
    reduce_ok(params, &transform_param/1)
  end

  defp transform_param(%{"kind" => "Param"} = node) do
    pattern = Map.get(node, "pattern") || %{}
    name = Map.get(pattern, "name", "_")
    type_node = Map.get(node, "type_node")

    with {:ok, type_ast} <- transform_optional(type_node),
         {:ok, pattern_ast} <- transform_pattern(pattern) do
      # The pattern is kept so `FromMeta` can restore `self` receivers and
      # destructured parameters instead of rebuilding a bare identifier.
      meta = [type: type_ast, type_name: type_name(type_node), pattern: pattern_ast]
      {:ok, {:param, meta ++ location(node), name}}
    end
  end

  defp transform_param(node), do: transform_node(node)

  defp type_name(%{"name" => name}) when is_binary(name), do: name
  defp type_name(_), do: nil

  defp reduce_ok(items, fun) when is_list(items) do
    Enum.reduce_while(items, {:ok, []}, fn item, {:ok, acc} ->
      case fun.(item) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      error -> error
    end
  end

  defp split_params(node) do
    children = Map.get(node, "children", [])
    split_at = Enum.find_index(children, &(Map.get(&1, "kind") != "Param")) || length(children)
    Enum.split(children, split_at)
  end

  defp mutable_pattern?(%{"mutability" => true}), do: true
  defp mutable_pattern?(_), do: false

  # `syn` renders a path as `a :: b :: c`; normalise it to `a::b::c` so the
  # semantic pattern tables can match on it.
  defp normalise_path(path) when is_binary(path) do
    path
    |> String.replace(~r/\s*::\s*/, "::")
    |> String.trim()
  end

  defp normalise_path(_), do: "_"

  defp receiver_name(nil, method), do: method

  defp receiver_name(%{"kind" => "Path", "name" => name}, method),
    do: "#{normalise_path(name)}.#{method}"

  defp receiver_name(_receiver, method), do: method

  defp container_type("Struct"), do: :struct
  defp container_type("Enum"), do: :enum
  defp container_type("Trait"), do: :trait
  # `:impl` is not a MetaAST container type. An inherent `impl` is the block
  # that carries a type's methods, which is exactly `:class`; a trait `impl`
  # is distinguished by the `:trait` metadata key rather than by the type.
  defp container_type("Impl"), do: :class
  defp container_type("Module"), do: :module
  defp container_type(_), do: :module

  defp hint_for(kind), do: kind |> Macro.underscore() |> String.to_atom()

  defp location(%{"span" => %{"line" => line, "col" => col}} = node)
       when is_integer(line) and line > 0 do
    # `semi` (statement terminator) is semantically load-bearing: a tail
    # expression is a block's value, a `;`-terminated one discards it. It is
    # carried on every node so `FromMeta` never has to guess.
    base = [line: line, col: col]
    if Map.get(node, "semi", false), do: base ++ [semi: true], else: base
  end

  defp location(node) when is_map(node) do
    if Map.get(node, "semi", false), do: [semi: true], else: []
  end

  defp map_binary_op(op) do
    case op do
      "+" -> {:arithmetic, :+}
      "-" -> {:arithmetic, :-}
      "*" -> {:arithmetic, :*}
      "/" -> {:arithmetic, :/}
      "%" -> {:arithmetic, :%}
      "==" -> {:comparison, :==}
      "!=" -> {:comparison, :!=}
      ">" -> {:comparison, :>}
      ">=" -> {:comparison, :>=}
      "<" -> {:comparison, :<}
      "<=" -> {:comparison, :<=}
      "&&" -> {:boolean, :and}
      "||" -> {:boolean, :or}
      "&" -> {:bitwise, :bitand}
      "|" -> {:bitwise, :bitor}
      "^" -> {:bitwise, :bitxor}
      "<<" -> {:bitwise, :lshift}
      ">>" -> {:bitwise, :rshift}
      ".." -> {:range, :..}
      "..=" -> {:range, :range_inclusive}
      _ -> {:arithmetic, :+}
    end
  end

  defp map_unary_op(op) do
    case op do
      "!" -> {:boolean, :not}
      "-" -> {:arithmetic, :-}
      "*" -> {:arithmetic, :deref}
      "&" -> {:arithmetic, :ref}
      _ -> {:arithmetic, :-}
    end
  end

  @doc false
  # Exposed for tests: the MetaAST layer of a node, via the single source of
  # truth in `Metastatic.AST`.
  def layer(node), do: AST.layer(node)
end
