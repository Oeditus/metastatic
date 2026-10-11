defmodule Metastatic.Adapters.Agda.ToMeta do
  @moduledoc """
  Transform Agda AST (M1) to MetaAST (M2).

  Implements the abstraction function α_Agda that lifts Agda-specific
  AST structures to the meta-level representation.

  ## 3-Tuple Format

  All MetaAST nodes use the uniform 3-tuple structure:
  `{type_atom, keyword_meta, children_or_value}`
  """

  @doc """
  Transform Agda AST to MetaAST.

  Returns `{:ok, meta_ast, metadata}` on success or `{:error, reason}` on failure.
  """
  @spec transform(term()) :: {:ok, term(), map()} | {:error, String.t()}

  # M2.1 Core Layer - Literals

  def transform(%{"type" => "literal", "value" => value} = node) do
    {:ok, ast, meta} = transform_literal(value)
    {:ok, add_location(ast, node), meta}
  end

  # M2.1 Core Layer - Variables

  def transform(%{"type" => "var", "name" => name} = node) do
    scope = if constructor_name?(name), do: :constructor, else: :local
    {:ok, add_location({:variable, [scope: scope], name}, node), %{}}
  end

  # M2.1 Core Layer - Infix Binary Operations

  def transform(%{"type" => "infix", "operator" => op, "left" => left, "right" => right} = node) do
    with {:ok, left_meta, _} <- transform(left),
         {:ok, right_meta, _} <- transform(right) do
      {category, op_atom} = classify_operator(op)

      {:ok,
       add_location(
         {:binary_op, [category: category, operator: op_atom], [left_meta, right_meta]},
         node
       ), %{operator: op}}
    end
  end

  # M2.1 Core Layer - Application / Function Calls

  def transform(%{"type" => "app", "function" => func, "argument" => arg} = node) do
    with {:ok, func_meta, _} <- transform(func),
         {:ok, arg_meta, _} <- transform(arg) do
      name = extract_name(func_meta)

      {:ok,
       add_location(
         {:function_call, [name: name], [arg_meta]},
         node
       ), %{}}
    end
  end

  def transform(%{"type" => "raw_app", "elements" => [first | rest]} = node) do
    with {:ok, first_meta, _} <- transform(first),
         {:ok, rest_meta} <- transform_list(rest) do
      name = extract_name(first_meta)

      {:ok,
       add_location(
         {:function_call, [name: name], rest_meta},
         node
       ), %{}}
    end
  end

  # M2.1 Core Layer - Lambdas

  def transform(%{"type" => "lambda", "parameters" => params, "body" => body} = node) do
    param_names =
      Enum.map(params, fn
        %{"name" => name} -> name
        %{"text" => text} -> text
        name when is_binary(name) -> name
        _ -> "_"
      end)

    with {:ok, body_meta, _} <- transform(body) do
      {:ok,
       add_location(
         {:lambda, [params: param_names], [body_meta]},
         node
       ), %{}}
    end
  end

  # M2.1 Core Layer - Let bindings

  def transform(%{"type" => "let", "declarations" => decls} = node) do
    with {:ok, decls_meta} <- transform_list(decls) do
      body_meta =
        case Map.get(node, "body") do
          nil ->
            []

          %{} = b ->
            case transform(b) do
              {:ok, m, _} -> [m]
              _ -> []
            end

          _ ->
            []
        end

      {:ok,
       add_location(
         {:block, [construct: :let], decls_meta ++ body_meta},
         node
       ), %{}}
    end
  end

  # Types - Arrow Function Types (A -> B)

  def transform(%{"type" => "arrow", "from" => from, "to" => to} = node) do
    with {:ok, from_meta, _} <- transform(from),
         {:ok, to_meta, _} <- transform(to) do
      {:ok,
       add_location(
         {:type_annotation, [kind: :arrow], [from_meta, to_meta]},
         node
       ), %{}}
    end
  end

  # Types - Pi Types (Dependent Function Types)

  def transform(%{"type" => "pi", "telescope" => tel, "target" => target} = node) do
    with {:ok, target_meta, _} <- transform(target) do
      tel_texts = Enum.map(tel, fn t -> Map.get(t, "text", inspect(t)) end)

      {:ok,
       add_location(
         {:language_specific, [construct: :pi_type, telescope: tel_texts, language: :agda],
          [target_meta]},
         node
       ), %{}}
    end
  end

  # M2.2 Extended Layer - Declarations & Structural Elements

  def transform(%{"type" => "type_sig", "name" => name, "signature" => sig} = node) do
    with {:ok, sig_meta, _} <- transform(sig) do
      {:ok,
       add_location(
         {:type_def, [name: name, kind: :signature], [sig_meta]},
         node
       ), %{}}
    end
  end

  def transform(%{"type" => "field_sig", "name" => name, "signature" => sig} = node) do
    with {:ok, sig_meta, _} <- transform(sig) do
      {:ok,
       add_location(
         {:type_def, [name: name, kind: :field_signature], [sig_meta]},
         node
       ), %{}}
    end
  end

  def transform(%{"type" => "fun_clause", "lhs" => lhs, "rhs" => rhs} = node) do
    {name, params} = extract_lhs(lhs)

    with {:ok, rhs_meta} <- transform_rhs(rhs) do
      {:ok,
       add_location(
         {:function_def, [name: name, params: params], [rhs_meta]},
         node
       ), %{}}
    end
  end

  def transform(
        %{"type" => "data", "name" => name, "typeExpr" => type_expr, "constructors" => ctors} =
          node
      ) do
    with {:ok, type_meta, _} <- transform(type_expr),
         {:ok, ctors_meta} <- transform_list(ctors) do
      {:ok,
       add_location(
         {:type_def, [name: name, kind: :data], [type_meta | ctors_meta]},
         node
       ), %{}}
    end
  end

  def transform(
        %{"type" => "record", "name" => name, "typeExpr" => type_expr, "fields" => fields} = node
      ) do
    with {:ok, type_meta, _} <- transform(type_expr),
         {:ok, fields_meta} <- transform_list(fields) do
      {:ok,
       add_location(
         {:type_def, [name: name, kind: :record], [type_meta | fields_meta]},
         node
       ), %{}}
    end
  end

  def transform(%{"type" => "module", "declarations" => decls} = node) do
    with {:ok, decls_meta} <- transform_list(decls) do
      name = Map.get(node, "name")

      {:ok,
       add_location(
         {:container, [container_type: :module, name: name, language: :agda], decls_meta},
         node
       ), %{}}
    end
  end

  def transform(%{"type" => "open", "module" => mod_name} = node) do
    {:ok,
     add_location(
       {:import, [module: mod_name, open: true], []},
       node
     ), %{}}
  end

  def transform(%{"type" => "import", "module" => mod_name} = node) do
    is_open = Map.get(node, "open", false)

    {:ok,
     add_location(
       {:import, [module: mod_name, open: is_open], []},
       node
     ), %{}}
  end

  def transform(%{"type" => "postulate", "declarations" => decls} = node) do
    with {:ok, decls_meta} <- transform_list(decls) do
      {:ok,
       add_location(
         {:language_specific, [construct: :postulate, language: :agda], decls_meta},
         node
       ), %{}}
    end
  end

  def transform(%{"type" => "infix_decl", "fixity" => fixity, "names" => names} = node) do
    {:ok,
     add_location(
       {:language_specific, [construct: :fixity, fixity: fixity, names: names, language: :agda],
        []},
       node
     ), %{}}
  end

  def transform(%{"type" => "hole"} = node) do
    {:ok, add_location({:variable, [scope: :hole], "?"}, node), %{}}
  end

  def transform(%{"type" => "wildcard"} = node) do
    {:ok, add_location({:variable, [scope: :wildcard], "_"}, node), %{}}
  end

  def transform(%{"type" => "other_expr", "text" => text} = node) do
    {:ok,
     add_location(
       {:language_specific, [construct: :expr, text: text, language: :agda], []},
       node
     ), %{}}
  end

  def transform(%{"type" => "other_decl", "text" => text} = node) do
    {:ok,
     add_location(
       {:language_specific, [construct: :declaration, text: text, language: :agda], []},
       node
     ), %{}}
  end

  def transform(unsupported) do
    {:error, "Unsupported Agda AST node: #{inspect(unsupported)}"}
  end

  # Helpers

  defp transform_literal(%{"literalType" => "int", "value" => val}) do
    {:ok, {:literal, [subtype: :integer], val}, %{subtype: :integer}}
  end

  defp transform_literal(%{"literalType" => "float", "value" => val}) do
    {:ok, {:literal, [subtype: :float], val}, %{subtype: :float}}
  end

  defp transform_literal(%{"literalType" => "string", "value" => val}) do
    {:ok, {:literal, [subtype: :string], val}, %{subtype: :string}}
  end

  defp transform_literal(%{"literalType" => "char", "value" => val}) do
    {:ok, {:literal, [subtype: :char], val}, %{subtype: :char}}
  end

  defp transform_literal(%{"literalType" => "qname", "value" => val}) do
    {:ok, {:variable, [scope: :qualified], val}, %{}}
  end

  defp transform_literal(%{"literalType" => "meta"}) do
    {:ok, {:variable, [scope: :meta], "?"}, %{}}
  end

  defp transform_literal(other) do
    {:ok, {:literal, [subtype: :unknown], inspect(other)}, %{}}
  end

  defp transform_list(elements) when is_list(elements) do
    Enum.reduce_while(elements, {:ok, []}, fn elem, {:ok, acc} ->
      case transform(elem) do
        {:ok, meta_ast, _} -> {:cont, {:ok, [meta_ast | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, list} -> {:ok, Enum.reverse(list)}
      error -> error
    end
  end

  defp transform_rhs(%{"type" => "rhs", "expression" => expr}) do
    case transform(expr) do
      {:ok, meta, _} -> {:ok, meta}
      error -> error
    end
  end

  defp transform_rhs(%{"type" => "absurd_rhs"}) do
    {:ok, {:literal, [subtype: :absurd], "()"}}
  end

  defp transform_rhs(_) do
    {:ok, {:literal, [subtype: :unknown], nil}}
  end

  defp extract_lhs(%{"type" => "var_pat", "name" => name}), do: {name, []}

  defp extract_lhs(%{"type" => "infix_pat", "operator" => op, "left" => left, "right" => right}) do
    left_name = extract_pat_name(left)
    right_name = extract_pat_name(right)
    {op, [left_name, right_name]}
  end

  defp extract_lhs(%{"type" => "app_pat", "elements" => [head | rest]}) do
    name = extract_pat_name(head)
    params = Enum.map(rest, &extract_pat_name/1)
    {name, params}
  end

  defp extract_lhs(other) do
    {"_", [inspect(other)]}
  end

  defp extract_pat_name(%{"type" => "var_pat", "name" => name}), do: name
  defp extract_pat_name(%{"type" => "lit_pat", "value" => %{"value" => val}}), do: to_string(val)
  defp extract_pat_name(%{"type" => "wildcard"}), do: "_"
  defp extract_pat_name(other), do: inspect(other)

  defp extract_name({:variable, _, name}), do: name
  defp extract_name({:function_call, meta, _}), do: Keyword.get(meta, :name, "call")
  defp extract_name(_), do: "call"

  defp constructor_name?(name) when is_binary(name) do
    case String.first(name) do
      nil -> false
      c -> c >= "A" and c <= "Z"
    end
  end

  defp classify_operator(op) when is_binary(op) do
    op_atom = String.to_atom(op)

    case op do
      o when o in ["+", "-", "*", "/", "%", "mod", "div"] ->
        {:arithmetic, op_atom}

      o when o in ["==", "===", "!=", "=/=", "<", ">", "<=", ">=", "≤", "≥", "≡"] ->
        {:comparison, op_atom}

      o when o in ["and", "or", "not", "&&", "||", "∧", "∨"] ->
        {:boolean, op_atom}

      _ ->
        {:custom, op_atom}
    end
  end

  defp add_location({tag, meta, children} = _ast, %{
         "location" => %{"startLine" => sl, "startCol" => sc, "endLine" => el, "endCol" => ec}
       })
       when is_list(meta) and not is_nil(sl) and not is_nil(sc) do
    loc_meta = [line: sl, col: sc, end_line: el, end_col: ec]
    {tag, Keyword.merge(meta, loc_meta), children}
  end

  defp add_location(ast, _), do: ast
end
