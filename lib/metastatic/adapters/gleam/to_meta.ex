defmodule Metastatic.Adapters.Gleam.ToMeta do
  @moduledoc """
  Abstracts the Gleam bridge's tagged M1 JSON into MetaAST.

  ## The M1 shape

  Every node is a map with a `kind` discriminator, a `span`, and kind-specific
  fields (`name`, `value`, `children`, `type_node`, `pattern`, `extra`). See
  `Metastatic.Adapters.Gleam` for the full shape and
  `priv/parsers/gleam/src/ast.rs` for the Rust definition.

  ## Coverage

  Every `kind` the bridge emits is matched. There is no catch-all that turns an
  unknown node into `:language_specific` silently — an unrecognised `kind`
  raises a `FunctionClauseError` that `transform/1` converts into a clear
  `{:error, reason}`. That is deliberate: a *silent* fallback would hide a
  bridge/adapter version skew, which is exactly the failure this adapter's
  design is meant to make loud.

  Constructs that *are* modelled but have no portable MetaAST analogue —
  clause guards, record updates, string-prefix patterns, `echo` — become
  `:language_specific` nodes carrying the M1 payload, so `FromMeta` can restore
  them exactly.

  ## Metadata

  Every node carries `line:` and `col:` from the bridge's span. Anything MetaAST
  cannot hold but reification needs is kept in a `gleam_`-prefixed key:

    * `gleam_kind:` — the original M1 `kind`, where the M2 node type alone is
      ambiguous (`TypeAlias` vs `TypeConstructor`, `Todo` vs `Panic`);
    * `gleam_operator:` — the `BinOp` variant, because `LtInt` and `LtFloat`
      both print as a comparison but are different operators;
    * `gleam_literal:` — a numeric literal's source spelling, when the value
      does not round-trip through Elixir's integer/float types (a bignum, a
      trailing zero).

  Everything else is expressed with MetaAST's own vocabulary, so an analyzer
  never has to know Gleam to understand a Gleam tree.
  """

  import Kernel, except: [node: 1]

  alias Metastatic.AST

  @binary_operators %{
    "AddInt" => {:arithmetic, :+},
    "AddFloat" => {:arithmetic, :+},
    "SubInt" => {:arithmetic, :-},
    "SubFloat" => {:arithmetic, :-},
    "MultInt" => {:arithmetic, :*},
    "MultFloat" => {:arithmetic, :*},
    "DivInt" => {:arithmetic, :/},
    "DivFloat" => {:arithmetic, :/},
    "RemainderInt" => {:arithmetic, :rem},
    "Eq" => {:comparison, :==},
    "NotEq" => {:comparison, :!=},
    "LtInt" => {:comparison, :<},
    "LtFloat" => {:comparison, :<},
    "LtEqInt" => {:comparison, :<=},
    "LtEqFloat" => {:comparison, :<=},
    "GtInt" => {:comparison, :>},
    "GtFloat" => {:comparison, :>},
    "GtEqInt" => {:comparison, :>=},
    "GtEqFloat" => {:comparison, :>=},
    "And" => {:boolean, :and},
    "Or" => {:boolean, :or},
    "Concatenate" => {:string, :<>}
  }

  @doc """
  Transforms the bridge's M1 module into a module-level `:block`.

  ## Examples

      iex> {:ok, ast} = Metastatic.Adapters.Gleam.Subprocess.parse("pub fn main() { 1 }")
      iex> {:ok, {:block, meta, [_]}, _} = Metastatic.Adapters.Gleam.ToMeta.transform(ast)
      iex> Keyword.get(meta, :scope)
      :module
  """
  @spec transform(map()) :: {:ok, AST.meta_ast(), map()} | {:error, String.t()}
  def transform(%{"kind" => "Module"} = module) do
    statements =
      module
      |> Map.get("children", [])
      |> Enum.map(&convert/1)

    comments =
      module
      |> Map.get("comments", [])
      |> Enum.map(fn text ->
        {:comment, [comment_kind: :doc, language: :gleam], text}
      end)

    meta =
      [scope: :module, language: :gleam] ++
        location(module) ++
        if(comments == [], do: [], else: [module_comments: comments])

    {:ok, {:block, meta, statements}, %{language: :gleam}}
  rescue
    error in [FunctionClauseError, KeyError, MatchError, ArgumentError] ->
      {:error, "Invalid Gleam AST: #{Exception.message(error)}"}
  catch
    {:gleam_transform, reason} -> {:error, reason}
  end

  def transform(other) do
    {:error, "Expected a Gleam module node, got: #{inspect(other, limit: 5)}"}
  end

  @doc """
  Transforms one M1 node into MetaAST.

  Exposed so tests and analyzers can abstract a single node without wrapping it
  in a module.

  ## Examples

      iex> {:ok, {:literal, meta, 42}} =
      ...>   Metastatic.Adapters.Gleam.ToMeta.node(%{"kind" => "Int", "value" => %{"subtype" => "integer", "value" => "42"}})
      iex> Keyword.get(meta, :subtype)
      :integer
  """
  @spec node(map()) :: {:ok, AST.meta_ast()} | {:error, String.t()}
  def node(%{"kind" => _} = m1) do
    {:ok, convert(m1)}
  rescue
    error in [FunctionClauseError, KeyError, MatchError, ArgumentError] ->
      {:error, "Invalid Gleam AST: #{Exception.message(error)}"}
  catch
    {:gleam_transform, reason} -> {:error, reason}
  end

  def node(other), do: {:error, "Expected a tagged Gleam node, got: #{inspect(other, limit: 5)}"}

  # ── Definitions ────────────────────────────────────────────────────

  defp convert(%{"kind" => "Import"} = node) do
    # `gleam format` sorts an import's unqualified list, so the M2 names are
    # sorted too: otherwise re-parsing formatted output would produce a
    # different (but semantically identical) tree.
    #
    # `type X` keeps its `type ` prefix — it distinguishes a type import from a
    # value import of the same name, and dropping it made `type Option` come
    # back as a value import.
    extra = Map.get(node, "extra", %{})

    names =
      (Enum.map(Map.get(extra, "values", []), &import_name/1) ++
         Enum.map(Map.get(extra, "types", []), &("type " <> import_name(&1))))
      |> Enum.sort()

    meta =
      [
        source: node["name"],
        import_type: :module,
        names: names,
        alias: get_in(node, ["extra", "as_name"])
      ]
      |> compact()
      |> Kernel.++(location(node))

    {:import, meta, []}
  end

  defp convert(%{"kind" => "Fn"} = node) do
    children = Map.get(node, "children", [])
    {params, body} = Enum.split_with(children, &(&1["kind"] == "Arg"))

    meta =
      [
        name: node["name"],
        params: Enum.map(params, &convert/1),
        arity: length(params),
        visibility: visibility(node),
        language: :gleam,
        gleam_kind: "Fn"
      ]
      |> compact()
      |> Kernel.++(location(node))
      |> Kernel.++(optional(:return_type, type_name(node["type_node"])))
      |> Kernel.++(optional(:documentation, get_in(node, ["extra", "documentation"])))
      |> Kernel.++(optional(:deprecated, get_in(node, ["extra", "deprecated"])))
      |> Kernel.++(optional(:target, get_in(node, ["extra", "target"])))
      |> Kernel.++(external_meta(node))

    {:function_def, meta, Enum.map(body, &convert/1)}
  end

  defp convert(%{"kind" => "TypeAlias"} = node) do
    # `AST` requires `annotation_type:` from `[:spec, :type, :hint, :callback]`;
    # a type alias declaration is a `:type`.
    {:type_annotation,
     [
       annotation_type: :type,
       name: node["name"],
       visibility: visibility(node),
       language: :gleam,
       gleam_kind: "TypeAlias",
       parameters: get_in(node, ["extra", "parameters"]) || []
     ]
     |> then(
       &(&1 ++ location(node) ++ optional(:type, node["type_node"] && convert(node["type_node"])))
     ), []}
  end

  defp convert(%{"kind" => "CustomType"} = node) do
    meta =
      [
        # A Gleam custom type is a tagged union: `:enum` is the closest
        # portable container kind, and its constructors are `:struct`-like
        # variants. `AST`'s `@container_types` does not include `:variant`, so
        # using it would make every custom type non-conforming.
        container_type: :enum,
        name: node["name"],
        visibility: visibility(node),
        opaque: Map.get(node, "opaque", false),
        language: :gleam,
        gleam_kind: "CustomType",
        parameters: get_in(node, ["extra", "parameters"]) || []
      ]
      |> then(
        &(&1 ++
            location(node) ++ optional(:documentation, get_in(node, ["extra", "documentation"])))
      )

    {:container, meta, Enum.map(Map.get(node, "children", []), &convert/1)}
  end

  defp convert(%{"kind" => "RecordConstructor"} = node) do
    {:container,
     [
       container_type: :struct,
       name: node["name"],
       language: :gleam,
       gleam_kind: "RecordConstructor"
     ]
     |> compact()
     |> Kernel.++(location(node))
     |> Kernel.++(optional(:documentation, get_in(node, ["extra", "documentation"]))),
     Enum.map(Map.get(node, "children", []), &convert/1)}
  end

  defp convert(%{"kind" => "RecordConstructorArg"} = node) do
    # `:param`'s third element is the parameter's *name*, not a child list —
    # `AST.conforms?/1` requires a binary or atom there. The type annotation
    # lives in the metadata.
    # The type is a plain string in `:type`, matching the Rust adapter: the
    # Elixir reifier (and, by extension, cross-language translation) does not
    # understand a `:type_annotation` node in a parameter slot, so a Gleam
    # function with typed parameters could not be translated at all.
    meta =
      [
        kind: :positional,
        field: true,
        label: get_in(node, ["extra", "label"]),
        type: type_name(node["type_node"]),
        language: :gleam,
        gleam_kind: "RecordConstructorArg"
      ]
      |> compact()
      |> Kernel.++(location(node))

    {:param, meta, get_in(node, ["extra", "label"]) || "_"}
  end

  defp convert(%{"kind" => "ModuleConstant"} = node) do
    {:assignment,
     [
       binding: :constant,
       name: node["name"],
       visibility: visibility(node),
       language: :gleam,
       gleam_kind: "ModuleConstant"
     ]
     |> then(&(&1 ++ location(node))),
     [
       {:variable, [scope: :module, language: :gleam], node["name"]},
       convert(hd(Map.get(node, "children", [])))
     ]}
  end

  # ── Statements ─────────────────────────────────────────────────────

  defp convert(%{"kind" => "Let"} = node) do
    {:assignment,
     [
       binding: if(get_in(node, ["extra", "kind"]) == "assert", do: :assert, else: :let),
       language: :gleam,
       gleam_kind: "Let"
     ]
     |> then(
       &(&1 ++ location(node) ++ optional(:type, node["type_node"] && convert(node["type_node"])))
     ),
     [
       convert(node["pattern"]),
       convert(hd(Map.get(node, "children", [])))
     ]}
  end

  # `use x <- f()` desugars to `f(fn(x) { …body… })`, which is exactly what
  # this models: the call becomes a `:function_call` whose last argument is a
  # `:lambda` binding the `use` patterns. That is portable, analyzable, and
  # reifies back to the `use` form because the lambda carries
  # `gleam_kind: "Use"`.
  defp convert(%{"kind" => "Use"} = node) do
    assignments = get_in(node, ["extra", "assignments"]) || []
    [call] = Map.get(node, "children", [])

    params =
      Enum.map(assignments, fn assignment ->
        {:param, [kind: :positional, language: :gleam, gleam_kind: "UseAssignment"],
         use_param_name(assignment["pattern"])}
      end)

    callback =
      {:lambda,
       [params: params, kind: "use", language: :gleam, gleam_kind: "Use"] ++ location(node),
       Enum.map(assignments, fn assignment ->
         {:assignment, [binding: :use, language: :gleam],
          [
            convert(assignment["pattern"]),
            {:variable, [scope: :local, language: :gleam], use_param_name(assignment["pattern"])}
          ]}
       end)}

    case convert(call) do
      {:function_call, meta, arguments} ->
        {:function_call, Keyword.put(meta, :gleam_kind, "Use"), arguments ++ [callback]}

      other ->
        {:function_call, [name: "<use>", language: :gleam, gleam_kind: "Use"], [other, callback]}
    end
  end

  # `AST` has no `:assert` node type, and inventing one would fail
  # conformance. An `assert` is a statement with no portable analogue (it
  # aborts the function on failure), so the M1 payload is preserved verbatim —
  # which also keeps `assert … as "message"` intact for reification.
  defp convert(%{"kind" => "Assert"} = node) do
    {:language_specific, [language: :gleam, hint: :assert] ++ location(node), node}
  end

  # ── Expressions ────────────────────────────────────────────────────

  defp convert(%{"kind" => kind} = node) when kind in ["Int", "Float", "String"] do
    %{"subtype" => subtype, "value" => value} = node["value"]

    meta =
      [subtype: literal_subtype(subtype), language: :gleam]
      |> Kernel.++(location(node))
      |> Kernel.++(literal_meta(subtype, value))

    {:literal, meta, literal_value(subtype, value)}
  end

  defp convert(%{"kind" => "Var"} = node) do
    case get_in(node, ["extra", "module"]) do
      nil ->
        {:variable, [scope: :local, language: :gleam] ++ location(node), node["name"]}

      module ->
        {:variable, [scope: :qualified, module: module, language: :gleam] ++ location(node),
         node["name"]}
    end
  end

  defp convert(%{"kind" => "Block"} = node) do
    {:block, [scope: :expression, language: :gleam] ++ location(node),
     Enum.map(Map.get(node, "children", []), &convert/1)}
  end

  defp convert(%{"kind" => "FnLiteral"} = node) do
    children = Map.get(node, "children", [])
    {params, body} = Enum.split_with(children, &(&1["kind"] == "Arg"))

    meta =
      [
        params: Enum.map(params, &convert/1),
        kind: get_in(node, ["extra", "kind"]),
        language: :gleam,
        gleam_kind: "FnLiteral"
      ]
      |> then(
        &(&1 ++
            location(node) ++
            optional(:return_type, type_name(node["type_node"])))
      )

    {:lambda, meta, Enum.map(body, &convert/1)}
  end

  # A pattern list's tail is `%{"pattern" => …, "location" => …}` (a
  # `TailPattern`), unlike an expression list's tail, which is a bare node.
  defp convert(%{"kind" => "List", "extra" => %{"tail" => %{"pattern" => tail}}} = node) do
    {:list, [language: :gleam] ++ location(node),
     Enum.map(Map.get(node, "children", []), &convert/1) ++
       [{:spread, [context: :pattern, language: :gleam], [convert(tail)]}]}
  end

  defp convert(%{"kind" => "List"} = node) do
    elements = Enum.map(Map.get(node, "children", []), &convert/1)

    case get_in(node, ["extra", "tail"]) do
      nil ->
        {:list, [language: :gleam] ++ location(node), elements}

      tail ->
        # `[1, 2, ..rest]` is a list with a spread tail. MetaAST models the
        # spread explicitly so the tail stays an analyzable child rather than
        # being flattened into the elements.
        {:list, [language: :gleam] ++ location(node),
         elements ++ [{:spread, [context: :expression, language: :gleam], [convert(tail)]}]}
    end
  end

  defp convert(%{"kind" => "Tuple"} = node) do
    {:tuple, [language: :gleam] ++ location(node),
     Enum.map(Map.get(node, "children", []), &convert/1)}
  end

  defp convert(%{"kind" => "Call"} = node) do
    [callee | arguments] = Map.get(node, "children", [])

    {:function_call,
     [name: call_name(callee), language: :gleam, gleam_kind: "Call"] ++ location(node),
     Enum.map(arguments, &convert/1)}
  end

  defp convert(%{"kind" => "CallArg"} = node) do
    case get_in(node, ["extra", "label"]) do
      nil ->
        convert(hd(Map.get(node, "children", [])))

      label ->
        {:labeled, [label: label, language: :gleam], [convert(hd(Map.get(node, "children", [])))]}
    end
  end

  defp convert(%{"kind" => "BinOp"} = node) do
    [left, right] = Map.get(node, "children", [])
    operator = get_in(node, ["extra", "operator"])
    {category, symbol} = Map.get(@binary_operators, operator, {:arithmetic, :+})

    {:binary_op,
     [category: category, operator: symbol, gleam_operator: operator, language: :gleam] ++
       location(node), [convert(left), convert(right)]}
  end

  defp convert(%{"kind" => "NegateInt"} = node) do
    {:unary_op, [category: :arithmetic, operator: :-, language: :gleam] ++ location(node),
     [convert(hd(Map.get(node, "children", [])))]}
  end

  defp convert(%{"kind" => "NegateBool"} = node) do
    {:unary_op, [category: :boolean, operator: :not, language: :gleam] ++ location(node),
     [convert(hd(Map.get(node, "children", [])))]}
  end

  defp convert(%{"kind" => "Pipeline"} = node) do
    # A Gleam pipeline is a chain of `|>` applications. MetaAST's `:pipe` is
    # binary, so a three-stage pipeline nests left: `a |> f |> g` becomes
    # `(a |> f) |> g`, which is how Gleam evaluates it.
    node
    |> Map.get("children", [])
    |> Enum.map(&convert/1)
    |> Enum.reduce(fn right, left ->
      {:pipe, [operator: :|>, language: :gleam] ++ location(node), [left, right]}
    end)
  end

  defp convert(%{"kind" => "Case"} = node) do
    children = Map.get(node, "children", [])
    {subjects, clauses} = Enum.split_with(children, &(&1["kind"] != "Clause"))
    converted = Enum.map(subjects, &convert/1)

    # `AST` requires `:pattern_match` to have exactly one scrutinee. A
    # multi-subject case (`case a, b { 0, 0 -> … }`) is the same construct as
    # matching on a tuple of the subjects, so that is how it is modelled —
    # and `subject_count:` records the original arity for reification.
    scrutinee =
      case converted do
        [single] -> single
        many -> {:tuple, [language: :gleam, implicit: true] ++ location(node), many}
      end

    {:pattern_match,
     [language: :gleam, gleam_kind: "Case", subject_count: length(converted)] ++
       location(node), [scrutinee | Enum.map(clauses, &convert/1)]}
  end

  defp convert(%{"kind" => "Clause"} = node) do
    children = Map.get(node, "children", [])
    {patterns, [body]} = Enum.split(children, -1)
    guard = get_in(node, ["extra", "guard"])

    # `AST` requires `:pattern` on a `:match_arm` to be a *single* node, not a
    # list. A Gleam clause can match several subjects (`case a, b { 0, 0 -> }`),
    # so a multi-pattern clause keeps them in `patterns:` and puts the first in
    # `pattern:`; `FromMeta` reads `patterns:` when it is present.
    converted = Enum.map(patterns, &convert/1)

    {:match_arm,
     [
       pattern: List.first(converted),
       patterns: converted,
       language: :gleam,
       gleam_kind: "Clause",
       alternative_patterns: get_in(node, ["extra", "alternative_patterns"]) || 0
     ]
     |> then(
       &(&1 ++
           location(node) ++
           optional(
             :guard,
             guard && {:language_specific, [language: :gleam, hint: :guard], guard}
           ))
     ), [convert(body)]}
  end

  defp convert(%{"kind" => "FieldAccess"} = node) do
    {:attribute_access, [attribute: node["name"], language: :gleam] ++ location(node),
     [convert(hd(Map.get(node, "children", [])))]}
  end

  defp convert(%{"kind" => "TupleIndex"} = node) do
    {:attribute_access,
     [attribute: Integer.to_string(get_in(node, ["extra", "index"]) || 0), language: :gleam]
     |> then(&(&1 ++ location(node))), [convert(hd(Map.get(node, "children", [])))]}
  end

  defp convert(%{"kind" => "Todo"} = node) do
    {:throw,
     [kind: :todo, language: :gleam, gleam_kind: "Todo"] ++
       location(node) ++ optional(:todo_kind, get_in(node, ["extra", "kind"])),
     Enum.map(Map.get(node, "children", []), &convert/1)}
  end

  defp convert(%{"kind" => "Panic"} = node) do
    {:throw, [kind: :panic, language: :gleam, gleam_kind: "Panic"] ++ location(node),
     Enum.map(Map.get(node, "children", []), &convert/1)}
  end

  defp convert(%{"kind" => "Echo"} = node) do
    # `echo` is a debugging aid with no portable analogue: it prints and
    # returns its argument. Preserved verbatim so reification restores it.
    {:language_specific, [language: :gleam, hint: :echo] ++ location(node), node}
  end

  defp convert(%{"kind" => "BitArray"} = node) do
    {:list, [list_kind: :bit_array, language: :gleam] ++ location(node),
     Enum.map(Map.get(node, "children", []), &convert/1)}
  end

  defp convert(%{"kind" => "BitArraySegment"} = node) do
    options = get_in(node, ["extra", "options"]) || []

    {:bin_segment,
     [
       type: bit_array_type(options),
       size: bit_array_size(options, node),
       unit: bit_array_unit(options),
       signedness: bit_array_signedness(options),
       endianness: bit_array_endianness(options),
       language: :gleam
     ]
     |> then(&(&1 ++ location(node))), [convert(hd(Map.get(node, "children", [])))]}
  end

  defp convert(%{"kind" => "RecordUpdate"} = node) do
    [constructor, base | arguments] = Map.get(node, "children", [])

    {:record_update, [name: call_name(constructor), language: :gleam] ++ location(node),
     [convert(base) | Enum.map(arguments, &convert/1)]}
  end

  defp convert(%{"kind" => "RecordUpdateArg"} = node) do
    {:labeled, [label: node["name"], language: :gleam],
     [convert(hd(Map.get(node, "children", [])))]}
  end

  defp convert(%{"kind" => "Record"} = node) do
    {:function_call,
     [
       name: qualified_name(node),
       record: true,
       language: :gleam,
       gleam_kind: "Record"
     ]
     |> then(&(&1 ++ location(node))), Enum.map(Map.get(node, "children", []), &convert/1)}
  end

  # ── Patterns ───────────────────────────────────────────────────────

  defp convert(%{"kind" => "Discard"} = node) do
    {:variable, [scope: :discard, language: :gleam] ++ location(node), node["name"] || "_"}
  end

  # `AST` requires `:inline_match` to have exactly `[pattern, value]`. A Gleam
  # `pattern as name` binds the whole matched value to `name`, so the pattern
  # is both: it is the thing matched and the thing bound.
  defp convert(%{"kind" => "Assign"} = node) do
    inner = convert(hd(Map.get(node, "children", [])))

    {:inline_match, [name: node["name"], language: :gleam] ++ location(node), [inner, inner]}
  end

  defp convert(%{"kind" => "Constructor"} = node) do
    {:function_call,
     [
       name: qualified_name(node),
       pattern: true,
       language: :gleam,
       gleam_kind: "Constructor"
     ]
     |> compact()
     |> Kernel.++(location(node))
     |> Kernel.++(if(get_in(node, ["extra", "spread"]), do: [spread: true], else: [])),
     Enum.map(Map.get(node, "children", []), &convert/1)}
  end

  defp convert(%{"kind" => "StringPrefix"} = node) do
    {:language_specific, [language: :gleam, hint: :string_prefix] ++ location(node), node}
  end

  defp convert(%{"kind" => "InvalidPattern"} = node) do
    {:variable, [scope: :invalid, language: :gleam] ++ location(node), "_"}
  end

  # ── Types ──────────────────────────────────────────────────────────

  defp convert(%{"kind" => "TypeConstructor"} = node) do
    {:type_annotation,
     [
       annotation_type: :type,
       name: qualified_type_name(node),
       language: :gleam,
       gleam_kind: "TypeConstructor"
     ]
     |> then(&(&1 ++ location(node))), Enum.map(Map.get(node, "children", []), &convert/1)}
  end

  defp convert(%{"kind" => "FnType"} = node) do
    children = Map.get(node, "children", [])
    {arguments, [return_type]} = Enum.split(children, -1)

    {:type_annotation,
     [
       annotation_type: :type,
       name: "fn",
       language: :gleam,
       gleam_kind: "FnType",
       arguments: Enum.map(arguments, &convert/1)
     ]
     |> then(&(&1 ++ location(node) ++ optional(:type, convert(return_type)))), []}
  end

  defp convert(%{"kind" => "TupleType"} = node) do
    {:type_annotation,
     [annotation_type: :type, name: "tuple", language: :gleam, gleam_kind: "TupleType"] ++
       location(node), Enum.map(Map.get(node, "children", []), &convert/1)}
  end

  defp convert(%{"kind" => "TypeVar"} = node) do
    {:type_annotation,
     [annotation_type: :type, name: node["name"], language: :gleam, gleam_kind: "TypeVar"] ++
       location(node), []}
  end

  defp convert(%{"kind" => "TypeHole"} = node) do
    {:type_annotation,
     [annotation_type: :type, name: node["name"], language: :gleam, gleam_kind: "TypeHole"] ++
       location(node), []}
  end

  # ── Parameters ─────────────────────────────────────────────────────

  defp convert(%{"kind" => "Arg"} = node) do
    # `:param`'s third element is the parameter's name. `AST`'s param kinds are
    # `:positional | :keyword | :variadic | :keyword_variadic`; a discarded
    # parameter is still positional, and the discard is carried by `discard:`
    # so conformance holds.
    # See `RecordConstructorArg` above: the type is a string in `:type`, which
    # is what makes a Gleam function translatable to another language.
    meta =
      [
        kind: :positional,
        label: get_in(node, ["extra", "label"]),
        discard: Map.get(node, "discard", false),
        type: type_name(node["type_node"]),
        language: :gleam,
        gleam_kind: "Arg"
      ]
      |> compact()
      |> Kernel.++(location(node))

    {:param, meta, node["name"] || "_"}
  end

  # An unrecognised kind is a bridge/adapter skew. Failing loudly beats
  # silently degrading every new construct to an opaque leaf.
  defp convert(%{"kind" => kind}) do
    throw({:gleam_transform, "Unsupported Gleam node kind: #{inspect(kind)}"})
  end

  # The source spelling of a type node, e.g. `Int`, `List(Int)`, `fn(Int) -> Int`.
  #
  # Parameters and return annotations keep the *name* rather than the
  # `:type_annotation` tree, because that is what the other adapters expose and
  # what cross-language translation consumes.
  defp type_name(nil), do: nil

  defp type_name(%{"kind" => "TypeConstructor"} = node) do
    case Map.get(node, "children", []) do
      [] -> qualified_type_name(node)
      arguments -> "#{qualified_type_name(node)}(#{Enum.map_join(arguments, ", ", &type_name/1)})"
    end
  end

  defp type_name(%{"kind" => "FnType"} = node) do
    {arguments, [return_type]} = Enum.split(Map.get(node, "children", []), -1)
    "fn(#{Enum.map_join(arguments, ", ", &type_name/1)}) -> #{type_name(return_type)}"
  end

  defp type_name(%{"kind" => "TupleType"} = node) do
    "#(#{Enum.map_join(Map.get(node, "children", []), ", ", &type_name/1)})"
  end

  defp type_name(%{"kind" => kind} = node) when kind in ["TypeVar", "TypeHole"],
    do: node["name"]

  defp type_name(_node), do: nil

  # The implicit name bound by a `use` assignment. Gleam's `use` patterns are
  # variables in the overwhelming majority of cases; anything else keeps a
  # positional placeholder so the lambda stays well-formed.
  defp use_param_name(%{"kind" => "Var", "name" => name}), do: name
  defp use_param_name(%{"kind" => "Discard", "name" => name}), do: name
  defp use_param_name(_), do: "_"

  # ── Helpers ────────────────────────────────────────────────────────

  defp location(%{"span" => %{"line" => line, "col" => col}}) do
    [line: line, col: col]
  end

  defp location(_), do: []

  defp optional(_key, nil), do: []
  defp optional(key, value), do: [{key, value}]

  defp compact(keyword), do: Enum.reject(keyword, fn {_key, value} -> is_nil(value) end)

  defp visibility(node) do
    if Map.get(node, "public", false), do: :public, else: :private
  end

  defp external_meta(node) do
    extra = Map.get(node, "extra", %{})

    [
      external_erlang: extra["external_erlang"],
      external_javascript: extra["external_javascript"]
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp import_name(%{"name" => name, "as_name" => nil}), do: name
  defp import_name(%{"name" => name, "as_name" => as_name}), do: "#{name} as #{as_name}"

  # The callee of a `Call` is an expression; its name is what analyzers key on
  # (`io.println`, `list.map`, `Ok`). A non-variable callee keeps a
  # placeholder so the node stays well-formed.
  defp call_name(%{"kind" => "Var", "name" => name} = node) do
    case get_in(node, ["extra", "module"]) do
      nil -> name
      module -> "#{module}.#{name}"
    end
  end

  defp call_name(%{"kind" => "FieldAccess", "name" => name} = node) do
    case get_in(node, ["children", Access.at(0)]) do
      %{"kind" => "Var", "name" => receiver} -> "#{receiver}.#{name}"
      _ -> name
    end
  end

  defp call_name(_), do: "<anonymous>"

  defp qualified_name(node) do
    case get_in(node, ["extra", "module"]) do
      nil -> node["name"]
      module -> "#{module}.#{node["name"]}"
    end
  end

  defp qualified_type_name(node) do
    case get_in(node, ["extra", "module"]) do
      nil -> node["name"]
      module -> "#{module}.#{node["name"]}"
    end
  end

  defp literal_subtype("integer"), do: :integer
  defp literal_subtype("float"), do: :float
  defp literal_subtype("string"), do: :string
  defp literal_subtype(_), do: :string

  # `AST` requires a literal's value to be the *native* type: an integer for
  # `:integer`, a float for `:float`. The bridge sends source spelling because
  # Gleam integers are arbitrary precision (`1 <<< 200` has no `i64`), so the
  # string is converted here and the original spelling is kept in the node's
  # metadata by `literal_meta/2` — that is what lets `FromMeta` write back a
  # value Elixir cannot represent.
  defp literal_value("integer", value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _ -> 0
    end
  end

  defp literal_value("float", value) do
    case Float.parse(value) do
      {float, ""} -> float
      _ -> 0.0
    end
  end

  defp literal_value("string", value), do: value
  defp literal_value(_, value), do: value

  # The source spelling of a numeric literal, when it differs from what the
  # value converts back to (a bignum, a trailing zero, `1.0` vs `1`).
  defp literal_meta("integer", value) do
    case Integer.parse(value) do
      {integer, ""} when integer == value -> []
      _ -> [gleam_literal: value]
    end
  end

  defp literal_meta("float", value) do
    case Float.parse(value) do
      {float, ""} -> if Float.to_string(float) == value, do: [], else: [gleam_literal: value]
      _ -> [gleam_literal: value]
    end
  end

  defp literal_meta(_subtype, _value), do: []

  # Gleam's segment type names do not all exist in MetaAST's
  # `@bin_segment_types`; `bytes` is `:binary` there and `int` is `:integer`.
  @bit_array_types %{
    "bytes" => :binary,
    "int" => :integer,
    "float" => :float,
    "bits" => :bits,
    "utf8" => :utf8,
    "utf16" => :utf16,
    "utf32" => :utf32
  }

  defp bit_array_type(options) do
    Enum.find_value(options, fn
      %{"name" => name} -> Map.get(@bit_array_types, name)
      _ -> nil
    end)
  end

  # `:bin_segment`'s `:size` must be a MetaAST node, so the bridge's size
  # expression is abstracted rather than copied through as a raw value.
  defp bit_array_size(options, _node) do
    Enum.find_value(options, fn
      %{"name" => "size", "extra" => %{"value" => value}} ->
        case __MODULE__.node(value) do
          {:ok, size} -> size
          {:error, _} -> nil
        end

      _ ->
        nil
    end)
  end

  defp bit_array_unit(options) do
    Enum.find_value(options, fn
      %{"name" => "unit", "extra" => %{"value" => value}} -> value
      _ -> nil
    end)
  end

  defp bit_array_signedness(options) do
    Enum.find_value(options, fn
      %{"name" => "signed"} -> :signed
      %{"name" => "unsigned"} -> :unsigned
      _ -> nil
    end)
  end

  defp bit_array_endianness(options) do
    Enum.find_value(options, fn
      %{"name" => "big"} -> :big
      %{"name" => "little"} -> :little
      %{"name" => "native"} -> :native
      _ -> nil
    end)
  end
end
