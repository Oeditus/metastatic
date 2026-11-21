defmodule Metastatic.Adapters.Haskell.ToMeta do
  @moduledoc """
  Transform Haskell AST (M1) to MetaAST (M2).

  Implements the abstraction function α_Haskell that lifts Haskell-specific
  AST structures to the meta-level representation.

  ## 3-Tuple Format

  All MetaAST nodes use the uniform 3-tuple structure:
  `{type_atom, keyword_meta, children_or_value}`

  ## Transformation Strategy

  ### M2.1 (Core Layer)
  - Literals: integers, floats, strings, chars
  - Variables: unqualified and qualified names
  - Binary operators: arithmetic, comparison, boolean
  - Function application
  - Conditionals: if-then-else
  - Lambdas: anonymous functions
  - Let bindings

  ### M2.2 (Extended Layer)
  - List comprehensions
  - Case expressions (pattern matching)
  - Do notation (monadic sequencing)

  ### M2.3 (Native Layer)
  - Type signatures
  - Data type definitions
  - Type class definitions
  - Module definitions
  """

  @doc """
  Transform Haskell AST to MetaAST.

  Returns `{:ok, meta_ast, metadata}` on success or `{:error, reason}` on failure.
  """
  @spec transform(term()) :: {:ok, term(), map()} | {:error, String.t()}

  # M2.1 Core Layer - Literals

  def transform(%{"type" => "literal", "value" => value} = node) do
    case transform_literal(value) do
      {:ok, ast, meta} -> {:ok, add_location(ast, node), meta}
      error -> error
    end
  end

  # M2.1 Core Layer - Variables

  def transform(%{"type" => "var", "name" => name} = node) do
    {:ok, add_location({:variable, [scope: :local], name}, node), %{}}
  end

  # M2.1 Core Layer - Constructors (data constructors)
  #
  # A constructor is a bare name, which the `:symbol` literal subtype models.
  # `:constructor` is not a member of `@literal_subtypes` and `:symbol`
  # requires an atom, so the name is converted here — emitting the string
  # made every node containing a constructor (e.g. `Nothing`) non-conforming.
  def transform(%{"type" => "con", "name" => name} = node) do
    {:ok, add_location({:literal, [subtype: :symbol], String.to_atom(name)}, node), %{}}
  end

  # M2.1 Core Layer - Negation (unary minus)

  def transform(%{"type" => "negate", "expression" => expr} = node) do
    with {:ok, expr_meta, _} <- transform(expr) do
      ast = {:unary_op, [category: :arithmetic, operator: :-], [expr_meta]}
      {:ok, add_location(ast, node), %{}}
    end
  end

  # M2.1 Core Layer - Expression type signature: (e :: T)

  def transform(%{"type" => "expr_type_sig", "expression" => expr, "signature" => sig} = node) do
    with {:ok, expr_meta, _} <- transform(expr) do
      type_expr = {:language_specific, [language: :haskell, hint: :type_expr], sig}
      ast = {:type_annotation, [annotation_type: :hint], [expr_meta, type_expr]}
      {:ok, add_location(ast, node), %{}}
    end
  end

  # M2.1 Core Layer - Operator sections

  def transform(%{"type" => "left_section", "expression" => expr, "operator" => op} = node) do
    with {:ok, expr_meta, _} <- transform(expr) do
      ast =
        {:language_specific, [language: :haskell, hint: :left_section],
         %{"operator" => op, "expression" => expr_meta}}

      {:ok, add_location(ast, node), %{}}
    end
  end

  def transform(%{"type" => "right_section", "operator" => op, "expression" => expr} = node) do
    with {:ok, expr_meta, _} <- transform(expr) do
      ast =
        {:language_specific, [language: :haskell, hint: :right_section],
         %{"operator" => op, "expression" => expr_meta}}

      {:ok, add_location(ast, node), %{}}
    end
  end

  # M2.1 Core Layer - Record construction: C { field = value }

  def transform(%{"type" => "record_constr", "name" => name, "fields" => fields} = node) do
    with {:ok, pairs} <- transform_record_fields(fields) do
      ast = {:map, [record: true, constructor: name], pairs}
      {:ok, add_location(ast, node), %{record: true}}
    end
  end

  # M2.1 Core Layer - Record update: e { field = value }

  def transform(%{"type" => "record_update", "expression" => expr, "fields" => fields} = node) do
    with {:ok, expr_meta, _} <- transform(expr),
         {:ok, pairs} <- transform_record_fields(fields) do
      ast =
        {:language_specific, [language: :haskell, hint: :record_update],
         %{"target" => expr_meta, "fields" => pairs}}

      {:ok, add_location(ast, node), %{}}
    end
  end

  # M2.1 Core Layer - Enum sequences ([a .. b], [a, b .. c])

  def transform(%{"type" => "enum_from_to", "from" => from, "to" => to} = node) do
    with {:ok, from_meta, _} <- transform(from),
         {:ok, to_meta, _} <- transform(to) do
      {:ok, add_location({:range, [range_type: :enum], [from_meta, to_meta]}, node), %{}}
    end
  end

  def transform(%{"type" => "enum_from", "from" => from} = node) do
    with {:ok, from_meta, _} <- transform(from) do
      ast = {:language_specific, [language: :haskell, hint: :enum_from], %{"from" => from_meta}}
      {:ok, add_location(ast, node), %{}}
    end
  end

  def transform(%{"type" => "enum_from_then", "from" => from, "then" => then_e} = node) do
    with {:ok, from_meta, _} <- transform(from),
         {:ok, then_meta, _} <- transform(then_e) do
      ast =
        {:language_specific, [language: :haskell, hint: :enum_from_then],
         %{"from" => from_meta, "then" => then_meta}}

      {:ok, add_location(ast, node), %{}}
    end
  end

  # M2.1 Core Layer - Function Application

  def transform(%{"type" => "app", "function" => func, "argument" => arg} = node) do
    with {:ok, func_meta, _} <- transform(func),
         {:ok, arg_meta, _} <- transform(arg) do
      # Haskell function application: f x
      ast =
        case func_meta do
          {:function_call, meta, args} ->
            # Accumulate curried arguments
            name = Keyword.get(meta, :name)
            {:function_call, [name: name], args ++ [arg_meta]}

          _ ->
            # First application
            {:function_call, [name: format_function(func_meta)], [arg_meta]}
        end

      {:ok, add_location(ast, node), %{}}
    end
  end

  # M2.1 Core Layer - Infix Operators

  def transform(%{"type" => "infix", "left" => left, "operator" => op, "right" => right} = node) do
    with {:ok, left_meta, _} <- transform(left),
         {:ok, right_meta, _} <- transform(right) do
      op_atom = normalize_op(op)

      ast =
        cond do
          is_arithmetic_op?(op_atom) ->
            {:binary_op, [category: :arithmetic, operator: op_atom], [left_meta, right_meta]}

          is_comparison_op?(op_atom) ->
            {:binary_op, [category: :comparison, operator: op_atom], [left_meta, right_meta]}

          is_boolean_op?(op_atom) ->
            normalized = normalize_bool_op(op_atom)
            {:binary_op, [category: :boolean, operator: normalized], [left_meta, right_meta]}

          true ->
            # Custom operator - treat as function call
            {:function_call, [name: op], [left_meta, right_meta]}
        end

      custom_meta =
        if is_arithmetic_op?(op_atom) or is_comparison_op?(op_atom) or
             is_boolean_op?(op_atom),
           do: %{},
           else: %{custom_op: true}

      {:ok, add_location(ast, node), custom_meta}
    end
  end

  # M2.1 Core Layer - Lambda Expressions

  def transform(%{"type" => "lambda", "patterns" => patterns, "body" => body} = node) do
    with {:ok, params} <- extract_lambda_params(patterns),
         {:ok, body_meta, _} <- transform(body) do
      {:ok, add_location({:lambda, [params: params, captures: []], [body_meta]}, node), %{}}
    end
  end

  # M2.1 Core Layer - Let Bindings

  def transform(%{"type" => "let", "bindings" => bindings, "body" => body} = node) do
    with {:ok, bindings_meta} <- transform_bindings(bindings),
         {:ok, body_meta, _} <- transform(body) do
      # Represent as block with assignments followed by body
      statements = bindings_meta ++ [body_meta]
      {:ok, add_location({:block, [construct: :let], statements}, node), %{construct: :let}}
    end
  end

  # M2.1 Core Layer - If-Then-Else

  def transform(
        %{"type" => "if", "condition" => cond, "then" => then_exp, "else" => else_exp} = node
      ) do
    with {:ok, cond_meta, _} <- transform(cond),
         {:ok, then_meta, _} <- transform(then_exp),
         {:ok, else_meta, _} <- transform(else_exp) do
      {:ok, add_location({:conditional, [], [cond_meta, then_meta, else_meta]}, node), %{}}
    end
  end

  # M2.1 Core Layer - Lists

  def transform(%{"type" => "list", "elements" => elements} = node) do
    with {:ok, elements_meta} <- transform_list(elements) do
      {:ok, add_location({:list, [collection_type: :list], elements_meta}, node),
       %{collection_type: :list}}
    end
  end

  # M2.1 Core Layer - Tuples

  def transform(%{"type" => "tuple", "elements" => elements} = node) do
    with {:ok, elements_meta} <- transform_list(elements) do
      {:ok, add_location({:tuple, [], elements_meta}, node), %{}}
    end
  end

  # M2.2 Extended Layer - Case Expressions (Pattern Matching)

  def transform(%{"type" => "case", "scrutinee" => scrutinee, "alternatives" => alts} = node) do
    with {:ok, scrutinee_meta, _} <- transform(scrutinee),
         {:ok, arms} <- transform_case_alts(alts) do
      {:ok, add_location({:pattern_match, [], [scrutinee_meta | arms]}, node), %{}}
    end
  end

  # M2.2 Extended Layer - List Comprehensions -> comprehension

  def transform(
        %{
          "type" => "list_comp",
          "expression" => expr,
          "qualifiers" => quals
        } = node
      ) do
    with {:ok, expr_meta, _} <- transform(expr),
         {:ok, quals_meta} <- transform_qualifiers(quals) do
      {:ok,
       add_location(
         {:comprehension, [comp_type: :list], [expr_meta | quals_meta]},
         node
       ), %{}}
    end
  end

  # M2.2 Extended Layer - Do Notation

  def transform(%{"type" => "do", "statements" => stmts} = node) do
    with {:ok, stmts_meta} <- transform_do_statements(stmts) do
      {:ok, add_location({:block, [construct: :do_notation], stmts_meta}, node),
       %{construct: :do_notation}}
    end
  end

  # M2.2s Structural Layer - Module -> container

  def transform(%{"type" => "module", "declarations" => decls} = node) do
    module_name = Map.get(node, "name", "Main")

    with {:ok, decls_meta} <- transform_declarations(decls) do
      {:ok,
       add_location(
         {:container, [container_type: :module, name: module_name, language: :haskell],
          decls_meta},
         node
       ), %{}}
    end
  end

  # M2.2s Structural Layer - Type Signature -> type_annotation

  def transform(%{"type" => "type_sig", "names" => names, "signature" => sig} = node) do
    name = List.first(names) || "unknown"
    type_expr = {:language_specific, [language: :haskell, hint: :type_expr], sig}

    {:ok,
     add_location(
       {:type_annotation, [annotation_type: :spec, name: name, names: names], [type_expr]},
       node
     ), %{}}
  end

  # M2.3 Native Layer - Data Type Declaration

  def transform(
        %{
          "type" => "data_decl",
          "data_or_new" => kind,
          "name" => name,
          "constructors" => cons
        } = node
      ) do
    {:ok,
     add_location(
       {:language_specific, [language: :haskell, hint: :data_decl],
        %{"kind" => kind, "name" => name, "constructors" => cons}},
       node
     ), %{}}
  end

  # M2.3 Native Layer - Type Alias

  def transform(%{"type" => "type_alias", "name" => name, "definition" => def_type} = node) do
    {:ok,
     add_location(
       {:language_specific, [language: :haskell, hint: :type_alias],
        %{"name" => name, "definition" => def_type}},
       node
     ), %{}}
  end

  # M2.2s Structural Layer - Type Class Declaration -> container interface

  def transform(%{"type" => "class_decl", "name" => name, "methods" => methods} = node) do
    with {:ok, methods_meta} <- transform_declarations(methods) do
      {:ok,
       add_location(
         {:container, [container_type: :interface, name: name, language: :haskell], methods_meta},
         node
       ), %{}}
    end
  end

  # M2.3 Native Layer - Instance Declaration

  def transform(%{"type" => "instance_decl", "rule" => rule, "methods" => methods} = node) do
    {:ok,
     add_location(
       {:language_specific, [language: :haskell, hint: :instance_decl],
        %{"rule" => rule, "methods" => methods}},
       node
     ), %{}}
  end

  # M2.2s Structural Layer - Function Binding -> function_def

  def transform(%{"type" => "fun_bind", "matches" => matches} = node) do
    case extract_function_from_matches(matches) do
      {:ok, name, params, body} ->
        meta = [
          name: name,
          params: params,
          visibility: :public,
          arity: length(params),
          language: :haskell
        ]

        {:ok, add_location({:function_def, meta, [body]}, node), %{construct: :function_binding}}

      :error ->
        {:ok,
         add_location(
           {:language_specific, [language: :haskell, hint: :function_binding],
            %{"matches" => matches}},
           node
         ), %{}}
    end
  end

  # Pattern nodes reached as expressions (e.g. inside do-notation generators)

  def transform(%{"type" => pat_type} = node)
      when pat_type in [
             "con_pat",
             "tuple_pat",
             "list_pat",
             "infix_pat",
             "as_pat",
             "record_pat",
             "var_pat",
             "lit_pat",
             "wildcard"
           ] do
    with {:ok, pat_meta} <- transform_pattern(node) do
      {:ok, add_location(pat_meta, node), %{}}
    end
  end

  # Statement nodes reached as expressions (do-notation / comprehension items)

  def transform(%{"type" => stmt_type} = node)
      when stmt_type in ["generator", "qualifier", "let_stmt"] do
    transform_statement(node)
  end

  # Top-level pattern bindings (e.g. `main = do ...`)
  #
  # `transform_binding/1` already attaches the location, so this clause must
  # not call `add_location/2` again — doing so duplicated every location key
  # (`[line: 29, line: 29, ...]`), which made the node fail `AST.conforms?/1`.
  def transform(%{"type" => "pat_bind"} = node) do
    with {:ok, assignment} <- transform_binding(node) do
      {:ok, assignment, %{}}
    end
  end

  # Unsupported constructs

  def transform(unsupported) do
    {:error, "Unsupported Haskell AST construct: #{inspect(unsupported)}"}
  end

  # Helper Functions

  defp transform_literal(%{"literalType" => "int", "value" => value}) do
    {:ok, {:literal, [subtype: :integer], value}, %{}}
  end

  defp transform_literal(%{"literalType" => "float", "value" => value}) do
    {:ok, {:literal, [subtype: :float], value}, %{}}
  end

  defp transform_literal(%{"literalType" => "string", "value" => value}) do
    {:ok, {:literal, [subtype: :string], value}, %{}}
  end

  defp transform_literal(%{"literalType" => "char", "value" => value}) do
    {:ok, {:literal, [subtype: :char], value}, %{}}
  end

  defp transform_literal(_), do: {:error, "Unknown literal type"}

  defp transform_list(items) when is_list(items) do
    items
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
      case transform(item) do
        {:ok, meta, _} -> {:cont, {:ok, [meta | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, items} -> {:ok, Enum.reverse(items)}
      error -> error
    end
  end

  defp extract_lambda_params(patterns) when is_list(patterns) do
    params =
      Enum.map(patterns, fn
        %{"type" => "var_pat", "name" => name} -> {:param, [], name}
        _ -> {:param, [], "_"}
      end)

    {:ok, params}
  end

  defp transform_bindings(bindings) when is_list(bindings) do
    bindings
    |> Enum.reduce_while({:ok, []}, fn binding, {:ok, acc} ->
      case transform_binding(binding) do
        {:ok, meta} -> {:cont, {:ok, [meta | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, bindings} -> {:ok, Enum.reverse(bindings)}
      error -> error
    end
  end

  defp transform_binding(%{"type" => "pat_bind", "pattern" => pat, "rhs" => rhs} = binding) do
    with {:ok, var_name} <- extract_pattern_var(pat),
         {:ok, value_meta, _} <- transform(rhs) do
      {:ok,
       add_location(
         {:assignment, [], [{:variable, [scope: :local], var_name}, value_meta]},
         binding
       )}
    end
  end

  defp transform_binding(_), do: {:error, "Unsupported binding"}

  defp extract_pattern_var(%{"type" => "var_pat", "name" => name}), do: {:ok, name}
  defp extract_pattern_var(_), do: {:error, "Complex pattern in let binding"}

  defp transform_case_alts(alts) when is_list(alts) do
    alts
    |> Enum.reduce_while({:ok, []}, fn alt, {:ok, acc} ->
      case transform_case_alt(alt) do
        {:ok, branch} -> {:cont, {:ok, [branch | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, branches} -> {:ok, Enum.reverse(branches)}
      error -> error
    end
  end

  defp transform_case_alt(%{"pattern" => pat, "rhs" => rhs} = alt) do
    with {:ok, pat_meta} <- transform_pattern(pat),
         {:ok, rhs_meta, _} <- transform(rhs) do
      {:ok, add_location({:match_arm, [pattern: pat_meta], [rhs_meta]}, alt)}
    end
  end

  defp transform_pattern(%{"type" => "var_pat", "name" => name}) do
    {:ok, {:variable, [], name}}
  end

  defp transform_pattern(%{"type" => "lit_pat", "literal" => lit}) do
    case transform_literal(lit) do
      {:ok, lit_meta, _} -> {:ok, lit_meta}
      error -> error
    end
  end

  # A wildcard is the `:wildcard` node, not the bare atom `:_`. `AST.conforms?/1`
  # rejects the atom, so emitting it made every `case` arm with a `_` pattern
  # (and therefore the whole module) non-conforming.
  defp transform_pattern(%{"type" => "wildcard"}) do
    {:ok, {:wildcard, [], nil}}
  end

  defp transform_pattern(%{"type" => "con_pat", "name" => name, "patterns" => pats}) do
    with {:ok, args} <- transform_patterns(pats) do
      {:ok, {:function_call, [name: name, pattern: true], args}}
    end
  end

  defp transform_pattern(%{"type" => "tuple_pat", "elements" => elems}) do
    with {:ok, args} <- transform_patterns(elems) do
      {:ok, {:tuple, [pattern: true], args}}
    end
  end

  defp transform_pattern(%{"type" => "list_pat", "elements" => elems}) do
    with {:ok, args} <- transform_patterns(elems) do
      {:ok, {:list, [collection_type: :list, pattern: true], args}}
    end
  end

  defp transform_pattern(%{
         "type" => "infix_pat",
         "left" => left,
         "operator" => op,
         "right" => right
       }) do
    with {:ok, left_meta} <- transform_pattern(left),
         {:ok, right_meta} <- transform_pattern(right) do
      # `x : xs` is a cons *constructor* pattern, not an operator: `:pattern`
      # is not a valid `:binary_op` category, so the previous encoding made
      # every node containing a cons pattern non-conforming. A constructor
      # application (`{:function_call, [pattern: true]}`) is the shape the
      # other constructor patterns already use.
      {:ok, {:function_call, [name: to_string(op), pattern: true], [left_meta, right_meta]}}
    end
  end

  defp transform_pattern(%{"type" => "as_pat", "name" => name, "pattern" => pat}) do
    with {:ok, pat_meta} <- transform_pattern(pat) do
      {:ok,
       {:language_specific, [language: :haskell, hint: :as_pattern],
        %{"name" => name, "pattern" => pat_meta}}}
    end
  end

  defp transform_pattern(%{"type" => "record_pat", "name" => name, "fields" => fields}) do
    with {:ok, pairs} <- transform_record_pattern_fields(fields) do
      {:ok, {:map, [record: true, constructor: name], pairs}}
    end
  end

  defp transform_pattern(_), do: {:error, "Unsupported pattern"}

  defp transform_patterns(pats) when is_list(pats) do
    pats
    |> Enum.reduce_while({:ok, []}, fn pat, {:ok, acc} ->
      case transform_pattern(pat) do
        {:ok, meta} -> {:cont, {:ok, [meta | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, metas} -> {:ok, Enum.reverse(metas)}
      error -> error
    end
  end

  defp transform_record_pattern_fields(fields) when is_list(fields) do
    fields
    |> Enum.reduce_while({:ok, []}, fn field, {:ok, acc} ->
      with %{"name" => name, "pattern" => pat} <- field,
           {:ok, pat_meta} <- transform_pattern(pat) do
        key = {:literal, [subtype: :string], name}
        {:cont, {:ok, [{:pair, [], [key, pat_meta]} | acc]}}
      else
        {:error, _} = err -> {:halt, err}
        _ -> {:halt, {:error, "Unsupported record pattern field: #{inspect(field)}"}}
      end
    end)
    |> case do
      {:ok, pairs} -> {:ok, Enum.reverse(pairs)}
      error -> error
    end
  end

  defp transform_record_fields(fields) when is_list(fields) do
    fields
    |> Enum.reduce_while({:ok, []}, fn field, {:ok, acc} ->
      with %{"name" => name, "value" => value} <- field,
           {:ok, value_meta, _} <- transform(value) do
        key = {:literal, [subtype: :string], name}
        {:cont, {:ok, [{:pair, [], [key, value_meta]} | acc]}}
      else
        {:error, _} = err -> {:halt, err}
        _ -> {:halt, {:error, "Unsupported record field: #{inspect(field)}"}}
      end
    end)
    |> case do
      {:ok, pairs} -> {:ok, Enum.reverse(pairs)}
      error -> error
    end
  end

  defp transform_qualifiers(quals) when is_list(quals) do
    quals
    |> Enum.reduce_while({:ok, []}, fn qual, {:ok, acc} ->
      case transform_qualifier(qual) do
        {:ok, meta} -> {:cont, {:ok, [meta | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, quals_list} -> {:ok, Enum.reverse(quals_list)}
      error -> error
    end
  end

  defp transform_qualifier(
         %{"type" => "generator", "pattern" => pat, "expression" => expr} = qual
       ) do
    with {:ok, pat_meta} <- transform_pattern(pat),
         {:ok, expr_meta, _} <- transform(expr) do
      {:ok, add_location({:generator, [], [pat_meta, expr_meta]}, qual)}
    end
  end

  defp transform_qualifier(%{"type" => "qualifier", "expression" => expr} = qual) do
    with {:ok, expr_meta, _} <- transform(expr) do
      {:ok, add_location({:qualifier, [], [expr_meta]}, qual)}
    end
  end

  defp transform_qualifier(other), do: {:error, "Unsupported qualifier: #{inspect(other)}"}

  defp transform_do_statements(stmts) when is_list(stmts) do
    stmts
    |> Enum.reduce_while({:ok, []}, fn stmt, {:ok, acc} ->
      case transform_statement(stmt) do
        {:ok, meta} -> {:cont, {:ok, [meta | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, stmts_list} -> {:ok, Enum.reverse(stmts_list)}
      error -> error
    end
  end

  defp transform_statement(
         %{"type" => "generator", "pattern" => pat, "expression" => expr} = stmt
       ) do
    with {:ok, pat_meta} <- transform_pattern(pat),
         {:ok, expr_meta, _} <- transform(expr) do
      {:ok, add_location({:generator, [], [pat_meta, expr_meta]}, stmt)}
    end
  end

  defp transform_statement(%{"type" => "qualifier", "expression" => expr}) do
    with {:ok, expr_meta, _} <- transform(expr) do
      {:ok, expr_meta}
    end
  end

  defp transform_statement(%{"type" => "let_stmt", "bindings" => bindings}) do
    with {:ok, bindings_meta} <- transform_bindings(bindings) do
      {:ok, {:block, [construct: :let], bindings_meta}}
    end
  end

  defp transform_statement(%{"type" => "pat_bind"} = binding) do
    transform_binding(binding)
  end

  defp transform_statement(other), do: {:error, "Unsupported statement: #{inspect(other)}"}

  defp format_function({:variable, _meta, name}), do: name
  defp format_function(_), do: "func"

  defp normalize_op(op) when is_binary(op), do: String.to_atom(op)
  defp normalize_op(op) when is_atom(op), do: op

  # Normalize boolean operator variants to canonical :and/:or
  defp normalize_bool_op(:&&), do: :and
  defp normalize_bool_op(:||), do: :or
  defp normalize_bool_op(op), do: op

  defp is_arithmetic_op?(op) when is_atom(op) do
    op in [:+, :-, :*, :/, :div, :mod, :^, :**]
  end

  defp is_comparison_op?(op) when is_atom(op) do
    op in [:==, :"/=", :<, :>, :<=, :>=]
  end

  defp is_boolean_op?(op) when is_atom(op) do
    op in [:&&, :||, :and, :or]
  end

  defp transform_declarations(decls) when is_list(decls) do
    decls
    |> Enum.reduce_while({:ok, []}, fn decl, {:ok, acc} ->
      case transform(decl) do
        {:ok, meta, _} -> {:cont, {:ok, [meta | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, decls_list} -> {:ok, Enum.reverse(decls_list)}
      error -> error
    end
  end

  defp extract_function_from_matches([match | _]) do
    case match do
      %{"name" => name, "patterns" => patterns, "rhs" => rhs} ->
        with {:ok, params} <- extract_match_params(patterns),
             {:ok, body_meta, _} <- transform(rhs) do
          {:ok, name, params, body_meta}
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp extract_function_from_matches(_), do: :error

  defp extract_match_params(patterns) when is_list(patterns) do
    params =
      Enum.map(patterns, fn
        %{"type" => "var_pat", "name" => name} -> {:param, [], name}
        _ -> {:param, [], "_"}
      end)

    {:ok, params}
  end

  # Location extraction - merges location from JSON node into keyword_meta
  defp add_location({type, meta, children}, %{"location" => loc}) when is_map(loc) do
    location_fields =
      []
      |> maybe_prepend(:line, loc["startLine"])
      |> maybe_prepend(:col, loc["startCol"])
      |> maybe_prepend(:end_line, loc["endLine"])
      |> maybe_prepend(:end_col, loc["endCol"])

    {type, meta ++ location_fields, children}
  end

  defp add_location(ast, _node), do: ast

  defp maybe_prepend(list, _key, nil), do: list
  defp maybe_prepend(list, key, value), do: [{key, value} | list]
end
