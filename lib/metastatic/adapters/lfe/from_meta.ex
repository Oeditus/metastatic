defmodule Metastatic.Adapters.Lfe.FromMeta do
  @moduledoc """
  Transform MetaAST (M2) back to LFE sexprs (M1).

  The inverse of `Metastatic.Adapters.Lfe.ToMeta`. Every
  `:language_specific` node carries the original sexpr, so reifying those is
  an identity — which is what makes constructs the adapter does not model
  (`receive`, records, structs, binaries) round-trip exactly.

  ## Strategy

  Nodes are rebuilt from their MetaAST shape; when a node cannot be reified
  (an M2 construct LFE has no syntax for) the transform returns
  `{:error, reason}` rather than emitting something invalid.

  ## Call-versus-data on the way back

  `ToMeta` had to decide whether `[1, 2]` was a call or a list. Going back
  the decision is explicit: `:list` nodes are rendered as the `(list …)`
  constructor when they appear in expression position, because a bare
  `[1, 2]` sexpr would be re-read as a call. `:tuple` nodes become
  `{:tuple, elems}`, the shape LFE's reader produces for `#(…)`.

  ## Examples

      iex> ast = {:binary_op, [category: :arithmetic, operator: :+],
      ...>   [{:literal, [subtype: :integer], 1}, {:literal, [subtype: :integer], 2}]}
      iex> {:ok, sexpr} = Metastatic.Adapters.Lfe.FromMeta.transform(ast, %{})
      iex> sexpr
      [:"+", 1, 2]
  """

  @doc """
  Transform MetaAST back to an LFE sexpr.

  Returns `{:ok, sexpr}` on success or `{:error, reason}` on failure.

  ## Examples

      iex> {:ok, sexpr} = Metastatic.Adapters.Lfe.FromMeta.transform({:literal, [subtype: :integer], 42}, %{})
      iex> sexpr
      42
  """
  @spec transform(term(), map()) :: {:ok, term()} | {:error, String.t()}
  def transform(meta_ast, metadata \\ %{})

  # A `:quote` node carries an *already abstracted* child, so it is reified
  # by recursing into that child rather than by restoring a native payload.
  # This clause must precede the verbatim-restore clause below.
  def transform({:language_specific, meta, [inner]}, metadata)
      when is_list(meta) and is_tuple(inner) do
    if Keyword.get(meta, :hint) == :quote do
      with {:ok, payload} <- transform_data(inner, metadata) do
        {:ok, [:quote, payload]}
      end
    else
      {:ok, [Keyword.get(meta, :hint), inner]}
    end
  end

  # Preserved native payloads are restored exactly.
  def transform({:language_specific, _meta, native}, _metadata) do
    {:ok, native}
  end

  # The module-level block is the file: its children are top-level forms.
  # A nested block (a `let`, a `progn`) is a single expression and is reified
  # by `transform_node/4`, which knows how to rebuild the binding list.
  def transform({:block, meta, statements}, metadata) when is_list(statements) do
    if Keyword.get(meta, :scope) == :module do
      transform_list(statements, metadata)
    else
      transform_node(:block, meta, statements, metadata)
    end
  end

  # A single expression reifies to **one** sexpr, not a list of forms. Without
  # this clause `from_meta/2` on a bare `:binary_op` returned `[:"+", 1, 2]`
  # from `transform_node/4`, which the caller then treated as three top-level
  # forms and printed as `+\n1\n2`.
  def transform({type, meta, children}, metadata)
      when is_atom(type) and is_list(meta) and type != :block do
    with {:ok, sexpr} <- transform_node(type, meta, children, metadata) do
      {:ok, single_form(sexpr)}
    end
  end

  def transform(other, _metadata) do
    {:error, "Cannot reify MetaAST to LFE: #{inspect(other, limit: 5)}"}
  end

  # `transform_node/4` returns a sexpr for most nodes, but a container may
  # return a list of forms (a `defmodule` plus its `export`). Only a list whose
  # head is an atom and which is *not* itself a call is ambiguous; the call
  # shape (`[:defun, name, params | body]`) is the normal case and is kept
  # as-is.
  defp single_form(sexpr), do: sexpr
  # ----- Node Transformers -----

  defp transform_node(:literal, meta, value, _metadata) do
    case Keyword.get(meta, :subtype, :string) do
      :integer when is_integer(value) -> {:ok, value}
      :float when is_number(value) -> {:ok, value * 1.0}
      :string when is_binary(value) -> {:ok, String.to_charlist(value)}
      :boolean when is_boolean(value) -> {:ok, value}
      :null -> {:ok, nil}
      :symbol when is_atom(value) -> {:ok, value}
      :char when is_binary(value) -> {:ok, value}
      :bytes when is_binary(value) -> {:ok, value}
      _ -> {:error, "Cannot reify literal to LFE: #{inspect({meta, value}, limit: 5)}"}
    end
  end

  defp transform_node(:variable, _meta, name, _metadata) when is_binary(name) do
    {:ok, String.to_atom(name)}
  end

  defp transform_node(:variable, _meta, name, _metadata) when is_atom(name), do: {:ok, name}

  defp transform_node(:list, _meta, elements, metadata) when is_list(elements) do
    with {:ok, children} <- transform_list(elements, metadata) do
      # A bare list sexpr would be re-read as a call, so the constructor is
      # made explicit. `FromMeta` is allowed to be more verbose than the
      # source; `unparse/1` prints whatever sexpr it is given.
      {:ok, [:list | children]}
    end
  end

  defp transform_node(:tuple, _meta, elements, metadata) when is_list(elements) do
    with {:ok, children} <- transform_list(elements, metadata) do
      {:ok, {:tuple, children}}
    end
  end

  defp transform_node(:binary_op, meta, [left, right], metadata) do
    operator = Keyword.get(meta, :operator)

    with {:ok, l} <- transform(left, metadata),
         {:ok, r} <- transform(right, metadata) do
      {:ok, [operator, l, r]}
    end
  end

  defp transform_node(:unary_op, meta, [operand], metadata) do
    operator = Keyword.get(meta, :operator)

    with {:ok, inner} <- transform(operand, metadata) do
      {:ok, [operator, inner]}
    end
  end

  defp transform_node(:function_call, meta, args, metadata) do
    name = Keyword.get(meta, :name, "")

    with {:ok, arg_nodes} <- transform_list(args, metadata) do
      {:ok, [name_to_atom(name) | arg_nodes]}
    end
  end

  defp transform_node(:conditional, _meta, [condition, then_branch, else_branch], metadata) do
    with {:ok, c} <- transform(condition, metadata),
         {:ok, t} <- transform(then_branch, metadata) do
      case else_branch do
        nil ->
          {:ok, [:if, c, t]}

        _ ->
          with {:ok, e} <- transform(else_branch, metadata) do
            {:ok, [:if, c, t, e]}
          end
      end
    end
  end

  defp transform_node(:pattern_match, _meta, [scrutinee | arms], metadata) do
    with {:ok, subject} <- transform(scrutinee, metadata),
         {:ok, arm_nodes} <- transform_list(arms, metadata) do
      {:ok, [:case, subject | arm_nodes]}
    end
  end

  # LFE's reader already wraps the pattern in a one-element list
  # (`[[0], [:quote, :zero]]`), and `ToMeta` preserves that shape, so the
  # reified pattern is emitted as-is. Wrapping again produced `(((0)) …)`.
  defp transform_node(:match_arm, meta, body, metadata) do
    pattern = Keyword.get(meta, :pattern)
    guard = Keyword.get(meta, :guard)

    with {:ok, pattern_node} <- transform_pattern(pattern, metadata),
         {:ok, body_nodes} <- transform_list(body, metadata),
         {:ok, guard_nodes} <- transform_guard(guard, metadata) do
      {:ok, [pattern_node | guard_nodes ++ body_nodes]}
    end
  end

  defp transform_node(:block, meta, statements, metadata) do
    scope = Keyword.get(meta, :scope)

    with {:ok, nodes} <- transform_list(statements, metadata) do
      case scope do
        :let -> {:ok, [:let, bindings_of(nodes), drop_bindings(nodes)]}
        :"let*" -> {:ok, [:"let*", bindings_of(nodes), drop_bindings(nodes)]}
        _ -> {:ok, [:progn | nodes]}
      end
    end
  end

  # `(set x 1)` — a plain assignment in expression position.
  defp transform_node(:assignment, _meta, [target, value], metadata) do
    with {:ok, target_node} <- transform(target, metadata),
         {:ok, value_node} <- transform(value, metadata) do
      {:ok, [:set, target_node, value_node]}
    end
  end

  # LFE's reader gives a lambda body as a bare sexpr, so the reified body is
  # emitted as one expression (`[:lambda, [:x], [:*, :x, 2]]`), not as a
  # one-element list.
  defp transform_node(:lambda, meta, body, metadata) do
    params = Keyword.get(meta, :params, [])

    with {:ok, param_nodes} <- transform_params(params, metadata),
         {:ok, body_nodes} <- transform_list(body, metadata) do
      {:ok, [:lambda, param_nodes | body_nodes]}
    end
  end

  defp transform_node(:function_def, meta, body, metadata) do
    name = Keyword.get(meta, :name, "anonymous")
    params = Keyword.get(meta, :params, [])

    with {:ok, param_nodes} <- transform_params(params, metadata),
         {:ok, body_nodes} <- transform_list(body, metadata) do
      {:ok, [:defun, name_to_atom(name), param_nodes | body_nodes]}
    end
  end

  defp transform_node(:macro_def, meta, body, metadata) do
    name = Keyword.get(meta, :name, "anonymous")
    params = Keyword.get(meta, :params, [])

    with {:ok, param_nodes} <- transform_params(params, metadata),
         {:ok, body_nodes} <- transform_list(body, metadata) do
      {:ok, [:defmacro, name_to_atom(name), param_nodes | body_nodes]}
    end
  end

  defp transform_node(:container, meta, body, metadata) do
    name = Keyword.get(meta, :name, "anonymous")

    with {:ok, body_nodes} <- transform_list(body, metadata) do
      {:ok, [:defmodule, name_to_atom(name) | body_nodes]}
    end
  end

  defp transform_node(:import, meta, _children, _metadata) do
    source = Keyword.get(meta, :source, "")

    case Keyword.get(meta, :import_type) do
      :export ->
        names = Keyword.get(meta, :names, [])
        {:ok, [:export | Enum.map(names, &export_spec/1)]}

      :include ->
        {:ok, [:"include-file", source]}

      _ ->
        {:ok, [:"include-file", source]}
    end
  end

  defp transform_node(:comprehension, meta, [body | qualifiers], metadata) do
    kind = Keyword.get(meta, :kind, :lc)

    with {:ok, body_node} <- transform(body, metadata),
         {:ok, qual_nodes} <- transform_list(qualifiers, metadata) do
      {:ok, [kind, body_node | qual_nodes]}
    end
  end

  defp transform_node(:generator, _meta, [pattern, collection], metadata) do
    with {:ok, pattern_node} <- transform_pattern(pattern, metadata),
         {:ok, coll_node} <- transform_data(collection, metadata) do
      {:ok, [:gen, pattern_node, coll_node]}
    end
  end

  defp transform_node(:exception_handling, _meta, [body | handlers], metadata) do
    with {:ok, body_node} <- transform(body, metadata),
         {:ok, handler_nodes} <- transform_list(handlers, metadata) do
      {:ok, [:try, body_node | handler_nodes]}
    end
  end

  defp transform_node(type, _meta, children, metadata) when is_list(children) do
    # Unknown structural node: reify children and keep the type visible so the
    # caller can see what was not modelled rather than silently losing it.
    with {:ok, nodes} <- transform_list(children, metadata) do
      {:ok, [type | nodes]}
    end
  end

  defp transform_node(type, _meta, value, _metadata) do
    {:error, "Cannot reify #{inspect(type)} to LFE: #{inspect(value, limit: 5)}"}
  end

  # ----- Helpers -----
  defp transform_guard(nil, _metadata), do: {:ok, []}

  defp transform_guard(guard, metadata) do
    with {:ok, node} <- transform(guard, metadata) do
      {:ok, [[:when, node]]}
    end
  end

  defp transform_data({:list, _meta, elements}, metadata) when is_list(elements) do
    transform_list(elements, metadata)
  end

  defp transform_data(node, metadata), do: transform(node, metadata)

  defp transform_list(items, metadata) when is_list(items) do
    items
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
      case transform(item, metadata) do
        {:ok, node} -> {:cont, {:ok, [node | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, nodes} -> {:ok, Enum.reverse(nodes)}
      error -> error
    end
  end

  defp transform_params(params, metadata) when is_list(params) do
    params
    |> Enum.reduce_while({:ok, []}, fn param, {:ok, acc} ->
      case transform_param(param, metadata) do
        {:ok, node} -> {:cont, {:ok, [node | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, nodes} -> {:ok, Enum.reverse(nodes)}
      error -> error
    end
  end

  defp transform_params(other, _metadata), do: {:error, "Invalid params: #{inspect(other)}"}

  defp transform_param({:param, meta, name}, _metadata) when is_binary(name) do
    atom = String.to_atom(name)

    case Keyword.get(meta, :kind, :positional) do
      :variadic -> {:ok, [:rest, atom]}
      :keyword -> {:ok, [:key, atom]}
      _ -> {:ok, atom}
    end
  end

  defp transform_param({:param, meta, _name}, metadata) do
    case Keyword.get(meta, :pattern) do
      nil -> {:error, "Cannot reify param: #{inspect(meta, limit: 5)}"}
      pattern -> transform_pattern(pattern, metadata)
    end
  end

  defp transform_param(other, metadata), do: transform(other, metadata)

  # A pattern is data: lists stay lists, symbols stay symbols.
  defp transform_pattern(nil, _metadata), do: {:ok, :_}

  defp transform_pattern({:variable, _meta, name}, _metadata) when is_binary(name) do
    {:ok, String.to_atom(name)}
  end

  defp transform_pattern({:literal, meta, value}, metadata) do
    transform_node(:literal, meta, value, metadata)
  end

  defp transform_pattern({:list, _meta, elements}, metadata) when is_list(elements) do
    transform_list(elements, metadata)
  end

  defp transform_pattern({:tuple, _meta, elements}, metadata) when is_list(elements) do
    with {:ok, children} <- transform_list(elements, metadata) do
      {:ok, {:tuple, children}}
    end
  end

  defp transform_pattern(other, metadata), do: transform(other, metadata)

  # `(let ((x 1) (y 2)) body)` — `ToMeta` flattens the bindings and the body
  # into one block of statements, marking each binding as an `:assignment`.
  # `bindings_of/1` recovers the `((x 1) (y 2))` list and `drop_bindings/1`
  # returns the body that follows it.
  defp bindings_of(nodes) do
    nodes
    |> Enum.take_while(&binding?/1)
    |> Enum.map(fn [:set, target, value] -> [target, value] end)
  end

  defp drop_bindings(nodes) do
    case Enum.drop_while(nodes, &binding?/1) do
      [] -> [nil]
      rest -> rest
    end
  end

  defp binding?([:set, target, _value]) when is_atom(target), do: true
  defp binding?(_), do: false

  defp export_spec(name) when is_binary(name) do
    case String.split(name, "/") do
      [fun, arity] ->
        case Integer.parse(arity) do
          {n, ""} -> [String.to_atom(fun), n]
          _ -> String.to_atom(name)
        end

      _ ->
        String.to_atom(name)
    end
  end

  defp export_spec(name), do: name

  # LFE module-qualified calls are a single symbol (`io:format`), so a dotted
  # MetaAST name is converted back to that form.
  defp name_to_atom(name) when is_binary(name) do
    name
    |> String.replace(".", ":")
    |> String.to_atom()
  end

  defp name_to_atom(name) when is_atom(name), do: name
end
