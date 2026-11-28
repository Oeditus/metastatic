defmodule Metastatic.Adapters.Lfe.ToMeta do
  @moduledoc """
  Transform LFE sexprs (M1) to MetaAST (M2).

  ## The M1 shape

  LFE's reader produces plain Erlang terms, so M1 is the sexpr itself:

      42                      # integer literal
      "text"                  # binary (string) literal
      :atom                   # symbol
      :x                      # a variable, lexically identical to a symbol
      [1, 2, 3]               # a list
      [:f, :a, :b]            # the call (f a b)
      {:tuple, [1, 2]}        # the tuple #(1 2)
      [:quote, :x]            # '(quote x)

  ## The call-versus-data rule

  This is the one genuinely hard part of abstracting LFE, because a Lisp
  reader erases the distinction: `(f a b)` and a three-element list are both
  Erlang lists. Every transform therefore carries an explicit **context**:

    * `:expr` — the term sits in operator/head position, so a non-empty list
      whose head is a symbol is a **function call**;
    * `:data` — the term is list *content* (an argument, a list element, a
      quoted body), so a list is a **data list** and its elements are
      transformed in `:expr` position.

  `[:list, 1, 2]` in `:expr` context is the call `(list 1 2)`; `[1, 2]` in
  `:data` context is the list `[1, 2]`. The same rule makes
  `[:quote, [:a, :b]]` a quoted *data* list rather than a call to `a`.

  ## Mapping

  ### M2.1 Core

  | LFE (M1) | MetaAST (M2) |
  | :--- | :--- |
  | integer / float / binary | `{:literal, [subtype: ...], value}` |
  | `:true` / `:false` | `{:literal, [subtype: :boolean], bool}` |
  | `:nil` / `:undefined` | `{:literal, [subtype: :null], nil}` |
  | other atom | `{:literal, [subtype: :symbol], atom}` |
  | variable | `{:variable, [scope: :local], "name"}` |
  | `(+ a b)`, `(== a b)`, `(and a b)` | `{:binary_op, [category:, operator:], [l, r]}` |
  | `(- a)`, `(not a)` | `{:unary_op, [category:, operator:], [a]}` |
  | `(f a b)` | `{:function_call, [name: "f"], [a, b]}` |
  | `(io:format …)` | `{:function_call, [name: "io:format"], …}` |
  | `(list 1 2)` | `{:list, [], [1, 2]}` |
  | `#(1 2)` | `{:tuple, [], [1, 2]}` |
  | `(if c t e)` | `{:conditional, [kind: :if], [c, t, e]}` |
  | `(let ((x 1)) body)` | `{:block, [scope: :let], [assignment, …]}` |
  | `(case x …)` | `{:pattern_match, [], [x, arms…]}` |
  | `(lambda (x) body)` | `{:lambda, [params: …], body}` |
  | `(try …)` | `{:exception_handling, [kind: :try], …}` |
  | `(lc (… ) (…))` | `{:comprehension, [], …}` |

  ### M2.2s Structural

  | LFE | MetaAST |
  | :--- | :--- |
  | `(defmodule name …)` | `{:container, [container_type: :module, name: …], body}` |
  | `(defun name (args) body)` | `{:function_def, [name:, params:, arity:], body}` |
  | `(defmacro name (args) body)` | `{:macro_def, [name: …], body}` |
  | `(export (f 1))` | metadata `exports:` on the enclosing container |
  | `(include-file "x.lfe")` | `{:import, [source:, import_type: :include], []}` |

  ### M2.3 Native

  Anything else — `receive`, `quote` of a non-trivial form, records,
  structs, binaries, `catch`, `after` — becomes
  `{:language_specific, [language: :lfe, hint: …], original_sexpr}`,
  preserving the sexpr verbatim so `FromMeta` can restore it exactly.

  ## Metadata

  Every node carries `line:` from the reader. `:language_specific` nodes
  additionally carry the original sexpr, which is what makes the escape
  hatch lossless.
  """

  alias Metastatic.AST

  @arithmetic_ops [:+, :-, :*, :/, :div, :rem]
  @comparison_ops [:==, :"/=", :<, :>, :"=<", :>=, :"=:=", :"=/="]
  @boolean_ops [:and, :or, :andalso, :orelse]
  @bitwise_ops [:band, :bor, :bxor, :bsl, :bsr, :bnot]
  @unary_ops [:-, :+, :not, :bnot]

  @doc """
  Transforms the reader's output into a module-level `:block`.

  ## Examples

      iex> {:ok, meta, _} = Metastatic.Adapters.Lfe.ToMeta.transform([{[:defun, :add, [:a, :b], [:"+", :a, :b]], 1}])
      iex> elem(meta, 0)
      :block
  """
  @spec transform([{term(), integer()}] | term()) :: {:ok, term(), map()} | {:error, String.t()}
  def transform([{sexpr, line}]) do
    with {:ok, node} <- transform(sexpr, line, :expr) do
      {:ok, node, %{language: :lfe}}
    end
  end

  def transform([{_sexpr, _line} | _] = forms) do
    {:ok, statements} = transform_forms(forms)
    {:ok, {:block, [scope: :module], statements}, %{language: :lfe}}
  end

  # A bare sexpr (single expression) is still accepted.
  def transform(sexpr) do
    with {:ok, node} <- transform(sexpr, 1, :expr) do
      {:ok, node, %{language: :lfe}}
    end
  end

  @doc """
  Transforms one sexpr in an explicit context.

  `context` is `:expr` (operator position: lists are calls) or `:data`
  (list content: lists are data).

  ## Examples

      iex> {:ok, node} = Metastatic.Adapters.Lfe.ToMeta.transform([:f, 1], 1, :expr)
      iex> elem(node, 0)
      :function_call

      iex> {:ok, node} = Metastatic.Adapters.Lfe.ToMeta.transform([1, 2], 1, :data)
      iex> elem(node, 0)
      :list
  """
  @spec transform(term(), integer(), :expr | :data) :: {:ok, term()} | {:error, String.t()}
  def transform(sexpr, line, context \\ :expr)

  # ----- Literals -----

  def transform(value, line, _context) when is_integer(value) do
    {:ok, {:literal, [subtype: :integer, line: line], value}}
  end

  def transform(value, line, _context) when is_float(value) do
    {:ok, {:literal, [subtype: :float, line: line], value}}
  end

  def transform(value, line, _context) when is_binary(value) do
    {:ok, {:literal, [subtype: :string, line: line], value}}
  end

  # LFE's reader returns string literals as **charlists**, not binaries
  # (`"~p~n"` arrives as `[126, 112, 126, 110]`). A printable charlist is
  # therefore a string literal, not a data list.
  #
  # This clause must come *after* the call clause below: `[head | args]` with
  # an atom head is a call, and a call whose head happens to be a printable
  # charlist cannot occur (a charlist head is not an atom). Ordering it first
  # would swallow every call.
  def transform(true, line, _context) do
    {:ok, {:literal, [subtype: :boolean, line: line], true}}
  end

  def transform(false, line, _context) do
    {:ok, {:literal, [subtype: :boolean, line: line], false}}
  end

  # `nil` and `undefined` are both LFE's "absent" value.
  def transform(nil, line, _context) do
    {:ok, {:literal, [subtype: :null, line: line], nil}}
  end

  def transform(:undefined, line, _context) do
    {:ok, {:literal, [subtype: :null, line: line], nil}}
  end

  # A bare symbol is a variable reference. LFE is a Lisp-2, but at the sexpr
  # level a symbol in expression position always denotes the *value*
  # namespace, so `:variable` is the right abstraction; call heads are handled
  # by `transform_call/4` before reaching here.
  def transform(name, line, :expr) when is_atom(name) do
    {:ok, {:variable, [scope: :local, line: line], Atom.to_string(name)}}
  end

  # In data position an atom is a symbol literal (`'(a b)`).
  def transform(name, line, :data) when is_atom(name) do
    {:ok, {:literal, [subtype: :symbol, line: line], name}}
  end

  # ----- Tuples: `#(1 2)` — the reader produces a 2-tuple `{:tuple, elems}` -----

  def transform({:tuple, elements}, line, _context) when is_list(elements) do
    with {:ok, children} <- transform_list(elements, line, :data) do
      {:ok, {:tuple, [line: line], children}}
    end
  end

  # ----- Lists: the call-versus-data decision -----

  def transform([], line, _context) do
    {:ok, {:list, [line: line], []}}
  end

  def transform([head | args] = sexpr, line, :expr) when is_atom(head) do
    transform_call(head, args, sexpr, line)
  end

  # A list in data position is data, whatever its head is.
  def transform(list, line, :data) when is_list(list) do
    with {:ok, children} <- transform_list(list, line, :expr) do
      {:ok, {:list, [line: line], children}}
    end
  end

  # A list whose head is not a symbol cannot be a call. A printable charlist
  # is LFE's string literal; any other list is data.
  def transform(list, line, :expr) when is_list(list) do
    if charlist?(list) do
      {:ok, {:literal, [subtype: :string, line: line], List.to_string(list)}}
    else
      transform_list_sexpr(list, line, :expr)
    end
  end

  # ----- Anything else is preserved verbatim -----

  def transform(other, line, _context) do
    {:ok, native(other, line, :unknown)}
  end

  # A non-printable list is a data list. Shared by the charlist clause and the
  # expression-position list clause.
  defp transform_list_sexpr(list, line, context) do
    with {:ok, children} <- transform_list(list, line, context) do
      {:ok, {:list, [line: line], children}}
    end
  end

  # `true` when `list` is a printable charlist — LFE's representation of a
  # string literal. An empty list is a list, not an empty string, and a
  # charlist whose head is an atom is a call (handled before this point).
  defp charlist?(list), do: List.ascii_printable?(list)

  # ----- Calls -----
  # `(quote x)` / `'x` — the quoted payload is data, never a call.
  defp transform_call(:quote, [payload], _sexpr, line) do
    with {:ok, inner} <- transform(payload, line, :data) do
      {:ok, {:language_specific, [language: :lfe, hint: :quote, line: line], [inner]}}
    end
  end

  defp transform_call(:quote, _args, sexpr, line), do: {:ok, native(sexpr, line, :quote)}

  # Arithmetic / comparison / boolean / bitwise binary operators.
  defp transform_call(op, [left, right], _sexpr, line)
       when op in @arithmetic_ops or op in @comparison_ops or op in @boolean_ops or
              op in @bitwise_ops do
    with {:ok, l} <- transform(left, line, :expr),
         {:ok, r} <- transform(right, line, :expr) do
      meta = [category: operator_category(op), operator: op, line: line]
      {:ok, {:binary_op, meta, [l, r]}}
    end
  end

  # `(- a)` / `(not a)` — unary operators.
  defp transform_call(op, [operand], _sexpr, line) when op in @unary_ops do
    with {:ok, inner} <- transform(operand, line, :expr) do
      meta = [category: operator_category(op), operator: op, line: line]
      {:ok, {:unary_op, meta, [inner]}}
    end
  end

  # `(list 1 2)` — an explicit list constructor is a data list.
  defp transform_call(:list, elements, _sexpr, line) do
    with {:ok, children} <- transform_list(elements, line, :expr) do
      {:ok, {:list, [line: line], children}}
    end
  end

  # `(if c t e)` / `(if c t)`.
  defp transform_call(:if, [condition, then_branch], _sexpr, line) do
    with {:ok, c} <- transform(condition, line, :expr),
         {:ok, t} <- transform(then_branch, line, :expr) do
      {:ok, {:conditional, [kind: :if, line: line], [c, t, nil]}}
    end
  end

  defp transform_call(:if, [condition, then_branch, else_branch], _sexpr, line) do
    with {:ok, c} <- transform(condition, line, :expr),
         {:ok, t} <- transform(then_branch, line, :expr),
         {:ok, e} <- transform(else_branch, line, :expr) do
      {:ok, {:conditional, [kind: :if, line: line], [c, t, e]}}
    end
  end

  # `(case x ((pat) body) …)` — pattern matching.
  defp transform_call(:case, [subject | clauses], _sexpr, line) do
    with {:ok, scrutinee} <- transform(subject, line, :expr),
         {:ok, arms} <- transform_arms(clauses, line) do
      {:ok, {:pattern_match, [line: line], [scrutinee | arms]}}
    end
  end

  # `(let ((x 1) (y 2)) body…)` — a block of bindings followed by a body.
  defp transform_call(kind, [bindings, body], _sexpr, line) when kind in [:let, :"let*"] do
    with {:ok, assignments} <- transform_bindings(bindings, line),
         {:ok, body_nodes} <- transform_body(body, line) do
      {:ok, {:block, [scope: kind, line: line], assignments ++ body_nodes}}
    end
  end

  # `(lambda (x y) body…)` and `(match-lambda ((pat) body) …)`.
  # `(lambda (x y) body…)`. LFE's reader already gives the body as a bare
  # sexpr (`[:lambda, [:x], [:*, :x, 2]]`), so no unwrapping is needed.
  defp transform_call(:lambda, [params, body], _sexpr, line) do
    with {:ok, param_nodes} <- transform_params(params, line),
         {:ok, body_nodes} <- transform_body(body, line) do
      {:ok, {:lambda, [params: param_nodes, line: line], body_nodes}}
    end
  end

  defp transform_call(:lambda, _args, sexpr, line), do: {:ok, native(sexpr, line, :lambda)}

  # `(defun name (args) body…)`.
  defp transform_call(:defun, [name, params | body], _sexpr, line) when is_atom(name) do
    with {:ok, param_nodes} <- transform_params(params, line),
         {:ok, body_nodes} <- transform_body(body, line) do
      meta = [
        name: Atom.to_string(name),
        params: param_nodes,
        arity: length(param_nodes),
        visibility: :public,
        line: line
      ]

      {:ok, {:function_def, meta, body_nodes}}
    end
  end

  defp transform_call(:defun, _args, sexpr, line), do: {:ok, native(sexpr, line, :defun)}

  # `(defmacro name (args) body…)`.
  defp transform_call(:defmacro, [name, params | body], _sexpr, line) when is_atom(name) do
    with {:ok, param_nodes} <- transform_params(params, line),
         {:ok, body_nodes} <- transform_body(body, line) do
      meta = [name: Atom.to_string(name), params: param_nodes, line: line]
      {:ok, {:macro_def, meta, body_nodes}}
    end
  end

  defp transform_call(:defmacro, _args, sexpr, line), do: {:ok, native(sexpr, line, :defmacro)}

  # `(defmodule name (export …))` — the module container.
  #
  # In LFE the `export` form is a **sibling** of `defmodule`, not a child of
  # it, so the container body is only the module's own arguments. The
  # `export` form is picked up separately by `transform_forms/1`, which
  # attaches it to the most recent container as `exports:` metadata.
  defp transform_call(:defmodule, [name | body], _sexpr, line) when is_atom(name) do
    with {:ok, body_nodes} <- transform_body(body, line) do
      meta = [container_type: :module, name: Atom.to_string(name), language: :lfe, line: line]
      {:ok, {:container, meta, body_nodes}}
    end
  end

  defp transform_call(:defmodule, _args, sexpr, line), do: {:ok, native(sexpr, line, :defmodule)}

  # `(export (f 1) (g 2))` — a module-level declaration. It is represented as
  # an `:import` node so analyzers see the module's public surface; the
  # enclosing container also records the same list as `exports:` metadata.
  defp transform_call(:export, specs, _sexpr, line) do
    names = Enum.flat_map(specs, &export_name/1)
    {:ok, {:import, [source: "export", import_type: :export, names: names, line: line], []}}
  end

  # `(include-file "x.lfe")` / `(include-lib "x/include/y.lfe")`.
  defp transform_call(kind, [path], _sexpr, line)
       when kind in [:"include-file", :"include-lib"] do
    source = if is_binary(path), do: path, else: inspect(path)
    {:ok, {:import, [source: source, import_type: :include, line: line], []}}
  end

  # `(try body (catch …) (after …))`.
  #
  # LFE's `try` carries its handlers as *forms* (`(catch …)`, `(after …)`),
  # not as the `(pattern body)` clause list `:exception_handling` expects, so
  # modelling it would mean inventing a shape the meta-model does not have and
  # would fail conformance. It is therefore preserved verbatim as
  # `:language_specific`, which round-trips exactly.
  defp transform_call(:try, _args, sexpr, line) do
    {:ok, native(sexpr, line, :try)}
  end

  # `(lc (expr) (gen pat list) …)` / `(bc …)` — list and binary comprehensions.
  #
  # LFE's reader wraps the comprehension body in a one-element list, so
  # `(lc ((* x 2)) …)` arrives as `[:lc, [[:*, :x, 2]], …]`. The body is an
  # expression, not a data list, so the single element is unwrapped before
  # abstraction.
  defp transform_call(kind, [body | qualifiers], _sexpr, line) when kind in [:lc, :bc] do
    with {:ok, body_node} <- transform(comprehension_body(body), line, :expr),
         {:ok, quals} <- transform_qualifiers(qualifiers, line) do
      {:ok, {:comprehension, [kind: kind, line: line], [body_node | quals]}}
    end
  end

  # Erlang interop and ordinary calls: `(io:format "~p" x)`, `(f a b)`.
  defp transform_call(name, args, _sexpr, line) when is_atom(name) do
    with {:ok, arg_nodes} <- transform_list(args, line, :expr) do
      {:ok, {:function_call, [name: Atom.to_string(name), line: line], arg_nodes}}
    end
  end

  # ----- Helpers -----

  defp comprehension_body([single]), do: single
  defp comprehension_body(other), do: other

  defp transform_forms(forms) do
    forms
    |> Enum.reduce_while({:ok, []}, fn {sexpr, line}, {:ok, acc} ->
      case transform(sexpr, line, :expr) do
        {:ok, node} -> {:cont, {:ok, [node | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, nodes} -> {:ok, attach_exports(Enum.reverse(nodes))}
      error -> error
    end
  end

  # In LFE `(export …)` is a sibling of the `defmodule` it belongs to, so the
  # export list has to be attached to the preceding container after the flat
  # walk. The `:import` node is then dropped: the information now lives on the
  # container as `exports:` metadata, and keeping both would duplicate it.
  # An `export` with no preceding container is left standalone rather than
  # being silently discarded.
  defp attach_exports(nodes), do: attach_exports(nodes, [])

  defp attach_exports([], acc), do: Enum.reverse(acc)

  defp attach_exports([{:import, meta, []} = node | rest], acc) do
    if Keyword.get(meta, :import_type) == :export do
      case acc do
        [{:container, c_meta, body} | acc_rest] ->
          names = Keyword.get(meta, :names, [])
          container = {:container, Keyword.put(c_meta, :exports, names), body}
          attach_exports(rest, [container | acc_rest])

        _ ->
          attach_exports(rest, [node | acc])
      end
    else
      attach_exports(rest, [node | acc])
    end
  end

  defp attach_exports([node | rest], acc), do: attach_exports(rest, [node | acc])

  defp transform_list(items, line, context) when is_list(items) do
    items
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
      case transform(item, line, context) do
        {:ok, node} -> {:cont, {:ok, [node | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, nodes} -> {:ok, Enum.reverse(nodes)}
      error -> error
    end
  end

  # A body is a single expression or a sequence of expressions.
  #
  # The distinction is the same call-versus-data rule the rest of the module
  # uses: a list whose head is a symbol is **one** expression (a call), while a
  # list of lists is a sequence of forms. Without this, `(lambda (x) (* x 2))`
  # was read as three body expressions (`*`, `x`, `2`).
  defp transform_body([], _line), do: {:ok, []}

  defp transform_body([head | _] = body, line) when is_atom(head) do
    with {:ok, node} <- transform(body, line, :expr), do: {:ok, [node]}
  end

  defp transform_body([_ | _] = body, line), do: transform_list(body, line, :expr)

  defp transform_body(body, line) do
    with {:ok, node} <- transform(body, line, :expr), do: {:ok, [node]}
  end

  # `((x 1) (y 2))` — a let binding list.
  defp transform_bindings(bindings, line) when is_list(bindings) do
    bindings
    |> Enum.reduce_while({:ok, []}, fn
      [name, value], {:ok, acc} when is_atom(name) ->
        with {:ok, target} <- transform(name, line, :expr),
             {:ok, expr} <- transform(value, line, :expr) do
          {:cont, {:ok, [{:assignment, [line: line], [target, expr]} | acc]}}
        else
          error -> {:halt, error}
        end

      other, {:ok, acc} ->
        case transform(other, line, :expr) do
          {:ok, node} -> {:cont, {:ok, [node | acc]}}
          error -> {:halt, error}
        end
    end)
    |> case do
      {:ok, nodes} -> {:ok, Enum.reverse(nodes)}
      error -> error
    end
  end

  defp transform_bindings(other, line), do: transform(other, line, :expr)

  # `((pat) body)` / `((pat) (when guard) body)` — case arms.
  #
  # The pattern is always wrapped in a one-element list by LFE's reader, so
  # `((0) …)` carries the pattern `0`, not the data list `[0]`. A leading
  # `(when guard)` is the arm guard, not a call.
  #
  # `:pattern` carries no `line:`: `AST.canonicalize/1` keeps it as a semantic
  # metadata key but does not recurse into it, so a location there would make
  # two otherwise identical arms compare unequal after a round-trip.
  defp transform_arms(clauses, line) when is_list(clauses) do
    clauses
    |> Enum.reduce_while({:ok, []}, fn
      [pattern | body], {:ok, acc} ->
        with {:ok, pattern_node} <- transform(pattern, line, :data),
             {:ok, guard, body} <- split_guard(body, line),
             {:ok, body_nodes} <- transform_body(body, line) do
          meta = [pattern: strip_line(pattern_node)] ++ if(guard, do: [guard: guard], else: [])
          arm = {:match_arm, meta, body_nodes}
          {:cont, {:ok, [arm | acc]}}
        else
          error -> {:halt, error}
        end

      other, {:ok, acc} ->
        case transform(other, line, :expr) do
          {:ok, node} -> {:cont, {:ok, [node | acc]}}
          error -> {:halt, error}
        end
    end)
    |> case do
      {:ok, nodes} -> {:ok, Enum.reverse(nodes)}
      error -> error
    end
  end

  defp transform_arms(other, line), do: transform(other, line, :expr)

  # Removes `line:` from a node and, recursively, from its children.
  defp strip_line({type, meta, children}) when is_atom(type) and is_list(meta) do
    {type, Keyword.delete(meta, :line), strip_line(children)}
  end

  defp strip_line(list) when is_list(list), do: Enum.map(list, &strip_line/1)
  defp strip_line(other), do: other
  # `((when guard) body…)` — the guard is the first body element.
  defp split_guard([[:when, guard] | rest], line) do
    with {:ok, guard_node} <- transform(guard, line, :expr) do
      {:ok, guard_node, rest}
    end
  end

  defp split_guard(body, _line), do: {:ok, nil, body}

  # `(gen pat list)` / `(gen-server …)` — comprehension qualifiers.
  defp transform_qualifiers(qualifiers, line) when is_list(qualifiers) do
    qualifiers
    |> Enum.reduce_while({:ok, []}, fn
      [:gen, pattern, collection], {:ok, acc} ->
        with {:ok, pattern_node} <- transform(pattern, line, :data),
             {:ok, coll_node} <- transform(collection, line, :expr) do
          {:cont, {:ok, [{:generator, [line: line], [pattern_node, coll_node]} | acc]}}
        else
          error -> {:halt, error}
        end

      other, {:ok, acc} ->
        case transform(other, line, :expr) do
          {:ok, node} -> {:cont, {:ok, [node | acc]}}
          error -> {:halt, error}
        end
    end)
    |> case do
      {:ok, nodes} -> {:ok, Enum.reverse(nodes)}
      error -> error
    end
  end

  defp transform_qualifiers(other, line), do: transform(other, line, :expr)

  # `(x y)` — a parameter list.
  defp transform_params(params, line) when is_list(params) do
    params
    |> Enum.reduce_while({:ok, []}, fn param, {:ok, acc} ->
      case transform_param(param, line) do
        {:ok, node} -> {:cont, {:ok, [node | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, nodes} -> {:ok, Enum.reverse(nodes)}
      error -> error
    end
  end

  defp transform_params(other, line), do: transform(other, line, :expr)

  # Parameters are structural, not located: `:param` nodes deliberately carry
  # no `line:`. `AST.canonicalize/1` keeps `:params` as a semantic metadata key
  # but does not recurse into it, so a `line:` on a param would make two
  # otherwise identical functions compare unequal after a round-trip.
  defp transform_param(name, _line) when is_atom(name) do
    {:ok, {:param, [], Atom.to_string(name)}}
  end

  # `(optional x)` / `(rest xs)` / `(key val)` — LFE's extended parameter forms.
  defp transform_param([kind, name], _line) when is_atom(kind) and is_atom(name) do
    param_kind =
      case kind do
        :rest -> :variadic
        :key -> :keyword
        _ -> :positional
      end

    {:ok, {:param, [kind: param_kind], Atom.to_string(name)}}
  end

  defp transform_param(other, line) do
    with {:ok, node} <- transform(other, line, :data) do
      {:ok, {:param, [pattern: node], "_"}}
    end
  end

  defp export_name([name, arity]) when is_atom(name) and is_integer(arity),
    do: ["#{name}/#{arity}"]

  defp export_name(name) when is_atom(name), do: [Atom.to_string(name)]
  defp export_name(_), do: []

  defp operator_category(op) when op in @arithmetic_ops, do: :arithmetic
  defp operator_category(op) when op in @comparison_ops, do: :comparison
  defp operator_category(op) when op in @boolean_ops, do: :boolean
  defp operator_category(op) when op in @bitwise_ops, do: :bitwise
  defp operator_category(_), do: :arithmetic

  # Preserved verbatim for `FromMeta` to restore.
  defp native(sexpr, line, hint) do
    {:language_specific, [language: :lfe, hint: hint, line: line], sexpr}
  end

  # Referenced so the alias is not flagged as unused when the mapping grows.
  @doc false
  def __ast__, do: AST
end
