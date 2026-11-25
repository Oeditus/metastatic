defmodule Metastatic.Adapters.Gleam.FromMeta do
  @moduledoc """
  Reifies MetaAST into the Gleam bridge's tagged M1 JSON.

  The inverse of `Metastatic.Adapters.Gleam.ToMeta`. Every child is rebuilt
  recursively: an original file is never replayed, so an edit made at M2
  survives reification.

  ## Strategy

  MetaAST nodes are mapped back to the M1 `kind` they came from. Where the
  abstraction was lossy — a `:pipe` chain, a `:list` with a spread tail, a
  `:labeled` argument — the original M1 payload is restored from the metadata
  `ToMeta` recorded, because the M2 shape alone cannot distinguish, say,
  `[1, ..xs]` from `[1, xs]`.

  Nodes that cannot be reified (an M2 construct Gleam has no syntax for)
  return `{:error, reason}` rather than emitting something invalid.

  ## Examples

      iex> {:ok, node} = Metastatic.Adapters.Gleam.FromMeta.transform({:variable, [], "x"})
      iex> node["kind"]
      "Var"
  """

  alias Metastatic.AST

  @operator_variants %{
    {:arithmetic, :+} => "AddInt",
    {:arithmetic, :-} => "SubInt",
    {:arithmetic, :*} => "MultInt",
    {:arithmetic, :/} => "DivInt",
    {:arithmetic, :rem} => "RemainderInt",
    {:comparison, :==} => "Eq",
    {:comparison, :!=} => "NotEq",
    {:comparison, :<} => "LtInt",
    {:comparison, :<=} => "LtEqInt",
    {:comparison, :>} => "GtInt",
    {:comparison, :>=} => "GtEqInt",
    {:boolean, :and} => "And",
    {:boolean, :or} => "Or",
    {:string, :<>} => "Concatenate"
  }

  @doc """
  Converts MetaAST to a Gleam M1 node.

  Returns `{:error, reason}` for a non-conforming MetaAST or a construct Gleam
  cannot express; it never raises.

  ## Examples

      iex> {:ok, node} = Metastatic.Adapters.Gleam.FromMeta.transform({:literal, [subtype: :integer], "42"})
      iex> node["value"]
      %{"subtype" => "integer", "value" => "42"}
  """
  @spec transform(AST.meta_ast(), map()) :: {:ok, map()} | {:error, String.t()}
  def transform(ast, metadata \\ %{}) do
    _ = metadata

    if AST.conforms?(ast) do
      try do
        {:ok, convert(ast)}
      rescue
        error in [ArgumentError, FunctionClauseError, MatchError] ->
          {:error, "Invalid MetaAST for Gleam: #{Exception.message(error)}"}
      catch
        {:gleam_reification, reason} -> {:error, reason}
      end
    else
      {:error, "Cannot reify a non-conforming MetaAST as Gleam"}
    end
  end

  # ── Module ─────────────────────────────────────────────────────────

  defp convert({:block, meta, statements}) when is_list(statements) do
    if Keyword.get(meta, :scope) == :module do
      %{
        "kind" => "Module",
        "span" => span(meta),
        "comments" => module_comments(meta),
        "children" => Enum.map(statements, &convert/1)
      }
    else
      %{"kind" => "Block", "span" => span(meta), "children" => Enum.map(statements, &convert/1)}
    end
  end

  defp convert({:comment, _meta, text}) when is_binary(text) do
    # Comments are hoisted to the module's `comments` list by `ToMeta`, so a
    # standalone one is dropped rather than rendered as a statement.
    %{"kind" => "Comment", "span" => span([]), "name" => text}
  end

  # ── Definitions ────────────────────────────────────────────────────

  defp convert({:function_def, meta, body}) do
    params = Keyword.get(meta, :params, [])

    %{
      "kind" => "Fn",
      "span" => span(meta),
      "name" => Keyword.get(meta, :name, "anonymous"),
      "public" => Keyword.get(meta, :visibility) == :public,
      "children" => Enum.map(params, &convert/1) ++ Enum.map(body, &convert/1),
      "type_node" => type_node(Keyword.get(meta, :return_type)),
      "extra" =>
        compact(%{
          "publicity" =>
            if(Keyword.get(meta, :visibility) == :public, do: "public", else: "private"),
          "documentation" => Keyword.get(meta, :documentation),
          "deprecated" => Keyword.get(meta, :deprecated),
          "target" => Keyword.get(meta, :target),
          "external_erlang" => Keyword.get(meta, :external_erlang),
          "external_javascript" => Keyword.get(meta, :external_javascript)
        })
    }
  end

  defp convert({:type_annotation, meta, children}) do
    case Keyword.get(meta, :gleam_kind) do
      "TypeAlias" ->
        %{
          "kind" => "TypeAlias",
          "span" => span(meta),
          "name" => Keyword.get(meta, :name, "Anonymous"),
          "public" => Keyword.get(meta, :visibility) == :public,
          "type_node" => convert_optional(Keyword.get(meta, :type)),
          "extra" =>
            compact(%{
              "publicity" =>
                if(Keyword.get(meta, :visibility) == :public, do: "public", else: "private"),
              "parameters" => Keyword.get(meta, :parameters, [])
            })
        }

      "TypeConstructor" ->
        %{
          "kind" => "TypeConstructor",
          "span" => span(meta),
          "name" => Keyword.get(meta, :name),
          "children" => Enum.map(List.wrap(children), &convert/1),
          "extra" => %{"module" => module_of(Keyword.get(meta, :name))}
        }

      "FnType" ->
        arguments = Keyword.get(meta, :arguments, [])

        %{
          "kind" => "FnType",
          "span" => span(meta),
          "children" =>
            Enum.map(arguments, &convert/1) ++
              List.wrap(convert_optional(Keyword.get(meta, :type)))
        }

      "TupleType" ->
        %{
          "kind" => "TupleType",
          "span" => span(meta),
          "children" => Enum.map(List.wrap(children), &convert/1)
        }

      "TypeVar" ->
        %{"kind" => "TypeVar", "span" => span(meta), "name" => Keyword.get(meta, :name)}

      "TypeHole" ->
        %{"kind" => "TypeHole", "span" => span(meta), "name" => Keyword.get(meta, :name)}

      _ ->
        %{
          "kind" => "TypeConstructor",
          "span" => span(meta),
          "name" => Keyword.get(meta, :name),
          "children" => Enum.map(List.wrap(children), &convert/1),
          "extra" => %{"module" => module_of(Keyword.get(meta, :name))}
        }
    end
  end

  defp convert({:container, meta, children}) do
    case Keyword.get(meta, :container_type) do
      :enum ->
        %{
          "kind" => "CustomType",
          "span" => span(meta),
          "name" => Keyword.get(meta, :name, "Anonymous"),
          "public" => Keyword.get(meta, :visibility) == :public,
          "opaque" => Keyword.get(meta, :opaque, false),
          "children" => Enum.map(children, &convert/1),
          "extra" =>
            compact(%{
              "publicity" =>
                if(Keyword.get(meta, :visibility) == :public, do: "public", else: "private"),
              "parameters" => Keyword.get(meta, :parameters, []),
              "documentation" => Keyword.get(meta, :documentation)
            })
        }

      :struct ->
        %{
          "kind" => "RecordConstructor",
          "span" => span(meta),
          "name" => Keyword.get(meta, :name, "Constructor"),
          "children" => Enum.map(children, &convert/1),
          "extra" => compact(%{"documentation" => Keyword.get(meta, :documentation)})
        }

      _ ->
        %{
          "kind" => "CustomType",
          "span" => span(meta),
          "name" => Keyword.get(meta, :name, "Anonymous"),
          "public" => Keyword.get(meta, :visibility) == :public,
          "children" => Enum.map(children, &convert/1),
          "extra" => %{"parameters" => Keyword.get(meta, :parameters, [])}
        }
    end
  end

  # `:param`'s third element is the parameter's name (see `ToMeta`).
  defp convert({:param, meta, name}) do
    case Keyword.get(meta, :gleam_kind) do
      "RecordConstructorArg" ->
        %{
          "kind" => "RecordConstructorArg",
          "span" => span(meta),
          "type_node" => type_node(Keyword.get(meta, :type)),
          "extra" => compact(%{"label" => Keyword.get(meta, :label)})
        }

      _ ->
        %{
          "kind" => "Arg",
          "span" => span(meta),
          "name" => to_string(name),
          "discard" => Keyword.get(meta, :discard, false),
          "type_node" => type_node(Keyword.get(meta, :type)),
          "extra" => compact(%{"label" => Keyword.get(meta, :label)})
        }
    end
  end

  defp convert({:import, meta, _children}) do
    names = Keyword.get(meta, :names, [])
    {types, values} = Enum.split_with(names, &String.starts_with?(&1, "type "))

    %{
      "kind" => "Import",
      "span" => span(meta),
      "name" => Keyword.get(meta, :source, ""),
      "extra" =>
        compact(%{
          "as_name" => Keyword.get(meta, :alias),
          "values" => Enum.map(values, &unqualified_import/1),
          "types" => Enum.map(types, &unqualified_import/1)
        })
    }
  end

  # ── Statements ─────────────────────────────────────────────────────

  defp convert({:assignment, meta, [target, value]}) do
    case Keyword.get(meta, :binding) do
      :constant ->
        %{
          "kind" => "ModuleConstant",
          "span" => span(meta),
          "name" => Keyword.get(meta, :name, "constant"),
          "public" => Keyword.get(meta, :visibility) == :public,
          "children" => [convert(value)],
          "type_node" => convert_optional(Keyword.get(meta, :type)),
          "extra" =>
            compact(%{
              "publicity" =>
                if(Keyword.get(meta, :visibility) == :public, do: "public", else: "private")
            })
        }

      binding ->
        %{
          "kind" => "Let",
          "span" => span(meta),
          "pattern" => convert(target),
          "children" => [convert(value)],
          "type_node" => convert_optional(Keyword.get(meta, :type)),
          "extra" => %{"kind" => if(binding == :assert, do: "assert", else: "let")}
        }
    end
  end

  defp convert({:block, meta, statements}) do
    if Keyword.get(meta, :scope) == :use do
      {assignments, body} =
        Enum.split_with(statements, fn
          {:assignment, inner, _} -> Keyword.get(inner, :binding) == :use
          _ -> false
        end)

      %{
        "kind" => "Use",
        "span" => span(meta),
        "children" => Enum.map(body, &convert/1),
        "extra" => %{
          "assignments" =>
            Enum.map(assignments, fn {:assignment, _inner, [pattern]} ->
              %{"pattern" => convert(pattern), "annotation" => nil}
            end)
        }
      }
    else
      %{"kind" => "Block", "span" => span(meta), "children" => Enum.map(statements, &convert/1)}
    end
  end

  defp convert({:assert, meta, [value]}) do
    %{
      "kind" => "Assert",
      "span" => span(meta),
      "children" => [convert(value)] ++ List.wrap(convert_optional(Keyword.get(meta, :message)))
    }
  end

  # ── Expressions ────────────────────────────────────────────────────

  defp convert({:literal, meta, value}) do
    subtype = Keyword.get(meta, :subtype, :string)

    %{
      "kind" => literal_kind(subtype),
      "span" => span(meta),
      "value" => %{
        "subtype" => literal_subtype(subtype),
        # The source spelling wins when `ToMeta` had to keep one (a bignum, a
        # trailing zero); otherwise the value is rendered back to text.
        "value" => Keyword.get(meta, :gleam_literal) || to_string(value)
      }
    }
  end

  defp convert({:variable, meta, name}) do
    case Keyword.get(meta, :scope) do
      :discard ->
        %{"kind" => "Discard", "span" => span(meta), "name" => to_string(name), "discard" => true}

      :invalid ->
        %{"kind" => "InvalidPattern", "span" => span(meta)}

      :qualified ->
        %{
          "kind" => "Var",
          "span" => span(meta),
          "name" => to_string(name),
          "extra" => %{"module" => Keyword.get(meta, :module)}
        }

      _ ->
        %{"kind" => "Var", "span" => span(meta), "name" => to_string(name)}
    end
  end

  defp convert({:lambda, meta, body}) do
    params = Keyword.get(meta, :params, [])

    %{
      "kind" => "FnLiteral",
      "span" => span(meta),
      "children" => Enum.map(params, &convert/1) ++ Enum.map(body, &convert/1),
      "type_node" => type_node(Keyword.get(meta, :return_type)),
      "extra" => compact(%{"kind" => Keyword.get(meta, :kind) || "anonymous"})
    }
  end

  defp convert({:list, meta, elements}) do
    if Keyword.get(meta, :list_kind) == :bit_array do
      %{"kind" => "BitArray", "span" => span(meta), "children" => Enum.map(elements, &convert/1)}
    else
      {spreads, plain} =
        Enum.split_with(elements, fn
          {:spread, _meta, _} -> true
          _ -> false
        end)

      %{
        "kind" => "List",
        "span" => span(meta),
        "children" => Enum.map(plain, &convert/1),
        "extra" => %{
          "tail" =>
            case spreads do
              [{:spread, _meta, [inner]}] -> convert(inner)
              _ -> nil
            end
        }
      }
    end
  end

  defp convert({:tuple, meta, elements}) do
    %{"kind" => "Tuple", "span" => span(meta), "children" => Enum.map(elements, &convert/1)}
  end

  defp convert({:bin_segment, meta, [value]}) do
    %{
      "kind" => "BitArraySegment",
      "span" => span(meta),
      "children" => [convert(value)],
      "extra" => %{"options" => bit_array_options(meta)}
    }
  end

  # A `use` expression was desugared into `f(fn(x) { … })` by `ToMeta`; undo
  # that so the original `use x <- f()` comes back.
  defp convert({:function_call, meta, arguments}) do
    if Keyword.get(meta, :gleam_kind) == "Use" do
      convert_use(meta, arguments)
    else
      convert_call(meta, arguments)
    end
  end

  defp convert({:labeled, meta, [inner]}) do
    %{
      "kind" => "CallArg",
      "span" => span(meta),
      "children" => [convert(inner)],
      "extra" => %{"label" => Keyword.get(meta, :label)}
    }
  end

  defp convert({:binary_op, meta, [left, right]}) do
    category = Keyword.get(meta, :category)
    operator = Keyword.get(meta, :operator)

    variant =
      Keyword.get(meta, :gleam_operator) ||
        Map.get(@operator_variants, {category, operator}, "AddInt")

    %{
      "kind" => "BinOp",
      "span" => span(meta),
      "name" => operator_symbol(variant),
      "children" => [convert(left), convert(right)],
      "extra" => %{"operator" => variant}
    }
  end

  defp convert({:unary_op, meta, [operand]}) do
    kind = if Keyword.get(meta, :category) == :boolean, do: "NegateBool", else: "NegateInt"
    %{"kind" => kind, "span" => span(meta), "children" => [convert(operand)]}
  end

  defp convert({:pipe, meta, [left, right]}) do
    # A nested `:pipe` is the left-associated chain `ToMeta` built, so
    # flattening it restores the original `Pipeline` node.
    %{
      "kind" => "Pipeline",
      "span" => span(meta),
      "children" => flatten_pipe(left) ++ [convert(right)]
    }
  end

  defp convert({:pattern_match, meta, [subject | clauses]}) do
    # A multi-subject case was modelled as a case on an implicit tuple; undo
    # that so the original `case a, b { … }` comes back.
    subjects =
      case subject do
        {:tuple, inner, many} ->
          if Keyword.get(inner, :implicit) and
               Keyword.get(meta, :subject_count, 1) == length(many) do
            many
          else
            [subject]
          end

        single ->
          [single]
      end

    %{
      "kind" => "Case",
      "span" => span(meta),
      "children" => Enum.map(subjects, &convert/1) ++ Enum.map(clauses, &convert/1)
    }
  end

  defp convert({:match_arm, meta, body}) do
    # `patterns:` carries every subject of a multi-subject clause; `pattern:`
    # is the single-node form `AST` requires and is the fallback for a
    # hand-written tree.
    patterns =
      case Keyword.get(meta, :patterns) do
        nil -> List.wrap(Keyword.get(meta, :pattern))
        patterns -> patterns
      end

    guard =
      case Keyword.get(meta, :guard) do
        {:language_specific, _meta, payload} -> payload
        _ -> nil
      end

    %{
      "kind" => "Clause",
      "span" => span(meta),
      "children" => Enum.map(patterns, &convert/1) ++ Enum.map(body, &convert/1),
      "extra" => %{
        "guard" => guard,
        "pattern_count" => length(patterns),
        "alternative_patterns" => Keyword.get(meta, :alternative_patterns, 0)
      }
    }
  end

  defp convert({:attribute_access, meta, [receiver]}) do
    attribute = Keyword.get(meta, :attribute, "")

    if attribute =~ ~r/^\d+$/ do
      %{
        "kind" => "TupleIndex",
        "span" => span(meta),
        "children" => [convert(receiver)],
        "extra" => %{"index" => String.to_integer(attribute)}
      }
    else
      %{
        "kind" => "FieldAccess",
        "span" => span(meta),
        "name" => attribute,
        "children" => [convert(receiver)]
      }
    end
  end

  defp convert({:throw, meta, children}) do
    kind = if Keyword.get(meta, :kind) == :panic, do: "Panic", else: "Todo"

    %{
      "kind" => kind,
      "span" => span(meta),
      "children" => Enum.map(children, &convert/1),
      "extra" => compact(%{"kind" => Keyword.get(meta, :todo_kind)})
    }
  end

  defp convert({:record_update, meta, [base | arguments]}) do
    name = Keyword.get(meta, :name, "Record")

    %{
      "kind" => "RecordUpdate",
      "span" => span(meta),
      "children" => [callee_node(name, meta), convert(base) | Enum.map(arguments, &convert/1)]
    }
  end

  defp convert({:inline_match, meta, [inner | _]}) do
    %{
      "kind" => "Assign",
      "span" => span(meta),
      "name" => Keyword.get(meta, :name, "_"),
      "children" => [convert(inner)]
    }
  end

  defp convert({:language_specific, _meta, payload}) when is_map(payload) do
    # `ToMeta` keeps the original M1 node for constructs it does not model, so
    # reification is an identity — which is what makes `echo`, clause guards
    # and string-prefix patterns round-trip exactly.
    payload
  end

  defp convert({:language_specific, _meta, payload}) do
    throw(
      {:gleam_reification,
       "Cannot reify Gleam language_specific payload: #{inspect(payload, limit: 5)}"}
    )
  end

  defp convert(other) do
    throw({:gleam_reification, "Cannot reify #{inspect(other, limit: 5)} as Gleam"})
  end

  # Rebuilds a `use` node from the desugared call plus its callback.
  defp convert_use(meta, arguments) do
    {callback, call_arguments} =
      case List.pop_at(arguments, -1) do
        {{:lambda, _lambda_meta, _body} = lambda, rest} -> {lambda, rest}
        {other, rest} -> {other, rest}
      end

    assignments =
      case callback do
        {:lambda, lambda_meta, body} ->
          params = Keyword.get(lambda_meta, :params, [])

          Enum.map(params, fn {:param, _param_meta, name} ->
            pattern =
              Enum.find_value(body, fn
                {:assignment, inner, [target, _value]} ->
                  if Keyword.get(inner, :binding) == :use, do: target

                _ ->
                  nil
              end)

            %{
              "pattern" => convert(pattern || {:variable, [scope: :local], to_string(name)}),
              "annotation" => nil
            }
          end)

        _ ->
          []
      end

    %{
      "kind" => "Use",
      "span" => span(meta),
      "children" => [convert_call(meta, call_arguments)],
      "extra" => %{"assignments" => assignments}
    }
  end

  defp convert_call(meta, arguments) do
    kind =
      cond do
        Keyword.get(meta, :pattern) -> "Constructor"
        Keyword.get(meta, :record) -> "Record"
        true -> "Call"
      end

    callee = callee_node(Keyword.get(meta, :name, "<anonymous>"), meta)

    children =
      case kind do
        "Call" -> [callee | Enum.map(arguments, &convert/1)]
        _ -> Enum.map(arguments, &convert/1)
      end

    node = %{"kind" => kind, "span" => span(meta), "children" => children}

    case kind do
      "Call" ->
        node

      "Constructor" ->
        Map.merge(node, %{
          "name" => Keyword.get(meta, :name, "Constructor"),
          "extra" => %{
            "module" => nil,
            "spread" => if(Keyword.get(meta, :spread), do: span(meta), else: nil)
          }
        })

      "Record" ->
        Map.merge(node, %{
          "name" => Keyword.get(meta, :name, "Record"),
          "extra" => %{
            "module" => nil,
            "has_arguments" => true
          }
        })
    end
  end

  # ── Helpers ────────────────────────────────────────────────────────

  defp flatten_pipe({:pipe, _meta, [left, right]}), do: flatten_pipe(left) ++ [convert(right)]
  defp flatten_pipe(other), do: [convert(other)]

  defp callee_node(name, meta) when is_binary(name) do
    case String.split(name, ".") do
      [single] ->
        %{"kind" => "Var", "span" => span(meta), "name" => single}

      parts ->
        {module, [function]} = Enum.split(parts, -1)

        %{
          "kind" => "Var",
          "span" => span(meta),
          "name" => function,
          "extra" => %{"module" => Enum.join(module, ".")}
        }
    end
  end

  defp callee_node(name, meta), do: callee_node(to_string(name), meta)

  defp module_of(nil), do: nil

  defp module_of(name) when is_binary(name) do
    case String.split(name, ".") do
      [_single] -> nil
      parts -> parts |> Enum.drop(-1) |> Enum.join(".")
    end
  end

  defp module_of(_), do: nil

  defp convert_optional(nil), do: nil
  defp convert_optional(node), do: convert(node)

  # A parameter's `:type` is a plain string (see `ToMeta`), so it is rebuilt as
  # a `TypeConstructor` node. A tree that carries a full `:type_annotation`
  # node instead is passed through unchanged.
  defp type_node(nil), do: nil
  defp type_node(name) when is_binary(name), do: %{"kind" => "TypeConstructor", "name" => name}
  defp type_node(node), do: convert(node)

  defp span(meta) do
    %{
      "line" => Keyword.get(meta, :line, 0),
      "col" => Keyword.get(meta, :col, 0),
      "end_line" => Keyword.get(meta, :line, 0),
      "end_col" => Keyword.get(meta, :col, 0)
    }
  end

  defp module_comments(meta) do
    meta
    |> Keyword.get(:module_comments, [])
    |> Enum.map(fn {:comment, _meta, text} -> text end)
  end

  defp compact(map) do
    map
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp unqualified_import(name) do
    case String.split(name, " as ") do
      [single] ->
        %{"name" => String.replace_prefix(single, "type ", ""), "as_name" => nil}

      [original, alias_name] ->
        %{"name" => String.replace_prefix(original, "type ", ""), "as_name" => alias_name}
    end
  end

  defp literal_kind(:integer), do: "Int"
  defp literal_kind(:float), do: "Float"
  defp literal_kind(_), do: "String"

  defp literal_subtype(:integer), do: "integer"
  defp literal_subtype(:float), do: "float"
  defp literal_subtype(_), do: "string"

  defp operator_symbol(variant) do
    case variant do
      "And" -> "&&"
      "Or" -> "||"
      "Eq" -> "=="
      "NotEq" -> "!="
      "LtInt" -> "<"
      "LtFloat" -> "<."
      "LtEqInt" -> "<="
      "LtEqFloat" -> "<=."
      "GtInt" -> ">"
      "GtFloat" -> ">."
      "GtEqInt" -> ">="
      "GtEqFloat" -> ">=."
      "AddInt" -> "+"
      "AddFloat" -> "+."
      "SubInt" -> "-"
      "SubFloat" -> "-."
      "MultInt" -> "*"
      "MultFloat" -> "*."
      "DivInt" -> "/"
      "DivFloat" -> "/."
      "RemainderInt" -> "%"
      "Concatenate" -> "<>"
      _ -> "+"
    end
  end

  defp bit_array_options(meta) do
    type =
      case Keyword.get(meta, :type) do
        nil -> []
        type -> [%{"name" => Atom.to_string(type), "span" => span(meta)}]
      end

    # `:size` is a MetaAST node (see `ToMeta.bit_array_size/2`), so it is
    # reified back to an M1 node rather than copied through as a raw value.
    size =
      case Keyword.get(meta, :size) do
        nil ->
          []

        value ->
          [
            %{
              "name" => "size",
              "span" => span(meta),
              "extra" => %{"value" => convert(value), "short_form" => false}
            }
          ]
      end

    unit =
      case Keyword.get(meta, :unit) do
        nil -> []
        value -> [%{"name" => "unit", "span" => span(meta), "extra" => %{"value" => value}}]
      end

    signedness =
      case Keyword.get(meta, :signedness) do
        nil -> []
        value -> [%{"name" => Atom.to_string(value), "span" => span(meta)}]
      end

    endianness =
      case Keyword.get(meta, :endianness) do
        nil -> []
        value -> [%{"name" => Atom.to_string(value), "span" => span(meta)}]
      end

    type ++ size ++ unit ++ signedness ++ endianness
  end
end
